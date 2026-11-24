"""Clean three-system Mingli corpus retrieval for grounded AI readings.

Reads audited JSONL files from ``skills/mingli-corpus/`` (zero external deps)
and retrieves strictly system-isolated excerpts matching the signed chart facts
and user question.
"""

from __future__ import annotations

import json
import re
from functools import lru_cache
from pathlib import Path
from typing import Any

_REPO_ROOT = Path(__file__).resolve().parents[2]
CORPUS_DIR = _REPO_ROOT / "skills" / "mingli-corpus"

_STEMS = "甲乙丙丁戊己庚辛壬癸"
_BRANCHES = "子丑寅卯辰巳午未申酉戌亥"

_SYSTEM_FILES: dict[str, tuple[str, ...]] = {
    "bazi": ("bazi_qiongtong.jsonl", "bazi_classics.jsonl"),
    "ziwei": ("ziwei_quanshu.jsonl", "ziwei_stars_patterns.jsonl"),
    "qizheng": ("qizheng_classics.jsonl", "qizheng_stars.jsonl", "qizheng_palaces_geju.jsonl"),
}

_ZIWEI_MAJORS = (
    "紫微", "天机", "太阳", "武曲", "天同", "廉贞", "天府",
    "太阴", "贪狼", "巨门", "天相", "天梁", "七杀", "破军",
)
_ZIWEI_PALACES = (
    "命宫", "兄弟", "夫妻", "子女", "财帛", "疾厄",
    "迁移", "仆役", "交友", "官禄", "田宅", "福德", "父母",
)
_BAZI_SHISHEN = (
    "正官", "七杀", "正财", "偏财", "正印", "偏印", "枭神",
    "食神", "伤官", "比肩", "劫财", "羊刃", "建禄",
)
_QIZHENG_STARS = (
    "太阳", "太阴", "木星", "火星", "土星", "金星", "水星",
    "罗睺", "计都", "月孛", "紫气", "岁星", "荧惑", "镇星", "太白", "辰星",
)
_ALIASES: dict[str, tuple[str, ...]] = {
    "感情": ("夫妻", "妻妾", "婚姻", "配偶", "正财", "正官", "桃花"),
    "婚姻": ("夫妻", "妻妾", "婚姻", "配偶", "正财", "正官"),
    "姻缘": ("夫妻", "妻妾", "婚姻", "配偶", "正财", "正官"),
    "事业": ("官禄", "事业", "正官", "七杀", "印绶", "功名"),
    "工作": ("官禄", "事业", "正官", "七杀", "印绶"),
    "财运": ("财帛", "正财", "偏财", "禄存", "武曲", "天府", "太阴", "田宅"),
    "财富": ("财帛", "田宅", "正财", "偏财", "禄存", "武曲", "天府"),
    "健康": ("疾厄", "调候", "五行", "生杀", "太阴", "天梁"),
    "运势": ("大运", "大限", "流年", "用神", "调候"),
}


@lru_cache(maxsize=4)
def _load_system_records(system: str, *, include_feixing: bool = False) -> tuple[dict[str, Any], ...]:
    files = _SYSTEM_FILES.get(system, ())
    out: list[dict[str, Any]] = []
    for fname in files:
        fpath = CORPUS_DIR / fname
        if not fpath.is_file():
            continue
        with fpath.open(encoding="utf-8") as fh:
            for line in fh:
                s = line.strip()
                if not s:
                    continue
                rec = json.loads(s)
                if not include_feixing and rec.get("school") == "feixing_reference":
                    continue
                out.append(rec)
    return tuple(out)


def _facts_text(facts: list[Any] | None) -> str:
    if not facts:
        return ""
    chunks: list[str] = []
    for item in facts:
        text = getattr(item, "text", None)
        if text is None and isinstance(item, dict):
            text = item.get("text", "")
        if text:
            chunks.append(str(text))
    return "\n".join(chunks)


