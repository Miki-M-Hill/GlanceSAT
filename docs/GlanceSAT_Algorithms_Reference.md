# GlanceSAT — Algorithms & Implementation Reference

| Field | Value |
|-------|--------|
| **Document type** | Technical reference for engineering, pedagogy, and product review |
| **Product** | GlanceSAT iOS app (+ widget extension) |
| **Scope** | Runtime algorithms: scheduling, daily batch, quiz construction, learner-state updates, streak plant, analytics, widget sync |
| **Out of scope** | Offline Python/database batch tooling except where bundled JSON fields drive runtime behavior |
| **Source of truth** | Swift under `GlanceSAT/GlanceSAT/` and `GlanceSAT/GlanceSATWidgets/` |
| **Last updated** | May 2026 (platform hardening: App Group lock, streak day keys, debounced reloads) |

---

## Executive summary

GlanceSAT coordinates five main systems:

1. **Spaced repetition (SRS)** — SM-2–style scheduling per word after each graded interaction that applies SRS.
2. **Calendar-day word batch** — Exactly **10 words per calendar day**, **locked until local midnight**, shared by Today, the primary daily quiz, and widgets.
3. **Quiz assembly** — `QuizGenerator` builds up to 10 items (synonym, sentence, connotation foil) with per-question SRS flags for supplemental rounds.
4. **Streak plant & streak count** — Persisted evolution tier, wilt/demotion on missed dailies, honest streak count with **one grace day**; plant art and streak number are related but not identical.
5. **Analytics** — `QuizSession` rows power Insights; per-word counters and `lastSuccessfulReviewDate` power category bars and weekly metrics.

**Graded surfaces**

| Surface | Updates SRS? | Notes |
|---------|--------------|-------|
| Primary daily quiz | Yes (all items) | `quality` 1 / 3–5 from latency on correct; `appliesSRS` true on every question |
| Supplemental quiz — today’s **misses** | **No** | Practice after primary lapse; `appliesSRS == false` |
| Supplemental quiz — **fill** words | **Yes** | SRS fill from prior daily batches / due pool; `appliesSRS == true` |
| Widget “Know” | Yes | `quality` 5; `reviewedAt` = tap time |
| Widget “Reveal example” | No | UI-only queue entry |
| Widget after primary quiz done | No new words | **Rest** timeline until midnight (§8.4) |

There is **no global priority queue** beyond sort descriptors (onboarding rank, due date, frequency for catalog fallback).

---

## 1. Architecture overview

| Concern | Primary module(s) | Role |
|--------|-------------------|------|
| Calendar-day batch | `DailyWordBatchService.swift` | 10-word daily set; **calendar-day lock**; batch history; widget reconcile |
| Supplemental quiz plan | `SupplementalQuizPlanner.swift` | Missed-first + SRS fill to 10; eligibility for “Take another quiz” |
| Spaced repetition | `SRSEngine.swift` | Interval, ease, dates, status, `lastSuccessfulReviewDate` |
| Streak plant state | `StreakPlantState.swift` | Evolution tier, wilt, demotion, last primary quiz day |
| Streak day count | `QuizStreakCalculator.swift` | Consecutive quiz days with **one grace day** |
| Widget daily rest | `WidgetDailyState.swift` | Primary-quiz-done flag for widget rest UI |
| Today / quiz shell | `DailyHubView.swift` | UI; sync; primary + supplemental; plant animations |
| Question construction | `QuizGenerator.swift` | Synonym, sentence, foil; `srsEligibleWordIDs` tagging |
| Quiz UI & grading | `DailyQuizView.swift`, `ConnotationFoilView.swift` | Per-question `applySRSUpdate` |
| Session history | `QuizSession.swift` | One row per completed quiz |
| In-progress quiz | `DailyQuizPersistence.swift` | `UserDefaults` resume; `appliesSRS` on questions |
| Insights | `ProgressViewModel.swift`, `ProgressView.swift` | Aggregates; optional accuracy; mastered strict |
| App Group coordination | `AppGroupFileLock.swift`, `WidgetPendingEventsStore.swift` | Cross-process lock + file-backed event queue |
| Widget timeline reload | `WidgetTimelineReloader.swift` | Debounced `WidgetCenter` reload (host) |
| Widget reconcile | `WidgetInteractionReconciler.swift` | Pending events → SRS (know only) |
| Widget snapshot | `WidgetSnapshotWriter.swift` | Delegates to batch refresh |
| Widget timeline | `GlanceSATVocabularyWidget.swift` | Rotate daily 10, or **rest** entry after primary quiz |
| Vocabulary import | `WordJSONImportService.swift` | Insert missing rows; sync lexical metadata only |
| Library | `ExploreView.swift` | Filter/search only |

