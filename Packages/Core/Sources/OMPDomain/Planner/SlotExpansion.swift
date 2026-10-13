/// A member marked "not eating" for one meal (AC-6.3).
public struct MealAbsence: Codable, Sendable, Hashable {
    public var memberId: MemberID
    public var date: LocalDate
    public var slot: MealSlot

    public init(memberId: MemberID, date: LocalDate, slot: MealSlot) {
        self.memberId = memberId
        self.date = date
        self.slot = slot
    }
}

/// One slot to fill: a day, a meal slot and everyone's serving (plan section 5 step 2).
public struct PlannerSlot: Sendable, Hashable {
    public let date: LocalDate
    public let slot: MealSlot
    /// One serving per cleared member, in clearance order; `notEating` marks who is not eating.
    public let servings: [MealServing]

    public init(date: LocalDate, slot: MealSlot, servings: [MealServing]) {
        self.date = date
        self.slot = slot
        self.servings = servings
    }

    /// The members who eat this slot; only their rules constrain it (AC-6.3).
    public var eaterIDs: [MemberID] {
        servings.filter { !$0.notEating }.map(\.memberId)
    }
}

/// Expands a date range into slots (plan section 5 step 2; AC-6.1, AC-6.3, AC-7.2, R7, G5).
public enum SlotExpansion {
    /// The order slots are filled within a day. The lunchbox comes before family lunch because
    /// it draws from the smaller `lunchboxSuitable` subset.
    public static let fillOrder: [MealSlot] = [.breakfast, .lunchbox, .lunch, .dinner, .snack]

    /// Whether `member` needs a lunchbox on `date`: `needsSchoolLunch` and the date's weekday is
    /// one of their `schoolDays` (AC-7.2).
    public static func needsLunchbox(_ member: Member, on date: LocalDate) -> Bool {
        member.needsSchoolLunch && member.schoolDays.contains(date.weekday)
    }

    /// The slots for `dates`, in date order and `fillOrder` within a day.
    ///
    /// - Every day gets breakfast, lunch and dinner; a snack only when `settings.snacksEnabled`.
    /// - A day gets one `lunchbox` slot when at least one member needs a lunchbox that day. Only
    ///   those members eat it; everyone else is `notEating` there.
    /// - On such a day the lunchbox members are `notEating` at family lunch (R7).
    /// - Every member in `absences` for that date and slot is `notEating` (AC-6.3).
    /// - Every slot lists a serving for every member (their default portion, AC-6.2), so a member
    ///   can never be silently missing from a meal.
    public static func slots(
        dates: [LocalDate], members: [Member], settings: HouseholdSettings, absences: Set<MealAbsence>
    ) -> [PlannerSlot] {
        var result: [PlannerSlot] = []
        for date in dates {
            let lunchboxMembers = Set(members.filter { needsLunchbox($0, on: date) }.map(\.id))
            for slot in fillOrder {
                switch slot {
                case .snack where !settings.snacksEnabled:
                    continue
                case .lunchbox where lunchboxMembers.isEmpty:
                    continue
                default:
                    break
                }
                let servings = members.map { member -> MealServing in
                    var serving = MealServing(defaultFor: member)
                    let absent = absences.contains(MealAbsence(memberId: member.id, date: date, slot: slot))
                    switch slot {
                    case .lunchbox:
                        serving.notEating = absent || !lunchboxMembers.contains(member.id)
                    case .lunch:
                        serving.notEating = absent || lunchboxMembers.contains(member.id)
                    case .breakfast, .dinner, .snack:
                        serving.notEating = absent
                    }
                    return serving
                }
                result.append(PlannerSlot(date: date, slot: slot, servings: servings))
            }
        }
        return result
    }
}
