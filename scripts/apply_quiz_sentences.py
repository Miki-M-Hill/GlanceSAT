#!/usr/bin/env python3
"""Merge quiz sentences from a word/sentence text file into Database.json."""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DB_PATH = ROOT / "GlanceSAT" / "GlanceSAT" / "Database.json"
DEFAULT_INPUT = ROOT / "scripts" / "quiz_sentences_input.txt"


def parse_input(text: str) -> dict[str, str]:
    lines = [ln.rstrip() for ln in text.splitlines()]
    out: dict[str, str] = {}
    i = 0
    while i < len(lines):
        while i < len(lines) and not lines[i].strip():
            i += 1
        if i >= len(lines):
            break
        word = lines[i].strip()
        i += 1
        while i < len(lines) and not lines[i].strip():
            i += 1
        if i >= len(lines):
            raise ValueError(f"Missing sentence for {word!r}")
        sentence = lines[i].strip()
        i += 1
        key = word.lower()
        if key in out:
            raise ValueError(f"Duplicate word: {word!r}")
        out[key] = sentence
    return out


def main() -> int:
    input_path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_INPUT
    if not input_path.is_file():
        print(f"Input not found: {input_path}", file=sys.stderr)
        return 1

    mapping = parse_input(input_path.read_text(encoding="utf-8"))
    with DB_PATH.open(encoding="utf-8") as f:
        db = json.load(f)

    db_by_key = {r["word"].strip().lower(): r for r in db}
    applied = 0
    for key, sentence in mapping.items():
        row = db_by_key.get(key)
        if row is None:
            continue
        row["quizSentence"] = sentence
        applied += 1

    with DB_PATH.open("w", encoding="utf-8") as f:
        json.dump(db, f, indent=2, ensure_ascii=False)
        f.write("\n")

    in_db_not_input = sorted(r["word"] for k, r in db_by_key.items() if k not in mapping)
    in_input_not_db = sorted(w for k, w in mapping.items() if k not in db_by_key)

    print(f"Parsed input: {len(mapping)} words")
    print(f"Applied quizSentence: {applied}")
    print(f"In DB, missing from input ({len(in_db_not_input)}):")
    for w in in_db_not_input:
        print(w)
    if in_input_not_db:
        print(f"In input, not in DB ({len(in_input_not_db)}):")
        for w in in_input_not_db:
            print(w)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