**Persistence**

- **SwiftData:** `Word`, `QuizSession`, `Item`
- **App Group:** `daily_word_batch.json`, `daily_batch_history.json`, `widget_words_snapshot.json`, `widget_pending_events.json`, `.widget_app_group.lock`, widget interaction + plant/streak `UserDefaults`

---

## 2. Calendar-day word batch (`DailyWordBatchService`)

**File:** `GlanceSAT/GlanceSAT/DailyWordBatchService.swift`  
**Constant:** `maxDailyWords = 10`

Today, the **primary** daily quiz, and widgets all consume the **same 10 word IDs** for the current calendar day (`yyyy-MM-dd` in the user’s calendar/time zone).

### 2.1 Calendar-day lock (Batch A)

Once today’s ten `wordIDs` are written to `daily_word_batch.json` for `calendarDayKey == today`:

- **Same-day refresh** only **resolves** those UUIDs in stored order.
- **No** `filterDueWords` swaps, **no** backfill replacements for the daily ten.
- Supports passive widget exposure and a stable evening quiz on the same headwords all day.

A **new** batch is selected only when:

- `calendarDayKey` changes (local midnight), or
- Persisted batch is missing, corrupt, or for a different day.

On day rollover, the **previous** day’s `wordIDs` are appended to batch history (§2.5) before today’s batch is created.

### 2.2 Refresh pipeline (`refresh`)

1. **`WidgetDailyState.clearIfNotToday`** — Clear primary-quiz-done widget flag after midnight.
2. **`StreakPlantState.clearIfNotToday`** — Clear stale wilt keys if needed.
3. **`WidgetInteractionReconciler.applyPendingEvents`** — Apply queued widget SRS before building the batch.
4. **Archive prior day** — If persisted `calendarDayKey != today`, append old `wordIDs` to `daily_batch_history.json`.
5. **Load or create batch**
   - If persisted key matches today → `resolveWords(wordIDs:)` in order.
   - Else → `selectNewBatch` (new day only).
6. **Persist** `wordIDs` + `calendarDayKey`.
7. **Write widget snapshot** + reload timelines.

**Removed from same-day path:** due-filter/backfill that swapped words out of today’s ten after widget “Know” or schedule changes.

### 2.3 New batch selection (`selectNewBatch`)

When today has no valid persisted batch:

1. Fetch up to 10 words with `nextReviewDate <= referenceDate`, sorted by §2.4.
2. If empty → `selectCatalogFallbackBatch` (§2.4).

### 2.4 Sort descriptors

**Due words:**

```text
SortDescriptor(\.onboardingRank, forward)
SortDescriptor(\.nextReviewDate, forward)
```

**Catalog fallback** (nothing due): `frequencyRank` ↑, `difficulty` ↑, `onboardingRank` ↑, then **day-keyed shuffle** (`DayKeyedRNG(dayKey:)`).

### 2.5 Batch history (supplemental fill)

**File:** `daily_batch_history.json` (App Group)

- Up to **60** entries: `{ calendarDayKey, wordIDs[] }`.
- Filled when the calendar day rolls (previous day archived).
- **`SupplementalQuizPlanner`** prefers **due** words whose IDs appeared in past daily batches (excluding today + remembered), then any other due words.

### 2.6 Widget rotation (extension)

**File:** `GlanceSATWidgets/GlanceSATVocabularyWidget.swift`

- If **not** primary-quiz-rest (§8.4): **48** entries/day, 30-minute slots, cycling the daily ten.
- If primary quiz completed for today: **single rest entry** until midnight.

