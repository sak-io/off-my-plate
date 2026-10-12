# OffMyPlate — Technical Specification

**Status:** Draft v0.3 · **Date:** 2026-10-12 · **Companion to:** [`product-concept.md`](product-concept.md)

This document describes how OffMyPlate is built. The product vision, personas and roadmap live in the concept document; this one covers architecture, data, components, and engineering decisions.

> **Verification note:** Platform capabilities named below (Foundation Models, VisionKit, App Intents, CloudKit sharing, etc.) evolve with each iOS release. Items marked **[verify]** must be checked against current Apple documentation and the minimum supported OS before implementation.

---

## 1. Design Principles

1. **On-device first.** All household, health, and pantry data lives on the device and in the user's iCloud. There is no OffMyPlate-operated AI backend.
2. **We do not provide an LLM.** Intelligence comes from (a) Apple's on-device models and (b) an optional, user-supplied API key (BYOK). The product must be fully useful with neither.
3. **Deterministic core, probabilistic edges.** Safety-critical logic (allergens, medical rules, macros, pantry math) is ordinary code. Models only parse messy input, rank/reword options, and converse.
4. **Confirm before commit.** Anything a model extracts (diet plans, receipts, fridge photos) is shown to the user for confirmation before it is stored or used.
5. **Graceful degradation.** Every feature has a non-AI fallback (forms, templates, manual entry) so unsupported devices and offline use still work.
6. **Universal app.** One codebase for iPhone and iPad with adaptive layouts.
7. **Light start, slow learning.** Onboarding asks at most three questions (only the safety question is mandatory) and shows a draft plan immediately. Every other profile field is optional with a sensible default. The app learns from behaviour and asks for detail only in context (see §5.2 and §8.5).
8. **Inference never touches safety.** Learned signals feed soft preferences only. Hard rules (allergies, medical, religious) exist only if the user stated or confirmed them. The safety check is mandatory and unskippable: no plan is generated until it has been answered ("no restrictions" is a valid answer).
9. **Human approval gate.** Every meal plan and every order requires explicit user approval. Models, learning, chat tools, schedulers and automations can create drafts and proposals but can never approve a plan or place an order (see §6.4).

## 2. Scope and Non-Goals

**In scope (v1):** household profiles, mandatory safety check, constraint-based meal planning with explicit plan approval, school-lunch slot, pantry, shopping list, guidance import, Apple Notes import via Share Extension, camera/voice input, iCloud family sync.

**Out of scope for v1:** store carts and ordering (see §14), hosted LLM, Android/web clients, social features, a marketplace for professional plans.

## 3. Platform Targets

| Item | Decision |
|---|---|
| Devices | iPhone, iPad (universal) |
| Language / UI | Swift, SwiftUI (UIKit only where SwiftUI lacks capability) |
| Minimum OS | Proposed iOS/iPadOS 18 for core app **[verify]**; on-device assistant requires Apple Intelligence-capable hardware and OS **[verify]** |
| Concurrency | Swift Concurrency (async/await, actors) |
| Persistence | SwiftData (Core Data fallback if SwiftData limits sharing) **[verify]** |
| Sync | CloudKit private + shared databases |
| Build | Xcode, Swift Package Manager for modules |
| Testing | XCTest / Swift Testing, snapshot tests, UI tests |

## 4. High-Level Architecture

```
┌──────────────────────────────── App (SwiftUI) ───────────────────────────────┐
│  Planner UI · Pantry UI · List UI · Capture UI · Chat/Voice UI · Settings     │
└───────────────┬───────────────────────────────────────────────┬───────────────┘
                │                                               │
        ┌───────▼────────┐                              ┌───────▼────────┐
        │  Application   │                              │  Intelligence  │
        │  Services      │◄────── structured I/O ──────►│  Layer         │
        │ (use cases)    │                              │ (model router) │
        └───────┬────────┘                              └───────┬────────┘
                │                                               │
   ┌────────────▼─────────────┐                  ┌──────────────▼───────────────┐
   │ Domain Core (pure Swift) │                  │ Providers                    │
   │ • Constraint engine      │                  │ • AppleOnDeviceProvider      │
   │ • Planner                │                  │ • BYOKProvider (Gemini/      │
   │ • Pantry/Shopping math   │                  │   OpenAI/Anthropic)          │
   │ • Nutrition calculator   │                  │ • NullProvider (no model)    │
   └────────────┬─────────────┘                  └──────────────────────────────┘
                │
   ┌────────────▼─────────────┐     ┌─────────────────────┐   ┌──────────────────┐
   │ Persistence (SwiftData)  │◄───►│ CloudKit sync/share │   │ Keychain (keys)  │
   └──────────────────────────┘     └─────────────────────┘   └──────────────────┘

 Extensions: Share Extension · App Intents/Shortcuts · Widgets · Live Activities
```