def _select_balanced(scored: list[tuple[float, int, dict[str, Any]]], limit: int) -> list[dict[str, Any]]:
    ordered = [r for _, _, r in scored]
    picked: list[dict[str, Any]] = []
    seen_ids: set[str] = set()
    book_counts: dict[str, int] = {}
    cap = max(1, limit // 2)
    for rec in ordered:
        b = rec["book"]
        if book_counts.get(b, 0) < cap:
            picked.append(rec)
            seen_ids.add(rec["id"])
            book_counts[b] = book_counts.get(b, 0) + 1
            if len(picked) >= limit:
                return picked
    for rec in ordered:
        if rec["id"] not in seen_ids:
            picked.append(rec)
            seen_ids.add(rec["id"])
            if len(picked) >= limit:
                return picked
    return picked


def _score_terms(rec: dict[str, Any], primary: list[str], secondary: list[str]) -> float:
    title = rec.get("title", "")
    category = rec.get("category", "")
    text = rec.get("text", "")
    tags_s = json.dumps(rec.get("tags", {}), ensure_ascii=False)
    score = 0.0
    for term in primary:
        if term in title or term in category:
            score += 7.0
        if term in tags_s:
            score += 5.0
        cnt = text.count(term)
        if cnt:
            score += min(cnt, 4) * 2.0
    for term in secondary:
        if term in title or term in category:
            score += 3.0
        if term in tags_s:
            score += 2.5
        cnt = text.count(term)
        if cnt:
            score += min(cnt, 3) * 1.0
    if score > 0 and rec.get("school") == "classical":
        score += 0.5
    if score > 0 and "（续" in title:
        score -= 0.4
    return score


def _topic_terms(question: str) -> list[str]:
    terms: list[str] = []
    for key, vals in _ALIASES.items():
        if key in question:
            terms.extend(vals)
    return list(dict.fromkeys(terms))


def retrieve_bazi(facts_blob: str, question: str, limit: int = 5) -> list[dict[str, Any]]:
    recs = _load_system_records("bazi")
    if not recs:
        return []
    m_month = re.search(rf"月柱([{_STEMS}])([{_BRANCHES}])", facts_blob)
    m_day = re.search(rf"日柱([{_STEMS}])([{_BRANCHES}])", facts_blob)
    day_stem = m_day.group(1) if m_day else ""
    month_branch = m_month.group(2) if m_month else ""

    picked: list[dict[str, Any]] = []
    if day_stem and month_branch:
        qt = [
            r for r in recs
            if r["book"] == "穷通宝鉴"
            and r["tags"].get("day_stem") == day_stem
            and month_branch in r["tags"].get("month_branches", [])
        ]
        picked.extend(qt[:2])

    seen_ids = {r["id"] for r in picked}
    shishen_hits = [s for s in _BAZI_SHISHEN if s in facts_blob or s in question]
    primary = list(dict.fromkeys(shishen_hits + _topic_terms(question) + ([f"{day_stem}{month_branch}"] if day_stem and month_branch else [])))
    secondary = [day_stem, month_branch, "用神", "格局"] if day_stem else ["用神", "格局"]

    scored: list[tuple[float, int, dict[str, Any]]] = []
    for idx, rec in enumerate(recs):
        if rec["id"] in seen_ids or rec["book"] == "穷通宝鉴":
            continue
        sc = _score_terms(rec, primary, secondary)
        if day_stem and day_stem in rec["tags"].get("day_stems", []):
            sc += 3.0
        if sc > 0:
            scored.append((-sc, idx, rec))
    scored.sort(key=lambda x: (x[0], x[1]))
    rem = max(1, limit - len(picked))
    picked.extend(_select_balanced(scored, rem))
    return picked[:limit]


def retrieve_ziwei(facts_blob: str, question: str, limit: int = 5) -> list[dict[str, Any]]:
    recs = _load_system_records("ziwei", include_feixing=False)
    if not recs:
        return []
    stars = [s for s in _ZIWEI_MAJORS if s in facts_blob or s in question]
    palaces = [p for p in _ZIWEI_PALACES if p in question or f"{p}" in facts_blob[:600]]
    # Prefer the palace most emphasized in question or domain facts first
    topic_terms = _topic_terms(question)
    primary = list(dict.fromkeys(topic_terms + stars[:6] + palaces[:4]))
    secondary = list(dict.fromkeys(stars + palaces + ["命宫", "四化"]))
    scored: list[tuple[float, int, dict[str, Any]]] = []
    for idx, rec in enumerate(recs):
        sc = _score_terms(rec, primary, secondary)
        if sc > 0:
            scored.append((-sc, idx, rec))
    scored.sort(key=lambda x: (x[0], x[1]))
    return _select_balanced(scored, limit)


def retrieve_qizheng(facts_blob: str, question: str, limit: int = 5) -> list[dict[str, Any]]:
    recs = _load_system_records("qizheng")
    if not recs:
        return []
    stars = [s for s in _QIZHENG_STARS if s in facts_blob or s in question]
    extra: list[str] = []
    if "昼生" in facts_blob:
        extra.extend(["昼生", "太阳", "昼星"])
    elif "夜生" in facts_blob:
        extra.extend(["夜生", "太阴", "夜星"])
    m_pal = re.search(r"命宫([子丑寅卯辰巳午未申酉戌亥])", facts_blob)
    if m_pal:
        extra.append(m_pal.group(1) + "宫")
    primary = list(dict.fromkeys(_topic_terms(question) + extra[:4] + stars[:5]))
    secondary = list(dict.fromkeys(stars + ["命宫", "恩星", "难星", "升殿", "居垣"]))
    scored: list[tuple[float, int, dict[str, Any]]] = []
    for idx, rec in enumerate(recs):
        sc = _score_terms(rec, primary, secondary)
        if sc > 0:
            scored.append((-sc, idx, rec))
    scored.sort(key=lambda x: (x[0], x[1]))
    return _select_balanced(scored, limit)


def retrieve_for_facts(
    bundle_types: set[str],
    facts: list[Any] | None = None,
    question: str = "",
    *,
    limit_per_system: int = 5,
    max_total_chars: int = 12000,
) -> str:
    """Return tightly scoped classical excerpts matching the active systems and facts."""
    has_ziwei = any(t == "ziwei.chart" or t.startswith(("fortune.", "domain.")) for t in bundle_types)
    has_bazi = "bazi.chart" in bundle_types
    has_qizheng = "qizheng.chart" in bundle_types
    if not (has_ziwei or has_bazi or has_qizheng):
        return ""

    facts_blob = _facts_text(facts)
    sections: list[str] = []
    used = 0

    def add_section(header: str, records: list[dict[str, Any]]) -> None:
        nonlocal used
        if not records or used >= max_total_chars:
            return
        lines = [header]
        for rec in records:
            txt = rec["text"].strip()
            if len(txt) > 520:
                txt = txt[:520].rstrip() + "……"
            entry = f"- 《{rec['book']}》· {rec['title']}：{txt}"
            if used + len(entry) > max_total_chars and len(lines) > 1:
                break
            lines.append(entry)
            used += len(entry) + 1
        if len(lines) > 1:
            sections.append("\n".join(lines))

    if has_bazi:
        add_section("≪八字·按盘实查古籍原典≫", retrieve_bazi(facts_blob, question, limit=limit_per_system))
    if has_ziwei:
        add_section("≪紫微·按盘实查古籍原典≫", retrieve_ziwei(facts_blob, question, limit=limit_per_system))
    if has_qizheng:
        add_section(
            "≪七政四余·按盘实查古籍原典（《张果星宗》《星学大成》《乾元秘旨》，注：恩难仇用口径以 facts 为准）≫",
            retrieve_qizheng(facts_blob, question, limit=limit_per_system),
        )
    return "\n\n".join(sections)
