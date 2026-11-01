import Foundation

/// What a pantry item is: a taxonomy ingredient, or free text not resolved yet (AC-9.2).
///
/// An enum rather than two optionals, so an item can never be both or neither.
public enum PantryItemRef: Codable, Sendable, Hashable {
    case ingredient(IngredientID)
    /// Unresolved: shown, but never counted toward plan requirements until resolved.
    case freeText(String)

    /// The ingredient id when resolved.
    public var ingredientId: IngredientID? {
        switch self {
        case .ingredient(let id): return id
        case .freeText: return nil
        }
    }
}

/// How a pantry item got into the pantry.
public enum PantryItemSource: String, CaseIterable, Codable, Sendable, Hashable {
    case manual
    case voice
    case notesImport
    case cookedDeduct
    case bought
}

/// Something at home (plan section 3.1, AC-9.1).
public struct PantryItem: Identifiable, Codable, Sendable, Hashable {
    public let id: PantryItemID
    public var item: PantryItemRef
    public var quantity: Double
    public var unit: MeasureUnit
    public var location: StorageLocation
    public var purchasedAt: Date?
    /// Best-before day, if known.
    public var expiresOn: LocalDate?
    /// Last time the user confirmed it is still there; confidence decays from here (AC-9.7).
    public var lastConfirmedAt: Date
    public var source: PantryItemSource

    public init(
        id: PantryItemID,
        item: PantryItemRef,
        quantity: Double,
        unit: MeasureUnit,
        location: StorageLocation,
        purchasedAt: Date? = nil,
        expiresOn: LocalDate? = nil,
        lastConfirmedAt: Date,
        source: PantryItemSource
    ) {
        self.id = id
        self.item = item
        self.quantity = quantity
        self.unit = unit
        self.location = location
        self.purchasedAt = purchasedAt
        self.expiresOn = expiresOn
        self.lastConfirmedAt = lastConfirmedAt
        self.source = source
    }
}

/// One pantry deduction made by "Mark cooked" (AC-9.6).
public struct PantryDeduction: Codable, Sendable, Hashable {
    public var pantryItemId: PantryItemID
    public var quantity: Double
    public var unit: MeasureUnit

    public init(pantryItemId: PantryItemID, quantity: Double, unit: MeasureUnit) {
        self.pantryItemId = pantryItemId
        self.quantity = quantity
        self.unit = unit
    }
}

/// The record of a cooked meal (plan section 3.1, AC-9.6). Only approved plans can be cooked.
public struct CookLog: Identifiable, Codable, Sendable, Hashable {
    public let id: CookLogID
    public var planId: MealPlanID
    public var mealId: PlannedMealID
    public var recipeId: RecipeID
    public var cookedAt: Date
    public var deductions: [PantryDeduction]

    public init(
        id: CookLogID,
        planId: MealPlanID,
        mealId: PlannedMealID,
        recipeId: RecipeID,
        cookedAt: Date,
        deductions: [PantryDeduction] = []
    ) {
        self.id = id
        self.planId = planId
        self.mealId = mealId
        self.recipeId = recipeId
        self.cookedAt = cookedAt
        self.deductions = deductions
    }
}
