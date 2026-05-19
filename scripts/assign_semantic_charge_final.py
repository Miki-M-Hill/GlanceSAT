#!/usr/bin/env python3
"""Final pass: semanticCharge + semanticChargeIntensity on Database.json and patch files."""
from __future__ import annotations

import json
import sys
from collections import Counter
from pathlib import Path

from semantic_charge_lexicon import apply_semantic_fields, validate_entries

ROOT = Path(__file__).resolve().parents[1]
DB = ROOT / "GlanceSAT" / "GlanceSAT" / "Database.json"


def process_entries(entries: list[dict]) -> int:
    return sum(1 for e in entries if apply_semantic_fields(e))


def main() -> int:
    paths = [DB, *sorted((ROOT / "GlanceSAT" / "GlanceSAT").glob("patches_batch_*.json"))]
    if len(sys.argv) > 1:
        paths = [Path(p) for p in sys.argv[1:]]

    for path in paths:
        if not path.exists():
            print(f"skip: {path}")
            continue
        with path.open(encoding="utf-8") as f:
            doc = json.load(f)
        is_patch = isinstance(doc, dict) and "entries" in doc
        entries = doc["entries"] if is_patch else doc
        n = process_entries(entries)
        errs = validate_entries(entries)
        if is_patch:
            doc["entries"] = entries
            payload = doc
        else:
            payload = entries
        with path.open("w", encoding="utf-8") as f:
            json.dump(payload, f, indent=2, ensure_ascii=False)
            f.write("\n")
        print(f"{path.name}: updated {n} rows, validation errors {len(errs)}")

    with DB.open(encoding="utf-8") as f:
        data = json.load(f)
    charges = Counter(e.get("semanticCharge") for e in data)
    intensities = Counter(
        (e.get("semanticCharge"), e.get("semanticChargeIntensity"))
        for e in data
        if e.get("semanticCharge") in ("negative", "positive")
    )
    print("\nDatabase.json distribution:")
    print("  charge:", dict(charges))
    print("  charge+intensity:", dict(sorted(intensities.items())))
    mixed = [e["word"] for e in data if e.get("semanticCharge") == "mixed"]
    print("  mixed:", mixed)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
