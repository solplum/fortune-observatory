"""Source cards are evidence-backed, not generated bibliographic claims."""
import re

_PAIR = re.compile(r'《([^《》\n]{2,40})》[：:，,\s]*(?:[写说]道[：:]?)?[“"「]([^“”"「」\n]{6,160})[”"」]')


def adjacent_sources(text: str, excerpts: dict[str, str]) -> list[tuple[str, str]]:
    result = []
    seen = set()
    for match in _PAIR.finditer(text):
        title, quote = match.groups()
        if title in excerpts and quote in excerpts[title] and title not in seen:
            result.append((title, quote))
            seen.add(title)
    return result[:3]
