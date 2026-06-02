#!/usr/bin/env python3
"""Apply audited definition and example-sentence fixes to Database.json."""

from __future__ import annotations

import json
import re
from pathlib import Path

DB_PATH = Path(__file__).resolve().parents[1] / "GlanceSAT" / "GlanceSAT" / "Database.json"

DEFINITION_FIXES: dict[str, str] = {
    "Agnostic": "Believing that the existence of God cannot be proven or disproven",
    "Calumny": "A false statement meant to damage someone's reputation",
    "Caucus": "A meeting of members of a political party or faction",
    "Discretion": "Careful judgment; the quality of behaving with tact",
    "Encore": "An extra performance demanded by applause",
    "Hierarchy": "A system of ranked groups, usually by authority or status",
    "Infusion": "The process of steeping or injecting one substance into another",
    "Inoculate": "To introduce a vaccine or serum to produce immunity",
    "Inure": "To accustom someone to something difficult",
    "Juxtaposition": "The act of placing two things side by side for contrast",
    "Morass": "A swampy bog; a confusing, difficult situation",
    "Officious": "Excessively eager to offer unwanted help or advice",
    "Prepossessing": "Attractive or appealing in appearance",
    "Phlegmatic": "Calm and unemotional; slow to react",
    "Apocryphal": "Of doubtful authenticity; widely told but likely untrue",
    "Abet": "To assist or encourage, especially in wrongdoing",
    "Pathology": "A disease or disorder; abnormal bodily condition",
    "Antediluvian": "Antiquated; extremely old-fashioned",
    "Accessible": "Reachable; easy to understand or approach",
    "Accede": "To agree or yield; to assume an office",
    "Figurative": "Using figures of speech; not literal",
    "Amiable": "Friendly and good-natured",
    "Amicable": "Characterized by friendly goodwill",
    "Cloying": "Disgustingly or distastefully sweet",
    "Saccharine": "Overly or insincerely sweet",
    "Emollient": "Softening or soothing, especially to the skin",
    "Pacific": "Peaceful, calm",
    "Portent": "A sign or warning of something to come",
    "Presage": "An omen foreshadowing a future event",
    "Insipid": "Lacking flavor, vigor, or interest",
    "Tedious": "Tiresome because of length or dullness",
    "Raucous": "Harshly loud and disorderly",
    "Vociferous": "Expressing opinions loudly and insistently",
}

EXAMPLE_TOP_FIXES: dict[str, str] = {
    "Abet": "He was charged with aiding and abetting the robbery.",
    "Anathema": "Tax evasion is anathema to voters who demand honest government.",
    "Chaos": "The fire alarm plunged the hallway into brief but total chaos.",
    "Criteria": "The committee published clear criteria for evaluating grant proposals.",
    "Nefarious": "Investigators uncovered a nefarious scheme to sell stolen identities online.",
    "Permeate": "The smell of smoke began to permeate every room in the building.",
    "Profligate": "The profligate heir squandered his fortune on reckless bets within a year.",
    "Sanctimonious": "The sanctimonious critic preached thrift while hiding his own debts.",
    "Strenuous": "Training for a marathon is a strenuous challenge for any runner.",
    "Ubiquitous": "Smartphones have become ubiquitous in classrooms worldwide.",
}

