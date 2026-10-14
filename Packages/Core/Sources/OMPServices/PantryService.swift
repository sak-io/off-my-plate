import Foundation
import OMPDomain

/// What the user types or picks when adding or editing a pantry item (AC-9.1).
public struct PantryItemInput: Sendable, Hashable {
    /// Free text, or the picked ingredient's name.
    public var name: String
    /// The ingredient picked from the search list, if any (otherwise the name is resolved, and
    /// kept as free text when nothing matches, AC-9.2).
    public var ingredientId: IngredientID?
    public var quantity: Double
    public var unit: MeasureUnit
    public var location: StorageLocation
    public var expiresOn: LocalDate?

    public init(
        name: String, ingredientId: IngredientID? = nil, quantity: Double, unit: MeasureUnit,
        location: StorageLocation, expiresOn: LocalDate? = nil
    ) {
        self.name = name
        self.ingredientId = ingredientId
        self.quantity = quantity
        self.unit = unit
        self.location = location
        self.expiresOn = expiresOn
    }
}

/// What a confirmed voice command did (AC-9.4).
public struct VoiceOutcome: Sendable, Hashable {
    public var added: [PantryItem] = []
    /// Items whose quantity was set to zero ("we're out of ...").
    public var markedOut: [PantryItemID] = []
    public var removed: [PantryItemID] = []

    public init() {}
}

/// The pantry and Mark cooked (AC-9.1 to AC-9.4, AC-9.6, AC-12.1; task T19).
///
/// - Every change re-derives the shopping list (AC-9.3).
/// - Voice is confirm-to-save: `parseSpoken` only parses; nothing is stored until
///   `confirmVoice` is called with the commands the user confirmed (AC-9.4).
/// - Mark cooked works on effectively approved plans only (AC-5.3, AC-9.6); it writes the
///   `CookLog`, the deductions and a `.cooked` learning event.
public final class PantryService: Sendable {
    let context: ServiceContext

    public init(context: ServiceContext) {
        self.context = context
    }

    private var shopping: ShoppingEngine { ShoppingEngine(context: context) }

    // MARK: Queries

    public func items() async throws -> [PantryItem] {
        try await context.repositories.pantry.fetchAll()
    }

    /// Ingredient suggestions for the search picker (AC-9.1).
    public func searchIngredients(_ query: String, limit: Int = 10) -> [IngredientResolver.Candidate] {
        context.library.resolver.candidates(for: query, limit: limit)
    }

    // MARK: CRUD (AC-9.1, AC-9.2, AC-9.3)

    /// Adds an item with `source: .manual`.
    @discardableResult
    public func add(_ input: PantryItemInput) async throws -> PantryItem {
        try await context.serialized {
            let now = context.clock.now
            let item = PantryItem(
                id: PantryItemID(context.makeID()),
                item: try shopping.pantryRef(name: input.name, ingredientId: input.ingredientId),
                quantity: try Self.checkedAmount(input.quantity), unit: input.unit, location: input.location,
                expiresOn: input.expiresOn, lastConfirmedAt: now, source: .manual)
            try await context.repositories.pantry.save(item)
            try await shopping.rederive()
            return item
        }
    }

    /// Replaces the editable fields of an item. Saving counts as confirming it (AC-9.7).
    @discardableResult
    public func update(_ id: PantryItemID, with input: PantryItemInput) async throws -> PantryItem {
        try await context.serialized {
            guard var item = try await context.repositories.pantry.fetch(id: id) else {
                throw ServiceError.pantryItemNotFound(id)
            }
            item.item = try shopping.pantryRef(name: input.name, ingredientId: input.ingredientId)
            item.quantity = try Self.checkedAmount(input.quantity)
            item.unit = input.unit
            item.location = input.location
            item.expiresOn = input.expiresOn
            item.lastConfirmedAt = context.clock.now
            try await context.repositories.pantry.save(item)
            try await shopping.rederive()
            return item
        }
    }

