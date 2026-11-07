from __future__ import annotations

import asyncio
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
from reading_agent import stream_completion
from tcm.lore import source_excerpts
from verified_sources import adjacent_sources
from tcm.models import ConsultRequest, ConsultResponse, SourceOut
from tcm.prompts import STREAM, system_prompt

logger = logging.getLogger("fortune.tcm")


# 急性危重信号：命中即确定性转介（不打 LLM、不出方），对齐解梦自伤转介的产品口径。
# 同义词族收全口语面（run-3 实测：心肌梗塞/脑梗/脑卒中/吐血/抽搐/喘不上气 全漏）；
# 匹配前先规范化（is_emergency），防拆字/零宽/全角绕闸。
_EMERGENCY_PATTERNS = (
    "中風", "腦梗", "腦卒中", "腦出血", "呼吸困難", "意識不清", "昏厥",
    "半身不遂", "偏瘫", "偏癱", "口眼歪斜", "口角歪斜", "一侧无力", "一側無力", "说话不清", "說話不清",
    "药物过量", "藥物過量", "服药过量", "服藥過量", "吞药", "吞藥", "吃了一瓶", "吃了整瓶", "吃了一整瓶", "吃了一把", "中毒",
    "心梗", "心肌梗死", "心肌梗塞", "心绞痛",
    "中风", "脑梗", "脑梗死", "脑梗塞", "脑卒中", "脑出血", "脑溢血",
    "昏迷", "昏厥", "晕厥", "休克",
    "大出血", "呕血", "咯血", "吐血",
    "呼吸困难", "喘不上气", "喘不过气",
    "意识不清", "意识模糊", "抽搐", "高热惊厥", "高烧惊厥",
    "剧烈胸痛", "胸口剧痛",
)

# 免责框固定文案（与 skill 口径一致），流式/非流式收尾强校验缺失即补齐。
DISCLAIMER = (
    "⚠️ 本内容仅用于中医学习与学术研究，不构成医疗诊断、处方或个体化治疗建议。"
    "身体不适请咨询执业中医师辨证开方；急性危重症请立即送医。"
)

_REFERRAL_TEXT = (
    "你描述的情况可能需要紧急医疗帮助。请立即拨打当地急救电话（中国大陆为 120），"
    "不要独自驾车或等待线上问诊。疑似药物过量时不要自行催吐或再服药，保留药品包装交给急救人员；"
    "疑似卒中时记录症状开始时间，尽快由急救人员评估。"
)

_ESSAY_CAP = 3600


# 零宽字符（ZWSP/ZWNJ/ZWJ/WJ/BOM）显式按码点构造：源码保持纯 ASCII，
# 防格式化器把字面量零宽字符剥掉后正则悄悄失效。
_INVISIBLE_CHARS = re.compile(r"[\s" + "".join(map(chr, (0x200B, 0x200C, 0x200D, 0x2060, 0xFEFF))) + "]+")


def _normalize_signal_text(text: str) -> str:
    """信号匹配前规范化：NFKC 折叠全角/兼容字符，剥掉空白与零宽字符，
    否则「心肌 梗塞」「脑<零宽>梗」这类拆字写法能绕开子串匹配。"""
    return _INVISIBLE_CHARS.sub("", unicodedata.normalize("NFKC", text))


# Additional exposure/FAST colloquialisms: match an event, not merely a product
# name or a number. This is conservative routing, never a safe-dose calculator.
_POISON = r"(?:农药|農藥|杀虫剂|殺蟲劑|除草剂|除草劑|百草枯|敌敌畏|敵敵畏|老鼠药|老鼠藥|鼠药|鼠藥|洁厕剂|潔廁劑|漂白水|消毒液)"
_INGEST = r"(?:喝|吞|吃|误服|誤服|误饮|誤飲|误食|誤食)"
_MEDICINE = r"(?:安眠药|安眠藥|止痛药|止痛藥|药|藥)"


def is_emergency(question: str) -> bool:
    normalized = _normalize_signal_text(question)
    if any(_normalize_signal_text(pattern) in normalized for pattern in _EMERGENCY_PATTERNS):
        return True
    if re.search(r"(?:药|藥|安眠|止痛).{0,8}(?:过量|過量|吃多|多吃|超量)|(?:吃多|多吃|超量|过量|過量).{0,8}(?:药|藥|安眠|止痛)|(?:吃|吞|服).{0,8}(?:几十|幾十|十几|十幾|一把|整瓶).{0,4}(?:药|藥|片|颗|顆)", normalized):
        return True
    if re.search(_INGEST + r".{0,8}" + _POISON + r"|" + _POISON + r".{0,8}" + _INGEST, normalized):
        return True
    # Numeral ingestion: word-boundaries are unreliable for Chinese. The unit
    # and medicine context prevent e.g. a pack containing twenty tablets from
    # being mistaken for taking twenty tablets.
    for match in re.finditer(r"(?:吞|吃|服)(?:下|了|用|药|藥|下了)*([0-9]{1,4})(?:片|粒|颗|顆)(.{0,10})", normalized):
        if int(match.group(1)) >= 10 and re.search(_MEDICINE, normalized[max(0, match.start() - 8):match.end()]):
            return True
    # Sudden FAST-type descriptions, including informal arm/face descriptions.
    fast = r"(?:嘴歪|嘴巴歪|臉歪|脸歪|胳膊抬不起来|胳膊抬不起來|手臂抬不起来|手臂抬不起來|说不清话|說不清話|讲不清话|講不清話)"
    return bool(re.search(r"(?:突然|忽然|刚刚|剛剛).{0,18}" + fast, normalized))


