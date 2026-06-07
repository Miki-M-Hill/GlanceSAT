#!/usr/bin/env python3
"""Validate and fix all three sentences per word in Database.json."""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DB_PATH = ROOT / "GlanceSAT" / "GlanceSAT" / "Database.json"
REPORT_PATH = ROOT / "docs" / "sentence_validation_report.json"

MAX_WORDS = 15
BANNED_FILLERS = ("incredibly", "completely", "massive")
PG13_PATTERN = re.compile(
    r"\b("
    r"murder(?:ed|s|ing)?|brutally|gore|naked|nude|sexual|rape|suicide|torture(?:d|s)?|"
    r"genocide|mutilat\w*|profuse amount of blood|blood on the"
    r")\b",
    re.I,
)

# Explicit rewrites keyed as "Word|field".
EXPLICIT_FIXES: dict[str, str] = {
    # --- Length > 15 (quizSentence) ---
    "Encumber|quizSentence": (
        "Do not encumber yourself with heavy luggage on our long walking tour."
    ),
    "Expedient|quizSentence": (
        "He chose the most expedient route to reach the hospital before visiting hours ended."
    ),
    "Expiate|quizSentence": (
        "He donated half his wealth to charity to expiate his past corporate misconduct."
    ),
    "Fervent|quizSentence": (
        "Fervent supporters stood in freezing rain just to glimpse the visiting president."
    ),
    "Fetter|quizSentence": (
        "The guards used heavy iron chains to fetter the prisoner to the stone wall."
    ),
    "Forage|quizSentence": (
        "Lost hikers had to forage for edible berries and nuts in the dense forest."
    ),
    "Forsake|quizSentence": (
        "The devoted monk chose to forsake his worldly possessions for a life of prayer."
    ),
    "Insipid|quizSentence": (
        "The hospital food was so insipid that visitors brought spices from home."
    ),
    "Inveterate|quizSentence": (
        "As an inveterate liar, he lied even about what he ate for breakfast."
    ),
    "Mundane|quizSentence": (
        "Sorting laundry is one mundane chore I complete every Sunday morning."
    ),
    "Nadir|quizSentence": (
        "Losing his job and house on the same day marked the nadir of his career."
    ),
    "Oscillate|quizSentence": (
        "The fan is designed to oscillate so cool air reaches every corner."
    ),
    "Ostensible|quizSentence": (
        "His ostensible reason for visiting was to borrow a tool, not to socialize."
    ),
    "Pellucid|quizSentence": (
        "The shallow tropical water was so pellucid we could see coins on the bottom."
    ),
    "Placate|quizSentence": (
        "He bought flowers to placate his partner after forgetting their anniversary dinner."
    ),
    "Ruminate|quizSentence": (
        "She needed several days to ruminate on the job offer before responding."
    ),
    "Semaphore|quizSentence": (
        "The sailor used bright orange flags to send a semaphore message to the ship."
    ),
    "Serendipity|quizSentence": (
        "Finding her lost ring in the garden years later was pure serendipity."
    ),
    "Stoic|quizSentence": (
        "The stoic athlete showed no emotion despite the painful injury during the match."
    ),
    "Temerity|quizSentence": (
        "She had the temerity to demand a raise after losing the firm's biggest client."
    ),
    "Tenuous|quizSentence": (
        "The bridge relied on a tenuous system of rusting cables that looked near collapse."
    ),
    "Tortuous|quizSentence": (
        "The tortuous maze of medieval streets makes it easy to get lost downtown."
    ),
    "Trite|quizSentence": (
        "The commencement speech offered trite advice about following dreams and reaching higher."
    ),
    "Validate|quizSentence": (
        "You must stamp your parking ticket at the desk to validate it for free exit."
    ),
    "Venerable|quizSentence": (
        "The venerable oak tree had shaded the town square for over two centuries."
    ),
    "Vocation|quizSentence": (
        "Nursing is not merely a job to her; she treats it as a lifelong vocation."
    ),
    "Wallow|quizSentence": (
        "Pigs wallow in cool mud to protect their sensitive skin from the hot sun."
    ),
    "Wane|quizSentence": (
        "The campfire's bright glow began to wane as the logs burned to embers."
    ),
    "Winsome|quizSentence": (
        "The child's winsome smile convinced her grandfather to buy her an ice cream."
    ),
    "Wistful|quizSentence": (
        "He cast a wistful glance at his old high school while leaving his hometown."
    ),
    "Zenith|quizSentence": (
        "At the zenith of his career, the actor won three Academy Awards in one night."
    ),
    # --- Filler + length (quizSentence) ---
    "Abridge|quizSentence": (
        "The publisher decided to abridge the lengthy novel for younger readers."
    ),
    "Accommodating|quizSentence": (
        "The hotel staff was accommodating when we arrived late after the delayed flight."
    ),
    "Aggrandize|quizSentence": (
        "The dictator built towering statues to aggrandize his own legacy."
    ),
    "Amiable|quizSentence": (
        "The amiable tour guide made our trip enjoyable and easy to follow."
    ),
    "Bereft|quizSentence": (
        "The grieving widow felt bereft of comfort after the funeral."
    ),
    "Catalog|quizSentence": (
        "The librarian worked tirelessly to catalog the new book donation."
    ),
    "Chronicle|quizSentence": (
        "This thick volume is a detailed chronicle of the Roman Empire."
    ),
    "Coherent|quizSentence": (
        "The exhausted speaker was unable to form a coherent sentence."
    ),
    "Colossus|quizSentence": (
        "The ancient Colossus of Rhodes was a bronze statue honoring the sun god."
    ),
    "Commodious|quizSentence": (
        "The commodious living room had plenty of space for a large sectional couch."
    ),
    "Conflagration|quizSentence": (
        "The dropped cigarette started a conflagration that destroyed the forest."
    ),
    "Debauch|quizSentence": (
        "The lottery winner allowed endless parties to debauch his orderly life."
    ),
    "Deleterious|quizSentence": (
        "Smoking has deleterious effects on your respiratory system over time."
    ),
    "Desiccated|quizSentence": (
        "The desert sun left the abandoned fruit desiccated and hard as rock."
    ),
    "Desolate|quizSentence": (
        "The desolate landscape of the moon is devoid of life or color."
    ),
    "Destitute|quizSentence": (
        "The hurricane left thousands of families homeless and destitute."
    ),
    "Disavow|quizSentence": (
        "The politician rushed to disavow any connection to the bribery scandal."
    ),
    "Discrepancy|quizSentence": (
        "The auditor found a discrepancy between the bank statements and the ledger."
    ),
    "Disparate|quizSentence": (
        "The support group brought together people from disparate walks of life."
    ),
    "Disseminate|quizSentence": (
        "The internet makes it easy to disseminate information across the globe."
    ),
    "Dissuade|quizSentence": (
        "I tried to dissuade my brother from buying that expensive sports car."
    ),
    "Docile|quizSentence": (
        "The normally wild horse became docile after months of gentle training."
    ),
    "Elaborate|quizSentence": (
        "The thieves planned an elaborate heist involving lasers and grappling hooks."
    ),
    "Enamor|quizSentence": (
        "The charming coastal town managed to enamor the visiting tourists."
    ),
    "Ennui|quizSentence": (
        "The wealthy heir suffered from ennui, bored by his luxurious routine."
    ),
    "Entail|quizSentence": (
        "Adopting a puppy will entail a serious commitment of your time and energy."
    ),
    "Equivocal|quizSentence": (
        "The politician gave an equivocal answer that dodged the reporter's question."
    ),
    "Euphoric|quizSentence": (
        "The winning team felt euphoric as they lifted the championship trophy."
    ),
    "Execrable|quizSentence": (
        "The harsh critic called the new blockbuster film an execrable piece of trash."
    ),
    "Exonerate|quizSentence": (
        "The DNA evidence was enough to exonerate the wrongfully convicted man."
    ),
    "Extol|quizSentence": (
        "The nutritionist continues to extol the health benefits of eating dark leafy greens."
    ),
    "Exult|quizSentence": (
        "The crowd began to exult wildly when the home team scored the winning goal."
    ),
    "Fatuous|quizSentence": (
        "The arrogant politician made a fatuous comment that alienated his voters."
    ),
    "Fecund|quizSentence": (
        "The fecund river valley produces abundant harvests of wheat every year."
    ),
    "Flabbergasted|quizSentence": (
        "I was flabbergasted when I saw the outrageous total on my restaurant receipt."
    ),
    "Forlorn|quizSentence": (
        "The abandoned puppy looked forlorn sitting alone in the cold, pouring rain."
    ),
    "Fortitude|quizSentence": (
        "The soldier showed fortitude while enduring hardship during active combat."
    ),
    "Fortuitous|quizSentence": (
        "The fortuitous discovery of the gold vein transformed the struggling miner."
    ),
    "Fractious|quizSentence": (
        "The fractious toddler threw a tantrum in the middle of the grocery store."
    ),
    "Frugal|quizSentence": (
        "The frugal student saved money by eating simple, inexpensive meals."
    ),
    "Impassive|quizSentence": (
        "The royal guard remained impassive despite the teasing tourists."
    ),
    "Impervious|quizSentence": (
        "My new winter coat is impervious to the freezing wind."
    ),
    "Meritorious|quizSentence": (
        "The soldier received a medal for his meritorious conduct in battle."
    ),
    "Oblivious|quizSentence": (
        "He was oblivious to the fact that his shirt was on inside out."
    ),
    "Obsolete|quizSentence": (
        "The invention of the digital calculator made the slide rule obsolete."
    ),
    "Onerous|quizSentence": (
        "Filling out fifty pages of tax paperwork is an onerous responsibility."
    ),
    "Perplex|quizSentence": (
        "The complicated riddle managed to perplex the escape room participants."
    ),
    "Profligate|quizSentence": (
        "The profligate heir blew through his entire inheritance in less than two years."
    ),
    "Protean|quizSentence": (
        "The protean actor transformed into six different characters in one play."
    ),
    "Puerile|quizSentence": (
        "Throwing spitballs at the substitute teacher is puerile behavior for a high schooler."
    ),
    "Rancid|quizSentence": (
        "The butter left out overnight tasted rancid, so she discarded it immediately."
    ),
    "Rash|quizSentence": (
        "Quitting your job before finding a new one is a rash financial decision."
    ),
    "Reproach|quizSentence": (
        "Her spotless professional record is beyond any reproach."
    ),
    "Resolute|quizSentence": (
        "She remained resolute in her decision to climb the mountain without oxygen."
    ),
    "Revel|quizSentence": (
        "The victorious football team went out to revel in their championship win."
    ),
    "Rife|quizSentence": (
        "The corrupt police department was rife with bribery and scandal."
    ),
    "Saccharine|quizSentence": (
        "The movie's saccharine soundtrack ruined the serious tone of the dramatic scene."
    ),
    "Scrupulous|quizSentence": (
        "The scrupulous accountant caught an error of three cents in the ledger."
    ),
    "Solvent|quizSentence": (
        "The business remained financially solvent despite the global economic recession."
    ),
    "Somnolent|quizSentence": (
        "The warm fire and soft music left the travelers feeling somnolent before bedtime."
    ),
    "Stolid|quizSentence": (
        "The stolid bouncer stood at the club entrance with a blank, unreadable expression."
    ),
    "Strenuous|quizSentence": (
        "Chopping firewood all afternoon is strenuous physical labor."
    ),
    "Stupefy|quizSentence": (
        "The magician's ability to levitate a car managed to stupefy the audience."
    ),
    "Surfeit|quizSentence": (
        "A surfeit of apples caused the orchard to drop its prices dramatically."
    ),
    "Tedious|quizSentence": (
        "Peeling fifty pounds of potatoes by hand is a tedious chore."
    ),
    "Tome|quizSentence": (
        "The library holds a leather-bound tome detailing the town's history."
    ),
    "Turgid|quizSentence": (
        "The academic paper was so turgid that I reread every sentence twice."
    ),
    "Vapid|quizSentence": (
        "The pop song featured a catchy beat but vapid and meaningless lyrics."
    ),
    "Vex|quizSentence": (
        "The difficult crossword puzzle continued to vex me for the entire morning."
    ),
    "Viscous|quizSentence": (
        "Cold honey is viscous and pours very slowly from the plastic bear bottle."
    ),
    "Refurbish|quizSentence": (
        "She bought an old dresser at a garage sale and planned to refurbish it."
    ),
    "Rectitude|quizSentence": (
        "The judge was a model of moral rectitude who refused every offer of a bribe."
    ),
    # --- PG-13 ---
    "Avenge|quizSentence": (
        "The hero swore to avenge the unjust defeat of his family."
    ),
    "Avenge|exampleSentence": (
        "The prince swore to avenge the wrong done to his royal family."
    ),
    "Coagulate|quizSentence": (
        "Exposure to the air caused the spilled latex paint to rapidly coagulate."
    ),
    "Coagulate|alternateExampleSentence": (
        "The patient lacked the necessary platelets to properly coagulate the wound."
    ),
    "Inquisitor|alternateExampleSentence": (
        "The attorney acted like a relentless inquisitor during the tense courtroom cross-examination."
    ),
    "Profuse|exampleSentence": (
        "The accident left a profuse amount of water on the concrete floor."
    ),
    "Astute|alternateExampleSentence": (
        "Her astute observations helped the committee quickly solve the complex budget crisis."
    ),
    "Insipid|alternateExampleSentence": (
        "The food critic dismissed the chef's new soup as painfully insipid."
    ),
}


