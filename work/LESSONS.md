# CI pitfalls already paid for (read before coding)
- Swift 6.2 strict concurrency: typed-throws closures need explicit types; keep Sendable conformances explicit.
- Adding an enum case in Core? grep `Packages/Apple` for exhaustive `switch` over it (OMPData DTO mappings broke macOS CI for `lockedMealNoLongerSafe`).
- Empty fixture directories are not tracked by git - add a `.gitkeep`.
- Floating-point quantity math: compare with tolerance; round only at display.
- Unicode: combining marks/Cf (e.g. Prepend) break grapheme assumptions - use `TranscriptSanitiser` for voice/text input.
- Safety lint: a new `unblock`-style call needs a reviewed exception in `scripts/lint-safety.sh`; do not work around it.
- Every behavior change needs unit tests; the test-count asserts (`assert-tests-ran.sh`) fail a run that silently skips tests.
- Batch CI: push several finished tasks on one `claude/ci-batch-N` branch; one CI cycle instead of one per task.
- Docs-only changes (`*.md`, `work/**`) do not trigger CI.
