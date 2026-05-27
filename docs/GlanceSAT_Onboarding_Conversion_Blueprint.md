# Glance: SAT® Vocab Prep — Onboarding Conversion Blueprint

**Document type:** Strategic product spec (complete revamp)  
**Author lens:** SAT pedagogy · premium app positioning · conversion optimization · first-run psychology  
**Audience:** Founder, design, engineering, copy, growth  
**Status:** Recommendation only — not tied to current implementation  
**Date:** May 2026

---

## 0. Why this document exists

Glance wins when a student believes three things in the first three minutes:

1. **“This is not another study app.”** It does not demand new hours, new guilt, or new schedules.
2. **“The Lock Screen is the product.”** Passive glances are the engine; the daily quiz is the honest check-in.
3. **“I already built something.”** Premium is unlocking *my* plan—not buying a generic word list.

This blueprint designs onboarding as a **conversion instrument**, not a feature tour. Every screen earns the next swipe. Every swipe increases sunk cost without increasing anxiety.

---

## 1. Product truth (what onboarding must sell)

### 1.1 The loop (pedagogically honest)

| Phase | Surface | Cognitive load | Emotional tone |
|-------|---------|----------------|----------------|
| **Exposure** | Lock Screen widget | Near zero | Calm, ambient, “I already do this” |
| **Consolidation** | One short daily quiz | Low | Honest, finite, “done in minutes” |
| **Adaptation** | SRS + Insights | Invisible | Trust, “it adjusts without nagging” |

**Positioning line (internal):**  
*You already check your phone. Glance makes a few of those checks count.*

### 1.2 What Glance is NOT (say implicitly, never as attack ads)

- Not a flashcard marathon  
- Not a TikTok-style dopamine game  
- Not a “800 guaranteed” score machine  
- Not a replacement for reading practice or grammar drills  

### 1.3 Who we are talking to

**Primary:** High-school juniors and seniors taking (or retaking) the Digital SAT.  
**Secondary:** Sophomores building verbal runway early.  
**Influencer (non-user):** Parents who pay and fear their kid “won’t study.”

| Segment | Dominant fear | Dominant desire | Onboarding lever |
|---------|---------------|-----------------|------------------|
| **Crammer** | “I’m behind.” | Efficient lift before test day | Time-to-test personalization + Sprint tier |
| **Avoider** | “Study apps don’t stick.” | Something that fits real life | Lock Screen mechanism + no red/green shame |
| **Optimizer** | “I need 700+ RW.” | Precision, high-impact words | Baseline signal + “SAT-high-impact” language |
| **Parent payer** | “Money wasted.” | Visible habit, calm structure | Trial transparency + widget activation proof |

---

## 2. Conversion architecture

### 2.1 The funnel we are actually optimizing

```text
Install → Belief (Acts I–II) → Identity investment (Act III) →
Plan ownership (Act IV) → Trial start (Act V) → Widget live (Act VI) →
Day-1 quiz completion (D1) → Day-3 retention (D3)
```

**Primary conversion event:** Start 7-day free trial.  
**Activation event (equal priority):** Widget successfully added to Lock Screen.  
**Quality event:** Complete first daily quiz within 24 hours of onboarding.

> A trial without the widget is a refund. A widget without a trial is a support ticket. Onboarding must treat both as one motion psychologically, even if StoreKit completes before the widget sheet.

### 2.2 Psychological spine (in order)

1. **Relief** — Reduce SAT vocab anxiety before asking for anything.  
2. **Recognition** — “This fits the life I already live.”  
3. **Proof** — Show the mechanism, not the feature list.  
4. **Micro-commitment** — Small inputs that feel like self-discovery, not testing.  
5. **Endowment** — Name *their* plan aloud.  
6. **Loss framing (gentle)** — “Your plan is ready—unlock it.”  
7. **Ritual closure** — Widget install as the “graduation” moment.  
8. **Peak-end** — End on competence, not payment shame.

### 2.3 Friction budget

| Allowed friction | Forbidden friction |
|------------------|-------------------|
| 2–3 taps on calibration | Score band steppers / 400–800 spectrum |
| One wheel time picker | Account creation before value |
| One paywall decision | Red/green “wrong answer” shame |
| Widget install steps | Fake loading / “AI analyzing…” delays |
| Optional skip after Act II | Skip-to-paywall before investment |

