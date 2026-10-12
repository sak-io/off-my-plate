# ADR 0008: Plan lifecycle state machine with SHA-256 content hash

- **Status:** Accepted (owner: tech §6.4, spec US-5; hash algorithm by architect)
- **Date:** 2026-10-12

## Context
Plans move `draft -> approved -> superseded`, or `draft -> discarded`. Only an explicit in-app Approve may approve. Approval stores who, when and a content hash, and any change invalidates it. Editing an approved plan creates a draft revision while the approved version stays active (A6).

## Decision
- `PlanLifecycle` is a pure function set over `MealPlan` values. Illegal transitions return typed errors.
- `approve(draft, confirmation: UserConfirmation, validation: ValidationReport, now)`. `UserConfirmation` is created only by the approval sheet's button handler (lint-enforced: its initialiser appears only in `OMPFeatures/Plan/ApprovalSheet*.swift` and tests). The voice grammar maps "approve it"/"looks good" to `.openApprovalSheet`, never to a transition. The share extension doesn't link `OMPServices`.
- Content hash = SHA-256 over a canonical encoding (sorted-key JSON of week start, and per meal: date, slot, recipe id, locked, servings (member id, portion, notEating)). Cooked state and explanations are excluded, so cooking doesn't void approval. `isEffectivelyApproved` = `status == .approved && hash(content) == approval.contentHash`.
- Revisions share a `seriesId`. A diff (`PlanDiff`: added/removed/changed meals) drives the re-approval sheet.
- SHA-256 is implemented in the core (~120 lines) and verified against NIST test vectors. Its purpose is change detection, not tamper resistance (there is no adversary across a trust boundary on-device).

## Alternatives considered
1. CryptoKit. Rejected: not available on Linux.
2. A non-cryptographic hash (FNV-64). Rejected: collision margin, and SHA-256 is cheap to verify with vectors.
3. A per-meal approval state. Rejected: the owner's UX approves the whole week; a per-meal diff is enough.

## Consequences
- The canonical encoding is part of the persistence contract. Changing it needs a re-hash migration.
