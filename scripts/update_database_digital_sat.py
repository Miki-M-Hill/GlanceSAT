#!/usr/bin/env python3
"""Prune legacy vocabulary and inject Digital SAT high-yield words into Database.json."""

from __future__ import annotations

import json
import uuid
from pathlib import Path

DATABASE_PATH = Path(__file__).resolve().parents[1] / "GlanceSAT" / "GlanceSAT" / "Database.json"

REMOVE_HEADWORDS = {
    "Abduct",
    "Abort",
    "Aisle",
    "Anesthesia",
    "Aquatic",
    "Artifact",
    "Ballad",
    "Bard",
    "Clergy",
    "Cobbler",
    "Contusion",
    "Coronation",
    "Dialect",
    "Laceration",
    "Larceny",
    "Palette",
    "Putrid",
    "Reservoir",
    "Swarthy",
}

LEARNING_DATA = {
    "status": "new",
    "nextReviewDate": "2026-03-30T00:00:00Z",
    "lastReviewDate": None,
    "interval": 1,
    "easeFactor": 2.5,
    "successfulRecalls": 0,
    "consecutiveCorrect": 0,
    "totalAttempts": 0,
}


def uid() -> str:
    return str(uuid.uuid4())


def entry(
    word: str,
    *,
    part_of_speech: str | None = None,
    definition: str | None = None,
    synonyms: list[str] | None = None,
    etymology: str,
    example_sentence: str,
    quiz_sentence: str,
    category: str,
    passage_domain: str = "thought_language",
    difficulty: int = 3,
    frequency: int = 2,
    semantic_charge: str = "neutral",
    semantic_charge_intensity: int | None = None,
    memory_hook_kind: str = "morphology",
    memory_hook_text: str | None = None,
    senses: list[dict] | None = None,
) -> dict:
    record: dict = {
        "id": uid(),
        "word": word,
        "difficultyLevel": difficulty,
        "frequencyTier": frequency,
        "category": category,
        "etymology": etymology,
        "learningData": LEARNING_DATA.copy(),
        "passageDomain": passage_domain,
        "semanticCharge": semantic_charge,
    }

    if senses:
        record["senses"] = senses
    else:
        if not part_of_speech or definition is None or synonyms is None:
            raise ValueError(f"{word} requires part_of_speech, definition, and synonyms when senses is omitted")
        record["partOfSpeech"] = part_of_speech
        record["definition"] = definition
        record["synonyms"] = synonyms
        record["exampleSentence"] = example_sentence

    if semantic_charge_intensity is not None:
        record["semanticChargeIntensity"] = semantic_charge_intensity

    if memory_hook_text:
        record["memoryHook"] = {"kind": memory_hook_kind, "text": memory_hook_text}
    else:
        record["memoryHook"] = None

    record["quizSentence"] = quiz_sentence
    return record


