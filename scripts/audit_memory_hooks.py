#!/usr/bin/env python3
"""Audit memory hooks in Database.json and write Hook_Audit_Report.md."""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATABASE_PATH = ROOT / "GlanceSAT" / "GlanceSAT" / "Database.json"
REPORT_PATH = ROOT / "docs" / "Hook_Audit_Report.md"

VISUAL_CUES = re.compile(
    r"\b("
    r"imagine|picture|visualize|absurd|wild|steal|stolen|run|running|escape|"
    r"scream|shout|crash|explod|fight|hide|sneak|gross|weird|cartoon|"
    r"nightmare|horror|monster|ghost|clown|banana|pizza|scone|pillow|"
    r"chase|fall|drop|spill|yell|panic|chaos|cackl|"
    r"secretly|suddenly|dramatically|broken|wretched|thrown"
    r")\b",
    re.I,
)

ACTION_CUES = re.compile(
    r"\b(steal|run|hide|yell|shove|break|fall|crash|eat|bite|kick|"
    r"escape|flee|grab|drop|spill|scream|laugh|cackle|conned|trick|"
    r"humiliat|kidnap|abolish|repeal|support|dig|collapse)\b",
    re.I,
)

MORPHOLOGY_PATTERN = re.compile(
    r'^"?[a-z]{2,4}-?"?\s*\([^)]+\)\s*(\+|=)',
    re.I,
)

ETYM_ONLY_PATTERN = re.compile(
    r"^(from|greek|latin|old french|french|german|originally|literally)\b",
    re.I,
)

GENERIC_PATTERNS = [
    re.compile(r"\b(on the sat|often means|think of it as|simply means|another word for)\b", re.I),
    re.compile(r"\b(is when|is the act of|refers to|describes)\b", re.I),
    re.compile(r"\bsame root as\b", re.I),
]


def primary_definition(entry: dict) -> str:
    if entry.get("definition"):
        return entry["definition"]
    senses = entry.get("senses") or []
    if senses:
        return senses[0].get("definition", "")
    return ""


def hook_text(entry: dict) -> tuple[str | None, str | None]:
    hook = entry.get("memoryHook")
    if not hook:
        return None, None
    if isinstance(hook, dict):
        return hook.get("kind"), hook.get("text")
    return "unknown", str(hook)


def normalize(text: str) -> str:
    return re.sub(r"[^a-z0-9\s]", " ", text.lower())


def token_set(text: str) -> set[str]:
    return {t for t in normalize(text).split() if len(t) > 2}


def overlap_ratio(a: str, b: str) -> float:
    ta, tb = token_set(a), token_set(b)
    if not ta or not tb:
        return 0.0
    return len(ta & tb) / min(len(ta), len(tb))


def acoustic_keywords(word: str, hook: str) -> list[str]:
    w = word.lower()
    h = hook.lower()
    hits: list[str] = []

    for length in range(min(len(w), 8), 2, -1):
        for start in range(len(w) - length + 1):
            chunk = w[start : start + length]
            if chunk in h and chunk not in hits:
                hits.append(chunk)

    bonus_fragments = [
        "horror", "hor", "base", "bait", "bet", "bridge", "gate", "scone",
        "scones", "con", "conned", "cackl", "dict", "ject", "neg", "cede",
        "claim", "cord", "heart", "bolster", "elude", "lie", "mine", "electric",
        "fold", "qual", "syn", "thesis", "substance", "scrut", "converse",
        "context", "correl", "extra", "facil", "feas", "ped", "foot", "via",
        "headlong", "perpetual", "do-able", "sound", "speak", "throw",
    ]
    for frag in bonus_fragments:
        if frag in h and frag not in hits:
            hits.append(frag)
    return hits


def is_definition_restatement(definition: str, hook: str, kind: str | None) -> bool:
    if kind in {"morphology", "etymology_story", "sound_spelling"}:
        return False
    if MORPHOLOGY_PATTERN.search(hook) or ETYM_ONLY_PATTERN.search(hook):
        return False
    if any(p.search(hook) for p in GENERIC_PATTERNS):
        return True
    if overlap_ratio(definition, hook) >= 0.9:
        return True
    def_norm = normalize(definition)
    hook_norm = normalize(hook)
    return len(def_norm) > 30 and def_norm in hook_norm


@dataclass
class AuditResult:
    word: str
    hook: str
    tier: int
    rationale: str


