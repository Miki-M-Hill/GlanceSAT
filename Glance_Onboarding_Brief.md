# Glance Onboarding Brief

This document describes the current Glance onboarding experience: product narrative, screen flow, copy, CTAs, UI structure, personalization inputs, reminder setup, recap, paywall framing, and key feedback questions.

## Product Thesis
Glance is an SAT vocabulary app built around a passive learning loop:

**Passive exposure first. Active recall later.**

The core idea is that students already check their phone repeatedly throughout the day. Glance turns those unavoidable Lock Screen moments into repeated exposure to high-impact SAT vocabulary, then uses one short daily quiz to test what actually stayed.

The onboarding is designed to make the user understand and believe three things before the paywall:

- Glance is not another demanding study app.
- The Lock Screen widget is the breakthrough.
- The subscription unlocks a personalized quiet-learning plan, not just a list of features.

## Current Flow
The onboarding has nine screens:

1. Welcome
2. Lock Screen widget
3. Method
4. Prior SAT context
5. Target Reading/Writing score
6. Quick level check
7. Daily check-in reminder
8. Personalized plan recap
9. Premium paywall

The flow is divided into four phases shown in the bottom progress area:

- **Discover:** welcome, widget, method
- **Personalize:** prior score, target score, level check
- **Activate:** daily check-in, plan recap
- **Unlock:** premium paywall

There is no vertical scrolling in onboarding. Each screen is designed to fit fully on screen using compact spacing, line limits, adaptive sizing, and a fixed bottom CTA/progress area.

## Global UI System
The onboarding uses the app’s warm premium palette:

- Linen background
- Oatmeal cards
- Espresso primary text and CTAs
- Ember accent highlights
- Thin/ultra-thin material surfaces
- Rounded continuous corners
- Soft shadows
- Subtle glassmorphism and depth

Typography uses Apple system fonts throughout, with semibold titles and restrained body copy. The design goal is premium, calm, and native rather than loud or gamified.

### Layout Pattern
Each page generally contains:

- Top brand bar: `Glance`
- Main visual/hero card
- Eyebrow label
- Title
- Short body copy
- Optional proof card or input control
- Bottom progress bar and CTA

The diagnostic page is an exception: it does not show the main hero card so the question content can fit comfortably without scrolling.

### Progress Indicator
The old page dots were replaced with:

- Phase label, such as `Discover` or `Personalize`
- Numeric progress, such as `3/9`
- Slim horizontal progress bar

This makes the onboarding feel less long and more like a guided setup.

## Screen-by-Screen Detail

### 1. Welcome
**Purpose:** Create warmth, politeness, and immediate clarity before the product pitch.

**Eyebrow:** `Welcome to Glance`

**Title:** `Vocabulary prep that fits into the day you already have.`

**Body:** `Glance helps you absorb high-impact SAT words through quiet Lock Screen exposure, then checks what stayed with one short daily quiz.`

**Prominent thesis capsule:** `Passive exposure first. Active recall later.`

**Hero:** Glass card with sparkle icon and line: `A calmer way to build SAT vocabulary.`

**CTA:** `Begin`

**Psychological job:** Make the user feel welcomed and reduce resistance. This screen positions Glance as calm and compatible with normal life.

### 2. Lock Screen Widget
**Purpose:** Put the core differentiator front and center.

**Eyebrow:** `The Lock Screen advantage`

**Title:** `Turn the phone checks you already do into SAT vocabulary exposure.`

**Body:** `The breakthrough is where learning happens: your Lock Screen. Glance puts one high-impact word where your eyes already go.`

**Hero:** iPhone Lock Screen mockup with a Glance widget showing:

- Word: `cogent`
- Definition: `clear, logical, and convincing`
- Example: `Her cogent argument changed the room.`

**Proof card:** `150+ Lock Screen moments a day` with support copy: `Glance turns unused checks into vocabulary exposure.`

**CTA:** `Show Me How It Works`

**Psychological job:** Make the user understand that the widget is not a side feature. It is the core learning mechanism.

### 3. Method
**Purpose:** Explain why the system should work without over-teaching.

**Eyebrow:** `The method`

**Title:** `High-impact words. Repeated exposure. Adaptive review.`

**Body:** `Glance pairs a curated SAT word bank with spaced repetition: missed words return sooner, remembered words move forward.`

**Proof card:** Three-step timeline:

- `Glance`
- `Recall`
- `Adapt`

**Bullets:**

- `Curated SAT vocabulary.`
- `Examples that make meaning stick.`
- `Review timing handled for you.`

**CTA:** `Build My Recall Plan`

**Psychological job:** Convert curiosity into belief. The user should feel there is a real system behind the simplicity.

### 4. Prior SAT Context
**Purpose:** Capture useful starting-point data while making the experience feel personalized.

