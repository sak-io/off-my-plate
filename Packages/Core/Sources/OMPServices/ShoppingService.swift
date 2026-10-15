import Foundation
import OMPDomain

/// What the user types when adding a shopping item by hand (AC-10.5).
public struct ShoppingItemInput: Sendable, Hashable {
    public var name: String
    /// The ingredient picked from the search list, if any (otherwise the name is resolved, and
    /// kept as free text when nothing matches).
    public var ingredientId: IngredientID?
    public var quantity: Double?
    public var unit: MeasureUnit?

    public init(name: String, ingredientId: IngredientID? = nil, quantity: Double? = nil, unit: MeasureUnit? = nil) {
        self.name = name
        self.ingredientId = ingredientId
        self.quantity = quantity
        self.unit = unit
    }
}

/// The shopping list (AC-10.1 to AC-10.7; task T19).
///
/// The list is derived from the effectively approved plan and the pantry (`ShoppingDerivation`)
/// and merged into the stored list, which also holds manual and imported items. The app calls
/// `refresh()` when the Shopping tab opens and after a plan is approved; the pantry service
/// refreshes it itself after every pantry change (AC-9.3).
public final class ShoppingService: Sendable {
    let context: ServiceContext

    public init(context: ServiceContext) {
        self.context = context
    }

    private var engine: ShoppingEngine { ShoppingEngine(context: context) }

    // MARK: Queries

    /// The stored list as it is, without re-deriving.
    public func items() async throws -> [ShoppingItem] {
        try await context.repositories.shopping.fetchAll()
    }

    /// Re-derives the plan lines and returns the whole list (AC-10.1, AC-10.2, AC-10.5).
    @discardableResult
    public func refresh() async throws -> [ShoppingItem] {
        try await context.serialized {
            try await engine.rederive()
        }
    }

    // MARK: Editing

    /// Adds a manual item (AC-10.5). It survives every re-derivation.
    @discardableResult
    public func addManual(_ input: ShoppingItemInput) async throws -> ShoppingItem {
        try await context.serialized {
            let reference = try engine.pantryRef(name: input.name, ingredientId: input.ingredientId)
            let ingredient = reference.ingredientId.flatMap { context.library.ingredientsByID[$0] }
            var quantity: Double?
            var unit: MeasureUnit?
            if let amount = input.quantity {
                let checked = try PantryService.checkedAmount(amount)
                let chosen = input.unit ?? ingredient?.defaultUnit ?? .piece
                if chosen.isQuantified, checked > 0 {
                    quantity = checked
                    unit = chosen
                }
            }
            let name: String
            switch reference {
            case .ingredient(let id): name = context.library.ingredientsByID[id]?.name ?? id.rawValue
            case .freeText(let text): name = text
            }
            let id = ShoppingItemID(context.makeID())
            let item = ShoppingItem(
                id: id, key: "manual:" + id.rawValue, ingredientId: reference.ingredientId, name: name,
                quantity: quantity, unit: unit, aisle: ingredient?.aisle ?? .other, origin: .manual)
            try await context.repositories.shopping.save(item)
            return item
        }
    }

    /// Checks an item off (or back on). Check-offs on unchanged plan lines survive
    /// re-derivation (AC-10.5).
    @discardableResult
    public func setChecked(_ id: ShoppingItemID, _ checked: Bool) async throws -> ShoppingItem {
        try await context.serialized {
            guard var item = try await context.repositories.shopping.fetch(id: id) else {
                throw ServiceError.shoppingItemNotFound(id)
            }
            item.checkedOff = checked
            try await context.repositories.shopping.save(item)
            return item
        }
    }

    /// Removes a manual or imported item. Plan lines cannot be removed by hand: they follow the
    /// approved plan and the pantry.
    public func remove(_ id: ShoppingItemID) async throws {
        try await context.serialized {
            guard let item = try await context.repositories.shopping.fetch(id: id) else {
                throw ServiceError.shoppingItemNotFound(id)
            }
            guard item.origin != .plan else {
                throw ServiceError.invalidInput("A line from the plan cannot be removed by hand.")
            }
            try await context.repositories.shopping.delete(id: id)
        }
    }

    // MARK: Bought everything (AC-10.6)

