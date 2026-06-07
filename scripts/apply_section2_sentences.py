#!/usr/bin/env python3
"""Apply Section 2 filler rewrites to Database.json selectively.

Only updates exampleSentence and/or alternateExampleSentence for words flagged
in docs/GlanceSAT_Sentence_Rewrite_Prompt.md SECTION 2. When a single field
needs replacement, picks the stronger of the two submitted sentences.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DB_PATH = ROOT / "GlanceSAT" / "GlanceSAT" / "Database.json"
PROMPT_PATH = ROOT / "docs" / "GlanceSAT_Sentence_Rewrite_Prompt.md"
TRANSCRIPT = Path(
    "/Users/mikihill/.cursor/projects/Users-mikihill-GlanceSAT/agent-transcripts/"
    "7aba19d7-8597-4e7f-aa13-5c1e38f00719/7aba19d7-8597-4e7f-aa13-5c1e38f00719.jsonl"
)

BANNED = ("incredibly", "completely", "massive")
SOFT_FILLERS = (
    "absolutely",
    "highly",
    "entirely",
    "utterly",
    "actually",
    "totally",
    "very",
    "extremely",
    "severely",
    "profoundly",
    "deeply",
    "truly",
    "really",
    "simply",
    "merely",
    "purely",
    "immense",
    "immensely",
    "countless",
    "endless",
    "numerous",
    "quickly",
    "rapidly",
    "suddenly",
    "strictly",
    "frequently",
    "often",
    "always",
    "never",
    "barely",
    "easily",
    "happily",
    "loudly",
    "wildly",
    "sheer",
    "several",
)

# Manual fixes for flagged sentences / wrong senses.
SENTENCE_OVERRIDES: dict[str, tuple[str, str]] = {
    "inexorable": (
        "s1",
        "The inexorable advance of the glacier slowly crushed everything standing in its path.",
    ),
    "fatuous": (
        "s2",
        "Ignoring expert financial advice, she blindly pursued a fatuous scheme to get rich quickly.",
    ),
    "appropriate": (
        "s2",
        "State officials attempted to appropriate the abandoned factory for public housing development.",
    ),
    "compound": (
        "s2",
        "Repeated shipping delays will compound the financial losses for the struggling retailer.",
    ),
}

# Patterns that indicate wrong sense for this DB entry.
WRONG_SENSE_PATTERNS: dict[str, tuple[str, ...]] = {
    "appropriate": (
        r"\bnot appropriate\b",
        r"\bappropriate attire\b",
        r"\bappropriate formal\b",
    ),
    "compound": (
        r"\bmilitary compound\b",
        r"\bisolated military compound\b",
    ),
}


def load_user_pairs() -> dict[str, tuple[str, str, str]]:
    text = None
    for line in TRANSCRIPT.read_text(encoding="utf-8").splitlines():
        if "The disgraced monarch chose to abdicate" in line:
            payload = json.loads(line)
            text = payload["message"]["content"][0]["text"]
            break
    if text is None:
        raise SystemExit("Section 2 user batch not found in transcript.")

    text = text.split("section 2:", 1)[1].strip()
    entries: dict[str, tuple[str, str, str]] = {}
    lines = text.splitlines()
    i = 0
    while i < len(lines):
        match = re.match(r"^\s*\d+\.\s+([A-Za-z]+)\s*$", lines[i])
        if not match:
            i += 1
            continue
        word = match.group(1)
        i += 1
        sentences: list[str] = []
        while i < len(lines) and len(sentences) < 2:
            stripped = lines[i].strip()
            i += 1
            if not stripped:
                continue
            if re.match(r"^\d+\.\s+[A-Za-z]+", stripped):
                i -= 1
                break
            if stripped.startswith(("Here is", "Every sentence", "following all")):
                continue
            if stripped.endswith("."):
                sentences.append(stripped)
        if len(sentences) >= 2:
            entries[word.lower()] = (word, sentences[0], sentences[1])
    return entries


def parse_section2_targets() -> dict[str, dict[str, bool]]:
    prompt = PROMPT_PATH.read_text(encoding="utf-8")
    section = prompt.split("SECTION 2")[1].split("SECTION 3")[0]
    targets: dict[str, dict[str, bool]] = {}
    for block in re.split(r"\n(?=[A-Z][a-z]+\s*\n)", section):
        match = re.match(r"^([A-Z][a-z]+)\s*\n(.*)", block, re.S)
        if not match:
            continue
        word = match.group(1)
        body = match.group(2)
        example = "[example]" in body
        alternate = "[alternate]" in body
        if example or alternate:
            targets[word.lower()] = {"example": example, "alternate": alternate}
    return targets


def apply_overrides(word_key: str, s1: str, s2: str) -> tuple[str, str]:
    if word_key not in SENTENCE_OVERRIDES:
        return s1, s2
    slot, replacement = SENTENCE_OVERRIDES[word_key]
    if slot == "s1":
        return replacement, s2
    return s1, replacement


def wrong_sense_penalty(word_key: str, sentence: str) -> int:
    patterns = WRONG_SENSE_PATTERNS.get(word_key)
    if not patterns:
        return 0
    lowered = sentence.lower()
    for pattern in patterns:
        if re.search(pattern, lowered):
            return 80
    return 0


def score_sentence(word_key: str, sentence: str) -> int:
    score = 100
    words = sentence.split()
    word_count = len(words)
    if word_count < 10 or word_count > 14:
        score -= 60
    elif word_count in (11, 12, 13):
        score += 4

    lowered = sentence.lower()
    for banned in BANNED:
        if re.search(rf"\b{re.escape(banned)}\b", lowered):
            score -= 120

    for filler in SOFT_FILLERS:
        if re.search(rf"\b{re.escape(filler)}\b", lowered):
            score -= 4

    score -= wrong_sense_penalty(word_key, sentence)

    if word_key not in lowered:
        score -= 25

    # Prefer concrete subjects over generic clichés.
    if "four-leaf clover" in lowered:
        score -= 8
    if "drowning in paperwork" in lowered:
        score -= 3

    return score


def pick_stronger(word_key: str, s1: str, s2: str) -> str:
    s1_score = score_sentence(word_key, s1)
    s2_score = score_sentence(word_key, s2)
    if s2_score > s1_score:
        return s2
    if s1_score > s2_score:
        return s1
    return s1


def main() -> int:
    pairs = load_user_pairs()
    targets = parse_section2_targets()

    missing_targets = sorted(set(targets) - set(pairs))
    if missing_targets:
        raise SystemExit(f"Missing user sentences for: {', '.join(missing_targets)}")

    with DB_PATH.open(encoding="utf-8") as handle:
        database = json.load(handle)

    db_by_key = {row["word"].strip().lower(): row for row in database}
    example_updates = 0
    alternate_updates = 0
    choices: list[str] = []

    for word_key, fields in sorted(targets.items()):
        row = db_by_key.get(word_key)
        if row is None:
            print(f"WARNING: {word_key} not in database")
            continue

        _, s1, s2 = pairs[word_key]
        s1, s2 = apply_overrides(word_key, s1, s2)

        update_example = fields["example"]
        update_alternate = fields["alternate"]

        if update_example and update_alternate:
            row["exampleSentence"] = s1
            row["alternateExampleSentence"] = s2
            example_updates += 1
            alternate_updates += 1
            continue

        if update_example:
            chosen = pick_stronger(word_key, s1, s2)
            row["exampleSentence"] = chosen
            example_updates += 1
            rejected = s2 if chosen == s1 else s1
            choices.append(
                f"{row['word']} [example]: kept ({score_sentence(word_key, chosen)}) "
                f"over ({score_sentence(word_key, rejected)})"
            )
            continue

        if update_alternate:
            chosen = pick_stronger(word_key, s1, s2)
            row["alternateExampleSentence"] = chosen
            alternate_updates += 1
            rejected = s2 if chosen == s1 else s1
            choices.append(
                f"{row['word']} [alternate]: kept ({score_sentence(word_key, chosen)}) "
                f"over ({score_sentence(word_key, rejected)})"
            )

    with DB_PATH.open("w", encoding="utf-8") as handle:
        json.dump(database, handle, indent=2, ensure_ascii=False)
        handle.write("\n")

    # Post-apply validation on touched fields.
    violations: list[str] = []
    for word_key, fields in targets.items():
        row = db_by_key[word_key]
        for field_name, enabled in (
            ("exampleSentence", fields["example"]),
            ("alternateExampleSentence", fields["alternate"]),
        ):
            if not enabled:
                continue
            sentence = row.get(field_name) or ""
            wc = len(sentence.split())
            if wc < 10 or wc > 14:
                violations.append(f"{row['word']} {field_name}: {wc} words")
            lowered = sentence.lower()
            for banned in BANNED:
                if re.search(rf"\b{re.escape(banned)}\b", lowered):
                    violations.append(f"{row['word']} {field_name}: banned '{banned}'")

    print(f"Section 2 words processed: {len(targets)}")
    print(f"exampleSentence updates: {example_updates}")
    print(f"alternateExampleSentence updates: {alternate_updates}")
    print(f"Single-field picks logged: {len(choices)}")
    if violations:
        print("\nVALIDATION FAILURES:")
        for item in violations:
            print(f"  - {item}")
        return 1

    print("\nValidation passed: all updated sentences are 10–14 words with no banned fillers.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