NEW_WORDS: list[dict] = [
    entry(
        "Allude",
        part_of_speech="verb",
        definition="To refer to indirectly",
        synonyms=["hint at", "suggest", "imply", "touch on"],
        etymology="Latin alludere, from ad- ('to') + ludere ('to play')",
        example_sentence="The essay alludes to Plato without naming him, expecting readers to recognize the reference.",
        quiz_sentence="Rather than quoting the poem directly, the critic chose to allude to its central metaphor.",
        category="language-communication",
        difficulty=3,
        frequency=2,
        memory_hook_text='"Allude" sounds like "elude" — you elude naming something by alluding to it.',
        memory_hook_kind="sound_spelling",
    ),
    entry(
        "Assert",
        part_of_speech="verb",
        definition="To state confidently as true",
        synonyms=["declare", "maintain", "claim", "affirm"],
        etymology="Latin asserere, from ad- ('to') + serere ('to join')",
        example_sentence="The historian asserts that trade routes, not battles alone, reshaped the empire.",
        quiz_sentence="In her opening paragraph, the author asserts that public transit reform is long overdue.",
        category="logic-reasoning",
        difficulty=2,
        frequency=1,
        memory_hook_text='"Assert" = to join your voice to a claim and stand by it.',
    ),
    entry(
        "Attest",
        part_of_speech="verb",
        definition="To provide evidence or bear witness",
        synonyms=["confirm", "verify", "corroborate", "testify"],
        etymology="Latin attestari, from ad- ('to') + testari ('to bear witness')",
        example_sentence="Ancient letters attest to the merchant's reputation among distant trading partners.",
        quiz_sentence="Multiple independent records attest that the treaty was signed in April.",
        category="logic-reasoning",
        difficulty=3,
        frequency=2,
        memory_hook_text='"At-" + "test" = to be at the test as a witness.',
        memory_hook_kind="sound_spelling",
    ),
    entry(
        "Belie",
        part_of_speech="verb",
        definition="To give a false impression; to contradict",
        synonyms=["contradict", "misrepresent", "mask", "negate"],
        etymology="Old English belēogan, from be- + lēogan ('to lie')",
        example_sentence="Her calm tone belied the urgency of the warning she delivered.",
        quiz_sentence="The company's polished report belied serious losses in its overseas division.",
        category="intellect-judgment",
        difficulty=4,
        frequency=2,
        semantic_charge="negative",
        memory_hook_text='"Belie" hides the truth — it sounds like "lie" inside the word.',
        memory_hook_kind="sound_spelling",
    ),
    entry(
        "Bolster",
        part_of_speech="verb",
        definition="To support or strengthen",
        synonyms=["reinforce", "buttress", "prop up", "fortify"],
        etymology="Old English bolster ('long pillow'), from a word meaning 'to support'",
        example_sentence="New survey data bolstered the economist's claim that wages were finally rising.",
        quiz_sentence="The pilot study bolstered confidence in the larger experiment's design.",
        category="logic-reasoning",
        difficulty=2,
        frequency=2,
        semantic_charge="positive",
        memory_hook_text="A bolster pillow supports your head — to bolster an argument supports it.",
        memory_hook_kind="etymology_story",
    ),
    entry(
        "Conducive",
        part_of_speech="adjective",
        definition="Tending to promote or assist",
        synonyms=["favorable", "helpful", "beneficial", "propitious"],
        etymology="Latin conducere, from con- ('together') + ducere ('to lead')",
        example_sentence="Quiet libraries are conducive to focused reading and careful note-taking.",
        quiz_sentence="The mentor argued that smaller seminar sizes are conducive to deeper discussion.",
        category="academic",
        difficulty=3,
        frequency=2,
        semantic_charge="positive",
        memory_hook_text='"Con-" (together) + "duc-" (lead) = conditions that lead you toward a result.',
    ),
    entry(
        "Conjecture",
        difficulty=3,
        frequency=2,
        category="logic-reasoning",
        etymology="Latin conjectura, from conjectus ('thrown together'), from conicere",
        example_sentence="Without more data, the theory remains conjecture rather than established fact.",
        quiz_sentence="What looks like proof may still be conjecture until it survives repeated testing.",
        senses=[
            {
                "partOfSpeech": "noun",
                "definition": "An inference formed without complete evidence",
                "synonyms": ["guess", "speculation", "hypothesis", "supposition"],
                "exampleSentence": "The article treats the link between diet and mood as conjecture, not certainty.",
            },
            {
                "partOfSpeech": "verb",
                "definition": "To form an opinion on incomplete evidence",
                "synonyms": ["speculate", "surmise", "infer", "hypothesize"],
                "exampleSentence": "Researchers conjectured that the artifact predated the written records.",
            },
        ],
        memory_hook_text='"Con-" (together) + "ject" (throw) = ideas thrown together into a guess.',
    ),
    entry(
        "Contextualize",
        part_of_speech="verb",
        definition="To place in context so meaning becomes clear",
        synonyms=["frame", "situate", "background", "explain"],
        etymology="From Latin contextus ('woven together') + -ize",
        example_sentence="The editor contextualized the quote by explaining the political crisis surrounding it.",
        quiz_sentence="Good historians contextualize events instead of judging them by modern standards alone.",
        category="language-communication",
        difficulty=3,
        frequency=2,
        memory_hook_text="Context + -ize = to put something inside its surrounding context.",
        memory_hook_kind="morphology",
    ),
    entry(
        "Conversely",
        part_of_speech="adverb",
        definition="On the other hand; in an opposite way",
        synonyms=["on the contrary", "in contrast", "alternatively", "by contrast"],
        etymology="From converse ('turned about') + -ly",
        example_sentence="Urban density can reduce emissions; conversely, sprawl often increases driving.",
        quiz_sentence="The first trial showed gains in speed; conversely, accuracy declined sharply.",
        category="logic-reasoning",
        difficulty=2,
        frequency=1,
        memory_hook_text="Converse = turn around — conversely turns the argument to the other side.",
        memory_hook_kind="morphology",
    ),
    entry(
        "Correlate",
        part_of_speech="verb",
        definition="To show or have a mutual relationship",
        synonyms=["correspond", "associate", "link", "connect"],
        etymology="Medieval Latin correlare, from Latin com- ('together') + relatus ('carried back')",
        example_sentence="The study correlates higher reading time with stronger vocabulary growth.",
        quiz_sentence="Analysts correlated rising temperatures with increased crop failures across the region.",
        category="science-method",
        passage_domain="science_world",
        difficulty=3,
        frequency=1,
        memory_hook_text='"Co-" (together) + "relate" = variables related together.',
        memory_hook_kind="morphology",
    ),
    entry(
        "Diminish",
        part_of_speech="verb",
        definition="To make smaller, weaker, or less important",
        synonyms=["reduce", "lessen", "weaken", "curtail"],
        etymology="Old French diminuer, from Latin deminuere, from de- ('away') + minuere ('lessen')",
        example_sentence="Repeated interruptions diminished the speaker's ability to make a coherent case.",
        quiz_sentence="The new evidence diminished the credibility of the earlier conclusion.",
        category="academic",
        difficulty=2,
        frequency=2,
        semantic_charge="negative",
        memory_hook_text='"Di-" (away) + "min" (small) = to make something smaller.',
    ),
    entry(
        "Exemplify",
        part_of_speech="verb",
        definition="To serve as a typical example of",
        synonyms=["illustrate", "demonstrate", "represent", "embody"],
        etymology="Medieval Latin exemplificare, from Latin exemplum ('example') + facere ('make')",
        example_sentence="The case study exemplifies how small policy changes can shift public behavior.",
        quiz_sentence="Her career exemplifies the value of persistent, evidence-based advocacy.",
        category="logic-reasoning",
        difficulty=3,
        frequency=2,
        memory_hook_text="Example + -ify = to make into an example.",
        memory_hook_kind="morphology",
    ),
    entry(
        "Explicit",
        part_of_speech="adjective",
        definition="Stated clearly and directly, leaving nothing implied",
        synonyms=["clear", "direct", "plain", "unambiguous"],
        etymology="Latin explicitus, past participle of explicare ('unfold')",
        example_sentence="The contract's explicit terms prevented either party from claiming surprise later.",
        quiz_sentence="The author was explicit about which sources she relied on and which she rejected.",
        category="language-communication",
        difficulty=2,
        frequency=1,
        memory_hook_text="Explicit = fully unfolded and spelled out, not hidden.",
        memory_hook_kind="morphology",
    ),
    entry(
        "Extrapolate",
        part_of_speech="verb",
        definition="To infer unknown values by extending known data",
        synonyms=["project", "infer", "extend", "estimate"],
        etymology="Latin extra ('outside') + polare ('to polish'), via extrapolatio",
        example_sentence="Scientists extrapolated the trend line to predict demand over the next decade.",
        quiz_sentence="From three years of scores, the committee extrapolated likely long-term improvement.",
        category="science-method",
        passage_domain="science_world",
        difficulty=4,
        frequency=2,
        memory_hook_text='"Extra-" (beyond) + "polate" = push a pattern beyond the data you have.',
    ),
    entry(
        "Facilitate",
        part_of_speech="verb",
        definition="To make an action or process easier",
        synonyms=["enable", "ease", "assist", "expedite"],
        etymology="Latin facilitare, from facilis ('easy')",
        example_sentence="Shared calendars facilitate coordination among researchers in different time zones.",
        quiz_sentence="The revised workflow facilitated faster review without sacrificing rigor.",
        category="academic",
        difficulty=2,
        frequency=2,
        semantic_charge="positive",
        memory_hook_text="Facile means easy — facilitate makes things easy to do.",
        memory_hook_kind="morphology",
    ),
    entry(
        "Feasible",
        part_of_speech="adjective",
        definition="Possible to do or achieve with available means",
        synonyms=["practicable", "viable", "workable", "achievable"],
        etymology="Old French faisable, from fais-, stem of faire ('to do')",
        example_sentence="Engineers concluded that a bridge at that site was feasible but costly.",
        quiz_sentence="The plan is ambitious, yet still feasible if funding arrives on schedule.",
        category="general-academic",
        difficulty=2,
        frequency=2,
        semantic_charge="positive",
        memory_hook_text='Feasible = able to be done (think "do-able").',
        memory_hook_kind="sound_spelling",
    ),
    entry(
        "Galvanize",
        part_of_speech="verb",
        definition="To stimulate people into urgent action",
        synonyms=["spur", "motivate", "energize", "rouse"],
        etymology="From Luigi Galvani, whose experiments with electricity inspired the metaphor",
        example_sentence="The leaked report galvanized students to organize a campus-wide forum.",
        quiz_sentence="A single compelling speech galvanized the coalition to act before the vote.",
        category="social-behavior",
        passage_domain="human_social",
        difficulty=3,
        frequency=2,
        semantic_charge="positive",
        memory_hook_text="Galvanize recalls an electric jolt that shocks people into motion.",
        memory_hook_kind="etymology_story",
    ),
    entry(
        "Impede",
        part_of_speech="verb",
        definition="To obstruct or slow progress",
        synonyms=["hinder", "block", "hamper", "thwart"],
        etymology="Latin impedire, from in- ('in') + pes ('foot') — to shackle the feet",
        example_sentence="Outdated software impeded the team's ability to analyze the dataset quickly.",
        quiz_sentence="Bureaucratic delays impeded implementation of the approved reforms.",
        category="academic",
        difficulty=3,
        frequency=2,
        semantic_charge="negative",
        memory_hook_text='"Im-" (in) + "ped" (foot) = feet caught, movement blocked.',
    ),
    entry(
        "Inherent",
        part_of_speech="adjective",
        definition="Existing as a permanent, essential characteristic",
        synonyms=["intrinsic", "built-in", "innate", "fundamental"],
        etymology="Latin inhaerere, from in- ('in') + haerere ('stick')",
        example_sentence="The author argues that bias is inherent in any single-source narrative.",
        quiz_sentence="Risk is inherent in experimentation, but it can be measured and managed.",
        category="intellect-judgment",
        difficulty=3,
        frequency=2,
        memory_hook_text="Inherent = stuck inside as a core trait.",
        memory_hook_kind="morphology",
    ),
    entry(
        "Notwithstanding",
        difficulty=4,
        frequency=2,
        category="logic-reasoning",
        etymology="Middle English not withstanding, literally 'not standing against'",
        example_sentence="Notwithstanding earlier setbacks, the lab published its findings on schedule.",
        quiz_sentence="The policy remained popular, notwithstanding fierce criticism from experts.",
        senses=[
            {
                "partOfSpeech": "preposition",
                "definition": "In spite of",
                "synonyms": ["despite", "regardless of", "even with", "in defiance of"],
                "exampleSentence": "Notwithstanding the rain, the march continued through downtown.",
            },
            {
                "partOfSpeech": "adverb",
                "definition": "Nevertheless; all the same",
                "synonyms": ["nevertheless", "nonetheless", "still", "yet"],
                "exampleSentence": "The evidence was thin; notwithstanding, the jury reached a verdict.",
            },
        ],
        memory_hook_text="Not with standing against = nothing standing in the way of the fact still being true.",
        memory_hook_kind="morphology",
    ),
    entry(
        "Obviate",
        part_of_speech="verb",
        definition="To remove a need or difficulty beforehand",
        synonyms=["prevent", "preclude", "avert", "forestall"],
        etymology="Latin obviare, from ob- ('against') + via ('way') — to meet and block",
        example_sentence="Clear instructions obviated the need for repeated follow-up emails.",
        quiz_sentence="Backup systems obviate panic when a primary server fails.",
        category="intellect-judgment",
        difficulty=4,
        frequency=3,
        semantic_charge="positive",
        memory_hook_text='"Ob-" (against) + "via" (way) = block the problem before it arrives.',
    ),
    entry(
        "Perpetuate",
        part_of_speech="verb",
        definition="To cause to continue indefinitely",
        synonyms=["prolong", "sustain", "maintain", "preserve"],
        etymology="Latin perpetuare, from perpetuus ('continuous')",
        example_sentence="Stereotypes perpetuated by media can shape public policy for decades.",
        quiz_sentence="Without reform, the loophole could perpetuate inequality in college admissions.",
        category="social-behavior",
        passage_domain="human_social",
        difficulty=3,
        frequency=2,
        semantic_charge="negative",
        memory_hook_text="Perpetual = forever — perpetuate keeps something going without end.",
        memory_hook_kind="morphology",
    ),
    entry(
        "Postulate",
        difficulty=4,
        frequency=2,
        category="logic-reasoning",
        etymology="Latin postulare ('to demand, assume')",
        example_sentence="The physicist postulated that the anomaly would disappear under tighter controls.",
        quiz_sentence="Economists postulate a link between trust and investment, then test it empirically.",
        senses=[
            {
                "partOfSpeech": "verb",
                "definition": "To assume as true for the sake of argument or theory",
                "synonyms": ["hypothesize", "propose", "posit", "presume"],
                "exampleSentence": "The essay postulates that readers already accept the author's definition of fairness.",
            },
            {
                "partOfSpeech": "noun",
                "definition": "Something taken as self-evident or assumed without proof",
                "synonyms": ["assumption", "premise", "axiom", "presupposition"],
                "exampleSentence": "The entire proof rests on a postulate that critics say is outdated.",
            },
        ],
        memory_hook_text="Postulate = put forward a starting claim before you prove the rest.",
        memory_hook_kind="morphology",
    ),
    entry(
        "Precipitate",
        difficulty=3,
        frequency=2,
        category="academic",
        etymology="Latin praecipitare, from praeceps ('headlong')",
        example_sentence="The sudden scandal precipitated the minister's resignation within days.",
        quiz_sentence="A single miscalculation can precipitate a chain of failures in complex systems.",
        senses=[
            {
                "partOfSpeech": "verb",
                "definition": "To cause something to happen suddenly",
                "synonyms": ["trigger", "hasten", "bring about", "spark"],
                "exampleSentence": "Trade disputes precipitated a sharp drop in consumer confidence.",
            },
            {
                "partOfSpeech": "verb",
                "definition": "To cause a substance to separate from a solution (chemistry)",
                "synonyms": ["settle out", "crystallize", "deposit", "form a solid"],
                "exampleSentence": "Cooling the mixture caused salts to precipitate from the liquid.",
            },
        ],
        passage_domain="science_world",
        memory_hook_text="Precipitate = headlong — events fall fast when you precipitate them.",
    ),
    entry(
        "Qualify",
        difficulty=3,
        frequency=1,
        category="logic-reasoning",
        etymology="Medieval Latin qualificare, from Latin qualis ('of what kind') + facere ('make')",
        example_sentence="The researcher qualified her conclusion, noting the sample size was small.",
        quiz_sentence="A good thesis qualifies broad claims so they match the evidence presented.",
        senses=[
            {
                "partOfSpeech": "verb",
                "definition": "To limit or modify a claim",
                "synonyms": ["moderate", "restrict", "nuance", "temper"],
                "exampleSentence": "The author qualifies the headline by adding important exceptions in the next sentence.",
            },
            {
                "partOfSpeech": "verb",
                "definition": "To meet the requirements for something",
                "synonyms": ["be eligible", "meet standards", "pass muster", "satisfy conditions"],
                "exampleSentence": "Only three candidates qualified for the final round of interviews.",
            },
        ],
        memory_hook_text="On the SAT, qualify often means add limits — like adding qualities that narrow a claim.",
        memory_hook_kind="morphology",
    ),
    entry(
        "Reiterate",
        part_of_speech="verb",
        definition="To repeat for emphasis or clarity",
        synonyms=["repeat", "restate", "emphasize again", "recapitulate"],
        etymology="Latin reiterare, from re- ('again') + iterare ('to repeat')",
        example_sentence="The judge reiterated that the ruling applied only to future cases.",
        quiz_sentence="The coach reiterated the same strategy because the team kept drifting off plan.",
        category="language-communication",
        difficulty=2,
        frequency=2,
        memory_hook_text='"Re-" (again) + "iterate" (repeat) = say it again on purpose.',
    ),
    entry(
        "Scrutinize",
        part_of_speech="verb",
        definition="To examine closely and critically",
        synonyms=["inspect", "analyze", "pore over", "study closely"],
        etymology="Latin scrutinium, from scrutari ('to search through rubbish carefully')",
        example_sentence="Peer reviewers scrutinize methods sections for hidden flaws.",
        quiz_sentence="Voters scrutinize campaign promises when economic data tell a different story.",
        category="intellect-judgment",
        difficulty=3,
        frequency=2,
        memory_hook_text="Scrutinize = search through every detail as if hunting for hidden trash.",
        memory_hook_kind="etymology_story",
    ),
    entry(
        "Subsequently",
        part_of_speech="adverb",
        definition="Afterward; at a later time",
        synonyms=["later", "afterward", "then", "after that"],
        etymology="Latin subsequens, from sub- ('after') + sequi ('to follow')",
        example_sentence="The team published its pilot results and subsequently launched a larger trial.",
        quiz_sentence="The law passed in May and subsequently changed hiring practices across the state.",
        category="logic-reasoning",
        difficulty=2,
        frequency=1,
        memory_hook_text='"Sub-" (after) + "sequ-" (follow) = what follows later in sequence.',
    ),
    entry(
        "Substantiate",
        part_of_speech="verb",
        definition="To provide evidence that supports a claim",
        synonyms=["corroborate", "verify", "confirm", "back up"],
        etymology="Latin substantiare, from substantia ('substance, essence')",
        example_sentence="The journalist could not substantiate the rumor without named sources.",
        quiz_sentence="Charts alone cannot substantiate causation without a plausible mechanism.",
        category="logic-reasoning",
        difficulty=4,
        frequency=2,
        memory_hook_text="Substance = solid proof — substantiate gives a claim substance.",
        memory_hook_kind="morphology",
    ),
    entry(
        "Synthesize",
        part_of_speech="verb",
        definition="To combine separate elements into a coherent whole",
        synonyms=["integrate", "merge", "combine", "fuse"],
        etymology="Greek syntithenai, from syn- ('together') + tithenai ('to place')",
        example_sentence="The essay synthesizes archival research with oral histories into one narrative.",
        quiz_sentence="Strong conclusions synthesize conflicting studies instead of citing only one.",
        category="logic-reasoning",
        difficulty=3,
        frequency=2,
        memory_hook_text='"Syn-" (together) + "thesis" (placing) = place ideas together into one whole.',
    ),
    entry(
        "Undermine",
        part_of_speech="verb",
        definition="To weaken gradually or indirectly",
        synonyms=["erode", "sabotage", "subvert", "impair"],
        etymology="From under + mine — to dig beneath foundations",
        example_sentence="Selective quoting can undermine an otherwise careful argument.",
        quiz_sentence="Repeated delays undermined public trust in the agency's forecasts.",
        category="logic-reasoning",
        difficulty=3,
        frequency=2,
        semantic_charge="negative",
        memory_hook_text="To undermine is to dig under a wall until it collapses.",
        memory_hook_kind="etymology_story",
    ),
]


