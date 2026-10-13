import Foundation

/// Stored-list operations: re-derivation merge (AC-10.2, AC-10.5) and "Bought everything"
/// (AC-10.6). Pure functions over values; persisting the result is the caller's job.
public enum ShoppingListMerge {
    /// Relative tolerance when deciding whether a re-derived quantity is "unchanged".
    public static let unchangedTolerance = 1e-9

    /// Upper bound on a fridge shelf life used for `expiresOn` (10 years).
    static let maxShelfLifeDays = 3650

    /// Replaces the plan items of `existing` with `derived` (AC-10.5):
    /// - manual and imported items are kept exactly as they are, in their order;
    /// - a derived line whose key matches an existing plan item keeps that item's id, and keeps
    ///   its check-off only if the quantity and unit are unchanged;
    /// - other derived lines are new, unchecked items with an id from `makeId`;
    /// - plan items with no derived line any more are dropped (with no approved plan, `derived`
    ///   is empty and only manual and imported items remain, AC-10.2).
    ///
    /// Result order: derived lines in their given order, then the kept non-plan items.
    public static func merge(
        existing: [ShoppingItem],
        derived: [DerivedShoppingLine],
        makeId: () -> ShoppingItemID = { ShoppingItemID.generate() }
    ) -> [ShoppingItem] {
        var previousByKey: [String: ShoppingItem] = [:]
        for item in existing where item.origin == .plan && previousByKey[item.key] == nil {
            previousByKey[item.key] = item
        }

        var result: [ShoppingItem] = []
        for line in derived {
            let previous = previousByKey[line.key]
            let unchanged = previous.map { isSameQuantity($0, line.quantity) } ?? false
            result.append(
                ShoppingItem(
                    id: previous?.id ?? makeId(),
                    key: line.key,
                    ingredientId: line.ingredientId,
                    name: line.name,
                    quantity: line.quantity.amount,
                    unit: line.quantity.unit,
                    aisle: line.aisle,
                    checkedOff: unchanged && (previous?.checkedOff ?? false),
                    origin: .plan,
                    group: line.group))
        }
        result += existing.filter { $0.origin != .plan }
        return result
    }

    static func isSameQuantity(_ item: ShoppingItem, _ quantity: Quantity) -> Bool {
        guard item.unit == quantity.unit, let amount = item.quantity else { return false }
        let scale = max(abs(amount), abs(quantity.amount))
        return abs(amount - quantity.amount) <= unchangedTolerance * scale
    }

    /// The outcome of "Bought everything".
    public struct BoughtEverythingResult: Sendable, Hashable {
        /// New pantry items, one per checked "to buy" item, in list order.
        public let pantryAdditions: [PantryItem]
        /// The list without the checked items.
        public let remaining: [ShoppingItem]

        public init(pantryAdditions: [PantryItem], remaining: [ShoppingItem]) {
            self.pantryAdditions = pantryAdditions
            self.remaining = remaining
        }
    }

    /// AC-10.6: every checked item leaves the list; checked "to buy" items become pantry items.
    ///
    /// - A checked "Check you have" item means the user confirmed they have it, not that they
    ///   bought more, so it is removed from the list without adding stock (handoff Q2).
    /// - The pantry item refers to the ingredient when the line has one, otherwise it is free
    ///   text (unresolved, AC-9.2). Quantity and unit come from the line; a line with no amount
    ///   becomes 1 of the ingredient's default unit (1 piece for free text).
    /// - Location is the ingredient's default location (shelf for free text). A fridge item
    ///   with a known fridge shelf life gets `expiresOn = today + shelf life`.
    /// - `purchasedAt` and `lastConfirmedAt` are `now`; the source is `.bought`.
    public static func boughtEverything(
        list: [ShoppingItem],
        ingredients: [IngredientID: Ingredient],
        now: Date,
        timeZone: TimeZone,
        makeId: () -> PantryItemID = { PantryItemID.generate() }
    ) -> BoughtEverythingResult {
        let today = LocalDate(now, in: timeZone)
        var additions: [PantryItem] = []
        for item in list where item.checkedOff && item.group == .toBuy {
            let ingredient = item.ingredientId.flatMap { ingredients[$0] }
            let unit = item.unit ?? ingredient?.defaultUnit ?? .piece
            let amount = item.quantity ?? 1
            let location = ingredient?.defaultLocation ?? .shelf
            var expiresOn: LocalDate?
            if location == .fridge, let days = ingredient?.fridgeShelfLifeDays, days >= 0 {
                // Capped so a nonsense shelf life cannot push the date out of LocalDate's range.
                expiresOn = today.adding(days: min(days, maxShelfLifeDays))
            }
            additions.append(
                PantryItem(
                    id: makeId(),
                    item: item.ingredientId.map(PantryItemRef.ingredient) ?? .freeText(item.name),
                    quantity: Quantity(amount, unit).amount,
                    unit: unit,
                    location: location,
                    purchasedAt: now,
                    expiresOn: expiresOn,
                    lastConfirmedAt: now,
                    source: .bought))
        }
        return BoughtEverythingResult(pantryAdditions: additions, remaining: list.filter { !$0.checkedOff })
    }
}
