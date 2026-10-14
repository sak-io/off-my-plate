import Foundation
import OMPDomain

/// Copy for the Household tab, "What I've learned", the reflect-back card, the 180-day card and
/// About (S-30 to S-37), keyed by the ids in docs/design/copy.md. `nonisolated` so view-model
/// tests can read them off the main actor.
enum SettingsCopy {
    // MARK: S-30 Household (C-110)
    nonisolated static var householdTitle: String {
        String(localized: "C-110.title", defaultValue: "Household", comment: "S-30 title.")
    }
    nonisolated static var people: String {
        String(localized: "C-110.people", defaultValue: "People", comment: "S-30 section header.")
    }
    nonisolated static var addPerson: String {
        String(localized: "C-110.add", defaultValue: "Add person", comment: "S-30 button.")
    }
    nonisolated static var safety: String {
        String(localized: "C-110.safety", defaultValue: "Safety", comment: "S-30 section header.")
    }
    nonisolated static var yourPlan: String {
        String(localized: "C-110.plan", defaultValue: "Your plan", comment: "S-30 section header.")
    }
    nonisolated static var about: String {
        String(localized: "C-110.about", defaultValue: "About", comment: "S-30 section header.")
    }
    nonisolated static var allergiesRow: String {
        String(
            localized: "C-038", defaultValue: "Allergies & must-avoid foods",
            comment: "S-33 title and the S-30 row that opens it.")
    }
    nonisolated static var learnedRow: String {
        String(localized: "C-150.title", defaultValue: "What I've learned", comment: "S-35 title and the S-30 row.")
    }
    nonisolated static var aboutRow: String {
        String(
            localized: "C-110.aboutRow", defaultValue: "About, privacy & medical note",
            comment: "S-30 row that opens S-37.")
    }
    nonisolated static var deleteAllRow: String {
        String(localized: "C-161.row", defaultValue: "Delete all data", comment: "S-30 destructive row.")
    }

    // MARK: Member status (C-110a)
    nonisolated static var statusNothing: String {
        String(localized: "C-110a.none", defaultValue: "Nothing to avoid", comment: "Member status.")
    }
    nonisolated static func statusAvoids(_ items: String) -> String {
        String(localized: "C-110a.avoids", defaultValue: "Avoids \(items)", comment: "Member status. %@ is a list.")
    }
    nonisolated static var statusNotAnswered: String {
        String(localized: "C-110a.unanswered", defaultValue: "Not answered yet", comment: "Member status.")
    }

