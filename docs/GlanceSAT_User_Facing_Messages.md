# GlanceSAT — User-facing copy catalog

| Field | Value |
|-------|--------|
| **Scope** | Static and templated strings shown to users (in-app, widgets, notifications, system UI) |
| **Excludes** | Word definitions, quiz distractors, database content, legal page body HTML |
| **Last updated** | May 2026 |

Placeholders: `{n}`, `{word}`, `{days}`, etc. Dynamic values noted in *italics*.

---

## 1. App shell & navigation

| Location | Text |
|----------|------|
| Root tabs | **Today**, **Library**, **Insights** |
| Navigation title (Today, quiz, settings sheet) | **Glance** |
| Splash | **glance** (accessibility: “Glance”) |
| Launch / brand | **Glance** |

---

## 2. Today tab (`DailyHubView`)

### 2.1 Streak bar

| Context | Text |
|---------|------|
| Streak subtitle | `{n} day streak - {plant message}` |
| Plant messages (healthy) | **plant the habit**, **first sprout**, **taking root**, **full bloom** |
| Plant messages (wilted) | **come back tomorrow**, **needs a little water**, **drooping a bit**, **rest until tomorrow** |
| Streak bubble accessibility | `Streak day {day}, completed\|upcoming[, milestone day]` |
| Streak plant accessibility | `Streak plant, {empty pot\|seedling\|young plant\|mature plant\|wilted …}` |

### 2.2 Pre-quiz hero

| Context | Text |
|---------|------|
| Hero copy | **See what stayed with you today** |
| Primary CTA | **Start Daily Quiz** |
| Resume CTA | **Resume Daily Quiz** |
| CTA hint (start) | **Begins today's vocabulary check-in without revealing definitions first.** |
| CTA hint (resume) | **Continues your saved daily quiz session.** |
| Section label | **Today's Words · {newCount} new · {reviewCount} review** |
| Empty state title | **No reviews due** |
| Empty state body | **When words are ready for review, your Daily Hub will show up to ten here.** |

### 2.3 Post-quiz hero

| Context | Text |
|---------|------|
| Title | **Quiz Completed!** |
| Summary pills | `{count}` **remembered**, `{count}` **missed** |
| Hero copy (all remembered, no supplemental) | **Nice work - you remembered every word.** |
| Hero copy (default) | **Nice work on today's ten.** |
| Hero copy (supplemental available) | **Nice work on today's ten - ready for more recall?** |
| Secondary CTA | **Resume quiz**, **Take another quiz** |
| Supplemental footnote | **Original score stays - keeps recall honest** |

### 2.4 Word cards (post-quiz tags)

| Outcome | Pill label |
|---------|----------------|
| Correct on primary quiz | **Remembered** |
| Missed on primary quiz | **Missed** |
| In batch, neither set | **Missed** (label “Returning tomorrow” in code; pill shows **Missed**) |
| Pre-quiz locked | **Definitions unlock after first quiz attempt** |
| Section headers | **Definition**, **Example** |
| Origin/hook title | From word metadata (`Origin` / `Hook` via `cardOriginOrHookTitle`) |

### 2.5 Quiz alerts

| Title | Message |
|-------|---------|
| **Nothing due yet** | **There are no words available yet. Please try again in a moment.** |
| **Quiz unavailable** | **Could not build quiz questions from the current list.** |
| **Quiz error** | *`error.localizedDescription`* |
| **Nothing to quiz** | **No missed words or review words are available right now.** |
| Dismiss | **OK** |

---

## 3. Daily quiz (`DailyQuizView`)

| Context | Text |
|---------|------|
| Question type (synonym) | **Synonym Match** |
| Completion title | **Quiz Complete** |
| Score | `{correct}/{total}` |
| Subtitle | **Nice work - keep the streak alive tomorrow** |
| Button | **Return to Today's Words** |
| Placeholder (dev/preview) | **Placeholder vocabulary prompt**, **Placeholder answer option** |

---

## 4. Library (`ExploreView`)

| Context | Text |
|---------|------|
| Empty search | **No matching words** / **Adjust your filters or search query.** |
| Loading placeholders | **Placeholder headword**, **Placeholder definition line…** |
| Card sections | **Definition**, **Example** |
| Filters sheet | **Filters** |
| Filter chip remove | `Remove {title} filter` |
| Toolbar | **Filters**, **Settings** |

