# Glance — Legal & App Store Submission Checklist

Use this checklist when publishing **Glance: SAT® Vocab Prep** to the App Store. The policy text lives in:

- [GlanceSAT_Privacy_Policy.md](GlanceSAT_Privacy_Policy.md) → host at `https://www.glanceprep.com/privacy`
- [GlanceSAT_Terms_of_Use.md](GlanceSAT_Terms_of_Use.md) → host at `https://www.glanceprep.com/terms`

---

## Before you submit

### Host the legal pages

- [ ] Publish Privacy Policy at **https://www.glanceprep.com/privacy** (full text from `GlanceSAT_Privacy_Policy.md`)
- [ ] Publish Terms at **https://www.glanceprep.com/terms** (full text from `GlanceSAT_Terms_of_Use.md`)
- [ ] Verify in-app Safari links in Settings open both URLs (`AppExternalLinks.swift`)

### App Store Connect — App Information

- [ ] **Privacy Policy URL:** `https://www.glanceprep.com/privacy` (required)
- [ ] **Support URL:** `https://www.glanceprep.com/support` (or support email page)
- [ ] **Marketing URL:** `https://www.glanceprep.com`
- [ ] Set real **App Store Apple ID** in `GlanceSAT-Info.plist` (replace `REPLACE_ME`)

### App Store Connect — App Privacy (nutrition labels)

Align answers with the Privacy Policy (current app: **no third-party analytics SDKs**, learning data **on device only**):

| Question | Suggested answer (current build) |
|----------|--------------------------------|
| Do you or third-party partners collect data from this app? | **No** — if nothing leaves the device except Apple subscription validation and optional support emails |
| Data linked to user | N/A if not collecting |
| Tracking | **No** |

Re-evaluate if you add analytics, crash SDKs, or a backend.

### Subscriptions (when StoreKit is live)

Apple requires in the **paywall / purchase flow**:

- [ ] Title of subscription (e.g. Monthly, Full SAT Prep)
- [ ] Length and price (must match App Store Connect products)
- [ ] Free trial terms (length, auto-renewal, price after trial)
- [ ] Link to **Privacy Policy** and **Terms** (tappable)
- [ ] Restore Purchases (if applicable)
- [ ] Manage Subscriptions path (Settings already uses `AppStore.showManageSubscriptions`)

Product IDs in App Store Connect must match code when you implement `Product` purchase.

### In-app (already wired)

- [x] Settings → Help / Privacy / Terms (Safari)
- [x] Settings → Manage subscription (StoreKit / Apple)
- [ ] Paywall: add Privacy + Terms links before submission if not already visible

---

## Accuracy notes (matched to codebase May 2026)

| Topic | Implementation |
|-------|----------------|
| Learning data | SwiftData + UserDefaults on device |
| Widgets | App Group `group.com.mikihill.GlanceSAT` |
| Onboarding fields | `@AppStorage` in `OnboardingView.swift` |
| SAT date | `satExamDateSeconds` in Settings |
| Notifications | Local `UNUserNotificationCenter` only |
| Analytics SDKs | **None** in repo |
| Accounts / cloud sync | **None** |
| Subscriptions | UI shows $7.99/mo, $49.99/yr, 7-day trial; StoreKit purchase TBD |
| 3-day preview | `hasStartedNoCardPreview` optional path |

---

## Optional but recommended

- [ ] Lawyer review (COPPA/teens, Delaware governing law, subscriptions)
- [ ] EULA: Apple’s standard EULA vs custom Terms — you use custom Terms + Apple beneficiary clause
- [ ] Export Compliance / encryption (standard HTTPS exemption questionnaire)
- [ ] Age rating questionnaire (4+, no unrestricted web)
- [ ] Screenshots and description include “SAT®” trademark line where needed

---

## When you change the app, update legal docs if you add:

- Analytics (Firebase, etc.)
- Crash reporting (Sentry, etc.)
- User accounts or cloud backup
- AI features sending text off-device
- New data types (email signup, social login)
- Different subscription prices or trial lengths

Update **Last updated** date on both pages when you publish changes.
