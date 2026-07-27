"""Flags near-duplicate posts within a fetched batch (e.g. the same
spammy text posted repeatedly, or cross-posted under several tags) so a
human can review and delete them later. Detection only -- nothing here
ever deletes or skips a post on its own.
"""

import re
import unicodedata
from difflib import SequenceMatcher
from html.parser import HTMLParser

from . import config

# Arabic combining diacritics (tashkeel) ranges, so e.g. "مُحَمَد"
# and "محمد" normalize to the same thing.
ARABIC_DIACRITICS = re.compile("[ؐ-ًؚ-ٰٟۖ-ۭ࣓-ࣿ]")


class _TextExtractor(HTMLParser):
    def __init__(self):
        super().__init__()
        self.parts = []

    def handle_data(self, data):
        self.parts.append(data)


def strip_html(html):
    parser = _TextExtractor()
    parser.feed(html or "")
    return " ".join("".join(parser.parts).split())


def normalize(text):
    text = unicodedata.normalize("NFKC", text)
    text = ARABIC_DIACRITICS.sub("", text)
    text = re.sub(r"https?://\S+", "", text)
    text = re.sub(r"[#@]\w+", "", text)
    text = re.sub(r"[^\w\s]", "", text, flags=re.UNICODE)
    return " ".join(text.lower().split())


def find_near_duplicates(statuses, threshold=None):
    """statuses: list of dicts with at least 'id' and 'content_text'.

    Returns a list of {id, duplicate_of, similarity} for every status whose
    normalized text is a near/exact match of an earlier status in the list
    (earlier = first one seen keeps the "original" role).
    """
    threshold = threshold if threshold is not None else config.DUPLICATE_THRESHOLD
    seen = []  # list of (normalized_text, id)
    flags = []

    for status in statuses:
        norm = normalize(status["content_text"])
        if not norm:
            continue

        best_ratio = 0.0
        best_id = None
        for other_norm, other_id in seen:
            longer = max(len(norm), len(other_norm), 1)
            if abs(len(norm) - len(other_norm)) > longer * (1 - threshold) * 4:
                continue
            ratio = SequenceMatcher(None, norm, other_norm).ratio()
            if ratio > best_ratio:
                best_ratio = ratio
                best_id = other_id

        if best_ratio >= threshold and best_id is not None:
            flags.append({"id": status["id"], "duplicate_of": best_id, "similarity": round(best_ratio, 3)})
        else:
            seen.append((norm, status["id"]))

    return flags
