#!/usr/bin/env python3
"""Apply vocabulary definitions from a text file to Database.json."""

from __future__ import annotations

import json
import re
from pathlib import Path

DB_PATH = Path(__file__).resolve().parents[1] / "GlanceSAT" / "GlanceSAT" / "Database.json"
INPUT_PATH = Path(__file__).resolve().parent / "definitions_update_input.txt"

ENTRY_PATTERN = re.compile(
    r"^([A-Za-z]+(?:\s+[A-Za-z]+)?)\s*\(([^)]+)\)\s*[-:]\s*(.+)$"
)


def parse_definitions(text: str) -> dict[str, str]:
    definitions: dict[str, str] = {}
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("GlanceSAT"):
            continue
        match = ENTRY_PATTERN.match(line)
        if not match:
            raise ValueError(f"Could not parse line: {raw_line!r}")
        word, _pos, definition = match.groups()
        word_key = word.strip()
        definition = definition.strip()
        if word_key in definitions:
            raise ValueError(f"Duplicate definition for {word_key!r}")
        definitions[word_key] = definition
    return definitions


def main() -> None:
    text = INPUT_PATH.read_text(encoding="utf-8")
    definitions = parse_definitions(text)
    print(f"Parsed {len(definitions)} definitions from {INPUT_PATH.name}")

    with DB_PATH.open(encoding="utf-8") as f:
        words = json.load(f)

    updated = 0
    missing: list[str] = []
    for entry in words:
        word = entry["word"]
        if word not in definitions:
            missing.append(word)
            continue
        new_def = definitions[word]
        old_def = entry.get("definition")
        if old_def != new_def:
            entry["definition"] = new_def
            updated += 1

    extra = sorted(set(definitions) - {entry["word"] for entry in words})
    if missing:
        raise SystemExit(f"Database words missing from input ({len(missing)}): {missing[:10]}...")
    if extra:
        raise SystemExit(f"Input words not in database ({len(extra)}): {extra[:10]}...")

    with DB_PATH.open("w", encoding="utf-8") as f:
        json.dump(words, f, indent=2, ensure_ascii=False)
        f.write("\n")

    print(f"Updated {updated} definitions in {DB_PATH}")
    print(f"Unchanged: {len(words) - updated}")


if __name__ == "__main__":
    main()
