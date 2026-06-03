# Streak bar UI — Today vs Insights

Both tabs render the streak chrome through **`SharedStreakBarView`** → **`StreakBarView`**, using the same **`TodayHubLayoutMetrics`** tokens and **`StreakBarAppearance.insightsSolid`** (oatmeal card, linen upcoming-day circles, no glass). Insights is the layout source of truth; Today reuses that shell and only swaps the plant visual and a few surrounding layout choices.

All numeric values below are **design baselines** at the reference height (780 pt, iPhone 17 Pro class). They scale proportionally via `TodayHubLayoutMetrics.scaled(_)` on every device.

---

## Shared structure (both tabs)

```
┌─────────────────────────────────────────┐
│  GLANCE  (GlanceScreenTitle)            │
│                                         │
│  ┌─ HubSolidCardChrome (r=24) ───────┐ │
│  │  N day streak - {plant message}    │ │  ← subtitle row
│  │  ○ ○ ○ ○ ○ ○ ○                     │ │  ← 7 day bubbles
│  │  🌱                                  │ │  ← plant (bottom-left)
│  └─────────────────────────────────────┘ │
└─────────────────────────────────────────┘
```

### Glance title (`SharedStreakBarView`)

| Token | Baseline | Notes |
|-------|----------|-------|
| Top padding | `glanceHeaderTopPadding` | Clamped from safe area: `max(safeTop − 16, 2)` capped at 5% of screen height |
| Title → streak bar | `scaled(16)` | Space below `GlanceScreenTitle` |
| Streak bar outer top | `scaled(4)` | Extra inset above the card |
| Horizontal inset | `horizontalContentInset` = **22** | Title and streak card share this inset |

Title typography: `.caption.weight(.bold)`, tracking 2, uppercase `"Glance"`.

### Streak bar card (`StreakBarView`)

| Token | Baseline | Notes |
|-------|----------|-------|
| Corner radius | **24** | `HubSolidCardChrome.streakBarCornerRadius` |
| Background | Oatmeal solid | `HubSolidCardChrome.background` — no blur/glass |
| Horizontal padding (inside card) | **14** | `streakBarHorizontalPadding` |
| Vertical padding (inside card) | **10** | `streakBarVerticalPadding` |

### Streak message (subtitle)

Text: `"{streakDays} day streak - {evolutionPlantStage.message}"`

| Condition | Font size | Alignment | Leading inset |
|-----------|-----------|-----------|---------------|
| Small plant (tier &lt; day 7) | **19** | Center | **12** pt from card leading edge |
| Large plant (tier ≥ day 7) | **18** | Leading | **plantImageSize + 10** — text clears the plant |

Additional subtitle chrome:

- Trailing padding: **12**
- `lineLimit(1)`, `minimumScaleFactor` 0.72 (small plant) or 0.76 (large plant)
- Color: `HubPalette.espressoMuted`, semibold

### Day circles (bubbles)

| Token | Baseline | Notes |
|-------|----------|-------|
| Visible slots | **7** | Last 3 may be empty/upcoming when streak ≥ 5 |
| Row top offset | **30** | `streakBubbleTopPadding` below subtitle baseline |
| Row leading inset | See subtitle table | Matches subtitle leading when large plant; else `streakPlantFrame + 16` |
| Bubble H spacing | **9** | Fixed in `StreakBarView` |
| Label → circle V spacing | **5** | Day number above circle |
| Circle diameter (normal) | **24** | Filled ember when completed |
| Circle diameter (milestone) | **26** | Ember stroke ring when upcoming milestone |
| Day label font | **11** / **10** / **9** | For 1-digit / 2-digit / 3-digit day numbers |
| Upcoming fill | **linen** | Completed = ember + white checkmark |
| Milestone upcoming | Ember stroke ring (+4 pt) | Highlight on next milestone day in window |

Milestones: 1, 3, 7, 14, 30, 100, 365, 1000.

### Plant frame (shared metrics)

| Token | Baseline | Notes |
|-------|----------|-------|
| Plant container | **86 × 86** | `streakPlantFrame` — ZStack frame for plant + glow |
| Glow circle | **78** dia | Ember @ 10% opacity, blur 4 |
| day0 image | **60** | + **5** pt downward offset when healthy |
| day1 image | **108** | |
| day3 image | **98** | |
| day7 / 14 / 30 / 60 | **86** each | |
| Pivot anchor | `(0.5, 0.88)` | Today animations only — pot base |

---

## Today tab — differences

**File:** `DailyHubView.swift` → `dailyHeader(metrics:)` → `SharedStreakBarView` with custom `streakPlantVisual`.