---

## 3. Learner state model (`Word`)

### 3.1 SRS fields (mutable at runtime)

| Field | Default | Meaning |
|-------|---------|---------|
| `easeFactor` | `2.5` | Interval multiplier on success; reduced on failure |
| `interval` | `1` | Days until next review after latest grade |
| `status` | `"new"` | `"learning"` \| `"review"` \| `"mastered"` (§4.4) |
| `nextReviewDate` | import `Date()` | When word becomes due |
| `lastReviewDate` | `nil` | Last graded interaction (any quality) |
| `lastSuccessfulReviewDate` | `nil` | Last success only (`quality >= 3`); Insights weekly remembered |
| `totalAttempts` | `0` | +1 per `calculateNextReview` |
| `successfulRecalls` | `0` | +1 per success only |
| `consecutiveCorrect` | `0` | Success streak; reset on failure |

### 3.2 Bundled metadata (from `Database.json`)

See prior fields: `passageDomain`, `semanticCharge`, `tonalFoilId`, `onboardingRank`, `quizSentence`, `sensesJSON`, etc.  
**Import:** `WordJSONImportService.syncBundledLexicalMetadata` does **not** overwrite SRS progress.

### 3.3 Quiz lexical helpers (`Word` extension)

| Property | Behavior |
|----------|----------|
| `quizPrimarySenseBlock` | Pinned sense for quizzes (§6.7) |
| `quizSynonyms` | Synonyms from **pinned sense only** |
| `quizCompletionSentence` | `quizSentence` if set, else `exampleSentence` |
| `hasSuccessfulRecall` | `successfulRecalls >= 1` (foil gating) |

---

## 4. Spaced repetition (`SRSEngine`)

**File:** `GlanceSAT/GlanceSAT/SRSEngine.swift`  
**API:** `calculateNextReview(word:quality:reviewedAt:)`

- **`quality`:** Incorrect → **`1`**. Correct in daily quiz → **`5`** (≤2.5s), **`4`** (≤5s), **`3`** (slower). Widget Know remains **`5`**.
- **`reviewedAt`:** Widget uses **tap time** (`min(event.date, Date())`).

### 4.1–4.4 SM-2 rules

Unchanged: failure/success ease and interval rules; `status` from `consecutiveCorrect` (mastered at ≥ 5).

### 4.5 Call sites

| Caller | SRS? | Notes |
|--------|------|-------|
| `DailyQuizView` | If `question.appliesSRS` | Primary: all true; supplemental misses: false; fill: true |
| `WidgetInteractionReconciler` know | Yes | `quality` 5 |
| Legacy `review` events | Reconciled but **no UI** (Batch B) | No new review taps |

---

## 5. Today tab & quiz flow (`DailyHubView`)

**File:** `GlanceSAT/GlanceSAT/DailyHubView.swift`

### 5.1 Primary daily quiz

1. `WordJSONImportService.importIfNeeded`
2. `syncDailyWords()` → batch refresh + streak reconcile
3. Resume or `QuizGenerator().generateQuiz(for: dailyWords)` (all questions `appliesSRS: true`)
4. On completion:
   - `rememberedWordIDs` / `missedWordIDs` — **frozen** for post-quiz UI (primary only)
   - `supplementalRememberedWordIDs` / `supplementalMissedWordIDs` — initialized; updated only on supplemental rounds
   - `quizCompletedToday = true`
   - `WidgetDailyState.markPrimaryQuizCompleted(streakDays:)`
   - `StreakPlantState.markPrimaryQuizCompleted(streakDays:)`
   - Union `usedQuestionSlots`

### 5.2 Supplemental quiz (Batch C)

**Eligibility** (`SupplementalQuizPlanner.canOfferSupplementalQuiz`):

- At least one word in plan: today’s **missed** daily words (not in `rememberedWordIDs`) **or** SRS **fill** to 10.

**Word order:**

1. Today’s missed daily words (batch order), not in `supplementalRememberedWordIDs`.
2. Fill: due words from **past daily batches** (history), excluding today’s ten and remembered IDs.
3. If still short: any other due words (same exclusions).
4. If still short: **`selectCatalogFallbackBatch`** (same catalog fallback as §2.3) so a caught-up user can still get a 10-word supplemental deck.