### 4.1 Module Layout (Swift packages)

| Module | Responsibility | Depends on |
|---|---|---|
| `OMPDomain` | Entities, value types, constraint engine, planner, nutrition & pantry math. No UI, no I/O. | — |
| `OMPData` | SwiftData models, repositories, CloudKit sync, migrations | `OMPDomain` |
| `OMPIntelligence` | `ModelProvider` protocol, providers, prompt templates, JSON schemas, validators | `OMPDomain` |
| `OMPCapture` | Camera/OCR/barcode/receipt scanning, speech capture, Notes/text import parsing | `OMPIntelligence`, `OMPDomain` |
| `OMPRecipes` | Bundled recipe library, ingredient taxonomy, nutrition tables, search/index | `OMPDomain` |
| `OMPUI` | Shared SwiftUI components, design system, adaptive layouts | — |
| `OMPApp` | App target, composition root, navigation | all |
| `OMPShareExtension`, `OMPWidgets`, `OMPIntents` | System extension targets | `OMPData`, `OMPCapture` |

Keeping `OMPDomain` free of Apple frameworks makes the safety-critical logic fast to test and portable.

## 5. Data Model

Core entities (simplified; all have `id`, `createdAt`, `updatedAt`, soft-delete flag for sync):

```
Household ──< Member
Household ──< PantryItem
Household ──< ShoppingList ──< ShoppingItem
Household ──< MealPlan ──< PlannedMeal ──< MealServing (per Member variation)
MealPlan  ──< PlanApproval (who, when, content hash)
ShoppingList ──< Order ──< OrderApproval (who, when, content hash, total)
Household ──< Rule (household-level custom advice)
Member    ──< Rule (dietary restrictions, allergies, guidance-derived rules)
Member    ──< GuidanceDocument ──< Target (kcal, macros, timings)
Recipe    ──< RecipeIngredient >── Ingredient
Household ──< CookLog (what was cooked/rated)
```

### 5.1 Key Entities

