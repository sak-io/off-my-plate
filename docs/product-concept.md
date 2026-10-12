# OffMyPlate — Product Concept

**Status:** Draft v0.2 · **Date:** 2026-10-12 · **Platforms:** iPhone, iPad (iOS/iPadOS)

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
5. **Closes the loop** — plan → shopping list → cart (later: assisted ordering, always with explicit approval).
6. **Understands without being told** — light start, learns quietly from behaviour, never demands a profile.
7. **You stay in control** — safety is confirmed up front, and every meal plan and every order needs your explicit approval.

### 4.1 Experience Principles: Light Start, Slow Learning

Most apps lose users at onboarding: a long form asks people to describe their household before the app has given them anything. Putting thoughts into words is hard work, and people rarely know in advance what they will want ("we eat everything", "it depends on the week"). OffMyPlate should instead behave like a thoughtful helper who notices.

1. **Value before questions.** The first plan appears within a minute, from at most 2–3 questions. Everything else is optional or learned.
2. **Learn from behaviour, not forms.** Swaps, skips, "cooked it", re-rolls, ratings, Notes lists, receipts and pantry photos teach the app more than any questionnaire. A swapped-out Wednesday dinner is a signal; no one had to explain it.
3. **Optional detail, always available.** A "Tell me more" area lets people add specifics (nutritionist plans, goals, house rules) in their own words, by voice, or by photo. Nothing is blocked behind it, and it can be done at any time. The one exception is the safety check (principle 8).
4. **Free-form, not form-shaped.** People can say things the way they think them ("the kids have been picky about veg lately", "we're trying to eat lighter this month"). The app turns that into structure; the user never has to.
5. **Show understanding, invite correction.** The app reflects what it has picked up in plain language ("Looks like you usually skip fish on weekdays. Right?"), with one-tap confirm, fix or dismiss. It never nags or interrogates.
6. **Ask at the moment of relevance.** Apart from the safety check, a question appears only when the answer changes something the user is looking at, one question at a time, always skippable.
7. **Sensible defaults, quiet confidence.** Where the app is guessing about tastes, it uses sensible defaults and says so lightly, instead of asking up front.
8. **Safety is confirmed, never guessed and never skippable.** Allergies and medical or religious restrictions can't be inferred, so the app asks once, in one light screen, before it makes any plan. "No, nobody has any" is a valid one-tap answer, but an answer is required. Learned patterns only ever influence *preferences*; the user's stated answer is the only source of truth for safety.
9. **Nothing happens without your say-so.** The app drafts; you decide. Every meal plan and every order requires explicit human approval. Models, learning and automations can propose but can never approve or place anything.

## 5. Inputs the Planner Understands

| Input | Examples | Capture method |
|---|---|---|
| **Household profile** | Members, ages, kids needing school lunch, who's home on which days | 2–3 starter questions; the rest is inferred or added any time by choice |
| **Eating habits** | Cuisines, usual dishes, spice level, cook time budget, appliances available | Learned from swaps, cooked meals, ratings, lists and receipts; optional "tell me more" |
| **Dietary restrictions** | Vegetarian, halal, allergies, diabetic, low-sodium, religious fasting days | One mandatory, one-tap-light safety screen before the first plan ("No restrictions" is a valid answer); re-checked when a member is added; refined only when the user chooses; never inferred |
| **Professional guidance** | Nutritionist plan, gym coach macros, doctor's advice | Upload PDF / photo / paste text / dictate; parsed into structured rules |
| **Pantry & fridge inventory** | Items, quantity, expiry | Photo scan, voice, receipt scan, manual, auto-deduct after cooking |
| **Last shopping list / purchases** | What was bought recently | Apple Notes import, receipt scan, order history (later) |
| **Custom advice** | "Dad avoids dairy at night", "Fish only on Fridays", "Kids hate gourds" | Free text/voice; stored as persistent rules |
| **Context** | Budget, guests, travel, festivals, weather, time available this week | Quick prompts / calendar (opt-in) |

## 6. Key Features

### 6.1 MVP (v1)

