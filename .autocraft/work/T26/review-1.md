# T26 review-1 (light, tier N)
Scope: git diff claude/build-v1...feat/t26. No Swift toolchain; CI is the compile/test gate.

Invariants checked
- Imports touch only list/pantry rows + staple events (ImportService unchanged; extension model has no household/rules/safety). OK (AC-11.5).
- Link isolation: project.yml OffMyPlateShare adds only OMPShare (plus OMPDomain/OMPRecipes/OMPUI); Package.swift OMPShare deps = OMPUI + OMPDomain. ShareLinkListTests reads both files (#filePath x5 reaches repo root), checks block-scoped dependencies and `import` lines. Real test. OK.
- Inbox recreated: DirectoryShareInboxWriter.createDirectory on every write (tested). OK.
- Format: uses InboxImport(importId:...), encoded() (schema + 256 KiB guard thrown -> C-173), file name = item.fileName = id. OK; retry reuses one id, overwrite not duplicate.
- No network: link text ignored, only text types/file URLs read, capped by maxInputBytes+1. OK.
- App Group: nil/UnavailableInboxWriter when entitlement missing; UI test uses -OMPUITestInbox temp dir (Debug only). Not signing-dependent. OK.
- Drain: runs at .task and scene .active; ImportService serialised + processed-id store, so repeated drain is idempotent. Toast: C-111 "Added {n} items from Notes." matches copy.md; singular is a logged deviation.
- ADR 0011 deviation (new OMPShare product) is acceptable and logged in tracked.md (architect ack pending).
- Swift 6.2: ShareTextLoader handler marked @Sendable captures only the continuation, no NSItemProvider; `.task { closeAfterDelay() }` is MainActor view code; ShareViewController Task is @MainActor. No likely compile failure found.
- CompositionRoot names verified against package source (SeedLoader.loadBundled, ServiceContext init, InMemoryProcessedImportStore, store in scope).

Findings
- [MINOR] App/project.yml comment above OffMyPlateShare still says "links only OMPDomain, OMPRecipes and OMPUI"; add OMPShare.
- [MINOR] drain failure of `stuck` files and quarantined files only logged (tracked, needs owner copy). Accepted.
- [NIT] DirectoryShareInboxWriter sets protectionKey .complete on the Inbox directory itself; if the app is woken in background while locked, listing/reading will fail and the drain logs and retries (safe: files stay). Fine, no change needed.
- [QUESTION] none blocking.

Ordering: CI note: this touches Packages/Apple and App/, so per owner rule it must not merge until macOS CI is green again.

VERDICT: APPROVED