def word_count(sentence: str) -> int:
    return len(sentence.split())


def target_word_present(word: str, sentence: str) -> bool:
    base = word.lower()
    if base in sentence.lower():
        return True
    stems = (
        base,
        base + "s",
        base + "es",
        base + "ed",
        base + "ing",
        base + "ly",
        base.rstrip("e") + "ing",
        base.rstrip("e") + "ed",
        base.rstrip("y") + "ied",
        base.rstrip("e") + "ion",
        base.rstrip("y") + "ies",
    )
    if base.endswith("ify"):
        stems = (*stems, base[:-1] + "ies", base + "ing")
    lowered = sentence.lower()
    return any(re.search(rf"\b{re.escape(stem)}\b", lowered) for stem in stems if stem)


def has_banned_filler(sentence: str) -> bool:
    lowered = sentence.lower()
    return any(re.search(rf"\b{re.escape(filler)}\b", lowered) for filler in BANNED_FILLERS)


def validate_sentence(word: str, sentence: str) -> list[str]:
    issues: list[str] = []
    if not sentence.strip():
        issues.append("missing")
        return issues
    if word_count(sentence) > MAX_WORDS:
        issues.append(f"length>{MAX_WORDS}")
    if not target_word_present(word, sentence):
        issues.append("missing_target_word")
    if has_banned_filler(sentence):
        issues.append("banned_filler")
    if PG13_PATTERN.search(sentence):
        issues.append("pg13")
    return issues


