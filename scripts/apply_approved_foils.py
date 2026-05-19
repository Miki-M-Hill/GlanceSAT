#!/usr/bin/env python3
"""Inject tonalFoilId on approved target rows in Database.json (directed edges only)."""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_ALLOWLIST = ROOT / "approved_foils.json"
DEFAULT_DB = ROOT / "GlanceSAT" / "GlanceSAT" / "Database.json"


def load_allowlist(path: Path) -> tuple[dict[str, str], dict[str, int]]:
    """Map targetId -> foilId and optional onboardingRank from approved_foils.json."""
    doc = json.loads(path.read_text(encoding="utf-8"))
    pairs = doc.get("pairs")
    if not isinstance(pairs, list):
        raise ValueError(f"Invalid allowlist: missing pairs array in {path}")
    mapping: dict[str, str] = {}
    ranks: dict[str, int] = {}
    for pair in pairs:
        if not isinstance(pair, dict):
            continue
        target_id = pair.get("targetId")
        foil_id = pair.get("foilId")
        if not target_id or not foil_id:
            continue
        target_key = str(target_id)
        if target_key in mapping and mapping[target_key] != foil_id:
            raise ValueError(f"Duplicate targetId with conflicting foil: {target_id}")
        mapping[target_key] = str(foil_id)
        rank = pair.get("onboardingRank")
        if isinstance(rank, int) and rank > 0:
            ranks[target_key] = rank
    if not mapping:
        raise ValueError("Allowlist produced zero target→foil mappings")
    return mapping, ranks


def apply_to_database(
    db_path: Path,
    target_to_foil: dict[str, str],
    pair_onboarding_rank: dict[str, int],
) -> tuple[int, int]:
    entries = json.loads(db_path.read_text(encoding="utf-8"))
    if not isinstance(entries, list):
        raise ValueError(f"Expected JSON array in {db_path}")

    foil_ids = set(target_to_foil.values())
    target_ids = set(target_to_foil.keys())
    cleared = 0
    set_count = 0

    for entry in entries:
        if not isinstance(entry, dict):
            continue
        word_id = entry.get("id")
        if word_id in target_ids:
            entry["tonalFoilId"] = target_to_foil[word_id]
            rank = pair_onboarding_rank.get(word_id)
            if rank is not None:
                entry["onboardingRank"] = rank
            elif "onboardingRank" in entry:
                del entry["onboardingRank"]
            set_count += 1
        elif "tonalFoilId" in entry:
            del entry["tonalFoilId"]
            cleared += 1
        elif word_id in foil_ids and entry.get("tonalFoilId"):
            del entry["tonalFoilId"]
            cleared += 1

    if set_count != len(target_to_foil):
        missing = target_ids - {e.get("id") for e in entries if isinstance(e, dict)}
        raise ValueError(f"Could not find target ids in database: {sorted(missing)}")

    db_path.write_text(json.dumps(entries, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return set_count, cleared


def main() -> int:
    allowlist = DEFAULT_ALLOWLIST
    db_path = DEFAULT_DB
    if len(sys.argv) > 1:
        allowlist = Path(sys.argv[1])
    if len(sys.argv) > 2:
        db_path = Path(sys.argv[2])

    mapping, ranks = load_allowlist(allowlist)
    set_count, cleared = apply_to_database(db_path, mapping, ranks)
    print(f"Applied {set_count} tonalFoilId values from {allowlist}")
    print(f"Cleared {cleared} stale tonalFoilId keys in {db_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
