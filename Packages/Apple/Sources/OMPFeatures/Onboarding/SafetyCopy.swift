import Foundation
import OMPDomain

/// Copy for onboarding and the safety screens, keyed by the ids in docs/design/copy.md.
/// `nonisolated` so view-model tests can read them off the main actor.
enum SafetyCopy {
    // MARK: S-01
    nonisolated static var whoTitle: String {
        String(localized: "C-010", defaultValue: "Who's eating?", comment: "S-01 title.")
    }
    nonisolated static var whoSubtitle: String {
        String(localized: "C-011", defaultValue: "No names needed. You can add them later.", comment: "S-01 subtitle.")
    }
    nonisolated static var adults: String {
        String(localized: "C-011b.adults", defaultValue: "Adults", comment: "S-01 stepper label.")
    }
    nonisolated static var children: String {
        String(localized: "C-011b.children", defaultValue: "Children", comment: "S-01 stepper label.")
    }
    nonisolated static var teensNote: String {
        String(localized: "C-011c", defaultValue: "Teens count as adults for portions.", comment: "S-01 footnote.")
    }
    nonisolated static var addOnePerson: String {
        String(localized: "C-012", defaultValue: "Add at least one person.", comment: "S-01 invalid footnote.")
    }
    nonisolated static var maxPeople: String {
        String(
            localized: "C-013", defaultValue: "That's the most I can plan for right now (12).",
            comment: "S-01 footnote at the household cap.")
    }
    nonisolated static var continueButton: String {
        String(localized: "C-014", defaultValue: "Continue", comment: "Continue button.")
    }

    // MARK: S-02
    nonisolated static var safetyTitle: String {
        String(
            localized: "C-020", defaultValue: "Does anyone have an allergy or something they must avoid?",
            comment: "S-02 title.")
    }
    nonisolated static var reason: String {
        String(
            localized: "C-021",
            defaultValue: "I'll never put these in a plan, so I need to know before I suggest anything.",
            comment: "One-sentence reason on the safety question.")
    }
    nonisolated static var noNobody: String {
        String(localized: "C-022", defaultValue: "No, nobody", comment: "S-02 primary button.")
    }
    nonisolated static var noNobodyVoiceOver: String {
        String(
            localized: "C-022a", defaultValue: "No, nobody has allergies or foods to avoid",
            comment: "VoiceOver label for the S-02 primary button.")
    }
    nonisolated static var orTellMe: String {
        String(localized: "C-023", defaultValue: "or tell me what to avoid", comment: "S-02 divider.")
    }
    nonisolated static var placeholder: String {
        String(
            localized: "C-023a", defaultValue: "e.g. no beef, one of us can't have nuts",
            comment: "S-02 text field placeholder.")
    }
    nonisolated static var toAvoid: String {
        String(localized: "C-023c", defaultValue: "To avoid", comment: "S-02 list header.")
    }
    nonisolated static var who: String {
        String(localized: "C-023d.who", defaultValue: "Who?", comment: "S-02 Who? menu label.")
    }
    nonisolated static var notSureWho: String {
        String(
            localized: "C-023d.everyone", defaultValue: "Not sure who (everyone)",
            comment: "S-02 Who? menu default: applies to everyone.")
    }
    nonisolated static var speak: String {
        String(localized: "C-123.speak", defaultValue: "Speak", comment: "Mic button label.")
    }
    nonisolated static func unrecognised(_ text: String) -> String {
        String(
            localized: "C-024",
            defaultValue: "I can't check recipes for \u{201C}\(text)\u{201D} yet. Pick the closest match, or remove it and check recipes yourself.",
            comment: "S-02 unrecognised item. %@ is what the user typed.")
    }
    nonisolated static var pickClosest: String {
        String(localized: "C-024a.pick", defaultValue: "Pick closest match", comment: "Unrecognised item button.")
    }
    nonisolated static var remove: String {
        String(localized: "C-024a.remove", defaultValue: "Remove", comment: "Remove button.")
    }
    nonisolated static var sortOutItem: String {
        String(
            localized: "C-025", defaultValue: "Sort out the item above to continue.",
            comment: "Continue disabled hint.")
    }
    nonisolated static var removeToChooseNobody: String {
        String(
            localized: "C-026",
            defaultValue: "You've added things to avoid. Remove them to choose \u{201C}No, nobody\u{201D}.",
            comment: "No, nobody disabled hint.")
    }
    nonisolated static var checkTitle: String {
        String(localized: "C-027", defaultValue: "Check this is right", comment: "S-02b title.")
    }
    nonisolated static var everyone: String {
        String(localized: "C-027a.everyone", defaultValue: "Everyone", comment: "S-02b row label.")
    }
    nonisolated static var everyoneElse: String {
        String(localized: "C-027a.else", defaultValue: "Everyone else", comment: "S-02b row label.")
    }
    nonisolated static var nothingToAvoid: String {
        String(localized: "C-027a.none", defaultValue: "Nothing to avoid", comment: "S-02b row value.")
    }
    nonisolated static var yesSave: String {
        String(localized: "C-027b.save", defaultValue: "Yes, save this", comment: "S-02b primary button.")
    }
    nonisolated static var change: String {
        String(localized: "C-027b.change", defaultValue: "Change", comment: "S-02b secondary button.")
    }

