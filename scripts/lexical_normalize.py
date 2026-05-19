#!/usr/bin/env python3
"""Denormalize senses[0] onto flat lexical fields when root fields are empty.

Keeps `senses[]` intact for multi-meaning UI. Safe to run repeatedly.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any


def _empty(value: Any) -> bool:
    if value is None:
        return True
    if isinstance(value, str):
        return not value.strip()
    if isinstance(value, list):
        return len(value) == 0
    return False


def normalize_entry(entry: dict[str, Any]) -> bool:
    """Backfill flat fields from senses[0]. Returns True if entry was modified."""
    senses = entry.get("senses")
    if not isinstance(senses, list) or not senses:
        return False
    first = senses[0]
    if not isinstance(first, dict):
        return False

    changed = False
    if _empty(entry.get("definition")) and not _empty(first.get("definition")):
        entry["definition"] = first["definition"]
        changed = True
    if _empty(entry.get("exampleSentence")) and not _empty(first.get("exampleSentence")):
        entry["exampleSentence"] = first["exampleSentence"]
        changed = True
    if _empty(entry.get("partOfSpeech")) and not _empty(first.get("partOfSpeech")):
        entry["partOfSpeech"] = first["partOfSpeech"]
        changed = True
    if _empty(entry.get("synonyms")) and not _empty(first.get("synonyms")):
        entry["synonyms"] = first["synonyms"]
        changed = True
    return changed


def normalize_entries(entries: list[dict[str, Any]]) -> int:
    return sum(1 for e in entries if normalize_entry(e))


def validate_entries(entries: list[dict[str, Any]]) -> list[str]:
    errors: list[str] = []
    for entry in entries:
        word = entry.get("word") or entry.get("id") or "?"
        has_flat = not _empty(entry.get("definition"))
        senses = entry.get("senses") or []
        has_senses = isinstance(senses, list) and any(
            isinstance(s, dict) and not _empty(s.get("definition")) for s in senses
        )
        if not has_flat and not has_senses:
            errors.append(f"{word}: no definition in flat fields or senses[]")
    return errors


def load_json_array_or_patch(path: Path) -> tuple[list[dict[str, Any]], bool]:
    """Returns (entries, is_patch_wrapper)."""
    with path.open(encoding="utf-8") as f:
        doc = json.load(f)
    if isinstance(doc, list):
        return doc, False
    if isinstance(doc, dict) and isinstance(doc.get("entries"), list):
        return doc["entries"], True
    raise ValueError(f"Unsupported JSON shape: {path}")


def save_json(path: Path, entries: list[dict[str, Any]], is_patch_wrapper: bool, wrapper: dict | None) -> None:
    if is_patch_wrapper:
        if wrapper is None:
            raise ValueError("patch wrapper required")
        wrapper["entries"] = entries
        payload = wrapper
    else:
        payload = entries
    with path.open("w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2, ensure_ascii=False)
        f.write("\n")


def normalize_file(path: Path) -> int:
    entries, is_patch = load_json_array_or_patch(path)
    wrapper = None
    if is_patch:
        with path.open(encoding="utf-8") as f:
            wrapper = json.load(f)
    n = normalize_entries(entries)
    if n:
        save_json(path, entries, is_patch, wrapper)
    return n


def main(argv: list[str]) -> int:
    root = Path(__file__).resolve().parents[1]
    paths = [Path(p) for p in argv[1:]] if len(argv) > 1 else [
        root / "GlanceSAT" / "GlanceSAT" / "Database.json",
        *sorted((root / "GlanceSAT" / "GlanceSAT").glob("patches_batch_*.json")),
    ]
    total = 0
    for path in paths:
        if not path.exists():
            print(f"skip (missing): {path}")
            continue
        n = normalize_file(path)
        entries, _ = load_json_array_or_patch(path)
        errs = validate_entries(entries)
        print(f"{path.name}: normalized {n} row(s), validation errors: {len(errs)}")
        for err in errs[:5]:
            print(f"  - {err}")
        total += n
    return 0 if total >= 0 else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
