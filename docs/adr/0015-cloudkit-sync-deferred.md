# ADR 0015: CloudKit family sync deferred; keep the model sync-ready

- **Status:** Accepted (given by owner: kickoff #2; spec G6. Tech §2/§5.3 listed sync for v1)
- **Date:** 2026-10-12

## Decision
v1 has a local store only, and data survives through normal device backup. The model follows CloudKit-compatible rules (ADR 0003), and approvals record `approver = .thisDevice` (G8), so sync and role rules can be added later. `Member.safetyStatus` is household data, so an unasked member will block every device once sync exists.

## Alternatives considered
1. Ship private-database sync now. Rejected by the owner (scope). SwiftData + CKShare support is still an open question (tech §17.2).

## Consequences
- Moving to Core Data or CKSyncEngine later stays contained to `OMPData`.
