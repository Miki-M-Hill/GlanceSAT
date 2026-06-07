#!/usr/bin/env python3
"""Apply Section 3 broken/off-target rewrites to Database.json selectively."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DB_PATH = ROOT / "GlanceSAT" / "GlanceSAT" / "Database.json"
PROMPT_PATH = ROOT / "docs" / "GlanceSAT_Sentence_Rewrite_Prompt.md"
DEFAULT_INPUT = ROOT / "scripts" / "section3_sentences_input.txt"

# Reuse scoring helpers from Section 2 apply script.
sys.path.insert(0, str(ROOT / "scripts"))
from apply_example_sentences import parse_input  # noqa: E402
from apply_section2_sentences import (  # noqa: E402
    apply_overrides,
    pick_stronger,
)

# Section 3 targets parsed from the rewrite prompt (not regex — stable list).
SECTION3_TARGETS: dict[str, dict[str, bool]] = {
    "abide": {"example": False, "alternate": True},
    "patent": {"example": True, "alternate": False},
    "turgid": {"example": False, "alternate": True},
    "canvas": {"example": False, "alternate": True},
    "florid": {"example": True, "alternate": False},
    "foil": {"example": False, "alternate": True},
    "forage": {"example": True, "alternate": False},
    "fortuitous": {"example": True, "alternate": False},
    "fractious": {"example": False, "alternate": True},
    # Remaining Section 3 words — awaiting user batch:
    "placid": {"example": True, "alternate": False},
    "plausible": {"example": True, "alternate": False},
    "pliable": {"example": True, "alternate": False},
    "poignant": {"example": True, "alternate": False},
    "polemic": {"example": True, "alternate": False},
    "precipice": {"example": True, "alternate": False},
    "presage": {"example": True, "alternate": False},
    "probity": {"example": True, "alternate": False},
    "prosaic": {"example": True, "alternate": False},
}

# Prefer sentences that satisfy the listed Section 3 fix.
PREFERRED_SENTENCE: dict[str, str] = {
    "abide": (
        "The honorable knight swore to abide by the strict royal code."
    ),
    "turgid": (
        "The boring professor delivered a turgid lecture filled with unnecessary academic jargon."
    ),
    "canvas": (
        "The talented artist carefully primed the blank canvas before painting her masterpiece."
    ),
    "florid": (
        "The architect despised the florid decorations covering the walls of the Victorian mansion."
    ),
    "foil": (
        "The cynical detective served as a perfect foil to his optimistic partner."
    ),
    "fortuitous": (
        "Meeting the influential publisher at the crowded cafe was a fortuitous encounter."
    ),
    "fractious": (
        "The exhausted teacher struggled to quiet the fractious children during the long assembly."
    ),
}

BANNED = ("incredibly", "completely", "massive")


def choose_sentence(word_key: str, s1: str, s2: str) -> str:
    preferred = PREFERRED_SENTENCE.get(word_key)
    if preferred:
        for candidate in (s1, s2):
            if candidate == preferred:
                return candidate
    return pick_stronger(word_key, s1, s2)


def main() -> int:
    input_path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_INPUT
    if not input_path.is_file():
        print(f"Input not found: {input_path}", file=sys.stderr)
        return 1

    raw = parse_input(input_path.read_text(encoding="utf-8"))
    pairs = {key: (word, first, second) for key, (word, first, second) in raw.items()}

    with DB_PATH.open(encoding="utf-8") as handle:
        database = json.load(handle)
    db_by_key = {row["word"].strip().lower(): row for row in database}

    example_updates = 0
    alternate_updates = 0

    for word_key, fields in SECTION3_TARGETS.items():
        if word_key not in pairs:
            continue

        row = db_by_key.get(word_key)
        if row is None:
            print(f"WARNING: {word_key} not in database")
            continue

        _, s1, s2 = pairs[word_key]
        s1, s2 = apply_overrides(word_key, s1, s2)

        if fields["example"] and fields["alternate"]:
            row["exampleSentence"] = s1
            row["alternateExampleSentence"] = s2
            example_updates += 1
            alternate_updates += 1
        elif fields["example"]:
            row["exampleSentence"] = choose_sentence(word_key, s1, s2)
            example_updates += 1
        elif fields["alternate"]:
            row["alternateExampleSentence"] = choose_sentence(word_key, s1, s2)
            alternate_updates += 1

    with DB_PATH.open("w", encoding="utf-8") as handle:
        json.dump(database, handle, indent=2, ensure_ascii=False)
        handle.write("\n")

    violations: list[str] = []
    for word_key, fields in SECTION3_TARGETS.items():
        if word_key not in pairs:
            continue
        row = db_by_key[word_key]
        for field_name, enabled in (
            ("exampleSentence", fields["example"]),
            ("alternateExampleSentence", fields["alternate"]),
        ):
            if not enabled:
                continue
            sentence = row.get(field_name) or ""
            word_count = len(sentence.split())
            if word_count < 10 or word_count > 14:
                violations.append(f"{row['word']} {field_name}: {word_count} words")
            lowered = sentence.lower()
            for banned in BANNED:
                if re.search(rf"\b{re.escape(banned)}\b", lowered):
                    violations.append(f"{row['word']} {field_name}: banned '{banned}'")

    pending = sorted(k for k in SECTION3_TARGETS if k not in pairs)
    print(f"Section 3 words in prompt: {len(SECTION3_TARGETS)}")
    print(f"Applied from input: {len(pairs)}")
    print(f"exampleSentence updates: {example_updates}")
    print(f"alternateExampleSentence updates: {alternate_updates}")
    print(f"Still pending ({len(pending)}): {', '.join(w.title() for w in pending)}")

    if violations:
        print("\nVALIDATION FAILURES:")
        for item in violations:
            print(f"  - {item}")
        return 1

    print("\nValidation passed for applied words.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
