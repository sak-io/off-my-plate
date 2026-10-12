# OffMyPlate v1: Copy

**Status:** DRAFT · **Author:** ux-designer · **Date:** 2026-10-12
All user-facing strings for v1. IDs (`C-xxx`) are referenced from `screens.md`; developers should use them as String Catalog keys or comments so tests and translators can trace them. `{name}` = member display name (custom name, or "Adult 1" / "Child 2"), `{n}` = a number.

## Voice and tone
- The app speaks as "I", the user is "you". Warm, short, plain. One idea per sentence.
- Say what happened and what to do next. Never blame, guilt, nag or use exclamation marks for errors.
- No jargon: never "draft revision", "validator", "hard rule", "Fact", "confidence", "sync". Use "changes", "safety check", "must avoid", "what I've learned".
- Pluralise properly via String Catalog plural variants ("1 item" / "2 items").
- Safety copy is calm and factual, never alarming, never cute.

---

## 1. Onboarding

| ID | Where | Text |
|---|---|---|
| C-010 | S-01 title | Who's eating? |
| C-011 | S-01 subtitle | No names needed. You can add them later. |
| C-011b | S-01 steppers | Adults · Children |
| C-011c | S-01 footnote | Teens count as adults for portions. |
| C-012 | S-01 invalid | Add at least one person. |
| C-013 | S-01 max | That's the most I can plan for right now (12). |
| C-014 | Button | Continue |
| C-020 | S-02 title | Does anyone have an allergy or something they must avoid? |
| C-021 | S-02 reason (one sentence) | I'll never put these in a plan, so I need to know before I suggest anything. |
| C-022 | S-02 primary button | No, nobody |
| C-022a | VoiceOver label for C-022 | No, nobody has allergies or foods to avoid |
| C-023 | S-02 divider | or tell me what to avoid |
| C-023a | Text field placeholder | e.g. no beef, one of us can't have nuts |
| C-023b | Chips | Peanuts · Tree nuts · Dairy/milk · Egg · Wheat/gluten · Soy · Sesame · Mustard · Fish · Shellfish · Beef · Pork · Vegetarian · Jain (no onion, garlic, root veg) |
| C-023c | List header | To avoid |
| C-023d | Who? menu | Who? · Not sure who (everyone) · {name} |
| C-024 | Unrecognised item | I can't check recipes for “{text}” yet. Pick the closest match, or remove it and check recipes yourself. |
| C-024a | Buttons | Pick closest match · Remove |
| C-025 | Continue disabled hint | Sort out the item above to continue. |
| C-026 | "No, nobody" disabled hint | You've added things to avoid. Remove them to choose "No, nobody". |
| C-027 | S-02b title | Check this is right |
| C-027a | S-02b rows | {name}: {items} · Everyone: {items} · Everyone else: nothing to avoid |
| C-027b | S-02b buttons | Yes, save this · Change |
| C-030 | Gate cover title (one member) | Does {name} have an allergy or something they must avoid? |
| C-030a | Gate cover progress | {n} of {total} |
| C-031 | Gate cover primary | No, nothing |
| C-031a | VoiceOver label for C-031 | No, {name} has nothing to avoid |
| C-033 | Gate escape | Added by mistake? Remove {name} |
| C-034 | Confirm remove (alert) | Remove {name}? · Remove · Cancel |
| C-034b | Confirm remove from Household | Remove {name}? Their portions will come out of future plans. · Remove · Cancel |
| C-035 | S-03 title | What do you usually cook? |
| C-035a | S-03 subtitle | Pick a few, or skip. I'll learn as we go. |
| C-035b | S-03 chips | North Indian · South Indian · Gujarati / Maharashtrian · Bengali / East Indian · A bit of everything |
| C-035c | Buttons | Skip · Make my plan |

## 2. Safety re-checks and editing

| ID | Where | Text |
|---|---|---|
| C-036 | Remove a must-avoid item | Remove {item} for {name}? Future plans may include {item}. · Remove · Cancel |
| C-037 | S-33 empty | Nobody has anything to avoid. |
| C-038 | S-33 title | Allergies & must-avoid foods |
| C-040 | 180-day card title | Still correct? |
| C-040a | 180-day card body | Here's what I avoid for your household: {summary}. |
| C-040b | Summary when none | Nobody has anything to avoid. |
| C-040c | Buttons | Yes, still correct · Make changes |
| C-041 | Age change sheet title | Still correct for {name}? |
| C-041a | Age change body | {name} is now a {ageGroup}. Here's what I avoid for them: {items or "nothing"}. |
| C-042 | Toast after confirm | Thanks. I'll check again in about six months. |

## 3. Plan

