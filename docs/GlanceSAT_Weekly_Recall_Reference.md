# GlanceSAT — Weekly Recall Quiz Reference

| Field | Value |
|-------|--------|
| **Audience** | Engineering, product, pedagogy |
| **Source of truth** | `WeeklyRecallEligibility.swift`, `WeeklyRecallQuizPlanner.swift`, `QuizGenerator.swift` (`generateWeeklyRecallQuiz`), `WeeklyRecallQuizView.swift`, `DailyHubView.swift` |
| **Last updated** | June 2026 |
| **Related** | [GlanceSAT_SRS_and_Daily_Selection.md](./GlanceSAT_SRS_and_Daily_Selection.md), [GlanceSAT_Word_Selection_Reference.md](./GlanceSAT_Word_Selection_Reference.md), [GlanceSAT_Algorithms_Reference.md](./GlanceSAT_Algorithms_Reference.md) |

---

## Executive summary

**Weekly Recall** (user-facing copy: “Weekly Recap”) is an optional **20-question** quiz offered **after the primary daily quiz**, at most **once every seven days**. It targets vocabulary the learner has struggled with recently, mixes **sentence completion** and **synonym** formats, and updates SRS on every answer.

The quiz is **opt-in**: finishing the daily quiz shows a summary screen with a path into a short “Week N complete” transition, then the learner taps **Begin Weekly Recap** to start.

---

## 1. When the quiz triggers

### 1.1 Eligibility gate (`WeeklyRecallEligibility`)

| Rule | Implementation |
|------|----------------|
| **Cadence** | At most once per **7 calendar days** since the last *completed* weekly recall |
| **First time** | If `weeklyRecallLastCompletedAt` is unset, the quiz is **due immediately** |
| **Completion tracking** | `markCompleted()` runs when the learner finishes all 20 questions (not on exit) |
| **Week label** | `displayWeekNumber = completedCount + 1` — shown on the unlock transition (“Week 3 complete”) |

```swift
// WeeklyRecallEligibility.isDue()
elapsed >= 7 * 24 * 60 * 60  // seconds since last completion
```

Debug builds can call `WeeklyRecallEligibility.resetForTesting()` to clear cadence state.

### 1.2 Content gate (`WeeklyRecallQuizPlanner`)

A weekly quiz is only **buildable** when the word pool is large enough:

| Constant | Value | Role |
|----------|-------|------|
| `questionCount` | **20** | Target words / questions |
| `minimumWordPool` | **8** | Early exit if fewer than 8 candidates after selection + filler |
| **Effective minimum** | **20** | `QuizGenerator.generateWeeklyRecallQuiz` returns `[]` unless `words.count >= 20` |

If planning fails, `pendingWeeklyRecall` stays `nil` and the daily quiz dismisses normally with no weekly offer.

### 1.3 UI trigger flow

Weekly recall is **not** a separate tab or push notification. It appears inside the **daily quiz navigation cover** (`DailyHubView`).

```text
Primary daily quiz completes
        │
        ▼
prepareWeeklyRecallIfEligible()     ← runs in daily-quiz completion handler
scheduleWeeklyRecallPreload()       ← background question build
        │
        ▼
Daily quiz summary screen
        │
        │  User taps Continue / Return
        ▼
attemptWeeklyRecallOrDismiss()      ← DailyQuizView
        │
        ├─ weeklyRecallPresentation present & non-empty
        │       AND NOT supplemental round
        │       → onBeginWeeklyRecall()
        │
        └─ otherwise → dismiss daily quiz cover

onBeginWeeklyRecall()
        │
        ▼
quizCoverPhase = .weeklyUnlock      ← WeeklyRecallUnlockTransition interstitial
        │
        │  User taps "Begin Weekly Recap"
        ▼
quizCoverPhase = .weeklyRecall      ← WeeklyRecallQuizView
```

**Excluded cases**

- **Supplemental quiz rounds** never offer weekly recall (`isSupplementalPersistence` blocks `attemptWeeklyRecallOrDismiss`).
- **Not due** (`!WeeklyRecallEligibility.isDue()`) → no presentation prepared.
- **Paused session exists** → resume path takes priority over building a fresh quiz.

### 1.4 Background preload

