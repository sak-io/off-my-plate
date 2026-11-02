# W05 report: onboarding and mandatory safety screens (tier S)

Branch `feat/w05`, CI branch `claude/ci-w05`. Package `platforms/web/app`. No `core/` change, no facade change, no runtime dependency. One new dev dependency: `@axe-core/playwright 4.10.1` (exact pin, lockfile updated, `npm ci --ignore-scripts`).

## 1. Files
| File | Purpose |
|---|---|
| `src/screens/onboarding.ts` | S-01 (who is eating), S-02 safety question (onboarding and gate-cover variants), S-02b check, S-03 cuisines, S-04 planning; the guards (Back, Escape) |
| `src/screens/onboarding-entry.ts` | chips, text field, "To avoid" list, Who? menu, unmapped-item rows. Only `safety.parse` (saves nothing) |
| `src/screens/onboarding-model.ts` | pure logic: chip labels (C-023b), candidates, summary rows (C-027a), wire form of items, rule summary |
| `src/screens/onboarding-reconfirm.ts` | "Still correct?" card (AC-3.4, F5) with a compact editor |
| `src/screens/dom.ts` | DOM helpers (textContent only) |
| `src/main.ts` (+9 lines) | `render()` asks `gateScreen` first; Plan tab shows the re-check card. `styles.css`: appended block only |
| `tests/onboarding.spec.ts` | 16 Playwright tests incl. axe; `tests/e2e.spec.ts`: the W04 test now walks through onboarding (the Household tab no longer creates a household; the old form is unreachable) |

## 2. How each rule is enforced
| Rule | Mechanism | Test |
|---|---|---|
| Safety question cannot be skipped or closed | `render()` calls `gateScreen` before anything else. While the core's gate is `noHousehold` or `refused/safetyUnanswered`, only the onboarding page is drawn: no tabs, no Skip/Close/Later, no links. The decision is the core's gate on every render, never UI state alone. A household.get failure fails closed. | S-02 has no skip/close; noShell asserted on every screen |
| Escape | no handler closes anything (capture-phase `keydown` swallows Escape while blocking); the only dialog (remove question) closes itself only | Escape test on body, button, chip, input, check screen; cover remove dialog |
| Tab / Shift+Tab | nothing else is on the page; 60 key presses never focus an element outside `main#onboarding` | Tab test |
| Browser Back | a history entry is pushed and re-pushed on `popstate` while blocking | 3 x `goBack` on S-02 and on S-02b, URL and screen unchanged |
| Reload | state lives in the core snapshot (IndexedDB); gate re-evaluated from it. Household created but unasked reopens at S-02 (not S-01); unsaved candidates are gone, not saved | reload on S-02 and on S-02b; snapshot still has `rules: []` and all `unasked` |
| Explicit confirm before saving | chips/typed text only edit an in-memory list; `safety.confirm` / `confirmMember` are called from exactly one place, the "Yes, save this" click on S-02b. "Change" keeps the answers | snapshot read between each step: no rules, all `unasked` until Save; then `hard`/`user` rules and `stated` / `confirmedNone` |
| Unmapped item forces pick or remove | row shows C-024 text with "Pick closest match" and Remove; Continue disabled with C-025; "No, nobody" disabled. `toApiItems` throws if anything is unresolved (second lock); the core also refuses `unresolved_items` | unmapped test incl. forced click on the disabled button; nothing saved |
| App never constructs the approval | no approval type or `plan.approve` / `approvalPreview` in `src/screens`; this task calls `plan.generate` only (draft) | source-scan test |
| All core calls through `Core.call` with explicit ctx | screens only use `host.op` -> `App.op` -> `core.call(name, args, makeCtx())` | source-scan test (no `core.call`, `new Core` in screens; main.ts line asserted) |
| No innerHTML with data | `textContent` and DOM nodes only | scan for HTML-injection APIs + a typed `<img onerror>` stays text, `window.__xss` undefined |

## 3. Behaviour vs the design
- S-01: steppers 0..12, total 1..12, C-012/C-013 as text. Raising/lowering counts after answering (Back) follows `OnboardingModel.applyCounts`: new people are `unasked` and get the gate cover; lowering removes the highest-numbered people with `household.removeMember {removeOwnRules:true}`.
- S-02 onboarding variant (all members unasked; also after a reload): Back to S-01, chips, text, Who? menu (hidden for one person; parser name hints map to a person only on an exact name match, else Everyone), unmapped rows, disclaimer C-090. "No, nobody" -> `safety.confirmNobody {pendingItemCount:0}`.
- Gate cover (some members unasked: person added later, or after Back): one page per person with "n of total", no Back, no Who?, "No, nothing" -> `safety.confirmMember`, items scoped to that person, "Added by mistake? Remove {name}" with a confirm (cannot remove the only person).
- S-02b: rows Everyone / person / "Everyone else: Nothing to avoid", "Yes, save this" / "Change". Save failure shows C-095 and keeps the answers.
- S-03 cuisines (Back, Skip, chips), S-04 "Planning your week..." (C-051 after 5 s) calls `plan.generate`, error C-052 with Try again, then switches to the Plan tab (W06 draws the plan).
- Re-check (AC-3.4): when the core gate is `refused/reconfirmationDue` the Plan tab shows "Still correct?" with the household summary; "Yes, still correct" -> `safety.reconfirm`; "Make changes" -> remove a rule (asks first, `confirmed:true`) or add items (review, explicit save, `safety.addRule`). It may be ignored (the core keeps new drafts blocked, G3).

## 4. Deviations and open points
1. **Cuisine chips are not stored (AC-1.4 partly open).** The facade has no op to record cuisines as `stated` soft facts (W03 listed `recordCuisines` as deferred; W13 did not add it). The chips are shown and selectable, Skip/Make my plan both continue, and the selection is dropped. A facade op (for example `learning.recordCuisines {cuisines}`) is needed; this is a follow-up for a facade task, not done here (no Swift change in W05, and the cuisine list must match the seed tags, open item U5).
2. **Age-group change sheet (C-041, second half of AC-3.4) is not wired:** there is no member-edit UI yet (W09). The op `household.setAgeBand` exists; the re-check card logic can be reused.
3. After going Back from S-03 and adding people, the gate cover ends on the Plan tab (not back at S-03).
4. The W04 Household-tab create form is now unreachable (a household always comes from onboarding); left in place to keep the shell diff small.
5. Browser Back cannot be made impossible (a user can long-press history or close the tab); the guarantee is that leaving and returning always shows the question again, because the gate comes from the stored state.
6. Local verification limits: no Chromium or Swift toolchain in the sandbox (download blocked), so the Playwright suite ran only in CI. Locally: typecheck, and a jsdom smoke run of the flow against a fake core (size -> safety -> unmapped resolve -> check -> change -> save -> cuisines -> plan).
7. The axe test uses a context with `bypassCSP` only so axe can inject itself; the shipped CSP is still tested by `e2e.spec.ts`.
8. Dark mode, 200% zoom and reduced-motion audits are W10.

## 5. Tests
16 new browser tests (list in `tests/onboarding.spec.ts`) plus the adapted W04 suite. CI result: see the final message / board.