**Generation:** `QuizGenerator.generateQuiz(..., srsEligibleWordIDs: fillWordIDs)` — fill words get `appliesSRS: true`; today’s misses get `appliesSRS: false`.

**After supplemental completion:**

- Update **only** `supplementalRememberedWordIDs` / `supplementalMissedWordIDs` (for next supplemental plan).
- **Do not** change primary `rememberedWordIDs` / `missedWordIDs` (pills + card tags stay primary results).
- Union `usedQuestionSlots`.

**UI:** “Take another quiz” hidden when plan is empty. Footnote: original score unchanged.

**Multi-round:** Each supplemental removes correct words from supplemental miss set; fill pool refreshes; up to 10 questions per round.

### 5.3 Post-quiz word labels (UI only)

| Label | Source |
|-------|--------|
| Remembered | `rememberedWordIDs` (primary, frozen) |
| Missed | `missedWordIDs` (primary, frozen) |
| Returning tomorrow | In daily batch, neither set |

Streak bar subtitle uses **`evolutionPlantStage.message`** (tier-based), not wilt-specific copy.

---

## 6. Quiz generation (`QuizGenerator`)

**File:** `GlanceSAT/GlanceSAT/QuizGenerator.swift`

### 6.1 `QuizQuestion.appliesSRS`

- Default **true** for primary quiz.
- When `srsEligibleWordIDs` is provided, `appliesSRS = eligible.contains(targetWord.id)`.
- Persisted in `PersistedQuizQuestion` for resume.

### 6.2–6.8 Item mix, foil, morphology, sequencing, primary sense

Unchanged from prior doc: foil ≤1, sentences ≤3, synonyms ≤6, `canUseSentenceCompletion`, sequencing lock, `quizPrimarySenseBlock`, recency distractors.

---

## 7. Quiz runtime (`DailyQuizView`)

### 7.1 Grading

```text
applySRSUpdate: guard question.appliesSRS else { return }
```

Supplemental practice on today’s misses does not move SRS.

### 7.2 Session record

Still inserts `QuizSession` for **both** primary and supplemental completions.

| Field | Meaning |
|-------|---------|
| `startedAt` | Wall-clock quiz start (duration / history) |
| `calendarDayKey` | Local `yyyy-MM-dd` at **start** (streak credit); resume via `PersistedDailyQuiz` |
| `durationSeconds`, `totalQuestions`, `correctAnswers` | Summary stats for Insights |

### 7.3 Latency-based SRS quality (primary + supplemental when `appliesSRS`)

| Outcome | Response time | `quality` |
|---------|---------------|-----------|
| Incorrect | any | `1` |
| Correct | ≤ 2.5 s | `5` |
| Correct | ≤ 5.0 s | `4` |
| Correct | > 5.0 s | `3` |

Timer resets on each new question via **`resetQuestionTimer()`**, triggered by:

- `.onChange(of: activeQuestionID, initial: true)` — includes first card on mount (plain `onChange` skips initial render)
- `.onChange(of: questionDeckToken, initial: true)` — supplemental round replaces the deck at index 0
- `advanceToNextQuestion()` — explicit reset after index bump

Do **not** rely on `.onAppear` alone (multi-round supplemental can reuse the view without a second appear).

---

## 8. Widget integration

### 8.1 Recording events (extension)

**File:** `GlanceSATWidgets/WidgetWordIntents.swift`

- **Know** — SRS success + dismissed from rotation set.
- **Reveal example** — No SRS.
- **Review** — **Removed** (Batch B). Legacy queued `.review` events: applied at reconcile but **no SRS failure** (no-op for scheduling).

Pending events are appended to **`widget_pending_events.json`** under **`AppGroupFileLock`**. Writes use **tmp + POSIX `rename`** (`AppGroupAtomicJSONFile`) so jetsam mid-write cannot corrupt the queue; decode failures delete the file and return `[]`. Legacy `UserDefaults` queue rows are migrated on first read.

### 8.2 Reconciliation (host app)