### Plant visual

| Aspect | Today | Insights |
|--------|-------|----------|
| Implementation | `streakPlantVisual(metrics:)` — live animated view | `StreakBarView.staticPlantVisual(...)` |
| Evolution transition | **1080° Y-axis spin** (`rotation3DEffect`, axis Y) + confetti + scale pulse | None |
| Wilt | Pitch/roll fall animation, thud haptics | Static wilt asset when `StreakPlantState.isWilted` |
| Celebration wiggle | ±5.5° roll oscillation during celebration | — |
| Scale during celebration | Up to **1.06×** at pot pivot | — |
| `plantTwirlSettleScale` | Shrinks to **0.86×** mid-flip (edge-on read) | — |

Asset and size tokens match Insights static plant; only motion differs.

### Title opacity

- **Today:** `titleOpacity: todayNavigationHeaderOpacity` — fades out over the first **~56 pt** of vertical scroll.
- **Insights:** Always **1** (no scroll fade on the title).

### Streak data source

- **Today:** `displayedStreakDays` — can be **frozen** after quiz completion until streak upgrade reveal; respects `debugStreakDayOverride`.
- **Insights:** `insightsStreakDays` — live from sessions + today completion flag; same debug override.

Plant stage:

- **Today:** `evolutionPlantStage` — may use `frozenEvolutionTier` during post-quiz presentation freeze.
- **Insights:** Always `StreakPlantState.evolutionTier` (or debug override).

Wilt:

- **Today:** `showWiltedPlant` — may use `frozenPlantShowsWilted` during freeze.
- **Insights:** `StreakPlantState.isWilted` (or debug wilt preview).

### Position in screen layout

| Aspect | Today |
|--------|-------|
| Scroll container | `ScrollView` — full Today hub scrolls |
| Top inset | `HubScreenHeaderLayout.scrollTopInset` = **2%** of screen height |
| Below streak header | Pre-quiz: `preQuizUniformSectionSpacing` (**20**) → “Today’s Words…” label |
| | Post-quiz: `postQuizGlassSpacing` (**16**) → “Quiz Completed!” block |
| Next section horizontal inset | `horizontalContentInset` (**22**) — matches streak header |

---

## Insights tab — differences

**File:** `ProgressView.swift` → `insightsStreakHeader(metrics:)` → `SharedStreakBarView(metrics:streakDays:evolutionPlantStage:wilted:)`.

### Plant visual

Static image only — no rotation, confetti, or wilt fall animation. Same glow, frame, image sizes, and day0 offset as Today’s idle state.

### Title opacity

Fixed at **1** — header does not fade when Insights content scrolls.

### Position in screen layout

| Aspect | Insights |
|--------|----------|
| Scroll container | Premium: `ScrollView`; Free tier: fixed `VStack` (no streak scroll fade context) |
| Top inset | Same `scrollTopInset` (**2%** screen height) |
| Below streak header | `InsightsLayout.sectionSpacing` = **28** → SAT countdown line |
| SAT countdown | Bold scaled text, **0.85** scale effect when date set; no bubble chrome |
| Content below SAT | Same `horizontalContentInset` (**22** scaled) as streak bar — single centered column |

---

## Side-by-side summary

| Property | Today | Insights |
|----------|-------|----------|
| Shared streak card layout | ✓ Same `StreakBarView` | ✓ Same |
| Card chrome | Oatmeal solid, r=24 | Same |
| Streak message rules | Same tier-based layout | Same |
| Day circles | Same 7-slot window, sizes, colors | Same |
| Plant container (86×86) | Same | Same |
| Plant image sizes by stage | Same tokens | Same |
| Plant motion | Animated (X-flip, wilt, confetti) | Static |
| Glance title fade on scroll | Yes | No |
| Streak count source | May freeze post-quiz | Always live |
| Space below header | 20 (pre-quiz) / 16 (post-quiz) | 28 to SAT countdown |
| Horizontal inset below header | 22 | 22 (unified via `insightsContentColumn`) |

---

## Code references

| Piece | Location |
|-------|----------|
| Shared wrapper | `StreakBarView.swift` — `SharedStreakBarView` |
| Bar layout + bubbles | `StreakBarView.swift` — `StreakBarView` |
| Metrics | `HubTheme.swift` — `TodayHubLayoutMetrics` |
| Today header | `DailyHubView.swift` — `dailyHeader`, `streakPlantVisual` |
| Insights header | `ProgressView.swift` — `insightsStreakHeader` |
| Top scroll inset | `HubTheme.swift` — `HubScreenHeaderLayout.scrollTopInset` |
