# Spec: OffMyPlate v1 (thin first version)

**Status:** DRAFT, awaiting owner review · **Owner:** project owner · **Date:** 2026-10-12 · **Phase covered:** concept roadmap phase 1 (MVP), narrowed by the owner's kickoff decisions in `docs/STATUS.md`

**Sources:** `docs/product-concept.md` (cited as *concept §n*), `docs/technical-specification.md` (cited as *tech §n*), `docs/STATUS.md` (cited as *kickoff #n*). Where this spec had to guess, it says **ASSUMPTION**. Open points are in section 9 (G1–G12).

## Summary (5 lines)

1. OffMyPlate v1 is an offline-first iPhone/iPad app that plans a week of Indian home cooking for one household from three quick questions.
2. A mandatory safety question (allergies and must-avoid foods, one-tap "No, nobody") gates every plan, and a deterministic planner never serves a member something they must avoid.
3. Plans are drafts until the user taps Approve; only an approved plan feeds the shopping list and pantry deductions.
4. The pantry is kept by typing or speaking; the shopping list is "approved plan minus pantry", grouped by aisle; an Apple Notes list can be shared into the app.
5. The app quietly learns soft preferences from swaps and cooked meals, shows what it learned, and lets the user correct or forget it. It never learns safety rules.

---

## 1. Problem and goal

Deciding what to cook, what to buy and what is already at home is a daily, invisible chore with constraints that differ per person (allergies, kids' lunchboxes, tastes) [concept §2]. v1 proves the core loop **plan → approve → shopping list → cook → pantry update** [concept §17] for the primary persona, *the family planner* (3–6 people, school-going kids) [concept §3], cooking Indian home food [kickoff #3]. Success means a household reaches an approved first plan in about a minute and trusts it to be safe [concept §4.1, §13].

## 2. Actors

- **Planner (device user):** an adult who sets up the household, approves plans, keeps the pantry and shops. In v1 there is exactly one planner per install (no sharing) [kickoff #2].
- **Household members:** people who eat. They are data subjects, not app users. Some are children [concept §10].
- **Apple Notes (via the Share Sheet):** source of an existing shopping list [tech §8.1].
- **The app's own automation** (planner, learning, voice parsing): may create drafts and proposals, never approvals [tech §1.9].

## 3. Goals and non-goals

### Goals (v1)
1. First draft plan within ~1 minute of first launch, from at most three questions [concept §4.1.1, tech §8.5].
2. Zero allergen or must-avoid violations in any displayed or approved plan [concept §13, tech §6.2].
3. Explicit human approval before anything acts on a plan [concept §4.1.9, tech §6.4].
4. Pantry and shopping list that stay in step with the approved plan [concept §6.1, tech §10].
5. Fully usable offline, on-device only, no OffMyPlate servers [tech §1.1, §13].

### Non-goals: deferred by the owner [kickoff #2]
- Photo/PDF AI: guidance import (nutritionist/gym plans), fridge/shelf photo recognition, receipt scan, handwritten-list OCR, barcode lookup.
- CloudKit family sharing and multi-device sync (tech §2 lists it for v1; see G6).
- Bring-your-own-key (BYOK) model providers and any off-device AI call.
- Subscription, paywall, StoreKit (see G7).
- Store carts, assisted ordering, order approval flows [concept §6.3, tech §14].

### Non-goals: not in the owner's thin list (ASSUMPTION: deferred to v1.x; owner may pull any back in)
- Chat assistant; on-device model re-ranking or natural-language explanations (template explanations are used instead) [tech §6.3].
- "Tell me more" free-form input, nutrition targets/macros, nutrition summaries [concept §6.1, §6.2].
- "Cook what I have" mode, expiry-driven planning beyond simple pantry coverage scoring [concept §6.1].
- User-added or imported recipes (URL/photo); recipe library beyond ~30 seed recipes [kickoff #2].
- Reminders (EventKit) sync, Shortcuts/App Intents actions, widgets, Live Activities, notifications, iPad kitchen mode, ratings loop [tech §8.1, concept §6.2].
- Export of the list back into Notes (share-as-text via the Share Sheet is in; see US-11).
- Pack-size rounding and "staples below threshold" [tech §10].
- Any languages other than English [tech §15].

## 4. User stories and acceptance criteria

Each criterion is written to be checkable by an automated test (domain-level unit test unless it says UI test).

### US-1 Onboarding in three questions
*As a planner I want to answer a few quick questions and see a plan, so that I get value before filling in a profile.* [concept §6.1 Onboarding, §7 First launch; tech §8.5]

- AC-1.1 **Given** first launch **When** the app opens **Then** the first screen is "Who's eating?" with adult and child steppers prefilled to a default (ASSUMPTION: 2 adults, 0 children), no account, sign-in or name fields required [concept §6.1; tech §8.5.1].
- AC-1.2 **Given** the user confirms counts A adults and C children **When** they continue **Then** A+C members exist (labelled "Adult 1…", "Child 1…"), each with `safetyStatus = unasked` [tech §5.1, §8.5.1].
- AC-1.3 **Given** the household-size step **When** the user tries to set fewer than 1 member in total **Then** they cannot continue (ASSUMPTION: max 12 members) [tech §8.5].
- AC-1.4 **Given** the cuisine step "What do you usually cook?" **When** the user picks chips or taps Skip **Then** the app continues; chosen cuisines are stored as `stated` soft Facts and skipping stores nothing [concept §6.1; tech §5.2, §8.5.3].
- AC-1.5 **Given** onboarding is complete **When** the safety question has been answered **Then** a draft weekly plan is shown, labelled as a starting point, with an Approve control [concept §7 First launch step 4].
- AC-1.6 **Given** the onboarding flow **Then** it contains no more than three questions (size, safety, cuisines) [concept §13 activation].

### US-2 Mandatory safety question
*As a planner I want to say once, clearly, what anyone must avoid, so that no plan ever includes it.* [concept §4.1.8, §6.1; tech §8.5.2]

- AC-2.1 **Given** the safety screen **Then** it shows a one-sentence reason for asking, a prominent "No, nobody" button, chips for common allergens/restrictions, and a text field, and it has **no** skip, close or back-to-plan control [tech §8.5.2] (UI test).
- AC-2.2 **Given** the safety screen **When** the user taps "No, nobody" **Then** every current member becomes `confirmedNone` with `confirmedAt` set [tech §5.1].
- AC-2.3 **Given** the safety screen **When** the user selects chips or types/speaks items (e.g. "no beef", "one of us can't have nuts") **Then** they are shown back as candidate hard rules, and only after the user confirms are they saved as `Rule(kind: hard, source: user)` and the affected members set to `stated` [tech §5.1, §8.5.2]. Assignment to members follows G3.
- AC-2.4 **Given** text the parser cannot map to a known allergen/restriction tag **When** shown back **Then** the user must pick a tag or remove the item; unmapped free text is never silently dropped and never silently saved as "safe" (ASSUMPTION, follows tech §6.2 "unverified" principle).
- AC-2.5 **Given** chips **Then** they include at least: peanuts, tree nuts, dairy/milk, egg, wheat/gluten, soy, sesame, mustard, fish, shellfish, beef, pork, vegetarian, Jain (no root vegetables, onion, garlic) (ASSUMPTION for Indian home cooking; see G1).
- AC-2.6 **Given** any screen in the app **Then** the medical disclaimer is reachable, and it is shown on the safety screen (see US-14) [tech §6.2].

### US-3 Safety gate blocks planning
*As a planner I want the app to refuse to plan for anyone it has not asked about, so that safety is never guessed.* [concept §6.1, §10; tech §6.2]

- AC-3.1 **Given** any member with `safetyStatus = unasked` **When** any code path requests plan generation, regeneration, slot re-roll or swap **Then** the domain layer refuses with a "safety unanswered" result and no plan or meal is produced [tech §6.2]. A test fails the build if any planner entry point bypasses the gate [tech §6.2, §12.2].
- AC-3.2 **Given** an existing household **When** the planner adds a member **Then** the new member is `unasked`, the safety question is shown for that member immediately, and planning stays blocked until it is answered [concept §6.1; tech §8.5].
- AC-3.3 **Given** a member becomes `unasked` while an approved plan exists **Then** the approved plan stays visible and usable for existing members, but no new draft, swap or regenerate is possible until the question is answered (ASSUMPTION).
- AC-3.4 **Given** a member's age band changes from child to teen/adult (or vice versa), or the periodic re-confirmation is due (G3) **Then** the safety re-confirmation is shown, exempt from the contextual-prompt caps [tech §8.5].
- AC-3.5 **Given** a household and safety settings screen **When** the user adds, edits or removes a hard rule **Then** it takes effect for the next draft and the validator re-runs on any open draft [tech §6.2].

### US-4 Planner hard-rule guarantees
*As a planner I want a guarantee that plans respect every hard rule, so that I can trust them without checking each recipe.* [concept §10; tech §6.1, §6.2, §12.2]

- AC-4.1 **Given** any household and the seed library **When** a plan is generated **Then** no slot contains a recipe with an ingredient whose allergen/diet tags violate a hard rule of any member eating that slot [tech §6.1 step 3]. Verified by property-based tests over generated households [tech §12.1].
- AC-4.2 **Given** a generated plan **Then** an independent validator (separate code path) re-checks it before display and again at approval; a failing plan is never displayed or approved [tech §6.2].
- AC-4.3 **Given** an ingredient with missing or unresolved allergen tags ("unverified") **When** any member eating the slot has any hard rule **Then** the recipe is excluded for that slot [tech §6.2; concept §10].
- AC-4.4 **Given** hard rules leave no valid recipe for a slot **Then** the slot is left empty with an explanation ("No safe recipe for this meal yet"), never filled with a violating recipe (ASSUMPTION).
- AC-4.5 **Given** the CI pipeline **Then** a non-skippable safety suite runs the allergen/diet-rule matrix × every seed recipe × member combinations and fails the build on any violation [tech §12.2].
- AC-4.6 **Given** the same inputs and seed **When** the planner runs twice **Then** it produces the same plan (deterministic) [tech §6].
- AC-4.7 **Given** a planned meal **Then** it shows a short template explanation built from its score components (e.g. "uses your paneer; quick weekday dinner") [tech §6.1 step 8, §6.3].

### US-5 Draft → approved plan lifecycle
*As a planner I want nothing to happen until I approve, and to see exactly what changed when I edit, so that I stay in control without re-checking everything.* [concept §4.1.9, §6.1 Meal planning; tech §6.4]

- AC-5.1 **Given** a newly generated plan **Then** its status is `draft` [tech §5.1, §6.4].
- AC-5.2 **Given** a draft **When** the user taps Approve once **Then** the whole week becomes `approved`, storing approver ("this device", see G8), timestamp and a content hash [tech §6.4]. Per-meal review is available before approving.
- AC-5.3 **Given** a plan that is not `approved` **Then** no shopping list items are derived from it and "Mark cooked" (pantry deduction) is unavailable for its meals [tech §6.4].
- AC-5.4 **Given** an approved plan **When** the user swaps, re-rolls, locks/unlocks or regenerates any meal **Then** a draft revision is created, the previous approved version stays active for downstream use until re-approval (ASSUMPTION), and the approval sheet lists only the changed meals; the validator re-runs before re-approval is allowed [tech §6.4].
- AC-5.5 **Given** an approved plan whose content hash no longer matches its stored approval **Then** it is treated as not approved [tech §6.4].
- AC-5.6 **Given** voice input such as "looks good" or "approve it" **Then** the app opens the approval sheet and still requires a confirming tap; no voice, share-extension or background path can set `approved` [tech §6.4, §7.3]. Tested by asserting the approve transition is reachable only from the in-app Approve action.
- AC-5.7 **Given** an approved plan is replaced by a newly approved revision **Then** the old one becomes `superseded`; a discarded draft becomes `discarded` [tech §6.4].

### US-6 Weekly plan, slots and per-member servings
*As a planner I want one shared meal with sensible portions per person, so that I cook once for everyone.* [concept §6.1 Meal planning; tech §5.1, §6.1 step 6]

- AC-6.1 **Given** a generated plan **Then** it covers 7 days with breakfast, lunch and dinner slots (ASSUMPTION: snacks off by default, can be turned on; see G5) [concept §6.1].
- AC-6.2 **Given** a planned meal **Then** each eating member has a serving with a portion size derived from age band (ASSUMPTION: adult 1.0, teen 1.0, child 0.6, toddler 0.4) that the user can adjust per member [tech §5.1 MealServing].
- AC-6.3 **Given** a member marked "not eating" for a meal **Then** they get no serving and their hard rules no longer constrain that slot (ASSUMPTION; follows tech §6.1 "any eater of that slot").
- AC-6.4 **Given** per-member servings **When** the shopping list is derived **Then** quantities are recipe quantity × sum of portions, unit-normalised [tech §10].

### US-7 Lunchbox slot via contextual prompt
*As a parent I want the app to ask about school lunches only when it matters, so that onboarding stays short.* [concept §6.1 Progressive profile; tech §8.5 Contextual prompts]

- AC-7.1 **Given** a household with at least one child **When** the user first opens a lunch slot **Then** the prompt "Do any of the kids take lunch to school?" appears once, skippable [concept §6.1].
- AC-7.2 **Given** the user answers yes and picks children and days (default Mon–Fri) **Then** those children get `needsSchoolLunch` and `schoolDays`, and the current draft (or a new draft revision) gains a `lunchbox` slot on those days, filled only from school-lunch-suitable recipes [tech §5.1, §6.1 step 2].
- AC-7.3 **Given** the user skips or dismisses the prompt **Then** it is not shown again for a cooldown (ASSUMPTION: 14 days) [tech §8.5].
- AC-7.4 **Given** the contextual-prompt scheduler **Then** at most one prompt is visible at a time and non-safety prompts are capped per week (ASSUMPTION: 3) [tech §8.5].

### US-8 Swap, lock, regenerate
*As a planner I want to change any meal easily, so that the plan fits our week.* [concept §6.1; tech §6.1, §6.4]

- AC-8.1 **Given** a meal **When** the user taps Swap **Then** up to 3 alternative valid recipes for that slot are offered (ASSUMPTION), all passing the hard-rule checker [tech §6.2].
- AC-8.2 **Given** a meal **When** the user re-rolls with an optional reason chip ("don't feel like it", "too long", "kids won't eat it") **Then** a different valid recipe replaces it and the reason is logged as a learning event [concept §6.1; tech §8.5].
- AC-8.3 **Given** locked meals **When** the user regenerates the week **Then** locked meals are unchanged and all others may change [tech §5.1 `locked`].
- AC-8.4 **Given** any swap/re-roll/regenerate on an approved plan **Then** AC-5.4 applies.

### US-9 Pantry: manual and voice
*As a planner I want to keep track of what's at home by typing or speaking, so that plans and lists use it.* [concept §6.1 Pantry; tech §5.1 PantryItem, §8.3]

- AC-9.1 **Given** the pantry screen **When** the user adds an item manually (name via search picker over the ingredient taxonomy, quantity, unit, location fridge/freezer/shelf, optional expiry) **Then** a PantryItem is saved with `source: manual` [tech §5.1, §7.2 `resolveIngredient` fallback].
- AC-9.2 **Given** a name that matches no ingredient **Then** the item is saved as free text, marked unresolved, and does not count toward covering plan requirements until resolved (ASSUMPTION) [tech §5.1].
- AC-9.3 **Given** the user edits or deletes a pantry item **Then** the change is saved and the shopping list recomputes [tech §10].
- AC-9.4 **Given** the user says "I bought 2 kg rice and a dozen eggs" **When** transcription completes **Then** a confirmation card lists the parsed items (rice 2 kg, eggs 12) for edit/confirm, and nothing is saved until confirmed [tech §8.3; concept §6.1]. Parsing uses the deterministic command grammar (see G9).
- AC-9.5 **Given** speech recognition is unavailable (no permission, unsupported device, or offline without on-device support) **Then** the voice control explains why and manual entry remains available [tech §1.5].
- AC-9.6 **Given** a meal in an **approved** plan **When** the user taps "Mark cooked" **Then** pantry quantities decrease by recipe quantities × servings (editable on a confirm sheet), never below zero, and a CookLog entry is written [concept §6.1; tech §10]. **Given** a draft plan **Then** "Mark cooked" is not available [tech §6.4].
- AC-9.7 **Given** a pantry item not re-confirmed for a while **Then** its confidence decays (ASSUMPTION: below threshold after 7 days for fridge items, 60 days for shelf/freezer; re-confirming resets it) [tech §5.1].

### US-10 Shopping list from the approved plan
*As a planner I want a list of only what I need to buy, grouped the way I shop.* [concept §6.1 Shopping list; tech §10]

- AC-10.1 **Given** an approved plan for the week **Then** the list = Σ(approved meals' ingredients × servings) − usable pantry quantities, unit-normalised [tech §10].
- AC-10.2 **Given** no approved plan **Then** the list holds only manual and imported items [tech §6.4].
- AC-10.3 **Given** list items **Then** they are grouped by aisle/category from the ingredient taxonomy (ASSUMPTION aisles: vegetables & fruit, dairy & eggs, grains & flours, pulses & lentils, spices & masalas, oils & ghee, meat & fish, bakery, other) [tech §5.1 ShoppingItem].
- AC-10.4 **Given** a pantry item that covers a need but has confidence below threshold **Then** it appears in a separate "Check you have" group instead of being silently subtracted [tech §10].
- AC-10.5 **Given** the user adds a manual item or checks one off **Then** it persists, and after a plan re-approval derived items recompute while manual items and check-offs on unchanged items are kept (ASSUMPTION) [tech §5.1 `origin`].
- AC-10.6 **Given** the user taps "Bought everything" **Then** checked items are added to the pantry [tech §10].
- AC-10.7 **Given** the list **When** the user taps Share **Then** a plain-text list goes to the system Share Sheet (e.g. into Notes or a messaging app) [tech §8.1 Export].

### US-11 Apple Notes import via Share Extension
*As a planner I want to send my existing Notes shopping list to the app, so that I don't retype it.* [concept §6.1, §8 Apple Notes; tech §8.1]

- AC-11.1 **Given** a note in Apple Notes **When** the user shares it and picks OffMyPlate **Then** the extension parses the text into items `{name, qty?, unit?}` with the rule-based tokenizer (bullets, checkboxes, "2 kg rice", "rice - 2kg", "milk x2") [tech §7.2 `parseShoppingText`].
- AC-11.2 **Given** the parsed items **Then** a review screen lets the user edit, remove and choose a destination: shopping list (default) or pantry (ASSUMPTION), and nothing is saved until the user confirms [tech §8.1].
- AC-11.3 **Given** confirmed items **When** the main app next becomes active **Then** they are merged from the shared App Group store, de-duplicated against existing items by ingredient, with `origin: Notes import` [tech §8.1, §5.1].
- AC-11.4 **Given** shared content that is not text (image, PDF) **Then** the extension says it is not supported yet (deferred) [kickoff #2].
- AC-11.5 **Given** an import **Then** item names count as learning evidence (staples) only, never as safety information [tech §5.2].

### US-12 Learned soft preferences
*As a planner I want the app to notice what we like and check with me, so that plans improve without forms.* [concept §4.1.2, §4.1.5, §10; tech §5.2, §8.5]

- AC-12.1 **Given** swaps, re-rolls (with reasons), skips, "cooked" taps and Notes imports **Then** they are recorded as on-device events and update `inferred` Facts with confidence that decays without reinforcement [tech §5.2, §8.5 Learning signals].
- AC-12.2 **Given** an inferred Fact **When** it reaches the evidence threshold (ASSUMPTION: ≥3 independent events across ≥2 different weeks) **Then** it becomes `proposed` and may be shown as a reflect-back card with **Yes / Not really / Don't ask again**, max one card per week (ASSUMPTION) [tech §5.2, §8.5].
- AC-12.3 **Given** Yes → Fact `confirmed`; Not really → `dismissed`; Don't ask again → `dismissed` and never re-proposed [tech §8.5].
- AC-12.4 **Given** any pattern, however strong (e.g. every dairy meal swapped out) **Then** inference never creates or changes a hard Rule or a member's `safetyStatus`; at most a soft Fact is proposed, and confirming it keeps it soft [tech §5.2; concept §10]. Hard rules are created only on the safety screen (US-2/US-3).
- AC-12.5 **Given** the "What I've learned" screen **Then** it lists every active and proposed Fact in plain language with its origin (said / confirmed / noticed / default), and the user can edit it or Forget it; Forget removes the Fact and its evidence weight from future scoring [tech §5.2].
- AC-12.6 **Given** confirmed or stated soft Facts **Then** they change planner scores only, never hard filtering [tech §6.1 step 4].

### US-13 Offline operation
*As a planner I want everything to work without a connection.* [tech §5.3, §13]

- AC-13.1 **Given** airplane mode **Then** onboarding, planning, approval, pantry (manual), shopping list, Notes import and "What I've learned" all work (UI test) [tech §13].
- AC-13.2 **Given** the app at any time **Then** it makes no network requests to OffMyPlate or third-party servers (ASSUMPTION: no analytics or crash SDKs; see NFR) [tech §11].

### US-14 Medical disclaimer
*As a planner I want to know the app's limits.* [concept §10; tech §6.2, §11]

- AC-14.1 **Given** the safety screen, the plan screen and Settings → About **Then** a persistent, non-dismissable notice says the app does not provide medical advice and the user should check ingredients and labels (wording to be reviewed, G4) [tech §6.2].

### US-15 Accessibility basics
*As a planner who uses accessibility features I want to use every v1 screen.* [tech §15, §12.1]

- AC-15.1 **Given** Dynamic Type at the largest accessibility size **Then** every v1 screen remains usable without truncating actions (UI/snapshot test).
- AC-15.2 **Given** VoiceOver **Then** every control has a meaningful label, including the "No, nobody" and Approve buttons and allergen chips.
- AC-15.3 **Given** colour contrast checks **Then** text meets WCAG AA; state (e.g. draft vs approved, unverified) is never conveyed by colour alone.
- AC-15.4 **Given** Reduce Motion on **Then** non-essential animations are removed.
- AC-15.5 **Given** iPhone and iPad (including split view) **Then** layouts adapt without clipped content; no dedicated iPad kitchen layout in v1 [tech §3, concept §6.2].

### US-16 Household and data controls
*As a planner I want to manage members and delete our data.* [tech §5.1, §11]

- AC-16.1 **Given** Settings → Household **Then** the user can add/remove members and optionally set name and age band; only existence and safety status are required [tech §5.1].
- AC-16.2 **Given** "Delete all data" with a confirmation **Then** all household, pantry, plan, list, Fact and event data is removed from the device and onboarding restarts [tech §11 Compliance].

## 5. Non-functional requirements

| Area | Requirement | Source |
|---|---|---|
| Cold start | < 1.5 s to interactive on iPhone 12-class | tech §13 |
| Plan generation | Full week (deterministic) < 2 s on iPhone 12-class | tech §13 |
| Offline | Planning, pantry, list fully usable offline | tech §13 |
| Stability | ≥ 99.5% crash-free sessions (measured from TestFlight/App Store Connect reports) | tech §13 |
| Storage | Local store bounded; CookLog/events older than 12 months archived or pruned | tech §13 |
| Privacy | No OffMyPlate servers; all data on-device; no third-party SDKs that collect data; no off-device AI | tech §1.1, §11; kickoff #2 |
| Encryption | iOS Data Protection on the local store | tech §11 |
| Children | Minimal data: no names or birth dates required, age band optional; parent-managed only; nothing tied to analytics identifiers | tech §11; concept §10 |
| Analytics | v1: none leaves the device. On-device counters (time to first plan, prompts answered/skipped) only, for future opt-in | tech §8.5, §11 |
| Permissions | Microphone and speech recognition requested just-in-time with purpose strings; no camera, Reminders or Calendar in v1 | tech §11 |
| Safety QA | Non-skippable safety suite in CI; property tests on planner | tech §12.1–12.2 |
| Accessibility | Dynamic Type, VoiceOver, contrast, Reduce Motion | tech §15 |
| Localisation | English only, but strings in a string catalog; metric units (ASSUMPTION for India) | tech §15 |
| Build | Pure-Swift domain core buildable/testable on Linux; app, extension and UI tests on the owner's Mac (Xcode) and a macOS GitHub Actions runner | kickoff #1; tech §4.1 |

**Also needed (capabilities):** `privacy-compliance` (health-adjacent and children's data: on-device only, delete-all, professional review G4), `database` (on-device store, migrations, App Group share with the extension), `secrets-and-config` (no secrets in v1; signing material stays out of the repo), `deployment-hosting` (TestFlight/App Store distribution, no server), `analytics-observability` (Apple crash reports only, no third-party SDK).

## 6. Data the app holds (one-page data map)

Household (member count, optional names/age bands, safety status per member, hard rules), Facts and learning events, plans and approvals, pantry, shopping list, CookLog. All on-device; deleted by "Delete all data"; not synced (sync deferred). Health-adjacent: allergies and restrictions. Children's data: optional name and age band only.

## 7. Assumptions

1. A1 Single planner, single device, no account [kickoff #2].
2. A2 The ~30 seed recipes ship inside the app bundle; no content-pack updates in v1 [tech §9, kickoff #2].
3. A3 Every seed recipe ingredient is resolved to a canonical ingredient with allergen/diet tags; missing tags are treated as unverified (AC-4.3).
4. A4 v1 is distributed via TestFlight to a small beta (concept §15 phase 1 target ~50 households), not the App Store.
5. A5 Metric units; Indian ingredient names and common transliterations in the taxonomy (e.g. "dahi"/"curd"/"yogurt") [tech §9, §15].
6. A6 While an approved plan has a pending draft revision, the approved version stays active for shopping and cooking (AC-5.4).
7. A7 No on-device language model is used in v1; every "model" task uses its documented non-AI fallback [tech §7.2].
8. A8 The week starts Monday; the plan covers the next 7 days from approval (owner can change).

## 8. Constraints

- iOS/iPadOS native app, SwiftUI, Swift Package modules with an Apple-framework-free domain core [tech §3, §4.1].
- No backend [tech §1.1, concept §8].
- Planning and safety logic are deterministic code, never a model [tech §1.3].

## 9. Gaps, ambiguities and contradictions

★ = one of the five the owner most needs to answer. The rest proceed on the default unless the owner objects.

**G1 ★ Who supplies and verifies the seed recipes and allergen data?**
*Where:* tech §9, §17.4; concept §8, §16.7. *Why:* the safety guarantee is only as good as the ingredient allergen tags; 30 Indian recipes need a taxonomy (incl. hidden allergens such as hing compounded with wheat flour, ghee/dairy, peanut oil, mustard). *Default:* the team drafts 30 original recipes (about 8 breakfast, 14 lunch/dinner, 8 lunchbox-suitable) and a ~150-ingredient taxonomy with tags; the owner (or a person they nominate) signs off each recipe's tags before beta; provenance recorded per recipe; any ingredient with a "may contain" doubt is tagged conservatively.

**G2 ★ Minimum iOS version and devices.**
*Where:* tech §3, §17.1; concept §16.4. *Why:* drives APIs (SwiftData, speech) and test matrix. *Default:* iOS/iPadOS 18, iPhone primary, iPad supported with adaptive layouts; no Apple Intelligence dependency in v1, so all iOS 18 devices get the full v1 feature set.

**G3 ★ Safety answer per member or per household, and re-confirmation cadence.**
*Where:* concept §16.9, tech §5.1, §8.5, §17.10. *Why:* onboarding has no names, yet rules are stored per member. *Default:* status per member (as tech §5.1). Onboarding lets the user tag each stated item to a member ("Adult 1", "Child 2") or "Not sure who"; "Not sure who" applies the rule to the whole household (safer). Re-confirm when a member is added (blocking), when a child's age band changes, and every 180 days via a one-tap "Still correct?" that blocks only new drafts.

**G4 ★ Medical, allergen and children's-privacy (COPPA/GDPR-K) professional review.**
*Where:* concept §10, §16.11; tech §11. *Why:* allergen claims and children's data carry liability; the privacy capability requires a qualified human for health and children's data. *Default:* TestFlight beta may proceed with the disclaimer; before any App Store release, a qualified legal/privacy reviewer approves the privacy policy, data map and disclaimer wording, and a dietitian or food-safety reviewer spot-checks the recipe allergen tags. Tracked as a release blocker.

**G5 ★ Is ~30 recipes enough for the slots promised?**
*Where:* kickoff #2 vs concept §6.1 (breakfast, lunch, dinner, snacks, lunchbox) and tech §6.1 (variety window). *Why:* with allergens removed, 30 recipes can leave slots empty or repetitive. *Default:* v1 plans breakfast, lunch and dinner (snacks optional, off by default); lunchbox from its own subset; variety rule "no repeat within 3 days" relaxed automatically when not enough safe recipes remain, with the slot explaining why.

**G6 iCloud family sync: tech §2 lists it in v1; concept §15 puts it in phase 2. RESOLVED:** owner deferred CloudKit sharing [kickoff #2]. *Consequence/default:* local store only; data survives via normal device backup; keep sync-ready fields (ids, timestamps, soft-delete) per tech §5 so sync can be added later.

**G7 Subscription in concept §12 with no StoreKit design. RESOLVED:** deferred [kickoff #2]. *Default:* v1 is free with no paywall or free-tier limits.

**G8 Who may approve in a shared household (concept §16.10, tech §17.11).** *Moot for v1* because there is no sharing. *Default:* approval records "this device"; the data model keeps an approver field so a rule (e.g. adults only) can be added with sharing.

**G9 Voice without an on-device model.**
*Where:* tech §7.2 `parseSpokenCommand`, §8.3; concept §8. *Why:* v1 uses no model, and speech-to-text availability offline varies by device/language. *Default:* Apple speech recognition (on-device where supported) feeds a deterministic grammar covering "I bought/add <qty> <unit> <item> [and …]", "we're out of / used up <item>", "remove <item>"; numbers as digits or words, "a dozen", "half a kilo". Anything unparsed opens the manual form prefilled with the transcript. Voice covers pantry only in v1.

**G10 What learned preferences do in v1 without sharing or a model.**
*Where:* tech §5.2, §8.5, §17.9, §17.12. *Why:* signals, thresholds and scope are undefined. *Default:* Facts are household-level (per-member only when the user attributes them); v1 signals are swaps, re-roll reasons, skips, "cooked" and Notes imports; proposals need ≥3 events over ≥2 weeks; max one reflect-back card per week; inferred weights decay with a ~4-week half-life.

**G11 Notes import destination and scope.**
*Where:* concept §5 ("last shopping list"), §6.1; tech §8.1. *Why:* an imported list could mean "to buy" or "already bought". *Default:* review screen asks "Add to shopping list" (default) or "Add to pantry"; text only; the Shortcuts action and Reminders sync deferred; export by Share Sheet text only.

**G12 Features named for v1 in the source documents but absent from the owner's thin list.**
*Where:* concept §6.1 ("Tell me more", "Cook what I have", camera input, list sharing with family), tech §2. *Why:* silent omission could surprise the owner. *Default:* all deferred to v1.x as listed in section 3; hard rules can still be edited later in Settings → Household & safety.

## 10. Handoff

```
HANDOFF
From: requirements-analyst   To: human (owner), then architect
Status: NEEDS-HUMAN
Summary: Ingested concept + tech spec + kickoff decisions into a thin-v1 spec: 16 user stories with
  numbered, source-cited acceptance criteria; NFRs from tech §13; 12 gaps with defaults (2 resolved by
  kickoff, 1 moot). Owner review needed on the 5 starred gaps; everything else proceeds on defaults.
Artifacts: docs/specs/offmyplate-v1.md
Open items:
  1. G1 seed recipe/allergen data: who supplies and signs off (default: team drafts, owner signs off)
  2. G2 minimum OS (default: iOS/iPadOS 18, no Apple Intelligence dependency)
  3. G3 safety answer per member + re-confirm cadence (default: per member, "Not sure who" = household, 180 days)
  4. G4 professional legal/privacy/dietitian review before App Store (default: required, beta may proceed)
  5. G5 30 recipes vs slots (default: B/L/D + lunchbox, snacks off, relaxed variety)
Next: Owner approves the spec or answers G1-G5. Architect then designs the module layout, data model
  and the safety-gate/approval state machines from this spec (tech §4-§6), keeping OMPDomain buildable
  and testable on Linux.
```
