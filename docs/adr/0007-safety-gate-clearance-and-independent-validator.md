# ADR 0007: Safety gate as a clearance token; independent validator module

- **Status:** Accepted (owner: tech §1.8, §6.2; spec US-3, US-4; mechanism by architect)
- **Date:** 2026-10-12

## Context
Tech §6.2 says planning must refuse while any member is `unasked`, that this must be enforced in the domain layer, with tests that fail the build if any path bypasses the gate, and that the hard-rule checker must be a separate module run before display and again at approval. G3 adds a 180-day re-confirmation that blocks new drafts.

## Decision
- `SafetyGate.evaluate(household, now) -> Result<SafetyClearance, GateRefusal>`, where `GateRefusal` is `.safetyUnanswered([MemberID])` or `.reconfirmationDue([MemberID])`.
- `SafetyClearance` has a **file-private initialiser**. It carries an immutable snapshot of members, hard rules and a household fingerprint. Every planner entry point (`generateWeek`, `regenerate`, `reroll`, `alternatives`) takes a clearance and plans **only from its snapshot**, so you can't clear household A and then plan for household B.
- `OMPSafetyCheck.PlanValidator` is a separate target with its own code path. It recomputes each recipe's tags from the raw ingredient lines and the taxonomy (the planner uses a precomputed index), treats `mayContain` as contains, and treats `unverified` ingredients as violating whenever any eater has a hard rule. `OMPServices` calls it directly (it is not injectable) before any draft is returned for display and inside `approve`.
- Build-failing checks: (a) a parameterised test calls every planner entry point with an `unasked` and with an overdue household and expects refusal; (b) `scripts/lint-safety.sh` fails if any `public func` under `Sources/OMPDomain/Planner/` lacks a `SafetyClearance` parameter, or if `SafetyClearance(` appears outside `SafetyGate.swift`; (c) the non-skippable safety suite (plan §8).

## Alternatives considered
1. A boolean check at the top of each planner function. Rejected: one forgotten call means a silent bypass. The token makes a bypass a compile error.
2. Validator sharing the planner's filter function. Rejected: a bug in the shared function would defeat both checks.

## Consequences
- There is a little duplicated logic, and that duplication is deliberate. Tests cross-check that the filter and the validator agree on every seed recipe × restriction.