**Target swipe count to trial CTA:** 5–6 content screens + paywall.  
**Target time-on-onboarding (median):** 2:30–4:00 minutes.

---

## 3. Macro flow — six acts, nine beats

Do **not** present this as “9 steps” to the user. Present as **three chapters** with subtle chapter labels only.

```text
CHAPTER 1 — THE REFRAME        (2 beats)
CHAPTER 2 — YOUR ADVANTAGE      (3 beats)
CHAPTER 3 — YOUR PLAN          (4 beats: plan → pay → activate → enter app)
```

### Beat map

| Beat | Act | Screen name | User feeling | CTA |
|------|-----|-------------|--------------|-----|
| 1 | I | **The Quiet Promise** | Relief | Continue |
| 2 | I | **The Real Habit** | Recognition | Continue |
| 3 | II | **The Glance Loop** | Understanding | Continue |
| 4 | II | **Lock Screen Proof** | Desire | Continue |
| 5 | II | **Your Timeline** | Agency | Continue |
| 6 | III | **Three-Tap Baseline** | Competence (no shame) | Save my starting point |
| 7 | III | **Your Evening Ritual** | Control | Set my check-in |
| 8 | III | **Plan Assembled** | Ownership | See my plan |
| 9 | III | **Unlock** | Commitment | Start free trial |
| 10 | III | **Activation** | Pride | My widget is live |

**Skip rule:** Skip appears only on beats 1–2, and lands on beat 9 (paywall)—never on activation.  
**Progress UI:** Chapter label + thin segment bar (3 segments). No `7/10` anxiety counter.

---

## 4. Screen-by-screen specification

### Beat 1 — The Quiet Promise

**Job:** Kill “another study app” reflex in 8 seconds.

**Layout (top → bottom):**
- Minimal top bar: wordmark `Glance` only (no skip).
- Hero: single large line, left-aligned (not centered marketing poster).
- One glass card (light) / elevated slate card (dark) with **one sentence** proof pill.
- Vast vertical whitespace.
- Fixed bottom: primary CTA only.

**Copy:**
- **Eyebrow:** `Tiny exposure. Real retention.`
- **Headline:** `SAT words stick when you stop cramming.`
- **Body:** `You don't need longer study sessions. You need more calm repetitions of the words that actually appear on the test.`
- **Pill:** `Passive first · One short quiz · Adapts quietly`
- **CTA:** `Continue`

**Psychology:**
- Lead with **relief**, not ambition.
- Avoid “boost your score” in screen 1 (triggers skepticism).

**UI notes:**
- Native SF Pro, semibold headline, restrained body.
- No illustration of books, graduation caps, or stress cartoons.

---

### Beat 2 — The Real Habit

**Job:** Transfer belief from “study” to “phone checks.”

**Layout:**
- Center hero: abstract **check rhythm** graphic (not stock teens studying).
  - Example: 3 small time marks (morning / afternoon / night) with one word chip appearing at Lock Screen position.
- Below: one stat line in muted type.

**Copy:**
- **Eyebrow:** `THE REAL HABIT`
- **Headline:** `You already look at your phone all day.`
- **Body:** `Glance uses a few of those glances for high-impact SAT words—so repetition happens without opening a study app.`
- **Stat pill:** `Students unlock their phones 100+ times a day.`
- **CTA:** `Show me how`

**Psychology:**
- **Recognition > novelty.** Parent and student both nod.
- First micro-commitment: CTA copy changes from “Continue” (signals “content ahead”).

**Skip:** Appears here (top-right, muted). Skip copy: `Skip` not `Not now` (confident brand).

---

### Beat 3 — The Glance Loop

**Job:** Teach the loop in 10 seconds without a lecture.

**Layout:**
- Horizontal **three-node loop** inside one glass card:
  1. `Glance` — Lock Screen  
  2. `Recall` — Daily quiz (2–4 min)  
  3. `Adapt` — Words return when due  
- No paragraph below the card—let the diagram breathe.

**Copy:**
- **Eyebrow:** `HOW IT WORKS`
- **Headline:** `Exposure first. Recall second.`
- **Body:** `Your brain remembers words it sees often. Glance makes “often” automatic.`
- **CTA:** `Continue`

