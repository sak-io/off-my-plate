import Foundation

/// Copy of the Share Extension (docs/design/copy.md section 9, C-169 to C-173).
enum ShareCopy {
    static var title: String {
        String(localized: "C-169.title", defaultValue: "Add to OffMyPlate", comment: "Share sheet title.")
    }
    static var cancel: String {
        String(localized: "C-169.cancel", defaultValue: "Cancel", comment: "Share sheet cancel button.")
    }
    static func add(_ count: Int) -> String {
        String(localized: "C-169.add", defaultValue: "Add \(count)", comment: "Share sheet add button with the item count.")
    }
    static var destination: String {
        String(localized: "C-169a.label", defaultValue: "Add to", comment: "Destination picker label.")
    }
    static var shoppingList: String {
        String(localized: "C-169a.list", defaultValue: "Shopping list", comment: "Destination option.")
    }
    static var pantry: String {
        String(localized: "C-169a.pantry", defaultValue: "Pantry", comment: "Destination option.")
    }
    static var unsureHeader: String {
        String(localized: "C-169b.header", defaultValue: "Not sure about these", comment: "Header of the unparsed lines.")
    }
    static var keep: String {
        String(localized: "C-169b.keep", defaultValue: "Keep", comment: "Keep an unparsed line.")
    }
    static var empty: String {
        String(localized: "C-170", defaultValue: "I couldn't find a list in this note.", comment: "No list in the note.")
    }
    static var notText: String {
        String(
            localized: "C-171", defaultValue: "I can only read text for now. Photos and PDFs aren't supported yet.",
            comment: "The shared content is not text.")
    }
    static var saved: String {
        String(
            localized: "C-172", defaultValue: "Added. You'll see them next time you open OffMyPlate.",
            comment: "Saved to the inbox.")
    }
    static var error: String {
        String(localized: "C-173", defaultValue: "Couldn't save these. Please try again.", comment: "Saving failed.")
    }
    static var close: String {
        String(localized: "share.close", defaultValue: "Close", comment: "Close the share sheet.")
    }
    // Labels the design does not spell out (accessibility and field prompts).
    static var namePrompt: String {
        String(localized: "share.row.name", defaultValue: "Item", comment: "Name field of a review row.")
    }
    static var quantityPrompt: String {
        String(localized: "share.row.quantity", defaultValue: "Amount", comment: "Quantity field of a review row.")
    }
    static var noUnit: String {
        String(localized: "share.row.noUnit", defaultValue: "No unit", comment: "Unit menu: no unit.")
    }
    static var unitPrompt: String {
        String(localized: "share.row.unit", defaultValue: "Unit", comment: "Unit menu of a review row.")
    }
    static func remove(_ name: String) -> String {
        String(localized: "share.row.remove", defaultValue: "Remove \(name)", comment: "VoiceOver label of the remove button.")
    }
    static func include(_ name: String) -> String {
        String(localized: "share.row.include", defaultValue: "Add \(name)", comment: "VoiceOver label of the row checkbox.")
    }
}
