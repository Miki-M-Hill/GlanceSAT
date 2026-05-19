#!/usr/bin/env python3
"""Read scripts/batch_004_hooks.tsv → write scripts/batch_004_user_memory_hooks.json."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
TSV = ROOT / "batch_004_hooks.tsv"
OUT = ROOT / "batch_004_user_memory_hooks.json"

KMAP = {"s": "sound_spelling", "m": "morphology", "e": "etymology_story"}


def clamp(text: str, n: int = 140) -> str:
    text = text.strip()
    if len(text) <= n:
        return text
    cut = text[: n - 1].rsplit(" ", 1)[0]
    return cut + "…"


def main() -> None:
    out: dict[str, dict | None] = {}
    for raw in TSV.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t", 2)
        if len(parts) == 2 and parts[1] == "n":
            out[parts[0]] = None
            continue
        if len(parts) != 3:
            raise ValueError(f"Bad TSV line: {raw!r}")
        word, k, text = parts
        if k not in KMAP:
            raise ValueError(f"{word}: bad kind {k!r}")
        ct = clamp(text)
        if len(ct) > 140:
            raise ValueError(f"{word}: still >140 after clamp: {len(ct)}")
        out[word] = {"kind": KMAP[k], "text": ct}

    OUT.write_text(json.dumps(out, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    nn = sum(1 for v in out.values() if v)
    print("words", len(out), "non_null", nn, "->", OUT)


if __name__ == "__main__":
    main()
