# OffMyPlate v1: Screens, states and navigation

**Status:** DRAFT · **Author:** ux-designer · **Date:** 2026-10-12
Wireframes are iPhone (compact width) unless marked iPad. Text in quotes is placeholder; final strings are in `copy.md` (IDs `C-xx`). Components are standard SwiftUI; names in `monospace` are suggestions, not mandates.

Legend: `[ Button ]` button · `( chip )` toggle chip · `[x]` checkbox/check state · `>` navigation row · `~~text~~` struck-through · `(i)` info · `▲!` warning icon (SF Symbol `exclamationmark.triangle`) · `✓` `checkmark` icon. Icons always come with a text label (never colour or icon alone).

---

## 1. Navigation structure

```
Root
├── Onboarding (only until household exists): S-01 → S-02 → S-03 → S-04 → Plan tab
├── Safety gate cover S-02 (fullScreenCover over everything while any member is unasked)
└── TabView (.sidebarAdaptable)
    ├── Plan       (fork.knife)          S-10 → S-11 meal detail → sheets S-12, S-13, S-14, S-15
    ├── List       (checklist)           S-25
    ├── Pantry     (refrigerator)        S-20 → sheets S-21, S-22, S-23
    └── Household  (house)               S-30 → S-31, S-33, S-34, S-35 → S-36, S-37, delete-all alert
Share Extension (separate process): S-40
```

- Each tab owns a `NavigationStack`. Sheets use `.presentationDetents([.medium, .large])` where the content is short.
- Tab badge: Plan tab shows a badge ("!") only when safety is blocking planning, and VoiceOver reads it as "Plan, needs your answer". No numeric badges otherwise (never nag).
- No deep links, notifications, widgets or Shortcuts in v1.

### iPad adaptive layout
- `TabView` with `.tabViewStyle(.sidebarAdaptable)` shows a sidebar in regular width and a tab bar in compact width (Slide Over, narrow Split View).
- **Plan** in regular width: `NavigationSplitView` with the week (days and meals list) in the content column and S-11 meal detail in the detail column. Selecting a meal does not push; it fills the detail column. Approve bar stays at the bottom of the content column.
- **Pantry** and **List** in regular width: single column list, max readable width (`.containerRelativeFrame` or `.frame(maxWidth: 700)`), centred. Add/edit sheets become `.formSheet`-style centred sheets (default on iPad).
- **Household**: `NavigationSplitView` (settings rows in content, selected page in detail), matching the iPad Settings app.
- Onboarding and the safety cover: centred card with max width ~600 pt; same content as iPhone.
- Every layout must reflow at 1/3 Split View width (compact) without clipping (AC-15.5).

---

## 2. Onboarding

### S-01 Who's eating? (AC-1.1–1.3)
```
┌─────────────────────────────────────┐
│ Who's eating?                 (Large│ title)
│ No names needed. You can add them   │
│ later.                              │
│                                     │
│ Adults                 [ − ] 2 [ + ]│  Stepper 0…12
│ Children               [ − ] 0 [ + ]│  Stepper 0…12
│                                     │
│ Teens count as adults for portions. │  footnote
│                                     │
│                                     │
│ [         Continue          ]       │  borderedProminent, bottom
└─────────────────────────────────────┘
```
States
- Default: 2 adults, 0 children. Continue enabled.
- Invalid (total 0): Continue disabled; footnote changes to C-012 "Add at least one person." (text, not just greyed button).
- Max (total 12): the "+" steppers disable at the cap; footnote C-013.
- No loading/error/offline states (local only).
- Accessibility sizes: label above stepper (VStack), stepper full width.