    // MARK: S-31 Person form (C-112, C-034b)
    nonisolated static var addPersonTitle: String {
        String(localized: "C-112.addTitle", defaultValue: "Add person", comment: "S-31 title when adding.")
    }
    nonisolated static var editPersonTitle: String {
        String(localized: "C-112.editTitle", defaultValue: "Person", comment: "S-31 title when editing.")
    }
    nonisolated static var nameOptional: String {
        String(localized: "C-112.name", defaultValue: "Name (optional)", comment: "S-31 field.")
    }
    nonisolated static var ageGroupOptional: String {
        String(localized: "C-112.age", defaultValue: "Age group (optional)", comment: "S-31 picker.")
    }
    nonisolated static var notSet: String {
        String(localized: "C-112.notSet", defaultValue: "Not set", comment: "S-31 age group not set.")
    }
    nonisolated static func ageGroup(_ band: AgeBand?) -> String {
        switch band {
        case nil: return notSet
        case .infant?: return String(localized: "C-112.infant", defaultValue: "Infant", comment: "Age group.")
        case .toddler?: return String(localized: "C-112.toddler", defaultValue: "Toddler", comment: "Age group.")
        case .child?: return String(localized: "C-112.child", defaultValue: "Child", comment: "Age group.")
        case .teen?: return String(localized: "C-112.teen", defaultValue: "Teen", comment: "Age group.")
        case .adult?: return String(localized: "C-112.adult", defaultValue: "Adult", comment: "Age group.")
        case .senior?: return String(localized: "C-112.senior", defaultValue: "Senior", comment: "Age group.")
        }
    }
    nonisolated static var removePerson: String {
        String(localized: "C-112.remove", defaultValue: "Remove person", comment: "S-31 destructive button.")
    }
    nonisolated static func confirmRemove(_ name: String) -> String {
        String(
            localized: "C-034b",
            defaultValue: "Remove \(name)? Their portions will come out of future plans.",
            comment: "Confirm remove from Household. %@ is the member name.")
    }
    nonisolated static var save: String {
        String(localized: "C-153a.save", defaultValue: "Save", comment: "Save button.")
    }
    nonisolated static var add: String {
        String(localized: "C-037.add", defaultValue: "Add", comment: "Add button.")
    }
    nonisolated static var cancel: String {
        String(localized: "C-034.cancel", defaultValue: "Cancel", comment: "Cancel button.")
    }
    nonisolated static var remove: String {
        String(localized: "C-024a.remove", defaultValue: "Remove", comment: "Remove button.")
    }
    nonisolated static var done: String {
        String(localized: "C-130.done", defaultValue: "Done", comment: "Done button.")
    }
    nonisolated static var saveFailed: String {
        String(
            localized: "C-095",
            defaultValue: "Something went wrong saving that. Your other information is safe. Please try again.",
            comment: "Save failed alert.")
    }
    nonisolated static var ok: String {
        String(localized: "settings.ok", defaultValue: "OK", comment: "Alert dismiss button.")
    }
    nonisolated static var tryAgain: String {
        String(localized: "C-052.retry", defaultValue: "Try again", comment: "Retry button.")
    }
    nonisolated static var askedAfterAdd: String {
        String(
            localized: "settings.addPerson.note",
            defaultValue: "I'll ask about allergies for them next, before planning anything.",
            comment: "S-31 note under the Add button.")
    }
    nonisolated static var ageChangeNote: String {
        String(
            localized: "settings.ageChange.note",
            defaultValue: "Changing between child and teen or adult means I'll ask about allergies again.",
            comment: "S-31 note about the safety re-check on an age group change (AC-3.4).")
    }

    // MARK: S-33 Allergies & must-avoid foods
    nonisolated static var everyone: String {
        String(localized: "C-027a.everyone", defaultValue: "Everyone", comment: "Group label.")
    }
    nonisolated static var nobodyAvoids: String {
        String(localized: "C-037", defaultValue: "Nobody has anything to avoid.", comment: "S-33 empty state.")
    }
    nonisolated static func confirmRemoveRule(item: String, name: String) -> String {
        String(
            localized: "C-036",
            defaultValue: "Remove \(item) for \(name)? Future plans may include \(item).",
            comment: "Remove a must-avoid item. First %@ is the item, second the person.")
    }
    nonisolated static var addRuleTitle: String {
        String(localized: "settings.addRule.title", defaultValue: "Add something to avoid", comment: "Add sheet title.")
    }
    nonisolated static var forWhom: String {
        String(localized: "settings.addRule.who", defaultValue: "Who is it for?", comment: "Add sheet picker label.")
    }
    nonisolated static var checkTitle: String {
        String(localized: "C-027", defaultValue: "Check this is right", comment: "Confirm step title.")
    }
    nonisolated static var yesSave: String {
        String(localized: "C-027b.save", defaultValue: "Yes, save this", comment: "Confirm step primary button.")
    }
    nonisolated static var review: String {
        String(localized: "C-014", defaultValue: "Continue", comment: "Go to the confirm step.")
    }
    nonisolated static var change: String {
        String(localized: "C-027b.change", defaultValue: "Change", comment: "Back to editing.")
    }
    nonisolated static var typeToAdd: String {
        String(
            localized: "C-023a", defaultValue: "e.g. no beef, one of us can't have nuts",
            comment: "Add sheet text field placeholder.")
    }
    nonisolated static var orTellMe: String {
        String(localized: "C-023", defaultValue: "or tell me what to avoid", comment: "Add sheet divider.")
    }
    nonisolated static func cannotCheck(_ text: String) -> String {
        String(
            localized: "C-024",
            defaultValue: "I can't check recipes for \u{201C}\(text)\u{201D} yet. Pick the closest match, or remove it and check recipes yourself.",
            comment: "Unrecognised item. %@ is what the user typed.")
    }
    nonisolated static var addText: String {
        String(localized: "settings.addRule.addText", defaultValue: "Add to list", comment: "Parses the typed text.")
    }
    nonisolated static var chosen: String {
        String(localized: "C-023c", defaultValue: "To avoid", comment: "List header.")
    }
    nonisolated static func avoidsFor(item: String, who: String) -> String {
        String(localized: "settings.addRule.line", defaultValue: "\(item): \(who)", comment: "Confirm line.")
    }

