import Foundation
import OMPDomain

/// Every user-facing string of the Plan screens (S-10 to S-14), keyed by copy id from
/// docs/design/copy.md. Strings without a copy id yet use a `plan.*` key; they are listed in the
/// T23 hand-off for the ux-designer to number.
///
/// The core builds no user-facing strings (ADR 0005): reasons, slots and change kinds are mapped
/// to text here. Each string is mirrored in `App/OffMyPlate/Localizable.xcstrings`.
enum PlanCopy {
    // MARK: Header and status

    static var title: String {
        String(localized: "C-053", defaultValue: "This week", comment: "Plan tab navigation title (S-10).")
    }

    static func dateRange(_ start: String, _ end: String) -> String {
        String(localized: "C-053a", defaultValue: "\(start) – \(end)", comment: "Plan date range: first day, last day.")
    }

    static var statusDraft: String {
        String(localized: "C-054", defaultValue: "Draft · not in use yet", comment: "Status label of a draft plan.")
    }

    static func statusApproved(_ date: String) -> String {
        String(localized: "C-055", defaultValue: "Approved \(date)", comment: "Status label of an approved plan; the date it was approved.")
    }

    static var statusPending: String {
        String(localized: "C-056", defaultValue: "Changes not approved yet", comment: "Status label of an approved plan with a pending draft revision.")
    }

    static func statusAccessibility(_ status: String) -> String {
        String(localized: "plan.status.accessibility", defaultValue: "Plan status: \(status)", comment: "VoiceOver label of the plan status. Argument is the visible status text.")
    }

    // MARK: Loading, empty, error

    static var loading: String {
        String(localized: "C-050", defaultValue: "Planning your week…", comment: "Plan loading text (S-04, S-10).")
    }

    static var error: String {
        String(localized: "C-052", defaultValue: "I couldn't make a plan just now. Please try again.", comment: "Plan generation or save error.")
    }

    static var tryAgain: String {
        String(localized: "C-052.retry", defaultValue: "Try again", comment: "Retry button on the plan error card.")
    }

    static var saveFailed: String {
        String(localized: "C-095", defaultValue: "Something went wrong saving that. Your other information is safe. Please try again.", comment: "Save failed on any screen.")
    }

    static var noPlan: String {
        String(localized: "C-063", defaultValue: "No plan for this week", comment: "Empty state of the Plan tab.")
    }

    static var makePlan: String {
        String(localized: "C-063.action", defaultValue: "Make a plan", comment: "Button on the empty Plan tab that generates a plan.")
    }

    // MARK: Draft banner, approve

    static var firstPlanBanner: String {
        String(localized: "C-060", defaultValue: "A starting point. Swap anything and I'll learn.", comment: "First-plan banner (dismissible).")
    }

    static var dismiss: String {
        String(localized: "plan.banner.dismiss", defaultValue: "Dismiss", comment: "Button that dismisses the first-plan banner.")
    }

    static var approveWeek: String {
        String(localized: "C-062", defaultValue: "Approve week", comment: "Approve button of a draft plan.")
    }

    static var approveCaption: String {
        String(localized: "C-062.caption", defaultValue: "Builds your shopping list and lets you mark meals cooked.", comment: "Caption under the Approve week button.")
    }

    static func approveHint(_ count: Int) -> String {
        String(localized: "C-062a", defaultValue: "Approves all \(count) meals for this week", comment: "VoiceOver hint of Approve week. Argument is the number of meals.")
    }

    static var approveWeekTitle: String {
        String(localized: "C-062b", defaultValue: "Approve this week?", comment: "Title of the approval sheet for a first plan (opened by voice).")
    }

    static var approveWeekDetail: String {
        String(localized: "C-062c", defaultValue: "Everything in this plan was checked for everyone.", comment: "Body of the approval sheet for a first plan.")
    }