def build_rationale(
    *,
    tier: int,
    kind: str | None,
    hook: str,
    acoustic: list[str],
    has_visual: bool,
    overlap: float,
    length: int,
) -> str:
    if tier == 5 and hook == "(none)":
        return "Missing hook entirely — no mnemonic support for recall under pressure."

    parts: list[str] = []

    if kind == "morphology" or MORPHOLOGY_PATTERN.search(hook):
        parts.append("Reads as a Latin/Greek prefix breakdown, not a vivid acoustic scene")

    elif kind == "etymology_story" or ETYM_ONLY_PATTERN.search(hook):
        if tier >= 3:
            parts.append("Etymology lecture without a punchy sound-alike keyword")
        else:
            parts.append("Etymology story with a concrete bridge to the meaning")

    elif kind == "sound_spelling" and not acoustic:
        parts.append("Tagged sound_spelling but no clear sound-alike anchor appears in the text")

    if acoustic:
        anchor = ", ".join(acoustic[:2])
        if tier == 1:
            parts.append(f"Elite acoustic anchor(s) '{anchor}' fused to an absurd, visual meaning")
        elif tier == 2:
            parts.append(f"Clear acoustic anchor(s) '{anchor}' tied to the definition")
        elif tier == 3:
            parts.append(f"Mild sound link via '{anchor}' but the image stays flat")
        else:
            parts.append(f"Weak or stretched sound link via '{anchor}'")

    if has_visual and tier <= 2:
        parts.append("includes a concrete or absurd visual action")
    elif not has_visual and tier >= 3:
        parts.append("lacks a memorable visual scenario")

    if length > 130 and tier >= 3:
        parts.append("too long to scan quickly on test day")

    if tier == 5 and overlap >= 0.9:
        parts.append("restates the definition instead of building a mnemonic device")

    defaults = {
        5: "Fails acoustic + visual mnemonic criteria; rewrite from scratch.",
        4: "High-friction hint — logical but unlikely to survive test stress.",
        3: "Passable study note, not a true memory hack.",
        2: "Solid, memorable bridge even if not outrageous.",
        1: "Master-tier acoustic + visual retention hook.",
    }
    if parts:
        return "; ".join(parts[:3]).rstrip(".") + "."
    return defaults[tier]


def score_hook(word: str, definition: str, kind: str | None, hook: str | None) -> AuditResult:
    if not hook or not hook.strip():
        return AuditResult(word, "(none)", 5, build_rationale(
            tier=5, kind=kind, hook="(none)", acoustic=[], has_visual=False, overlap=0, length=0
        ))

    hook = hook.strip()
    acoustic = acoustic_keywords(word, hook)
    has_visual = bool(VISUAL_CUES.search(hook) or ACTION_CUES.search(hook))
    overlap = overlap_ratio(definition, hook)
    length = len(hook)
    w = word.lower()

    # Tier 3 baseline: morphology / root templates
    if kind == "morphology" or MORPHOLOGY_PATTERN.search(hook):
        tier = 4 if length > 130 or (not acoustic and not has_visual and overlap >= 0.35) else 3
        return AuditResult(
            word, hook, tier,
            build_rationale(tier=tier, kind=kind, hook=hook, acoustic=acoustic,
                            has_visual=has_visual, overlap=overlap, length=length),
        )

    # Tier 3–4: etymology stories
    if kind == "etymology_story" or ETYM_ONLY_PATTERN.search(hook):
        tier = 4 if length > 150 or "historically" in hook.lower() else 3
        if has_visual and acoustic:
            tier = 2
        return AuditResult(
            word, hook, tier,
            build_rationale(tier=tier, kind=kind, hook=hook, acoustic=acoustic,
                            has_visual=has_visual, overlap=overlap, length=length),
        )

    # sound_spelling cluster (evaluate before trashing unknown kinds)
    if kind == "sound_spelling":
        masterpiece_words = {
            "abscond", "abrogate", "abhor", "cacophony", "abject",
        }
        if w in masterpiece_words or (
            acoustic
            and has_visual
            and length <= 100
            and overlap < 0.4
            and any(x in hook.lower() for x in (
                "steal", "scone", "gate", "broken", "horror", "cackl", "thrown", "wretched",
                "running away", "secretly",
            ))
        ):
            tier = 1
        elif not acoustic:
            tier = 4
        elif has_visual and length <= 110:
            tier = 2 if length > 55 else 1 if len(acoustic) >= 2 else 2
        elif not has_visual:
            tier = 3
        elif length > 125:
            tier = 3
        else:
            tier = 2
        return AuditResult(
            word, hook, tier,
            build_rationale(tier=tier, kind=kind, hook=hook, acoustic=acoustic,
                            has_visual=has_visual, overlap=overlap, length=length),
        )

    # Tier 5: non-mnemonic paraphrase (unknown / legacy hooks only)
    if is_definition_restatement(definition, hook, kind):
        return AuditResult(
            word, hook, 5,
            build_rationale(tier=5, kind=kind, hook=hook, acoustic=acoustic,
                            has_visual=has_visual, overlap=overlap, length=length),
        )

    # Unknown kind fallback
    tier = 4
    if acoustic and has_visual and length <= 100:
        tier = 2
    elif acoustic:
        tier = 3
    return AuditResult(
        word, hook, tier,
        build_rationale(tier=tier, kind=kind, hook=hook, acoustic=acoustic,
                        has_visual=has_visual, overlap=overlap, length=length),
    )