    /// Resolves a free-text item to a taxonomy ingredient (AC-9.2); it then counts toward plan needs.
    @discardableResult
    public func resolve(_ id: PantryItemID, to ingredientId: IngredientID) async throws -> PantryItem {
        try await context.serialized {
            guard var item = try await context.repositories.pantry.fetch(id: id) else {
                throw ServiceError.pantryItemNotFound(id)
            }
            guard context.library.ingredientsByID[ingredientId] != nil else {
                throw ServiceError.unknownIngredient(ingredientId)
            }
            item.item = .ingredient(ingredientId)
            try await context.repositories.pantry.save(item)
            try await shopping.rederive()
            return item
        }
    }

    /// "Still have it": resets the item's confidence (AC-9.7).
    @discardableResult
    public func reconfirm(_ id: PantryItemID) async throws -> PantryItem {
        try await context.serialized {
            guard var item = try await context.repositories.pantry.fetch(id: id) else {
                throw ServiceError.pantryItemNotFound(id)
            }
            item.lastConfirmedAt = context.clock.now
            try await context.repositories.pantry.save(item)
            try await shopping.rederive()
            return item
        }
    }

    public func delete(_ id: PantryItemID) async throws {
        try await context.serialized {
            guard try await context.repositories.pantry.fetch(id: id) != nil else {
                throw ServiceError.pantryItemNotFound(id)
            }
            try await context.repositories.pantry.delete(id: id)
            try await shopping.rederive()
        }
    }

    // MARK: Voice (AC-9.4)

    /// Parses a transcript with the deterministic grammar. Pure: nothing is saved.
    public func parseSpoken(_ transcript: String) -> SpokenCommandParseResult {
        SpokenCommandParser(resolver: context.library.resolver).parse(transcript)
    }

    /// Applies the commands the user confirmed (possibly after editing the items on the card).
    /// This is the only way voice changes the pantry. `.openApprovalSheet` does nothing here.
    ///
    /// - Add: new `source: .voice` items. Out: matching items go to zero. Remove: matching items
    ///   are deleted.
    @discardableResult
    public func confirmVoice(_ commands: [SpokenCommand]) async throws -> VoiceOutcome {
        try await context.serialized {
            let now = context.clock.now
            var outcome = VoiceOutcome()
            var pantry = try await context.repositories.pantry.fetchAll()
            for command in commands {
                switch command {
                case .add(let items):
                    for spoken in items {
                        let id = spoken.match.ingredientId
                        let ingredient = context.library.ingredientsByID[id]
                        let amount = spoken.quantity ?? Quantity(1, ingredient?.defaultUnit ?? .piece)
                        let location = ingredient?.defaultLocation ?? .shelf
                        let item = PantryItem(
                            id: PantryItemID(context.makeID()), item: .ingredient(id),
                            quantity: try Self.checkedAmount(amount.amount), unit: amount.unit, location: location,
                            purchasedAt: now, expiresOn: shopping.expiry(for: ingredient, location: location, now: now),
                            lastConfirmedAt: now, source: .voice)
                        try await context.repositories.pantry.save(item)
                        pantry.append(item)
                        outcome.added.append(item)
                    }
                case .markOut(let items):
                    for spoken in items {
                        for index in pantry.indices where pantry[index].item.ingredientId == spoken.match.ingredientId {
                            pantry[index].quantity = 0
                            pantry[index].lastConfirmedAt = now
                            try await context.repositories.pantry.save(pantry[index])
                            outcome.markedOut.append(pantry[index].id)
                        }
                    }
                case .remove(let items):
                    for spoken in items {
                        let doomed = pantry.filter { $0.item.ingredientId == spoken.match.ingredientId }
                        for item in doomed {
                            try await context.repositories.pantry.delete(id: item.id)
                            outcome.removed.append(item.id)
                        }
                        pantry.removeAll { $0.item.ingredientId == spoken.match.ingredientId }
                    }
                case .openApprovalSheet:
                    break
                }
            }
            try await shopping.rederive()
            return outcome
        }
    }

