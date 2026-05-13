#!/usr/bin/env python3
"""Merge Database.json entries like 'Word (1)' / 'Word (2)' into one record with senses[]."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import Any

NUMBERED_SUFFIX = re.compile(r"^(?P<base>.+?) \((?P<num>\d+)\)\s*$")


def split_top_level_json_objects(raw: str) -> list[str]:
    depth = 0
    start: int | None = None
    in_string = False
    escape = False
    blobs: list[str] = []
    for i, ch in enumerate(raw):
        if escape:
            escape = False
            continue
        if ch == "\\" and in_string:
            escape = True
            continue
        if ch == '"':
            in_string = not in_string
            continue
        if in_string:
            continue
        if ch == "{":
            if depth == 0:
                start = i
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0 and start is not None:
                blobs.append(raw[start : i + 1])
                start = None
    return blobs


def parse_records(path: Path) -> list[dict[str, Any]]:
    raw = path.read_text(encoding="utf-8")
    trimmed = raw.strip()
    # Try whole-file JSON array first
    try:
        data = json.loads(trimmed)
        if isinstance(data, list):
            return [x for x in data if isinstance(x, dict)]
    except json.JSONDecodeError:
        pass

    blobs = split_top_level_json_objects(trimmed)
    records: list[dict[str, Any]] = []
    for b in blobs:
        try:
            records.append(json.loads(b))
        except json.JSONDecodeError as e:
            print(f"Skipping malformed object: {e}", file=sys.stderr)
    return records


def base_word_key(word: str) -> tuple[str | None, int | None]:
    m = NUMBERED_SUFFIX.match(word.strip())
    if not m:
        return word.strip(), None
    return m.group("base").strip(), int(m.group("num"))


def merge_database(records: list[dict[str, Any]]) -> list[dict[str, Any]]:
    numbered_buckets: dict[str, list[tuple[int, dict[str, Any]]]] = {}
    for rec in records:
        w = rec.get("word")
        if not isinstance(w, str):
            continue
        base, num = base_word_key(w)
        if num is None:
            continue
        numbered_buckets.setdefault(base, []).append((num, rec))

    merged_by_base: dict[str, dict[str, Any]] = {}
    for base, items in numbered_buckets.items():
        items = sorted(items, key=lambda x: x[0])
        first = items[0][1]
        senses = [
            {
                "partOfSpeech": r["partOfSpeech"],
                "definition": r["definition"],
                "synonyms": r.get("synonyms", []),
                "exampleSentence": r["exampleSentence"],
            }
            for _, r in items
        ]
        merged_by_base[base] = {
            "id": first["id"],
            "word": base,
            "difficultyLevel": first.get("difficultyLevel"),
            "frequencyTier": first.get("frequencyTier"),
            "category": first["category"],
            "etymology": first.get("etymology"),
            "learningData": first.get("learningData"),
            "senses": senses,
        }

    out: list[dict[str, Any]] = []
    seen_numbered_bases: set[str] = set()
    for rec in records:
        w = rec.get("word")
        if not isinstance(w, str):
            out.append(rec)
            continue
        base, num = base_word_key(w)
        if num is None:
            out.append(rec)
            continue
        if base in seen_numbered_bases:
            continue
        seen_numbered_bases.add(base)
        out.append(merged_by_base[base])

    return out


def main() -> None:
    root = Path(__file__).resolve().parent
    db_path = root / "Database.json"
    if not db_path.exists():
        print(f"Missing {db_path}", file=sys.stderr)
        sys.exit(1)

    records = parse_records(db_path)
    print(f"Parsed {len(records)} records", file=sys.stderr)
    out = merge_database(records)
    print(f"After merge: {len(out)} records", file=sys.stderr)

    db_path.write_text(json.dumps(out, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Wrote {db_path}", file=sys.stderr)


if __name__ == "__main__":
    main()