While the daily quiz cover is visible, `QuizPreparationManager.scheduleWeeklyRecallPreload` may build the weekly quiz **off the main thread** (`QuizPreparationActor.prepareWeeklyRecall`). When preload finishes, `weeklyRecallPreloadRevision` bumps and `applyPreloadedWeeklyRecallIfEligible()` attaches questions to `pendingWeeklyRecall` so the summary → transition path is instant.

Preload is cancelled when the cover disappears or the learner is not eligible.

### 1.5 Resume after exit

If the learner leaves mid-quiz (back button or app background), `WeeklyRecallQuizPersistence` saves progress to UserDefaults (`weeklyRecallInProgress.v1`). The Today hub shows a **Resume Weekly Recap** CTA (`showPostQuizWeeklyRecallCTA`). Tapping it restores the saved deck and index.

---

## 2. How target words are selected

**File:** `WeeklyRecallQuizPlanner.swift`

### 2.1 Candidate pool

Fetch words with **any prior quiz exposure**:

```text
totalAttempts > 0  AND  lastReviewDate != nil
```

Then keep only words reviewed in the **past 7 days** (`lastReviewDate >= referenceDate - 7 days`). Up to **512** rows are fetched from SwiftData; filtering happens in memory.

### 2.2 Struggle ranking

Candidates are sorted by **descending struggle score** — higher score = more likely to appear in the weekly quiz.

```text
struggleScore =
    misses × 2.2
  + masteryGap × 1.6        // masteryGap = max(0, 5 - consecutiveCorrect)
  + easePenalty × 2.8       // easePenalty = max(0, 2.5 - easeFactor)
  + learningPenalty         // +1.5 if status == "learning", else 0
  + recentReset             // +2.0 if consecutiveCorrect == 0 AND totalAttempts > 0

where misses = max(0, totalAttempts - successfulRecalls)
```

The top **20** words by this score become the primary selection.

### 2.3 Filler words

If fewer than 20 struggle candidates exist, the planner pulls **due words** (`nextReviewDate <= now`), sorted by soonest due date, excluding already-selected IDs, shuffled, and takes enough to reach 20.

### 2.4 Weekly exposure set

Separately, the planner builds `weeklyExposureIDs`: all candidate words whose `lastReviewDate` falls within the past 7 days. This set is passed to the generator for **synonym distractor** selection (recently seen words make plausible wrong answers).

### 2.5 Question generation handoff

```text
WeeklyRecallQuizPlanner.plan()
    → WeeklyRecallQuizGenerator.generate()
        → QuizGenerator.generateWeeklyRecallQuiz()
```

The planner returns `nil` unless exactly **20** questions are produced.

---

## 3. Question format and word assignment

**Constants** (`QuizGenerator`):

| Type | Count |
|------|-------|
| Sentence completion | **6** |
| Synonym match | **14** |
| **Total** | **20** |

After all questions are built, the deck is **shuffled** (no sequencing lock — unlike the daily quiz).

### 3.1 Assigning words to sentence vs synonym slots

From the 20 selected target words:

1. **Sentence-eligible** words — those with a usable `quizCompletionSentence` (see §4.1) — are ranked by `sentenceScore` (descending).
2. The top **6** become sentence-completion targets.
3. Remaining selected words fill **synonym** slots (up to 14).
4. If fewer than 6 sentence-eligible words exist, additional eligible words from the pool are added to sentence slots before synonym assignment.

**Important:** sentence and synonym slots draw from **disjoint word sets** when possible (synonym words exclude sentence picks).

### 3.2 Sentence score (which words get context questions)

Higher `sentenceScore` → better candidate for sentence completion:

```text
sentenceScore =
    (successfulRecalls × 12)
  + (consecutiveCorrect × 8)
  + (interval × 2)
  + statusBonus

statusBonus:  mastered → 40,  review → 20,  else → 0
```

Paradoxically, words with **stronger recall history** are preferred for sentence items within the weekly quiz. The weekly quiz already selected words by *struggle* at the planner level; sentence scoring picks which of those 20 are best suited to inline-blank prompts.

---

## 4. How distractors are chosen

All weekly questions present **four shuffled options** (one correct + three distractors). Distractor logic lives in `QuizGenerator.swift`.

### 4.1 Sentence completion eligibility

A word can only receive a sentence-completion question when `canUseSentenceCompletion` passes:

