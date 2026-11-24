#!/usr/bin/env python3
"""
Deterministic classical dream-divination corpus search and shiling (时令五行) engine for lzl-dream.

Zero third-party dependencies (Python 3 stdlib only).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import sys
from datetime import date, datetime, timedelta, timezone
from functools import lru_cache
from pathlib import Path
from typing import Any

SKILL_ROOT = Path(__file__).resolve().parent.parent
REFS_DIR = SKILL_ROOT / "references"
CORPUS_DIR = REFS_DIR / "corpus"

# ---------------------------------------------------------------------------
# Astronomical Solar Terms & Ganzhi Calendar (aligned with bazi/pai_pan.py)
# ---------------------------------------------------------------------------
BJ = timezone(timedelta(hours=8))
J2000 = 2451545.0
UNIX_JD = 2440587.5

GAN = "甲乙丙丁戊己庚辛壬癸"
ZHI = "子丑寅卯辰巳午未申酉戌亥"
GAN_WUXING = "木木火火土土金金水水"

JIE_DEFS = (
    (315, "立春", 2),
    (345, "惊蛰", 3),
    (15, "清明", 4),
    (45, "立夏", 5),
    (75, "芒种", 6),
    (105, "小暑", 7),
    (135, "立秋", 8),
    (165, "白露", 9),
    (195, "寒露", 10),
    (225, "立冬", 11),
    (255, "大雪", 0),
    (285, "小寒", 1),
)

YUE_GAN_YIN = {0: 2, 5: 2, 1: 4, 6: 4, 2: 6, 7: 6, 3: 8, 8: 8, 4: 0, 9: 0}
ZI_SHI_GAN = {0: 0, 5: 0, 1: 2, 6: 2, 2: 4, 7: 4, 3: 6, 8: 6, 4: 8, 9: 8}

SEASON_WUXING = {
    2: ("春", "木", {"旺": "木", "相": "火", "休": "水", "囚": "金", "死": "土"}),
    3: ("春", "木", {"旺": "木", "相": "火", "休": "水", "囚": "金", "死": "土"}),
    4: ("春末土旺", "土（兼春木）", {"旺": "土", "相": "金", "休": "火", "囚": "木", "死": "水"}),
    5: ("夏", "火", {"旺": "火", "相": "土", "休": "木", "囚": "水", "死": "金"}),
    6: ("夏", "火", {"旺": "火", "相": "土", "休": "木", "囚": "水", "死": "金"}),
    7: ("夏末土旺", "土（兼夏火）", {"旺": "土", "相": "金", "休": "火", "囚": "木", "死": "水"}),
    8: ("秋", "金", {"旺": "金", "相": "水", "休": "土", "囚": "火", "死": "木"}),
    9: ("秋", "金", {"旺": "金", "相": "水", "休": "土", "囚": "火", "死": "木"}),
    10: ("秋末土旺", "土（兼秋金）", {"旺": "土", "相": "金", "休": "火", "囚": "木", "死": "水"}),
    11: ("冬", "水", {"旺": "水", "相": "木", "休": "金", "囚": "土", "死": "火"}),
    0: ("冬", "水", {"旺": "水", "相": "木", "休": "金", "囚": "土", "死": "火"}),
    1: ("冬末土旺", "土（兼冬水）", {"旺": "土", "相": "金", "休": "火", "囚": "木", "死": "水"}),
}

PERIOD_WEIGHTS = {
    "初夜": ("亥初前后（约21:00-23:00）", "偏低（昼思未定、饮食未化，思梦/病梦居多，宜先筛成因）"),
    "半夜": ("子丑之时（约23:00-03:00）", "中等（阴极阳生之交，梦象清晰连贯则可参断）"),
    "平旦": ("寅卯之际（约03:00-07:00）", "最高（鸡鸣平旦清气初升，古法以此时正梦最验）"),
    "午睡": ("巳午未时（约09:00-15:00）", "中等偏轻（《梦林玄解》云昼夜皆有吉凶，但须先排劳倦外感）"),
    "白昼": ("巳午未申时（白天）", "中等偏轻（《梦林玄解》云昼夜皆有吉凶，但须先排劳倦外感）"),
}

SHICHEN_TO_PERIOD = {
    "亥": "初夜",
    "戌": "初夜",
    "子": "半夜",
    "丑": "半夜",
    "寅": "平旦",
    "卯": "平旦",
    "辰": "平旦",
    "巳": "白昼",
    "午": "午睡",
    "未": "午睡",
    "申": "白昼",
    "酉": "初夜",
}


def _delta_t_seconds(year: float) -> float:
    t = (year - 2000.0) / 100.0
    if 1986 <= year < 2005:
        t1 = year - 2000.0
        return (
            63.86
            + 0.3345 * t1
            - 0.060374 * t1**2
            + 0.0017275 * t1**3
            + 0.000651814 * t1**4
            + 0.00002373599 * t1**5
        )
    if year < 2050:
        return 62.92 + 0.32217 * t + 0.005589 * t * t
    return -20.0 + 32.0 * ((year - 1820.0) / 100.0) ** 2 - 0.5628 * (2150.0 - year)


def _datetime_utc_from_jd(jd: float) -> datetime:
    return datetime(1970, 1, 1, tzinfo=timezone.utc) + timedelta(seconds=(jd - UNIX_JD) * 86400.0)


def _jd_tt_to_beijing(jd_tt: float) -> datetime:
    year = 2000.0 + (jd_tt - J2000) / 365.242189
    utc_jd = jd_tt - _delta_t_seconds(year) / 86400.0
    return _datetime_utc_from_jd(utc_jd).astimezone(BJ)


def _jdn(year: int, month: int, day: int) -> int:
    a = (14 - month) // 12
    y = year + 4800 - a
    m = month + 12 * a - 3
    return day + (153 * m + 2) // 5 + 365 * y + y // 4 - y // 100 + y // 400 - 32045


def _sun_apparent_longitude(jd_tt: float) -> float:
    T = (jd_tt - J2000) / 36525.0
    L0 = 280.46646 + 36000.76983 * T + 0.0003032 * T * T
    M = 357.52911 + 35999.05029 * T - 0.0001537 * T * T
    mr = math.radians(M)
    C = (
        (1.914602 - 0.004817 * T - 0.000014 * T * T) * math.sin(mr)
        + (0.019993 - 0.000101 * T) * math.sin(2.0 * mr)
        + 0.000289 * math.sin(3.0 * mr)
    )
    omega = 125.04 - 1934.136 * T
    lam = L0 + C - 0.00569 - 0.00478 * math.sin(math.radians(omega))
    return lam % 360.0


@lru_cache(maxsize=512)
def _solar_term_jd(year: int, longitude: float) -> float:
    longitude = float(longitude) % 360.0
    delta_lon = (longitude - 280.46646) % 360.0
    jd0 = J2000 + (year - 2000) * 365.242189 + delta_lon / 0.98564736
    lo, hi = jd0 - 8.0, jd0 + 8.0
    for _ in range(52):
        mid = (lo + hi) / 2.0
        diff = (_sun_apparent_longitude(mid) - longitude + 180.0) % 360.0 - 180.0
        if diff < 0:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2.0


def _gz_from_index(idx: int) -> tuple[str, str]:
    idx %= 60
    return GAN[idx % 10], ZHI[idx % 12]


def compute_shiling(date_str: str | None, shichen: str | None = None, period: str | None = None) -> dict[str, Any]:
    """Compute exact Ganzhi day/month/year and four-season Wuxing vigor."""
    if date_str:
        dt_d = date.fromisoformat(date_str)
    else:
        dt_d = datetime.now(BJ).date()

    # Use noon Beijing time as representative moment of the civil day unless shichen is 亥/子
    ref_dt = datetime(dt_d.year, dt_d.month, dt_d.day, 12, 0, tzinfo=BJ)
    lichun = _jd_tt_to_beijing(_solar_term_jd(dt_d.year, 315))
    year_num = dt_d.year if ref_dt >= lichun else dt_d.year - 1
    yg, yz = _gz_from_index((year_num - 4) % 60)
    yg_idx = GAN.index(yg)

    events = []
    for y in (dt_d.year - 1, dt_d.year, dt_d.year + 1):
        for lon, name, zhi_i in JIE_DEFS:
            events.append((_jd_tt_to_beijing(_solar_term_jd(y, lon)), name, zhi_i))
    events.sort(key=lambda x: x[0])

    current_jie = events[0]
    next_jie = None
    for ev in events:
        if ev[0] <= ref_dt:
            current_jie = ev
        elif next_jie is None:
            next_jie = ev
            break

    jie_dt, jie_name, yue_zhi_i = current_jie
    yue_zhi = ZHI[yue_zhi_i]
    yue_gan = GAN[(YUE_GAN_YIN[yg_idx] + (yue_zhi_i - 2) % 12) % 10]

    day_idx = (_jdn(dt_d.year, dt_d.month, dt_d.day) + 49) % 60
    dg, dz = _gz_from_index(day_idx)
    dg_wx = GAN_WUXING[GAN.index(dg)]

    season_label, dominant_wx, vigor = SEASON_WUXING[yue_zhi_i]

    resolved_period = period
    if not resolved_period and shichen and shichen in SHICHEN_TO_PERIOD:
        resolved_period = SHICHEN_TO_PERIOD[shichen]

    period_info = None
    if resolved_period:
        for k, val in PERIOD_WEIGHTS.items():
            if k in resolved_period or resolved_period in k:
                period_info = {"name": k, "time_range": val[0], "weight": val[1]}
                break
        if period_info is None:
            period_info = {"name": resolved_period, "time_range": "自述时段", "weight": "按清浊原则酌参"}

    hour_gz = None
    if shichen and shichen in ZHI:
        zi_i = ZHI.index(shichen)
        hg = GAN[(ZI_SHI_GAN[GAN.index(dg)] + zi_i) % 10]
        hour_gz = f"{hg}{shichen}"

    return {
        "date": dt_d.isoformat(),
        "year_gz": f"{yg}{yz}",
        "month_gz": f"{yue_gan}{yue_zhi}",
        "day_gz": f"{dg}{dz}",
        "day_wuxing": dg_wx,
        "hour_gz": hour_gz,
        "shichen": shichen,
        "jieqi": jie_name,
        "jieqi_date": jie_dt.strftime("%Y-%m-%d"),
        "next_jieqi": next_jie[1] if next_jie else None,
        "next_jieqi_date": next_jie[0].strftime("%Y-%m-%d") if next_jie else None,
        "season": season_label,
        "dominant_wuxing": dominant_wx,
        "wuxing_vigor": vigor,
        "period": period_info,
    }


# ---------------------------------------------------------------------------
# Corpus & Mapping Loaders
# ---------------------------------------------------------------------------
def load_mappings() -> dict[str, Any]:
    syn_path = REFS_DIR / "synonym-xieyin.json"
    if not syn_path.exists():
        return {"modern_to_classical": [], "synonym_groups": [], "xieyin": [], "trad_to_simp": {}}
    return json.loads(syn_path.read_text(encoding="utf-8"))


def normalize_zh(text: str, t2s: dict[str, str]) -> str:
    return "".join(t2s.get(ch, ch) for ch in text)


def load_corpus(books_filter: set[str] | None = None, layer_filter: str = "all") -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    for path in sorted(CORPUS_DIR.glob("*.jsonl")):
        with path.open("r", encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                rec = json.loads(line)
                if books_filter and rec["book"] not in books_filter:
                    continue
                if layer_filter != "all" and rec["layer"] != layer_filter:
                    continue
                records.append(rec)
    return records


# ---------------------------------------------------------------------------
# Query Expansion & Deterministic Ranking
# ---------------------------------------------------------------------------
STOP_CHARS = set("我你他她它的是了在有和与把被让给向从到又也都很太更最梦梦见梦到做了个")
NOISY_SINGLE_CHARS = set("子儿头机器物体人事大小老新男女长短高低前后上下左右内外中这那")
ACTION_HINTS = set("打杀咬追逃跑掉脱落碎破裂坏飞升坠跌淹溺烧焚哭笑死生亡入出开闭拿取拾捡丢遗借卖买吃饮喝")


def expand_query(query: str, mappings: dict[str, Any]) -> dict[str, Any]:
    t2s = mappings.get("trad_to_simp", {})
    q_simp = normalize_zh(query.strip(), t2s)
    raw_chunks = [c for c in re.split(r"[，。、；：！？\s,./|]+", q_simp) if c]

    direct_terms: list[str] = []
    expanded_terms: list[str] = []
    concept_groups: list[list[str]] = []
    modern_bridges: list[dict[str, Any]] = []
    xieyin_hints: list[dict[str, Any]] = []
    matched_modern_words: list[str] = []

    seen_direct: set[str] = set()
    seen_expanded: set[str] = set()
    seen_modern: set[str] = set()
    seen_xieyin: set[str] = set()

    def add_direct(t: str) -> None:
        if t and t not in seen_direct:
            seen_direct.add(t)
            direct_terms.append(t)

    def add_expanded(t: str) -> None:
        if t and t not in seen_direct and t not in seen_expanded:
            seen_expanded.add(t)
            expanded_terms.append(t)

    # Check modern_to_classical mappings on full query and chunks
    for m_item in mappings.get("modern_to_classical", []):
        matched_kw = None
        for m_kw in sorted(m_item["modern"], key=len, reverse=True):
            if m_kw in q_simp:
                matched_kw = m_kw
                break
        if matched_kw:
            matched_modern_words.append(matched_kw)
            key_tuple = tuple(m_item["modern"])
            if key_tuple not in seen_modern:
                seen_modern.add(key_tuple)
                if matched_kw not in m_item["classical"]:
                    modern_bridges.append(
                        {
                            "matched": matched_kw,
                            "classical": m_item["classical"],
                            "basis": m_item["basis"],
                        }
                    )
            for c in m_item["classical"]:
                add_expanded(c)
            # Also fold any matching synonym_groups into this same concept group to avoid double-counting
            merged_grp = [matched_kw] + list(m_item["classical"])
            for sg in mappings.get("synonym_groups", []):
                if any(c in sg for c in merged_grp):
                    merged_grp.extend(sg)
            concept_groups.append(list(dict.fromkeys(merged_grp)))

    # Check xieyin hints
    for x_item in mappings.get("xieyin", []):
        k = x_item["key"]
        if k in q_simp and k not in seen_xieyin:
            seen_xieyin.add(k)
            xieyin_hints.append(x_item)

    # Build direct tokens + sub-tokens & synonym group expansions
    syn_groups = mappings.get("synonym_groups", [])
    modern_sorted = sorted(set(matched_modern_words), key=len, reverse=True)
    for chunk in raw_chunks:
        chunk_clean = re.sub(r"^(?:我?昨天?夜里?|晚上|昨晚|刚才|最近)?(?:老是|总是|经常)?(?:梦见|梦到|做了个梦|做梦|梦)", "", chunk)
        if not chunk_clean:
            chunk_clean = chunk

        grp: list[str] = []
        # Preserve matched modern compound words intact without splitting inner chars (e.g. 房子/飞机/棺材)
        residual = chunk_clean
        covered_by_modern = False
        for mw in modern_sorted:
            if mw in residual:
                add_direct(mw)
                residual = residual.replace(mw, " ")
                covered_by_modern = True

        if not covered_by_modern:
            add_direct(chunk_clean)
            grp.append(chunk_clean)
            if chunk != chunk_clean:
                add_direct(chunk)

        for seg in residual.split():
            if not seg:
                continue
            if len(seg) == 1:
                if seg not in STOP_CHARS and seg not in NOISY_SINGLE_CHARS:
                    add_direct(seg)
                    grp.append(seg)
            else:
                add_direct(seg)
                grp.append(seg)
                for i in range(len(seg) - 1):
                    bi = seg[i : i + 2]
                    if not all(ch in STOP_CHARS for ch in bi):
                        add_direct(bi)
                        grp.append(bi)
                for ch in seg:
                    if (
                        ch not in STOP_CHARS
                        and ch not in NOISY_SINGLE_CHARS
                        and (ch in ACTION_HINTS or len(seg) <= 3)
                    ):
                        add_direct(ch)
                        grp.append(ch)

        # Apply classical synonym_groups only for non-modern residual tokens (modern already merged above)
        if not covered_by_modern:
            for sg in syn_groups:
                if any(w in chunk_clean or chunk_clean == w for w in sg):
                    for w in sg:
                        add_expanded(w)
                        grp.append(w)

        if grp:
            concept_groups.append(list(dict.fromkeys(grp)))

    return {
        "query_norm": q_simp,
        "direct_terms": direct_terms,
        "expanded_terms": expanded_terms,
        "concept_groups": concept_groups,
        "modern_bridges": modern_bridges,
        "xieyin_hints": xieyin_hints,
    }


def score_record(rec: dict[str, Any], exp: dict[str, Any]) -> tuple[float, list[str], list[str]]:
    motif = rec.get("motif", "")
    motif_core = re.sub(r"^梦见?", "", motif)
    text = rec.get("text", "")
    category = rec.get("category", "")
    cat_clean = re.sub(r"^[子丑寅卯辰巳午未申酉戌亥]·", "", category)
    kw_set = set(rec.get("keywords", []))
    q_norm = exp["query_norm"]

    score = 0.0
    matched_direct: list[str] = []
    matched_expanded: list[str] = []

    if q_norm and len(q_norm) >= 2:
        if q_norm == motif or q_norm == motif_core:
            score += 60.0
        elif q_norm in motif:
            score += 38.0
        elif q_norm in text:
            score += 22.0

    for term in exp["direct_terms"]:
        if len(term) == 1 and term not in ACTION_HINTS and len(exp["direct_terms"]) > 2:
            in_motif = term in motif_core
            in_kw = term in kw_set
            in_text = term in text
            if in_motif:
                score += 11.0
                matched_direct.append(term)
            elif in_kw:
                score += 6.0
                matched_direct.append(term)
            elif in_text and rec["layer"] == "omen":
                score += 3.0
                matched_direct.append(term)
            continue

        weight = 1.0 if len(term) >= 2 else 0.6
        if term == motif_core or term == motif:
            score += 42.0 * weight
            matched_direct.append(term)
        elif term in motif:
            score += 22.0 * weight
            matched_direct.append(term)
        elif term in kw_set or term in cat_clean:
            score += 12.0 * weight
            matched_direct.append(term)
        elif term in text:
            density_bonus = 7.0 if len(text) < 80 else 4.0
            score += density_bonus * weight
            matched_direct.append(term)

    for term in exp["expanded_terms"]:
        weight = 1.0 if len(term) >= 2 else 0.55
        if term == motif_core:
            score += 18.0 * weight
            matched_expanded.append(term)
        elif term in motif:
            score += 11.0 * weight
            matched_expanded.append(term)
        elif term in kw_set or term in cat_clean:
            score += 6.0 * weight
            matched_expanded.append(term)
        elif term in text and (len(term) >= 2 or rec["layer"] == "omen"):
            score += 2.5 * weight
            matched_expanded.append(term)

    if score <= 0:
        return 0.0, [], []

    # Concept group co-occurrence bonus (e.g. object + action both appear in same entry)
    concepts_hit = 0
    for grp in exp["concept_groups"]:
        if any((g in motif or g in text) for g in grp if len(g) >= 2 or g in ACTION_HINTS or g in motif_core):
            concepts_hit += 1
    if concepts_hit >= 2:
        score += (concepts_hit - 1) * 18.0

    # Layer tie-breaker: concise omen entries slightly favored over anecdotes unless theory matches
    if rec["layer"] == "omen":
        score += 3.0
    elif rec["layer"] in ("theory", "rang") and any(t in motif or t in cat_clean for t in exp["direct_terms"]):
        score += 14.0

    # Mild length normalization for huge prose blocks
    if len(text) > 350 and not any(len(t) >= 2 and t in motif for t in exp["direct_terms"]):
        score *= 0.8

    return round(score, 2), list(dict.fromkeys(matched_direct)), list(dict.fromkeys(matched_expanded))


def search_corpus(
    query: str,
    books_filter: set[str] | None = None,
    layer_filter: str = "all",
    limit: int = 15,
) -> dict[str, Any]:
    mappings = load_mappings()
    exp = expand_query(query, mappings)
    records = load_corpus(books_filter=books_filter, layer_filter=layer_filter)

    scored: list[dict[str, Any]] = []
    for rec in records:
        sc, md, me = score_record(rec, exp)
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

    # Round-robin balanced per-book selection so all matching books get represented even at small --limit
    if books_filter or len(scored) <= limit:
        selected = scored[:limit]
    else:
        book_priority = ["梦林玄解", "断梦秘书", "周公解梦", "古今图书集成·梦部"]
        selected = []
        used_ids: set[str] = set()
        by_book: dict[str, list[dict[str, Any]]] = {}
        for item in scored:
            b = item["record"]["book"]
            by_book.setdefault(b, []).append(item)

        top_global = scored[0]["score"] if scored else 0.0
        min_quota_score = max(5.0, top_global * 0.25)

        for rank in range(3):
            for b in book_priority:
                items = by_book.get(b, [])
                if rank < len(items) and len(selected) < limit:
                    item = items[rank]
                    if item["score"] >= min_quota_score and item["record"]["id"] not in used_ids:
                        selected.append(item)
                        used_ids.add(item["record"]["id"])

        for b, items in by_book.items():
            if b not in book_priority:
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

    has_direct_omen = any(
        item["match_kind"] == "direct" and item["record"]["layer"] == "omen" for item in selected
    )
    return {
        "query": query,
        "query_norm": exp["query_norm"],
        "direct_terms": exp["direct_terms"],
        "expanded_terms": exp["expanded_terms"],
        "modern_bridges": exp["modern_bridges"],
        "xieyin_hints": exp["xieyin_hints"],
        "total_candidates": len(scored),
        "has_direct_omen": has_direct_omen,
        "results": selected,
    }


# ---------------------------------------------------------------------------
# Subcommand Handlers
# ---------------------------------------------------------------------------
def cmd_stats(args: argparse.Namespace) -> int:
    man_path = CORPUS_DIR / "manifest.json"
    if not man_path.exists():
        print("ERROR: manifest.json missing", file=sys.stderr)
        return 1
    manifest = json.loads(man_path.read_text(encoding="utf-8"))
    integrity: dict[str, bool] = {}
    for fname, meta in manifest["files"].items():
        fpath = CORPUS_DIR / fname
        if not fpath.exists():
            integrity[fname] = False
            continue
        actual_sha = hashlib.sha256(fpath.read_bytes()).hexdigest()
        integrity[fname] = actual_sha == meta["sha256"]

    all_ok = all(integrity.values())
    if args.json:
        print(json.dumps({"integrity_ok": all_ok, "integrity": integrity, "manifest": manifest}, ensure_ascii=False, indent=2))
        return 0 if all_ok else 1

    print(f"## 典籍知识库状态 (total={manifest['total_records']} 条, 校验={'PASS' if all_ok else 'FAIL'})")
    print(f"- 构建时间: {manifest['built_at']}")
    print("- 分文件统计:")
    for fname, meta in manifest["files"].items():
        mark = "OK" if integrity[fname] else "SHA-MISMATCH"
        print(f"  - `{fname}`: {meta['count']} 条, {meta['bytes']/1024:.1f} KB [{mark}]")
    print("- 分典籍统计:")
    for b, cnt in manifest["books"].items():
        print(f"  - {b}: {cnt} 条")
    print("- 分层级统计:", manifest["layers"])
    print("- 收录说明:")
    for note in manifest.get("coverage_notes", []):
        print(f"  - {note}")
    return 0 if all_ok else 1


def cmd_browse(args: argparse.Namespace) -> int:
    books_filter = {b.strip() for b in args.book.split(",")} if args.book else None
    records = load_corpus(books_filter=books_filter, layer_filter=args.layer)
    if args.category:
        records = [r for r in records if args.category in r["category"]]

    if args.list_categories:
        cats: dict[str, int] = {}
        for r in records:
            key = f"{r['book']} :: {r['category']}"
            cats[key] = cats.get(key, 0) + 1
        if args.json:
            print(json.dumps(cats, ensure_ascii=False, indent=2))
        else:
            print(f"## 门类目录（共 {len(cats)} 类）")
            for k, v in cats.items():
                print(f"- {k} ({v})")
        return 0

    sliced = records[: args.limit]
    if args.json:
        print(json.dumps(sliced, ensure_ascii=False, indent=2))
        return 0

    print(f"## 浏览典籍条目（命中 {len(records)} 条，展示前 {len(sliced)} 条）")
    for r in sliced:
        print(f"- [{r['id']}] 《{r['book']}》[{r['category']}] ({r['layer']} / {r['polarity']})：{r['text']}")
    return 0


def cmd_search(args: argparse.Namespace) -> int:
    books_filter = {b.strip() for b in args.books.split(",") if b.strip()} if args.books else None
    res = search_corpus(args.q, books_filter=books_filter, layer_filter=args.layer, limit=args.limit)

    shiling = None
    if args.date or args.with_time or args.shichen or args.period:
        shiling = compute_shiling(args.date, shichen=args.shichen, period=args.period)

    if args.json:
        payload = {"search": res, "shiling": shiling}
        print(json.dumps(payload, ensure_ascii=False, indent=2))
        return 0

    print(f"## 检索条件：`{res['query']}`（规范化：`{res['query_norm']}`，共筛出 {res['total_candidates']} 条相关记录）")
    if res["modern_bridges"]:
        print("### 现代意象取象桥接（非古籍原辞，仅用于检索扩展与类比参考）")
        for mb in res["modern_bridges"]:
            print(f"- `{mb['matched']}` → {', '.join(mb['classical'])}（依据：{mb['basis']}）")
    if res["xieyin_hints"]:
        print("### 传统谐音取象线索")
        for x in res["xieyin_hints"]:
            print(f"- `{x['key']}` 谐音 `{'/'.join(x['homophones'])}` → {x['meaning']}（{x['basis']}）")

    if shiling:
        print("\n## 时令与干支五行")
        print(f"- 公历日期：{shiling['date']}｜节气：{shiling['jieqi']}（{shiling['jieqi_date']}）后")
        print(f"- 干支纪日：年柱 `{shiling['year_gz']}` · 月柱 `{shiling['month_gz']}` · 日柱 `{shiling['day_gz']}`（日干五行：**{shiling['day_wuxing']}**）")
        if shiling["hour_gz"]:
            print(f"- 梦时推算：{shiling['shichen']}时（时柱 `{shiling['hour_gz']}`）")
        v = shiling["wuxing_vigor"]
        print(f"- 四时气令：**{shiling['season']}**（当令五行：**{shiling['dominant_wuxing']}**）｜旺 `{v['旺']}` · 相 `{v['相']}` · 休 `{v['休']}` · 囚 `{v['囚']}` · 死 `{v['死']}`")
        if shiling["period"]:
            p = shiling["period"]
            print(f"- 时段权重：{p['name']}（{p['time_range']}）→ {p['weight']}")

    print("\n## 典籍命中原文")
    if not res["results"]:
        print("（典籍词库中未命中直接条文，请换用核心物体/动作或古语近义词重检。）")
        return 0

    if not res["has_direct_omen"]:
        print("（典籍词库中未命中直接梦占条文，以下为古语同义扩展、取象类比或古籍总论/案例参考：）")

    for i, item in enumerate(res["results"], 1):
        r = item["record"]
        m_tag = "直接命中" if item["match_kind"] == "direct" else "同义/取象扩展"
        cond_str = "、".join(r["conditions"])
        print(
            f"{i}. **[{r['id']}] 《{r['book']}》· {r['category']}** "
            f"（层级：{r['layer']}｜吉凶倾向：{r['polarity']}｜适用：{cond_str}｜{m_tag}：{','.join(item['matched_terms'])}｜分值：{item['score']}）"
        )
        print(f"   > {r['text']}")
        if r.get("note"):
            print(f"   - 注：{r['note']}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="lzl-dream 古籍检索与时令五行推算引擎")
    sub = p.add_subparsers(dest="cmd", required=True)

    ps = sub.add_parser("search", help="检索梦象原文与计算时令干支五行")
    ps.add_argument("--q", required=True, help="梦境关键词或短句（支持空格分隔物体+动作）")
    ps.add_argument("--books", default="", help="过滤典籍，逗号分隔")
    ps.add_argument("--layer", default="all", choices=["all", "omen", "theory", "case", "rang", "literature"])
    ps.add_argument("--date", default=None, help="做梦日期 YYYY-MM-DD")
    ps.add_argument("--with-time", action="store_true", help="未传 --date 时默认按今天计算时令干支")
    ps.add_argument("--shichen", default=None, choices=list(ZHI), help="做梦时辰地支")
    ps.add_argument("--period", default=None, help="做梦时段（初夜/半夜/平旦/午睡/白昼）")
    ps.add_argument("--limit", type=int, default=15)
    ps.add_argument("--json", action="store_true")
    ps.set_defaults(func=cmd_search)

    pb = sub.add_parser("browse", help="按典籍与门类浏览知识库")
    pb.add_argument("--book", default="", help="典籍名称")
    pb.add_argument("--category", default="", help="门类关键词")
    pb.add_argument("--layer", default="all", choices=["all", "omen", "theory", "case", "rang", "literature"])
    pb.add_argument("--list-categories", action="store_true")
    pb.add_argument("--limit", type=int, default=30)
    pb.add_argument("--json", action="store_true")
    pb.set_defaults(func=cmd_browse)

    pst = sub.add_parser("stats", help="校验典籍库完整性与显示统计")
    pst.add_argument("--json", action="store_true")
    pst.set_defaults(func=cmd_stats)
    return p


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
