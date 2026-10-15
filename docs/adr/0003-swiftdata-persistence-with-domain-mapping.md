# ADR 0003: SwiftData persistence behind repositories, mapped to domain value types

- **Status:** Accepted. SwiftData is given by owner (tech §3, §4.1 `OMPData`); the mapping approach is added by the architect.
- **Date:** 2026-10-12

## Context
The owner chose SwiftData. The safety core has to be pure Swift that can be tested on Linux (ADR 0005), and SwiftData `@Model` classes are Apple-only reference types. CloudKit sync is deferred (G6) but should stay possible.

## Decision
- Domain entities in `OMPDomain` are immutable, `Sendable` value types. `OMPServices` (portable) defines async **repository protocols** and in-memory implementations.
- `OMPData` (Apple-only) defines `@Model` records in `SchemaV1: VersionedSchema` with a `SchemaMigrationPlan` from day one, plus mappers `Record <-> Domain`. Repositories are `@ModelActor` actors that implement the `OMPServices` protocols.
- Enums are stored as raw `String`s, and tag sets as sorted `[String]`.
- A **plan's content** (meals, servings, explanations) is stored as one versioned JSON blob (`PlanContentDTO v1`) on `MealPlanRecord`. A plan is always loaded and approved as a whole, which keeps the content hash and diff exact. Members, rules, pantry, shopping items, facts, events, cook logs and prompt state are first-class records.
- CloudKit-compatible modelling from V1 so sync can be added without a rewrite: no `@Attribute(.unique)`, every attribute optional or defaulted, relationships optional, UUID ids, `createdAt`/`updatedAt`/`deletedAt` (soft delete) on every record.
- The store lives in the app's own container (not the App Group) with `NSFileProtectionComplete`.

## Alternatives considered
1. Use `@Model` classes directly as domain types. Rejected: the core could no longer build on Linux, and global mutable reference state works against deterministic, testable planning.
2. Core Data or GRDB/SQLite. Rejected: the owner chose SwiftData. The mapping layer keeps a later switch (tech §17.2) contained to `OMPData`.
3. Normalised `PlannedMeal` records. Rejected for v1: it makes hashing and atomic revisions harder, and nothing queries meals across plans.

## Consequences
- There is mapping code to write and test (round-trip tests on macOS).
- Plan content migrations are handled in our own DTO versioning, which is tested on Linux.
