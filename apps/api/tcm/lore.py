"""Online allowlist of non-prescription concepts. Historical corpus stays unchanged.

Only individually reviewed, exact excerpts are injected; source labels identify
repository study notes, not an unverified original book or author's words.
"""
from pathlib import Path

SKILL_DIR = Path(__file__).resolve().parents[3] / "skills" / "nihaixia"
_ALLOWED = (
    ("中医八纲学习摘录", "references/distilled/04-acupuncture-highlights.md",
     "中医八纲：阴阳、表里、虚实、寒热。"),
    ("六经概念学习摘录", "references/distilled/01-six-meridian-formulas.md",
     "六经是动态的**开阖枢**系统，不是静态的脏腑分类"),
)


def source_excerpts() -> dict[str, str]:
    result = {}
    for title, filename, quote in _ALLOWED:
        try:
            corpus = (SKILL_DIR / filename).read_text(encoding="utf-8")
        except OSError:
            continue
        if quote in corpus:
            result[title] = quote
    return result


def skill_profile() -> str:
    return "\n\n".join(f"《{title}》（仓库学习摘录，非原著引文）：\n{quote}"
                          for title, quote in source_excerpts().items())
