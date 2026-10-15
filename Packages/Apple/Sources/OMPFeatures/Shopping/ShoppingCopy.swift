import Foundation
import OMPDomain

/// Every user-facing string of the List tab (S-25), keyed by copy id from docs/design/copy.md
/// section 7. Strings without a copy id use a `shopping.*` key.
enum ShoppingCopy {
    static var title: String {
        String(localized: "C-144", defaultValue: "Shopping list", comment: "List tab navigation title (S-25).")
    }

    static func forRange(_ range: String) -> String {
        String(localized: "C-144.range", defaultValue: "For \(range)", comment: "Week the list is for; argument is a date range.")
    }

    static var checkYouHave: String {
        String(localized: "C-144.check", defaultValue: "Check you have", comment: "Section of items the pantry probably covers.")
    }

    static var noPlan: String {
        String(localized: "C-140", defaultValue: "Approve your plan to build your list", comment: "No approved plan (S-25).")
    }

    static var goToPlan: String {
        String(localized: "C-140.action", defaultValue: "Go to plan", comment: "Button on the no-plan card that opens the Plan tab.")
    }

    static var nothingToBuy: String {
        String(localized: "C-141", defaultValue: "You have everything for this week.", comment: "Nothing to buy.")
    }

    static var pendingChanges: String {
        String(
            localized: "C-142", defaultValue: "This list is from your approved plan. Approve your changes to update it.",
            comment: "Banner while a plan revision is waiting for approval.")
    }

    static func boughtConfirm(_ count: Int) -> String {
        String(localized: "C-143", defaultValue: "Add \(count) checked items to your pantry?", comment: "Bought everything confirmation; argument is the number of checked items.")
    }

    static var addToPantry: String {
        String(localized: "C-143.confirm", defaultValue: "Add to pantry", comment: "Confirms Bought everything.")
    }

    static var cancel: String {
        String(localized: "C-143.cancel", defaultValue: "Cancel", comment: "Cancels Bought everything.")
    }

    static var haveIt: String {
        String(localized: "C-145.have", defaultValue: "I have it", comment: "Check you have: the user has this at home.")
    }

    static var needIt: String {
        String(localized: "C-145.need", defaultValue: "Need it", comment: "Check you have: the user needs this.")
    }

    static var addField: String {
        String(localized: "C-146", defaultValue: "Add an item", comment: "Placeholder of the add field.")
    }

    static var fromNotes: String {
        String(localized: "C-147", defaultValue: "from Notes", comment: "Origin label of an imported item.")
    }

    static var boughtEverything: String {
        String(localized: "C-149.bought", defaultValue: "Bought everything", comment: "Button and menu item.")
    }

    static var clearChecked: String {
        String(localized: "C-149.clear", defaultValue: "Clear checked items", comment: "Menu item that unchecks every checked item.")
    }

    static var share: String {
        String(localized: "shopping.share", defaultValue: "Share", comment: "Share the list as text.")
    }

    static var menu: String {
        String(localized: "shopping.menu", defaultValue: "More options", comment: "VoiceOver label of the list menu.")
    }

    static var loading: String {
        String(localized: "shopping.loading", defaultValue: "Loading your list…", comment: "Shown while the list loads.")
    }

    static var saveFailed: String {
        String(
            localized: "C-095",
            defaultValue: "Something went wrong saving that. Your other information is safe. Please try again.",
            comment: "Save failed on any screen.")
    }

    static var tryAgain: String {
        String(localized: "shopping.retry", defaultValue: "Try again", comment: "Retry button on the list error card.")
    }

    static var checked: String {
        String(localized: "shopping.checked", defaultValue: "Checked", comment: "VoiceOver value of a checked item.")
    }

    static var notChecked: String {
        String(localized: "shopping.notChecked", defaultValue: "Not checked", comment: "VoiceOver value of an unchecked item.")
    }

    static var remove: String {
        String(localized: "shopping.remove", defaultValue: "Remove", comment: "Swipe action that removes a manual or imported item.")
    }

    static func aisle(_ aisle: Aisle) -> String {
        switch aisle {
        case .vegetablesAndFruit:
            return String(localized: "C-144.veg", defaultValue: "Vegetables & fruit", comment: "Aisle header.")
        case .dairyAndEggs:
            return String(localized: "C-144.dairy", defaultValue: "Dairy & eggs", comment: "Aisle header.")
        case .grainsAndFlours:
            return String(localized: "C-144.grains", defaultValue: "Grains & flours", comment: "Aisle header.")
        case .pulsesAndLentils:
            return String(localized: "C-144.pulses", defaultValue: "Pulses & lentils", comment: "Aisle header.")
        case .spicesAndMasalas:
            return String(localized: "C-144.spices", defaultValue: "Spices & masalas", comment: "Aisle header.")
        case .oilsAndGhee:
            return String(localized: "C-144.oils", defaultValue: "Oils & ghee", comment: "Aisle header.")
        case .meatAndFish:
            return String(localized: "C-144.meat", defaultValue: "Meat & fish", comment: "Aisle header.")
        case .bakery:
            return String(localized: "C-144.bakery", defaultValue: "Bakery", comment: "Aisle header.")
        case .other:
            return String(localized: "C-144.other", defaultValue: "Other", comment: "Aisle header.")
        }
    }
}
