import Foundation
import OMPDomain

/// Every user-facing string of the Pantry screens (S-20 to S-23) and the cooked sheet (S-15),
/// keyed by copy id from docs/design/copy.md. Strings without a copy id yet use a `pantry.*`
/// key; they are listed in the T24 hand-off for the ux-designer to number.
enum PantryCopy {
    // MARK: Shared

    static var title: String {
        String(localized: "pantry.title", defaultValue: "Pantry", comment: "Pantry tab navigation title (S-20).")
    }

    static var cancel: String {
        String(localized: "pantry.cancel", defaultValue: "Cancel", comment: "Cancel button on pantry sheets.")
    }

    static var save: String {
        String(localized: "pantry.save", defaultValue: "Save", comment: "Save button of the add/edit item sheet.")
    }

    static var tryAgain: String {
        String(localized: "pantry.tryAgain", defaultValue: "Try again", comment: "Retry button on the pantry error card.")
    }

    static var saveFailed: String {
        String(localized: "C-095", defaultValue: "Something went wrong saving that. Your other information is safe. Please try again.", comment: "Save failed on any screen.")
    }

    static var loadFailed: String {
        String(localized: "pantry.loadFailed", defaultValue: "I couldn't load your pantry. Please try again.", comment: "Pantry could not be loaded.")
    }

    static var loading: String {
        String(localized: "pantry.loading", defaultValue: "Loading your pantry…", comment: "Pantry loading text.")
    }

    // MARK: S-20

    static var speak: String {
        String(localized: "C-123.speak", defaultValue: "Speak", comment: "Mic button: speak to the pantry.")
    }

    static var addItem: String {
        String(localized: "C-126.add", defaultValue: "Add item", comment: "Add item button and add form title.")
    }

    static var editItem: String {
        String(localized: "C-126.edit", defaultValue: "Edit item", comment: "Edit item form title.")
    }

    static var search: String {
        String(localized: "pantry.search", defaultValue: "Search", comment: "Pantry search field prompt.")
    }

    static var clearSearch: String {
        String(localized: "pantry.search.clear", defaultValue: "Clear search", comment: "VoiceOver label of the clear button in the pantry search field.")
    }

    static var emptyTitle: String {
        String(localized: "C-122", defaultValue: "Your pantry is empty", comment: "Empty pantry title.")
    }

    static var emptyBody: String {
        String(localized: "C-123", defaultValue: "Add what you have, or say it: “I bought 2 kg rice.”", comment: "Empty pantry body.")
    }

    static func noResults(_ text: String) -> String {
        String(localized: "C-124", defaultValue: "Nothing called “\(text)” in your pantry.", comment: "Pantry search with no result. Argument is the search text.")
    }

    static var stale: String {
        String(localized: "C-120", defaultValue: "Not checked in a while", comment: "Pantry item not re-confirmed for a while.")
    }

    static var stillHaveIt: String {
        String(localized: "C-120.action", defaultValue: "Still have it", comment: "Button that re-confirms a stale pantry item.")
    }

    static var notRecognised: String {
        String(localized: "C-121", defaultValue: "Not recognised", comment: "Pantry item typed as free text.")
    }

    static var matchIt: String {
        String(localized: "C-121.action", defaultValue: "Match it", comment: "Button that matches a free-text pantry item to an ingredient.")
    }

    static var delete: String {
        String(localized: "pantry.delete", defaultValue: "Delete", comment: "Swipe action that deletes a pantry item.")
    }

    static var pastUseBy: String {
        String(localized: "C-127.past", defaultValue: "Past use-by date", comment: "Pantry item whose use-by date has passed.")
    }

    static func useByWeekday(_ weekday: String) -> String {
        String(localized: "C-127.weekday", defaultValue: "Use by \(weekday)", comment: "Use-by within the week. Argument is the weekday name.")
    }

    static func useByDate(_ date: String) -> String {
        String(localized: "C-127.date", defaultValue: "Use by \(date)", comment: "Use-by later than a week. Argument is a short date.")
    }

    static func location(_ location: StorageLocation) -> String {
        switch location {
        case .fridge: return String(localized: "C-126.fridge", defaultValue: "Fridge", comment: "Storage location.")
        case .freezer: return String(localized: "C-126.freezer", defaultValue: "Freezer", comment: "Storage location.")
        case .shelf: return String(localized: "C-126.shelf", defaultValue: "Shelf", comment: "Storage location.")
        }
    }