def escape_md(text: str) -> str:
    return text.replace("|", "\\|").replace("\n", " ")


def render_report(results: list[AuditResult]) -> str:
    counts = {t: 0 for t in range(1, 6)}
    for r in results:
        counts[r.tier] += 1
    total = len(results)

    lines = [
        "# GlanceSAT Memory Hook Audit Report",
        "",
        "Audit source: `GlanceSAT/GlanceSAT/Database.json`",
        "",
        "Evaluation criteria: **acoustic bridge** (sound-alike keyword), **visual/semantic link** "
        "(vivid, absurd, active imagery), and **brevity** (punchy enough for test-day recall).",
        "",
        "Rows are sorted by severity: **Tier 5 (rewrite first)** through **Tier 1 (masterpiece)**.",
        "",
        "## Executive summary",
        "",
        "| Tier | Label | Count | Share |",
        "| --- | --- | ---: | ---: |",
        f"| 5 | Trash — useless / misleading | {counts[5]} | {counts[5]/total*100:.1f}% |",
        f"| 4 | Weak — high friction | {counts[4]} | {counts[4]/total*100:.1f}% |",
        f"| 3 | Mediocre — passable but forgettable | {counts[3]} | {counts[3]/total*100:.1f}% |",
        f"| 2 | Strong — highly effective | {counts[2]} | {counts[2]/total*100:.1f}% |",
        f"| 1 | Masterpiece — perfect retention | {counts[1]} | {counts[1]/total*100:.1f}% |",
        f"| **Total audited** | | **{total}** | **100%** |",
        "",
        "### Priority actions",
        "",
        f"1. **Rewrite Tier 5 first** ({counts[5]} hooks) — includes all missing hooks and definition paraphrases.",
        f"2. **Refine Tier 4 next** ({counts[4]} hooks) — weak sound bridges and overlong etymology notes.",
        f"3. **Upgrade Tier 3** ({counts[3]} hooks) — mostly morphology templates; inject sound-alike + visual scenes.",
        f"4. **Preserve Tier 1–2** ({counts[1] + counts[2]} hooks) as models for rewrites.",
        "",
        "## Full audit table",
        "",
    ]

    tier_labels = {
        5: "Tier 5 — Trash (Useless / Misleading)",
        4: "Tier 4 — Weak (High Friction)",
        3: "Tier 3 — Mediocre (Passable but Forgettable)",
        2: "Tier 2 — Strong (Highly Effective)",
        1: "Tier 1 — Masterpiece (Perfect Retention)",
    }

    for tier in (5, 4, 3, 2, 1):
        bucket = [r for r in results if r.tier == tier]
        bucket.sort(key=lambda r: r.word.lower())
        lines.extend([
            f"### {tier_labels[tier]} ({len(bucket)} words)",
            "",
            "| Word | Current Hook | Tier (1-5) | Rationale (Brief critique based on the criteria) |",
            "| --- | --- | :---: | --- |",
        ])
        for r in bucket:
            lines.append(
                f"| {escape_md(r.word)} | {escape_md(r.hook)} | {r.tier} | {escape_md(r.rationale)} |"
            )
        lines.append("")

    return "\n".join(lines)


def main() -> None:
    with DATABASE_PATH.open(encoding="utf-8") as handle:
        data = json.load(handle)

    results = [
        score_hook(entry["word"], primary_definition(entry), *hook_text(entry))
        for entry in data
    ]

    REPORT_PATH.parent.mkdir(parents=True, exist_ok=True)
    REPORT_PATH.write_text(render_report(results), encoding="utf-8")

    counts = {t: sum(1 for r in results if r.tier == t) for t in range(1, 6)}
    print(f"Wrote {REPORT_PATH} ({len(results)} rows)")
    print("Tier counts:", counts)


if __name__ == "__main__":
    main()