# (word, sense_index) -> exampleSentence
EXAMPLE_SENSE_FIXES: dict[tuple[str, int], str] = {
    ("Abridge", 1): "Even the abridged Moby-Dick remains longer than most novels on the shelf.",
    ("Aggregate", 0): "The three branches form an aggregate more powerful than each part alone.",
    ("Annex", 1): "He studied in a quiet annex attached to the main reading room.",
    ("Buffet", 1): "Guests took food from the buffet and ate standing in the hall.",
    ("Clamor", 1): "Fans clamored for an encore, though the singer had already left the stage.",
    ("Collateral", 0): "Divorcing cost him dearly; losing her income was a harsh collateral effect.",
    ("Compound", 0): "Smoke and panic compounded the difficulty of reaching the fire escape.",
    ("Compound", 1): "Her attraction was a compound of curiosity, desire, and quiet admiration.",
    ("Compound", 2): "When fighting broke out, families retreated to the walled family compound.",
    ("Didactic", 1): "His didactic lectures pressed one viewpoint and left little room for debate.",
    ("Disdain", 0): "Older staff disdained the new hires, who were young and highly capable.",
    ("Dissent", 1): "The last juror voiced dissent, unconvinced the defendant was guilty.",
    ("Embellish", 1): "When Harry said he had done stuff on vacation, I asked him to embellish.",
    ("Eminent", 0): "The eminent scholar's lecture drew professors from across the campus.",
    ("Empirical", 0): "The study rests on empirical data gathered from controlled field trials.",
    ("Empirical", 1): "That cats hate water is empirical; I could test it on mine.",
    ("Facile", 1): "Any facile fix seemed too shallow to save a business so deep in debt.",
    ("Harangue", 1): "The teacher harangued the class about brushing teeth after chewing gum.",
    ("Impinge", 1): "New rules may impinge on fishing rights long protected by local custom.",
    ("Implement", 0): "She used a metal implement to pry the stubborn lid off the jar.",
    ("Implement", 1): "The mayor implemented a policy using cameras to catch graffiti vandals.",
    ("Incendiary", 0): "The incendiary remark during the match nearly caused a riot in the stands.",
    ("Liability", 1): "Her weak defense made Marcy a liability to the basketball team.",
    ("Manifest", 0): "The wrong sum on the board was so manifest the class laughed aloud.",
    ("Moderate", 1): "Mr. Park chose a moderate position between liberal and conservative extremes.",
    ("Reconcile", 1): "She tried to reconcile her skepticism with the UFO she had filmed.",
    ("Relegate", 1): "After spilling wine on a guest, the waiter was relegated to the worst shift.",
    ("Repulse", 1): "Lacy repulsed Jack's attempt to kiss her with a sharp turn away.",
}


def word_count(s: str) -> int:
    return len(re.findall(r"[A-Za-z']+", s))


def apply_fixes(entries: list[dict]) -> tuple[int, int]:
    def_count = 0
    ex_count = 0

    for entry in entries:
        word = entry.get("word", "")

        if word in DEFINITION_FIXES:
            new_def = DEFINITION_FIXES[word]
            if entry.get("definition") is not None:
                entry["definition"] = new_def
            elif entry.get("senses"):
                entry["senses"][0]["definition"] = new_def
            else:
                entry["definition"] = new_def
            def_count += 1

        if word in EXAMPLE_TOP_FIXES:
            entry["exampleSentence"] = EXAMPLE_TOP_FIXES[word]
            ex_count += 1

        senses = entry.get("senses") or []
        for idx, sense in enumerate(senses):
            key = (word, idx)
            if key in EXAMPLE_SENSE_FIXES:
                sense["exampleSentence"] = EXAMPLE_SENSE_FIXES[key]
                ex_count += 1
                if idx == 0 and entry.get("exampleSentence"):
                    entry["exampleSentence"] = EXAMPLE_SENSE_FIXES[key]

    return def_count, ex_count


def validate(entries: list[dict]) -> list[str]:
    errors: list[str] = []
    trunc = re.compile(
        r"\b(for|or|the|a|an|to|of|in|on|at|by|with|nor|and|same|one|other|good)\.$",
        re.I,
    )

    for entry in entries:
        word = entry["word"]
        defs = []
        if entry.get("definition"):
            defs.append(entry["definition"])
        for s in entry.get("senses") or []:
            if s.get("definition"):
                defs.append(s["definition"])
        for d in defs:
            if trunc.search(d.strip()):
                errors.append(f"truncated definition: {word}: {d}")

        examples = []
        if entry.get("exampleSentence"):
            examples.append(entry["exampleSentence"])
        for s in entry.get("senses") or []:
            if s.get("exampleSentence"):
                examples.append(s["exampleSentence"])
        for ex in examples:
            if word_count(ex) > 16:
                errors.append(f"example >16w: {word} ({word_count(ex)}): {ex[:60]}...")

    return errors


def main() -> None:
    with DB_PATH.open(encoding="utf-8") as f:
        entries = json.load(f)

    def_n, ex_n = apply_fixes(entries)
    issues = validate(entries)

    with DB_PATH.open("w", encoding="utf-8") as f:
        json.dump(entries, f, indent=2, ensure_ascii=False)
        f.write("\n")

    print(f"Updated definitions: {def_n}")
    print(f"Updated examples: {ex_n}")
    if issues:
        print("Remaining issues:")
        for issue in issues[:30]:
            print(f"  - {issue}")
        if len(issues) > 30:
            print(f"  ... +{len(issues) - 30} more")
    else:
        print("Validation passed.")


if __name__ == "__main__":
    main()