    static var weekApproved: String {
        String(localized: "C-065", defaultValue: "Week approved. Your shopping list is ready.", comment: "Toast after approving a first plan.")
    }

    static var changesApproved: String {
        String(localized: "C-072", defaultValue: "Changes approved. Your list is updated.", comment: "Toast after approving a revision.")
    }

    static func reviewChanges(_ count: Int) -> String {
        String(localized: "C-070", defaultValue: "Review \(count) changes", comment: "Review bar button of a plan with pending changes.")
    }

    static var validatorFailed: String {
        String(localized: "C-071", defaultValue: "Something changed since this plan was made, so I need to replace a few meals to keep everyone safe.", comment: "Alert when the safety check fails at approval.")
    }

    static var ok: String {
        String(localized: "C-071.ok", defaultValue: "OK", comment: "Dismiss button of an alert.")
    }

    static var cancel: String {
        String(localized: "plan.cancel", defaultValue: "Cancel", comment: "Cancel button of a sheet.")
    }

    static var save: String {
        String(localized: "plan.save", defaultValue: "Save", comment: "Save button of a sheet.")
    }

    // MARK: Rows

    static var emptySlot: String {
        String(localized: "C-064", defaultValue: "No safe recipe for this meal yet.", comment: "Row text of a meal with no safe recipe (AC-4.4).")
    }

    static var emptySlotWhyButton: String {
        String(localized: "C-064.why", defaultValue: "Why?", comment: "Button that explains an empty meal slot.")
    }

    static var emptySlotWhy: String {
        String(localized: "C-064.body", defaultValue: "None of my recipes fit everyone's must-avoid list for this meal. You could mark someone as not eating, or plan this one yourself.", comment: "Explanation of an empty meal slot (AC-4.4).")
    }

    static var locked: String {
        String(localized: "C-075.locked", defaultValue: "Locked", comment: "Label of a locked meal.")
    }

    static var lockedValue: String {
        String(localized: "C-075.value", defaultValue: "Locked, stays when you regenerate", comment: "VoiceOver value of a locked meal.")
    }

    static var lock: String {
        String(localized: "C-075.lock", defaultValue: "Lock", comment: "Lock a meal.")
    }

    static var unlock: String {
        String(localized: "C-075.unlock", defaultValue: "Unlock", comment: "Unlock a meal.")
    }

    static var swap: String {
        String(localized: "plan.swap", defaultValue: "Swap", comment: "Swap a meal (row action and meal detail button).")
    }

    static var open: String {
        String(localized: "plan.open", defaultValue: "Open", comment: "Context menu item that opens a meal.")
    }

    static var markCooked: String {
        String(localized: "C-076", defaultValue: "Mark cooked", comment: "Mark cooked button.")
    }

    static func markMealCooked(_ meal: String) -> String {
        String(localized: "C-076.meal", defaultValue: "Mark \(meal) cooked", comment: "VoiceOver label of Mark cooked. Argument is the meal name.")
    }

    static var cooked: String {
        String(localized: "C-076.cooked", defaultValue: "Cooked", comment: "Label of a meal marked cooked.")
    }

    static var draftCaption: String {
        String(localized: "C-066", defaultValue: "Approve the week to mark meals cooked.", comment: "Caption in meal detail of a draft plan.")
    }

    static var changed: String {
        String(localized: "C-079", defaultValue: "Changed", comment: "Label of a meal changed in a pending revision.")
    }

    static func approvedMeal(_ meal: String) -> String {
        String(localized: "C-079.approved", defaultValue: "Approved: \(meal)", comment: "Approved meal of a changed row. Argument is the meal name.")
    }

    static func proposedMeal(_ meal: String) -> String {
        String(localized: "C-079.proposed", defaultValue: "Proposed: \(meal)", comment: "Proposed meal of a changed row. Argument is the meal name.")
    }

    static var someone: String {
        String(localized: "plan.someone", defaultValue: "someone", comment: "Fallback for a person's name in a sentence.")
    }