### Learning status filters

**Unseen**, **Learning**, **Mastered**

---

## 5. Insights (`GlanceSATProgressScreen`)

| Context | Text |
|---------|------|
| SAT countdown header (if date set) | **`{n} days to go`**, **`1 day to go`**, **`SAT day`**, **`SAT date passed`** |
| Overview section | **Overview** / **Your vocabulary at a glance** |
| Overview metrics | **Words glanced**, **Quiz accuracy**, **Longest streak**, **Words absorbed** |
| Categories | **Strengths by category** / *dynamic trailing subtitle* |
| Locked categories | **Your strengths will appear after 3 quizzes** |
| Trajectory | **Quiz trajectory** / **last 10 days** |
| Locked trajectory | **Your trajectory will appear after 3 quizzes** |
| Insights locked panel (below Overview row 1) | **See your strengths, weaknesses and latest trends** |
| Paywall CTA | **See all insights** |
| Ring center | `{count}` / `{cap}` |
| Streak cell | `{n}` **days** |
| Accuracy | `{percent}%` or **-** |

---

## 6. Settings (`SettingsView`)

| Section / row | Text |
|---------------|------|
| **Subscription & goals** | |
| | **Manage subscription** |
| | **SAT Date** — subtitle: **Tap to choose your test date** or formatted date |
| **Spread the word** | |
| Share subject | **Glance** |
| Share message | **I'm prepping for the SAT with Glance — sharp vocabulary, daily rhythm.** (or variant without App Store link) |
| | **Leave us a review** |
| Share row | **Share Glance** |
| **Social** | **Instagram** `@glance_sat`, **TikTok** `@glance_sat` |
| **Support & legal** | **Help**, **Privacy policy**, **Terms and conditions** |
| Footer | **Glance**, **Version {version}** |
| Missing App Store ID (debug) | **Add your App Store ID in GlanceSAT-Info.plist…** |
| SAT date sheet | Nav **Glance**; **Cancel** / **Save** |

---

## 7. Paywall & subscriptions

| Context | Text |
|---------|------|
| Headline | **Start seeing SAT words naturally throughout your day** |
| Insights gate | **Subscribe to see all Insights** |
| Savings badge | **Save {n}% vs monthly** |
| Legal | **Cancel anytime within 7 days** |
| Restore | **Restore Purchases** |
| Alert title | **Subscription** |
| Plan names | **Monthly**, **3 months**, **Annual**, **Full SAT Prep (annual)** |
| Price fallbacks | e.g. **$49.99 / yr** (RevenueCat when available) |

---

## 8. Onboarding (`OnboardingView`) — selected copy

| Step / element | Text |
|----------------|------|
| Brand | **Glance** |
| First SAT | **Is this your first SAT?** |
| R&W level | **Where are you currently at in Reading & Writing?** |
| Dream score | **What is your dream score?** |
| Reminder tip | **We recommend the evening so your words have time to settle in throughout the day** |
| Notification promise | **One daily notification when it's time for your daily quiz** |
| Paywall | Same as §7 |
| Diagnostic baseline status lines | See `DiagnosticBaseline.statusLine` / `striveLine` in code (4 baselines × 2 lines) |
| SAT test date chips | e.g. **Slow and steady**, **Early bird** (from `SATTestDate`) |

---

## 9. Widget Studio & previews

| Context | Text |
|---------|------|
| Add widget | **Ready to add** / **Open your home screen to place the widget wherever feels right.** |
| Size badge | **Large only** |
| Preview chrome | **SAT** |
| Live preview clock | **9:41** |

---

## 10. Home Screen widgets — Glance (vocabulary)

### Gallery

**Glance** — “SAT vocabulary on your Home Screen and Lock Screen.”

### States

| State | Copy |
|-------|------|
| Placeholder word | **Glance** |
| Placeholder definition | **Open the app to sync vocabulary for your widgets.** |
| Celebration (home) | **Quiz complete** / **Well done on completing today's recall! Time to see today's words in context.** |
| Celebration (compact) | **Well done!** / **Today's recall is complete.** |
| Lock celebration | **Quiz complete** |
| Post-quiz rest (home) | **Rest.** / **See you tomorrow.** |
| Lock rest | **Rest. See you tomorrow.** |
| Freemium lock | **Daily limit reached.** / **Tap to unlock more.** |
| Stale | **Updating today's words…** / **Open the app to refresh.** / **Open GlanceSAT** |
| Lock stale | **Updating…** |