**Files:** `WidgetInteractionReconciler.swift`, `WidgetReconcileActor.swift`

1. **`Task.detached`** drains `widget_pending_events.json` under `flock` (never blocks the main thread waiting on the extension).
2. **`WidgetReconcileActor`** (`@ModelActor`) applies Know SRS + `UserDefaults` dedupe keys.
3. Invoked from `await DailyWordBatchService.refresh` and on `scenePhase == .active` / timezone change via `Task { await refreshWidgetDataFromHost() }`.

### 8.3 Snapshot

Writes current daily batch (≤ 10) + `calendarDayKey`.

### 8.4 Rest state after primary quiz (Batch D)

**File:** `WidgetDailyState.swift` (App Group `UserDefaults`)

| Key | Meaning |
|-----|---------|
| `widget.primaryQuizCompletedDayKey` | `yyyy-MM-dd` when user finished **primary** quiz |
| `widget.streakDays` | Streak count at completion (for rest plant hero) |

When `primaryQuizCompletedDayKey == today`:

- Timeline: **one** entry until midnight (no 30-minute word rotation).
- **Lock screen (rectangular / inline):** leaf + “Rest. See you tomorrow.”
- **Home small+:** streak plant asset + “Rest.” / “See you tomorrow” (no Know/Reveal).

Cleared at midnight via `clearIfNotToday` during batch refresh.

### 8.5 Wilted assets (widgets)

Rest UI uses healthy streak plant images by tier; wilted assets are Today-tab only.

### 8.6 Stale snapshot / timezone

