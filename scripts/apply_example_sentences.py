#!/usr/bin/env python3
"""Apply paired example sentences to Database.json.

Format (scripts/example_sentences_input.txt):
  Word
  First sentence -> exampleSentence
  Second sentence -> alternateExampleSentence

Duplicate words in the input use the first entry only.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DB_PATH = ROOT / "GlanceSAT" / "GlanceSAT" / "Database.json"
DEFAULT_INPUT = ROOT / "scripts" / "example_sentences_input.txt"

WORD_RE = re.compile(r"^[A-Z][A-Za-z'-]*$")
META_PREFIXES = (
    "please ",
    "Here is",
    "Thank you",
    "As strictly",
    "Then make",
    "use the first",
    "Every sentence",
    "The sentences",
    "maintaining",
    "Every single",
    "If anything",
    "make sure",
    "@GlanceSAT",
)


def is_meta(line: str) -> bool:
    stripped = line.strip()
    if not stripped:
        return True
    if any(stripped.startswith(prefix) for prefix in META_PREFIXES):
        return True
    return stripped.startswith("**") or stripped.startswith("- ")


def is_word_line(line: str) -> bool:
    stripped = line.strip()
    return (
        bool(stripped)
        and not is_meta(stripped)
        and bool(WORD_RE.match(stripped))
        and len(stripped) <= 30
    )


def parse_input(text: str) -> dict[str, tuple[str, str, str]]:
    text = text.replace("donation.Disclose", "donation.\n\nDisclose")
    lines = text.splitlines()
    entries: dict[str, tuple[str, str, str]] = {}
    i = 0
    while i < len(lines):
        if not is_word_line(lines[i]):
            i += 1
            continue
        word = lines[i].strip()
        i += 1
        while i < len(lines) and not lines[i].strip():
            i += 1
        if i >= len(lines) or is_word_line(lines[i]):
            continue
        first = lines[i].strip()
        i += 1
        while i < len(lines) and not lines[i].strip():
            i += 1
        if i >= len(lines) or is_word_line(lines[i]):
            continue
        second = lines[i].strip()
        i += 1
        key = word.lower()
        if key not in entries:
            entries[key] = (word, first, second)
    return entries


def main() -> int:
    input_path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_INPUT
    if not input_path.is_file():
        print(f"Input not found: {input_path}", file=sys.stderr)
        return 1

    mapping = parse_input(input_path.read_text(encoding="utf-8"))
    with DB_PATH.open(encoding="utf-8") as handle:
        database = json.load(handle)

    db_by_key = {row["word"].strip().lower(): row for row in database}
    applied = 0
    for key, (_, first, second) in mapping.items():
        row = db_by_key.get(key)
        if row is None:
            continue
        row["exampleSentence"] = first
        row["alternateExampleSentence"] = second
        applied += 1

    with DB_PATH.open("w", encoding="utf-8") as handle:
        json.dump(database, handle, indent=2, ensure_ascii=False)
        handle.write("\n")

    in_db_not_input = sorted(row["word"] for key, row in db_by_key.items() if key not in mapping)
    in_input_not_db = sorted(word for key, (word, _, _) in mapping.items() if key not in db_by_key)

    print(f"Parsed input: {len(mapping)} words")
    print(f"Applied example + alternate sentences: {applied}")
    print(f"In DB, missing from input ({len(in_db_not_input)}):")
    for word in in_db_not_input:
        print(word)
    if in_input_not_db:
        print(f"In input, not in DB ({len(in_input_not_db)}):")
        for word in in_input_not_db:
            print(word)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
