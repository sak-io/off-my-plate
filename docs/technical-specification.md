# OffMyPlate — Technical Specification

**Status:** Draft v0.1 · **Date:** 2026-10-12 · **Companion to:** [`product-concept.md`](product-concept.md)

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

## 2. Scope and Non-Goals

**In scope (v1):** household profiles, constraint-based meal planning, school-lunch slot, pantry, shopping list, guidance import, Apple Notes import via Share Extension, camera/voice input, iCloud family sync.

**Out of scope for v1:** store carts and auto-ordering (see §14), hosted LLM, Android/web clients, social features, a marketplace for professional plans.

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
Household ──< Rule (household-level custom advice)
Member    ──< Rule (dietary restrictions, allergies, guidance-derived rules)
Member    ──< GuidanceDocument ──< Target (kcal, macros, timings)
Recipe    ──< RecipeIngredient >── Ingredient
Household ──< CookLog (what was cooked/rated)
```

### 5.1 Key Entities

**Member**
- `name`, `ageBand` (infant/toddler/child/teen/adult/senior) or `birthDate`
- `role` flags: `needsSchoolLunch`, `schoolDays`
- `dietType` (omnivore, vegetarian, vegan, pescatarian, …), `religiousRules`
- `allergies: [AllergenTag]` (hard), `intolerances`, `dislikes` (soft)
- `goals` (maintain, lose, gain, athletic), `activeTargetSet`

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
- Date range, slot (breakfast, lunch, dinner, snack, lunchbox), `recipeId`, `locked` flag, per-member `MealServing` (portion size, substitutions, add-ons).

**ShoppingItem**
- Derived from plan − pantry; `ingredientId`, quantity/unit, aisle, `checkedOff`, `origin` (plan / manual / Notes import).

### 5.2 Sync Strategy

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
```

### 6.2 Safety Guarantees

- The hard-rule checker is a separate, exhaustively unit-tested module. A plan is never displayed unless it passes.
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
| `chat` | Conversation + tool calls | Reply + `PlanEdit`/`Intent` ops | On-device or BYOK | Disabled |

### 7.3 Tool Use / Actions

Chat is constrained to a fixed set of tools (typed, validated): `addPantryItem`, `removePantryItem`, `addRule`, `editMeal`, `lockMeal`, `regenerateSlot`, `addToShoppingList`. The model proposes tool calls; the app validates and applies them, showing a confirmation for any rule or health-related change.

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
requirements = Σ over planned meals (ingredient qty × servings, unit-normalised)
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
- Auto-order safeguards: spend caps, confirmation thresholds, substitution rules, order preview, audit log.
- A `ProductMatch` layer mapping canonical ingredients to store SKUs with user brand preferences and pack-size optimisation.
- Because there is no OffMyPlate backend in v1, any connector that needs server-side OAuth callbacks, scheduled orders, or price feeds would require introducing a minimal backend — a deliberate future decision.

## 15. Accessibility & Localisation

- Dynamic Type, VoiceOver labels, sufficient contrast, reduced-motion support; large-type, hands-free **kitchen mode** on iPad.
- Localisation-ready from day one (string catalogs); units (metric/imperial) per user; ingredient synonyms per locale.
- Right-to-left layout support; regional ingredient names in the taxonomy.
- Launch language: English; cuisine packs drive regional rollout.

## 16. Delivery Plan (Engineering)

| Milestone | Deliverables |
|---|---|
| **M0 – Spike (3–4 wks)** | Prototype Share Extension from Notes; Foundation Models structured extraction on target hardware; Vision OCR on sample diet plans; measure quality/latency; validate SwiftData + CKShare |
| **M1 – Core (6–8 wks)** | `OMPDomain` (rules, planner, pantry/list math) with safety test suite; data model & persistence; seed recipe pack (small) |
| **M2 – Experience (6–8 wks)** | Household onboarding, planner UI, pantry & list UI, iPad layouts, barcode/OCR capture, Share Extension |
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