If `widget_words_snapshot.json` `calendarDayKey` ≠ widget’s local today, the timeline shows a **stale** placeholder (“Updating today's words…”) and retries every **15 minutes**. The host refreshes batch + snapshot on **active** and **`NSSystemTimeZoneDidChange`**. Midnight rollover does **not** run `selectNewBatch` in the extension.

### 8.7 Timeline reload coalescing

**File:** `WidgetTimelineReloader.swift` — Host debounces `WidgetCenter.reloadTimelines` (~0.4s) after batch refresh / primary-done flag. Widget intents still reload immediately so dismissals feel instant.

---

## 9. Insights aggregates (`ProgressViewModel`)

Unchanged thresholds and rules: mastered = `status == "mastered"`; `quizAccuracy` optional until 20 questions; `weeklyRemembered` uses `lastSuccessfulReviewDate`.

**Streak on Insights:** `QuizStreakCalculator` (§10) — same grace-day rule as Today.

---

## 10. Streak algorithms

### 10.1 Streak day count (`QuizStreakCalculator`)

**File:** `GlanceSAT/GlanceSAT/QuizStreakCalculator.swift`

**Rule:** Consecutive calendar days with a completed quiz, keyed by **`QuizSession.calendarDayKey`** (frozen at quiz **start**; legacy rows fall back to `startedAt`). Walks backward on `yyyy-MM-dd` strings from **today** (or **yesterday** if today has no session yet), allowing **exactly one** calendar day without a session before the chain breaks.

| Scenario | Displayed streak |
|----------|------------------|
| Miss **1** day | **Unchanged** (grace absorbs the gap; missed day not counted) |
| Quiz again next day | Increments (e.g. 7 → 8) |
| Miss **2+** consecutive days | Resets (grace exhausted) |

**Used by:** `DailyHubView.quizStreakDays`, `ProgressViewModel.currentStreak`.

**Note:** Streak **number** is factual (with grace). **Plant tier** is separate (§11).

### 10.2 Today tab display

- **`displayedStreakDays`** — `quizStreakDays`, optional debug override, or `frozenStreakDays` while quiz cover open.
- **Optimistic today** — If primary quiz completed for display, today counts as a session day for streak walk.

### 10.3 Insights streak

Same `QuizStreakCalculator` on `QuizSession.creditedQuizDayKey`; no optimistic today injection in `ProgressViewModel`.

---

## 11. Streak plant (`StreakPlantState` + UI)

**File:** `StreakPlantState.swift`, `StreakPlantStage` enum, `DailyHubView` streak bar

### 11.1 Evolution tiers (persisted)

| Tier | Stage | Healthy asset | Wilted asset |
|------|-------|---------------|--------------|
| 0 | Pot (`day0`) | `StreakPlantDay0` | *(none — pot only)* |
| 1 | Seedling (`day1`) | `StreakPlantDay1` | `StreakPlantWiltedDay1` |
| 2 | Young (`day3`) | `StreakPlantDay3` | `StreakPlantWiltedDay3` |
| 3 | Mature (`day7`) | `StreakPlantDay7` | `StreakPlantWiltedDay7` |

`evolutionTier` grows on primary quiz complete: `max(currentTier, StreakPlantStage(days: streakDays).evolutionTier)`.

Subtitle message always uses **healthy** stage message for tier (e.g. “taking root”), even when wilted.

### 11.2 Missed daily quiz (wilt)

**Detection:** `reconcileMissedDays` — for each calendar day **after** `lastPrimaryQuizDayKey` through **yesterday** without a primary quiz marked that day, `applyMissedDay()`.

| Consecutive missed days processed | Effect |
|-----------------------------------|--------|
| 1 | `isWilted = true`; tier unchanged; show wilted art for current tier |
| ≥ 2 (within reconciliation) | **Demote** one tier (`evolutionTier -= 1`, floor 0); remain wilted; reset consecutive miss counter to 1 |

**Recovery:** Primary quiz complete → `isWilted = false`, update tier from streak, clear miss counters, set `lastPrimaryQuizDayKey = today`.

### 11.3 Wilt entrance animation (Today)

On wilt (app open after miss or debug **Wilted**):

- **Droop** ~1.04s: plant pitched upright → eases into wilted pose (pivot at pot).
- **Haptics:** soft + rigid at end; **no confetti**.
- Healthy recovery: tornado spin + confetti (unchanged).

### 11.4 Streak number vs demotion

- **Streak count:** §10 grace-day calculator (honest + one free gap).
- **Plant demotion:** Separate `evolutionTier`; does not fake the streak number.

---

## 12. Vocabulary import (`WordJSONImportService`)

Unchanged: insert missing; sync lexical metadata without overwriting SRS.

---

## 13. Library (`ExploreView`)

Client-side filter/search only.

---

## 14. Remediation & feature changelog

| Change | Resolution |
|--------|------------|
| Supplemental overwrote SRS / UI | Split `appliesSRS`; frozen primary remembered/missed |
| Same-day batch swapped after widget Know | **Calendar-day lock** — no same-day filter/backfill |
| Widget Review caused accidental lapses | **Review removed**; legacy events no-op |
| Supplemental blank-skip SRS | Misses: no SRS; fill words: SRS |
| Widget rotated after evening quiz | **Rest timeline** when primary done |
| Streak broke on 1 miss | **One grace day** in `QuizStreakCalculator` |
| Plant always young wilt in debug | Debug preserves day override when tapping Wilted |
| Wilted seedling white box | Transparent PNG aligned to healthy 1024 canvas |
| Insights mastered inflated | `status == "mastered"` only |
| Polysemy synonyms | Primary sense pinning |
| Catalog A–Z bias | `frequencyRank` + day-keyed shuffle |
| Widget reconcile time | `reviewedAt = event.date` |
| Lost widget Know taps (host + extension RMW) | File queue + `AppGroupFileLock` |
| Streak wrong after midnight quiz | `QuizSession.calendarDayKey` at start |
| `reloadTimelines` spam | `WidgetTimelineReloader` (~0.4s) |
| Stale widget after TZ change | Stale UI + refresh on active / `NSSystemTimeZoneDidChange` |
| Sentence spoiler irregulars | `canUseSentenceCompletion` guard |

---

## 15. Known limitations & review questions

1. **Quiz grading** — Daily quiz uses 1 / 3–5 by latency; widget Know stays 5.
2. **Per-question SRS** — Multiple items can hit the same word in one session.
3. **Primary quiz completion** — `quizCompletedToday` is in-memory; restored via `WidgetDailyState` + sessions on relaunch.
4. **Supplemental vs primary labels** — Card tags frozen to primary; supplemental only affects next supplemental plan.
5. **Streak grace** — One gap only; two misses break count and may demote plant.
6. **Sequencing lock** — Resume omits `sentenceDistractorHeadwords`.
7. **Batch lock** — Words marked due via widget may still appear in today’s ten until midnight (by design).
8. **Insights DEBUG** — Mock values may still default on in DEBUG builds.
9. **Clock tampering** — Future keys clamped; backward skew not blocked (§16.1).

---

## 16. Platform hardening (May 2026)

| Risk | Mitigation |
|------|------------|
| Extension vs host RMW on pending Know events | File-backed queue + `AppGroupFileLock` (`flock`) |
| `reloadTimelines` storms | `WidgetTimelineReloader` debounce on host |
| Quiz finished after midnight credits wrong day | `QuizSession.calendarDayKey` + `PersistedDailyQuiz.calendarDayKey` at start |
| Stale widget after TZ / midnight | Stale placeholder + host refresh on active / timezone notification |
| Batch JSON torn read | `loadPersistedBatch` / `persistBatch` under same lock |
| Multi-round latency leak | `activeQuestionID` + `questionDeckToken` timer resets (§7.3) |
| Manual clock forward (future day keys) | `clampedCalendarDayKey` / `isFutureCalendarDayKey` |
| `flock` fd leak on throw | `defer { flock(LOCK_UN); close(fd) }` in `AppGroupFileLock` |
| Main-thread `flock` on wake | Drain on `Task.detached`; SRS on `WidgetReconcileActor` |
| Torn pending-events JSON (widget jetsam) | `AppGroupAtomicJSONFile` tmp + `rename`; corrupt file deleted on read |
| Supplemental fill when nothing due | Catalog fallback in `selectSupplementalFillWords` |

### 16.1 Clock skew defense

**API:** `DailyWordBatchService.clampedCalendarDayKey(_:)` — if `key > today` (string compare on `yyyy-MM-dd`), return **today**.

| Surface | Behavior |
|---------|----------|
| `QuizSession.creditedQuizDayKey` | Clamps on read for streak |
| `QuizStreakCalculator` | Normalizes session key set before backward walk |
| `daily_word_batch.json` | Future-dated batch is **not** reused for today; not archived to history; fresh `selectNewBatch` |
| Quiz start / resume | `quizCalendarDayKey` clamped at write |

**Not defended:** deliberate clock **backward** to repeat yesterday’s batch (acceptable; streak still uses real today for walk). No NTP / `NSDate` “trusted time” API on iOS.

---

## 17. Implementation index

| Topic | File |
|-------|------|
| Daily 10-word batch | `DailyWordBatchService.swift` |
| Batch history | `DailyWordBatchService.swift` (`daily_batch_history.json`) |
| Supplemental plan | `SupplementalQuizPlanner.swift` |
| SRS | `SRSEngine.swift` |
| Streak day count | `QuizStreakCalculator.swift` |
| Streak plant persistence | `StreakPlantState.swift` |
| Widget primary-done flag | `WidgetDailyState.swift` |
| Quiz construction | `QuizGenerator.swift` |
| Quiz UI | `DailyQuizView.swift` |
| Today hub | `DailyHubView.swift` |
| Quiz resume | `DailyQuizPersistence.swift` |
| Sessions | `QuizSession.swift` |
| Word model | `Word.swift` |
| Insights math | `ProgressViewModel.swift` |
| App Group lock | `AppGroupFileLock.swift` |
| Widget pending events | `WidgetPendingEventsStore.swift` |
| Widget reload debounce | `WidgetTimelineReloader.swift` |
| Widget reconcile | `WidgetInteractionReconciler.swift`, `WidgetReconcileActor.swift` |
| App Group atomic JSON | `AppGroupAtomicJSONFile.swift` |
| Widget snapshot | `WidgetSnapshotWriter.swift` |
| Widget timeline + rest UI | `GlanceSATVocabularyWidget.swift`, `GlanceSATWidgetViews.swift` |
| Widget taps | `WidgetWordIntents.swift` |
| JSON import | `WordJSONImportService.swift` |
| App lifecycle | `GlanceSATApp.swift` |

---

*End of document.*
