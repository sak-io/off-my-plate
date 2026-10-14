# T22 review round 1 (pr-reviewer)

Scope: Onboarding/*, AppModel, AppShellView, SafetyGateCover, CompositionRoot, project.yml, Package.swift, Info.plist, OnboardingModelTests, SafetyAnswerModelTests, OnboardingUITests. No Swift toolchain here; compile and audits left to CI.

No BLOCKER, no MAJOR.

Checked and fine
- Safety question cannot be skipped: no skip/close/dismiss in SafetyAnswerView; onboarding Back goes to S-01 only; gate cover hosts the same view with no close control; answer only via explicit save or (member variant, not last member) confirmed removal.
- "No, nobody" gated on items.isEmpty in the model, not only in the view (canChooseNobody guard).
- Chips/text/voice only create AvoidItems. Writes happen only in chooseNobody/confirmSummary/removeSubject via SafetyService/HouseholdService; planning via PlanService.generateWeek (gate and validator inside). Tests assert rules empty and members unasked before confirm.
- Unmapped item: unresolved blocks Continue (canContinue) and confirmSummary re-guards; unknown restriction id also becomes unresolved; ruleRequests drops unresolved but cannot be reached with any.
- Name hint is ignored by the model (default scope = household, or the subject member); test asserts it.
- Failures keep items, phase and answers (save catch). Member save is idempotent on retry.
- Copy matches copy.md ids C-010..C-035c, C-134/135. No fixed font sizes, no .secondary, no ContentUnavailableView found (grep).
- Concurrency: MainActor model, Task inherits actor, SpeechCapture is @MainActor, EntityID is ExpressibleByStringLiteral (CuisineID literals OK), seed cuisine ids match. Exhaustive switches look complete.

Findings
- [MINOR] SafetyAnswerModel.micTapped / continueToSummary: listening is not stopped when the user taps Continue, and submitText has no phase guard. A late transcript can append rows (even an unresolved one) while the summary is shown; "Yes, save this" then silently does nothing (confirmSummary guard fails with no feedback). Suggest: continueToSummary calls speech?.stop() and submitText returns unless phase == .entry; add a test.
- [MINOR] AppShellView: if safetyServices is nil (seed load failed in wireSafety) the onboarding branch is skipped and tabs show with no household, and the gate cover (answering == nil) shows a question with no controls. Not a bypass of the planner gate, but a dead end/odd state; show LoadFailedView or a dedicated message when services are missing.
- [MINOR] Back from S-02 to S-01 discards the typed/chip rows (model rebuilt). Spec says failures keep answers, which holds; consider noting or preserving rows. Back from S-03 returns to S-01 though safety is already saved: acceptable, mention in release notes.
- [MINOR] PlanningPage failure has only "Try again"; a persistent validator rejection traps the user on S-04 until relaunch. Consider a secondary exit to the app (gate still holds) after N failures.
- [NIT] Info.plist NSMicrophoneUsageDescription says "while you hold the mic open" (it is a toggle); NSSpeechRecognition says "Speech stays on this device" - only true if on-device is forced (copy.md C-137 note); confirm SystemSpeechBackend sets requiresOnDeviceRecognition.
- [NIT] Hard-coded `spacing: 2` in summary rows; `Text(verbatim: "Adults: n")` bypasses localisation (use a formatted key).
- [PRAISE] Idempotent confirmMember, explicit model-level guards duplicating the view-level disabled states, and tests that assert persisted state rather than view flags.

VERDICT: APPROVED (CI must be green on both platforms before merge; track the MINORs in .autocraft/work/tracked.md)
