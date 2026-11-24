"""Regression checks for the cleaned Mingli 3-system corpus and traditional dream lore."""

from __future__ import annotations

import json
import sys
from pathlib import Path

API_DIR = Path(__file__).resolve().parents[2] / "apps" / "api"
SKILLS_DIR = Path(__file__).resolve().parents[2] / "skills"
if str(API_DIR) not in sys.path:
    sys.path.insert(0, str(API_DIR))

import dreams.lore as dream_lore  # noqa: E402
import dreams.service as dream_service  # noqa: E402
import lore as mingli_lore  # noqa: E402
import mingli_corpus  # noqa: E402
import reading_agent  # noqa: E402
from ai_explainer import AiFact  # noqa: E402


def test_no_fake_ziwei_classics_anywhere() -> None:
    forbidden = ("紫微化忌", "紫微星化忌", "企业高管", "逆袭", "有'不甘'二字推动", '有"不甘"二字推动')
    checked_files = [
        SKILLS_DIR / "ziwei-doushu" / "references" / "classics.md",
        SKILLS_DIR / "ziwei-doushu" / "references" / "patterns.md",
        API_DIR / "lore.py",
        API_DIR / "reading_agent.py",
        *sorted((SKILLS_DIR / "mingli-corpus").glob("*.jsonl")),
    ]
    for path in checked_files:
        content = path.read_text(encoding="utf-8")
        for term in forbidden:
            assert term not in content, f"Forbidden fake-classic term {term!r} found in {path}"


def test_mingli_corpus_qiongtong_120_coverage() -> None:
    stems = "甲乙丙丁戊己庚辛壬癸"
    branches = "子丑寅卯辰巳午未申酉戌亥"
    for s in stems:
        for b in branches:
            hits = mingli_corpus.retrieve_bazi(f"月柱甲{b} 日柱{s}巳", "用神 调候", limit=3)
            assert any(r["book"] == "穷通宝鉴" for r in hits), f"Missing Qiongtong for {s}{b}"


def test_mingli_corpus_retrieval_and_isolation() -> None:
    bazi_facts = [AiFact(id="bazi-1", text="八字四柱：年柱乙酉、月柱戊子、日柱辛巳、时柱己亥，偏财正印偏印")]
    zw_facts = [AiFact(id="ziwei-1", text="命宫干支己丑，太阴化忌，主星：太阳（不）、太阴（庙）；夫妻宫天同（庙）")]
    qz_facts = [AiFact(id="qizheng-1", text="七政昼夜盘：夜生，太阴入翼宿，命宫巳宫，恩星金星")]

    bazi_text = mingli_corpus.retrieve_for_facts({"bazi.chart"}, bazi_facts, "问感情")
    assert "穷通宝鉴" in bazi_text
    assert "张果星宗" not in bazi_text and "紫微斗数全书" not in bazi_text

    zw_text = mingli_corpus.retrieve_for_facts({"ziwei.chart"}, zw_facts, "问感情")
    assert "紫微斗数" in zw_text
    assert "穷通宝鉴" not in zw_text and "张果星宗" not in zw_text

    qz_text = mingli_corpus.retrieve_for_facts({"qizheng.chart"}, qz_facts, "问事业")
    assert "张果星宗" in qz_text
    assert "穷通宝鉴" not in qz_text and "紫微斗数全书" not in qz_text

    assert mingli_corpus.retrieve_for_facts({"unknown"}, bazi_facts, "问事业") == ""

    # Confirm hooks inside lore.py & reading_agent.py include grounded dynamic classics cleanly
    nonstream_bz = mingli_lore.lore_for_bundle_types({"bazi.chart"}, facts=bazi_facts, question="感情婚姻")
    assert "按盘实查古籍原典" in nonstream_bz and "穷通宝鉴" in nonstream_bz
    stream_qz = reading_agent.build_reading_system({"qizheng.chart"}, facts=qz_facts, question="事业")
    assert "张果星宗" in stream_qz


def test_traditional_dream_corpus_and_citations() -> None:
    manifest = json.loads(
        (SKILLS_DIR / "dream-interpretation" / "references" / "corpus" / "manifest.json").read_text(encoding="utf-8")
    )
    assert manifest["total_records"] == 3505

    profile = dream_lore.skill_profile("梦见一条蛇钻进怀里")
    assert "传统占梦总纲" in profile
    assert "梦林玄解" in profile or "周公解梦" in profile
    assert "荣格" not in profile and "阿尼玛" not in profile

    coffin_profile = dream_lore.skill_profile("梦见抬棺材进屋")
    assert "传统谐音象征旁参" in coffin_profile and "现代词转古象桥接" in coffin_profile

    excerpts = dream_lore.source_excerpts("梦见牙齿掉了几颗")
    assert len(excerpts) >= 2
    assert any(b in excerpts for b in ("梦林玄解", "周公解梦", "断梦秘书"))
    assert "传统占梦总纲" in excerpts
    assert "中国传统占梦核心心法" in excerpts["传统占梦总纲"]

    # Pick an actual sentence from matched excerpts and verify extract_sources works & rejects fakes
    for book, body in excerpts.items():
        if book == "传统占梦总纲":
            continue
        first_line = next((ln.strip() for ln in body.splitlines() if 10 <= len(ln.strip()) <= 80 and "“" not in ln and "\"" not in ln), "")
        if first_line:
            assert dream_service.extract_sources(f'《{book}》：“{first_line}”', query="梦见牙齿掉了几颗")
            assert not dream_service.extract_sources(f'《{book}》：“这是编造的假占梦句”', query="梦见牙齿掉了几颗")
            break
