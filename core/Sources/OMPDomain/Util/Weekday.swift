/// A day of the week, Monday first (ISO 8601 numbering: Monday = 1 ... Sunday = 7).
///
/// Encodes as its case name (`"monday"`), so stored data does not depend on any calendar's
/// first-weekday setting.
public enum Weekday: String, CaseIterable, Codable, Sendable, Hashable, Comparable {
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday
    case sunday

    /// ISO 8601 day number: Monday = 1 ... Sunday = 7.
    public var isoNumber: Int {
        switch self {
        case .monday: return 1
        case .tuesday: return 2
        case .wednesday: return 3
        case .thursday: return 4
        case .friday: return 5
        case .saturday: return 6
        case .sunday: return 7
        }
    }

    /// The weekday for an ISO 8601 day number, or `nil` outside 1...7.
    public init?(isoNumber: Int) {
        guard isoNumber >= 1, isoNumber <= 7 else { return nil }
        self = Weekday.allCases[isoNumber - 1]
    }

    /// Default school days for a lunchbox (AC-7.2): Monday to Friday.
    public static let schoolWeek: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]

    public static func < (lhs: Weekday, rhs: Weekday) -> Bool {
        lhs.isoNumber < rhs.isoNumber
    }
}