**Member** (every field except the member's existence and `safetyStatus` is optional; a Member can start as just "Adult 1" or "Child 1")
- `name?`, `ageBand?` (infant/toddler/child/teen/adult/senior) or `birthDate?`
- `role` flags: `needsSchoolLunch?`, `schoolDays?`
- `dietType?` (omnivore, vegetarian, vegan, pescatarian, …), `religiousRules?`
- `allergies: [AllergenTag]?` (hard), `intolerances?`, `dislikes?` (soft)
- `goals?` (maintain, lose, gain, athletic), `activeTargetSet?`
- `safetyStatus`: `unasked` | `confirmedNone` | `stated` — whether allergies/restrictions have been addressed for this member. There is no `skipped` state. While any member is `unasked`, plan generation is blocked (§6.4). A new member starts `unasked`. `confirmedAt` is stored so periodic re-confirmation can be scheduled. The status syncs with the household, so an unasked member blocks planning on every device.

**Rule** (unified constraint representation)
- `scope`: household | member
- `kind`: `hard` (never violate) | `soft` (prefer) 
- `source`: user | guidance(documentId) | system
- `predicate`: structured, e.g. `excludeAllergen(dairy)`, `maxPerDay(sodiumMg, 1500)`, `requirePerMeal(proteinG, ≥ 30)`, `onlyOnDays(fish, [Fri])`, `timeWindow(dairy, before: 18:00)`
- `explanation`: human-readable text shown in UI

**Ingredient / Recipe**
- Ingredients carry canonical id, `allergenTags`, `dietTags`, category/aisle, units + density conversions, nutrition per 100 g.
- Recipes carry servings, prep/cook time, equipment, cuisine, meal types, steps, `RecipeIngredient` list with normalized quantities, and a computed nutrition summary.

**PantryItem**
- `ingredientId` (or free-text until resolved), `quantity`, `unit`, `location` (fridge/freezer/shelf), `purchasedAt`, `expiresAt?`, `confidence` (decays over time unless re-confirmed), `source` (manual/voice/photo/receipt/cooked-deduct).

**MealPlan / PlannedMeal**
- Date range, `status` (`draft` | `approved` | `superseded` | `discarded`), slot (breakfast, lunch, dinner, snack, lunchbox), `recipeId`, `locked` flag, per-member `MealServing` (portion size, substitutions, add-ons). Approval details are in §6.4.

**ShoppingItem**
- Derived from plan − pantry; `ingredientId`, quantity/unit, aisle, `checkedOff`, `origin` (plan / manual / Notes import).

### 5.2 Household Knowledge Model (what the app knows and how well)

Instead of a form-shaped profile, the app keeps a set of **Facts** about the household, each with provenance and confidence. The planner reads Facts; the UI shows and edits them in plain language.

```
Fact {
  subject:     household | member(id) | recipe(id) | ingredient(id)
  statement:   structured, e.g. dislikes(ingredient: okra), prefers(quickMeals, weekdays),
               usuallySkips(fish, weekdays), cuisineAffinity(southIndian, 0.8)
  origin:      stated (user said/typed/spoke it) | confirmed (inferred, user approved)
               | inferred (observed from behaviour) | default (app assumption)
  confidence:  0…1 (inferred facts only; decays without reinforcement)
  evidence:    [events] (swaps, skips, ratings, cooked logs, list/receipt items)
  status:      active | proposed | dismissed | forgotten
  updatedAt
}
```

Rules:
- `stated` and `confirmed` facts are authoritative; `inferred` facts act as weak, decaying weights; `default` facts are replaced the moment better information exists.
- **Only soft facts can be `inferred`.** Facts that map to `Rule(kind: hard)` (allergens, medical, religious restrictions) are created exclusively from `stated` or `confirmed` origins. A repeated pattern such as "never buys dairy" yields at most a soft suggestion, which the user must explicitly confirm to promote.
- A fact reaches `proposed` (shown to the user for one-tap confirm) only after enough independent evidence, with a cap on proposals per week to avoid nagging.
- Every fact is viewable, editable and deletable in a plain-language "What I've learned" screen. "Forget" removes the fact and its evidence weight.
- All learning runs on-device, from the local event log; nothing is uploaded.

### 5.3 Sync Strategy

- Per-user data in the CloudKit private database; a household shared with family via **CKShare** so all members edit one `Household` record graph **[verify SwiftData + CKShare support]**.
- Conflict policy: field-level last-writer-wins for scalars; set-merge for tags; checked-off shopping items merge by "checked wins".
- Guidance documents (health data) stay in the private zone of the member who imported them unless that member explicitly shares.
- Offline-first: all reads/writes local; sync is opportunistic.

## 6. Planning Engine

The planner is deterministic and explainable. The model is optional and only decorates.

### 6.1 Pipeline

```
1. Gather      household, members, rules, pantry, recent CookLog, calendar slots
2. Expand      slots needing meals (incl. lunchbox for flagged members/days)
3. Filter      candidate recipes = library ∪ user recipes
               → drop any recipe violating a HARD rule for ANY eater of that slot
               → drop recently cooked (variety window) unless favourite
4. Score       weighted sum of soft rules:
               + pantry coverage (esp. items near expiry)
               + cuisine/habit affinity (from ratings & CookLog)
               + time fits (weekday vs weekend budget)
               + nutrition fit vs targets (rolling day/week)
               + variety (protein/cuisine diversity)
               − cost (if budget set)
5. Select      constrained selection per slot (greedy + local search / small ILP
               over the week for nutrition and variety)
6. Personalise per-member servings & variations (portion scaling, swaps/add-ons)
7. Validate    re-run hard-rule checker on final plan (independent code path)
8. Explain     reasons attached to each meal ("uses spinach expiring Thu;
               meets Dad's 90 g protein")
9. Persist     saved as a DRAFT; nothing downstream acts on it until approved (§6.4)
```

### 6.2 Safety Guarantees

- The hard-rule checker is a separate, exhaustively unit-tested module. A plan is never displayed unless it passes, and it runs again at approval time.
- **Safety gate:** the planner refuses to run while any member's `safetyStatus` is `unasked`. This is enforced in the domain layer (not just the UI), with tests that fail the build if any code path can generate a plan past the gate.
- Ingredient allergen detection uses structured tags, not text matching. Free-text or unresolved ingredients are flagged **"unverified"** and excluded from allergic members' meals by default.
- Packaged-food barcodes resolve to ingredient/allergen data where available; otherwise flagged as unverified.
- Persistent, non-dismissable disclaimer that the app does not provide medical advice.

### 6.3 Where a model is used (all optional)

| Task | Without model | With model |
|---|---|---|
| Rank/choose among valid candidates | Weighted scoring (default) | Re-rank for variety/tone — can only choose from the validated set |
| Explain the plan | Template strings from score components | Natural-language phrasing of the same reasons |
| Interpret "make it lighter on Thursday" | Structured controls (filters, sliders) | Chat → structured `PlanEdit` operations, then validated |
| Invent a new dish | Not supported (library + user recipes only) | Suggest a recipe draft, tagged `unverified` until ingredients are resolved and nutrition computed |

### 6.4 Approval Gate (plans and orders)

**Plan lifecycle:** `draft` → `approved` → `superseded` (or `discarded`).

- The planner and all model-assisted flows (chat edits, voice, regenerate, "cook what I have") only ever create or modify **drafts**.
- Only an explicit, user-initiated action in the app (an Approve control) moves a plan to `approved`. Chat tools, App Intents, Shortcuts, widgets, notifications and background tasks cannot approve. A spoken or typed "looks good" is treated as a proposal to approve and still needs a confirming tap.
- Until a plan is `approved`: no shopping list is generated from it, no reminders, Live Activities or widgets are scheduled for it, and no pantry deductions occur.
- Editing an approved plan creates a draft revision. The approval sheet shows a diff (what changed) and the validator re-runs before the user can re-approve; unchanged meals stay approved.
- Approval stores who approved, when, and a hash of the plan content, so any later change invalidates it.
- UX: one tap approves the whole week; per-meal review is optional but always available.

**Order lifecycle:** `proposed` → `approved` → `placed` → `delivered` (or `cancelled`/`failed`).

- A cart/order is derived from an approved shopping list and is always created as `proposed`.
- Placing it requires explicit approval of that specific order after the user sees the final items, substitutions and total, authenticated with Face ID/Touch ID (`LocalAuthentication`) where available.
- Approval is bound to the exact contents and total; if anything changes (price, substitution, quantity), the approval is void and must be repeated.
- No unattended, scheduled or recurring order placement. Schedulers may prepare a `proposed` order and notify the user; they can never advance it to `approved`.
- Spend caps and substitution rules are additional guards, not a replacement for approval. Every state transition is recorded in an audit log.


## 7. Intelligence Layer

### 7.1 Provider Abstraction

```swift
protocol ModelProvider {
    var capabilities: ModelCapabilities { get }   // text, vision, longContext, toolUse, structuredOutput
    func generate<T: Decodable>(_ request: ModelRequest<T>) async throws -> T
}
```

- Every call specifies a **JSON schema / Swift type** for the response. Free-form text is only used for explanations and chat replies.
- Providers: `AppleOnDeviceProvider` (Foundation Models, guided generation **[verify]**), `BYOKProvider` (Gemini, OpenAI, Anthropic adapters), `NullProvider` (returns `.unavailable`, triggering fallbacks).
- A **Router** selects the provider per task based on required capabilities, input size, user setting, and availability (device support, network, key presence, rate limit).

### 7.2 Task Catalogue

| Task | Input | Output (schema) | Preferred | Fallback |
|---|---|---|---|---|
| `parseShoppingText` | Text from Notes/paste/voice | `[{name, qty, unit}]` | On-device | Rule-based tokenizer |
| `parseSpokenCommand` | Transcript | `Intent` (add pantry, edit plan, add rule, …) | On-device | Command grammar + forms |
| `extractGuidance` | OCR text / PDF text / image | `GuidanceDraft {targets, rules, foods, timings}` | BYOK if long/complex, else on-device | Manual entry wizard |
| `recognizePantry` | Fridge/shelf photo | `[{ingredient, confidence}]` | BYOK vision, or on-device vision classifier **[verify]** | Barcode scan / manual |
| `parseReceipt` | OCR text | `[{item, qty, price}]` | On-device + store-specific heuristics | Manual |
| `resolveIngredient` | Free-text name | Canonical ingredient id candidates | On-device embedding/fuzzy match | Search picker |
| `explainPlan` | Plan + score components | Short text | On-device | Template strings |
| `parseFreeform` | Free-text/voice remark ("kids are picky about veg lately") | Candidate `Fact`/`Rule` list with origin=stated, shown for confirmation | On-device | Keyword matcher + chip editor |
| `chat` | Conversation + tool calls | Reply + `PlanEdit`/`Intent` ops | On-device or BYOK | Disabled |

### 7.3 Tool Use / Actions

Chat is constrained to a fixed set of tools (typed, validated): `addPantryItem`, `removePantryItem`, `addRule`, `editMeal`, `lockMeal`, `regenerateSlot`, `addToShoppingList`. Tools can only create or modify drafts and proposals; none can approve a plan or place an order (§6.4). The model proposes tool calls; the app validates and applies them, showing a confirmation for any rule or health-related change.

### 7.4 BYOK Management

- Supported initially: Google Gemini, OpenAI, Anthropic (user pastes API key).
- Key stored in **Keychain** (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`; not synced via iCloud Keychain by default), used only for direct device→provider calls. Never sent to or logged by OffMyPlate.
- Settings show: provider, model choice (from an allow-listed, tested set), a connectivity test, estimated usage, and a "what is sent" explainer.
- Per-task opt-in: user chooses which tasks may leave the device (e.g., allow vision for fridge scans, keep guidance documents on-device only).
- Redaction: names of children and other PII are replaced with role tokens (`Member A`) before any off-device call where the task allows it.
- **Provider evaluation:** each supported model must pass the internal evaluation suite (§12.3) before being added to the allow-list; the allow-list is shipped in app config and updatable.

### 7.5 Prompt & Schema Management

- Prompts versioned in the repo (`Prompts/<task>/v<N>.md`) with paired JSON schemas and golden test fixtures.
- Strict decoding; on schema failure retry once with a repair prompt, then fall back to non-AI path.
- All model output passes through domain validators (units parseable, quantities in plausible ranges, ingredient ids exist) before reaching the UI.

## 8. Capture Pipelines

### 8.1 Apple Notes / Text Import

Notes has no public read API **[verify]**. Supported paths:

1. **Share Extension** — user shares a note (or any text/URL/image/PDF) → "OffMyPlate" appears in the Share Sheet → extension parses and shows a review screen → items saved to a shared App Group store and merged by the main app.
2. **App Intents / Shortcuts** — "Add text to OffMyPlate shopping list" action that Shortcuts automations can invoke (e.g., from a Notes share).
3. **Paste / drag-and-drop** on iPad.
4. **Reminders (EventKit)** as a fully supported two-way shopping-list sync alternative.

Export: write the generated list to Reminders, or share as text/Note via the Share Sheet.

### 8.2 Camera

- **VisionKit `DataScannerViewController`** for live text and barcodes **[verify availability per device]**; Vision `VNRecognizeTextRequest` for still-image OCR.
- **Document scanning** (`VNDocumentCameraViewController`) for diet plans and receipts, with perspective correction.
- Barcode → product lookup via an open food database (e.g., Open Food Facts) and bundled cache; offline-tolerant.
- Fridge/shelf photos → `recognizePantry` (see §7.2); results presented as editable chips with confidence.

### 8.3 Voice

- `SpeechAnalyzer`/`SFSpeechRecognizer` with on-device recognition where supported **[verify]**; push-to-talk and a hands-free kitchen mode on iPad.
- Transcript → `parseSpokenCommand` → `Intent` → confirmation card → apply.
- Optional spoken replies via `AVSpeechSynthesizer`.

### 8.4 Guidance Document Import

```
Photo / PDF / pasted text
  → OCR / PDF text extraction (on-device)
  → extractGuidance (model, or manual wizard if no model)
  → GuidanceDraft review screen (every target/rule editable, source snippet shown)
  → user confirms → stored as Rules + Targets with source=guidance(docId)
```

The original document stays on-device (optionally in the member's private iCloud zone) and is never uploaded unless the user has enabled off-device processing for that task.

### 8.5 Onboarding & Progressive Learning

**Goal:** time to first draft plan under one minute; at most three questions; only the safety question (and household size, which is prefilled) is mandatory.

**Starter flow (household size and the safety question are required; cuisines are optional)**
1. *Who's eating?* Counts of adults and children (stepper, prefilled with a default). No names or ages required. Creates Members with `safetyStatus = unasked`.
2. *Does anyone have an allergy or something they must avoid?* **Required.** A prominent "No, nobody" button (one tap) sets `confirmedNone` on all current members; otherwise chips for common allergens/restrictions plus free-text/voice ("no beef", "one of us can't have nuts"), parsed via `parseSpokenCommand`/`parseFreeform` into candidate hard rules shown back for confirmation, then `stated`. There is no skip or dismiss control, and the planner is blocked until this is answered. The screen explains in one plain sentence why it is asked.
3. *What do you usually cook?* Cuisine chips, multi-select, optional.

The planner then produces a **draft** using defaults for everything else; nothing is acted on until the user approves it (§6.4). The safety question is asked again for any member added later, and re-confirmed periodically (cadence to be decided, see §17) and when a child's age band changes. These safety prompts are exempt from the prompt-scheduler caps below.

**Contextual prompts (the "ask when it matters" queue)**
- A prompt scheduler holds candidate questions, each with a trigger (screen/event), priority, and expiry. Rules: one prompt at a time, never during cooking mode, max N per week (safety prompts excepted), never repeat a dismissed prompt within a cooldown, and skip any whose answer is already inferable with confirmed confidence.
- Examples: opening the lunch slot → "Do any of the kids take lunch to school?"; importing a list full of high-protein items → "Is someone on a protein-focused plan?"; first import of a PDF → guidance review flow.

**Learning signals (implicit)**

| Signal | Learns |
|---|---|
| Swap/skip/re-roll (+ optional one-tap reason chip) | Dislikes, cuisine/protein affinity, time-of-day preferences |
| "Cooked it" and ratings | Favourites, repeat cadence, portion sizes |
| Leftover/uncooked meals | Over-planning, effort tolerance |
| Notes/list imports and receipts | Staple foods, brands, quantities per week |
| Pantry photos | What's usually stocked, spice/staple habits |
| Time between plan and cooking | Weekday vs. weekend effort budget |
| Free-text and voice remarks ("the kids are picky about veg lately") | Soft facts via `parseFreeform`, confirmed in a reflect-back card |

**Reflect-back cards.** Periodically (rate-limited) the app shows one card in natural language: "You usually skip fish on weekdays. Should I plan around that?" with **Yes / Not really / Don't ask again**. Outcomes update the Fact status and suppress re-asking.

**Free-form "Tell me more".** A single entry point accepting text, voice, or photo at any time. The model (or the non-AI fallback, a parser plus a review form) converts input into candidate Facts and Rules and presents them in a confirm sheet. The user never fills a structured form unless they choose the advanced editor.

**Without a model:** implicit learning (event counting, weighted scoring) is plain code and works fully offline. Only free-form interpretation depends on a model; without one it falls back to keyword matching with a confirm sheet, and a simple chip-based editor.

**Instrumentation (on-device, privacy-preserving):** questions shown/answered/skipped, time to first plan, proposals confirmed vs. dismissed. Aggregate, opt-in reporting only.

## 9. Recipe & Nutrition Content

Because no hosted LLM invents dishes, **the recipe library is a core product asset**.

- **Bundled library:** curated, tagged recipes (cuisine, diet, allergens, equipment, time, servings), with structured ingredients and verified nutrition. Initial target: ~500–800 recipes for the launch cuisine(s), school-lunch-suitable subset flagged.
- **Updates:** library delivered as signed content packs (via App Store updates or on-demand resources / CloudKit public database) **[decide]**.
- **User recipes:** manual entry, URL import (schema.org `Recipe` JSON-LD parsing), photo of cookbook page (OCR + parse). Imported recipes are `unverified` until ingredients are resolved.
- **Ingredient taxonomy:** canonical ingredient ids, synonyms/regional names/transliterations, unit conversions and densities, allergen & diet tags.
- **Nutrition data:** open/licensed sources (e.g., USDA FoodData Central, regional composition tables) **[verify licenses]**; recipe nutrition computed from ingredients with cooking-yield factors.
- **Licensing/provenance:** recipe content must be original, licensed, or user-owned; track provenance per recipe.

## 10. Shopping List Generation

```
requirements = Σ over meals in the APPROVED plan (ingredient qty × servings, unit-normalised)
need         = requirements − pantry (respecting expiry & confidence)
list         = merge(need, manual items, staples below threshold)
               → group by aisle → round to pack sizes
```

- Pantry confidence below a threshold produces "check you have…" items rather than silent assumptions.
- After "mark cooked", pantry is decremented by recipe quantities (adjustable).
- After shopping: receipt scan, barcode scan, or "bought everything" bulk-add updates the pantry.

## 11. Security & Privacy

| Area | Requirement |
|---|---|
| Data residency | Local + user's iCloud only; no OffMyPlate servers store user data |
| Encryption | iOS Data Protection on local store; CloudKit encrypts in transit/at rest; consider `encryptedValues` for sensitive CKRecord fields **[verify]** |
| Secrets | API keys and any store credentials only in Keychain, device-only accessibility class |
| Off-device AI calls | Only with explicit per-task opt-in (BYOK); PII redaction; no logging of payloads |
| Children's data | Minimal fields; parent-managed; no analytics identifiers tied to child profiles |
| Analytics | Privacy-preserving, aggregate, opt-in; no health or pantry content |
| Permissions | Camera, microphone, speech recognition, (optional) Reminders & Calendar — requested just-in-time with purpose strings |
| App Store | Accurate privacy nutrition labels; health-adjacent claims avoided in marketing; medical disclaimer in-app |
| Compliance | GDPR/CCPA data export & deletion in-app; COPPA/GDPR-K review for child profiles |

## 12. Quality, Testing & Evaluation

### 12.1 Automated Tests
- **Unit:** constraint engine (property-based tests: no generated plan ever violates a hard rule), unit conversion, pantry math, shopping aggregation, nutrition calc.
- **Integration:** persistence & migrations, sync conflict scenarios, Share Extension → main app handoff.
- **UI:** iPhone + iPad flows, Dynamic Type, VoiceOver, dark mode, Stage Manager/split-view.
- **Snapshot:** key screens across size classes.

### 12.2 Safety Test Suite
A dedicated, non-skippable CI suite: allergen/diet-rule matrix × recipe library × member combinations; fails the build on any violation.

### 12.3 Model Evaluation Harness
- Golden datasets: diet-plan PDFs/photos, handwritten lists, receipts, fridge photos, spoken commands (multiple accents/languages).
- Metrics: extraction field accuracy, schema-valid rate, hallucinated-ingredient rate, latency, on-device memory.
- Run per provider/model and per OS release; gate allow-list entries on thresholds.

### 12.4 Beta
TestFlight cohorts across device generations (with/without Apple Intelligence support) to measure real-world degradation behaviour.

## 13. Performance & Reliability Targets

| Metric | Target |
|---|---|
| Cold start to interactive | < 1.5 s on iPhone 12-class |
| Weekly plan generation (deterministic) | < 2 s |
| Plan with on-device model re-rank/explain | < 8 s, progressive display |
| Barcode/OCR scan to result | < 1 s typical |
| Offline | Planning, pantry, list, cooking mode fully usable offline |
| Crash-free sessions | ≥ 99.5% |
| Local DB size | Bounded; archive CookLog older than 12 months |

## 14. Future: Store Integrations (Design Constraints Now)

Not built in v1, but the architecture reserves space:

- A `StoreConnector` protocol: `searchProduct`, `buildCart(list)`, `checkoutHandoff`, `status`.
- Preference order: official partner API (OAuth) → deep link/share handoff → user-driven in-app web session where credentials stay on-device → (avoid) stored credentials.
- All credentials in Keychain; no server-side credential storage.
- Ordering is human-approved only: each order is a `proposed` cart that the user explicitly approves (Face ID where available) after seeing items, substitutions and total; no unattended or recurring placement (§6.4). Spend caps, substitution rules and an audit log are additional guards.
- A `ProductMatch` layer mapping canonical ingredients to store SKUs with user brand preferences and pack-size optimisation.
- Because there is no OffMyPlate backend in v1, any connector that needs server-side OAuth callbacks, scheduled cart preparation, or price feeds would require introducing a minimal backend (and even then orders stay approval-gated) — a deliberate future decision.

## 15. Accessibility & Localisation

- Dynamic Type, VoiceOver labels, sufficient contrast, reduced-motion support; large-type, hands-free **kitchen mode** on iPad.
- Localisation-ready from day one (string catalogs); units (metric/imperial) per user; ingredient synonyms per locale.
- Right-to-left layout support; regional ingredient names in the taxonomy.
- Launch language: English; cuisine packs drive regional rollout.

## 16. Delivery Plan (Engineering)

| Milestone | Deliverables |
|---|---|
| **M0 – Spike (3–4 wks)** | Prototype Share Extension from Notes; Foundation Models structured extraction on target hardware; Vision OCR on sample diet plans; measure quality/latency; validate SwiftData + CKShare |
| **M1 – Core (6–8 wks)** | `OMPDomain` (rules, planner, safety gate, plan/order approval state machines, pantry/list math) with safety test suite; data model & persistence; seed recipe pack (small) |
| **M2 – Experience (6–8 wks)** | Three-question onboarding with the safety gate, draft/approve plan UI, Fact store and learning signals, reflect-back cards, "What I've learned" screen, planner UI, pantry & list UI, iPad layouts, barcode/OCR capture, Share Extension |
| **M3 – Intelligence (4–6 wks)** | Provider abstraction, Apple on-device provider, voice intents, guidance import with review UI, model evaluation harness |
| **M4 – BYOK & Sync (3–4 wks)** | BYOK providers + settings + redaction; CloudKit family sharing; conflict handling |
| **M5 – Beta/Launch (4–6 wks)** | Widgets, notifications, accessibility pass, content expansion, TestFlight, App Store submission |

Parallel track: recipe & nutrition content production and licensing.

## 17. Open Technical Questions

1. What is the minimum iOS version and device class, and what share of the target market falls below Apple Intelligence support?
2. Does SwiftData + CloudKit sharing meet the household-sharing needs, or should the data layer use Core Data / CKSyncEngine directly?
3. Are on-device models sufficient for `extractGuidance` on long, messy PDFs, or must that task default to BYOK?
4. Which source(s) for recipes and nutrition data, and under what licences?
5. How are recipe content packs distributed and updated (App Store releases, On-Demand Resources, CloudKit public DB)?
6. Is a minimal backend ultimately acceptable (store connectors, content delivery, push), and if so, how is it kept free of user health data?
7. How do we evaluate and communicate quality differences between on-device and BYOK models to users?
8. Regional launch scope: which cuisine/ingredient taxonomy first?
9. What evidence thresholds and weekly caps make inferred suggestions feel perceptive rather than intrusive? (Needs user testing; start conservative.)
10. What are the wording and cadence of safety re-confirmation (member added, periodic, child's age band changes), and is the safety answer per household or per member?
11. What approval UX keeps the gate meaningful without becoming a rubber stamp: whole-week approval, diff-only re-approval, and how to present changes? In a shared household, which members may approve plans and orders?
12. Should reflect-back cards and "What I've learned" be shared across the household, or per member?
