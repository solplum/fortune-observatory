#!/usr/bin/env python3
"""Unit tests for lzl-dream corpus integrity, deterministic search, and shiling calendar."""

from __future__ import annotations

import hashlib
import json
import re
import subprocess
import sys
import unittest
from pathlib import Path

SCRIPTS_DIR = Path(__file__).resolve().parent
SKILL_ROOT = SCRIPTS_DIR.parent
CORPUS_DIR = SKILL_ROOT / "references" / "corpus"

sys.path.insert(0, str(SCRIPTS_DIR))
import dream_query  # noqa: E402


class CorpusIntegrityTests(unittest.TestCase):
    def test_manifest_and_sha256(self) -> None:
        man_path = CORPUS_DIR / "manifest.json"
        self.assertTrue(man_path.exists(), "manifest.json must exist")
        manifest = json.loads(man_path.read_text(encoding="utf-8"))

        expected_mins = {
            "menglin_xuanjie.jsonl": 600,
            "duanmeng_mishu.jsonl": 900,
            "zhougong_27.jsonl": 950,
            "gujin_mengbu.jsonl": 900,
            "classics_theory.jsonl": 10,
        }
        for fname, min_cnt in expected_mins.items():
            fpath = CORPUS_DIR / fname
            self.assertTrue(fpath.exists(), f"{fname} missing")
            meta = manifest["files"][fname]
            actual_sha = hashlib.sha256(fpath.read_bytes()).hexdigest()
            self.assertEqual(actual_sha, meta["sha256"], f"SHA mismatch on {fname}")

            lines = [json.loads(l) for l in fpath.read_text(encoding="utf-8").splitlines() if l.strip()]
            self.assertGreaterEqual(len(lines), min_cnt, f"Too few records in {fname}")
            for r in lines:
                self.assertTrue(r["text"].strip(), f"Empty text in {fname}: {r['id']}")
                self.assertFalse(
                    re.search(r"<[a-zA-Z/]+[^>]*>|&#\d+;|\[编辑\]|欢迎各位持续修正|Public domain|此作品在全世界", r["text"]),
                    f"Boilerplate/HTML leak in {fname}: {r['id']}",
                )
            if fname == "classics_theory.jsonl":
                max_len = max(len(r["text"]) for r in lines)
                self.assertLessEqual(max_len, 1500, f"Oversized record in {fname}: {max_len}")


class RetrievalPrecisionTests(unittest.TestCase):
    def test_black_snake_bite_kill(self) -> None:
        res = dream_query.search_corpus("黑蛇 咬 打死", limit=10)
        self.assertTrue(res["has_direct_omen"])
        books = {item["record"]["book"] for item in res["results"]}
        self.assertIn("周公解梦", books)
        self.assertIn("梦林玄解", books)
        # 蛇 itself is classical and should not be labeled as a modern bridge
        self.assertFalse(any(mb["matched"] == "蛇" for mb in res["modern_bridges"]))
        top_texts = " ".join(item["record"]["text"] for item in res["results"][:5])
        self.assertIn("蛇", top_texts)

    def test_house_collapse_modern_expansion(self) -> None:
        res = dream_query.search_corpus("房子 倒塌", limit=8)
        self.assertTrue(any(mb["matched"] == "房子" for mb in res["modern_bridges"]))
        self.assertGreater(len(res["results"]), 0)
        top_rec = res["results"][0]["record"]
        self.assertNotIn("子·天文类", top_rec["category"])
        top_texts = " ".join(item["record"]["text"] for item in res["results"][:4])
        self.assertTrue(any(k in top_texts for k in ("屋", "宅", "室", "倒", "塌", "坏", "崩")))

    def test_airplane_fall_no_ji_noise(self) -> None:
        res = dream_query.search_corpus("坐飞机 坠落", limit=8)
        self.assertTrue(any(mb["matched"] in ("飞机", "坐飞机") for mb in res["modern_bridges"]))
        # Must NOT decompose 飞机 into noisy single char '机' matching '生死之机'
        self.assertNotIn("机", res["direct_terms"])
        top_texts = " ".join(item["record"]["text"] for item in res["results"][:5])
        self.assertTrue(any(k in top_texts for k in ("飞", "上天", "坠", "落")))

    def test_coffin_xieyin_and_multi_book(self) -> None:
        res = dream_query.search_corpus("棺材", limit=8)
        self.assertTrue(any(x["key"] == "棺" for x in res["xieyin_hints"]))
        books = {item["record"]["book"] for item in res["results"]}
        self.assertGreaterEqual(len(books), 3, f"Expected >=3 books, got {books}")

    def test_theory_and_rang_queries(self) -> None:
        r1 = dream_query.search_corpus("淫邪发梦", limit=5)
        self.assertIn("黄帝内经·灵枢", {i["record"]["book"] for i in r1["results"]})

        r2 = dream_query.search_corpus("六梦", limit=5)
        self.assertTrue(any("周礼" in i["record"]["book"] for i in r2["results"]))

        r3 = dream_query.search_corpus("解恶梦", limit=5)
        self.assertIn("道藏·洞玄灵宝道学科仪", {i["record"]["book"] for i in r3["results"]})

    def test_unmatched_query_graceful(self) -> None:
        res = dream_query.search_corpus("zzzz_xyz_9999", limit=5)
        self.assertEqual(len(res["results"]), 0)
        self.assertFalse(res["has_direct_omen"])


class ShilingCalendarTests(unittest.TestCase):
    def test_known_dates(self) -> None:
        cases = [
            ("1990-05-15", "庚午", "辛巳", "庚辰", "夏", "火"),
            ("2000-01-01", "己卯", "丙子", "戊午", "冬", "水"),
            ("2026-11-24", "丙午", "己亥", "壬寅", "冬", "水"),
        ]
        for dt, yg, mg, dg, season, wang in cases:
            sh = dream_query.compute_shiling(dt, period="平旦")
            self.assertEqual(sh["year_gz"], yg, dt)
            self.assertEqual(sh["month_gz"], mg, dt)
            self.assertEqual(sh["day_gz"], dg, dt)
            self.assertEqual(sh["season"], season, dt)
            self.assertEqual(sh["wuxing_vigor"]["旺"], wang, dt)
            self.assertEqual(sh["period"]["name"], "平旦")

    def test_cross_check_bazi_script_if_present(self) -> None:
        bazi_script = Path("/Users/sol/.agents/skills/bazi/scripts/pai_pan.py")
        if not bazi_script.exists():
            self.skipTest("bazi/scripts/pai_pan.py not installed on this machine")
        out = subprocess.check_output(
            [sys.executable, str(bazi_script), "--solar", "2026-11-24", "--shichen", "午", "--sex", "男"],
            text=True,
        )
        sh = dream_query.compute_shiling("2026-11-24")
        self.assertIn(sh["day_gz"][0], out)
        self.assertIn(sh["day_gz"][1], out)


if __name__ == "__main__":
    unittest.main()