    // MARK: Safety summary (C-061) and 180-day card (C-040)
    nonisolated static func safetySummaryLine(_ summary: String) -> String {
        String(localized: "C-061", defaultValue: "Safety: \(summary).", comment: "Safety summary line on the plan.")
    }
    nonisolated static var summaryNobody: String {
        String(
            localized: "C-061.none", defaultValue: "nobody has anything to avoid",
            comment: "Safety summary when there are no rules.")
    }
    nonisolated static func summaryAvoids(who: String, items: String) -> String {
        String(localized: "C-061.avoids", defaultValue: "\(who) avoids \(items)", comment: "Safety summary part.")
    }
    nonisolated static var summaryEveryone: String {
        String(localized: "C-061.everyone", defaultValue: "everyone", comment: "Safety summary subject.")
    }
    nonisolated static var stillCorrectTitle: String {
        String(localized: "C-040", defaultValue: "Still correct?", comment: "180-day card title.")
    }
    nonisolated static func stillCorrectBody(_ summary: String) -> String {
        String(
            localized: "C-040a", defaultValue: "Here's what I avoid for your household: \(summary).",
            comment: "180-day card body. %@ is the summary.")
    }
    nonisolated static var stillCorrectNone: String {
        String(localized: "C-040b", defaultValue: "Nobody has anything to avoid.", comment: "180-day summary when none.")
    }
    nonisolated static var yesStillCorrect: String {
        String(localized: "C-040c.yes", defaultValue: "Yes, still correct", comment: "180-day card button.")
    }
    nonisolated static var makeChanges: String {
        String(localized: "C-040c.change", defaultValue: "Make changes", comment: "180-day card button.")
    }

    // MARK: Reflect-back (C-100 to C-103)
    nonisolated static func reflectQuestion(_ observation: String) -> String {
        String(
            localized: "C-100", defaultValue: "\(observation). Should I plan around that?",
            comment: "Reflect-back card. %@ is the observation.")
    }
    nonisolated static var yes: String {
        String(localized: "C-100.yes", defaultValue: "Yes", comment: "Reflect-back button.")
    }
    nonisolated static var notReally: String {
        String(localized: "C-100.no", defaultValue: "Not really", comment: "Reflect-back button.")
    }
    nonisolated static var dontAskAgain: String {
        String(localized: "C-100.never", defaultValue: "Don't ask again", comment: "Reflect-back button.")
    }
    nonisolated static func afterAnswer(_ answer: ReflectBackAnswer) -> String {
        switch answer {
        case .yes:
            return String(
                localized: "C-101", defaultValue: "Got it. You can change this in What I've learned.",
                comment: "After Yes.")
        case .notReally:
            return String(localized: "C-102", defaultValue: "Okay, I won't plan around that.", comment: "After Not really.")
        case .dontAskAgain:
            return String(
                localized: "C-103", defaultValue: "Okay, I won't ask about this again.", comment: "After Don't ask.")
        }
    }