**Onboarding (lightweight by design)**
- **Three quick questions to a first draft plan.** Starter questions: how many people eat (adults / kids); any allergies or foods that must be avoided (the one required screen: "No, nobody" is a single tap, or the user adds items with chips, text or voice); and the kind of food you usually cook (pick a few cuisines, or skip).
- No account wall, no long profile, no goals or appliance quiz up front. The first weekly plan is generated with sensible defaults, shown as a **draft** labelled as a starting point, and used only once the user approves it.
- **Progressive profile.** Details such as which kids need school lunch, who is on a gym or nutritionist plan, and who is home on which days are asked later, in context, one at a time ("Do any of the kids take lunch to school?" appears when the user opens the lunch slot).
- **"Tell me more" (optional, always available).** One place to add anything specific: type, speak or photograph it ("Dad is diabetic", "Meera has a nut allergy", a nutritionist's chart). It is never required and can be revisited or edited at any time.
- **Learning in the background.** The app picks up habits from swaps, skips, "cooked it" taps, pantry photos, receipts and Notes lists, and occasionally reflects them back for one-tap confirmation (see §4.1).
- **Safety confirmed, not guessed.** Allergies can't be inferred, so the safety screen cannot be skipped or dismissed and no plan is produced until it is answered. It is asked again for any member added later (and re-confirmed periodically, see open questions). Everything else in the profile stays optional.

**Meal planning**
- Weekly plan (breakfast, lunch, dinner, snacks, **school lunchbox** as a distinct slot).
- Per-member variations on a shared base meal (e.g., same dal, plus extra protein for the gym-goer, soft version for the toddler).
- Swap, lock, or regenerate any meal; "I don't feel like this" re-roll with a reason.
- "Cook what I have" mode: suggests meals from current pantry, prioritising items nearing expiry.
- Rules honoured as hard constraints (allergies, medical) vs. soft preferences (likes/dislikes).
- **Explicit approval for every plan.** Generated plans are drafts. Nothing downstream (shopping list, reminders, widgets, pantry deductions) acts on a plan until the user approves it. One tap approves the whole week; users can review or change individual meals first. Later edits to an approved plan show what changed and ask for approval again. Voice or chat can propose changes but cannot approve them.

**Guidance import**
- Upload or photograph a nutritionist/gym plan; the app extracts targets (calories, macros, meal timings, do/don't foods) and shows them for confirmation before use.

**Pantry**
- Maintain a home inventory via photo scan of fridge/shelf, voice ("I bought 2 kg rice and a dozen eggs"), receipt scan, or manual entry.
- Auto-decrement when a planned meal is marked cooked.

**Shopping list**
- Generated from the *approved* plan's requirements minus pantry, grouped by store aisle/category.
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

- **Phase A — Add-to-cart:** build a cart in supported stores/delivery apps from the shopping list; the user reviews and checks out themselves.
- **Phase B — Assisted ordering:** the app prepares the complete order (items, substitutions, total) and the user explicitly approves each one before it is placed. There are no unattended, scheduled or recurring orders; automation may prepare a cart and notify, but never place an order. Spend caps remain as an extra guard.
- Store connections where the user supplies credentials (see §9 for the security approach and a recommended alternative).
- Product matching: brand preferences, substitutions, pack-size optimisation, price comparison across stores.
- Reconcile delivered items into the pantry automatically.

## 7. Example User Flows

**First launch (under a minute)**
1. "How many people are you cooking for?" → 2 adults, 2 kids.
2. "Does anyone have an allergy or something they must avoid?" → required, but one tap for "No, nobody", or the user says "no beef, one of us can't have nuts".
3. "What do you usually cook?" → picks a couple of cuisines or skips.
4. A draft week appears, marked "A starting point. Swap anything and I'll learn." The user taps **Approve** to start using it.
5. Over the next days, the user swaps a dish and skips another. The app later says: "You tend to prefer quick dinners on weekdays. Should I plan around that?" One tap to confirm.

**Sunday planning (5 minutes)**
1. User says: "Plan the week. Two of us are on a high-protein plan, kids need lunchboxes Mon–Fri, no beef."
2. App checks pantry, last week's list, guidance rules, and favourites.
3. Presents a draft week view; user swaps Wednesday dinner and approves the plan.
4. App produces a shopping list from the approved plan (only the gaps) and offers to push it to Notes or prepare a store cart, which the user approves before anything is ordered.

**Daily "what's for lunch?"**
- Morning notification: today's meals + lunchbox. One tap to mark cooked (deducts pantry) or swap.

**Importing a nutritionist plan**
- Photograph a printed diet chart → app extracts rules → user confirms ("1,800 kcal, 90 g protein, no refined sugar, oats at breakfast") → plan generation uses them going forward.

**After shopping**
- Scan receipt → items added to pantry with estimated expiry → next plan uses them.

## 8. Platform & Technical Considerations (iOS / iPadOS)

Full detail is in [`technical-specification.md`](technical-specification.md). Key product-level decisions:

- **On-device first.** Household, health and pantry data stay on the device and in the user's own iCloud. OffMyPlate runs no AI backend and stores no user data on its servers.
- **OffMyPlate does not provide an LLM.** Intelligence comes from Apple's on-device models, plus an *optional* user-supplied API key (Gemini, OpenAI or Anthropic) for heavier tasks. The app must be fully useful with neither. Consumer chatbot subscriptions don't include API access, so "bring your own key" is a power-user feature, not the default.
- **Deterministic core, probabilistic edges.** Planning, allergen checks, nutrition maths and pantry/shopping arithmetic are ordinary code. Models only interpret messy input (photos, documents, voice, free text), phrase explanations and chat, and can only choose among options the rules have already approved.
- **Human approval for anything that matters.** Plans are drafts until the user approves them, and orders are placed only after explicit approval of that specific order. Models can propose but never approve.
- **Graceful degradation.** Every feature has a non-AI fallback (forms, templates, manual entry) for older devices and offline use.
- **A curated recipe library is a core asset**, because no hosted model invents dishes (see below).

| Capability | Approach | Notes / constraints |
|---|---|---|
| **UI** | SwiftUI, universal app with adaptive layouts (iPhone compact, iPad split-view/Stage Manager) | iPad gets a dedicated kitchen/planning layout |
| **Apple Notes** | Notes has **no public read API**. Options: Share Sheet extension ("Send to OffMyPlate" from a note), App Intents / Shortcuts action, copy-paste, or the user exporting the note text. | Direct background reading of Notes is not available; design around share-extension + Shortcuts. Consider Apple **Reminders (EventKit)** as a fully supported alternative for shopping lists. |
| **Camera scanning** | VisionKit `DataScannerViewController` + Vision text recognition (on-device OCR); barcode scanning for packaged goods | On-device first for privacy and speed |
| **Image understanding** (fridge photos, handwritten lists, diet-plan PDFs) | On-device OCR first; on-device model where capable; optional user-supplied model key for long or complex documents and vision | Confirm-before-save UI for every extraction; documents stay on-device unless the user opts in per task |
| **Voice** | Speech framework / on-device dictation for transcription; on-device model for intent parsing (command grammar as fallback); optional spoken replies (AVSpeechSynthesizer) | Hands-free mode important in the kitchen |
| **Planning engine** | Deterministic constraint filter and scoring over a curated recipe library (hard rules: allergies, macros, inventory), with an independent validator before display | A model, if available, only re-ranks validated options, explains the plan and handles chat; it never bypasses the validators |
| **Household knowledge** | A set of learned and stated facts, each with its source and confidence, viewable and editable in plain language | Learned preferences are soft only; safety rules come solely from what the user states or confirms |
| **Data & sync** | On-device store (SwiftData/Core Data) + CloudKit for household sync across family devices | Shared household via CloudKit sharing |
| **Backend** | None in v1. Recipe content ships as signed content packs. A minimal backend may be introduced later only if store connectors need it (OAuth callbacks, scheduled orders), kept free of user health data | Keeps cost, privacy and compliance surface small |
| **AI model management** | Router picks Apple on-device or a user-supplied key per task; key kept in the iOS Keychain and used only for direct device-to-provider calls; per-task opt-in for anything leaving the device; child names redacted | Every supported model is tested against an internal evaluation set before it is enabled |
| **Notifications & surfaces** | Local notifications, widgets, Live Activities, App Shortcuts/Siri | |
| **Recipes & nutrition** | Bundled curated library (target roughly 500–800 recipes for the launch cuisine, with a school-lunch subset), user-added recipes (URL, photo, manual), nutrition computed from ingredients using open or licensed data (e.g., USDA FoodData Central plus regional datasets) | Regional coverage and licensing matter; imported recipes stay "unverified" until ingredients are resolved |

## 9. Store Integration & Credentials — Approach

The "give us your store credentials" model is the highest-risk part of the product.

- **Reality check:** most grocery retailers have no public consumer-facing ordering API. Storing user passwords and automating logins (screen-scraping) is fragile, often violates store ToS, can trigger fraud/2FA lockouts, and creates serious liability.
- **Preferred order of approach:**
  1. **Official partner APIs / affiliate programs** where available (OAuth-based, no password handling).
  2. **Deep links / share handoff** — open the store app with items pre-filled, or generate a cart link.
  3. **On-device automation via the user's own session** (e.g., in-app web view where the user logs in themselves; credentials never leave the device and are stored only in iOS Keychain).
  4. Server-side stored credentials only as a last resort, encrypted, with explicit consent — and likely avoided entirely.
- **Safety rails for ordering:** every order requires explicit approval of the final cart (items, substitutions, total), ideally authenticated with Face ID; no unattended or recurring orders; spend caps, substitution rules, easy cancel window, full audit log.
- **Launch strategy:** begin with 1–2 stores in a single region with the best integration path; treat "add to cart" as the v1 automation milestone.

## 10. Privacy, Safety & Trust

- Health and dietary data is sensitive: on-device storage by default, encrypted CloudKit sync, clear data-deletion controls, App Store privacy labels kept accurate.
- Allergen safety: hard constraints are enforced by a deterministic checker, not left to any model; unresolved or unverified ingredients are flagged and excluded for affected members. Persistent disclaimer that the app does not replace medical advice.
- Inference never touches safety: learned patterns only adjust soft preferences. Allergies, medical and religious restrictions exist only if the user stated or confirmed them, and the safety screen is mandatory: no plan is generated until it has been answered ("no restrictions" counts as an answer).
- Human in the loop: every meal plan and every order needs explicit user approval; the app, a model or an automation can never approve on the user's behalf.
- No hosted AI: OffMyPlate holds no user data on its own servers. If the user adds their own API key, it stays in the Keychain, calls go straight from the device to the provider, and each task that sends data off the device needs explicit opt-in.
- Professional guidance is treated as authoritative input; the app never overrides it and surfaces conflicts ("Plan says no dairy; this recipe contains paneer — replaced").
- Child profiles: minimal data, parent-managed only, COPPA/GDPR-K aware.
- AI transparency: clear indication when content is AI-generated; user can inspect why a meal was chosen ("uses your spinach expiring Thursday; fits Dad's 90 g protein target").
- Credentials (API keys, and store logins if ever collected) live only in Keychain / secure enclave-backed storage.
- Learning is transparent and reversible: a plain-language "What I've learned" screen lets users see, correct or forget anything the app has picked up; all learning runs on-device.

## 11. Differentiators vs. Existing Apps

| Existing approach | Gap | OffMyPlate |
|---|---|---|
| Recipe apps (Yummly, Tasty) | Recipe-first, ignore household and pantry | Household-first planning |
| Meal-plan subscriptions (eMeals, Mealime) | Generic templates, limited personalisation, minimal pantry awareness | Learns what *this* family eats, uses real pantry state |
| Nutrition trackers (MyFitnessPal) | Log after eating; don't plan for a family | Plans ahead for everyone, with per-person targets |
| Grocery list apps | Lists unconnected to meals | Lists derived from plan minus pantry |
| Smart-fridge ecosystems | Hardware lock-in | Works with a phone camera and voice |

**Moat over time:** the accumulated household taste/pantry model, a curated recipe library, parsed professional guidance, a privacy-first on-device design that needs no AI backend, and store connections.

## 12. Monetisation (Hypotheses)

- **Freemium:** free tier — 1 week plan, basic list; **Premium subscription** (household plan) — unlimited planning, multi-member guidance, pantry scanning, family sharing, nutrition insights.
- **No AI cost to recover.** Because the app uses on-device models and an optional user-supplied key, there is no per-request model bill, which keeps margins healthy at any scale. The premium tier is justified by features, content (recipe packs, regional cuisines) and family sharing instead.
- **Affiliate / delivery referral fees** from store cart handoff (disclosed clearly).
- Possible future B2B2C: nutritionists/gym coaches push structured plans straight into clients' apps (pro tier).

## 13. Success Metrics

- **Activation:** % of new users who see a first weekly plan within 2 minutes of install; onboarding completion rate; median number of questions answered (target ≤ 3).
- **Learning quality:** share of inferred preferences confirmed vs. dismissed; reduction in swap rate over the first four weeks.
- **Engagement:** weekly active households; meals marked cooked per week; plans edited vs. accepted as-is.
- **Value:** self-reported time saved; reduction in food waste (pantry items expiring unused); takeout-substitution rate.
- **Quality:** meal rating average; swap/re-roll rate; allergen-violation rate (target: zero).
- **Retention:** week-4 and week-12 household retention; paid conversion.
- **Automation (later):** % of shopping lists converted to carts; cart-to-checkout completion.

## 14. Risks & Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Onboarding drop-off (long forms before value) | Users never reach the first plan | Three-question start, value first, everything else optional and contextual (§4.1) |
| Approval fatigue | Users rubber-stamp plans, or friction hurts adoption | One-tap approval of the whole week with optional per-meal review; show only what changed when re-approving |
| Mandatory safety screen feels like friction | Drop-off at the first step | Single screen, one-tap "No, nobody" answer, plain-language reason for asking |
| Wrong inferences feel creepy or inaccurate | Loss of trust | Learn only soft preferences, show what was learned in plain language, one-tap correct or forget, never infer safety-critical rules |
| Apple Notes has no read API | Core input broken | Share extension, Shortcuts/App Intents, Reminders support, paste flow |
| Store integrations unavailable or ToS-restricted | Automation vision delayed | Start with deep links/handoff; pursue partner APIs; keep planning valuable standalone |
| Model mistakes on allergies/medical diets | Safety, liability | Deterministic validators, confirm-before-use for extracted guidance, safety rules never inferred, disclaimers |
| On-device models are small and unavailable on older devices | Weaker document and photo understanding; some users get no assistant | Deterministic core carries planning; non-AI fallbacks for every feature; optional user-supplied key for heavy tasks; clear minimum-device messaging |
| Users won't have or want an API key | Optional upgrade path goes unused | Treat it as a power-user extra; baseline experience must stand on its own |
| Pantry upkeep fatigue | Inaccurate inventory → bad plans | Make capture nearly free (photo/receipt/voice), auto-deduct, "confidence" decay on stale items |
| Cultural/regional recipe coverage | Irrelevant suggestions | Seed with household's own dishes; user-added recipes; regional launch focus |
| Recipe library is the content bottleneck | Weak variety or poor regional fit without a generative model | Invest early in a curated, licensed, tagged library; user-added and imported recipes; regional launch focus; content packs as a premium/value driver |
| Privacy concerns around health/child data | Trust, regulatory | On-device-first, minimal retention, transparent controls |

## 15. Roadmap (Indicative)

| Phase | Scope | Outcome |
|---|---|---|
| **0 – Discovery** (4–6 wks) | 15–20 household interviews; prototype planner in a script/notebook; validate Notes/Shortcuts import flow; assess store API landscape for 1 target region | Validated persona, feasibility of inputs and integrations |
| **1 – MVP** (3 mo) | Three-question onboarding with learned preferences, deterministic planner over a seed recipe library, weekly planner with school-lunch slot, pantry (manual + voice + photo), shopping list, Notes share-extension import, guidance import (photo/PDF/text) | TestFlight beta with ~50 households |
| **2 – Launch** (2 mo) | iPad layouts, CloudKit family sharing, widgets, notifications, ratings loop, subscription | App Store release |
| **3 – Smart Kitchen** | Receipt scan, expiry tracking, leftovers, cooking mode, nutrition insights | Retention and daily-habit features |
| **4 – Shopping Automation** | Add-to-cart for 1–2 stores → assisted ordering with per-order approval | Closed-loop "off my plate" |

## 16. Open Questions

1. Which **region/cuisines** to launch with first? (Drives datasets, stores, and recipe corpus.)
2. Which **store(s)** are the priority integration targets, and what access paths exist for each?
3. Should shopping-list sync prefer **Reminders** (full API) over Notes, with Notes as import-only?
4. How far can **on-device models** (Apple Foundation Models / Core ML) go on long, messy documents, and when should a task default to the optional user-supplied key? Which minimum iOS version and devices do we support?
5. Do we pursue a **professional (nutritionist/coach) channel** early, or stay consumer-only for v1?
6. Pricing: per-household flat subscription vs. per-member tiers?
7. Which **recipe and nutrition sources** and licences, and how are content packs distributed and updated?
8. How aggressive should **learning and reflect-back prompts** be before they feel intrusive? (Start conservative; validate in user testing.)
9. What is the wording and cadence of the **safety re-confirmation** (when a member is added, periodically, when a child's age band changes), and should the safety answer be per household or per member?
10. What should the approval UX be for larger plans and for edits after approval, so it protects users without becoming a chore?
11. What is the minimum viable **nutrition accuracy** for credibility with health-guided users, and do we need a registered-dietitian advisor?

## 17. Summary

OffMyPlate is a household-aware, pantry-aware, guidance-aware meal planner for iPhone and iPad, driven by the easiest possible inputs — notes, camera, and voice — and ultimately connected to grocery carts. The app drafts, and the user decides: every meal plan and every order needs explicit approval. It starts in under a minute with three optional questions and then learns quietly from how the household actually eats. It runs on-device with no hosted AI, relying on a deterministic planner, a curated recipe library, Apple's on-device models and, optionally, the user's own API key. The MVP proves the planning loop (plan → list → cook → pantry update); shopping automation follows once planning is trusted and integration paths are secured.
