#!/usr/bin/env python3
"""
Find candidate Semantic Foil pairs in Database.json.

A valid pair must:
  - share the same partOfSpeech (no noun/verb mismatches),
  - share at least two normalized synonyms (overlap count > 1),
  - have different semanticCharge values (e.g. negative vs neutral).

Results are written to CSV for human review only; Database.json is not modified.
"""
from __future__ import annotations

import argparse
import csv
import json
import sys
from dataclasses import dataclass
from itertools import combinations
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DB = ROOT / "GlanceSAT" / "GlanceSAT" / "Database.json"
DEFAULT_OUT = ROOT / "candidate_foils.csv"

CSV_COLUMNS = [
    "Target ID",
    "Target Word",
    "Target Charge",
    "Foil ID",
    "Foil Word",
    "Foil Charge",
    "Overlap Count",
    "Overlapping Synonyms",
]


MIN_SYNONYM_OVERLAP = 2


@dataclass(frozen=True)
class WordRecord:
    id: str
    word: str
    part_of_speech: str
    semantic_charge: str
    synonyms: frozenset[str]


def normalize_synonyms(raw: object) -> frozenset[str]:
    if not isinstance(raw, list):
        return frozenset()
    out: set[str] = set()
    for item in raw:
        if not isinstance(item, str):
            continue
        cleaned = item.strip().lower()
        if cleaned:
            out.add(cleaned)
    return frozenset(out)


def normalize_charge(raw: object) -> str:
    if not isinstance(raw, str):
        return ""
    return raw.strip().lower()


def normalize_part_of_speech(raw: object) -> str:
    if not isinstance(raw, str):
        return ""
    return raw.strip().lower()


def load_words(path: Path) -> list[WordRecord]:
    with path.open(encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, list):
        raise ValueError(f"Expected JSON array in {path}")

    records: list[WordRecord] = []
    skipped = 0
    for entry in data:
        if not isinstance(entry, dict):
            skipped += 1
            continue
        word_id = entry.get("id")
        headword = entry.get("word")
        charge = normalize_charge(entry.get("semanticCharge"))
        pos = normalize_part_of_speech(entry.get("partOfSpeech"))
        if not word_id or not headword or not charge or not pos:
            skipped += 1
            continue
        records.append(
            WordRecord(
                id=str(word_id),
                word=str(headword).strip(),
                part_of_speech=pos,
                semantic_charge=charge,
                synonyms=normalize_synonyms(entry.get("synonyms")),
            )
        )
    if skipped:
        print(
            f"Skipped {skipped} entries missing id, word, partOfSpeech, or semanticCharge.",
            file=sys.stderr,
        )
    return records


def is_valid_foil_pair(a: WordRecord, b: WordRecord) -> frozenset[str] | None:
    """Return shared synonyms if the pair passes all guardrails, else None."""
    if a.part_of_speech != b.part_of_speech:
        return None
    if a.semantic_charge == b.semantic_charge:
        return None
    overlap = a.synonyms & b.synonyms
    if len(overlap) < MIN_SYNONYM_OVERLAP:
        return None
    return overlap


def find_foil_candidates(words: list[WordRecord]) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    for a, b in combinations(words, 2):
        overlap = is_valid_foil_pair(a, b)
        if overlap is None:
            continue
        overlap_sorted = sorted(overlap)  # len >= MIN_SYNONYM_OVERLAP
        rows.append(
            {
                "Target ID": a.id,
                "Target Word": a.word,
                "Target Charge": a.semantic_charge,
                "Foil ID": b.id,
                "Foil Word": b.word,
                "Foil Charge": b.semantic_charge,
                "Overlap Count": len(overlap_sorted),
                "Overlapping Synonyms": "|".join(overlap_sorted),
            }
        )
    rows.sort(key=lambda row: (-int(row["Overlap Count"]), row["Target Word"], row["Foil Word"]))
    return rows


def write_csv(rows: list[dict[str, object]], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=CSV_COLUMNS)
        writer.writeheader()
        writer.writerows(rows)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Export semantic foil candidate pairs from Database.json to CSV."
    )
    parser.add_argument(
        "--input",
        type=Path,
        default=DEFAULT_DB,
        help=f"Path to Database.json (default: {DEFAULT_DB})",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUT,
        help=f"Output CSV path (default: {DEFAULT_OUT})",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not args.input.is_file():
        print(f"Error: input file not found: {args.input}", file=sys.stderr)
        return 1

    words = load_words(args.input)
    rows = find_foil_candidates(words)
    write_csv(rows, args.output)

    print(f"Loaded {len(words)} words from {args.input}")
    print(f"Wrote {len(rows)} candidate pairs to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
