import Foundation
import OMPUI

/// The four top-level destinations (screens.md section 1).
public enum AppTab: String, CaseIterable, Hashable, Sendable {
    case plan
    case list
    case pantry
    case household

    /// The tab's title, localized.
    public var title: String {
        switch self {
        case .plan:
            return String(localized: "shell.tab.plan", defaultValue: "Plan", comment: "Tab title: the weekly plan.")
        case .list:
            return String(
                localized: "shell.tab.list", defaultValue: "List", comment: "Tab title: the shopping list.")
        case .pantry:
            return String(
                localized: "shell.tab.pantry", defaultValue: "Pantry", comment: "Tab title: what's at home.")
        case .household:
            return String(
                localized: "shell.tab.household", defaultValue: "Household",
                comment: "Tab title: people, safety, settings (C-110).")
        }
    }

    /// The SF Symbol (design-system.md "Icons").
    public var systemImage: String {
        switch self {
        case .plan: return OMPSymbol.plan
        case .list: return OMPSymbol.list
        case .pantry: return OMPSymbol.pantry
        case .household: return OMPSymbol.household
        }
    }
}
