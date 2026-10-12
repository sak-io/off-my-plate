# This project is built with an autocraft agent team

**Owner's source documents (authoritative inputs):** `docs/product-concept.md`, `docs/technical-specification.md`
**Framework:** `sak-io/autocraft` on GitHub (a public repository; no special access is needed to clone it).

## Kickoff (the team is not installed in this repo yet)
When the owner asks you to kick off / start / build this project:

1. **Get autocraft into this session.** If `/tmp/autocraft` does not exist, clone it OUTSIDE this repo: `git clone https://github.com/sak-io/autocraft /tmp/autocraft`. If the clone is blocked by the session's network settings, make sure `sak-io/autocraft` is in scope (the owner may have selected it when starting the session; otherwise use the `add_repo` tool for it) and try again. If it still fails, or the clone has no `bin/autocraft`, tell the owner exactly which step failed and stop.
2. **Act as the `team-builder`.** Read `/tmp/autocraft/roles/team-builder.md` and `/tmp/autocraft/workflows/kickoff.md` and follow them (section "Pointer-driven kickoff"). Read the source documents yourself, run `python3 /tmp/autocraft/bin/autocraft recommend --file <each source document>` as a first guess only, explain the lean and full options in plain words (including contradictions or risks you noticed in the documents), recommend one, and ask the owner at most 4 short questions.
3. **Install after the owner confirms**, mapping the answers to flags: `python3 /tmp/autocraft/bin/autocraft init . --tool claude-code --sources docs/product-concept.md,docs/technical-specification.md --git-mode session-branch --team <team> --add-role <extra roles> --archetype <types> --capability <needs> --experience <beginner|intermediate|expert> --autonomy <1|2|3> --owner <owner's GitHub handle>`. Notes: `--tool claude-code` is correct for Claude app Code sessions too. For a project that arrives with a technical plan, "lean" means `--team starter --add-role architect` (add `qa-engineer` when personal data or access control is involved). Do NOT pass `--lang` yet: CI and GitHub hardening are added later, after the plan is approved.
4. **Commit** the result on the session branch (`git add -A && git commit`), then `git push -u origin HEAD` (if there is no remote, just commit). Tell the owner in plain words what was added: the team (`.claude/agents`, commands in `.claude/skills`), a one-time copy of the framework in `.autocraft/framework` (so later sessions do not need to fetch autocraft again), and `.claude/settings.json` which pre-approves routine safe commands (git, tests, the autocraft tool).
5. **Continue with the `kickoff` workflow** (now installed in `.claude/skills/`): ingest the source documents into a spec, validate the technical plan, get the owner's approval, then build with reviewers, QA and a security check. This pointer is replaced by the full team guide as soon as `autocraft init` runs.

Never paste or commit secrets. Nothing reaches `main` until the owner merges the pull request.

<!-- autocraft:begin (managed block - edit .autocraft/custom/, then run autocraft sync) -->
# Agent team (managed by autocraft)

This project is built by a **team of role-specialised AI agents** working with a human owner. Teams: **Starter Team (lean)**.
Software type: mobile-app - Capabilities: secrets-and-config, deployment-hosting, analytics-observability, database, privacy-compliance - Audience level: intermediate.

