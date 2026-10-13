import Foundation

/// One shopping line derived from the approved plan, before it is merged into the stored
/// list (which assigns ids and keeps check-offs, AC-10.5).
public struct DerivedShoppingLine: Sendable, Hashable {
    /// Merge key, see `ShoppingDerivation.key(ingredient:dimension:group:)`.
    public let key: String
    public let ingredientId: IngredientID
    public let name: String
    /// Always quantified and greater than zero, in its display unit.
    public let quantity: Quantity
    public let aisle: Aisle
    public let group: ShoppingItemGroup

    public init(
        key: String, ingredientId: IngredientID, name: String, quantity: Quantity, aisle: Aisle,
        group: ShoppingItemGroup
    ) {
        self.key = key
        self.ingredientId = ingredientId
        self.name = name
        self.quantity = quantity
        self.aisle = aisle
        self.group = group
    }
}

/// Need = requirements − usable pantry, with low-confidence cover as "Check you have"
/// (plan section 6; AC-5.3, AC-9.2, AC-9.7, AC-10.1, AC-10.4).
public enum ShoppingDerivation {
    /// The merge key of a plan line: `plan:<ingredientId>:<dimension>:<group>`, for example
    /// `plan:ghee:volume:toBuy`. The dimension separates non-convertible lines of the same
    /// ingredient (AC-10.1); the group separates "to buy" from "Check you have". It does not
    /// contain the quantity, so a changed amount keeps the key (and clears the check-off).
    public static func key(ingredient: IngredientID, dimension: MeasureDimension, group: ShoppingItemGroup) -> String {
        "plan:" + ingredient.rawValue + ":" + dimension.rawValue + ":" + group.rawValue
    }

    /// The shopping lines for `plan` given the `pantry`, at `now` in `timeZone`.
    ///
    /// - Only the effectively-approved plan's usable, uncooked meals dated today or later count
    ///   (AC-5.3, AC-10.2: any other plan yields no lines).
    /// - Pantry items count only if resolved, not expired and with a positive amount (AC-9.2).
    ///   Confident items are subtracted silently; what low-confidence items would cover becomes
    ///   a "Check you have" line (AC-9.7, AC-10.4); the rest is "to buy".
    /// - Pantry amounts that do not convert into a requirement part are ignored for that part,
    ///   so non-convertible needs stay as their own lines (AC-10.1).
    ///
    /// Lines are sorted by aisle display order, then by key.
    public static func derive(
        plan: MealPlan,
        recipes: [RecipeID: Recipe],
        ingredients: [IngredientID: Ingredient],
        pantry: [PantryItem],
        now: Date,
        timeZone: TimeZone
    ) -> [DerivedShoppingLine] {
        let today = LocalDate(now, in: timeZone)
        let requirements = IngredientRequirements.forShopping(
            plan: plan, recipes: recipes, ingredients: ingredients, today: today)
        guard !requirements.isEmpty else { return [] }

        var confident: [IngredientID: [Quantity]] = [:]
        var lowConfidence: [IngredientID: [Quantity]] = [:]
        for item in pantry where item.isUsableForRequirements(today: today) {
            guard let id = item.item.ingredientId else { continue }
            switch item.confidence(now: now, timeZone: timeZone) {
            case .confident: confident[id, default: []].append(item.amount)
            case .low: lowConfidence[id, default: []].append(item.amount)
            }
        }

        var lines: [DerivedShoppingLine] = []
        for requirement in requirements {
            let id = requirement.ingredientId
            var afterConfident = requirement.total
            for amount in confident[id] ?? [] { afterConfident.subtract(amount) }
            var afterLow = afterConfident
            for amount in lowConfidence[id] ?? [] { afterLow.subtract(amount) }

            let ingredient = ingredients[id]
            // `subtract` never adds or reorders parts, so the indices line up.
            for index in afterConfident.parts.indices {
                let remaining = afterConfident.parts[index]
                guard remaining.isQuantified, !remaining.isZero else { continue }
                let toBuy = afterLow.parts[index]
                let check = remaining.subtracting(toBuy) ?? Quantity(0, remaining.unit)
                let groups: [(amount: Quantity, group: ShoppingItemGroup)] = [(toBuy, .toBuy), (check, .checkYouHave)]
                for (amount, group) in groups where !amount.isZero {
                    let shown = ShoppingUnits.normalised(
                        amount, profile: requirement.total.profile, defaultUnit: ingredient?.defaultUnit)
                    lines.append(
                        DerivedShoppingLine(
                            key: key(ingredient: id, dimension: shown.unit.dimension, group: group),
                            ingredientId: id,
                            name: ingredient?.name ?? id.rawValue,
                            quantity: shown,
                            aisle: ingredient?.aisle ?? .other,
                            group: group))
                }
            }
        }
        return lines.sorted(by: displayOrder)
    }

    static func displayOrder(_ lhs: DerivedShoppingLine, _ rhs: DerivedShoppingLine) -> Bool {
        let lhsAisle = Aisle.allCases.firstIndex(of: lhs.aisle) ?? Aisle.allCases.count
        let rhsAisle = Aisle.allCases.firstIndex(of: rhs.aisle) ?? Aisle.allCases.count
        if lhsAisle != rhsAisle { return lhsAisle < rhsAisle }
        return lhs.key.utf8.lexicographicallyPrecedes(rhs.key.utf8)
    }
}