**Eyebrow:** `Your starting point`

**Title:** `Have you taken the SAT before?`

**Body:** `If you have a previous Reading and Writing range, Glance can better frame your vocabulary path and later show meaningful progress.`

**Options:**

- `Not yet` / `First SAT`
- `Yes` / `I have a score`

If the user chooses `Yes`, Reading/Writing score ranges appear:

- `Under 550`
- `550-620`
- `630-690`
- `700-740`
- `750+`

**Microcopy:** `Ranges are enough. This is context, not a prediction.`

**CTA:** `Save Starting Point`

**Data stored:**

- `hasTakenSATBefore`
- `previousReadingWritingScoreRange`

**Psychological job:** Establish a starting line and collect future marketing/progress context without making the user feel interrogated.

### 5. Target Score
**Purpose:** Create ownership and goal commitment.

**Eyebrow:** `Personalize your target`

**Title:** `What are you aiming for on SAT Reading and Writing?`

**Body:** `Your goal shapes the tone of the experience. A higher target means we should be stricter about precision, harder distractors, and the words most likely to separate strong scores from elite scores.`

**Options:**

- `600+` — `Build a stronger vocabulary floor`
- `650+` — `Reduce avoidable word misses`
- `700+` — `Push into strong verbal range`
- `750+` — `Train for precision under pressure`
- `800` — `Keep elite vocabulary automatic`

**Microcopy:** `We use this as guidance, not as a promise or score prediction.`

**CTA:** `Set my target`

**Data stored:** `verbalScoreGoal`

**Psychological job:** Make the user feel the app is adapting to their ambition, while avoiding any risky SAT score guarantee.

### 6. Quick Level Check
**Purpose:** Create a fast baseline and make the plan feel earned.

**Eyebrow:** `Quick level check`

**Title:** `Answer four vocabulary questions so Glance can calibrate your starting point.`

**Body:** `This is not a full SAT diagnostic. It is a fast signal: easy to hard, designed to make the first rotation feel more intelligent.`

**Diagnostic questions:**

1. Warm-up  
   Prompt: `A cogent argument is...`  
   Options: `careless`, `convincing`, `hostile`, `brief`  
   Correct: `convincing`

2. Medium  
   Prompt: `To mitigate a problem means to...`  
   Options: `make it worse`, `make it less severe`, `ignore it`, `describe it`  
   Correct: `make it less severe`

3. Advanced  
   Prompt: `A tenuous claim is best described as...`  
   Options: `weakly supported`, `morally urgent`, `widely accepted`, `intentionally funny`  
   Correct: `weakly supported`

4. Elite  
   Prompt: `If a writer equivocates, they...`  
   Options: `speak with precision`, `avoid commitment through ambiguity`, `prove a point conclusively`, `repeat a claim for emphasis`  
   Correct: `avoid commitment through ambiguity`

**Internal quiz control:** The page shows one question at a time with a `Next question` button. On the final question, the internal button reads `Baseline saved`.

**Global CTA behavior:** The main bottom CTA is disabled until all four diagnostic answers are complete. While blocked, it reads `Finish Level Check`.

**Microcopy:** `Four questions. No pressure. The system adapts as you quiz daily.`

**Data stored:**

- `onboardingDiagnosticAnswers`
- `onboardingDiagnosticCorrectCount`

**Baseline labels:**

- `Building` for 0-1 correct
- `Developing` for 2 correct
- `Strong` for 3 correct
- `Advanced` for 4 correct

**Psychological job:** Increase perceived personalization and commitment. The user has now invested effort, which makes the final plan feel more valuable.

### 7. Daily Check-In Reminder
**Purpose:** Convert the product from an idea into a daily routine.

**Eyebrow:** `One notification`

**Title:** `Pick the time for your daily check-in.`

**Body:** `Daily habits are strongest when the cue stays consistent. Choose one evening reminder, take the quiz, review misses, then close the app.`

**Reminder UI:**

- Large selected time display
- Minus button to move back 15 minutes
- Plus button to move forward 15 minutes
- Preset buttons for `6 PM`, `7 PM`, `8 PM`, `9 PM`

**Bullets:**

- `Same time each evening.`
- `Definitions stay hidden until the first attempt.`
- `Insights show what the day’s exposure helped recover.`

**Microcopy:** `One reminder. No spam. The widget keeps working quietly.`

**CTA:** `Set My Daily Check-In`

**Default:** `7:00 PM`

**Data stored:**

- `dailyQuizReminderHour`
- `dailyQuizReminderMinute`

**Notification behavior:** On onboarding completion, the app requests notification permission and schedules one repeating daily reminder:

Title: `Evening check-in`  
Body: `Take your daily Glance quiz and see what stayed with you.`

**Psychological job:** Create a commitment cue. The “one reminder, no spam” line reduces notification anxiety.