def main() -> None:
    with DATABASE_PATH.open(encoding="utf-8") as handle:
        data: list[dict] = json.load(handle)

    original_count = len(data)
    removed = [w for w in data if w["word"] in REMOVE_HEADWORDS]
    data = [w for w in data if w["word"] not in REMOVE_HEADWORDS]

    if len(removed) != len(REMOVE_HEADWORDS):
        missing = REMOVE_HEADWORDS - {w["word"] for w in removed}
        raise SystemExit(f"Expected to remove {len(REMOVE_HEADWORDS)} words; missing: {sorted(missing)}")

    existing = {w["word"].lower() for w in data}
    collisions = [w["word"] for w in NEW_WORDS if w["word"].lower() in existing]
    if collisions:
        raise SystemExit(f"New words already present: {collisions}")

    data.extend(NEW_WORDS)
    data.sort(key=lambda item: (item["word"].lower(), item["word"]))

    with DATABASE_PATH.open("w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=2, ensure_ascii=False)
        handle.write("\n")

    # Validate round-trip
    with DATABASE_PATH.open(encoding="utf-8") as handle:
        validated = json.load(handle)

    words = [item["word"] for item in validated]
    sorted_words = sorted(words, key=lambda s: (s.lower(), s))
    assert words == sorted_words, "Database is not alphabetized"
    assert len(validated) == original_count - len(REMOVE_HEADWORDS) + len(NEW_WORDS)

    print(f"Removed: {len(removed)}")
    print(f"Added: {len(NEW_WORDS)}")
    print(f"Final count: {len(validated)}")
    print(f"Validated JSON at {DATABASE_PATH}")


if __name__ == "__main__":
    main()
