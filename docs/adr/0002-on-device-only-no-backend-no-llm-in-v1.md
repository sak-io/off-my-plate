# ADR 0002: On-device only; no backend; no model in v1 (non-AI fallbacks)

- **Status:** Accepted (given by owner: tech §1.1, §1.2, §1.5; kickoff #2; spec A7)
- **Date:** 2026-10-12

## Context
The owner's spec says there are no OffMyPlate servers and no hosted LLM, that every feature needs a non-AI fallback, and that safety logic is plain deterministic code. Kickoff #2 deferred BYOK and photo AI. Spec A7 says v1 uses no on-device model at all.

## Decision
- No network code ships in v1. A CI lint fails if `URLSession`, `Network`, `NWConnection` or third-party SDK imports show up in any target (backs AC-13.2).
- The `OMPIntelligence` module from tech §4.1 is **not built in v1**. Each tech §7.2 task that v1 needs gets a protocol named after it, with a rule-based implementation in the pure core:
  `ShoppingTextParsing` (`parseShoppingText`), `SpokenCommandParsing` (`parseSpokenCommand`), `IngredientResolving` (`resolveIngredient`), `PlanExplaining` (`explainPlan`), `SafetyTextParsing` (the §8.5 keyword fallback of `parseFreeform`).
  A future `OMPIntelligence` can wrap these with model-backed versions and keep the rule-based ones as fallbacks.

## Alternatives considered
1. Build `OMPIntelligence` now with only a `NullProvider`. Rejected: it is an empty layer with nothing to test (YAGNI). The protocol seams give the same extension point.
2. Use Apple Foundation Models where available. Rejected for v1 by the owner (A7). It would also make behaviour differ by device.

## Consequences
- The app behaves the same on every iOS 18 device, and the "no network" privacy claim can be tested.
- Parsing quality depends on the grammar and taxonomy synonyms, so golden fixtures matter.
