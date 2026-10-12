# OffMyPlate — Product Concept

**Status:** Draft v0.1 · **Date:** 2026-10-12 · **Platforms:** iPhone, iPad (iOS/iPadOS)

> *"What's for dinner?" — answered, shopped for, and off your plate.*

---

## 1. Vision

A kitchen companion that removes the daily mental load of deciding what to cook, what to buy, and what's already at home. OffMyPlate plans meals around the **real household** — who is eating, what's in the pantry, what the family actually likes, and what health guidance each person has been given — and eventually turns the plan into a filled grocery cart.

## 2. Problem

Household meal planning is a recurring, invisible chore with many interacting constraints:

- Decisions are made daily, under time pressure, with incomplete information ("what do we even have?").
- Constraints differ per person: kids' school lunches, allergies, a parent on a gym plan, a grandparent on a diabetic diet, a nutritionist's prescribed menu.
- Food gets wasted because purchases aren't tied to meals, and meals aren't tied to what's on hand.
- Shopping lists live in scattered places (Notes, WhatsApp, memory, paper).
- Existing recipe apps are recipe-centric, not household-centric; they ignore pantry state and personal dietary guidance.

## 3. Target Users

| Persona | Description | Key need |
|---|---|---|
| **The family planner** (primary) | Parent managing meals for 3–6 people, including school-going kids | Daily/weekly plan that respects everyone's constraints with minimal effort |
| **The health-guided household** | Someone following a nutritionist, dietitian, or gym coach plan | Turn a PDF/photo/text of a diet plan into actual cooked meals and groceries |
| **The couple / single** | 1–2 people who waste food and default to takeout | Use what's at home, shop less, cook more |

Initial market: English-speaking households with iPhone/iPad; expand regional cuisines early since "what we usually eat" is highly cultural (e.g., Indian, Mediterranean, East Asian home cooking).

## 4. Core Value Proposition

1. **Household-aware planning** — plans for *this* family, not a generic one.
2. **Pantry-aware** — uses what's at home first; shops only for the gap.
3. **Guidance-aware** — honours nutritionist/gym/doctor instructions as first-class inputs.
4. **Effortless input** — read Notes, snap a photo, or just talk.
5. **Closes the loop** — plan → shopping list → cart (later: auto-order).

## 5. Inputs the Planner Understands

| Input | Examples | Capture method |
|---|---|---|
| **Household profile** | Members, ages, kids needing school lunch, who's home on which days | Onboarding, editable anytime |
| **Eating habits** | Cuisines, usual dishes, spice level, cook time budget, appliances available | Onboarding quiz + learning from history/ratings |
| **Dietary restrictions** | Vegetarian, halal, allergies, diabetic, low-sodium, religious fasting days | Per-member profile |
| **Professional guidance** | Nutritionist plan, gym coach macros, doctor's advice | Upload PDF / photo / paste text / dictate; parsed into structured rules |
| **Pantry & fridge inventory** | Items, quantity, expiry | Photo scan, voice, receipt scan, manual, auto-deduct after cooking |
| **Last shopping list / purchases** | What was bought recently | Apple Notes import, receipt scan, order history (later) |
| **Custom advice** | "Dad avoids dairy at night", "Fish only on Fridays", "Kids hate gourds" | Free text/voice; stored as persistent rules |
| **Context** | Budget, guests, travel, festivals, weather, time available this week | Quick prompts / calendar (opt-in) |

## 6. Key Features

### 6.1 MVP (v1)

**Onboarding & household profile**
- Add family members with age, diet type, allergies, goals, and school-lunch flag.
- Choose cuisines, typical dishes, cooking skill/time, available appliances.