    static var noRecipe: String {
        String(localized: "plan.meal.none", defaultValue: "No recipe", comment: "Meal name when a meal has no recipe.")
    }

    static func minutes(_ count: Int) -> String {
        String(localized: "plan.minutes", defaultValue: "\(count) min", comment: "Cooking time in minutes.")
    }

    // MARK: Slots and reasons (C-084)

    static func slotName(_ slot: MealSlot) -> String {
        switch slot {
        case .breakfast: return String(localized: "plan.slot.breakfast", defaultValue: "Breakfast", comment: "Meal slot name.")
        case .lunch: return String(localized: "plan.slot.lunch", defaultValue: "Lunch", comment: "Meal slot name.")
        case .dinner: return String(localized: "plan.slot.dinner", defaultValue: "Dinner", comment: "Meal slot name.")
        case .snack: return String(localized: "plan.slot.snack", defaultValue: "Snack", comment: "Meal slot name.")
        case .lunchbox: return String(localized: "plan.slot.lunchbox", defaultValue: "Lunchbox", comment: "Meal slot name for school lunchboxes.")
        }
    }

    static func reason(_ reason: ExplanationReason, ingredientName: (IngredientID) -> String?) -> String? {
        switch reason {
        case .usesYourIngredient(let id), .usesExpiringIngredient(let id):
            guard let name = ingredientName(id) else { return nil }
            return String(localized: "C-084.uses", defaultValue: "Uses your \(name)", comment: "Reason template. Argument is an ingredient name.")
        case .quickWeekday(let slot):
            let meal = slotName(slot).lowercased()
            return String(localized: "C-084.quick", defaultValue: "Quick weekday \(meal)", comment: "Reason template. Argument is the meal name.")
        case .goodForLunchboxes:
            return String(localized: "C-084.lunchbox", defaultValue: "Good for lunchboxes", comment: "Reason template.")
        case .differentFromYesterday:
            return String(localized: "C-084.different", defaultValue: "Something different from yesterday", comment: "Reason template.")
        case .cookedOften:
            return String(localized: "C-084.often", defaultValue: "You cook this often", comment: "Reason template.")
        case .cuisineYouLike:
            return String(localized: "C-084.cuisine", defaultValue: "A cuisine you like", comment: "Reason template (cuisine affinity).")
        case .repeatedFewSafeOptions:
            return String(localized: "C-084.repeated", defaultValue: "Repeated: few safe options", comment: "Reason template when variety was relaxed.")
        case .lockedMealNoLongerSafe:
            return String(localized: "C-084.unlocked", defaultValue: "Replaced because the old one was no longer safe", comment: "Reason template for a locked meal replaced for safety.")
        }
    }

    // MARK: Regenerate

    static var regenerate: String {
        String(localized: "plan.regenerate", defaultValue: "Regenerate", comment: "Toolbar button that regenerates the plan.")
    }

    static var regenerateConfirm: String {
        String(localized: "C-074", defaultValue: "Replace all unlocked meals? Locked meals stay.", comment: "Regenerate confirmation.")
    }

    static var replace: String {
        String(localized: "C-074.replace", defaultValue: "Replace", comment: "Confirm button of regenerate.")
    }

    // MARK: Safety states

    static func blockedCard(_ name: String) -> String {
        String(localized: "C-080", defaultValue: "Answer the safety question for \(name) to keep planning.", comment: "Blocked-by-safety card. Argument is a member name.")
    }

    static var answerNow: String {
        String(localized: "C-080.action", defaultValue: "Answer now", comment: "Button that reopens the safety question.")
    }

    static func blockedHint(_ name: String) -> String {
        String(localized: "C-081", defaultValue: "I can't change meals until I know what \(name) must avoid.", comment: "Shown when a disabled action is used. Argument is a member name.")
    }

    // MARK: Meal detail (S-11)

