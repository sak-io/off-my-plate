# T21 handoff 1: app shell, design system, composition root

- **From:** developer -> **To:** pr-reviewer
- **Branch:** `feat/t21` (local worktree `/home/user/omp-t21`, base `claude/build-v1` @ 03e4b1d)
- **Task:** docs/architecture/tasks.md T21. ACs: AC-2.6, AC-14.1, AC-15.x groundwork.

## What and why
- **OMPUI** (`Packages/Apple/Sources/OMPUI/`), per docs/design/design-system.md:
  - `Tokens/OMPColor.swift`: accent #1B6E3A / #5CC98A and `onAccent` #FFFFFF / #0B2A17, each with
    Increase Contrast variants, built in code (UIColor/NSColor dynamic providers) so OMPUI needs no
    resources and the share extension gets the same values. `warning` = system orange.
  - `Tokens/OMPLayout.swift`: spacing 8/16/24, card radius 12, 44 pt hit target, max widths,
    text-style-only fonts (Dynamic Type), SF Symbol names; `.ompMinimumHitTarget()`, `.ompCardBackground()`.
  - `Components/`: `OMPPrimaryButtonStyle` (`.ompPrimary`, OnAccent label), `AdaptiveStack`
    (vertical from `.accessibility1`), `DisclaimerFooter` + `Disclaimer` (C-090/C-091/C-092) +
    `DisclaimerNoteView`, `InlineCard`, `StatusLabel`, `.ompPrimaryBottomBar`, `.ompToast`
    (4 s, VoiceOver announcement, opacity under Reduce Motion). `PlaceholderMessage` only moved
    (share extension still uses it).
- **OMPFeatures**: `AppModel` (`@MainActor @Observable`) holds `Repositories` and a `DomainClock`,
  exposes `household`, `gateStatus`, `membersNeedingAnswer`; `refresh()` reloads and re-evaluates.
  `GateStatus` is derived only from `SafetyGate.evaluate` (`unanswered` -> cover + badge;
  `reconfirmationDue` -> badge only, no cover, per screens.md; `loadFailed` -> C-096).
  `AppShellView`: `TabView(.sidebarAdaptable)` with Plan/List/Pantry/Household (each a
  `NavigationStack` placeholder), Plan "!" badge while planning is blocked, refresh on `.task` and
  on `scenePhase == .active` (180-day check). Root gate cover: `fullScreenCover` on iOS (sheet on
  macOS), binding setter ignores dismissal, `interactiveDismissDisabled(true)`, VoiceOver focus on
  the title, C-030 title, C-030a "1 of N", C-021 reason, C-090 footer. Plan placeholder shows
  C-091; Household -> About -> full note C-092 (AC-2.6 "reachable").
  `OMPLog`: os `Logger`s; only status names, counts and error *type* names, all `privacy: .public`.
  `Member.displayName` / `MemberLabel.displayName` ("Adult %lld", "Child %lld" via the catalog).
- **App target**: `CompositionRoot` opens `PersistenceStore` at `StoreLocation.appDefault()`; on
  failure logs a fault and uses `AppModel.storeUnavailable` (shows C-096; never restarts onboarding
  over existing data). Debug-only `-OMPUITestSeed empty|answered|unasked` uses fresh in-memory repos.
  `Localizable.xcstrings`: 18 keys, copy ids where they exist (C-021, C-030, C-030a, C-090..C-092,
  C-096) and `shell.*` / `member.label.*` otherwise. Code uses `String(localized: key, defaultValue:)`
  so packages fall back to English under `swift test`.
- `project.yml`: app also links Core `OMPDomain`, `OMPServices` (imported by the composition root).
  `Package.swift`: OMPFeatures depends on `OMPDomain` explicitly; new test targets `OMPUITests`,
  `OMPFeaturesTests`.

## Tests
- `swift test` (Packages/Apple, macOS): `DesignTokenTests` (variant selection, WCAG ratios for
  OnAccent-on-accent >= 4.5 in all 4 appearances, accent on light/dark backgrounds, white on dark
  accent fails, spacing, AdaptiveStack threshold, disclaimer copy ids/text, distinct symbols);
  `GateStatusTests` (no household, clear, unasked, deleted member, 181 days, answered without date,
  display names, C-030/C-030a, tab titles); `AppModelTests` (empty store, unasked order, refresh
  after answering, failing repository -> loadFailed, store unavailable).
- XCUITest `AppShellUITests` (replaces the T02 walking-skeleton test, whose screens are gone): tabs
  switch on iPhone and iPad; disclaimer reachable from Household; gate cover shows for an unasked
  member with "1 of 2", has no Close/Skip/Back/Cancel and survives a swipe down; two
  `performAccessibilityAudit()` runs (shell, gate cover), unfiltered.

## Verification status (honest)
- No Swift toolchain/Xcode here: **nothing was compiled or run locally.** `scripts/check-core.sh
  --lint-only` passes (no-network, core-imports, script self-tests). macOS CI is the verification
  of record; please run `swift test --package-path Packages/Apple` and the xcodebuild UI tests.

## Risks / review focus
- API spots double-checked from memory, worth a compiler look: `Tab(...).badge(Text?)`,
  `Text.accessibilityLabel(String) -> Text` (badge VoiceOver), `AccessibilityNotification.Announcement`.
- iPad tab tapping: `tapTab` tries tab-bar buttons, then any button, then sidebar cells.
- The accessibility audits are strict; a system-element false positive (e.g. tab bar on iPad)
  would need a narrow, documented filter rather than disabling the audit.
- Diff is ~1.7k lines (including ~200 lines of xcstrings JSON and ~500 of tests): over the 400-line
  guideline because the task bundles design system + shell + composition root.

## Deviations / gaps
- Domain-specific components (`SafetyAnswerView`, `SafetySummaryView`, `MealRow`,
  `ConfirmItemsList`, `PlanStatusLabel`) are left to T22-T24, which own their screens; OMPUI has
  the generic bases (`StatusLabel`, `InlineCard`, `AdaptiveStack`). The gate cover's answer
  controls ("No, nothing", C-033 remove) are T22.
- The share extension links OMPUI but has its own bundle: if it shows a disclaimer later it needs
  these keys in its own catalog.
- Services (T18/T19) are not wired yet; `AppModel` is where they go.