**Pedagogy note (for tooltips / optional long-press):**
- This mirrors legitimate spaced exposure → retrieval practice sequencing.
- Do not claim “brain science proves” — use calm certainty.

---

### Beat 4 — Lock Screen Proof

**Job:** Make the widget feel inevitable, premium, and magical—not a settings chore.

**Layout:**
- **Center stage:** Phone chassis (black rounded rect), calm async animation:
  - Idle dark → wake → word `cogent` → subtle parallax → time jump → `mitigate`
  - No tap animations; no gamified bounce.
- Footer: single proof pill with SF Symbol `iphone.badge.play`.

**Copy:**
- **Eyebrow:** `THE BREAKTHROUGH`
- **Headline:** `Your Lock Screen becomes the study space.`
- **Body:** `One word. One definition. A few seconds. Repeated all day.`
- **Footer pill:** `This is where Glance actually works.`
- **CTA:** `Continue`

**Psychology:**
- **Visual proof > verbal proof.**
- This is the screenshot moment for App Store social ads—design it like one.

**UI rules:**
- Animation loop slow (total cycle ~4.5s).
- Widget card inside phone uses native materials; word typography matches in-app widget studio.

---

### Beat 5 — Your Timeline

**Job:** Personalize urgency without score anxiety.

**Layout:**
- Three **large selectable cards** (not a spectrum, not steppers):
  - `My test is within 30 days`
  - `Within 90 days`
  - `Later this year`
- Optional expandable: `I haven't picked a date yet` (maps to “explore” cohort).

**Copy:**
- **Eyebrow:** `YOUR TIMELINE`
- **Headline:** `When are you aiming for the SAT?`
- **Body:** `We'll shape your plan around your runway. No account. No pressure.`
- **Microcopy (footer):** `You can change this anytime in Settings.`
- **CTA:** `Continue` (enabled after selection; gentle haptic)

**Stored signal:**
- `targetTestDate`: `within30` | `within90` | `later` | `explore`

**Psychology:**
- **Agency without diagnosis.** Date feels planful; score bands feel judgmental.
- Drives paywall tier logic later (Sprint vs Annual) without mentioning price yet.

**Conversion hook:**
- Within 30/90 → show Sprint tier on paywall.
- Later/explore → Annual only (reduce choice paralysis).

---

### Beat 6 — Three-Tap Baseline

**Job:** Create investment + competence signal without test panic.

**Format:** **3 questions only** (not 4). One per card. Large headword.

**Interaction rules (non-negotiable):**
- On tap: selected card fills **charcoal** (dark) / espresso (light)—**never red/green**.
- Show `sparkles` SF Symbol on selection.
- Reveal **one** micro-insight line (curiosity, not grading):
  - Example: `Nice. "Mitigate" shows up constantly in SAT reading passages about policy and science.`
- Auto-advance after 0.4s pause (no “Next” per question).
- No correct/incorrect copy.

**Baseline tiers (internal only):**

| Correct (of 3) | Label shown | Tone |
|----------------|-------------|------|
| 0 | `Getting Started` | Neutral, hopeful |
| 1 | `Momentum Building` | Encouraging |
| 2 | `Solid Foundation` | Respect |
| 3 | `Already Ahead` | Identity lift |

**Layout:**
- Progress: `1 of 3` dots (not a test timer).
- Bottom CTA disabled until Q3 answered: `Save my starting point`

**Copy:**
- **Eyebrow:** `QUICK SIGNAL`
- **Headline:** `Let's find your starting point.`
- **Body:** `Three taps. No score. Just a smarter first week.`

**Question set (rotate A/B pools):**

| # | Word | Distractors | Insight theme |
|---|------|-------------|---------------|
| 1 | cogent | convincing / careless | Argument quality |
| 2 | mitigate | make less severe / make worse | Policy/science frequency |
| 3 | tenuous | weakly supported / widely accepted | Evidence language |

**Psychology:**
- **Self-discovery framing** beats diagnostic framing.
- Parents hear “starting point”; students don’t hear “you failed q2.”

---

### Beat 7 — Your Evening Ritual

**Job:** Permission for one notification; tie quiz to calm routine.

