# T17 handoff 2: answers to review round 1

- **From:** developer -> **To:** pr-reviewer
- **Branch:** `feat/t17`

| Item | Resolution |
|---|---|
| [MAJOR] restate keeps the old id, so ids repeat and the old fact can be proposed again | **Fixed.** The API is now `FactLearner.restate(_ id:in facts:subject:statement:now:) -> [Fact]`. Same key: the fact is updated in place. New key: the old fact becomes a `.forgotten` tombstone that keeps its id, its suppression and `forgottenAt = now`, so the same evidence cannot bring it back. The stated fact either updates an existing fact with the new key or is appended with a new id from `uniqueID(for:avoiding:)`. `update` also uses `uniqueID` for new facts (`#2`, `#3`, ... suffix if the stable id is taken). Tests: `restateToMemberTombstonesOldKey` (unique ids; tombstone; no re-proposal; no reflect-back candidates), `restateKeepsSuppression`, `updateIDsAreUnique`; `statedFactsAreUserOwned` covers the same-key case. |
| [MINOR] the threshold ignores recency | **Fixed** as the lead decided. `proposalWindowDays = 56`: only events with age <= 56 days (weight >= 0.25, compared on seconds so the boundary is exact) count toward the threshold. Proposal is recomputed on every run, so a lapsed proposed fact returns to `observing`. Tests: `proposalWindowBoundary` (exactly 56 days counts, one second more does not), `proposedLapses`. |
| [MINOR] the id prefix is not tied to the kind | **Fixed.** `PromptCandidate.init` is now `internal` with a precondition that the prefix class matches the kind. `id` and `kind` are now `let`. Outside the module, candidates can only come from the `.lunchbox`, `.safety(_:)` and `.reflectBack(_:)` factories. Test: `idPrefixMatchesKind`. |
| [MINOR] ADR 0013 signature | **Fixed.** The ADR now gives `update(facts:events:recipes:now:timeZone:)`, the 56-day window and the restate-tombstone rule. |
| [NIT] the `record` overloads are ambiguous on `.yes` | **Fixed:** renamed to `recordLunchbox(_:on:now:)` and `recordReflectBack(_:on:now:)`. |
| [NIT] dismissed facts keep their confidence | **Fixed:** confidence is 0 when a fact is dismissed (suppressed or Not really). It is asserted in `restateKeepsSuppression`. |

## Evidence
- `bash scripts/check-core.sh --lint-only`: OK. No Swift toolchain here, so CI is the verification of record.