    // MARK: Gate cover variant
    nonisolated static var noNothing: String {
        String(localized: "C-031", defaultValue: "No, nothing", comment: "Gate cover primary button.")
    }
    nonisolated static func noNothingVoiceOver(_ name: String) -> String {
        String(
            localized: "C-031a", defaultValue: "No, \(name) has nothing to avoid",
            comment: "VoiceOver label for the gate cover primary button. %@ is the member name.")
    }
    nonisolated static func removeMember(_ name: String) -> String {
        String(
            localized: "C-033", defaultValue: "Added by mistake? Remove \(name)",
            comment: "Gate escape. %@ is the member name.")
    }
    nonisolated static func confirmRemoveTitle(_ name: String) -> String {
        String(localized: "C-034", defaultValue: "Remove \(name)?", comment: "Confirm remove alert title.")
    }
    nonisolated static var cancel: String {
        String(localized: "C-034.cancel", defaultValue: "Cancel", comment: "Cancel button.")
    }

    // MARK: S-03
    nonisolated static var cuisineTitle: String {
        String(localized: "C-035", defaultValue: "What do you usually cook?", comment: "S-03 title.")
    }
    nonisolated static var cuisineSubtitle: String {
        String(
            localized: "C-035a", defaultValue: "Pick a few, or skip. I'll learn as we go.",
            comment: "S-03 subtitle.")
    }
    nonisolated static var skip: String {
        String(localized: "C-035c.skip", defaultValue: "Skip", comment: "S-03 skip button.")
    }
    nonisolated static var makeMyPlan: String {
        String(localized: "C-035c.make", defaultValue: "Make my plan", comment: "S-03 primary button.")
    }
    nonisolated static var back: String {
        String(localized: "onboarding.back", defaultValue: "Back", comment: "Back button in onboarding.")
    }

    // MARK: S-04 and errors
    nonisolated static var planning: String {
        String(localized: "C-050", defaultValue: "Planning your week\u{2026}", comment: "S-04 loading.")
    }
    nonisolated static var stillWorking: String {
        String(localized: "C-051", defaultValue: "Still working\u{2026}", comment: "S-04 slow loading.")
    }
    nonisolated static var planError: String {
        String(
            localized: "C-052", defaultValue: "I couldn't make a plan just now. Please try again.",
            comment: "S-04 error.")
    }
    nonisolated static var tryAgain: String {
        String(localized: "C-052.retry", defaultValue: "Try again", comment: "Retry button.")
    }
    nonisolated static var saveFailed: String {
        String(
            localized: "C-095",
            defaultValue: "Something went wrong saving that. Your other information is safe. Please try again.",
            comment: "Save failed alert.")
    }
    nonisolated static var voicePermissionDenied: String {
        String(
            localized: "C-134",
            defaultValue: "Voice is off for OffMyPlate. To speak your pantry, turn on Microphone and Speech Recognition in Settings. You can always type instead.",
            comment: "Voice permission denied.")
    }
    nonisolated static var voiceUnavailable: String {
        String(
            localized: "C-135", defaultValue: "Voice isn't available on this device right now. You can type instead.",
            comment: "Voice unavailable.")
    }
    nonisolated static var openSettings: String {
        String(localized: "C-134.settings", defaultValue: "Open Settings", comment: "Open Settings button.")
    }
    nonisolated static var typeInstead: String {
        String(localized: "C-135.type", defaultValue: "Type instead", comment: "Type instead button.")
    }
    nonisolated static var listening: String {
        String(localized: "C-130.listening", defaultValue: "Listening\u{2026}", comment: "Listening state.")
    }
    nonisolated static var done: String {
        String(localized: "C-130.done", defaultValue: "Done", comment: "Stop listening button.")
    }
    nonisolated static func progress(index: Int, total: Int) -> String {
        String(localized: "C-030a", defaultValue: "\(index) of \(total)", comment: "Progress text.")
    }

    // MARK: Labels

    /// The chip / row label of a catalog restriction (C-023b). Unknown ids fall back to the
    /// catalog's own label key so a new catalog entry is shown, never hidden.
    nonisolated static func label(for restriction: Restriction) -> String {
        switch restriction.id.rawValue {
        case "peanuts": return String(localized: "restriction.peanuts", defaultValue: "Peanuts")
        case "tree-nuts": return String(localized: "restriction.treeNuts", defaultValue: "Tree nuts")
        case "milk": return String(localized: "restriction.milk", defaultValue: "Dairy/milk")
        case "egg": return String(localized: "restriction.egg", defaultValue: "Egg")
        case "wheat-gluten": return String(localized: "restriction.wheatGluten", defaultValue: "Wheat/gluten")
        case "soy": return String(localized: "restriction.soy", defaultValue: "Soy")
        case "sesame": return String(localized: "restriction.sesame", defaultValue: "Sesame")
        case "mustard": return String(localized: "restriction.mustard", defaultValue: "Mustard")
        case "fish": return String(localized: "restriction.fish", defaultValue: "Fish")
        case "shellfish": return String(localized: "restriction.shellfish", defaultValue: "Shellfish")
        case "beef": return String(localized: "restriction.beef", defaultValue: "Beef")
        case "pork": return String(localized: "restriction.pork", defaultValue: "Pork")
        case "vegetarian": return String(localized: "restriction.vegetarian", defaultValue: "Vegetarian")
        case "jain":
            return String(
                localized: "restriction.jain", defaultValue: "Jain (no onion, garlic, root veg)")
        default: return String(localized: String.LocalizationValue(restriction.labelKey))
        }
    }
}
