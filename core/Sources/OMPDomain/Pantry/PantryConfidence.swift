import Foundation

/// How sure the app is that a pantry item is still there (AC-9.7, plan section 6).
public enum PantryConfidence: String, CaseIterable, Codable, Sendable, Hashable {
    /// Re-confirmed recently enough to be subtracted from plan requirements silently.
    case confident
    /// Not re-confirmed for a while: it may still cover a need, but only as "Check you have"
    /// (AC-10.4), never silently.
    case low
}

extension StorageLocation {
    /// Whole calendar days after `lastConfirmedAt` during which an item kept here is still
    /// confident (AC-9.7 ASSUMPTION): 7 for the fridge, 60 for the shelf and the freezer.
    public var confidenceWindowDays: Int {
        switch self {
        case .fridge: return 7
        case .shelf, .freezer: return 60
        }
    }
}

extension PantryItem {
    /// Calendar days from the day of `lastConfirmedAt` to the day of `now`, both in `timeZone`.
    /// Never negative (a confirmation "in the future", for example after a clock change, is age 0).
    public func daysSinceConfirmed(now: Date, timeZone: TimeZone) -> Int {
        let confirmedDay = LocalDate(lastConfirmedAt, in: timeZone)
        let today = LocalDate(now, in: timeZone)
        return max(0, today.daysSince(confirmedDay))
    }

    /// AC-9.7: confident while the age in calendar days is at most the location's window
    /// (fridge: day 7 is still confident, day 8 is low; shelf/freezer: day 60 vs day 61).
    /// Re-confirming (setting `lastConfirmedAt` to now) resets it to confident.
    public func confidence(now: Date, timeZone: TimeZone) -> PantryConfidence {
        daysSinceConfirmed(now: now, timeZone: timeZone) <= location.confidenceWindowDays ? .confident : .low
    }

    /// Whether the best-before day is before `today`. An item with no expiry never expires.
    public func isExpired(today: LocalDate) -> Bool {
        guard let expiresOn else { return false }
        return expiresOn < today
    }

    /// The amount as a `Quantity` (negative or NaN stored amounts read as zero).
    public var amount: Quantity {
        Quantity(quantity, unit)
    }

    /// AC-9.2 and plan section 6: whether the item may count toward plan requirements at all.
    /// It must be resolved to a taxonomy ingredient, not expired, and hold a positive
    /// quantified amount. Confidence is checked separately (`confidence(now:timeZone:)`).
    public func isUsableForRequirements(today: LocalDate) -> Bool {
        item.ingredientId != nil && !isExpired(today: today) && amount.isQuantified && !amount.isZero
    }
}
