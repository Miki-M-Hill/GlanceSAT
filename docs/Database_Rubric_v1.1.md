# GlanceSAT — Database Final Pass  
## Master Rubric **v1.1** (Source of Truth)

### Mission
Ship **trust-first, SAT-useful, glance-safe** vocabulary data in **one disciplined pass**: add **`passageDomain`**, **`semanticCharge`**, optional **`memoryHook`**, and **avoid unnecessary churn** of existing synonyms, difficulty, frequency, and examples.

---

## A) Scope rules (non‑negotiable)

### A1) Default: **frozen fields**
Do **not** edit these unless they fail **§G (broken-row checks)** **or** **§K (definition display-safety)**:
- `synonyms`
- difficulty fields (`difficultyLevel` / `difficulty` — use what exists in your schema)
- frequency fields (`frequencyTier` / equivalents)
- `exampleSentence`

### A2) Always in scope for this pass
- Add / correct: **`passageDomain`**
- Add / correct: **`semanticCharge`**
- Add / correct: **`memoryHook`** (`null` allowed and encouraged)

### A3) Explicitly **out of scope** (do not add fields for)
- `confusable_anchor`, `collocation_chip`, `student_frame`, `syntax_role`, `wrong_answer_vibe`
- Separate “glance line” fields

### A4) `register` (formality)
**Not used in v1.1.**

---

## B) Canonical field: `passageDomain`

**Type:** string, **closed enum** (exactly one per row)

### B1) The five student-facing domains
1. **`human_social`** — *People interacting* (norms, groups, social behavior, cooperation/conflict between people)
2. **`self_character`** — *Feelings, self, and character* (emotion, temperament, motivation, inner traits)
3. **`thought_language`** — *Thinking, arguing, and wording* (logic, judgment, language, academic/intellectual process)
4. **`science_world`** — *Science, bodies, and the physical world* (STEM, nature, environment, health, measurement)
5. **`power_culture`** — *Power, rules, money, arts, and big ideas* (law/politics/institutions + arts/literature/religion/history/commerce/culture)

### B2) Slug → domain mapping (from current `category` slugs)

| Current `category` slug | `passageDomain` |
|---|---|
| `social-behavior` | `human_social` |
| `emotion-character`, `emotional`, `emotion` | `self_character` |
| `intellect-judgment`, `logic-reasoning`, `language-communication`, `academic`, `general-academic`, `formal-register`, `language`, `perception-quality` | `thought_language` |
| `science-engineering`, `science`, `environment`, `science-nature`, `health-body`, `science-method` | `science_world` |
| `law-ethics`, `politics-power`, `politics-law`, `legal`, `political`, `conflict-power`, `arts-literature`, `literary`, `arts`, `religion-philosophy`, `religion`, `history`, `business-economy`, `commerce`, `food-culture` | `power_culture` |

### B3) Overrides & polysemy (read with §F)
1. **Missing / novel slug:** assign using **definition + example sentence world**; flag internally if tooling allows.
2. **Slug vs example mismatch:** if slug maps to domain X but the **example sentence clearly lives** in domain Y, **choose Y** (**example wins**).
3. **Polysemy / multiple senses:** assign `passageDomain` to the **primary sense surfaced to learners** (same primary sense rule as §F). If a secondary sense would imply a different domain, record that in **internal annotation only** — **do not invent a sixth domain**.

### B4) `literary` slug (locked)
Slug **`literary` → `power_culture`**. If the example world clearly contradicts `power_culture`, apply **B3#2** (example wins).

### B5) `power_culture` — editor guidance (not new domains)
`power_culture` spans **institutional/system** language and **cultural/arts/belief** language.

**Tiebreaker (still `power_culture` either way):**
- Example centers **authority, rules, institutions, markets, war/peace, civic action** → read as **institutional** flavor.
- Example centers a **created work, performance, belief practice, historical/cultural artifact** → read as **cultural** flavor.

**Optional internal note:** `pculture:institutional` vs `pculture:cultural` on audit sheet — **not** a required JSON field in v1.1.

---

## C) Canonical field: `semanticCharge`

**Type:** string, **closed enum:** `negative` · `neutral` · `positive` · `mixed` (mixed is **rare**)

### C1) Rules
- **`neutral` bias** for classifiers/processes/structures unless the word routinely imports praise/blame in SAT-like prose.
- **`positive` / `negative`** when swapping charge commonly flips sentence **moral/emotional direction**.
- **`mixed`** only per **§C2** calibration.

### C2) `mixed` — two calibration examples (required)

**Example 1 — *zealous*** → `mixed`  
**Why not `neutral`:** Commonly swings between **admiring** (“zealous advocacy”) and **alarming** (“zealous followers”); neither reading is clearly secondary like a trivial secondary sense.