**Layout:**
- Top: large **time display** card showing selected time (updates live).
- Middle: native `DatePicker` wheel (hour/minute only).
- Preset chips row: `6:30 PM` `7:00 PM` `8:00 PM` (one-tap overrides wheel).

**Copy:**
- **Eyebrow:** `ONE RITUAL`
- **Headline:** `Pick a calm moment for your daily check-in.`
- **Body:** `Same time each day: a short quiz to see what stuck. The widget keeps working quietly all day.`
- **Footer:** `One reminder. No spam.`
- **CTA:** `Set my check-in`

**Behavior:**
- On CTA: request notification permission **once**; schedule repeating local notification.
- If denied: continue anyway (never block).

**Psychology:**
- Evening default respects school day; feels parent-safe.
- Positions quiz as **check-in**, not homework blast.

---

### Beat 8 — Plan Assembled (Zeigarnik peak)

**Job:** Instant recap—no fake loader. Make the plan feel built *for them*.

**Layout:**
- Headline + three **staggered material cards** (spring fade, 0.12s offsets):
  1. **Timeline** — icon `calendar`
  2. **Starting point** — icon `chart.line.uptrend.xyaxis`
  3. **Evening check-in** — icon `bell`
- Optional fourth muted row (text only, no card): `Method · Lock Screen exposure + adaptive review`

**Copy:**
- **Eyebrow:** `YOUR PLAN`
- **Headline:** `Here's the architecture of your prep.`
- **Body:** `Passive exposure on your Lock Screen. One honest quiz at night. Words return when you're ready.`
- **CTA:** `Unlock my plan`

**Psychology:**
- **Endowment effect:** They already “have” a system.
- **Zeigarnik:** Open loop closes at paywall, not before.

**Critical rule:**
- Transition **instant**. No spinner. No “analyzing.”

---

### Beat 9 — Unlock (Paywall)

**Job:** Convert trial with personalized ownership, not feature vomit.

**Layout (top → bottom):**
1. **Personalized headline** referencing timeline + baseline (dynamic).
2. **One hero plan card** pre-selected: `Full SAT Prep (Annual)`
3. **Conditional second card** only if `within30` or `within90`:
   - `SAT Sprint (3-Month)`
4. **Trial timeline** (3 beats): Today → Day 5 reminder → Day 7 billing
5. **Four compact proof rows** (not grid of 12 features):
   - Full high-impact word bank  
   - Lock Screen widget styles  
   - Adaptive daily quiz + review  
   - Quiet progress insights  
6. Primary CTA + legal microcopy

**Dynamic headline examples:**

| Cohort | Headline |
|--------|----------|
| within30 | `Your 30-day runway is mapped. Start your free week.` |
| within90 | `Your next 90 days, organized. Start your free week.` |
| later | `Your long-cycle plan is ready. Start your free week.` |

**Copy:**
- **Eyebrow:** `GLANCE PREMIUM`
- **Primary CTA:** `Start my 7-day free trial`
- **Secondary (optional A/B):** `See what's included` → expands sheet, not second paywall

**Pricing psychology:**
- Annual pre-selected (anchor).
- Sprint appears only when chronologically plausible (reduces “which should I pick?”).
- Show **monthly equivalent** under annual in small type (`~$4 / month`) — parent math.

**What NOT to show:**
- 3-day no-card preview beside 7-day trial (splits intent; increases support load unless fully gated in product).

**Post-CTA behavior:**
- Trial tap → **Activation beat immediately** (do not drop into Today tab yet).

---

### Beat 10 — Activation (Widget Install)

**Job:** This is the emotional finish line. User must leave feeling capable.

**Layout:**
- Simple **3-step vertical list** with connected line (numbered circles).
- Optional: looping **3-second** mini phone clip (add widget path) — silent, no voiceover.

**Copy:**
- **Eyebrow:** `ACTIVATION`
- **Headline:** `One last step: put Glance on your Lock Screen.`
- **Body:** `The widget is the engine. Without it, the plan can't compound.`
- **Steps:**
  1. `Touch and hold your Lock Screen`
  2. `Tap Customize → Add Widgets`
  3. `Choose Glance · place your word widget`
