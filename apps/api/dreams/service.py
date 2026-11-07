from __future__ import annotations

import asyncio
import json
import logging
import re
import time
import unicodedata
from collections.abc import AsyncIterator

import httpx

from ai_explainer import (
    _PROVIDER_RETRY_ATTEMPTS,
    _PROVIDER_RETRY_BASE_SECONDS,
    _read_limited_json_response,
    _retry_provider_status,
    AiConfigurationError,
    AiProviderError,
    get_provider_config,
    reserve_daily_budget,
)
from dreams.lore import source_excerpts, skill_profile
from verified_sources import adjacent_sources
from dreams.models import InterpretRequest, InterpretResponse, QuestionOut, QuestionsResponse, SourceOut
from dreams.prompts import INTERPRET_JSON, QUESTIONS, SYSTEM
from reading_agent import stream_completion

logger = logging.getLogger("fortune.dreams")


_REQUIRED_IDS = ("finished", "agency", "fear_of")
# 触发转介的自伤信号：只依据梦的明确叙述，不做推断
_REFERRAL_PATTERNS = ("自杀", "轻生", "不想活", "伤害自己", "伤自己", "自残", "自殺", "輕生", "不想活", "傷害自己", "自殘")


# 零宽字符按码点显式构造（与 tcm/service.py 同款）：源码保持纯 ASCII，
# 防格式化器剥掉字面量零宽字符后正则悄悄失效。
_INVISIBLE_CHARS = re.compile(r"[\s" + "".join(map(chr, (0x200B, 0x200C, 0x200D, 0x2060, 0xFEFF))) + "]+")


def _normalize_signal_text(text: str) -> str:
    """信号匹配前规范化：NFKC 折叠全角/兼容字符，剥掉空白与零宽字符——
    否则「自 残」「自<零宽>残」这类拆字写法能绕开子串匹配（2026-09-26 门0 实证）。"""
    return _INVISIBLE_CHARS.sub("", unicodedata.normalize("NFKC", text))


def is_referral(dream: str, answers: list | None = None) -> bool:
    # 追问回答与梦正文同等参与自伤信号检查：只查正文时，
    # "梦是朋友的、追问答'怕他轻生'"即可绕过转介直进 LLM。
    text = _normalize_signal_text(compose_query(dream, answers or []))
    return any(_normalize_signal_text(pattern) in text for pattern in _REFERRAL_PATTERNS)


def compose_query(dream: str, answers: list) -> str:
    extra = [f"{item.question}：{item.answer}" for item in answers if item.answer]
    return "\n".join([dream, *extra]) if extra else dream


def heuristic_questions(dream: str) -> list[QuestionOut]:
    snippet = re.sub(r"\s+", "", dream)[:16] or "这场梦"
    return [
        QuestionOut(id="finished", label=f"「{snippet}」做到结尾了吗？"),
        QuestionOut(id="agency", label="走进这个场面，是你自己要去，还是被卷进去的？"),
        QuestionOut(id="fear_of", label="最怕的是哪一幕，或哪个人？"),
    ]


def _parse_questions(text: str) -> list[QuestionOut]:
    start = text.find("{")
    end = text.rfind("}")
    if start < 0 or end <= start:
        raise ValueError("no json")
    payload = json.loads(text[start:end + 1])
    raw = payload.get("questions")
    if not isinstance(raw, list):
        raise ValueError("no questions")
    by_id = {}
    for item in raw:
        if not isinstance(item, dict):
            continue
        qid = str(item.get("id") or "")
        label = str(item.get("label") or "").strip()[:80]
        if qid in _REQUIRED_IDS and label:
            by_id[qid] = QuestionOut(id=qid, label=label)
    return [by_id[qid] for qid in _REQUIRED_IDS if qid in by_id]


def _provider():
    try:
        return get_provider_config()
    except AiConfigurationError:
        return None


