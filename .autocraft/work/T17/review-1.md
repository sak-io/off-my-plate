# T17 review, round 1: CHANGES REQUESTED

Lint green on a fresh clone; core-linux green on 71d1ad9. Learning provably soft-only; ISO week, thresholds, decay, Forget/Don't ask again and scheduler caps verified and tested. Flagged decisions 1–5 accepted (2 conditional on enforcing the prefix).

- [MAJOR] FactLearner.swift:174-185 + :139-154: restate to a different key keeps the old stable id → duplicate FactIDs, and old household evidence re-creates/re-proposes the household fact (nagging; suppression lost). Keep a tombstone for the old key (forgottenAt, suppression preserved), new id for the stated fact; tests for unique ids, no re-proposal after restate, suppression kept; general unique-id check on update output.
- [MINOR] Threshold ignores recency/decay (:292, :314): lead decision — count only events within a 56-day window (weight ≥ 0.25) toward the threshold; proposed facts whose qualifying evidence lapses drop back to observing; boundary tests.
- [MINOR] PromptScheduler.swift:20: enforce id prefix ↔ kind (internal memberwise init or precondition); test.
- [MINOR] Amend ADR 0013 for update(facts:events:recipes:now:timeZone:).
- [NIT] record overload ambiguity on `.yes` → recordLunchbox / recordReflectBack; [NIT] confidence 0 on dismissed.
