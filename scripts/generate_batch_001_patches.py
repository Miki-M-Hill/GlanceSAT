#!/usr/bin/env python3
"""
Rubric v1.1 - batch_001: first 250 rows of Database.json.

`memoryHook` values come from **scripts/batch_001_user_memory_hooks.json**
(user-curated sound bridges, morphology, etymology stories, or null).

Output: patches_batch_001.json with:
  - `entries`: 250 FULL word objects (copy-merge into Database.json by `id`)
  - `batch_stats`, `flags`

Rubric §D5 hook ceiling (≤30% non-null) is reported in `batch_stats`; this batch
may exceed it when the author assigns hooks to most rows on purpose.
"""
from __future__ import annotations

import copy
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DB = ROOT / "GlanceSAT" / "GlanceSAT" / "Database.json"
OUT = ROOT / "GlanceSAT" / "GlanceSAT" / "patches_batch_001.json"
USER_HOOKS_JSON = ROOT / "scripts" / "batch_001_user_memory_hooks.json"

HOOK_CEILING_FRAC = 0.30
BATCH_SIZE = 250

SLUG_TO_DOMAIN: dict[str, str] = {
    "social-behavior": "human_social",
    "emotion-character": "self_character",
    "emotional": "self_character",
    "emotion": "self_character",
    "intellect-judgment": "thought_language",
    "logic-reasoning": "thought_language",
    "language-communication": "thought_language",
    "academic": "thought_language",
    "general-academic": "thought_language",
    "formal-register": "thought_language",
    "language": "thought_language",
    "perception-quality": "thought_language",
    "science-engineering": "science_world",
    "science": "science_world",
    "environment": "science_world",
    "science-nature": "science_world",
    "health-body": "science_world",
    "science-method": "science_world",
    "law-ethics": "power_culture",
    "politics-power": "power_culture",
    "politics-law": "power_culture",
    "legal": "power_culture",
    "political": "power_culture",
    "conflict-power": "power_culture",
    "arts-literature": "power_culture",
    "literary": "power_culture",
    "arts": "power_culture",
    "religion-philosophy": "power_culture",
    "religion": "power_culture",
    "history": "power_culture",
    "business-economy": "power_culture",
    "commerce": "power_culture",
    "food-culture": "power_culture",
}

NEGATIVE = {
    "abase", "abhor", "abject", "abjure", "abscond", "acerbic", "acrimony", "admonish", "adverse",
    "affront", "aggrandize", "alias", "anathema", "anarchist", "anguish", "animosity", "antagonism",
    "antipathy", "appalling", "arbitrary", "arrogate", "aspersion", "assail", "atrocity", "avarice",
    "balk", "bane", "berate", "bereft", "bias", "bilk", "blight", "brazen", "brusque", "cacophony",
    "calumny", "carp", "censure", "chastise", "chide", "coerce", "collusion", "complacency",
    "complicit",
}
POSITIVE = {
    "acclaim", "accolade", "accommodating", "adept", "adroit", "affable", "alleviate", "ameliorate",
    "amiable", "amicable", "approbation", "auspicious", "benevolent", "benign", "boon", "camaraderie",
    "candor", "commendation", "compliment", "conciliatory", "clemency",
}
MIXED = {"ambivalent", "capricious", "mercurial", "zealous"}


def load_user_hooks() -> dict[str, dict | None]:
    if not USER_HOOKS_JSON.is_file():
        raise FileNotFoundError(f"Missing {USER_HOOKS_JSON}")
    with USER_HOOKS_JSON.open(encoding="utf-8") as f:
        raw: dict = json.load(f)
    out: dict[str, dict | None] = {}
    for word, val in raw.items():
        if val is None:
            out[word] = None
        else:
            kind = val.get("kind")
            text = (val.get("text") or "").strip()
            if kind not in ("sound_spelling", "morphology", "etymology_story"):
                raise ValueError(f"{word}: invalid kind {kind!r}")
            if not text:
                raise ValueError(f"{word}: empty text")
            if len(text) > 140:
                raise ValueError(f"{word}: hook text {len(text)} chars (max 140)")
            out[word] = {"kind": kind, "text": text}
    return out