### S-02 Safety question (AC-2.1–2.6, US-14) — onboarding variant
```
┌─────────────────────────────────────┐
│ ‹ Back                              │  onboarding only; no close / skip
│ Does anyone have an allergy or      │
│ something they must avoid?          │
│ I'll never put these in a plan, so  │  one-sentence reason C-021
│ I need to know before I suggest     │
│ anything.                           │
│                                     │
│ [        No, nobody         ]       │  borderedProminent, .large, full width
│                                     │
│ ── or tell me what to avoid ──      │
│ (Peanuts) (Tree nuts) (Dairy/milk)  │  chips, flow layout, ≥44 pt tall
│ (Egg) (Wheat/gluten) (Soy) (Sesame) │
│ (Mustard) (Fish) (Shellfish) (Beef) │
│ (Pork) (Vegetarian) (Jain)          │
│                                     │
│ ┌───────────────────────────┐ [🎤] │  TextField + mic button
│ │ e.g. no beef, one of us   │       │
│ │ can't have nuts           │       │
│ └───────────────────────────┘       │
│                                     │
│ To avoid                            │  appears once ≥1 item
│  Peanuts      Who? Not sure who ▾ ⊖ │  Menu: Everyone (not sure who) /
│  Beef         Who? Not sure who ▾ ⊖ │        Adult 1 / Adult 2 / Child 1
│  ▲! "kiwi" – I can't check recipes  │
│     for this yet. [Pick closest ▾]  │
│     [Remove]                        │
│                                     │
│ (i) OffMyPlate isn't medical advice.│  disclaimer C-090, always visible
│     Always check ingredients and    │
│     labels.                         │
│ [      Continue      ]              │  enabled when ≥1 item and none unresolved
└─────────────────────────────────────┘
```
- Selecting a chip adds it to "To avoid"; deselecting removes it. Typed/spoken text is parsed on Return or after the mic stops, and each parsed item is added as a row (AC-2.3). "Jain" chip label reads "Jain (no onion, garlic, root veg)".
- "Who?" menu default is **Not sure who → applies to everyone** (G3; safer). Hidden when the household has one member.
- "No, nobody" is disabled (with hint C-026) while "To avoid" has items, to avoid contradicting answers.
- Continue → **S-02b Check this is right**:
```
┌─────────────────────────────────────┐
│ Check this is right                 │
│ Adult 1        Peanuts              │
│ Everyone       Beef                 │
│ Everyone else  Nothing to avoid     │  only if some members have no items
│                                     │
│ [  Yes, save this  ]  [ Change ]    │
└─────────────────────────────────────┘
```
States
- Default (nothing chosen): only "No, nobody" is actionable; Continue hidden until an item exists.
- Unresolved item: row shows ▲! icon + text C-024; Continue disabled with footnote C-025.
- Parsing (instant, local): no spinner needed; if parse takes > 300 ms show inline `ProgressView` in the text field.
- Mic permission denied / speech unavailable: mic button stays visible; tapping opens S-23 (variant). Text and chips unaffected.
- Error saving: alert C-095, answers kept.
- Offline: no change.
- **No** loading, empty or skip state; no close button; `interactiveDismissDisabled(true)`.

Variants
- **Gate cover (member added later / unasked on launch):** title C-030 "Does Child 3 have an allergy or something they must avoid?", button "No, nothing" (C-031), no Back, no Who? menu, extra text button at the very bottom C-033 "Added by mistake? Remove Child 3" (confirm alert C-034). Several unasked members: one page per member with "1 of 2" progress text.
- **Re-check (180-day / age change):** sheet with summary and two buttons, see S-10 card and C-040s. This variant may be closed; closing leaves new drafts blocked (G3).

### S-03 What do you usually cook? (AC-1.4)
```
┌─────────────────────────────────────┐
│ ‹ Back                       Skip   │  Skip in toolbar trailing
│ What do you usually cook?           │
│ Pick a few, or skip. I'll learn as  │
│ we go.                              │
│ (North Indian) (South Indian)       │  multi-select chips
│ (Gujarati / Maharashtrian)          │
│ (Bengali / East Indian)             │
│ (A bit of everything)               │
│                                     │
│ [      Make my plan      ]          │  always enabled (no chips = same as Skip)
└─────────────────────────────────────┘
```
Chip list must match the cuisine tags the seed recipes actually carry (architect/content to confirm; see open item U5).

