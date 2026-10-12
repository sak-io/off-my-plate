# ADR 0011: Share-extension handoff through App Group inbox files

- **Status:** Accepted (owner: tech §8.1 "shared App Group store merged by the main app"; mechanism by architect)
- **Date:** 2026-10-12

## Context
The extension parses a shared note, shows a review screen and must hand confirmed items to the app (AC-11.1 to 11.3). Extensions have tight memory limits and run in a separate process. Two processes opening one SwiftData store risks lock contention and migration races.

## Decision
- The extension writes one JSON file per confirmed import, atomically, to `<AppGroup>/Inbox/<importId>.json` (`InboxImport v1`: `schemaVersion`, `importId`, `createdAt`, `destination: shoppingList|pantry`, `items[{name, ingredientId?, quantity?, unit?}]`), with `NSFileProtectionComplete`.
- The main app drains the inbox when the scene becomes active. `ImportService` merges (de-duplicating by ingredient), records `importId` (idempotent), emits learning events (staples only, AC-11.5), then deletes the file. Corrupt files are moved to `Inbox/failed/` and surfaced to the user, never silently dropped.
- The SwiftData store is **not** in the App Group. The extension never touches it.

## Alternatives considered
1. A shared SwiftData store in the App Group. Rejected: it widens the data exposed to the extension, and it risks concurrent access and migration races.
2. `UserDefaults(suiteName:)`. Rejected: not built for payloads, and its atomicity semantics are weak.

## Consequences
- The inbox format is a versioned contract with golden tests on Linux.
- Imports show up when the app is next opened (the spec already says this).