def resolve_sentence(word: str, field: str, sentence: str) -> tuple[str, bool]:
    key = f"{word}|{field}"
    if key in EXPLICIT_FIXES:
        return EXPLICIT_FIXES[key], True
    if not sentence.strip():
        return sentence, False
    issues = validate_sentence(word, sentence)
    if not issues:
        return sentence, False
    return sentence, False


def main() -> int:
    with DB_PATH.open(encoding="utf-8") as handle:
        database = json.load(handle)

    report: list[dict] = []
    total_modified = 0
    remaining_issues: list[str] = []

    for row in database:
        word = row["word"]
        modified_fields: list[str] = []
        resolved: dict[str, str] = {}

        for field in ("quizSentence", "exampleSentence", "alternateExampleSentence"):
            original = (row.get(field) or "").strip()
            if not original and field == "exampleSentence" and row.get("senses"):
                original = (row["senses"][0].get("exampleSentence") or "").strip()

            fixed, changed = resolve_sentence(word, field, original)
            if changed:
                row[field] = fixed
                modified_fields.append(field)
            resolved[field] = row.get(field) or fixed

        modified = bool(modified_fields)
        if modified:
            total_modified += 1

        for field in ("quizSentence", "exampleSentence", "alternateExampleSentence"):
            sentence = (row.get(field) or "").strip()
            for issue in validate_sentence(word, sentence):
                remaining_issues.append(f"{word} {field}: {issue} -> {sentence[:90]}")

        report.append(
            {
                "word": word,
                "quizSentence": row.get("quizSentence", ""),
                "exampleSentence": row.get("exampleSentence", ""),
                "alternateExampleSentence": row.get("alternateExampleSentence", ""),
                "modified": modified,
                **({"modifiedFields": modified_fields} if modified_fields else {}),
            }
        )

    with DB_PATH.open("w", encoding="utf-8") as handle:
        json.dump(database, handle, indent=2, ensure_ascii=False)
        handle.write("\n")

    REPORT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with REPORT_PATH.open("w", encoding="utf-8") as handle:
        json.dump(report, handle, indent=2, ensure_ascii=False)
        handle.write("\n")

    print(f"Words processed: {len(database)}")
    print(f"Words modified: {total_modified}")
    print(f"Report written: {REPORT_PATH}")
    print(f"Remaining validation issues: {len(remaining_issues)}")
    for item in remaining_issues[:30]:
        print(f"  - {item}")
    if len(remaining_issues) > 30:
        print(f"  ... +{len(remaining_issues) - 30} more")
    return 1 if remaining_issues else 0


if __name__ == "__main__":
    raise SystemExit(main())
