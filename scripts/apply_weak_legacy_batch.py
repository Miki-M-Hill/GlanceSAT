#!/usr/bin/env python3
"""Apply weak legacy sentence rewrites to Database.json by field."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DB_PATH = ROOT / "GlanceSAT" / "GlanceSAT" / "Database.json"
WEAK_TSV = ROOT / "docs" / "GlanceSAT_Weak_Legacy_Sentences.tsv"
DEFAULT_INPUT = ROOT / "scripts" / "weak_legacy_batch1_input.txt"


def load_weak_targets() -> dict[str, list[str]]:
    targets: dict[str, list[str]] = {}
    for line in WEAK_TSV.read_text(encoding="utf-8").splitlines()[1:]:
        word, _count, fields = line.split("\t")
        targets[word.lower()] = fields.split(", ")
    return targets


def parse_batch(text: str) -> dict[str, list[str]]:
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    entries: dict[str, list[str]] = {}
    index = 0
    while index < len(lines):
        line = lines[index]
        if not re.match(r"^[A-Z][A-Za-z'-]*$", line):
            index += 1
            continue
        word = line
        index += 1
        sentences: list[str] = []
        while index < len(lines) and not re.match(r"^[A-Z][A-Za-z'-]*$", lines[index]):
            sentences.append(lines[index])
            index += 1
        entries[word.lower()] = sentences
    return entries


def main() -> int:
    input_path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_INPUT
    if not input_path.is_file():
        print(f"Input not found: {input_path}", file=sys.stderr)
        return 1

    targets = load_weak_targets()
    batch = parse_batch(input_path.read_text(encoding="utf-8"))

    with DB_PATH.open(encoding="utf-8") as handle:
        database = json.load(handle)

    db_by_key = {row["word"].strip().lower(): row for row in database}
    applied = 0
    skipped: list[str] = []

    for key, sentences in batch.items():
        if key not in targets:
            skipped.append(f"{key}: not on weak list")
            continue
        row = db_by_key.get(key)
        if row is None:
            skipped.append(f"{key}: not in database")
            continue
        fields = targets[key]
        if len(sentences) < len(fields):
            skipped.append(f"{row['word']}: need {len(fields)} sentence(s), got {len(sentences)}")
            continue
        for field_name, sentence in zip(fields, sentences):
            row[field_name] = sentence
            applied += 1

    with DB_PATH.open("w", encoding="utf-8") as handle:
        json.dump(database, handle, indent=2, ensure_ascii=False)
        handle.write("\n")

    print(f"Words in batch: {len(batch)}")
    print(f"Field updates applied: {applied}")
    if skipped:
        print(f"Skipped ({len(skipped)}):")
        for item in skipped:
            print(f"  - {item}")
    return 0 if not skipped else 1


if __name__ == "__main__":
    raise SystemExit(main())