**Meal planning**
- Weekly plan (breakfast, lunch, dinner, snacks, **school lunchbox** as a distinct slot).
- Per-member variations on a shared base meal (e.g., same dal, plus extra protein for the gym-goer, soft version for the toddler).
- Swap, lock, or regenerate any meal; "I don't feel like this" re-roll with a reason.
- "Cook what I have" mode: suggests meals from current pantry, prioritising items nearing expiry.
- Rules honoured as hard constraints (allergies, medical) vs. soft preferences (likes/dislikes).

**Guidance import**
- Upload or photograph a nutritionist/gym plan; the app extracts targets (calories, macros, meal timings, do/don't foods) and shows them for confirmation before use.

**Pantry**
- Maintain a home inventory via photo scan of fridge/shelf, voice ("I bought 2 kg rice and a dozen eggs"), receipt scan, or manual entry.
- Auto-decrement when a planned meal is marked cooked.

**Shopping list**
- Generated as *plan requirements minus pantry*, grouped by store aisle/category.
- **Apple Notes integration** to import an existing shopping list and (where the platform allows) export the generated list back.
- Share list with family members.

**Multimodal input**
- **Voice:** conversational ("Plan next week, we have guests Saturday, and Aarav's off dairy for a week").
- **Camera:** scan fridge/pantry, grocery receipts, packaged-food labels, diet-plan documents, handwritten lists.
- **Text/Notes:** paste or import.

### 6.2 v1.x

- Nutrition summary per person/day/week vs. targets.
- Leftover planning (cook once, eat twice).
- Batch-cooking / meal-prep scheduling and a "tonight's cooking steps" timeline.
- Recipe import from URL/photo of cookbook page.
- Ratings and feedback loop ("loved it / kids refused it").
- iPad kitchen mode: large type, hands-free voice navigation, step-by-step cooking view.
- Widgets, Lock Screen/Live Activities ("Tonight: Paneer wrap — start at 6:30"), Siri/App Shortcuts.

### 6.3 Later: Shopping Automation

- **Phase A — Add-to-cart:** build a cart in supported stores/delivery apps from the shopping list; user reviews and checks out themselves.
- **Phase B — Auto-order:** scheduled or one-tap ordering with spend caps and confirmation rules.
- Store connections where the user supplies credentials (see §9 for the security approach and a recommended alternative).
- Product matching: brand preferences, substitutions, pack-size optimisation, price comparison across stores.
- Reconcile delivered items into the pantry automatically.

## 7. Example User Flows

**Sunday planning (5 minutes)**
1. User says: "Plan the week. Two of us are on a high-protein plan, kids need lunchboxes Mon–Fri, no beef."
2. App checks pantry, last week's list, guidance rules, and favourites.
3. Presents a week view; user swaps Wednesday dinner.
4. App produces a shopping list (only the gaps) and offers to push it to Notes or a store cart.

**Daily "what's for lunch?"**
- Morning notification: today's meals + lunchbox. One tap to mark cooked (deducts pantry) or swap.

**Importing a nutritionist plan**
- Photograph a printed diet chart → app extracts rules → user confirms ("1,800 kcal, 90 g protein, no refined sugar, oats at breakfast") → plan generation uses them going forward.

**After shopping**
- Scan receipt → items added to pantry with estimated expiry → next plan uses them.

## 8. Platform & Technical Considerations (iOS / iPadOS)

| Capability | Approach | Notes / constraints |
|---|---|---|
| **UI** | SwiftUI, universal app with adaptive layouts (iPhone compact, iPad split-view/Stage Manager) | iPad gets a dedicated kitchen/planning layout |
| **Apple Notes** | Notes has **no public read API**. Options: Share Sheet extension ("Send to OffMyPlate" from a note), App Intents / Shortcuts action, copy-paste, or the user exporting the note text. | Direct background reading of Notes is not available; design around share-extension + Shortcuts. Consider Apple **Reminders (EventKit)** as a fully supported alternative for shopping lists. |
| **Camera scanning** | VisionKit `DataScannerViewController` + Vision text recognition (on-device OCR); barcode scanning for packaged goods | On-device first for privacy and speed |
| **Image understanding** (fridge photos, handwritten lists, diet-plan PDFs) | Multimodal LLM via backend for recognition and structuring; on-device OCR as pre-step | Confirm-before-save UI for every extraction |
| **Voice** | Speech framework / on-device dictation for transcription; LLM for intent parsing; optional spoken replies (AVSpeechSynthesizer) | Hands-free mode important in the kitchen |
| **Planning engine** | Constraint solver (hard rules: allergies, macros, inventory) + LLM for creativity, variety, and natural-language interaction | LLM proposes, deterministic validators verify constraints before display |
| **Data & sync** | On-device store (SwiftData/Core Data) + CloudKit for household sync across family devices | Shared household via CloudKit sharing |
| **Backend** | Thin service for LLM orchestration, recipe/nutrition data, and (later) store connectors | Minimise PII sent; no raw health docs retained server-side by default |
| **Notifications & surfaces** | Local notifications, widgets, Live Activities, App Shortcuts/Siri | |
| **Nutrition data** | Licensed or open nutrition database (e.g., USDA FoodData Central plus regional datasets) | Regional coverage matters for home-cooked dishes |

## 9. Store Integration & Credentials — Approach

The "give us your store credentials" model is the highest-risk part of the product.

- **Reality check:** most grocery retailers have no public consumer-facing ordering API. Storing user passwords and automating logins (screen-scraping) is fragile, often violates store ToS, can trigger fraud/2FA lockouts, and creates serious liability.
- **Preferred order of approach:**
  1. **Official partner APIs / affiliate programs** where available (OAuth-based, no password handling).
  2. **Deep links / share handoff** — open the store app with items pre-filled, or generate a cart link.
  3. **On-device automation via the user's own session** (e.g., in-app web view where the user logs in themselves; credentials never leave the device and are stored only in iOS Keychain).
  4. Server-side stored credentials only as a last resort, encrypted, with explicit consent — and likely avoided entirely.
- **Safety rails for auto-order:** spend caps, mandatory confirmation above a threshold, substitution rules, order preview, easy cancel window, full audit log.
- **Launch strategy:** begin with 1–2 stores in a single region with the best integration path; treat "add to cart" as the v1 automation milestone.

## 10. Privacy, Safety & Trust

- Health and dietary data is sensitive: on-device storage by default, encrypted CloudKit sync, clear data-deletion controls, App Store privacy labels kept accurate.
- Allergen safety: hard constraints are enforced by a deterministic checker, not left to the LLM; ambiguous ingredients are flagged. Persistent disclaimer that the app does not replace medical advice.
- Professional guidance is treated as authoritative input; the app never overrides it and surfaces conflicts ("Plan says no dairy; this recipe contains paneer — replaced").
- Child profiles: minimal data, parent-managed only, COPPA/GDPR-K aware.
- LLM transparency: clear indication when content is AI-generated; user can inspect why a meal was chosen ("uses your spinach expiring Thursday; fits Dad's 90 g protein target").
- Credentials (if ever collected) live only in Keychain / secure enclave-backed storage.

## 11. Differentiators vs. Existing Apps

| Existing approach | Gap | OffMyPlate |
|---|---|---|
| Recipe apps (Yummly, Tasty) | Recipe-first, ignore household and pantry | Household-first planning |
| Meal-plan subscriptions (eMeals, Mealime) | Generic templates, limited personalisation, minimal pantry awareness | Learns what *this* family eats, uses real pantry state |
| Nutrition trackers (MyFitnessPal) | Log after eating; don't plan for a family | Plans ahead for everyone, with per-person targets |
| Grocery list apps | Lists unconnected to meals | Lists derived from plan minus pantry |
| Smart-fridge ecosystems | Hardware lock-in | Works with a phone camera and voice |

**Moat over time:** the accumulated household taste/pantry model, parsed professional guidance, and store connections.

## 12. Monetisation (Hypotheses)

- **Freemium:** free tier — 1 week plan, basic list; **Premium subscription** (household plan) — unlimited planning, multi-member guidance, pantry scanning, family sharing, nutrition insights.
- **Affiliate / delivery referral fees** from store cart handoff (disclosed clearly).
- Possible future B2B2C: nutritionists/gym coaches push structured plans straight into clients' apps (pro tier).

## 13. Success Metrics

- **Activation:** % of new users who generate a first weekly plan within 24 h.
- **Engagement:** weekly active households; meals marked cooked per week; plans edited vs. accepted as-is.
- **Value:** self-reported time saved; reduction in food waste (pantry items expiring unused); takeout-substitution rate.
- **Quality:** meal rating average; swap/re-roll rate; allergen-violation rate (target: zero).
- **Retention:** week-4 and week-12 household retention; paid conversion.
- **Automation (later):** % of shopping lists converted to carts; cart-to-checkout completion.

## 14. Risks & Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Apple Notes has no read API | Core input broken | Share extension, Shortcuts/App Intents, Reminders support, paste flow |
| Store integrations unavailable or ToS-restricted | Automation vision delayed | Start with deep links/handoff; pursue partner APIs; keep planning valuable standalone |
| LLM mistakes on allergies/medical diets | Safety, liability | Deterministic validators, confirm-before-use for extracted guidance, disclaimers |
| Pantry upkeep fatigue | Inaccurate inventory → bad plans | Make capture nearly free (photo/receipt/voice), auto-deduct, "confidence" decay on stale items |
| Cultural/regional recipe coverage | Irrelevant suggestions | Seed with household's own dishes; user-added recipes; regional launch focus |
| LLM cost at scale | Margin pressure | On-device OCR/ASR, caching, structured prompts, smaller models for routine tasks |
| Privacy concerns around health/child data | Trust, regulatory | On-device-first, minimal retention, transparent controls |

## 15. Roadmap (Indicative)

| Phase | Scope | Outcome |
|---|---|---|
| **0 – Discovery** (4–6 wks) | 15–20 household interviews; prototype planner in a script/notebook; validate Notes/Shortcuts import flow; assess store API landscape for 1 target region | Validated persona, feasibility of inputs and integrations |
| **1 – MVP** (3 mo) | Household profile, weekly planner with school-lunch slot, pantry (manual + voice + photo), shopping list, Notes share-extension import, guidance import (photo/PDF/text) | TestFlight beta with ~50 households |
| **2 – Launch** (2 mo) | iPad layouts, CloudKit family sharing, widgets, notifications, ratings loop, subscription | App Store release |
| **3 – Smart Kitchen** | Receipt scan, expiry tracking, leftovers, cooking mode, nutrition insights | Retention and daily-habit features |
| **4 – Shopping Automation** | Add-to-cart for 1–2 stores → auto-order with safeguards | Closed-loop "off my plate" |

## 16. Open Questions

1. Which **region/cuisines** to launch with first? (Drives datasets, stores, and recipe corpus.)
2. Which **store(s)** are the priority integration targets, and what access paths exist for each?
3. Should shopping-list sync prefer **Reminders** (full API) over Notes, with Notes as import-only?
4. How much processing can run **fully on-device** (Apple Foundation Models / Core ML) versus requiring a backend LLM?
5. Do we pursue a **professional (nutritionist/coach) channel** early, or stay consumer-only for v1?
6. Pricing: per-household flat subscription vs. per-member tiers?
7. What is the minimum viable **nutrition accuracy** for credibility with health-guided users, and do we need a registered-dietitian advisor?

## 17. Summary

OffMyPlate is a household-aware, pantry-aware, guidance-aware meal planner for iPhone and iPad, driven by the easiest possible inputs — notes, camera, and voice — and ultimately connected to grocery carts. The MVP proves the planning loop (plan → list → cook → pantry update); shopping automation follows once planning is trusted and integration paths are secured.