def passage_domain(slug: str) -> str:
    s = (slug or "").strip().lower()
    return SLUG_TO_DOMAIN.get(s, "thought_language")


def semantic_charge(word: str) -> str:
    from semantic_charge_lexicon import semantic_charge_for_word

    return semantic_charge_for_word(word)


def apply_semantic_charge_fields(full: dict) -> None:
    from semantic_charge_lexicon import apply_semantic_fields

    apply_semantic_fields(full)


def shorten_definition(text: str) -> str | None:
    if not text or len(text) <= 60:
        return None
    t = text.strip()
    cut = t[:57].rsplit(" ", 1)[0]
    if len(cut) < 20:
        cut = t[:60]
    while len(cut) > 60:
        cut = cut.rsplit(" ", 1)[0]
    if not cut.endswith((".", "!", "?")):
        cut = cut.rstrip(",; ") + "."
    return cut if len(cut) <= 60 else None


def memory_hooks_for_batch(batch: list[dict], user: dict[str, dict | None], flags: list[dict]) -> dict[str, dict | None]:
    """Map each row's `word` to memoryHook from user JSON; flag missing keys."""
    out: dict[str, dict | None] = {}
    for row in batch:
        w = row["word"]
        if w not in user:
            flags.append({"id": row.get("id"), "word": w, "reason": "Word missing from batch_001_user_memory_hooks.json"})
            out[w] = None
        else:
            hook = user[w]
            out[w] = copy.deepcopy(hook) if hook else None
    return out


def main() -> None:
    with DB.open(encoding="utf-8") as f:
        data = json.load(f)
    batch = data[:BATCH_SIZE]
    max_hooks = int(BATCH_SIZE * HOOK_CEILING_FRAC)

    user_hooks = load_user_hooks()
    flags: list[dict] = []
    hook_by_word = memory_hooks_for_batch(batch, user_hooks, flags)

    entries: list[dict] = []

    for row in batch:
        full = copy.deepcopy(row)
        word = full["word"]
        slug = full.get("category", "")

        from passage_domain_lexicon import apply_passage_domain

        apply_passage_domain(full)
        apply_semantic_charge_fields(full)

        defn = full.get("definition") or ""
        if not defn.strip():
            flags.append({"id": full["id"], "word": word, "reason": "Missing definition (§G/K)."})
        else:
            short = shorten_definition(defn)
            if short:
                full["definition"] = short

        mh = hook_by_word.get(word)
        full["memoryHook"] = mh

        entries.append(full)

    non_null = sum(1 for e in entries if e.get("memoryHook"))
    stats = {
        "batchId": "batch_001",
        "count": BATCH_SIZE,
        "nonNullHooksInBatch": non_null,
        "hookCeiling": max_hooks,
        "hookSource": str(USER_HOOKS_JSON.relative_to(ROOT)),
        "cumulativeWordsProcessedAfterBatch": BATCH_SIZE,
        "cumulativeNonNullHooksAfterBatch": non_null,
        "cumulativeNonNullHookRateAfterBatch": round(non_null / BATCH_SIZE, 4),
        "ceilingOk": non_null <= max_hooks,
        "note": "entries[] = full objects; merge into Database.json by matching id.",
    }
    if not stats["ceilingOk"]:
        stats["ceilingNote"] = (
            f"Rubric section D5 ceiling is {max_hooks} non-null hooks for {BATCH_SIZE} rows; "
            "this batch intentionally includes more because hooks are author-curated in JSON."
        )

    out_obj = {
        "_readme": "Use entries[] as full word records. Merge each object into Database.json by id (replace matching element).",
        "entries": entries,
        "batch_stats": stats,
        "flags": flags,
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with OUT.open("w", encoding="utf-8") as f:
        json.dump(out_obj, f, indent=2, ensure_ascii=False)
        f.write("\n")

    print(json.dumps(stats, indent=2))
    print("written", OUT)


if __name__ == "__main__":
    main()
