# T02 review, round 1: APPROVED

CI green on bd16466 before merge (pushed as claude/ci-t02): core-linux and apple-macos, including XcodeGen generate (no drift), app build, UI tests on iPhone and iPad simulators with the xcresult zero-test guard. Fresh-clone check-core --lint-only and all self-tests pass.

Tracked (no fix before merge):
1. [MINOR] Extension text-detection untested → T26.
2. [MINOR] XcodeGen soft-pinned via brew → follow-up: checksum-verified 2.46.0 zip (sha256 4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806, to re-confirm).
3. [MINOR] CODE_SIGNING_ALLOWED=NO likely leaves App Group entitlement off on CI simulators → T26 (sign to run locally, or injectable inbox root).
4. [MINOR] Handoff said "verifiable only after merge"; CI actually ran before merge (recorded here).
5. [NIT] UI test nav-bar button query could be scoped.
6. [NIT] Add a lint against CFBundleURLTypes / associated-domains under App/.
Owner: CI check renamed to "Apple platforms (macOS 15, Xcode 26)".