### 8. Personalized Plan Recap
**Purpose:** Make the paywall feel like unlocking a custom plan rather than buying generic features.

**Eyebrow:** `Your plan is ready`

**Title:** `Glance is set up around your goal.`

**Body:** `Your starting point, target, level check, and evening rhythm are now shaped into one quiet vocabulary routine.`

**Hero:** Premium-style glass card:

- `Your quiet-learning plan is ready.`
- `Built from your goal, baseline, and daily rhythm.`

**Plan recap rows:**

- `Starting point`: `First SAT`, `Previous SAT`, or selected Reading/Writing range
- `Reading/Writing goal`: selected target, such as `700+`
- `Level check`: `Building`, `Developing`, `Strong`, or `Advanced`
- `Daily check-in`: selected reminder time
- `Method`: `Lock Screen exposure + adaptive review`

**CTA:** `Unlock My Plan`

**Psychological job:** Create closure, ownership, and loss aversion. The user should feel they have built something that is now ready to activate.

### 9. Premium Paywall
**Purpose:** Convert by presenting premium as the activation of the plan.

**Eyebrow:** `Glance Premium`

**Title:** `Unlock your Glance plan.`

**Body:** `Start with a 7-day free trial. Annual is best for SAT prep because vocabulary compounds over weeks, not one weekend.`

**Hero:** Premium card:

- `Premium vocabulary, quietly compounded.`
- `7-day trial · $4.99 monthly · $29.99 annually`

**Compact plan summary:**

- Goal
- Level
- Check-in

**Pricing options:**

- Annual: `$29.99 / year`
  - Detail: `Best value for SAT prep`
  - Badge: `Save 50%`
- Monthly: `$4.99 / month`
  - Detail: `Flexible monthly access`

Annual is selected by default.

**Premium feature grid:**

- `Daily quiz`
- `Full word bank`
- `Widget Studio`
- `Quiet insights`

**CTA:** `Start 7-Day Free Trial`

**Secondary action:** `Not now`

**Trust microcopy:** `No charge today. Cancel anytime before the trial ends.`

**Current implementation note:** The paywall is visual and trial-ready, but the CTA currently completes onboarding and enters the app. Real subscription purchase still needs StoreKit wiring.

**Psychological job:** Reframe payment from “buy an app” to “activate the plan I just built.”

## Data Captured During Onboarding
The onboarding stores these values locally:

- `hasCompletedOnboarding`
- `dailyQuizReminderHour`
- `dailyQuizReminderMinute`
- `hasTakenSATBefore`
- `previousReadingWritingScoreRange`
- `verbalScoreGoal`
- `onboardingDiagnosticAnswers`
- `onboardingDiagnosticCorrectCount`

These values support:

- Personalization
- Reminder scheduling
- Plan recap
- Future progress tracking
- Future before/after SAT score marketing data

## Conversion Strategy
The current onboarding uses several conversion principles:

- **Clarity:** The first screens explain the core product quickly.
- **Novelty:** The Lock Screen widget is presented as the breakthrough.
- **Low friction:** The app is positioned as quiet and passive, not demanding.
- **Commitment:** Users choose a goal, starting point, and check-in time.
- **Personal investment:** The level check makes the plan feel earned.
- **Plan completion:** The recap creates a sense of ownership before payment.
- **Loss aversion:** The paywall asks users to unlock the plan they just created.
- **Trust:** Copy avoids score guarantees and calls the diagnostic a signal, not a prediction.

## UI Principles
The UI should feel:

- Premium
- Calm
- Native to iOS
- Warm, not academic
- Purposeful, not cluttered
- Visually consistent while varying layout enough to avoid feeling templated

Important constraints:

- No vertical scrolling in onboarding.
- All elements must be visible on screen.
- Text should avoid truncation.
- CTA area remains fixed and clear.
- Paywall must not feel overloaded.

## Open Questions for Feedback
Use these questions when sharing the onboarding for feedback:

1. Does the core idea make sense within the first two screens?
2. Does the Lock Screen widget feel like the main breakthrough?
3. Does the flow feel too long, too short, or just right?
4. Do the personalization questions feel helpful or intrusive?
5. Does the diagnostic feel valuable or like friction?
6. Does the daily reminder setup feel reassuring?
7. Does the recap make the paywall feel more personalized?
8. Does the paywall clearly explain what premium unlocks?
9. Does the copy feel premium and trustworthy?
10. Is anything confusing, repetitive, or too salesy?

## Current Recommendation
The current onboarding is in a strong direction. The most important thing to validate now is whether users feel the flow is motivating or slightly long. The recap/paywall pairing is likely the highest-leverage conversion element, while the diagnostic is the highest-risk friction point. If feedback shows fatigue, the diagnostic should become optional or shorter before removing any core product education.