    // MARK: S-35 What I've learned (C-150 to C-154)
    nonisolated static var learnedIntro: String {
        String(localized: "C-150", defaultValue: "These shape suggestions only.", comment: "S-35 intro.")
    }
    nonisolated static var sectionTold: String {
        String(localized: "C-150a.told", defaultValue: "You told me", comment: "S-35 section header.")
    }
    nonisolated static var sectionConfirmed: String {
        String(localized: "C-150a.confirmed", defaultValue: "You confirmed", comment: "S-35 section header.")
    }
    nonisolated static var sectionNoticed: String {
        String(localized: "C-150a.noticed", defaultValue: "I noticed", comment: "S-35 section header.")
    }
    nonisolated static var sectionGuesses: String {
        String(localized: "C-150a.guesses", defaultValue: "Starting guesses", comment: "S-35 section header.")
    }
    nonisolated static var likely: String {
        String(localized: "C-150b.likely", defaultValue: "Likely", comment: "Confidence word.")
    }
    nonisolated static var maybe: String {
        String(localized: "C-150b.maybe", defaultValue: "Maybe", comment: "Confidence word.")
    }
    nonisolated static var thatsRight: String {
        String(localized: "C-150c", defaultValue: "That's right", comment: "Quick confirm.")
    }
    nonisolated static var safetyPointer: String {
        String(
            localized: "C-151", defaultValue: "Allergies and must-avoid foods are only set by you.",
            comment: "S-35 footer pointing to S-33.")
    }
    nonisolated static var learnedEmpty: String {
        String(
            localized: "C-152",
            defaultValue: "Nothing yet. As you swap and cook, I'll note what your household likes here.",
            comment: "S-35 empty state.")
    }
    nonisolated static var forget: String {
        String(localized: "C-154.forget", defaultValue: "Forget", comment: "Forget action.")
    }
    nonisolated static var forgetThis: String {
        String(localized: "C-153a.forget", defaultValue: "Forget this", comment: "S-36 destructive button.")
    }
    nonisolated static var forgetConfirm: String {
        String(
            localized: "C-154", defaultValue: "Forget this? I'll stop using it for suggestions.",
            comment: "Forget confirmation.")
    }
    nonisolated static var loadFailed: String {
        String(localized: "C-096.learned", defaultValue: "I couldn't load that. Please try again.", comment: "Load error.")
    }

    // MARK: S-36 Fact sheet (C-153)
    nonisolated static var factTitle: String {
        String(localized: "C-153.title", defaultValue: "What I've learned", comment: "S-36 title.")
    }
    nonisolated static var whereFrom: String {
        String(localized: "C-153.where", defaultValue: "Where this came from", comment: "S-36 header.")
    }
    nonisolated static var appliesTo: String {
        String(localized: "C-153a.applies", defaultValue: "Applies to", comment: "S-36 picker.")
    }
    nonisolated static var strength: String {
        String(localized: "C-153.strength", defaultValue: "Strength", comment: "S-36 segmented label.")
    }
    nonisolated static var prefer: String {
        String(localized: "C-153a.prefer", defaultValue: "Prefer", comment: "S-36 strength.")
    }
    nonisolated static var avoidWhenPossible: String {
        String(localized: "C-153a.avoid", defaultValue: "Avoid when possible", comment: "S-36 strength.")
    }
    nonisolated static var originSaid: String {
        String(localized: "C-153.said", defaultValue: "You said this", comment: "Fact origin.")
    }
    nonisolated static var originConfirmed: String {
        String(localized: "C-153.confirmed", defaultValue: "You confirmed this", comment: "Fact origin.")
    }
    nonisolated static var originSwaps: String {
        String(localized: "C-153.swaps", defaultValue: "I noticed this from your swaps", comment: "Fact origin.")
    }
    nonisolated static var originCooked: String {
        String(
            localized: "C-153.cooked", defaultValue: "I noticed this from meals you cooked", comment: "Fact origin.")
    }
    nonisolated static var originLists: String {
        String(
            localized: "C-153.lists", defaultValue: "I noticed this from your shopping lists", comment: "Fact origin.")
    }
    nonisolated static var originDefault: String {
        String(localized: "C-153.default", defaultValue: "My starting guess", comment: "Fact origin.")
    }

