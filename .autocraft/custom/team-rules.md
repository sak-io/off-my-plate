<!-- Rules every role must follow in THIS project (style, frameworks, company standards). Then run: autocraft sync -->

## Usage budget (owner decision, 2026-10-13)
The owner's Claude plan has a rolling usage limit, and a wide parallel team exhausted it in about 30–40 minutes. Until the owner says otherwise:
- **At most 4 agents run at the same time** (owner: 2 -> 3 on 2026-10-14, then 4 once T19 merged and T24-T27 opened; for example three developers and one reviewer). The team lead does not start a fifth.
- **Reviewers (pr-reviewer, qa-engineer, security-auditor) run on Sonnet**; developers and the architect use the session model.
- **Short briefs:** each agent gets the task id, the exact files and spec/ADR sections it needs, and the CI facts — not "read the whole plan". Agents read only what their task needs.
- **One review round for small, non-safety tasks** when CI is green and round 1 finds no BLOCKER/MAJOR; remaining MINOR/NIT items are tracked in `.autocraft/work/tracked.md`. Safety-critical tasks (safety gate, validator, planner, plan approval, safety suite, services that call them) keep full review until approved.
- CI on both platforms stays mandatory before every merge; independent review is never skipped.
