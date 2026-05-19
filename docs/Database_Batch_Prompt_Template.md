# Database batch — copy/paste prompt template

Use one message per batch. Fill in **ALL CAPS** placeholders before sending.

---

## Prompt (copy everything below the line into Cursor)

---

**GlanceSAT — Database batch pass (v1.1 rubric)**

**Authoritative spec (follow exactly; do not invent rules):**  
Read and apply: `docs/Database_Rubric_v1.1.md`

**Micro-checklist (must all be true for this batch):**
1. Add/update only: `passageDomain`, `semanticCharge`, `memoryHook` (and `definition` **only** if rubric §K requires ≤60 chars or meaning breaks layout).
2. **Frozen by default:** `synonyms`, difficulty fields, frequency fields, `exampleSentence` — change **only** if rubric **§G** says broken.
3. **`memoryHook`:** only `null` | `etymology_story` | `morphology` | `sound_spelling`; **A-tier only**; **B-tier → null**.  
   - **`sound_spelling`** also covers **tight meaning bridges** (homophone / image / English echo)—see rubric §D3 (not only *colonel*/*kernel* spelling traps).
4. **`definition`:** must be **≤ 60 characters** after your edits; if faithful shortening is impossible without misleading the learner, **flag the word** in a short “Flags” list at the end (do not fake a short definition).
5. **Hook ceiling (cumulative):** After this batch, non-null hooks must stay **≤ 30%** of all words processed so far. If this batch would exceed the ceiling, **prefer null** for borderline hooks.

**Batch metadata**
- **Batch ID:** `BATCH_ID` (e.g. `batch_001`)
- **Input file (250 word objects, same shape as `Database.json` entries):** `PATH/TO/batch_XXX.json`  
  *(Or paste the JSON array in a fenced `json` block if not using a file.)*
- **Cumulative stats before this batch:**  
  - Total words already processed (all prior batches): `N_PRIOR`  
  - Non-null `memoryHook` count so far: `HOOKS_PRIOR`  
  - (Optional) Running list file you maintain: `PATH/TO/hook_stats.txt`

**Input contract**
- Exactly **250** entries in **stable order** (do not reorder).
- Each input object must include at least `id` and `word` so patches are merge-safe.

**Output contract (required format)**

1. **`patches` JSON array** — exactly **250** objects, **same order** as input.  
   Each object **must** include:
   - `id` (UUID string, must match input)
   - `word` (must match input, for human diff sanity)
   - `passageDomain` (one of: `human_social` | `self_character` | `thought_language` | `science_world` | `power_culture`)
   - `semanticCharge` (one of: `negative` | `neutral` | `positive` | `mixed`)
   - `memoryHook` — either `null` or a valid object per rubric §D

   **Optionally** include **only** if allowed by rubric:
   - `definition` — if and only if §K required edit or §G broken
   - any other frozen-field keys — **only** if §G triggered

2. **`batch_stats`** (JSON object at end of message, after the array) with:
   - `batchId`
   - `count`: 250
   - `nonNullHooksInBatch`: integer
   - `cumulativeWordsProcessedAfterBatch`: `N_PRIOR + 250`
   - `cumulativeNonNullHooksAfterBatch`: `HOOKS_PRIOR + nonNullHooksInBatch`
   - `cumulativeNonNullHookRateAfterBatch`: decimal (3 places), formula `(cumulativeNonNullHooksAfterBatch) / (cumulativeWordsProcessedAfterBatch)`
   - `ceilingOk`: boolean — `true` iff cumulative rate **≤ 0.30**; if `false`, explain in one sentence what to do next

3. **`flags`** — JSON array of `{ "id", "word", "reason" }` for any row you could not shorten `definition` safely, or any rubric conflict; empty array if none.

**Quality bar**
- Apply **§D3** A-tier/B-tier calibration literally; when unsure, **`memoryHook`: null**.
- Apply **§B3** (example wins over slug) and **§F** (primary sense) for domain/charge.
- **100%** self-review for every row where `memoryHook.kind` is `etymology_story` or `sound_spelling` before returning output.

**Do not**
- Add banned hook types (rubrics §A3).
- Output prose instead of the structured `patches` + `batch_stats` + `flags` deliverables.
- Drop or add rows (must remain 250).

---

**END PROMPT**

---

## After the model responds

1. **Merge** each patch into `GlanceSAT/GlanceSAT/Database.json` (or your ETL) by `id`.  
2. **QA sample:** randomly review **25/250** rows against the rubric.  
3. **Update cumulative hook stats** for the next prompt’s placeholders.

---

## Placeholder quick reference

| Placeholder | Example |
|-------------|---------|
| `BATCH_ID` | `batch_001` |
| `PATH/TO/batch_XXX.json` | `db_batches/batch_001.json` |
| `N_PRIOR` | `0` (first batch) then `250`, `500`, … |
| `HOOKS_PRIOR` | running count of non-null hooks after all prior batches |
