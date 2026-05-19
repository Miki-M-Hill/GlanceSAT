"""
Canonical passageDomain assignment (Database rubric v1.1 §B).

Five buckets: human_social | self_character | thought_language | science_world | power_culture
"""
from __future__ import annotations

import re
from typing import Any

VALID_DOMAINS = frozenset({
    "human_social",
    "self_character",
    "thought_language",
    "science_world",
    "power_culture",
})

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

# Lemma-level overrides (primary sense / example wins over category slug).
WORD_DOMAIN: dict[str, str] = {
    # Batch-001 emotion-in-social slug fixes
    "captivate": "self_character",
    "cherish": "self_character",
    "cloying": "self_character",
    "complacency": "self_character",
    "compunction": "self_character",
    # social-behavior → inner trait (not norms between people)
    "bashful": "self_character",
    "diffident": "self_character",
    "forlorn": "self_character",
    "hapless": "self_character",
    "despondent": "self_character",
    "morose": "self_character",
    "petulance": "self_character",
    "irascible": "self_character",
    # science-engineering slug, figurative / SAT-primary sense
    "caustic": "thought_language",
    "circumscribed": "thought_language",
    "catalyze": "thought_language",
    "increment": "thought_language",
    "latent": "thought_language",
    "linchpin": "thought_language",
    "refract": "thought_language",
    "immerse": "thought_language",
    "malleable": "thought_language",
    "oscillate": "thought_language",
    "permeate": "thought_language",
    "plethora": "thought_language",
    "compound": "thought_language",
    "compress": "thought_language",
    "counteract": "thought_language",
    "incendiary": "power_culture",
    "cleave": "thought_language",
    "fecund": "science_world",
    "zenith": "thought_language",
  # science-nature / perception — character or abstract quality
    "effervescent": "self_character",
    "ephemeral": "thought_language",
    "limpid": "thought_language",
    "diaphanous": "thought_language",
    # arts / communication
    "emote": "self_character",
    "epistolary": "power_culture",
    "eloquent": "thought_language",
    "rhetoric": "thought_language",
    # law / politics slug but inner or intellectual primary sense
    "contrite": "self_character",
    "remorse": "self_character",
    "temperance": "self_character",
    "validate": "thought_language",
    "judicious": "thought_language",
    "discretion": "thought_language",
    "advocate": "power_culture",
    "demagogue": "power_culture",
    "asylum": "power_culture",
    "aggregate": "thought_language",
    "antecedent": "thought_language",
    "catalog": "thought_language",
    "collateral": "power_culture",
    "fabricate": "thought_language",
    "fraught": "self_character",
    "palliate": "science_world",
    "propitious": "thought_language",
    "regurgitate": "thought_language",
    "sensual": "self_character",
    "vicarious": "self_character",
    "undulate": "science_world",
    "enervate": "self_character",
    "emaciated": "science_world",
    "pathology": "science_world",
    "panacea": "science_world",
    "empirical": "science_world",
    "conflagration": "science_world",
    "blight": "science_world",
    "maelstrom": "science_world",
    "zephyr": "science_world",
    # multi-sense rows — primary surfaced sense
    "abide": "thought_language",
    "abridge": "thought_language",
    "acute": "thought_language",
    "adhere": "thought_language",
    "advocate": "power_culture",
    "aggregate": "thought_language",
    "annex": "power_culture",
    "apprehend": "power_culture",
    "asylum": "power_culture",
    "attribute": "thought_language",
    "buffet": "thought_language",
    "buttress": "thought_language",
    "canvas": "power_culture",
    "catalog": "thought_language",
    "censure": "power_culture",
    "chronicle": "power_culture",
    "clamor": "human_social",
    "cleave": "thought_language",
    "collateral": "power_culture",
    "compound": "thought_language",
    "convention": "power_culture",
    "coup": "power_culture",
    "didactic": "thought_language",
    "diffuse": "thought_language",
    "disdain": "self_character",
    "dissent": "power_culture",
    "dissipate": "thought_language",
    "embellish": "power_culture",
    "eminent": "thought_language",
    "facile": "thought_language",
    "felicitous": "thought_language",
    "harangue": "human_social",
    "imperative": "thought_language",
    "impinge": "thought_language",
    "implement": "thought_language",
    "incarnate": "power_culture",
    "incumbent": "power_culture",
    "lavish": "self_character",
    "liability": "power_culture",
    "manifest": "thought_language",
    "moderate": "thought_language",
    "reconcile": "human_social",
    "redoubtable": "self_character",
    "relegate": "power_culture",
    "renovate": "science_world",
    "repulse": "self_character",
    "reservoir": "science_world",
    "resolve": "self_character",
    "solvent": "science_world",
}