### S-04 Making your plan (loading)
Full-screen centred `ProgressView` + C-050 "Planning your week…". Expected < 2 s. If > 5 s, add C-051 "Still working…". Error: C-052 with `[Try again]`. Reduce Motion: static text, standard spinner only.

---

## 3. Plan tab

### S-10 Plan (week) — draft
```
┌─────────────────────────────────────┐
│ This week                 [↻ Regenerate]
│ Mon 12 – Sun 18 Oct                 │
│ ✎ Draft · not in use yet            │  status label: icon + text
│ ┌─────────────────────────────────┐ │
│ │ A starting point. Swap anything │ │  first-plan banner C-060 (dismissible)
│ │ and I'll learn.                 │ │
│ └─────────────────────────────────┘ │
│ Safety: Adult 1 avoids peanuts;     │  safety summary C-061 + [Change] → S-33
│ everyone avoids beef.  [Change]     │
│                                     │
│ MONDAY 12                           │  Section header
│ Breakfast  Poha                  🔒 │  lock icon only if locked (+label)
│            Quick weekday breakfast  │  template reason (AC-4.7)
│ Lunch      Rajma chawal           › │
│            Uses your rajma          │
│ Dinner     Lauki chana dal        › │
│ TUESDAY 13 …                        │
│                                     │
│ (i) Not medical advice. Check       │  disclaimer footer C-091 (AC-14.1)
│     ingredients and labels.         │
├─────────────────────────────────────┤
│ [        Approve week         ]     │  safeAreaInset bottom bar, prominent
│ Builds your shopping list.          │  caption C-062
└─────────────────────────────────────┘
```
Row swipe actions (each also available in S-11): Swap (leading), Lock/Unlock (trailing). Context menu on long press: Swap, Lock, Open.

### S-10 states
| State | What the user sees |
|---|---|
| **Loading** (generating/regenerating) | Whole list: redacted placeholder rows (`.redacted(.placeholder)`) + "Planning your week…". Regenerate: only unlocked rows redacted; locked rows stay. Reduce Motion: no shimmer. |
| **Empty** (no plan: e.g. after Delete-all edge, or plan discarded) | `ContentUnavailableView` C-063 "No plan for this week" + `[Make a plan]`. |
| **Draft** | As wireframe. Status "✎ Draft · not in use yet". No Mark cooked. |
| **Approved** | Status "✓ Approved Mon 12 Oct". No bottom bar. Rows show `[Mark cooked]` trailing button for today and past days; cooked rows show "✓ Cooked" text. First-plan banner gone. |
| **Approved + pending changes** | Status "✎ Changes not approved yet". Changed rows show "Changed" label and two lines: "Approved: Aloo paratha" / "Proposed: Poha". Bottom bar `[Review 2 changes]` (C-070). Mark cooked acts on the approved meal. |
| **Empty slot** (AC-4.4) | Row: "No safe recipe for this meal yet" + `(i) Why?` → popover C-064. Approve still allowed. |
| **Blocked by safety (S-10b)** | Top card, not dismissible: ▲! C-080 "Answer the safety question for Child 3 to keep planning." `[Answer now]` reopens S-02 gate. Regenerate/Swap/Approve disabled with C-081 shown on tap. Approved plan below stays usable. Plan tab badge "!". |
| **New member not in approved plan** | Card C-082 "Child 3 isn't in this week's plan yet." `[Update plan]` (creates draft revision) · `[Later]`. |
| **"Still correct?" due** (F5) | Top card C-040: summary + `[Yes, still correct]` `[Make changes]`. Swap/Regenerate open this check as a sheet first. |
| **Contextual / reflect-back card** | Max one card visible (safety cards win). Reflect-back: C-100 text + `[Yes]` `[Not really]` `[Don't ask again]`. |
| **Error** (generation or save failed) | Inline card C-052 "I couldn't make a plan just now." `[Try again]`. Previous plan (if any) still shown. Validator failure at approval: alert C-071, then affected meals regenerate. |
| **Offline** | Identical to online (no network used). No offline banner anywhere in the app. |