    // MARK: Mark cooked (AC-9.6)

    /// What the confirm sheet proposes to take out of the pantry for `mealID`.
    ///
    /// - Throws: `.markCooked(.planNotApproved)` for anything but an effectively approved plan,
    ///   `.markCooked(.blockedBySafety)`, `.markCooked(.alreadyCooked)`, ...
    public func proposedCookAmounts(plan planID: MealPlanID, meal mealID: PlannedMealID) async throws -> [CookAmount] {
        let plan = try await requirePlan(planID)
        return try cookAmounts(for: mealID, in: plan)
    }

    /// Marks a meal cooked: takes `amounts` (default: the proposal) out of the pantry, never
    /// below zero, writes the `CookLog`, sets the meal's cooked reference and logs a `.cooked`
    /// learning event. Refuses a plan that is not effectively approved.
    @discardableResult
    public func markCooked(
        plan planID: MealPlanID, meal mealID: PlannedMealID, amounts edited: [CookAmount]? = nil
    ) async throws -> CookLog {
        try await context.serialized {
            var plan = try await requirePlan(planID)
            let proposed = try cookAmounts(for: mealID, in: plan)
            guard let index = plan.meals.firstIndex(where: { $0.id == mealID }),
                let recipeID = plan.meals[index].recipeId
            else { throw ServiceError.mealNotFound(mealID) }
            let now = context.clock.now

            let pantry = try await context.repositories.pantry.fetchAll()
            let result = MarkCooked.deduct(
                edited ?? proposed, from: pantry, ingredients: context.library.ingredientsByID)
            let before = Set(pantry)
            for item in result.pantry where !before.contains(item) {
                try await context.repositories.pantry.save(item)
            }
            let log = CookLog(
                id: CookLogID(context.makeID()), planId: planID, mealId: mealID, recipeId: recipeID, cookedAt: now,
                deductions: result.deductions)
            try await context.repositories.cookLogs.save(log)
            try await context.repositories.learningEvents.save(
                LearningEvent(id: LearningEventID(context.makeID()), kind: .cooked(recipe: recipeID), at: now))
            // Last, so an interrupted call can be repeated rather than leave a cooked meal with no log.
            plan.meals[index].cooked = CookRef(cookLogId: log.id, cookedAt: now)
            try await context.repositories.mealPlans.save(plan)
            try await shopping.rederive()
            return log
        }
    }

    // MARK: Private

    private func requirePlan(_ id: MealPlanID) async throws -> MealPlan {
        guard let plan = try await context.repositories.mealPlans.fetch(id: id) else {
            throw ServiceError.planNotFound(id)
        }
        return plan
    }

    private func cookAmounts(for mealID: PlannedMealID, in plan: MealPlan) throws -> [CookAmount] {
        // The plan status is checked first so a draft is refused whatever else is wrong with it.
        guard plan.isEffectivelyApproved else { throw ServiceError.markCooked(.planNotApproved) }
        guard let recipeID = plan.meal(mealID)?.recipeId else {
            return try mappingDomainErrors {
                try MarkCooked.proposedAmounts(
                    mealId: mealID, in: plan,
                    recipe: Recipe.placeholder, ingredients: context.library.ingredientsByID)
            }
        }
        guard let recipe = context.library.recipesByID[recipeID] else {
            throw ServiceError.recipeNotInLibrary(recipeID)
        }
        return try mappingDomainErrors {
            try MarkCooked.proposedAmounts(
                mealId: mealID, in: plan, recipe: recipe, ingredients: context.library.ingredientsByID)
        }
    }

    static func checkedAmount(_ value: Double) throws -> Double {
        guard value.isFinite, value >= 0, value <= 1_000_000_000 else {
            throw ServiceError.invalidInput("A quantity must be a finite number of at least 0.")
        }
        return value
    }
}
