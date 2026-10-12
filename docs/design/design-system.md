# OffMyPlate v1: Design system and accessibility

**Status:** DRAFT · **Author:** ux-designer · **Date:** 2026-10-12
Goal: no custom design assets. Use system fonts, SF Symbols, semantic colours and standard SwiftUI controls. The only custom asset is the accent colour pair below.

## 1. Tokens

### Colour
Use semantic system colours everywhere (`.primary`, `.secondary`, `Color(.systemBackground)`, `Color(.secondarySystemBackground)`, `.red` only via `role: .destructive`). They adapt to Dark Mode and Increase Contrast automatically.

| Token | Light | Dark | Use | Contrast |
|---|---|---|---|---|
| `AccentColor` | #1B6E3A | #5CC98A | tint, links, prominent buttons | light on white ≈ 6.3:1; dark on #1C1C1E ≈ 8.2:1 (AA text) |
| `OnAccent` | #FFFFFF | #0B2A17 | label on `borderedProminent` buttons | ≈ 6.3:1 / ≈ 7.3:1 |
| Warning | system `.orange` icon **plus text** | same | ▲! states (unasked, stale, unrecognised) | icon is decorative; the text carries meaning |

Note: SwiftUI's `borderedProminent` uses a white label by default; in Dark Mode that fails on #5CC98A. Set `.foregroundStyle(Color("OnAccent"))` in one shared `PrimaryButtonStyle` (or use the dark accent #1B6E3A in both modes if the team prefers zero custom styles; it passes 3:1 for non-text on dark backgrounds but text links then need `.primary`). Provide "Increase Contrast" variants in the colour set (darker light / lighter dark).

### Type
System text styles only (`.largeTitle`, `.title2`, `.headline`, `.body`, `.subheadline`, `.footnote`, `.caption`). No fixed point sizes. Meal names `.headline`, reasons `.subheadline` + `.secondary`, disclaimers `.footnote`.

### Spacing and shape
Rely on `List`/`Form` defaults. Custom stacks: 8 / 16 / 24 pt. Cards: `RoundedRectangle(cornerRadius: 12)` on `secondarySystemBackground`. Minimum hit target 44×44 pt (use `.contentShape` and padding on chips and icon buttons).

### Icons (SF Symbols, always paired with text or an accessibility label)
Plan `fork.knife` · List `checklist` · Pantry `refrigerator` · Household `house` · Draft `pencil.circle` · Approved `checkmark.seal` · Locked `lock.fill` · Warning `exclamationmark.triangle` · Mic `mic` · Listening `waveform` · Info `info.circle` · Cooked `checkmark.circle.fill`.

## 2. Reusable components (build once)

| Component | Built from | Used in |
|---|---|---|
| `SafetyAnswerView` | chips (`Toggle` with `.button` style in a flow `Layout`), `TextField`, mic button, item rows with `Menu` "Who?", resolution row | S-02 onboarding, S-02 gate cover, S-33 add sheet |
| `SafetySummaryView` | per-person rows | S-02b, 180-day card, age-change sheet, S-10 summary line |
| `PlanStatusLabel` | `Label` with icon + text | S-10 header, iPad sidebar |
| `MealRow` | `VStack` in `List` row, swipe actions, context menu | S-10 |
| `InlineCard` | rounded container, title, body, up to 3 buttons | lunchbox prompt, reflect-back, blocked, 180-day, new member, safety changed |
| `ConfirmItemsList` | editable rows + "didn't catch" row | S-22 confirm, S-15 cooked, S-40 review |
| `DisclaimerFooter` | `Label` `.footnote` | S-02, S-10, S-11, S-33 |
| `Toast` | bottom overlay, auto-hide 4 s, `AccessibilityNotification.Announcement` | approvals, Notes merge |
| `PrimaryBottomBar` | `.safeAreaInset(edge: .bottom)` | Approve week, Review changes |
| `ContentUnavailableView` | system | all empty states |

Prompt scheduler rule for UI: render at most one `InlineCard` from the prompt queue at a time; safety cards (blocked, 180-day, safety changed) always take the slot first.

## 3. Accessibility requirements (target WCAG 2.2 AA + Apple HIG)

### 3.1 Dynamic Type (AC-15.1)
- Support all sizes up to `.accessibility5`. No `.lineLimit(1)` on meal names, chips, buttons or copy; allow wrapping.
- At `dynamicTypeSize >= .accessibility1`: steppers and "label + value" rows switch from `HStack` to `VStack` (`ViewThatFits` or an environment check); chip flow layout becomes one chip per line; bottom bar buttons stack vertically; S-15/S-22 rows put the edit button under the text.
- Bottom bars use `safeAreaInset` so content scrolls above them and is never hidden.
- Snapshot tests at `.large` and `.accessibility5` for S-01, S-02, S-10 (draft + approved + pending), S-13, S-20, S-25, S-40.