**Example 2 — *mercurial*** → `mixed`  
**Why not `neutral`:** Can read **lively/clever** *or* **unreliable/unstable** depending on author stance; not a stable neutral descriptor like *variable* in a technical sense.

**Boundary (`mixed` vs `neutral`):** If the word is **stable** across typical contexts (*deliberate*, *document*, *structure*), use **`neutral`**, even in emotionally heated passages. **`mixed` = genuinely split evaluations**, not “sometimes appears in sad sentences.”

---

## D) Optional field: `memoryHook`

### D1) Allowed shapes
```json
"memoryHook": null
```
or
```json
"memoryHook": {
  "kind": "etymology_story" | "morphology" | "sound_spelling",
  "text": "string",
  "parts": [ { "piece": "string", "gloss": "string" } ]
}
```
(`parts` optional; morphology only.)

### D2) Global hook rules
- **`text` max length:** **140 characters** (prefer **90–120**).
- **One hook maximum** per row.
- **American English** spelling in hooks.
- **No** stereotypes, shock humor, “random internet voice.”

### D3) A-tier vs B-tier (required calibration)

**A-tier = publishable.** Passes all:
1. **Truth / defensibility** (no fake morphology; etymology stories not overclaimed)
2. **Meaning leverage** (improves recall of **primary** meaning)
3. **Length discipline** (D2)
4. **Novelty without stretch** (one clean hop)

**B-tier = forbidden → `null`.** Fails any of:
- Dictionary transfer chain disguised as a “story”
- Forced / fake morphology
- Loose sound puns that don’t stabilize meaning

**A-tier examples**
- **Morphology:** *inconspicuous* — honest `in-` + `conspic-` + `-uous` → meaning “not easily noticed.”
- **Etymology story:** *behemoth* — biblical beast → metaphor for anything huge/powerful (no over-specific zoology claim).
- **Sound / spelling / meaning bridge (`sound_spelling`):** use this kind whenever the latch is **phonetic**, **homophone/near-homophone**, or a **tight English echo** that stabilizes meaning—not only “hard spelling” cases like *colonel* / *kernel*.
  - **A-tier bridge:** one hop, meaning-locked, no fake etymology (e.g. *abet* ↔ *bet* on encouragement; *abate* ↔ *bait* on “less bait → fewer catches” as a reduce/lessen image; *abase* ↔ *base* as “lowered to a base / low point” for humiliation).
  - **B-tier:** second clause is random, or the bridge does not change what the word *means* in context.

**B-tier examples**
- *compliment* hook that is only “from French compliment, Italian complimento…”
- Fake breakdown of *unique*
- “E-phem-eral sounds like a fairy; fairies love glitter” (*ephemeral*) — second clause random; link too loose

### D4) `null` policy
`null` is **success** when any non-null hook would be B-tier.

### D5) Hook density ceiling
- **≤ 30%** of corpus rows may have **`memoryHook != null`** (cumulative).
- If cumulative **> 30%**, **stop** and **raise the A-tier bar** (do not lower quality to fit the ceiling).

---

## E) `etymology` (reference)
- Keep as **reference**; do not paste long chains into `memoryHook.text`.

---

## F) Multi-sense policy
- **Primary surfaced sense** drives primary **definition**, **example**, **`semanticCharge`**, **`passageDomain`**.
- Secondary sense domain mismatch → **internal note only** (B3#3).

---

## G) Broken-row checks (touch frozen fields only if)

### G1) `exampleSentence` broken
empty / placeholder / wrong sense / unsafe / ungrammatical

### G2) `synonyms` broken
empty where needed, duplicates, clearly wrong relations

### G3) difficulty / frequency broken
missing or contradictory to documented tier meaning

If none: **do not touch**.

---

## K) Definition display-safety
**`definition` ≤ 60 characters** (`String.count` / extended grapheme clusters).

- Hygiene edit allowed **for display** even if §G does not trigger, **if** shortening preserves core meaning and does not mislead vs the example.
- If impossible without misleading → **flag for product decision** (do not ship bad brevity).

---

## H) Batch QA (250 rows)

### H1) Mechanical
- `passageDomain` valid · `semanticCharge` valid · `memoryHook` null or valid + `text` ≤ 140 · `definition` ≤ 60 · cumulative non-null hook rate ≤ 30%

### H2) Human sampling
- **25 / 250 (10%)** full read minimum
- **100%** read for `etymology_story` or `sound_spelling`

### H3) Stop rule
**>2%** batch failures after fixes → pause, fix rubric drift, then continue.

---

## I) Per-row checklist
- [ ] `passageDomain` (B3 as needed)
- [ ] `semanticCharge` (C2 discipline)
- [ ] `memoryHook` null or A-tier (D3)
- [ ] `definition` ≤ 60 (K)
- [ ] Frozen fields untouched unless G or K
- [ ] Cumulative hook rate ≤ 30% (D5)

---

**End of Rubric v1.1**