- `quizCompletionSentence` is non-empty.
- The sentence can be blanked inline (target inflection found in context).
- The prompt does **not** fall back to appending a blank at the end only.
- The blanked prompt does not still expose the target headword or its inflected forms.

The correct option is the **inflected surface form** of the target word matching sentence context (base, past, progressive, or third-person), via `buildSentencePrompt` + `inflect`.

### 4.2 Sentence distractors (`pickRecencyWrongOptions`)

Wrong answers are **inflected headwords** from other catalog words, chosen in priority order:

| Priority | Pool | Sort / limit |
|----------|------|----------------|
| 1 | Same **distractor tier** (`noun_tier2`, etc.) | `lastReviewDate` descending, fetch limit 15 |
| 2 | Same **part of speech** | same recency sort |
| 3 | **Catalog-wide** recency slice | same recency sort |
| 4 | Reset `usedDistractorIDs` and retry catalog | allows reuse across questions if needed |
| 5 | Suffix disambiguation | `"Word (0)"`, `"Word (1)"` variants |

**Distractor tier** resolves from `word.distractorTier` when set; otherwise `WordDistractorTier.make(partOfSpeech:difficulty:)`.

**Uniqueness rules** (`isDistinctOption`):

- Normalized option text must differ from the correct answer, the target headword, and every already-chosen option.

**Cross-question dedup:** `usedDistractorIDs` tracks word IDs used as distractors across the weekly deck so the same foil headword is less likely to repeat; the set resets per sentence question but accumulates within the generator run.

`sentenceDistractorHeadwords` stores the source headwords for analytics/debug (sequencing lock is **not** applied in weekly recall).

### 4.3 Synonym distractors (`makeWeeklySynonymQuestion`)

**Correct answer** priority:

1. Random entry from `target.quizSynonyms` (non-empty).
2. Else `target.quizPrimaryDefinition`.
3. Else `target.definition`.

**Wrong answer pools** (absorbed in order until 3 distractors):

| Priority | Pool |
|----------|------|
| 1 | Same **`semanticCharge`**, same **part of speech** |
| 2 | Same **`semanticCharge`**, any POS |
| 3 | Words in **`weeklyExposureIDs`** (reviewed in past 7 days) |
| 4 | Same **distractor tier** |
| 5 | Same **part of speech** |
| 6 | Catalog recency pool |

Each candidate’s display text comes from `synonymLikeAnswer`: a random `quizSynonyms` entry, or the headword itself.

If still short of 3 distractors, synthetic fillers `"correct (0)"`, `"correct (1)"` are appended.

Synonym distractors also respect `usedDistractorIDs` across the full weekly generation pass.

### 4.4 Recency sort

All distractor fetches share:

```swift
SortDescriptor(\Word.lastReviewDate, order: .reverse)
```

Recently reviewed words are preferred as foils — they are familiar enough to be plausible mistakes.

---

## 5. Quiz experience and SRS impact

**File:** `WeeklyRecallQuizView.swift`

### 5.1 Answering

| Outcome | Behavior |
|---------|----------|
| **Correct** | Auto-advance after **1.2 s**; quality grade by response time (same as daily quiz): ≤2.5 s → 5, ≤5.0 s → 4, else → 3 |
| **Incorrect** | Shows **Next Question** / **Finish** button; no auto-advance |

All weekly questions have `appliesSRS: true`.

### 5.2 SRS updates

**Correct** → `SRSEngine.calculateNextReview(word:quality:)` (standard SM-2-style update). Newly mastered words trigger `AnalyticsManager.trackWordMastered(source: "weekly_recall")`.

**Incorrect** → `SRSEngine.applyWeeklyRecallIncorrect(word:)` — a **heavy penalty**:

```text
totalAttempts += 1
easeFactor = max(1.3, easeFactor - 0.55)
interval = 1
consecutiveCorrect = 0
status = "learning"
lastReviewDate = now
nextReviewDate = now        // immediately due again
```

### 5.3 Completion

On the final question:

1. `AnalyticsManager.trackWeeklyRecallCompleted(correctCount:totalQuestions:)`
2. `WeeklyRecallEligibility.markCompleted()` (skipped in debug preview mode)
3. Persistence cleared
4. **Weekly Summary** recap screen (`WeeklyRecallRecapView`)

### 5.4 Recap metrics (`WeeklyRecallResult` / `WeeklyRecallWeekStats`)