    static var whosEating: String {
        String(localized: "plan.detail.whosEating", defaultValue: "Who's eating", comment: "Section header of meal detail.")
    }

    static func portions(_ text: String) -> String {
        String(localized: "C-078", defaultValue: "\(text) portion(s)", comment: "Portion count of one person. Argument is a number.")
    }

    static var notEating: String {
        String(localized: "C-078.not", defaultValue: "Not eating", comment: "A person who is not eating this meal.")
    }

    static var ingredientsHeader: String {
        String(localized: "plan.detail.ingredients", defaultValue: "Ingredients", comment: "Section header of meal detail.")
    }

    static var stepsHeader: String {
        String(localized: "plan.detail.steps", defaultValue: "Steps", comment: "Section header of meal detail.")
    }

    // MARK: Lunchbox card (C-104) and school lunches (C-105)

    static var lunchboxPrompt: String {
        String(localized: "C-104", defaultValue: "Do any of the kids take lunch to school?", comment: "Lunchbox prompt card.")
    }

    static var yes: String {
        String(localized: "C-104.yes", defaultValue: "Yes", comment: "Lunchbox prompt answer.")
    }

    static var no: String {
        String(localized: "C-104.no", defaultValue: "No", comment: "Lunchbox prompt answer.")
    }

    static var notNow: String {
        String(localized: "C-104.notNow", defaultValue: "Not now", comment: "Lunchbox prompt answer.")
    }

    static var schoolLunches: String {
        String(localized: "C-105", defaultValue: "School lunches", comment: "School lunches sheet title.")
    }

    static var whoTakesLunch: String {
        String(localized: "C-105.who", defaultValue: "Who takes lunch to school?", comment: "School lunches sheet section.")
    }

    static var whichDays: String {
        String(localized: "C-105.days", defaultValue: "Which days?", comment: "School lunches sheet section.")
    }

    static var pickAtLeastOne: String {
        String(localized: "C-105.hint", defaultValue: "Pick at least one child and one day.", comment: "School lunches sheet caption while Save is disabled.")
    }

    static var lunchesSaved: String {
        String(localized: "plan.schoolLunches.saved", defaultValue: "School lunches saved.", comment: "Toast after saving school lunches.")
    }

    static var lunchesSavedLater: String {
        String(localized: "plan.schoolLunches.savedLater", defaultValue: "Saved. Lunchboxes are added once the safety questions are answered.", comment: "Toast after saving school lunches while the safety gate blocks planning.")
    }

    static func weekdayShort(_ day: Weekday) -> String {
        switch day {
        case .monday: return String(localized: "plan.day.mon", defaultValue: "Mon", comment: "Short weekday.")
        case .tuesday: return String(localized: "plan.day.tue", defaultValue: "Tue", comment: "Short weekday.")
        case .wednesday: return String(localized: "plan.day.wed", defaultValue: "Wed", comment: "Short weekday.")
        case .thursday: return String(localized: "plan.day.thu", defaultValue: "Thu", comment: "Short weekday.")
        case .friday: return String(localized: "plan.day.fri", defaultValue: "Fri", comment: "Short weekday.")
        case .saturday: return String(localized: "plan.day.sat", defaultValue: "Sat", comment: "Short weekday.")
        case .sunday: return String(localized: "plan.day.sun", defaultValue: "Sun", comment: "Short weekday.")
        }
    }

    // MARK: Swap sheet (S-12)

    static func swapTitle(day: String, meal: String) -> String {
        String(localized: "C-068", defaultValue: "Swap \(day) \(meal)", comment: "Swap sheet title. Arguments: day, meal name.")
    }

    static var whyChange: String {
        String(localized: "C-068.why", defaultValue: "Why change it? (optional)", comment: "Swap sheet reason header.")
    }

