"""
Canonical semanticCharge + semanticChargeIntensity for Database.json (rubric v1.1).

- semanticCharge: negative | neutral | positive | mixed
- semanticChargeIntensity: 1 | 2 | 3 for negative/positive only; omitted for neutral/mixed
"""
from __future__ import annotations

# §C2 — genuinely split evaluations only
MIXED = frozenset({
    "ambivalent",
    "capricious",
    "equivocal",
    "mercurial",
    "zealous",
})

# Lemma stays neutral even when examples are emotional or crime-adjacent
NEUTRAL_FORCE = frozenset({
    "abet",
    "abnegation",
    "abort",
    "abstain",
    "acute",
    "adamant",
    "adhere",
    "advocate",
    "aggregate",
    "annex",
    "apprehend",
    "asylum",
    "attribute",
    "buffet",
    "buttress",
    "canvas",
    "catalog",
    "censure",
    "chronicle",
    "clamor",
    "cleave",
    "collateral",
    "compound",
    "condone",
    "conflagration",
    "congenial",
    "consecrate",
    "conundrum",
    "contrite",
    "contusion",
    "credulity",
    "curt",
    "didactic",
    "diffuse",
    "dissent",
    "embellish",
    "eminent",
    "empirical",
    "facile",
    "forlorn",
    "hapless",
    "harangue",
    "imperative",
    "impinge",
    "implement",
    "incarnate",
    "incumbent",
    "innocuous",
    "inquisitor",
    "lavish",
    "liability",
    "manifest",
    "moderate",
    "mitigate",
    "poignant",
    "reconcile",
    "relegate",
    "renovate",
    "repulse",
    "reservoir",
    "resolve",
    "solvent",
    "clandestine",
    "surreptitious",
    "concord",
    "congruity",
    "consonant",
    "repose",
    "rapport",
    "combustion",
    "inextricable",
    "constrain",
})

NEGATIVE = frozenset({
    "abase", "abduct", "abhor", "abject", "abjure", "abscond", "acerbic", "acrimony",
    "admonish", "adverse", "affront", "aggrandize", "alias", "allege", "anarchist",
    "anathema", "anguish", "antagonism", "antipathy", "appalling", "arbitrary",
    "arrogate", "aspersion", "assail", "atrocity", "avarice", "aversion", "balk",
    "bane", "berate", "bereft", "bias", "bilk", "blight", "brazen", "brusque",
    "cacophony", "calumny", "callous", "carp", "caustic", "censure", "chastise",
    "chide", "coerce", "collusion", "complacency", "complicit", "confound", "connive",
    "contentious", "contravene", "coup", "covet", "credulity", "cupidity", "cunning",
    "debacle", "debase", "debauch", "decry", "deface", "defamatory", "defile",
    "deleterious", "demagogue", "demean", "denigrate", "denounce", "deplore",
    "depravity", "deride", "desecrate", "desolate", "despondent", "despot",
    "destitute", "devious", "discordant", "disaffected", "disdain", "disparage",
    "disrepute", "dissent", "dissonance", "dubious", "duplicity", "duress",
    "egregious", "embezzle", "enmity", "exacerbate", "exasperate", "execrable",
    "flagrant", "flout", "fractious", "frenetic", "furtive", "grandiloquence",
    "grandiose", "gratuitous", "grievous", "guile", "hackneyed", "harrowing",
    "haughty", "heinous", "ignominious", "illicit", "imperious", "impertinent",
    "impudent", "inane", "incendiary", "incorrigible", "infamy", "inimical",
    "iniquity", "insidious", "insolent", "insurgent", "irascible", "irreverence",
    "larceny", "lurid", "malediction", "malevolent", "mendacious", "morose",
    "nefarious", "noisome", "notorious", "noxious", "obdurate", "odious",
    "officious", "ominous", "onerous", "parsimony", "pejorative", "perfidious",
    "pernicious", "petulance", "pillage", "polemic", "proscribe", "punitive",
    "rancor", "reprehensible", "reprobate", "repugnant", "ribald", "sardonic",
    "scathing", "sordid", "strident", "sycophant", "tirade", "travesty",
    "truculent", "turpitude", "unctuous", "vilify", "vitriol", "wanton",
})