| ID | Where | Text |
|---|---|---|
| C-050 | Loading | Planning your week… |
| C-051 | Slow loading | Still working… |
| C-052 | Plan error | I couldn't make a plan just now. Please try again. · Try again |
| C-053 | Nav title | This week |
| C-053a | Date range | {Mon 12} – {Sun 18 Oct} |
| C-054 | Status: draft | Draft · not in use yet |
| C-055 | Status: approved | Approved {date} |
| C-056 | Status: pending changes | Changes not approved yet |
| C-060 | First-plan banner | A starting point. Swap anything and I'll learn. |
| C-061 | Safety summary line | Safety: {summary}. · Change |
| C-062 | Approve button + caption | Approve week · Builds your shopping list and lets you mark meals cooked. |
| C-062a | VoiceOver hint for Approve | Approves all {n} meals for this week |
| C-063 | No plan | No plan for this week · Make a plan |
| C-064 | Empty slot + Why? | No safe recipe for this meal yet. · None of my recipes fit everyone's must-avoid list for this meal. You could mark someone as not eating, or plan this one yourself. |
| C-065 | Toast after approve | Week approved. Your shopping list is ready. · View list |
| C-066 | Draft caption in meal | Approve the week to mark meals cooked. |
| C-067 | Swap empty | No other safe recipe for this meal. Try changing who's eating. |
| C-068 | Swap sheet | Swap {day} {meal} · Why change it? (optional) · Don't feel like it · Too long · Kids won't eat it · Pick one · Pick for me |
| C-069 | Toast after editing approved plan | Swapped. Changes need your approval. |
| C-070 | Review bar | Review {n} changes |
| C-070a | Diff sheet | Approve {n} changes? · Everything else stays as approved. · Was: {old} · Now: {new} · Approve changes · Discard changes · Not yet |
| C-070b | Diff: other change types | Added: lunchbox for {name} · Now empty: no safe recipe · Portions changed: {name} added |
| C-070c | Safety check line | Safety check passed for everyone |
| C-071 | Validator failed | Something changed since this plan was made, so I need to replace a few meals to keep everyone safe. · OK |
| C-072 | Toast after re-approve | Changes approved. Your list is updated. |
| C-073 | Discard confirm | Discard your changes? Your approved plan stays as it is. · Discard · Keep editing |
| C-074 | Regenerate confirm | Replace all unlocked meals? Locked meals stay. · Replace · Cancel |
| C-075 | Lock / unlock | Lock · Unlock · VoiceOver value: "Locked, stays when you regenerate" |
| C-076 | Mark cooked | Mark cooked · Mark {meal} cooked · Cooked today |
| C-077 | Cooked sheet | Cooked {meal}? · I'll take these out of your pantry. · {used} of {have} · Will be 0 · Not in your pantry · Update pantry |
| C-078 | Portions | {n} portion(s) · Not eating · Undo |
| C-079 | Changed row labels | Changed · Approved: {meal} · Proposed: {meal} |
| C-080 | Blocked card | Answer the safety question for {name} to keep planning. · Answer now |
| C-081 | Disabled action hint | I can't change meals until I know what {name} must avoid. · Answer now |
| C-082 | New member card | {name} isn't in this week's plan yet. · Update plan · Later |
| C-083 | Safety answers changed | Your safety answers changed. Some meals need replacing. · Update plan |
| C-084 | Template reasons (AC-4.7) | Uses your {ingredient} · Quick weekday {meal} · Good for lunchboxes · Something different from yesterday · You cook this often |

## 4. Medical note and disclaimers (wording to be reviewed before App Store, G4)

| ID | Where | Text |
|---|---|---|
| C-090 | S-02, S-33 footer | OffMyPlate isn't medical advice. Always check ingredients and labels. |
| C-091 | Plan + meal footer | Not medical advice. Check ingredients and labels, especially for allergies. |
| C-092 | S-37 full note | OffMyPlate suggests meals based on what you tell it. It isn't medical advice and can't guarantee a dish is free of allergens: packaged ingredients can contain hidden allergens or traces. Always check ingredients and labels. For allergies or medical diets, follow advice from your doctor or dietitian. |

## 5. Learning

| ID | Where | Text |
|---|---|---|
| C-100 | Reflect-back card | {observation}. Should I plan around that? · Yes · Not really · Don't ask again |
| C-100a | Observation examples | You usually swap out fish on weekdays · You often pick quick dinners on weekdays · You cook South Indian breakfasts often |
| C-101 | After Yes | Got it. You can change this in What I've learned. |
| C-102 | After Not really | Okay, I won't plan around that. |
| C-103 | After Don't ask again | Okay, I won't ask about this again. |
| C-104 | Lunchbox prompt | Do any of the kids take lunch to school? · Yes · No · Not now |
| C-105 | School lunches sheet | School lunches · Who takes lunch to school? · Which days? · Pick at least one child and one day. |
| C-150 | S-35 intro | These shape suggestions only. |
| C-150a | Section headers | You told me · You confirmed · I noticed · Starting guesses |
| C-150b | Confidence words | Likely · Maybe |
| C-150c | Quick confirm | That's right |
| C-151 | Safety pointer | Allergies and must-avoid foods are only set by you. |
| C-152 | Empty | Nothing yet. As you swap and cook, I'll note what your household likes here. |
| C-153 | Origin | You said this · You confirmed this · I noticed this from {n} swaps · I noticed this from {n} meals you cooked · I noticed this from your shopping lists · My starting guess |
| C-153a | Fact sheet fields | Applies to · Everyone · Prefer · Avoid when possible · Save · Forget this |
| C-154 | Forget confirm | Forget this? I'll stop using it for suggestions. · Forget · Cancel |