async def _chat(system: str, user: str) -> str:
    config = _provider()
    if config is None:
        raise AiConfigurationError("AI provider is not configured")
    # 解梦 prompt 含全量 skill 口径（4 万+字符），生成耗时显著高于常规解读，
    # 固定用长超时（50s < RequestGuard 的 62s AI 门，不冲突）；重试同样受
    # 墙钟约束，慢失败链不再顶到中间件门上被砍成 504。
    timeout_seconds = max(config.timeout_seconds, 50.0)
    timeout = httpx.Timeout(timeout_seconds, connect=min(3.0, timeout_seconds))
    async with httpx.AsyncClient(timeout=timeout, follow_redirects=False, trust_env=False) as client:
        started = time.monotonic()
        response = None
        for attempt in range(_PROVIDER_RETRY_ATTEMPTS):
            remaining = 56.0 - (time.monotonic() - started)
            if remaining <= 0:
                raise AiProviderError("provider deadline exceeded")
            response = await asyncio.wait_for(client.post(
                f"{config.base_url}/chat/completions",
                headers={
                    "authorization": f"Bearer {config.api_key}",
                    "content-type": "application/json",
                    "accept": "application/json",
                },
                json={
                    "model": config.model,
                    "max_tokens": 4096,
                    "messages": [
                        {"role": "system", "content": system},
                        {"role": "user", "content": user},
                    ],
                },
                timeout=httpx.Timeout(min(timeout_seconds, remaining), connect=min(3.0, remaining)),
            ), timeout=remaining)
            if _retry_provider_status(response.status_code) and attempt < _PROVIDER_RETRY_ATTEMPTS - 1:
                if time.monotonic() - started > 56.0:
                    logger.warning("dream provider retry skipped: wall clock exhausted attempt=%s", attempt + 1)
                    break
                logger.warning("dream provider retryable failure status=%s attempt=%s",
                               response.status_code, attempt + 1)
                await asyncio.sleep(min(_PROVIDER_RETRY_BASE_SECONDS * (attempt + 1), max(0, 56.0 - (time.monotonic() - started))))
                continue
            break
        try:
            response.raise_for_status()
            # provider 响应体与 explain 通道同上限（64KB）后再解析，
            # 防止半信任 provider 的超大响应把 worker 内存顶爆。
            payload = await _read_limited_json_response(response)
            text = str(payload["choices"][0]["message"]["content"] or "").strip()
        except Exception as error:
            raise AiProviderError("dream essay failed") from error
        return text


async def generate_questions(dream: str) -> QuestionsResponse:
    if is_referral(dream):
        return QuestionsResponse(questions=[
            QuestionOut(id="finished", label="醒来后，你现在安全吗？"),
            QuestionOut(id="agency", label="这些伤害自己的念头现在还在吗？"),
            QuestionOut(id="fear_of", label="现在能联系一位信任的人陪着你吗？"),
        ])
    config = _provider()
    if config is None:
        return QuestionsResponse(questions=heuristic_questions(dream))
    # 预算扣在 try 外：AiBudgetExceeded 必须传播成 429，不得被兜底逻辑吞掉。
    reserve_daily_budget(config.daily_limit)
    try:
        questions = _parse_questions(await _chat(QUESTIONS, dream[:800]))
        if len(questions) < 3:
            raise ValueError("incomplete")
        return QuestionsResponse(questions=questions)
    except Exception as error:
        logger.warning("dream questions fallback error_type=%s", type(error).__name__)
        return QuestionsResponse(questions=heuristic_questions(dream))


def _referral_result(dream: str) -> InterpretResponse:
    return InterpretResponse(
        referral="这场梦提到了伤害自己。梦不等于现实意图，但如果这些念头在醒来后还在，"
                 "建议找信得过的人或专业的心理援助聊一聊——这一步比任何解梦都重要。",
    )


_THINK_BLOCK = re.compile(r"<think>(.*?)(?:</think>|$)", re.S | re.I)


def _split_think(text: str) -> tuple[str, str]:
    """把模型原始输出拆成 (thinking, 正文)：与流式通道的 think/delta 分流同语义。
    无闭合 <think>（生成截断形态）整体归入 thinking、正文为空——由调用方显式报错，
    不再把思考混进 essay 静默返回（E-R3）。"""
    thinking = "\n".join(m.group(1).strip() for m in _THINK_BLOCK.finditer(text))
    body = _THINK_BLOCK.sub("", text).strip()
    return thinking.strip(), body


