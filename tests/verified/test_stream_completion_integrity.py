import asyncio
import json
import sys
from pathlib import Path
from types import SimpleNamespace

import httpx
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'apps' / 'api'))
import reading_agent
from ai_explainer import AiProviderError


def run_stream(monkeypatch, frames):
    content = '\n\n'.join('data: ' + (json.dumps(f) if isinstance(f, dict) else f) for f in frames)
    transport = httpx.MockTransport(lambda request: httpx.Response(200, text=content))
    real_client = httpx.AsyncClient
    monkeypatch.setattr(reading_agent.httpx, 'AsyncClient', lambda **kw: real_client(transport=transport, **kw))
    config = SimpleNamespace(model='test', api_key='not-secret', timeout_seconds=1, base_url='https://example.invalid')

    async def collect():
        return [item async for item in reading_agent.stream_completion(system='test', user='test', config=config)]
    return asyncio.run(collect())


def frame(text='', reason=None):
    return {'choices': [{'delta': {'content': text}, 'finish_reason': reason}]}


def test_complete_stream(monkeypatch):
    assert run_stream(monkeypatch, [frame('完整', 'stop'), '[DONE]']) == [('delta', '完整')]


@pytest.mark.parametrize('frames', [
    [frame('部分', 'length'), '[DONE]'],
    [frame('部分', 'stop')],
    [frame('部分'), '{bad json', '[DONE]'],
    [frame('', 'content_filter'), '[DONE]'],
    [frame(['invalid']), '[DONE]'],
    [frame([]), '[DONE]'],
    [frame(False), '[DONE]'],
    [{'choices': [{'delta': [], 'finish_reason': 'stop'}]}, '[DONE]'],
    [frame('部分'), {'error': {'message': 'generation failed'}}, '[DONE]'],
    [frame('部分', 'length'), frame('', 'stop'), '[DONE]'],
    [frame('部分'), {'choices': []}, '[DONE]'],
])
def test_incomplete_stream_is_not_success(monkeypatch, frames):
    with pytest.raises(AiProviderError):
        run_stream(monkeypatch, frames)


def test_usage_only_frame_remains_supported(monkeypatch):
    assert run_stream(monkeypatch, [frame('完整', 'stop'), {'choices': [], 'usage': {'total_tokens': 5}}, '[DONE]']) == [('delta', '完整')]