Toasts (non-blocking, `.overlay` at bottom, 4 s, announced to VoiceOver): C-065 "Week approved. Your shopping list is ready." with `[View list]`; C-072 "Changes approved."; C-111 "Added 8 items from Notes."

### S-11 Meal detail (pushed; iPad detail column)
```
┌─────────────────────────────────────┐
│ ‹ This week                 🔒 Lock │  toolbar toggle, label changes Lock/Unlock
│ Tuesday · Lunch                     │
│ Rajma chawal                        │  title
│ 45 min · Uses your rajma            │  time + reason
│ ┌ Lunchbox prompt card (F3) ──────┐ │  only lunch slot, only when eligible
│ │ Do any of the kids take lunch   │ │
│ │ to school?  [Yes] [No] [Not now]│ │
│ └─────────────────────────────────┘ │
│ WHO'S EATING                        │
│ Adult 1       1 portion   [−][+]    │  steps of 0.2; 0 = Not eating
│ Adult 2       1 portion   [−][+]    │
│ Child 1       0.6 portion [−][+]    │
│ Child 2       Not eating   [Undo]   │
│ INGREDIENTS (for 3.6 portions)      │
│ Rajma 220 g · Onion 2 · …           │
│ STEPS  (if recipe has steps)        │
│ 1. …                                │
│ [  Swap  ]       [ Mark cooked ]    │  Mark cooked only on approved plan
│ (i) Not medical advice…             │
└─────────────────────────────────────┘
```
- Setting a portion to 0 shows "Not eating" (AC-6.3). If the slot then has a safe recipe set that differs, nothing changes automatically; the user can Swap.
- Draft plan: Mark cooked replaced by caption C-066 "Approve the week to mark meals cooked."
- Changed meal in pending revision: shows "Approved: Aloo paratha" block with `[Mark Aloo paratha cooked]`, and "Proposed: Poha" block.
- Blocked by safety: Swap disabled + C-081.
- Cooked: button becomes "✓ Cooked today" (disabled).

### S-12 Swap sheet (AC-8.1, 8.2)
```
┌─────────────────────────────────────┐
│ Swap Tuesday lunch          Cancel  │
│ Why change it? (optional)           │
│ (Don't feel like it) (Too long)     │
│ (Kids won't eat it)                 │
│ PICK ONE                            │
│ ○ Chole chawal · 40 min             │  up to 3 rows, each with reason
│   Similar, and uses your chana      │
│ ○ Veg pulao · 30 min                │
│ ○ Dal khichdi · 25 min              │
│ [ Pick for me ]                     │  re-roll
└─────────────────────────────────────┘
```
States: Loading (inline spinner in list, < 1 s expected) · Empty (C-067 "No other safe recipe for this meal. Try changing who's eating.") · Blocked by safety (sheet not opened; C-081 alert instead) · Error C-095.
Selecting a row applies immediately and dismisses; toast "Swapped. Changes need your approval." if the plan was approved.