## 6. Pantry and voice

| ID | Where | Text |
|---|---|---|
| C-120 | Stale item | Not checked in a while · Still have it |
| C-121 | Unresolved item | Not recognised · Match it |
| C-122 | Empty title | Your pantry is empty |
| C-123 | Empty body | Add what you have, or say it: “I bought 2 kg rice.” · Add item · Speak |
| C-124 | Search no result | Nothing called “{text}” in your pantry. |
| C-125 | Add as typed | Add “{text}” as typed · I won't count it toward your plan until it's matched to an ingredient. |
| C-126 | Form labels | Add item · Edit item · Name · Amount · Unit · Where · Fridge · Freezer · Shelf · Use-by date · Delete item |
| C-127 | Use-by display | Use by {weekday} · Use by {date} · Past use-by date |
| C-130 | Listening | Listening… · Try: “I bought 1 kg onions”, “we're out of milk” · Done |
| C-130a | Confirm card | Add these? · Add {n} items · Remove {item} from pantry · Set {item} to 0 · Update pantry |
| C-130b | Partial | I didn't catch: “{text}” · Add it by hand |
| C-131 | Nothing understood | I didn't catch any items. Here's what I heard: “{transcript}” · Try again · Type it instead |
| C-132 | Interrupted | Stopped listening. |
| C-133 | Prefilled form caption | You said: “{transcript}” |
| C-134 | Permission denied | Voice is off for OffMyPlate. To speak your pantry, turn on Microphone and Speech Recognition in Settings. You can always type instead. · Open Settings · Type instead |
| C-135 | Unavailable | Voice isn't available on this device right now. You can type instead. · Type instead |
| C-136 | `NSMicrophoneUsageDescription` | OffMyPlate listens only while you hold the mic open, to add things to your pantry. |
| C-137 | `NSSpeechRecognitionUsageDescription` | OffMyPlate turns what you say into pantry items. Speech is processed on this device when it supports it. |

C-137 note for architect: if the device can't recognise on-device, Apple's speech service may be used by the system. Copy must match the implementation; if v1 forces on-device only (`requiresOnDeviceRecognition`), change the second sentence to "Speech stays on this device." and use C-135 when unsupported.

## 7. Shopping list

| ID | Where | Text |
|---|---|---|
| C-140 | No approved plan | Approve your plan to build your list · Go to plan |
| C-141 | Nothing to buy | You have everything for this week. |
| C-142 | Pending changes banner | This list is from your approved plan. Approve your changes to update it. |
| C-143 | Bought everything | Add {n} checked items to your pantry? · Add to pantry · Cancel |
| C-144 | Headers | Shopping list · For {range} · Check you have · Vegetables & fruit · Dairy & eggs · Grains & flours · Pulses & lentils · Spices & masalas · Oils & ghee · Meat & fish · Bakery · Other |
| C-145 | Check you have actions | I have it · Need it |
| C-146 | Add field | Add an item |
| C-147 | Origin label | from Notes |
| C-148 | Share text header | Shopping list for {range} (from OffMyPlate) |
| C-149 | Menu | Bought everything · Clear checked items |

## 8. Household, privacy, data

| ID | Where | Text |
|---|---|---|
| C-110 | Household | Household · People · Add person · Safety · Your plan · Plan snacks too · About |
| C-110a | Member status | Nothing to avoid · Avoids {items} · Not answered yet |
| C-112 | Person form | Name (optional) · Age group (optional) · Not set · Toddler · Child · Teen · Adult · Senior · Takes lunch to school · Remove person |
| C-111 | Notes merged toast | Added {n} items from Notes. |
| C-160 | Privacy | Everything you tell OffMyPlate stays on this device. There's no account, and nothing is sent to us or anyone else. |
| C-161 | Delete all | Delete everything? This removes your household, plans, pantry, list and everything I've learned from this device. It can't be undone. · Delete everything · Cancel |

## 9. Share Extension

| ID | Where | Text |
|---|---|---|
| C-169 | Title + buttons | Add to OffMyPlate · Cancel · Add {n} |
| C-169a | Destination | Add to · Shopping list · Pantry |
| C-169b | Unparsed group | Not sure about these · Keep |
| C-170 | Empty | I couldn't find a list in this note. |
| C-171 | Not text | I can only read text for now. Photos and PDFs aren't supported yet. |
| C-172 | Saved | Added. You'll see them next time you open OffMyPlate. |
| C-173 | Error | Couldn't save these. Please try again. |

## 10. Generic errors

| ID | Where | Text |
|---|---|---|
| C-095 | Save failed (any screen) | Something went wrong saving that. Your other information is safe. Please try again. · Try again |
| C-096 | Data couldn't load (launch) | I couldn't open your data. Restart the app; if it keeps happening, check your device has free space. |
| C-097 | Storage full | Your device is out of space, so I couldn't save. Free some space and try again. |