| Metric | Source |
|--------|--------|
| **Score** | correct / total for this session |
| **Weekly Accuracy** | Mean daily-quiz accuracy over `QuizSession` rows from past 7 days |
| **Words Glanced** | Distinct words with `lastReviewDate` in past 7 days and any attempts/recalls |
| **Strength by Category** | Per `PassageDomain` accuracy from recent word counters |
| **Hardest word mastered** | First newly mastered word this session, or the struggled-but-correct target with lowest pre-quiz `consecutiveCorrect` |

---

## 6. Persistence and data model

### 6.1 In-progress snapshot (`PersistedWeeklyRecall`)

Stored in UserDefaults as JSON:

- Full question payloads (`PersistedQuizQuestion`)
- Index, counts, remembered/missed word IDs
- Pre-quiz SRS snapshots (`preQuizConsecutiveCorrect`, `preQuizTotalAttempts`, `preQuizSuccessfulRecalls`) for recap comparison
- `isDebugPreview` flag

Hydration reuses `DailyQuizPersistence.rebuildQuestions` to reattach live `Word` rows from SwiftData.

### 6.2 Eligibility persistence

| Key | Purpose |
|-----|---------|
| `weeklyRecallLastCompletedAt` | `TimeInterval` since 1970 |
| `weeklyRecallCompletedCount` | Integer; drives week number label |

### 6.3 Background payload (`WeeklyRecallSessionData`)

Off-main-thread preload stores persisted questions + target word IDs + pre-quiz consecutive-correct map. Main thread hydrates into live `QuizQuestion` objects before presentation.

---

## 7. Analytics

| Event | When | Properties |
|-------|------|------------|
| `weekly_recall_started` | Quiz view appears (fresh session, not resume) | `question_count` |
| `weekly_recall_completed` | Last question answered | `correct_count`, `total_questions` |
| `word_mastered` | Word reaches mastered during weekly recall | `source: "weekly_recall"` |

---

## 8. Debug tooling

| Tool | Location | Behavior |
|------|----------|----------|
| `DebugWeeklyRecallControls.previewWeeklyRecallFlow()` | DEBUG | Posts notification to open mock flow |
| `WeeklyRecallQuizPlanner.planMockPreview` | DEBUG | Cycles any catalog words to 20; fallback builder if generator fails |
| `WeeklyRecallQuizPlanner.planForDebug` | DEBUG | Uses most recently reviewed words |
| `WeeklyRecallEligibility.resetForTesting()` | DEBUG | Clears cadence |
| `isDebugPreview` | Weekly quiz | Skips `markCompleted()` so cadence is not consumed |

---

## 9. Architecture map

```text
DailyHubView
├── WeeklyRecallEligibility          (7-day cadence)
├── WeeklyRecallQuizPlanner          (word selection + struggle score)
├── QuizPreparationManager/Actor     (background preload)
├── WeeklyRecallUnlockTransition     (opt-in interstitial)
└── WeeklyRecallQuizView
    ├── QuizGenerator.generateWeeklyRecallQuiz   (question + distractor build)
    ├── WeeklyRecallQuizPersistence    (pause/resume)
    ├── SRSEngine                      (grade updates)
    └── WeeklyRecallRecapView          (post-quiz summary)
```

---

## 10. Design intent (product)

| Principle | How it shows up |
|-----------|-----------------|
| **Spaced, not daily** | 7-day minimum between sessions |
| **Struggle-focused** | Planner ranks by misses, low ease, learning status |
| **Opt-in pacing** | Unlock transition after daily summary; learner chooses when to begin |
| **Mixed retrieval** | 6 context sentences + 14 synonym matches |
| **Consequences for misses** | `applyWeeklyRecallIncorrect` forces immediate re-review |
| **Continuity** | Mid-quiz exit persists; Today hub offers resume |

---

## 11. Key constants quick reference

| Constant | Value |
|----------|-------|
| Questions per session | 20 |
| Sentence / synonym split | 6 / 14 |
| Minimum days between sessions | 7 |
| Lookback window for candidates | 7 days |
| Planner `minimumWordPool` | 8 |
| Generator minimum words | 20 |
| Distractor pool fetch limit | 15 per query |
| Options per question | 4 |
| Auto-advance on correct | 1.2 seconds |