### S-13 Approval diff sheet (AC-5.4, 5.6)
```
┌─────────────────────────────────────┐
│ Approve 2 changes?          Not yet │
│ Everything else stays as approved.  │
│ TUE LUNCH                           │
│  Was: Rajma chawal                  │  "Was" / "Now" words, not colour
│  Now: Chole chawal                  │
│ WED DINNER                          │
│  Was: Palak paneer                  │
│  Now: Aloo gobi                     │
│ ✓ Safety check passed for everyone  │  validator result, text + icon
│ [      Approve changes       ]      │  prominent
│ [ Discard changes ]                 │  destructive role, plain style
└─────────────────────────────────────┘
```
States: Validating (button shows `ProgressView`, disabled) · Validator failed: replace check line with ▲! C-071 and disable Approve · Error saving C-095.
Change types listed: meal swapped, meal added (lunchbox), slot emptied, servings changed ("Child 3 added"), lock changes are not listed (they don't change food).

### S-14 School lunches sheet (AC-7.2)
```
┌─────────────────────────────────────┐
│ School lunches          Cancel  Save│
│ Who takes lunch to school?          │
│ [x] Child 1   [x] Child 2           │  Toggles, all on by default
│ Which days?                         │
│ (Mon)(Tue)(Wed)(Thu)(Fri)(Sat)(Sun) │  Mon–Fri selected
└─────────────────────────────────────┘
```
Save disabled if no child or no day selected (caption explains). Same sheet reachable from Household → School lunches.

### S-15 Cooked sheet (AC-9.6)
```
┌─────────────────────────────────────┐
│ Cooked Rajma chawal?        Cancel  │
│ I'll take these out of your pantry. │
│ Rajma        220 g of 500 g  [edit] │
│ Rice         300 g of 2 kg   [edit] │
│ Onion        2 of 1     → 0  [edit] │  never below zero; text "will be 0"
│ Ginger       Not in your pantry     │  secondary text, no action
│ [       Update pantry        ]      │
└─────────────────────────────────────┘
```
Edit opens a number field with unit. Error C-095.

---

## 4. Pantry tab

### S-20 Pantry
```
┌─────────────────────────────────────┐
│ Pantry                  [🎤] [ + ]  │  toolbar: Speak, Add
│ 🔍 Search                           │  .searchable
│ FRIDGE                              │
│ Paneer        200 g   Use by Thu    │
│ Milk          1 L     ▲! Not checked│  stale: icon + text C-120
│                       in a while    │
│               [Still have it]       │
│ FREEZER …                           │
│ SHELF                               │
│ Rice          2 kg                  │
│ "masala mix"  1 pack  ▲! Not        │  unresolved (AC-9.2) C-121
│               recognised [Match it] │
└─────────────────────────────────────┘
```
Swipe: Delete (trailing, destructive). Tap: edit (S-21).
States: Empty `ContentUnavailableView` C-122 "Your pantry is empty" + C-123 "Add what you have, or say it: “I bought 2 kg rice.”" + `[Add item]` `[Speak]` · Search no results: C-124 · Error C-095 · Offline: identical · Mic denied/unavailable: mic button stays, tap → S-23.

### S-21 Add / edit item
```
┌─────────────────────────────────────┐
│ Add item              Cancel   Save │
│ Name  [ Search ingredients…      ]  │  suggestions list under field
│       Rice · Basmati rice · …       │
│       + Add "masala mix" as typed   │  if no match, with note C-125
│ Amount [ 2      ]  Unit [ kg ▾ ]    │  g, kg, ml, L, pcs, pack
│ Where  [Fridge | Freezer | Shelf]   │  segmented, default by ingredient
│ Use-by date  [ off ]  → DatePicker  │
│ [ Delete item ]   (edit mode only)  │
└─────────────────────────────────────┘
```
Save disabled until name and amount present. Prefilled-from-voice variant shows the transcript as a caption above the form: C-133 "You said: “…”".

### S-22 Speak to pantry (listening → confirm)
```
Listening                         Confirm
┌──────────────────────────┐     ┌──────────────────────────┐
│ Listening…        Cancel │     │ Add these?        Cancel │
│ “I bought 2 kg rice and  │     │ Rice    2 kg      [edit] │
│  a dozen eggs”           │     │ Eggs    12        [edit] │
│                          │     │ ▲! I didn't catch:        │
│ Try: “I bought 1 kg      │     │  “some of that stuff”    │
│ onions”, “we're out of   │     │  [Add it by hand]        │
│ milk”                    │     │ [   Add 2 items    ]     │
│ [        Done        ]   │     └──────────────────────────┘
└──────────────────────────┘
```
- Listening indicator: text "Listening…" plus SF Symbol `waveform` (static when Reduce Motion is on).
- Interrupted (call, app backgrounded): stop, keep transcript, show confirm or C-131.
- Nothing understood: C-131 + transcript + `[Try again]` `[Type it instead]`.

### S-23 Voice unavailable (sheet, medium detent)
Variants: permission denied → C-134 + `[Open Settings]` `[Type instead]`; not supported / needs network while offline → C-135 + `[Type instead]`. Also used from S-02's mic button (then "Type instead" focuses the text field).

---

## 5. List tab

### S-25 Shopping list
```
┌─────────────────────────────────────┐
│ Shopping list        [Share] [⋯]    │  ⋯ menu: Bought everything, Clear checked
│ For Mon 12 – Sun 18 Oct (approved)  │
│ [ + Add an item               ]     │  inline TextField, Return adds
│ CHECK YOU HAVE                      │  AC-10.4, first section
│ Milk 1 L       [I have it][Need it] │
│ VEGETABLES & FRUIT                  │
│ ○ Onion 1 kg                        │  tap toggles check
│ ✓ ~~Tomato 500 g~~                  │  checked: checkmark + strikethrough
│ DAIRY & EGGS …                      │
│ OTHER                               │
│ ○ Masala mix · from Notes           │  origin label for imports
│ [   Bought everything   ]           │  bottom, enabled when ≥1 checked
└─────────────────────────────────────┘
```
States
- **No approved plan, draft exists:** `ContentUnavailableView` C-140 "Approve your plan to build your list" + `[Go to plan]`; manual/imported items still listed below if any.
- **Nothing to buy:** C-141 "You have everything for this week." (manual add still available).
- **Pending plan changes:** banner C-142.
- **Blocked by safety:** no special state (list follows the approved plan).
- **Loading:** recompute is local and fast; no spinner unless > 300 ms (then inline `ProgressView` in the header).
- **Error:** C-095. **Offline:** identical.
- Bought everything → confirmation dialog C-143.

---

## 6. Household tab

### S-30 Household
```
┌─────────────────────────────────────┐
│ Household                           │
│ PEOPLE                              │
│ Adult 1          Avoids peanuts   › │
│ Adult 2          Nothing to avoid › │
│ Child 3     ▲! Not answered yet   › │  text + icon
│ [ + Add person ]                    │
│ SAFETY                              │
│ Allergies & must-avoid foods      › │  S-33
│ YOUR PLAN                           │
│ School lunches                    › │  S-14 (only if children)
│ Plan snacks too           [toggle]  │  off by default (G5)
│ What I've learned                 › │  S-35
│ ABOUT                               │
│ About, privacy & medical note     › │  S-37
│ Delete all data                     │  destructive, red text + label
└─────────────────────────────────────┘
```

### S-31 Add / edit person
Form: Name (optional TextField, placeholder "Child 3"), Age group (optional Picker: Not set / Toddler / Child / Teen / Adult / Senior), Takes lunch to school (toggle, only for Toddler/Child/Not set child), Remove person (edit only, destructive, confirm C-034b). Add → creates member and opens the S-02 gate cover immediately. Changing age group across child ↔ teen/adult → re-check sheet (F5) after Save.

### S-33 Allergies & must-avoid foods
List grouped by person ("Everyone", "Adult 1", …) of hard rules, each row "Peanuts". `[+ Add]` opens the same chip/text/voice component as S-02 inside a sheet, then S-02b confirm. Swipe or Edit → Delete with confirmation C-036 ("Remove peanuts for Adult 1? Future plans may include peanuts."). Changing rules re-runs the validator on any open draft (AC-3.5); if an approved plan now violates, show card on Plan tab C-083 "Your safety answers changed. Some meals need replacing." `[Update plan]`. Empty state: C-037 "Nobody has anything to avoid." + `[Add]`. Disclaimer footer C-090.

### S-35 What I've learned
```
┌─────────────────────────────────────┐
│ What I've learned                   │
│ These shape suggestions only.       │  C-150
│ YOU TOLD ME                         │
│ You cook South Indian food        › │
│ YOU CONFIRMED                       │
│ Quick dinners on weekdays         › │
│ I NOTICED                           │
│ You often swap out okra    Likely › │  confidence word: Likely / Maybe
│   [That's right]                    │
│ STARTING GUESSES                    │
│ Medium spice                      › │
│ (i) Allergies and must-avoid foods  │  footer C-151 → S-33
│     are only set by you. ›          │
└─────────────────────────────────────┘
```
Swipe: Forget (destructive). Empty: C-152. Error C-095.

### S-36 Fact sheet
Statement (read-only text), "Where this came from" (C-153 variants: "You said this", "You confirmed this", "I noticed this from 4 swaps", "My starting guess"), Applies to (Picker: Everyone / each person), Strength (segmented: Prefer / Avoid when possible), `[Save]`, `[Forget this]` (destructive, confirm C-154). Never offers "Never" / "Allergic" options; a footer link C-151 points to S-33 for safety.

### S-37 About, privacy & medical note
Static text: medical note C-092 (full), privacy C-160, version. Non-dismissable (it's a page). Delete all data alert C-161 → onboarding restarts at S-01.

---

## 7. Share Extension

### S-40 Notes import review (separate target; compact sheet presented by the host app)
```
┌─────────────────────────────────────┐
│ Cancel     Add to OffMyPlate    Add │  Add = "Add 8" in label
│ Add to  [ Shopping list | Pantry ]  │  default Shopping list
│ Onion        1 kg          ⊖        │  each row editable inline
│ Milk         2 L           ⊖        │
│ Rice         —             ⊖        │  no qty is fine
│ NOT SURE ABOUT THESE                │
│ “call mom re sunday”        ⊖ [Keep]│  unparsed lines, removed unless kept
└─────────────────────────────────────┘
```
States: Parsing (spinner < 1 s) · Empty C-170 · Not text C-171 · Saved C-172 then auto-close after ~1.5 s (immediately with Reduce Motion, VoiceOver announcement) · Error C-173 (stays open) · Offline identical. The extension shows nothing from the household (no plan, no safety info).

---

## 8. Traceability: stories → screens → states

| Story | Screens | States/variants that must exist (UI tests) |
|---|---|---|
| US-1 Onboarding | S-01, S-02, S-03, S-04, S-10 | S-01 invalid/max; S-04 loading/slow/error; S-10 draft + first-plan banner |
| US-2 Safety question | S-02, S-02b, S-23 | no skip/close; "No, nobody"; chips; text/voice; unresolved item; Who? tags; disclaimer visible |
| US-3 Safety gate | S-02 gate cover, S-10b, S-30, S-31, S-33 | blocked state; added-member variant; re-check card/sheet; rule change re-validates |
| US-4 Hard-rule guarantees | S-10, S-11, S-12, S-13 | empty slot; "Why?" reasons; validator pass/fail at approval |
| US-5 Draft → approved | S-10, S-11, S-13 | draft / approved / pending changes; diff; discard; no Mark cooked on draft |
| US-6 Servings | S-11 | portion steppers; Not eating |
| US-7 Lunchbox | S-11 card, S-14 | Yes / No / Not now; cooldown; plan gains Lunchbox rows |
| US-8 Swap/lock/regenerate | S-10, S-11, S-12 | swap empty; Pick for me; regenerate keeps locked |
| US-9 Pantry | S-20, S-21, S-22, S-23, S-15 | empty; stale; unresolved; voice full/partial/none; denied; unavailable; cooked sheet |
| US-10 Shopping list | S-25 | no approved plan; nothing to buy; Check you have; pending changes; bought everything; share |
| US-11 Notes import | S-40, S-10 toast | empty; not text; unparsed lines; destination; saved; error |
| US-12 Learning | S-10 card, S-35, S-36 | reflect-back 3 answers; empty learned; forget; edit |
| US-13 Offline | all | every screen identical offline; only voice may be unavailable (S-23) |
| US-14 Disclaimer | S-02, S-10 footer, S-11 footer, S-33, S-37 | always visible, not dismissible |
| US-15 Accessibility | all | see `design-system.md` §3 |
| US-16 Household & data | S-30, S-31, S-37 | add/remove person; delete-all confirm → S-01 |