    // Fact sentences (C-150 examples).
    nonisolated static func cuisine(_ id: CuisineID) -> String {
        switch id.rawValue {
        case "northIndian": return String(localized: "cuisine.northIndian", defaultValue: "North Indian")
        case "southIndian": return String(localized: "cuisine.southIndian", defaultValue: "South Indian")
        case "westIndian": return String(localized: "cuisine.westIndian", defaultValue: "Gujarati / Maharashtrian")
        case "eastIndian": return String(localized: "cuisine.eastIndian", defaultValue: "Bengali / East Indian")
        default: return id.rawValue
        }
    }
    nonisolated static func likesCuisine(_ name: String) -> String {
        String(localized: "settings.fact.cuisine", defaultValue: "You cook \(name) food", comment: "Fact sentence.")
    }
    nonisolated static func skipsRecipe(_ title: String) -> String {
        String(localized: "settings.fact.dislikesRecipe", defaultValue: "You often skip \(title)", comment: "Fact sentence.")
    }
    nonisolated static func swapsOut(_ name: String) -> String {
        String(localized: "settings.fact.dislikesIngredient", defaultValue: "You often swap out \(name)", comment: "Fact sentence.")
    }
    nonisolated static var quickWeekday: String {
        String(
            localized: "settings.fact.quick", defaultValue: "Quick dinners on weekdays", comment: "Fact sentence.")
    }
    nonisolated static func keepsStocked(_ name: String) -> String {
        String(localized: "settings.fact.staple", defaultValue: "You keep \(name) stocked", comment: "Fact sentence.")
    }
    nonisolated static func likesRecipe(_ title: String) -> String {
        String(localized: "settings.fact.favourite", defaultValue: "You like \(title)", comment: "Fact sentence.")
    }
    nonisolated static var unknownItem: String {
        String(localized: "settings.fact.unknown", defaultValue: "something", comment: "Item name not in the library.")
    }

    // MARK: S-37 About (C-092, C-160, C-161)
    nonisolated static var aboutTitle: String {
        String(localized: "C-110.aboutTitle", defaultValue: "About", comment: "S-37 title.")
    }
    nonisolated static var medicalHeader: String {
        String(localized: "C-092.header", defaultValue: "Medical note", comment: "S-37 header.")
    }
    nonisolated static var privacyHeader: String {
        String(localized: "C-160.header", defaultValue: "Privacy", comment: "S-37 header.")
    }
    nonisolated static var privacy: String {
        String(
            localized: "C-160",
            defaultValue: "Everything you tell OffMyPlate stays on this device. There's no account, and nothing is sent to us or anyone else.",
            comment: "S-37 privacy text.")
    }
    nonisolated static func version(_ value: String) -> String {
        String(localized: "settings.version", defaultValue: "Version \(value)", comment: "S-37 version line.")
    }
    nonisolated static var deleteConfirmTitle: String {
        String(
            localized: "C-161",
            defaultValue: "Delete everything? This removes your household, plans, pantry, list and everything I've learned from this device. It can't be undone.",
            comment: "Delete all data confirmation.")
    }
    nonisolated static var deleteEverything: String {
        String(localized: "C-161.confirm", defaultValue: "Delete everything", comment: "Destructive confirm button.")
    }
    nonisolated static var deleteFailed: String {
        String(
            localized: "settings.deleteFailed",
            defaultValue: "I couldn't delete everything. Nothing else changed. Please try again.",
            comment: "Delete all data failed.")
    }
}