def _parse_interpret(text: str) -> InterpretResponse:
    thinking, text = _split_think(text)
    stripped = text.strip()
    if stripped.startswith("```json") or stripped.startswith("```\n"):
        stripped = stripped.split("\n", 1)[-1].strip() if "\n" in stripped else stripped[7:].strip()
        if stripped.endswith("```"):
            stripped = stripped[:-3].strip()
    # Structured output must parse completely. Never show truncated JSON as prose
    # or trim ordinary prose just because it contains braces or the word sources.
    if stripped.startswith("{") or stripped.startswith("["):
        try:
            payload = json.loads(stripped)
            if not isinstance(payload, dict) or not isinstance(payload.get("essay"), str):
                raise ValueError("invalid essay")
            essay = payload["essay"].strip()
        except (ValueError, TypeError) as error:
            raise AiProviderError("malformed dream response") from error
    else:
        essay = stripped
        for prefix in ("解梦正文：", "解梦正文:", "正文：", "正文:"):
            if essay.startswith(prefix):
                essay = essay[len(prefix):].strip()
                break
    if not essay:
        raise AiProviderError("empty essay")
    essay = essay[:3600]
    # Metadata alone is not evidence: require the cited quote in the shown essay.
    return InterpretResponse(essay=essay, sources=extract_sources(essay), thinking=thinking[:2000])


def extract_sources(text: str) -> list[SourceOut]:
    return [SourceOut(work=f"《{title}》", quote=quote, channel="字面")
            for title, quote in adjacent_sources(text, source_excerpts())]


async def interpret_dream_request(request: InterpretRequest) -> InterpretResponse:
    if is_referral(request.dream, request.answers):
        return _referral_result(request.dream)

    config = _provider()
    if config is None:
        raise AiConfigurationError("AI provider is not configured")
    # 转介路径不消耗 LLM，预算只对真实生成扣（try 外扣，超限抛 429）。
    reserve_daily_budget(config.daily_limit)
    profile = skill_profile()
    system = f"{SYSTEM}\n\n{profile}" if profile else SYSTEM
    lines = [f"梦：{request.dream[:2000]}"]
    extra = [f"{item.question}：{item.answer}" for item in request.answers if item.answer]
    if extra:
        lines.append("补充：\n" + "\n".join(extra))
    lines.append(INTERPRET_JSON)

    try:
        raw = await _chat(system, "\n".join(lines))
    except AiConfigurationError:
        raise
    except AiProviderError:
        raise
    except Exception as error:
        raise AiProviderError("dream essay failed") from error
    parsed = _parse_interpret(raw)
    return parsed


# 流式版：不再要求 JSON 回包，直接输出解梦正文；引用来源在收尾时后端提取。
_INTERPRET_STREAM = (
    "直接输出解梦正文（Markdown 分节书写），不要 JSON、不要代码块。"
    "只能引用实际注入的学习笔记标题和逐字原句，格式为《笔记标题》：“原句”。不可称为荣格或弗洛伊德的原话，不能编造书名或引文，没有合适引文就不引用。"
    "结尾固定两节：「## 可以先做」（2-3 条具体、可执行的动作）与「## 注意」（1 条单句提醒）。"
)


async def stream_interpret_events(request: InterpretRequest) -> AsyncIterator[dict]:
    """流式解梦：产出 {"type":"delta","text"} 与 {"type":"done","sources":[…]} 事件。"""
    if is_referral(request.dream, request.answers):
        yield {"type": "delta", "text": _referral_result(request.dream).referral}
        yield {"type": "done", "sources": []}
        return
    config = _provider()
    if config is None:
        raise AiConfigurationError("AI provider is not configured")
    reserve_daily_budget(config.daily_limit)
    profile = skill_profile()
    system = f"{SYSTEM}\n\n{profile}" if profile else SYSTEM
    lines = [f"梦：{request.dream[:2000]}"]
    extra = [f"{item.question}：{item.answer}" for item in request.answers if item.answer]
    if extra:
        lines.append("补充：\n" + "\n".join(extra))
    lines.append(_INTERPRET_STREAM)

    chunks: list[str] = []
    think_chunks: list[str] = []
    try:
        # stream_completion 产出 (kind, segment) 二元组：思考链转播给前端折叠条，
        # 只有正文 delta 进解梦文本与收尾全文。
        async for kind, text in stream_completion(system=system, user="\n".join(lines), config=config):
            if kind == "think":
                think_chunks.append(text)
                yield {"type": "think", "text": text}
                continue
            chunks.append(text)
            yield {"type": "delta", "text": text}
    except AiConfigurationError:
        raise
    except AiProviderError:
        raise
    except Exception as error:
        raise AiProviderError("dream essay failed") from error
    essay = "".join(chunks).strip()
    if not essay:
        raise AiProviderError("empty essay")
    yield {"type": "done", "sources": [item.model_dump(mode="json") for item in extract_sources(essay)]}