### Actions (accessibility)

| Action | Label |
|--------|--------|
| Hook / origin toggle | **Hide {origin\|hook}** / **Show {origin\|hook}** |
| Example toggle | **Hide example sentence** / **Show example sentence** |

### Word display

- Headword: *database*
- Definition line: **`(n.)` / `(v.)` / `(adj.)` …** + definition (`widgetDefinitionWithPartOfSpeech`)

---

## 11. Home Screen widgets — Glance Quiz

### Gallery

**Glance Quiz** — “Sentence-completion quizzes on your Home Screen, then the word card.”

Uses same celebration, rest, stale, and limit copy as vocabulary widget where applicable. Quiz prompt and options come from **snapshot** (`sentenceQuizPrompt`, `synonymQuizOptions`).

---

## 12. Home Screen widgets — SAT Countdown

### Gallery

**SAT Countdown** — “Days until your SAT — set your test date in Glance settings.”

| State | Copy |
|-------|------|
| Active | `{days}` + **days to go** / **day to go** + **until the SAT** |
| Past | **Past** / **Update your SAT date in settings** |
| Inactive | **Set your SAT date** / **Open Glance settings to activate this countdown.** |

---

## 13. Local notifications

### Daily quiz reminder (`NotificationManager`)

| Field | Value |
|-------|--------|
| Title | **Daily Recall** |
| Body | **Your daily recall check-in is ready.** |
| Schedule | User’s preferred time (default **19:00**); **7 days** ahead; skipped if primary quiz already done that day |

### Early completion (`handleQuizCompletedEarly`)

| Field | Value |
|-------|--------|
| Title | **Nice work today** |
| Body | **Your recall check-in is already complete. Come back anytime for a few extra words.** |

### Widget install nudge (`WidgetReminderNotificationCoordinator`)

Scheduled **1 hour after onboarding completion** if widgets missing:

| Condition | Title | Body |
|-----------|-------|------|
| Lock only | **Add the Home Screen widget** | **Keep SAT words nearby throughout the day with the Glance Home Screen widget.** |
| Home only | **Add the Lock Screen widget** | **See SAT words naturally each time you check your phone.** |
| Neither | **Glance works best with widgets** | **Add Glance to your Lock and Home screens to see SAT words naturally throughout the day.** |

---

## 14. Widget intents (Shortcuts / system)

| Intent | Title |
|--------|-------|
| AnswerWidgetQuizIntent | **Answer Quiz** |
| ToggleWidgetExampleIntent | **Toggle Example** |
| ToggleWidgetDetailIntent | **Toggle Hook** |

---

## 15. Insights & dynamic SAT strings

| Source | Examples |
|--------|----------|
| `SATExamDateStore.countdownLabel()` | **42 days to go**, **1 day to go**, **SAT day**, **SAT date passed** |

---

## 16. Debug-only (not shipped to App Store users)

| Context | Text |
|---------|------|
| App debug overlay | **Debug controls** |
| Insights mock toggle | Controlled by `DebugInsightsControls` |

---

## 17. Maintenance notes

1. **Typography normalization:** Some strings use ASCII hyphen `-` where UI spec may prefer en dash — search before global copy edits.
2. **Word-derived text** (definitions, examples, hooks, quiz sentences) lives in `Database.json` — not listed here.
3. **Web/legal** pages load from URLs in `AppExternalLinks` — full text not in repo.
4. When adding UI copy, update this doc or add a `Localizable.strings` workflow.

---

## 18. Source file index

| Surface | Primary files |
|---------|----------------|
| Today | `DailyHubView.swift` |
| Quiz | `DailyQuizView.swift` |
| Library | `ExploreView.swift` |
| Insights | `ProgressView.swift` |
| Settings | `SettingsView.swift` |
| Paywall | `PaywallViews.swift`, `OnboardingView.swift` |
| Widgets | `GlanceSATWidgetViews.swift`, `GlanceSATCountdownWidget.swift`, `GlanceSATQuizWidgetViews.swift` |
| Notifications | `NotificationManager.swift`, `WidgetReminderNotificationCoordinator.swift` |
| Plant copy | `StreakPlantState.swift` (`StreakPlantStage`) |
