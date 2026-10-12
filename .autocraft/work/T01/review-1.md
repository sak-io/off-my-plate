# T01 review, round 1: CHANGES REQUESTED

Reviewer: pr-reviewer (fresh context). Full review relayed by the team lead.

- [MAJOR] 1. Both lints bypassed by Swift 6 access-level imports (`internal import UIKit`, `public import Network`). Fix regexes + module_sed capture index; fixtures `violation-access-level-import` in both suites; add `public import Foundation` to core-imports clean fixture.
- [MAJOR] 2. Remote package detection misses multi-line `.package(\n url:`, registry `.package(id:`, `name:`+`url:`, XcodeGen `github:` and flow `{url: ...}`. Flag `(url|id)\s*:\s*"` in Package.swift (and Package@swift-*.swift), `(url|github)\s*:` in project.yml/project.yaml; fixtures multiline, registry-id, project-yml-github; update test-lints.sh case names.
- [MINOR] 3. Ban more locale-dependent APIs per ADR 0005: other *Formatter types, `.formatted(`, `(Calendar|Locale|TimeZone).(current|autoupdatingCurrent)`; one fixture.
- [MINOR] 4. no-network: add NetworkExtension, FoundationNetworking modules; URLRequest symbol.
- [MINOR] 5. bootstrap leaves the dockerd it started running when `docker pull` fails; kill it on that path; one retry with back-off on 429.
- [MINOR] 6. bootstrap tarball extract not atomic; extract to temp then mv.
- [NIT] 7. check `mktemp -d` failure.
- [NIT] 8. optional: pin swift.org key fingerprint (VALIDSIG).
- [NIT] 9. `cancel-in-progress: ${{ github.event_name == 'pull_request' }}`; optionally narrow push branches to claude/** and main.
- [NIT] 10. macOS job should fail (not warn) when Xcode 26 is missing, or rename the job.
- [NIT] 11. pin actions/checkout to a commit SHA with a version comment.
- [NIT] 12. fail CI when 0 tests ran (grep the Swift Testing summary).

Done well: fixture-driven lint self-tests, module names derived from Sources/*, check-core never reports green without building, bootstrap never installs unverified toolchains, least-privilege workflows.
