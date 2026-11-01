/// The dates a new plan covers (R8; plan section 5 step 0).
///
/// Each plan covers `MealPlan.lengthInDays` (7) days from its start date. The first plan starts
/// today; each next plan starts the day after the previous one ends. "Week starts Monday" (A8)
/// is not used here: it only drives weekly counters.
public enum PlanDateRange {
    /// The start date for a new plan series entry.
    ///
    /// - Parameters:
    ///   - previousEnd: the last day of the previous plan in the series, or `nil` for the first
    ///     plan.
    ///   - today: today's date (from the caller's `DomainClock`, in its explicit time zone).
    /// - Returns: `today` for the first plan; otherwise `previousEnd + 1`, but never a day
    ///   before `today` (a plan is never generated for days that are already over; this
    ///   clamp is an assumption flagged in the T10 handoff).
    public static func startDate(previousEnd: LocalDate?, today: LocalDate) -> LocalDate {
        guard let previousEnd else { return today }
        return max(previousEnd.adding(days: 1), today)
    }

    /// The `MealPlan.lengthInDays` consecutive days starting at `start`.
    public static func dates(from start: LocalDate) -> [LocalDate] {
        (0..<MealPlan.lengthInDays).map { start.adding(days: $0) }
    }
}
