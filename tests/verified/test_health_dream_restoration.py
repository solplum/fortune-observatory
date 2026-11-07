"""Restoration safety regressions, real corpus and mocked providers only."""
import asyncio
import json
from types import SimpleNamespace
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "apps" / "api"))

import pytest
from ai_explainer import AiProviderError
from dreams import service as dream
from dreams.lore import source_excerpts as dream_excerpts
from dreams.models import ComplexAnswer, InterpretRequest
from tcm import service as tcm
from tcm.lore import skill_profile, source_excerpts
from tcm.models import ConsultRequest
from tcm.prompts import system_prompt


def forbidden(*args, **kwargs):
    raise AssertionError("Emergency must not access provider or budget")


@pytest.mark.parametrize('text', [
    '媽媽突然半身不遂', '突然偏癱怎麼辦', '口角歪斜說話不清',
    '我服藥過量了', '我吞了几十片安眠药', '吃了一整瓶药',
    '腦\u200b卒中', '心肌 梗塞',
    '我刚喝了农药怎么办', '我剛喝了農藥怎麼辦', '我吞了20片安眠药',
    '我吞了２０片安眠藥', '安眠药我吃了20片', '我吃了30粒止痛药', '我误服了杀虫剂',
    '突然一边胳膊抬不起来嘴歪了', '突然手臂抬不起來', '刚刚嘴歪了',
])
def test_triage_without_provider_or_budget(monkeypatch, text):
    monkeypatch.setattr(tcm, '_provider', forbidden)
    monkeypatch.setattr(tcm, 'reserve_daily_budget', forbidden)
    request = ConsultRequest(question=text)
    assert asyncio.run(tcm.consult_request(request)).referral
    async def collect():
        return [event async for event in tcm.stream_consult_events(request)]
    events = asyncio.run(collect())
    assert events[-1] == {'type': 'done', 'sources': []}


def test_online_allowlist_preserves_real_nonprescription_corpus():
    profile = skill_profile()
    assert len(source_excerpts()) == 2
    assert '阴阳、表里、虚实、寒热' in profile
    for unsafe in ('生附子', '剂量', '煎服', '一剂就好', '六经辨证诊断公式'):
        assert unsafe not in profile
    assert '禁止只给' not in system_prompt()


def test_tcm_exact_adjacent_attributed_sources():
    title, quote = next(iter(source_excerpts().items()))
    assert tcm.extract_sources(f'《{title}》：“{quote}”')
    assert not tcm.extract_sources(f'《伤寒论》：“{quote}”')
    assert not tcm.extract_sources(f'《{title}》：“虚构的医学原句不可引用”')
    assert not tcm.extract_sources(f'《{title}》只作为背景。另一段说：“{quote}”')


def test_dream_real_injected_excerpt_only():
    title, body = next(iter(dream_excerpts().items()))
    quote = '与弗洛伊德（Freud）把梦视为伪装后的愿望满足不同'
    assert quote in body
    assert dream.extract_sources(f'《{title}》：“{quote}”')
    assert not dream.extract_sources(f'《梦的解析》：“{quote}”')
    assert not dream.extract_sources(f'《{title}》：“完全不存在的伪造引用”')
    raw = json.dumps({'essay': '这是可能的解释。', 'sources': [{'work': title, 'quote': quote}]})
    assert dream._parse_interpret(raw).sources == []


@pytest.mark.parametrize('raw', ['{"essay":"半段', '{"essay":null}', '[]', '{"essay":"正常"} extra'])
def test_malformed_json_is_not_displayed(raw):
    with pytest.raises(AiProviderError):
        dream._parse_interpret(raw)


def test_plain_prose_not_corrupted():
    text = '正文里提到 sources：是梦中词语，{门}也是梦中图案。'
    assert dream._parse_interpret(text).essay == text


def test_followup_and_questions_crisis_no_provider(monkeypatch):
    monkeypatch.setattr(dream, '_provider', forbidden)
    monkeypatch.setattr(dream, 'reserve_daily_budget', forbidden)
    request = InterpretRequest(dream='我梦见走在路上', answers=[ComplexAnswer(id='fear_of', question='怕什么', answer='我想自殘')])
    assert asyncio.run(dream.interpret_dream_request(request)).referral
    assert len(asyncio.run(dream.generate_questions('梦见自己自殺')).questions) == 3
    async def collect():
        return [event async for event in dream.stream_interpret_events(request)]
    assert asyncio.run(collect())[-1]['sources'] == []


def test_oversized_stream_chunk_keeps_prefix(monkeypatch):
    monkeypatch.setattr(tcm, '_provider', lambda: SimpleNamespace(daily_limit=10))
    monkeypatch.setattr(tcm, 'reserve_daily_budget', lambda _: None)
    async def completion(**kwargs):
        yield 'delta', '中' * 10000
    monkeypatch.setattr(tcm, 'stream_completion', completion)
    async def collect():
        return [event async for event in tcm.stream_consult_events(ConsultRequest(question='请介绍八纲的概念'))]
    events = asyncio.run(collect())
    text = ''.join(event.get('text', '') for event in events)
    assert text.startswith('中' * 100)
    assert len(text) <= tcm._ESSAY_CAP
    assert text.endswith(tcm.DISCLAIMER)


@pytest.mark.parametrize('service', [tcm, dream])
def test_retry_timeout_uses_remaining_deadline(monkeypatch, service):
    import httpx
    config = SimpleNamespace(timeout_seconds=50, base_url='https://provider.invalid', api_key='test', model='test')
    monkeypatch.setattr(service, '_provider', lambda: config)
    clock = [0.0]
    monkeypatch.setattr(service.time, 'monotonic', lambda: clock[0])
    observed = []
    class Client:
        def __init__(self, **kwargs): pass
        async def __aenter__(self): return self
        async def __aexit__(self, *args): pass
        async def post(self, *args, **kwargs):
            observed.append(kwargs['timeout'].read)
            clock[0] += 50 if len(observed) == 1 else 1
            return httpx.Response(503 if len(observed) == 1 else 200,
                request=httpx.Request('POST', 'https://provider.invalid'),
                json={'choices': [{'message': {'content': '正文'}}]})
    async def sleep(delay): clock[0] += delay
    monkeypatch.setattr(service.httpx, 'AsyncClient', Client)
    monkeypatch.setattr(service.asyncio, 'sleep', sleep)
    assert asyncio.run(service._chat('system', 'user')) == '正文'
    assert observed[0] == 50
    assert 0 < observed[1] <= 6


@pytest.mark.parametrize('text', [
    '农药要怎样安全存放', '一盒20片安眠药要如何保管',
    '医生让我睡前服用1片药', '我吃了1片安眠药',
    '我喝了20毫升水', '平时锻炼时胳膊很累',
])
def test_emergency_exposure_rules_do_not_match_unrelated_quantities(text):
    assert not tcm.is_emergency(text)