- **Primary CTA:** `My widget is live`
- **Secondary:** `I'll do this in a minute` (completes onboarding, schedules one gentle nudge in 2 hours—never shame)

**Psychology:**
- **Peak-end rule:** End on empowerment.
- **Implementation intention:** “My widget is live” is a commitment label, not passive “Done.”

**On complete:**
- Set `hasCompletedOnboarding = true`
- Land on **Today** with first word batch ready; optional soft coach mark pointing at streak/quiz CTA.

---

## 5. Visual & interaction system (onboarding-only)

### 5.1 Aesthetic north star

**Feels like:** Apple Health schedule setup × SAT prep seriousness × quiet luxury stationery.  
**Does not feel like:** Duolingo, TikTok edu-bro hype, or web SaaS gradients.

| Element | Light mode | Dark mode |
|---------|------------|-----------|
| Background | Linen + soft radial warmth | Charcoal + subtle elevation gradient |
| Cards | Frosted glass (`ultraThinMaterial` + linen wash) | Solid oatmeal panels (no blur “muddy eggs”) |
| Primary text | Espresso | Soft off-white (`softHighlight`, not harsh #FFF) |
| Accent / CTA | Plant pot / ember for **primary button** | Same; avoid neon green success |
| Progress | 3-segment chapter bar, ember fill | ember on charcoal track |

### 5.2 Motion

- Page transitions: `easeInOut` 0.22–0.26s horizontal slide.
- Plan cards: spring stagger `0.14s` delay increments.
- Lock Screen animation: slow, calm loop (spec separate).
- **Ban:** confetti, shake-on-wrong, pulsing CTAs, fake progress bars.

### 5.3 Typography

- Headlines: SF Pro **Semibold**, 28–30 pt (compact phones 26).
- Body: SF Pro **Regular**, 14–15 pt, line spacing +2.
- Eyebrows: 11 pt, tracked caps, ember—not shouty red.

### 5.4 Icons

- SF Symbols only, unmodified.
- Prefer: `calendar`, `bell`, `sparkles`, `iphone.badge.play`, `checkmark.circle` (activation success state on Today, not onboarding).

---

## 6. Copy principles (voice of an elite SAT educator)

1. **Calm certainty** — State what SAT rewards, not what we guarantee.  
2. **Specificity** — “reading passages,” “policy science,” “argument quality”—not “master vocabulary.”  
3. **Agency** — “Pick,” “shape,” “unlock”—not “submit,” “submit score,” “prove.”  
4. **Short clauses** — One idea per sentence on mobile.  
5. **Never shame** — Wrong answers don't exist in onboarding; only “signals.”  
6. **Parent-safe subtext** — Evening ritual, one reminder, ranges not scores.

**Banned words on first run:** crush, grind, dominate, hack, insane, guaranteed, AI-powered learning.

**Preferred words:** quiet, stick, exposure, check-in, high-impact, reading passages, plan, runway.

---

## 7. Monetization & tier logic

### 7.1 Plans shown

| Plan | When visible | Role |
|------|--------------|------|
| **Full SAT Prep (Annual)** | Always | Default selected; best LTV |
| **SAT Sprint (3-Month)** | `within30` or `within90` only | Urgency match |
| Monthly | Not on first onboarding | Avoid anchoring down before habit |

### 7.2 Trial structure (recommended)

- **7-day free trial** → annual or sprint (StoreKit intro offer).  
- Day 5 push: `Your trial ends in 2 days` (calm, not red alert).  
- Day 7: billing begins.

### 7.3 Conversion copy on paywall (trust)

- `Cancel anytime in Settings before Day 7.`  
- `We'll remind you before billing starts.`  
- Apple-required subscription terms linked, not buried.

---

## 8. Data captured (minimal, high-leverage)

| Key | Values | Used for |
|-----|--------|----------|
| `targetTestDate` | within30 / within90 / later / explore | Paywall tiers, copy, push cadence |
| `diagnosticBaseline` | 4 tier strings | Today difficulty seed, paywall headline |
| `diagnosticAnswers` | optional opaque blob | Analytics only |
| `reminderTime` | Date components | Evening notification |
| `hasCompletedOnboarding` | bool | Gate |
| `hasMarkedWidgetInstalled` | bool | Activation quality metric |
| `selectedOnboardingPlan` | annual / sprint | Analytics until StoreKit |

**Do not collect on first run:** email, parent email, exact SAT score, school name.

---

## 9. Metrics & experimentation

### 9.1 North-star metrics

| Metric | Definition | Target (benchmark aspirational) |
|--------|------------|----------------------------------|
| **Trial start rate** | trials / onboarding starts | 18–28% cold organic |
| **Widget attach rate** | widget live / trials | >85% |
| **D1 quiz rate** | quiz complete / onboarding completes | >40% |
| **D3 retention** | return open D3 | >25% |
| **Trial→paid** | paid / trials (Day 14) | category-dependent |

### 9.2 Funnel events (instrument every beat)

`onboarding_beat_viewed`, `onboarding_beat_completed`, `onboarding_skip_tapped`, `onboarding_timeline_selected`, `onboarding_baseline_saved`, `onboarding_reminder_set`, `onboarding_paywall_viewed`, `trial_started`, `widget_install_confirmed`, `widget_install_deferred`.

### 9.3 A/B tests (prioritized)

1. **3 vs 4** baseline questions (hypothesis: 3 ↑ completion, same conversion).  
2. **Paywall before vs after widget** (hypothesis: trial → widget wins LTV; widget → trial wins trial rate—measure paid LTV).  
3. **Headline on beat 1** (relief vs score outcome).  
4. **Sprint card visible vs hidden** for 90-day cohort.  
5. **CTA on activation:** `My widget is live` vs `Done`.

---

## 10. What to cut from typical SAT onboarding (explicit anti-patterns)

| Anti-pattern | Why it kills conversion for Glance |
|--------------|-----------------------------------|
| Score 400–800 sliders early | Triggers shame; feels like judgment app |
| “Create account to save progress” | Friction before value |
| Feature grid paywall (12 icons) | Reads generic; breaks ownership story |
| Red/green diagnostic | SAT anxiety spike; bad first emotion |
| Fake 3-second “building plan” loader | Destroys premium trust |
| Putting widget install *before* paywall | Commoditizes product; lowers trial intent |
| Aggressive skip-to-home | Attracts tourists; hurts paid conversion |
| Parental gate on screen 2 | Student bounce; use parent-safe copy instead |
| “Watch a 45s video” | Gen Z skip; passive proof animation wins |

---

## 11. Post-onboarding bridge (first 60 seconds in app)

Onboarding ends; **Today tab** must continue the story:

1. **Pre-filled carousel** with onboarding-prioritized words (`onboardingRank` in data).  
2. **Single coach line** under header: `Your first words are ready on your Lock Screen.`  
3. **Quiz CTA** copy: `Take tonight's check-in` (not `Start Daily Quiz` on day 0).  
4. If widget not confirmed: subtle banner on Today (not modal): `Add the widget to start passive practice.`

**Do not** show Insights or Library complexity before first quiz completion (optional lock or soft badge).

---

## 12. Parent & educator appendix (optional export PDF)

One-screen “For parents” link in paywall legal footer (not in main flow):

- What Glance does in plain English  
- Time commitment: **seconds × glances + 2–4 min quiz**  
- Why Lock Screen is intentional (attention already spent)  
- Trial and billing clarity  

Keeps student flow clean; helps payer conversion on shared devices.

---

## 13. Implementation sequencing (when you build)

| Phase | Scope | Outcome |
|-------|-------|---------|
| **P0** | Beats 1–4 + 6–8 + paywall + activation | Complete narrative |
| **P1** | StoreKit + trial timeline truth | Revenue |
| **P1** | Analytics events | Learning |
| **P2** | A/B infrastructure | Optimization |
| **P2** | Parent PDF / optional explore cohort | Segment fit |

---

## 14. One-page executive summary

Glance onboarding should feel like **designing a calm SAT verbal rhythm**, not signing up for homework. Ten beats across three chapters move the student from relief → mechanism proof → personal plan → trial → Lock Screen activation. Calibration is **signal, not test**. Paywall sells **their plan**. The widget is the **finish line**, not an appendix. Execute with Apple-native restraint, slow motion, and zero shame—and conversion follows because the product story finally matches the product.

---

*End of blueprint. This document is intentionally independent of the current `OnboardingView.swift` implementation.*