    static func rerollReason(_ reason: RerollReason) -> String {
        switch reason {
        case .dontFeelLikeIt: return String(localized: "C-068.dontFeel", defaultValue: "Don't feel like it", comment: "Swap reason chip.")
        case .tooLong: return String(localized: "C-068.tooLong", defaultValue: "Too long", comment: "Swap reason chip.")
        case .kidsWontEatIt: return String(localized: "C-068.kids", defaultValue: "Kids won't eat it", comment: "Swap reason chip.")
        }
    }

    static var pickOne: String {
        String(localized: "C-068.pick", defaultValue: "Pick one", comment: "Swap sheet list header.")
    }

    static var pickForMe: String {
        String(localized: "C-068.pickForMe", defaultValue: "Pick for me", comment: "Swap sheet re-roll button.")
    }

    static var swapEmpty: String {
        String(localized: "C-067", defaultValue: "No other safe recipe for this meal. Try changing who's eating.", comment: "Swap sheet empty state.")
    }

    static var swappedNeedsApproval: String {
        String(localized: "C-069", defaultValue: "Swapped. Changes need your approval.", comment: "Toast after editing an approved plan.")
    }

    // MARK: Approval diff sheet (S-13)

    static func approveChangesTitle(_ count: Int) -> String {
        String(localized: "C-070a", defaultValue: "Approve \(count) changes?", comment: "Approval diff sheet title.")
    }

    static var approveChangesQuestion: String {
        String(localized: "C-070a.question", defaultValue: "Approve changes?", comment: "Approval sheet title when only locks changed.")
    }

    static func diffHeader(day: String, meal: String) -> String {
        String(localized: "C-070a.header", defaultValue: "\(day) · \(meal)", comment: "Approval diff section header. Arguments: day, meal slot.")
    }

    static var everythingElse: String {
        String(localized: "C-070a.rest", defaultValue: "Everything else stays as approved.", comment: "Approval diff sheet subtitle.")
    }

    static func was(_ meal: String) -> String {
        String(localized: "C-070a.was", defaultValue: "Was: \(meal)", comment: "Approval diff, old meal.")
    }

    static func now(_ meal: String) -> String {
        String(localized: "C-070a.now", defaultValue: "Now: \(meal)", comment: "Approval diff, new meal.")
    }

    static var approveChanges: String {
        String(localized: "C-070a.approve", defaultValue: "Approve changes", comment: "Approval diff sheet primary button.")
    }

    static var discardChanges: String {
        String(localized: "C-070a.discard", defaultValue: "Discard changes", comment: "Approval diff sheet destructive button.")
    }

    static var notYet: String {
        String(localized: "C-070a.notYet", defaultValue: "Not yet", comment: "Approval diff sheet dismiss button.")
    }

    static var safetyCheckPassed: String {
        String(localized: "C-070c", defaultValue: "Safety check passed for everyone", comment: "Approval sheet validator result.")
    }

    static var nowEmpty: String {
        String(localized: "C-070b.empty", defaultValue: "Now empty: no safe recipe", comment: "Approval diff, slot emptied.")
    }

    static var removedSlot: String {
        String(localized: "C-070b.removed", defaultValue: "Removed", comment: "Approval diff, slot removed.")
    }

    static var addedSlot: String {
        String(localized: "C-070b.added", defaultValue: "Added", comment: "Approval diff, slot added.")
    }

    static var portionsChanged: String {
        String(localized: "C-070b.portions", defaultValue: "Portions changed", comment: "Approval diff, servings changed.")
    }

    static var discardConfirmTitle: String {
        String(localized: "C-073", defaultValue: "Discard your changes? Your approved plan stays as it is.", comment: "Discard confirmation.")
    }

    static var discard: String {
        String(localized: "C-073.discard", defaultValue: "Discard", comment: "Discard confirm button.")
    }

    static var keepEditing: String {
        String(localized: "C-073.keep", defaultValue: "Keep editing", comment: "Discard cancel button.")
    }
}
