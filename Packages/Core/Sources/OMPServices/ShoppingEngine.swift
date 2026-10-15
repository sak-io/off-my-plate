import Foundation
import OMPDomain

/// The shared, non-locking shopping logic. Callers hold the service lock.
struct ShoppingEngine: Sendable {
    let context: ServiceContext

    /// The plan the list is derived from (AC-10.1, AC-10.2): among the effectively approved
    /// plans that still cover today or later, the one that starts first. `nil` means no
    /// approved plan, so only manual and imported items remain.
    static func shoppingPlan(in plans: [MealPlan], today: LocalDate) -> MealPlan? {
        plans.filter { $0.isEffectivelyApproved && $0.endDate >= today }
            .min { lhs, rhs in
                lhs.weekStart != rhs.weekStart ? lhs.weekStart < rhs.weekStart : lhs.id < rhs.id
            }
    }

    /// Re-derives the plan lines from the approved plan and the pantry, merges them into the
    /// stored list (manual and imported items and check-offs on unchanged lines survive,
    /// AC-10.5) and stores the result.
    @discardableResult
    func rederive() async throws -> [ShoppingItem] {
        let repositories = context.repositories
        let now = context.clock.now
        let timeZone = context.clock.timeZone
        let plans = try await repositories.mealPlans.fetchAll()
        let pantry = try await repositories.pantry.fetchAll()
        let existing = try await repositories.shopping.fetchAll()

        var derived: [DerivedShoppingLine] = []
        if let plan = ShoppingEngine.shoppingPlan(in: plans, today: LocalDate(now, in: timeZone)) {
            derived = ShoppingDerivation.derive(
                plan: plan, recipes: context.library.recipesByID, ingredients: context.library.ingredientsByID,
                pantry: pantry, now: now, timeZone: timeZone)
        }
        let makeID = context.makeID
        let merged = ShoppingListMerge.merge(
            existing: existing, derived: derived, makeId: { ShoppingItemID(makeID()) })

        let kept = Set(merged.map(\.id))
        for old in existing where !kept.contains(old.id) {
            try await repositories.shopping.delete(id: old.id)
        }
        let before = Set(existing)
        for item in merged where !before.contains(item) {
            try await repositories.shopping.save(item)
        }
        return merged
    }

    /// The pantry reference for typed, imported or spoken text: a taxonomy ingredient when
    /// `ingredientId` is known or the name matches exactly one ingredient, else free text
    /// (AC-9.2).
    func pantryRef(name: String, ingredientId: IngredientID?) throws -> PantryItemRef {
        if let ingredientId {
            guard context.library.ingredientsByID[ingredientId] != nil else {
                throw ServiceError.unknownIngredient(ingredientId)
            }
            return .ingredient(ingredientId)
        }
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(InboxImport.Item.maxNameLength))
        guard !trimmed.isEmpty else { throw ServiceError.invalidInput("A name is required.") }
        if let match = context.library.resolver.confidentMatch(for: trimmed) {
            return .ingredient(match.ingredientId)
        }
        return .freeText(trimmed)
    }

    /// The expiry day for a new fridge item with a known shelf life, as "Bought everything"
    /// does (AC-10.6).
    func expiry(for ingredient: Ingredient?, location: StorageLocation, now: Date) -> LocalDate? {
        guard location == .fridge, let days = ingredient?.fridgeShelfLifeDays, days >= 0 else { return nil }
        return LocalDate(now, in: context.clock.timeZone).adding(days: min(days, 3650))
    }
}