    /// Every checked item leaves the list. Checked "to buy" items become pantry items
    /// (`source: .bought`); a checked "Check you have" item only confirms the pantry items of
    /// that ingredient (the user has it), so it does not come back. The list is then re-derived.
    ///
    /// - Returns: the pantry items added.
    @discardableResult
    public func boughtEverything() async throws -> [PantryItem] {
        try await context.serialized {
            let now = context.clock.now
            let list = try await context.repositories.shopping.fetchAll()
            let makeID = context.makeID
            let result = ShoppingListMerge.boughtEverything(
                list: list, ingredients: context.library.ingredientsByID, now: now, timeZone: context.clock.timeZone,
                makeId: { PantryItemID(makeID()) })
            for addition in result.pantryAdditions {
                try await context.repositories.pantry.save(addition)
            }

            let confirmed = Set(
                list.filter { $0.checkedOff && $0.group == .checkYouHave }.compactMap(\.ingredientId))
            if !confirmed.isEmpty {
                let pantry = try await context.repositories.pantry.fetchAll()
                for var held in pantry {
                    guard let ingredientId = held.item.ingredientId, confirmed.contains(ingredientId) else { continue }
                    held.lastConfirmedAt = now
                    try await context.repositories.pantry.save(held)
                }
            }

            let kept = Set(result.remaining.map(\.id))
            for item in list where !kept.contains(item.id) {
                try await context.repositories.shopping.delete(id: item.id)
            }
            try await engine.rederive()
            return result.pantryAdditions
        }
    }

    // MARK: Share (AC-10.7)

    /// The plain-text list for the system Share Sheet.
    public func shareText() async throws -> String {
        let repositories = context.repositories
        let items = try await repositories.shopping.fetchAll()
        let plans = try await repositories.mealPlans.fetchAll()
        let plan = ShoppingEngine.shoppingPlan(in: plans, today: context.clock.today)
        return ShoppingShareText.render(items: items, range: plan.map { $0.weekStart...$0.endDate })
    }
}

/// The share text of the shopping list (AC-10.7, copy C-148). Pure and locale-independent
/// (dates are ISO 8601); the UI translates the header only if the copy deck says so.
///
/// ```
/// Shopping list for 2026-10-12 to 2026-10-18 (from OffMyPlate)
///
/// Vegetables & fruit
/// - Onion 500 g
///
/// Check you have
/// - Rice 1 kg
/// ```
/// Checked items are left out. Aisles follow `Aisle.allCases`; "Check you have" comes last.
public enum ShoppingShareText {
    public static func render(items: [ShoppingItem], range: ClosedRange<LocalDate>?) -> String {
        var lines: [String] = []
        if let range {
            lines.append("Shopping list for \(range.lowerBound.isoString) to \(range.upperBound.isoString) (from OffMyPlate)")
        } else {
            lines.append("Shopping list (from OffMyPlate)")
        }
        let open = items.filter { !$0.checkedOff }
        for aisle in Aisle.allCases {
            let inAisle = open.filter { $0.group == .toBuy && $0.aisle == aisle }
            guard !inAisle.isEmpty else { continue }
            lines.append("")
            lines.append(title(of: aisle))
            lines += inAisle.map(line)
        }
        let check = open.filter { $0.group == .checkYouHave }
        if !check.isEmpty {
            lines.append("")
            lines.append("Check you have")
            lines += check.map(line)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func title(of aisle: Aisle) -> String {
        switch aisle {
        case .vegetablesAndFruit: return "Vegetables & fruit"
        case .dairyAndEggs: return "Dairy & eggs"
        case .grainsAndFlours: return "Grains & flours"
        case .pulsesAndLentils: return "Pulses & lentils"
        case .spicesAndMasalas: return "Spices & masalas"
        case .oilsAndGhee: return "Oils & ghee"
        case .meatAndFish: return "Meat & fish"
        case .bakery: return "Bakery"
        case .other: return "Other"
        }
    }

    static func line(_ item: ShoppingItem) -> String {
        var text = "- " + item.name
        if let quantity = item.quantity, let unit = item.unit, unit.isQuantified {
            text += " " + amount(quantity)
            if unit != .piece { text += " " + unit.rawValue }
        }
        return text
    }

    /// At most two decimals, no trailing zeros: 500, 1.5, 0.25. Rounded here only for display.
    static func amount(_ value: Double) -> String {
        guard value.isFinite, value > 0 else { return "0" }
        let hundredths = Int((min(value, 1e9) * 100).rounded())
        let whole = hundredths / 100
        let fraction = hundredths % 100
        if fraction == 0 { return String(whole) }
        var digits = fraction < 10 ? "0" + String(fraction) : String(fraction)
        if digits.hasSuffix("0") { digits.removeLast() }
        return String(whole) + "." + digits
    }
}