# Dedupe duplicate keys (last wins) — clean duplicates in dict above
WORD_DOMAIN = {k: v for k, v in WORD_DOMAIN.items()}

EMOTION_SLUGS = frozenset({"emotion-character", "emotional", "emotion"})

EXAMPLE_KEYWORDS: dict[str, re.Pattern[str]] = {
    "human_social": re.compile(
        r"\b(friend|friends|neighbor|crowd|people|person|guest|host|social|society|"
        r"group|peer|conversation|polite|rude|manners|family|community|together|"
        r"interact|relationship|marriage|wedding|party|team|classmate|stranger)\b",
        re.I,
    ),
    "self_character": re.compile(
        r"\b(feel|feeling|felt|emotion|mood|heart|fear|afraid|joy|happy|sad|grief|"
        r"anger|angry|temper|shy|anxious|lonely|hopeless|inner|character|soul|spirit|"
        r"miserable|depressed|enthusiasm|passion|confident|timid|melancholy|remorse|guilt)\b",
        re.I,
    ),
    "thought_language": re.compile(
        r"\b(argue|argument|logic|logical|mean|meaning|word|words|sentence|think|"
        r"thought|reason|reasoning|claim|define|definition|language|idea|theory|"
        r"interpret|phrase|speech|writing|read|essay|debate|conclude|infer|evidence|"
        r"idea|notion|abstract)\b",
        re.I,
    ),
    "science_world": re.compile(
        r"\b(science|scientist|experiment|lab|cell|body|brain|disease|plant|animal|"
        r"nature|forest|ocean|weather|storm|chemical|physics|biology|measure|data|"
        r"patient|doctor|hospital|muscle|blood|energy|atom|species|ecosystem|burn|"
        r"water|fire|soil|crop)\b",
        re.I,
    ),
    "power_culture": re.compile(
        r"\b(law|legal|court|judge|king|queen|war|army|soldier|money|profit|business|"
        r"art|artist|poem|novel|church|priest|history|government|president|election|"
        r"trade|market|culture|religion|temple|museum|empire|colony|revolution|prison|"
        r"crime|guilty|policy|nation|state)\b",
        re.I,
    ),
}


def _primary_text(entry: dict[str, Any]) -> str:
    parts = [
        entry.get("definition") or "",
        entry.get("exampleSentence") or "",
    ]
    senses = entry.get("senses")
    if isinstance(senses, list) and senses and isinstance(senses[0], dict):
        parts.append(senses[0].get("definition") or "")
        parts.append(senses[0].get("exampleSentence") or "")
    return " ".join(parts)


def _example_wins_domain(entry: dict[str, Any], slug_domain: str) -> str | None:
    blob = _primary_text(entry)
    scores = {domain: len(pattern.findall(blob)) for domain, pattern in EXAMPLE_KEYWORDS.items()}
    best = max(scores, key=scores.get)
    if scores[best] >= 3 and scores[slug_domain] == 0:
        return best
    if scores[best] >= 2 and scores[best] >= scores[slug_domain] + 2:
        return best
    return None


def passage_domain_for_entry(entry: dict[str, Any]) -> str:
    word = (entry.get("word") or "").strip()
    key = word.lower()
    slug = (entry.get("category") or "").strip().lower()

    if key in WORD_DOMAIN:
        return WORD_DOMAIN[key]

    if slug in EMOTION_SLUGS:
        return "self_character"

    slug_domain = SLUG_TO_DOMAIN.get(slug, "thought_language")

    if slug == "social-behavior" and word in {
        "Captivate", "Cherish", "Cloying", "Complacency", "Compunction",
    }:
        return "self_character"

    example_domain = _example_wins_domain(entry, slug_domain)
    if example_domain:
        return example_domain

    return slug_domain


def apply_passage_domain(entry: dict[str, Any]) -> bool:
    domain = passage_domain_for_entry(entry)
    if entry.get("passageDomain") != domain:
        entry["passageDomain"] = domain
        return True
    return False


def validate_entries(entries: list[dict[str, Any]]) -> list[str]:
    errors: list[str] = []
    for entry in entries:
        word = entry.get("word") or entry.get("id") or "?"
        domain = entry.get("passageDomain")
        if domain not in VALID_DOMAINS:
            errors.append(f"{word}: invalid passageDomain {domain!r}")
    return errors