def _emergency_result() -> ConsultResponse:
    return ConsultResponse(referral=_REFERRAL_TEXT, essay="", sources=[])


def extract_sources(text: str) -> list[SourceOut]:
    """Only exact quotations adjacent to a verified study-note title become cards."""
    return [SourceOut(work=f"《{title}》", quote=quote)
            for title, quote in adjacent_sources(text, source_excerpts())]


def _compose_user(question: str) -> str:
    return f"问诊：{question[:2000]}"


def _enforce_disclaimer(essay: str) -> str:
    """免责框缺失即补齐——免责是产品底线，不依赖模型自觉。"""
    if DISCLAIMER in essay:
        return essay
    return f"{essay.rstrip()}\n\n{DISCLAIMER}"


def _fit_essay(raw: str) -> str:
    """先裁后补：正文裁进「_ESSAY_CAP − 免责框」的预算位，免责框强制落在结尾。

    顺序是产品底线（保证用户永远看到免责）：此前 enforce 在 [:_ESSAY_CAP] 截断
    之前跑，长文会把结尾的免责框切掉。模型自带的结尾免责先剥掉再补，避免双份。
    """
    body = raw.strip()
    head = body[: -len(DISCLAIMER)].rstrip() if body.endswith(DISCLAIMER) else body.rstrip()
    room = _ESSAY_CAP - len(DISCLAIMER) - 2
    return f"{head[:room].rstrip()}\n\n{DISCLAIMER}"


def _provider():
    try:
        return get_provider_config()
    except AiConfigurationError:
        return None


async def _chat(system: str, user: str) -> str:
    config = _provider()
    if config is None:
        raise AiConfigurationError("AI provider is not configured")
    # Educational response uses a bounded provider timeout,
    # 固定用长超时（50s < RequestGuard 的 62s AI 门，不冲突）。
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
                    logger.warning("tcm provider retry skipped: wall clock exhausted attempt=%s", attempt + 1)
                    break
                logger.warning("tcm provider retryable failure status=%s attempt=%s",
                               response.status_code, attempt + 1)
                await asyncio.sleep(min(_PROVIDER_RETRY_BASE_SECONDS * (attempt + 1), max(0, 56.0 - (time.monotonic() - started))))
                continue
            break
        try:
            response.raise_for_status()
            # provider 响应体与 explain 通道同上限（64KB）后再解析。
            payload = await _read_limited_json_response(response)
            text = str(payload["choices"][0]["message"]["content"] or "").strip()
        except Exception as error:
            raise AiProviderError("tcm consult failed") from error
        return text


async def consult_request(request: ConsultRequest) -> ConsultResponse:
    if is_emergency(request.question):
        return _emergency_result()

    config = _provider()
    if config is None:
        raise AiConfigurationError("AI provider is not configured")
    # 转介路径不消耗 LLM，预算只对真实生成扣（try 外扣，超限抛 429）。
    reserve_daily_budget(config.daily_limit)
    try:
        raw = await _chat(system_prompt(), _compose_user(request.question))
    except (AiConfigurationError, AiProviderError):
        raise
    except Exception as error:
        raise AiProviderError("tcm consult failed") from error
    if not raw.strip():
        raise AiProviderError("empty essay")
    essay = _fit_essay(raw)
    return ConsultResponse(essay=essay, sources=extract_sources(essay))


async def stream_consult_events(request: ConsultRequest) -> AsyncIterator[dict]:
    """流式问诊：产出 {"type":"delta","text"} 与 {"type":"done","sources":[…]} 事件。"""
    if is_emergency(request.question):
        yield {"type": "delta", "text": _REFERRAL_TEXT}
        yield {"type": "done", "sources": []}
        return
    config = _provider()
    if config is None:
        raise AiConfigurationError("AI provider is not configured")
    reserve_daily_budget(config.daily_limit)

    chunks: list[str] = []
    think_chunks: list[str] = []
    # 与非流式「先裁后补」同口径：正文裁进预算位，免责框强制结尾。
    relayed = 0
    essay_budget = _ESSAY_CAP - len(DISCLAIMER) - 2
    try:
        # stream_completion 产出 (kind, segment) 二元组：思考链转播给前端折叠条，
        # 只有正文 delta 进问诊文本与收尾全文。
        async for kind, text in stream_completion(system=system_prompt(), user=_compose_user(request.question), config=config):
            if kind == "think":
                think_chunks.append(text)
                yield {"type": "think", "text": text}
                continue
            text = text[:max(0, essay_budget - relayed)]
            if not text:
                continue
            relayed += len(text)
            chunks.append(text)
            yield {"type": "delta", "text": text}
    except AiConfigurationError:
        raise
    except AiProviderError:
        raise
    except Exception as error:
        raise AiProviderError("tcm consult failed") from error
    essay = "".join(chunks).strip()
    if not essay:
        raise AiProviderError("empty essay")
    # 免责框缺失补齐：补的这段跟随收尾一起流出，保证用户永远看到免责。
    if DISCLAIMER not in essay:
        tail = f"\n\n{DISCLAIMER}"
        chunks.append(tail)
        yield {"type": "delta", "text": tail}
    yield {"type": "done", "sources": [item.model_dump(mode="json") for item in extract_sources("".join(chunks))]}
