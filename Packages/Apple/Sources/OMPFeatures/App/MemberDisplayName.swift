import Foundation
import OMPDomain

extension Member {
    /// The name the UI shows: the custom name when set, otherwise the generated label
    /// "Adult 1" / "Child 2" (AC-1.2), localized through the String Catalog (the core builds no
    /// user-facing strings, ADR 0005).
    public var displayName: String {
        if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        return label.displayName
    }
}

extension MemberLabel {
    /// "Adult 1" or "Child 2", localized.
    public var displayName: String {
        switch role {
        case .adult:
            return String(
                localized: "member.label.adult",
                defaultValue: "Adult \(number)",
                comment: "Generated label of an adult member, AC-1.2. %lld is the number.")
        case .child:
            return String(
                localized: "member.label.child",
                defaultValue: "Child \(number)",
                comment: "Generated label of a child member, AC-1.2. %lld is the number.")
        }
    }
}
