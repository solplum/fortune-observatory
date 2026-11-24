"""Traditional Chinese dream-divination lore grounded in ``skills/dream-interpretation``.

Reuses ``skills/dream-interpretation/scripts/dream_query.py`` (cleaned corpus of
3,505 entries across 《梦林玄解》《断梦秘书》《周公解梦》《古今图书集成·梦部》
plus pre-modern treatises) and provides tightly bounded, verbatim-checkable
excerpts for ``verified_sources.adjacent_sources``.
"""

from __future__ import annotations

import importlib.util
import sys
from functools import lru_cache
from pathlib import Path
from typing import Any

_DREAMS_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = _DREAMS_DIR.parents[2]
SKILL_DIR = PROJECT_ROOT / "skills" / "dream-interpretation"
SKILL_REFS_DIR = SKILL_DIR / "references"
_DREAM_QUERY_PATH = SKILL_DIR / "scripts" / "dream_query.py"

_METHODOLOGY_SUMMARY = (
    "【传统占梦总纲】\n"
    "1. 辨六梦与虚实（《周礼·占梦》《潜夫论·梦列》）：区分正梦、思梦（日有所思）、惧梦（惊怖）、"
    "喜梦、寤梦、噩梦；兼参醒后余绪与梦象连贯度。\n"
    "2. 平旦清浊：鸡鸣平旦（寅卯，约03:00-07:00）清气初升，验应最重；子丑半夜次之；"
    "初夜（亥前）昼思未定、午睡白昼外感居多，先筛劳倦积思。\n"
    "3. 合象转译：以主象、方位动向、终局与今日节气时令五行旺衰并看；援引古籍原文须逐字照录并"
    "标明《书名》，古代吉凶极言转译为平实可行的近事与身心提醒，不制造宿命恐慌。"
)


