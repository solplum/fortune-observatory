import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "apps" / "api"))

from lore import lore_for_bundle_types
from reading_agent import build_reading_system, corpus_for_bundle_types


def test_bazi_nonstream_only_loads_bazi_canon():
    text = lore_for_bundle_types({'bazi.chart'})
    assert '【八字解读框架】' in text
    assert '八字·典籍摘要' in text
    assert '紫微斗数·典籍断语' not in text
    assert '【紫微斗数解读框架】' not in text


def test_qizheng_nonstream_does_not_load_other_canon():
    text = lore_for_bundle_types({'qizheng.chart'})
    assert '【七政四余解读框架】' in text
    assert '八字·典籍摘要' not in text
    assert '紫微斗数·典籍断语' not in text


def test_mixed_nonstream_keeps_both_frameworks():
    text = lore_for_bundle_types({'bazi.chart', 'ziwei.chart'})
    assert '【八字解读框架】' in text
    assert '【紫微斗数解读框架】' in text
    assert '八字·典籍摘要' in text
    assert '紫微斗数·典籍断语' in text


def test_qizheng_stream_has_own_preamble_and_corpus():
    text = build_reading_system({'qizheng.chart'})
    assert '七政四余传统文化解读助手' in text
    assert '【七政四余解读框架】' in text
    assert '语料：ziwei-doushu/' not in text
    assert '语料：bazi/' not in text
    assert '资深紫微斗数命理解读师' not in text


def test_three_system_stream_keeps_systems_separate():
    text = build_reading_system({'qizheng.chart', 'ziwei.chart', 'bazi.chart'})
    assert '独立成节' in text
    assert '【七政四余解读框架】' in text
    assert '语料：ziwei-doushu/' in text
    assert '语料：bazi/' in text


def test_unknown_bundle_does_not_inject_unrelated_canon():
    assert corpus_for_bundle_types({'unknown'}) == ''
    text = lore_for_bundle_types({'unknown'})
    assert '典籍摘要' not in text
    assert '典籍断语' not in text
