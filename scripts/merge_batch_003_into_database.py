#!/usr/bin/env python3
"""Merge patches_batch_003.json `entries` into Database.json by matching `id` (full replace)."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DB = ROOT / "GlanceSAT" / "GlanceSAT" / "Database.json"
PATCH = ROOT / "GlanceSAT" / "GlanceSAT" / "patches_batch_003.json"


def main() -> None:
    with PATCH.open(encoding="utf-8") as f:
        pack = json.load(f)
    entries = pack["entries"]
    pmap = {e["id"]: e for e in entries}

    with DB.open(encoding="utf-8") as f:
        data = json.load(f)

    replaced = 0
    for i, row in enumerate(data):
        rid = row.get("id")
        if rid in pmap:
            data[i] = pmap[rid]
            replaced += 1

    with DB.open("w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")

    print(f"Merged {replaced} rows (expected {len(entries)}).")

    from lexical_normalize import normalize_file

    normalize_file(DB)
    print("Normalized flat lexical fields from senses[0] where needed.")


if __name__ == "__main__":
    main()