POSITIVE = frozenset({
    "acclaim", "accolade", "accommodating", "acumen", "adept", "adroit", "adulation",
    "affable", "alacrity", "alleviate", "ameliorate", "amiable", "amicable", "animated",
    "approbation", "ardor", "assuage", "auspicious", "benevolent", "benign", "boon",
    "camaraderie", "candor", "clemency", "commendation", "compliment", "conciliatory",
    "congenial", "consensus", "consolation", "convivial", "cordial", "corroborate",
    "cosmopolitan", "ebullient", "efficacious", "equanimity", "euphoric", "exalt",
    "exculpate", "exonerate", "extol", "exult", "felicitous", "fidelity", "fortitude",
    "genial", "gregarious", "judicious", "jubilant", "kudos", "largess", "laudatory",
    "lenient", "lucid", "luminous", "magnanimous", "meritorious", "munificence",
    "pacific", "palatable", "panacea", "philanthropic", "plaudits", "plenitude",
    "propitious", "reciprocate", "venerate", "ecstatic", "elated",
})

NEGATIVE_INTENSITY_3 = frozenset({
    "abase", "abhor", "abject", "abjure", "anathema", "appalling", "assail", "atrocity",
    "calumny", "debauch", "defile", "depravity", "desecrate", "despot", "execrable",
    "heinous", "ignominious", "iniquity", "lurid", "malevolent", "malediction",
    "nefarious", "noxious", "odious", "pernicious", "pillage", "anguish", "infamy",
    "harrowing", "debase", "desolate", "destitute", "blight", "bane", "repugnant",
    "turpitude", "vitriol", "reprobate", "vilify", "embezzle", "larceny",
})

NEGATIVE_INTENSITY_1 = frozenset({
    "alias", "arbitrary", "balk", "bereft", "bias", "carp", "chide", "complacency",
    "complicit", "credulity", "dissent", "dubious", "duplicity", "furtive", "hackneyed",
    "inane", "onerous", "parsimony", "aversion", "contrite", "contusion", "confound",
    "abduct", "abscond", "allege", "flout", "guile", "noisome",
})

POSITIVE_INTENSITY_3 = frozenset({
    "acclaim", "accolade", "benevolent", "euphoric", "exalt", "magnanimous", "panacea",
    "philanthropic", "plaudits", "venerate", "jubilant", "ecstatic", "elated", "extol",
    "adulation",
})

POSITIVE_INTENSITY_1 = frozenset({
    "accommodating", "benign", "consensus", "corroborate", "efficacious", "equanimity",
    "exculpate", "exonerate", "fidelity", "judicious", "lenient", "lucid", "palatable",
    "pacific", "plenitude", "propitious", "reciprocate", "assuage", "alleviate",
    "ameliorate", "munificence",
})


def _intensity(key: str, charge: str) -> int | None:
    if charge == "negative":
        if key in NEGATIVE_INTENSITY_3:
            return 3
        if key in NEGATIVE_INTENSITY_1:
            return 1
        return 2
    if charge == "positive":
        if key in POSITIVE_INTENSITY_3:
            return 3
        if key in POSITIVE_INTENSITY_1:
            return 1
        return 2
    return None


def semantic_charge_for_word(word: str) -> str:
    key = word.strip().lower()
    if key in MIXED:
        return "mixed"
    if key in NEUTRAL_FORCE:
        return "neutral"
    if key in NEGATIVE:
        return "negative"
    if key in POSITIVE:
        return "positive"
    return "neutral"


def semantic_charge_intensity(word: str, charge: str) -> int | None:
    return _intensity(word.strip().lower(), charge)


def apply_semantic_fields(entry: dict) -> bool:
    """Set semanticCharge (+ intensity). Returns True if entry changed."""
    word = entry.get("word", "")
    charge = semantic_charge_for_word(word)
    intensity = semantic_charge_intensity(word, charge)

    changed = False
    if entry.get("semanticCharge") != charge:
        entry["semanticCharge"] = charge
        changed = True

    if charge in ("negative", "positive"):
        if entry.get("semanticChargeIntensity") != intensity:
            entry["semanticChargeIntensity"] = intensity
            changed = True
    else:
        if "semanticChargeIntensity" in entry:
            del entry["semanticChargeIntensity"]
            changed = True

    return changed


def validate_entries(entries: list[dict]) -> list[str]:
    errors: list[str] = []
    valid_charges = {"negative", "neutral", "positive", "mixed"}
    for entry in entries:
        word = entry.get("word") or entry.get("id") or "?"
        charge = entry.get("semanticCharge")
        if charge not in valid_charges:
            errors.append(f"{word}: invalid semanticCharge {charge!r}")
            continue
        intensity = entry.get("semanticChargeIntensity")
        if charge in ("negative", "positive"):
            if intensity not in (1, 2, 3):
                errors.append(f"{word}: missing/invalid intensity for {charge}")
        elif intensity is not None:
            errors.append(f"{word}: intensity must be omitted for {charge}")
    return errors
