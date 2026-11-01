import Foundation
import OMPDomain
import OMPServices

/// Facts about a taxonomy ingredient the pantry screens show or default from.
public struct IngredientDefaults: Sendable, Hashable {
    public var name: String
    public var unit: MeasureUnit
    public var location: StorageLocation

    public init(name: String, unit: MeasureUnit, location: StorageLocation) {
        self.name = name
        self.unit = unit
        self.location = location
    }
}

/// One ingredient line of the cooked sheet (S-15).
public struct CookLine: Sendable, Hashable, Identifiable {
    public var ingredientId: IngredientID
    public var name: String
    /// What the recipe proposes to use, in the recipe's unit.
    public var proposed: Quantity
    /// What the pantry holds of it in the same unit, or nil when it is not in the pantry (or
    /// cannot be compared): such a line has no action.
    public var have: Quantity?

    public var id: String { ingredientId.rawValue }

    public init(ingredientId: IngredientID, name: String, proposed: Quantity, have: Quantity?) {
        self.ingredientId = ingredientId
        self.name = name
        self.proposed = proposed
        self.have = have
    }
}

/// What the cooked sheet shows for one meal.
public struct CookProposal: Sendable, Hashable {
    public var mealTitle: String
    public var lines: [CookLine]

    public init(mealTitle: String, lines: [CookLine]) {
        self.mealTitle = mealTitle
        self.lines = lines
    }
}

/// What the Pantry screens and the cooked sheet need from the use-case services (task T24).
/// The live implementation wraps `PantryService`; tests use a fake. Every change to the pantry
/// goes through the service, which re-derives the shopping list (AC-9.3) and refuses Mark cooked
/// on a plan that is not effectively approved (AC-9.6). Voice is confirm-to-save: `parseSpoken`
/// only parses, and only `confirmVoice` stores anything (AC-9.4).
public protocol PantryBackend: Sendable {
    func items() async throws -> [PantryItem]
    /// Ingredient suggestions for the name field (AC-9.1).
    func searchIngredients(_ query: String) -> [IngredientResolver.Candidate]
    func defaults(for id: IngredientID) -> IngredientDefaults?

    func add(_ input: PantryItemInput) async throws -> PantryItem
    func update(_ id: PantryItemID, with input: PantryItemInput) async throws -> PantryItem
    func reconfirm(_ id: PantryItemID) async throws
    func delete(_ id: PantryItemID) async throws

    func parseSpoken(_ transcript: String) -> SpokenCommandParseResult
    func confirmVoice(_ commands: [SpokenCommand]) async throws -> VoiceOutcome

    /// The cooked sheet's proposal. Throws `ServiceError.markCooked(.planNotApproved)` for a
    /// plan that is not effectively approved.
    func cookProposal(plan: MealPlanID, meal: PlannedMealID) async throws -> CookProposal
    func markCooked(plan: MealPlanID, meal: PlannedMealID, amounts: [CookAmount]) async throws
}

/// The services as the Pantry screens use them.
public final class LivePantryBackend: PantryBackend {
    private let service: PantryService
    private let context: ServiceContext

    public init(context: ServiceContext) {
        self.service = PantryService(context: context)
        self.context = context
    }

    public func items() async throws -> [PantryItem] {
        try await service.items()
    }

    public func searchIngredients(_ query: String) -> [IngredientResolver.Candidate] {
        service.searchIngredients(query)
    }

    public func defaults(for id: IngredientID) -> IngredientDefaults? {
        context.library.ingredientsByID[id].map {
            IngredientDefaults(name: $0.name, unit: $0.defaultUnit, location: $0.defaultLocation)
        }
    }

    public func add(_ input: PantryItemInput) async throws -> PantryItem {
        try await service.add(input)
    }

    public func update(_ id: PantryItemID, with input: PantryItemInput) async throws -> PantryItem {
        try await service.update(id, with: input)
    }

    public func reconfirm(_ id: PantryItemID) async throws {
        _ = try await service.reconfirm(id)
    }

    public func delete(_ id: PantryItemID) async throws {
        try await service.delete(id)
    }

    public func parseSpoken(_ transcript: String) -> SpokenCommandParseResult {
        service.parseSpoken(transcript)
    }

    public func confirmVoice(_ commands: [SpokenCommand]) async throws -> VoiceOutcome {
        try await service.confirmVoice(commands)
    }

    public func cookProposal(plan planID: MealPlanID, meal mealID: PlannedMealID) async throws -> CookProposal {
        let amounts = try await service.proposedCookAmounts(plan: planID, meal: mealID)
        let stock = try await service.items()
        let plan = try await context.repositories.mealPlans.fetch(id: planID)
        let title = plan?.meal(mealID)?.recipeId.flatMap { context.library.recipesByID[$0]?.title } ?? ""
        let lines = amounts.map { amount -> CookLine in
            let ingredient = context.library.ingredientsByID[amount.ingredientId]
            let profile = ingredient.map { ConversionProfile(ingredient: $0) } ?? .sameDimensionOnly
            var have = Quantity(0, amount.quantity.unit)
            for item in stock where item.item.ingredientId == amount.ingredientId {
                guard let converted = item.amount.converted(to: amount.quantity.unit, using: profile),
                    !converted.isZero
                else { continue }
                have = have.adding(converted, using: profile) ?? have
            }
            return CookLine(
                ingredientId: amount.ingredientId, name: ingredient?.name ?? amount.ingredientId.rawValue,
                proposed: amount.quantity, have: have.isZero ? nil : have)
        }
        return CookProposal(mealTitle: title, lines: lines)
    }

    public func markCooked(plan planID: MealPlanID, meal mealID: PlannedMealID, amounts: [CookAmount]) async throws {
        _ = try await service.markCooked(plan: planID, meal: mealID, amounts: amounts)
    }
}