    // MARK: S-21

    static var name: String {
        String(localized: "C-126.name", defaultValue: "Name", comment: "Form label.")
    }

    static var namePrompt: String {
        String(localized: "pantry.namePrompt", defaultValue: "Search ingredients…", comment: "Placeholder of the name field.")
    }

    static var amount: String {
        String(localized: "C-126.amount", defaultValue: "Amount", comment: "Form label.")
    }

    static var unit: String {
        String(localized: "C-126.unit", defaultValue: "Unit", comment: "Form label.")
    }

    static var whereLabel: String {
        String(localized: "C-126.where", defaultValue: "Where", comment: "Form label: where it is stored.")
    }

    static var useByDateLabel: String {
        String(localized: "C-126.useBy", defaultValue: "Use-by date", comment: "Form label.")
    }

    static var deleteItem: String {
        String(localized: "C-126.delete", defaultValue: "Delete item", comment: "Delete button on the edit form.")
    }

    static func addAsTyped(_ text: String) -> String {
        String(localized: "C-125", defaultValue: "Add “\(text)” as typed", comment: "Suggestion that keeps the typed name. Argument is the text.")
    }

    static var addAsTypedNote: String {
        String(localized: "C-125.note", defaultValue: "I won't count it toward your plan until it's matched to an ingredient.", comment: "Note under the add-as-typed suggestion.")
    }

    static func youSaid(_ transcript: String) -> String {
        String(localized: "C-133", defaultValue: "You said: “\(transcript)”", comment: "Caption on a form prefilled from voice. Argument is the transcript.")
    }

    static var saveNeedsAmount: String {
        String(localized: "pantry.saveNeeds", defaultValue: "Add a name and an amount to save.", comment: "Caption that explains why Save is off.")
    }

    // MARK: S-22 and S-23

    static var listening: String {
        String(localized: "C-130", defaultValue: "Listening…", comment: "Voice listening state.")
    }

    static var listeningHint: String {
        String(localized: "C-130.hint", defaultValue: "Try: “I bought 1 kg onions”, “we're out of milk”", comment: "Voice examples.")
    }

    static var done: String {
        String(localized: "C-130.done", defaultValue: "Done", comment: "Stops listening.")
    }

    static var confirmTitle: String {
        String(localized: "C-130a", defaultValue: "Add these?", comment: "Voice confirm card title.")
    }

    static func addItems(_ count: Int) -> String {
        String(localized: "C-130a.add", defaultValue: "Add \(count) items", comment: "Confirm button. Argument is the number of items.")
    }

    static var addOneItem: String {
        String(localized: "C-130a.addOne", defaultValue: "Add 1 item", comment: "Confirm button for one item.")
    }

    static var updatePantry: String {
        String(localized: "C-130a.update", defaultValue: "Update pantry", comment: "Confirm button when the commands only change existing items.")
    }

    static func removeFromPantry(_ item: String) -> String {
        String(localized: "C-130a.remove", defaultValue: "Remove \(item) from pantry", comment: "Voice confirm row. Argument is the item.")
    }

    static func setToZero(_ item: String) -> String {
        String(localized: "C-130a.zero", defaultValue: "Set \(item) to 0", comment: "Voice confirm row. Argument is the item.")
    }

    static func didntCatch(_ text: String) -> String {
        String(localized: "C-130b", defaultValue: "I didn't catch: “\(text)”", comment: "Voice partial result. Argument is the unparsed text.")
    }

    static var addByHand: String {
        String(localized: "C-130b.action", defaultValue: "Add it by hand", comment: "Opens the form prefilled with the unparsed text.")
    }

    static func nothingUnderstood(_ transcript: String) -> String {
        String(localized: "C-131", defaultValue: "I didn't catch any items. Here's what I heard: “\(transcript)”", comment: "Voice found nothing. Argument is the transcript.")
    }

    static var nothingHeard: String {
        String(localized: "C-131.empty", defaultValue: "I didn't catch any items.", comment: "Voice found nothing and there is no transcript.")
    }

    static var tryAgainVoice: String {
        String(localized: "C-131.retry", defaultValue: "Try again", comment: "Listen again.")
    }

    static var typeInstead: String {
        String(localized: "C-131.type", defaultValue: "Type it instead", comment: "Opens the add form.")
    }

    static var typeInsteadShort: String {
        String(localized: "C-134.type", defaultValue: "Type instead", comment: "Opens the add form from the voice-unavailable sheet.")
    }

