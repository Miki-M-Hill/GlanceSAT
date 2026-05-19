#!/usr/bin/env python3
"""Emit scripts/batch_004_hooks.tsv from batch_004_hook_table.ROWS + Database.json order."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "batch_004_hooks.tsv"
DB = ROOT.parent / "GlanceSAT" / "GlanceSAT" / "Database.json"

from batch_004_hook_table import ROWS  # noqa: E402


def main() -> None:
    with DB.open(encoding="utf-8") as f:
        data = json.load(f)
    batch = data[750:]
    words = [r["word"] for r in batch]
    if len(words) != len(ROWS):
        raise SystemExit(f"Word count {len(words)} != ROWS {len(ROWS)}")

    lines: list[str] = []
    for w, spec in zip(words, ROWS, strict=True):
        if spec is None:
            lines.append(f"{w}\tn")
        else:
            k, text = spec
            lines.append(f"{w}\t{k}\t{text}")

    OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("wrote", OUT, "rows", len(lines))

    for raw, w in zip(lines, words, strict=True):
        if raw.split("\t", 1)[0] != w:
            raise AssertionError((w, raw))


if __name__ == "__main__":
    main()