@lru_cache(maxsize=1)
def _dream_query_module():
    spec = importlib.util.spec_from_file_location("_observatory_lzl_dream_query", _DREAM_QUERY_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Cannot load dream_query module from {_DREAM_QUERY_PATH}")
    mod = importlib.util.module_from_spec(spec)
    sys.modules["_observatory_lzl_dream_query"] = mod
    spec.loader.exec_module(mod)
    return mod


@lru_cache(maxsize=1)
def _cached_records() -> list[dict[str, Any]]:
    try:
        dq = _dream_query_module()
        return dq.load_corpus()
    except Exception:
        return []


@lru_cache(maxsize=1)
def _cached_mappings() -> dict[str, Any]:
    try:
        dq = _dream_query_module()
        return dq.load_mappings()
    except Exception:
        return {"modern_to_classical": [], "synonym_groups": [], "xieyin": [], "trad_to_simp": {}}


@lru_cache(maxsize=1)
def _methodology_doc() -> str:
    try:
        return (SKILL_REFS_DIR / "methodology.md").read_text(encoding="utf-8")[:2400].strip()
    except OSError:
        return ""


@lru_cache(maxsize=64)
def retrieve_dream_context(query: str = "", limit: int = 12) -> dict[str, Any]:
    """Retrieve matched classical dream records + modern/xieyin bridges for query."""
    records = _cached_records()
    if not records:
        return {"results": [], "modern_bridges": [], "xieyin_hints": []}

    dq = _dream_query_module()
    q_clean = query.strip()
    if q_clean:
        mappings = _cached_mappings()
        exp = dq.expand_query(q_clean, mappings)
        scored: list[dict[str, Any]] = []
        for rec in records:
            sc, md, me = dq.score_record(rec, exp)
            if sc >= 5.0:
                scored.append(
                    {
                        "score": sc,
                        "match_kind": "direct" if md else "expanded",
                        "matched_terms": md if md else me,
                        "record": rec,
                    }
                )
        scored.sort(key=lambda x: (-x["score"], x["record"]["layer"] != "omen", len(x["record"]["text"])))

        book_priority = ["梦林玄解", "断梦秘书", "周公解梦", "古今图书集成·梦部"]
        selected: list[dict[str, Any]] = []
        used_ids: set[str] = set()
        by_book: dict[str, list[dict[str, Any]]] = {}
        for item in scored:
            by_book.setdefault(item["record"]["book"], []).append(item)

        top_global = scored[0]["score"] if scored else 0.0
        min_quota_score = max(5.0, top_global * 0.25)

        for rank in range(3):
            for book in book_priority:
                items = by_book.get(book, [])
                if rank < len(items) and len(selected) < limit:
                    item = items[rank]
                    if item["score"] >= min_quota_score and item["record"]["id"] not in used_ids:
                        selected.append(item)
                        used_ids.add(item["record"]["id"])
        for book, items in by_book.items():
            if book not in book_priority:
                for item in items[:2]:
                    if len(selected) < limit and item["score"] >= max(14.0, top_global * 0.45) and item["record"]["id"] not in used_ids:
                        selected.append(item)
                        used_ids.add(item["record"]["id"])
        for item in scored:
            if len(selected) >= limit:
                break
            if item["record"]["id"] not in used_ids:
                selected.append(item)
                used_ids.add(item["record"]["id"])
        selected.sort(key=lambda x: (-x["score"], x["record"]["id"]))

        if selected:
            return {
                "results": selected,
                "modern_bridges": exp["modern_bridges"],
                "xieyin_hints": exp["xieyin_hints"],
            }

    # Core traditional theory fallback (for empty query or zero lexical hit)
    theory = [
        {"score": 10.0, "match_kind": "theory", "matched_terms": [], "record": r}
        for r in records
        if r["layer"] == "theory" and r["book"] in ("梦林玄解", "周礼·占梦", "潜夫论·梦列", "周公解梦")
    ][:8]
    return {"results": theory, "modern_bridges": [], "xieyin_hints": []}


def _bounded_text(rec: dict[str, Any]) -> str:
    txt = rec["text"].strip()
    if len(txt) > 480:
        txt = txt[:480].rstrip() + "……"
    return txt


def skill_profile(query: str = "") -> str:
    """Build compact traditional dream-divination prompt context for LLM."""
    parts: list[str] = [_METHODOLOGY_SUMMARY]

    try:
        shiling = _dream_query_module().compute_shiling(None)
        vigor = shiling["wuxing_vigor"]
        parts.append(
            f"【今日时令五行】{shiling['date']}｜节气：{shiling['jieqi']}｜"
            f"{shiling['year_gz']}年 {shiling['month_gz']}月 {shiling['day_gz']}日｜"
            f"当令主气：{shiling['season']}·{shiling['dominant_wuxing']}"
            f"（旺{vigor['旺']} 相{vigor['相']} 休{vigor['休']} 囚{vigor['囚']} 死{vigor['死']}）"
        )
    except Exception:
        pass

    ctx = retrieve_dream_context(query, limit=12)
    if ctx["modern_bridges"]:
        bridges = "；".join(
            f"{b['matched']}→{'/'.join(b['classical'])}" for b in ctx["modern_bridges"][:5]
        )
        parts.append(f"【现代词转古象桥接】{bridges}")
    if ctx["xieyin_hints"]:
        hints = "；".join(
            f"{h['key']}谐{'/'.join(h['homophones'])}（{h['meaning']}）" for h in ctx["xieyin_hints"][:4]
        )
        parts.append(f"【传统谐音象征旁参】{hints}")

    if ctx["results"]:
        book_blocks: list[str] = []
        used = 0
        for item in ctx["results"]:
            rec = item["record"]
            snippet = _bounded_text(rec)
            label = rec.get("motif") or rec.get("category") or rec["id"]
            entry = f"《{rec['book']}》· {label}：\n{snippet}"
            if used + len(entry) > 7200 and book_blocks:
                break
            book_blocks.append(entry)
            used += len(entry) + 2
        parts.append("【实查占梦古籍原文（引文必须严格取自以下原句）】\n\n" + "\n\n".join(book_blocks))

    return "\n\n".join(parts)


def source_excerpts(query: str = "") -> dict[str, str]:
    """Return {book_title: verbatim_excerpts} for exact adjacent citation verification."""
    ctx = retrieve_dream_context(query, limit=12)
    by_book: dict[str, list[str]] = {}
    for item in ctx["results"]:
        rec = item["record"]
        by_book.setdefault(rec["book"], []).append(_bounded_text(rec))

    # Also keep core theory excerpts verifiable even when query primarily matches omen rows
    if "梦林玄解" not in by_book:
        for rec in _cached_records():
            if rec["book"] == "梦林玄解" and rec["layer"] == "theory":
                by_book.setdefault("梦林玄解", []).append(_bounded_text(rec))
                if len(by_book["梦林玄解"]) >= 2:
                    break

    excerpts = {book: "\n".join(texts) for book, texts in by_book.items()}
    method = _methodology_doc()
    if method:
        excerpts["传统占梦总纲"] = _METHODOLOGY_SUMMARY + "\n" + method
    return excerpts