### 3.2 VoiceOver (AC-15.2)
| Control | Label | Value / hint / trait |
|---|---|---|
| "No, nobody" | "No, nobody has allergies or foods to avoid" (C-022a) | button |
| "No, nothing" (gate) | "No, {name} has nothing to avoid" | button |
| Allergen chip | "Peanuts" | trait selected when on; hint "Adds to things to avoid" |
| "Who?" menu | "Who avoids peanuts" | value "Not sure who, everyone" |
| Remove item ⊖ | "Remove peanuts" | button |
| Mic button | "Speak" | hint "Say what you bought"; value "Not available" when off |
| Approve week | "Approve week" | hint "Approves all 21 meals and builds your shopping list" |
| Review changes | "Review 2 changes" | — |
| Plan status | "Plan status: draft, not in use yet" / "approved Monday 12 October" / "changes not approved yet" | header trait |
| Meal row | combined: "Tuesday lunch, Rajma chawal, uses your rajma, locked" | custom actions: Swap, Lock/Unlock, Mark cooked |
| Changed meal row | "Tuesday lunch, changed. Approved: Rajma chawal. Proposed: Chole chawal" | — |
| Diff entry | "Tuesday lunch. Was Rajma chawal. Now Chole chawal" | — |
| Portion stepper | "Child 1 portion" | value "0.6 portions" / "Not eating" |
| Lock toggle | "Lock" | value "Locked, stays when you regenerate" |
| List row | "Onion, 1 kilogram" | trait selected when checked; value "Checked" |
| Check you have | "Milk, 1 litre. Check you have it" | actions: I have it, Need it |
| Pantry stale row | "Milk, 1 litre, not checked in a while" | action: Still have it |
| Reflect-back card | read as one group, then 3 buttons | — |
| Tab badge | "Plan, needs your answer" | — |

- Swipe actions always have an equivalent visible button or custom accessibility action.
- Safety gate cover: focus starts on the title; `accessibilityAddTraits(.isModal)` is implicit for full-screen cover.
- Toasts and "Listening…" state changes post an announcement.
- Unit spoken in full ("kilogram", "litre") via `accessibilityLabel` on quantity text.

### 3.3 Contrast and colour (AC-15.3)
- Text ≥ 4.5:1 (≥ 3:1 for large text ≥ 18 pt regular / 14 pt bold); icons and control borders ≥ 3:1.
- State is never colour-only: Draft/Approved/Changed/Locked/Checked/Stale/Unrecognised/Not answered each have a word and an SF Symbol. Checked list items use checkmark + strikethrough.
- Respect Increase Contrast, Smart Invert (no images to protect in v1), Dark Mode.

### 3.4 Hit targets and input
- 44×44 pt minimum for every control, including chips, ⊖ remove, steppers, lock icon.
- 8 pt minimum between adjacent small targets (WCAG 2.5.8).
- Nothing requires a precise gesture: swipe and long press always have a button alternative. Drag-to-reorder is not used.
- Full keyboard (iPad hardware keyboard / Full Keyboard Access) navigation works; Return submits text fields; ⌘N adds a pantry item, ⌘F searches (nice to have).

### 3.5 Reduced Motion (AC-15.4)
- With Reduce Motion on: no redacted shimmer, no card slide-ins (use opacity crossfade), static listening icon, toasts fade instead of slide, no auto-scroll animations. No celebratory animations anywhere in v1.

### 3.6 Other
- Voice is never the only way: every voice action has a typing path (AC-9.5).
- Time-outs: Share Extension auto-close after save is the only timed UI; with VoiceOver running, wait for the announcement or close immediately after an explicit "Done".
- Plain-language copy aims for reading age ~10-12.

## 4. iPad kitchen-friendly note (v1, no dedicated kitchen mode)
A dedicated kitchen mode is deferred (spec §3). v1 should still be pleasant on a counter-top iPad:
- Meal detail (S-11) in the detail column uses `.controlSize(.large)` for Mark cooked and Swap, and the ingredient list in `.body` at minimum, so it is readable at arm's length with Dynamic Type raised.
- Works in landscape and portrait, Split View and Stage Manager; plan stays visible beside the detail.
- No gestures that are hard with wet or floury hands: big buttons, no swipe-only actions, no long-press-only actions.
- Do not disable auto-lock in v1 (would need a kitchen-mode toggle; deferred).
- Voice pantry works on iPad with the same push-to-talk sheet; hands-free listening is deferred.