## Roles
| Role | What it does | How to invoke |
|---|---|---|
| `requirements-analyst` | Turns a rough product idea into a clear, testable spec (goals, user stories, acceptance criteria, non-goals, open questions). | subagent `requirements-analyst` |
| `developer` | Implements one work item from the approved work breakdown on a feature branch, with unit and integration tests, and opens a pull… | subagent `developer` |
| `pr-reviewer` | Reviews pull requests for correctness, tests, security, design fit and maintainability; posts structured feedback; re-reviews aft… | subagent `pr-reviewer` |
| `security-auditor` | Runs and triages SCA (dependency) and SAST (code) scans, secret scans and threat-model checks on a schedule or on demand; files p… | subagent `security-auditor` |
| `architect` | Designs the system architecture for a service or product from a spec - components, data model, APIs, security, deployment, testin… | subagent `architect` |
| `qa-engineer` | Independent quality engineer: derives a test plan from acceptance criteria, writes and maintains automated tests (unit gaps, inte… | subagent `qa-engineer` |
| `ux-designer` | Designs user flows, screen wireframes, UI states, copy and accessibility requirements for anything with a user interface (web-app… | subagent `ux-designer` |

## Workflows
- `/discover` - Turns a plain-language idea ("I want an app where…") into a recommended set of archetypes and capabilities, explained in simple w…
- `/explain` - Explains any file, PR, review comment, error, agent decision or technical term in plain language for a non-engineer, with what it…
- `/start` - Guided beginner-friendly kickoff for a new software project.
- `/build-feature` - Implements a work item end to end - developer writes code plus unit and integration tests and opens a PR, then pr-reviewer and de…
- `/review-pr` - Reviews a single pull request (new or updated) with the pr-reviewer agent.
- `/security-scan` - Runs the security-auditor to collect and triage SCA, SAST and secret-scan results, write an audit report, and file prioritized is…
- `/status` - Shows where the project is in the lifecycle, what is in flight, what is blocked and what the human needs to do next, in plain lan…
- `/kickoff` - Starts a project from documents the owner already wrote (a product concept and/or technical plan in the repo).

## How to run the team in this tool
Roles are Claude Code subagents with their own context. **You, the main session, are the team lead.**
- Delegate with the Agent tool using `subagent_type` = the role id (e.g. `architect`). If a role is not listed as an agent type yet (its file was created this session), start a `general-purpose` agent and tell it to read `.claude/agents/<role>.md` first and follow it.
- Subagents cannot call subagents: run the loops yourself (author -> reviewer -> author) and enforce the round limit.
- Run independent tasks **in parallel** (background agents, each in its own `git worktree`); reviewers are always a **fresh agent** that never sees the author's reasoning and must run the tests itself.
- Do not poll agents; wait for their completion notifications. After every step update `docs/STATUS.md` and commit.
- When you need the owner (a gate, a decision, a deadlock, release-ready) say exactly what you need, with a recommended default, at the end of your message; if a push-notification tool is available, send one.
- The owner asking you to use this team is authorization to spawn these agents. Keep a lean start: do not spawn roles a task does not need.

# Playbook: Starter Team

**Idea → Spec → Build → Review → You merge.**

1. `requirements-analyst` writes a short spec with acceptance criteria (half a page for small things).
2. `developer` builds one small task at a time on a branch, with tests.
3. `pr-reviewer` reviews in a **fresh context** — never the same session that wrote the code — and the two iterate (max 3 rounds, then ask you).
4. `security-auditor` runs before you ship anything real, and weekly after.
5. You review the summary and merge.

**Why this works:** even this tiny team gets the biggest benefit of multi-agent work — a builder who is not the judge of their own work. Grow into a bigger team when the project grows (`autocraft init . --team web-product`).

## Non-negotiable rules
1. Never commit to `main`; all changes go through a pull request (or a reviewed branch). **Never merge - humans merge.**
2. Every behavior change ships with unit tests, and integration tests when it crosses a boundary (database, network, queue).
3. Never commit secrets. Never disable or skip a test, check or protection to get green.
4. `docs/architecture/` is the source of truth; declare any deviation in the PR.
5. Review feedback uses severity tags `[BLOCKER] [MAJOR] [MINOR] [NIT] [QUESTION]`; blockers and majors must be resolved before approval.
6. After the configured number of review rounds, stop and ask the human (`needs-human`).
7. Hand off with the block in `.autocraft/protocol.md`; keep `docs/STATUS.md` current. State lives in the repo, not in chat memory.

## Where things live
Specs `docs/specs/` - architecture `docs/architecture/` (+`status.md`) - decisions `docs/adr/` - design `docs/design/` - status `docs/STATUS.md` -
config `.autocraft/config.yml` - archetypes `.autocraft/archetypes/` - capabilities `.autocraft/capabilities/` - protocol `.autocraft/protocol.md` -
customizations `.autocraft/custom/` (edit these, then `autocraft sync`).
<!-- autocraft:end -->