    static var interrupted: String {
        String(localized: "C-132", defaultValue: "Stopped listening.", comment: "Listening was interrupted.")
    }

    static var voiceDenied: String {
        String(localized: "C-134", defaultValue: "Voice is off for OffMyPlate. To speak your pantry, turn on Microphone and Speech Recognition in Settings. You can always type instead.", comment: "Speech or microphone permission denied.")
    }

    static var openSettings: String {
        String(localized: "C-134.settings", defaultValue: "Open Settings", comment: "Opens the system Settings app.")
    }

    static var voiceUnavailable: String {
        String(localized: "C-135", defaultValue: "Voice isn't available on this device right now. You can type instead.", comment: "Speech unsupported or unavailable.")
    }

    static func voiceAdded(_ count: Int) -> String {
        String(localized: "pantry.voiceDone", defaultValue: "Updated your pantry (\(count)).", comment: "Toast after confirming voice. Argument is the number of changes.")
    }

    static var skip: String {
        String(localized: "pantry.voice.skip", defaultValue: "Skip this one", comment: "Drops one item from the voice confirm card.")
    }

    static var edit: String {
        String(localized: "pantry.voice.edit", defaultValue: "Edit", comment: "Edit one item on the voice confirm card.")
    }

    static var notUnderstoodEdit: String {
        String(localized: "pantry.notSure", defaultValue: "Check this one", comment: "Shown when the voice match is not confident.")
    }

    static func rowAmountLabel(_ name: String, _ amount: String) -> String {
        String(localized: "pantry.row.label", defaultValue: "\(name), \(amount)", comment: "VoiceOver label of a pantry row: name, amount.")
    }

    // MARK: S-15

    static func cookedTitle(_ meal: String) -> String {
        String(localized: "C-077", defaultValue: "Cooked \(meal)?", comment: "Cooked sheet title. Argument is the meal name.")
    }

    static var cookedIntro: String {
        String(localized: "C-077.intro", defaultValue: "I'll take these out of your pantry.", comment: "Cooked sheet explanation.")
    }

    static func usedOf(_ used: String, _ have: String) -> String {
        String(localized: "C-077.of", defaultValue: "\(used) of \(have)", comment: "Cooked sheet line: amount used of amount in the pantry.")
    }

    static var updatePantryCooked: String {
        String(localized: "C-077.update", defaultValue: "Update pantry", comment: "Cooked sheet confirm button.")
    }

    static var willBeZero: String {
        String(localized: "C-077.zero", defaultValue: "Will be 0", comment: "Cooked sheet: the pantry item runs out.")
    }

    static var notInPantry: String {
        String(localized: "C-077.none", defaultValue: "Not in your pantry", comment: "Cooked sheet: ingredient has no pantry item.")
    }

    static var doneEditing: String {
        String(localized: "pantry.cooked.doneEditing", defaultValue: "Done", comment: "Finish editing a cooked sheet amount.")
    }

    static func editLabel(_ name: String) -> String {
        String(localized: "pantry.cooked.editLabel", defaultValue: "Edit amount of \(name)", comment: "VoiceOver label of the edit button. Argument is the ingredient.")
    }

    static func less(_ name: String) -> String {
        String(localized: "pantry.cooked.less", defaultValue: "Use less \(name)", comment: "VoiceOver label of the minus button. Argument is the ingredient.")
    }

    static func more(_ name: String) -> String {
        String(localized: "pantry.cooked.more", defaultValue: "Use more \(name)", comment: "VoiceOver label of the plus button. Argument is the ingredient.")
    }

    static var noIngredients: String {
        String(localized: "pantry.cooked.none", defaultValue: "This meal has nothing to take out of your pantry.", comment: "Cooked sheet for a meal without measurable ingredients.")
    }

    static var notApproved: String {
        String(localized: "pantry.cooked.notApproved", defaultValue: "Approve the week to mark meals cooked.", comment: "Mark cooked refused because the plan is not approved (same text as C-066).")
    }

    static var alreadyCooked: String {
        String(localized: "pantry.cooked.already", defaultValue: "This meal is already marked cooked.", comment: "Mark cooked refused because the meal was already cooked.")
    }

    static var cookedDone: String {
        String(localized: "pantry.cooked.done", defaultValue: "Pantry updated.", comment: "Toast after Mark cooked.")
    }
}
