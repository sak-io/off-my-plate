# ADR 0005: Pure-Swift core, buildable and testable on Linux

- **Status:** Accepted (owner: tech §4.1 "free of Apple frameworks", kickoff #1; details by architect)
- **Date:** 2026-10-12

## Context
The cloud session and agent reviewers run on Linux with no Xcode. The safety-critical logic has to be verified by every reviewer on every task.

## Decision
- `Packages/Core`: `swift-tools-version: 6.0`, Swift 6 language mode (strict concurrency), platforms `.iOS(.v18), .macOS(.v15)`. **Zero third-party dependencies.**
- Only `import Foundation`, and only APIs that behave the same on swift-corelibs/swift-foundation: `Date`, `UUID`, `Data`, `JSONEncoder/Decoder` (sorted keys), `Calendar(identifier: .gregorian)` with an explicit `TimeZone`. Not allowed: `NSLocalizedString`, `String(localized:)`, locale-dependent formatters, `NSPredicate`, `CryptoKit`, `os.Logger`.
- Determinism: an injected `Clock` and a `LocalDate` value type (y/m/d). Randomness comes only from an internal seeded `SplitMix64`.
- User-facing strings are not built in the core. The core returns structured reasons (enums) and the UI localises them in a String Catalog.
- Tests use **Swift Testing** (`import Testing`; parameterised tests for the safety matrix). Swift Testing ships with Swift 6 toolchains on Linux and macOS.
- Linux CI uses the official `swift:6.x-noble` container image, pinned to the same Swift minor as the owner's Xcode.

## Alternatives considered
1. XCTest only. Rejected: Swift Testing's parameterised tests express the safety matrix much more clearly, and both toolchains ship it. XCTest stays for UI tests.
2. Use `swift-crypto` and `swift-algorithms`. Rejected: they add supply-chain surface and a network fetch to every build. We need one SHA-256 (ADR 0008) and a PRNG.

## Consequences
- A small amount of code is hand-rolled (SHA-256, PRNG, number words), each with known-answer tests.
- The Linux CI job is the verification of record for the core. A local toolchain in the cloud session is optional, because download.swift.org is blocked by the egress policy (plan §9).
