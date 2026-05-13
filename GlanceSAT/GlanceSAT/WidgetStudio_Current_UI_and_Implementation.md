# GlanceSAT Widget Studio
## Current UI and Implementation Reference

Date: 2026-05-06  
Owner: GlanceSAT iOS codebase  
Audience: Product, Design, QA, and external reviewers

---

## 1) Purpose and Scope

`WidgetStudioView` is the in-app configuration surface for composing SAT vocabulary home/lock widget previews before export. It currently supports:

- interactive style switching
- theme switching
- widget size switching
- typography scale switching (custom slider)
- placement toggles (home + lock, multi-select)
- preview word cycling
- add/save action dock and confirmation sheet

It is currently mounted as the 4th tab (rightmost) in the app tab bar.

---

## 2) Source Files (Current)

### Primary screen
- `WidgetStudioView.swift`

### State model
- `WidgetStudioViewModel.swift`

### Preview shell
- `LiveWidgetPreview.swift`

### Widget style renderers
- `WidgetStyleViews.swift`
  - `WidgetStyleMinimal`
  - `WidgetStyleDefinition`
  - `WidgetStyleEtymology`
  - `WidgetStyleRich`

### Supporting components
- `WidgetStudioComponents.swift`
  - `SectionEyebrow`
  - `StylePickerCard`
  - `ThemeSwatch`
  - `SizePill`
  - `PlacementRow`
  - `WordChip`
  - `CustomSlider`
  - `DockButton`

### Theme and palette
- `WidgetTheme.swift`
  - `WidgetTheme` model
  - `Color(hex:)` initializer
  - palette tokens (`wsLinen`, `wsCharcoalPrimary`, etc.)

### Integration
- `GlanceSATApp.swift` (tab insertion)

---

## 3) Entry Point and App Integration

In `GlanceSATApp.swift`, the app root uses `TabView(selection:)` with four tabs:

1. Today
2. Library
3. Insights
4. Widget Studio

`WidgetStudioView()` is tagged as `.widgetStudio` and appears as the rightmost tab item.

---

## 4) State Model

`WidgetStudioViewModel` is implemented with `@Observable` and stores all screen-driving state:

- `selectedStyle: WidgetStyle`
- `selectedTheme: WidgetTheme`
- `selectedSize: WidgetSize`
- `typographyScale: TypographyScale`
- `selectedPlacements: Set<WidgetPlacement>`
- `previewWord: SATWord` (`SATWord` typealias resolves to `Word`)
- `showingConfirmation: Bool`

Enums:
- `WidgetStyle`: `minimal`, `definition`, `etymology`, `rich`
- `WidgetSize`: `small`, `medium`, `large`
- `TypographyScale`: `small`, `default`, `large`
- `WidgetPlacement`: `homeScreen`, `lockScreen`

Behavior methods are centralized in the view model and already animate selection updates.

---

## 5) Visual Structure (Current)

`WidgetStudioView` uses:

- `ScrollView(.vertical, showsIndicators: false)`
- `VStack(spacing: 0)` with section stacking
- `.navigationBarHidden(true)`
- `.background(Color.wsLinen.ignoresSafeArea())`
- `.safeAreaInset(edge: .bottom)` for fixed action dock

### Header
- two-line title: “Widget” / “Studio” (Georgia 28)
- subtitle: “Customize how your words appear”

### Hero preview
- `LiveWidgetPreview` renders a framed phone mock
- dynamic widget composited at runtime by selected style/theme/size/word/scale

### Control sections
- Style (horizontal cards)
- Theme (row of swatches)
- Size (pill row)
- Text Size (custom slider)
- Placement (two row toggles)
- Preview Word (horizontal chips)

### Bottom dock
- `Save` secondary button
- `Add to Home Screen` primary button
- confirmation sheet (`.presentationDetents([.height(360)])`)

---

## 6) Widget Preview Rendering

`LiveWidgetPreview` composes:

- outer device body (220x420, rounded, stroked)
- decorative side buttons
- inner “screen” area with static wallpaper tone
- dynamic island element
- status area (time + custom-drawn wifi/battery glyphs)
- app-icon placeholder grid
- central live widget frame

Widget frame sizes are state-driven:

- Small: 90 x 90
- Medium: 190 x 90
- Large: 190 x 190

The actual style content is selected via switch:

- `WidgetStyleMinimal`
- `WidgetStyleDefinition`
- `WidgetStyleEtymology`
- `WidgetStyleRich`

---

## 7) Interaction and Animation (Current)

Implemented interaction patterns:

- press feedback on most tappables via `@GestureState` + `DragGesture(minimumDistance: 0)` + `scaleEffect`
- spring animation for style/size/placement/word updates
- ease-in-out animation for theme changes
- `Rich` style forces `Large` size in view model
- slider snaps to 3 stops (small/default/large)
- save pulse effect on Save action
- medium haptic on Add action
- sheet dismissal + timeline reload trigger (`WidgetCenter.shared.reloadAllTimelines()`)

---

## 8) Preview Data and Word Model Strategy

Widget Studio uses existing app `Word` model as SAT preview content through static factory helpers in `WidgetStudioViewModel.swift`:

- `Word.ephemeral`
- `Word.acumen`
- `Word.ardor`
- `Word.lucid`
- `Word.austere`
- `Word.candor`
- `Word.pernicious`
- `Word.alacrity`

This avoids introducing a parallel demo-only word type while keeping state and preview APIs compatible with app vocabulary structures.

---

## 9) Design Token Compliance Summary

The screen currently uses the custom widget-studio palette tokens declared in `WidgetTheme.swift` and generally adheres to a flat, editorial aesthetic.

### Notable implementation deviations from strict art direction

1. **Tab icon**
   - Widget Studio tab currently uses SF Symbol (`square.grid.2x2`) because tab bar item iconography is app-wide and separate from screen body rules.

2. **Internal glyphs in status simulation**
   - wifi/battery are custom-drawn shapes, not SF Symbols (compliant with no-SF requirement inside screen body).

3. **Font family provisioning**
   - screen currently uses Georgia + SF Rounded-like system `.rounded`; no custom font registration pipeline is added in this implementation phase.

4. **Some exact pixel/offset values**
   - broad layout targets are implemented, but this build should be treated as production-grade beta, not final pixel-perfect lock against every numerical spec line.

---

## 10) QA Checklist (Recommended)

1. **State coupling**
   - select Rich style -> verify size auto-switches to Large
   - attempt Small/Medium while Rich selected -> verify disabled behavior

2. **Live preview updates**
   - style/theme/size/word/typography all re-render the widget immediately

3. **Dock behavior**
   - Save pulse animation
   - Add button haptic + confirmation sheet display
   - sheet buttons dismiss properly

4. **Placement toggles**
   - both Home and Lock can be selected simultaneously

5. **Press feedback**
   - verify all major interactive elements respect 0.97 press scale and recover

---

## 11) Technical Notes for Feedback Review

- Architecture is modular and ready for iterative polishing.
- Component boundaries are clean enough for design-system extraction.
- Next-pass refinements can focus on strict visual parity (exact spacing/type scale constants), accessibility audits, and eventual export/installation flow wiring.

---

## 12) Suggested Next Iteration

1. Add explicit design constants file for all dimensions/spacing.
2. Move all font definitions into one token layer and, if desired, add custom font bundle registration.
3. Add snapshot testing for each style/theme/size combination.
4. Add accessibility labels and VoiceOver grouping for preview controls.
5. Replace remaining broad approximations with exact pixel-locked values from final design QA sheet.

