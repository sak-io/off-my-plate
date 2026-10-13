import Foundation

/// Why "Mark cooked" is not available for a meal (AC-5.3, AC-9.6, R1).
public enum MarkCookedError: Error, Sendable, Hashable {
    /// The plan is not effectively approved (draft, superseded, discarded or edited after
    /// approval).
    case planNotApproved
    /// No meal with this id in the plan.
    case mealNotFound(PlannedMealID)
    /// The meal was flagged unsafe after approval (R1).
    case blockedBySafety(PlannedMealID)
    /// The meal has no recipe.
    case emptyMeal(PlannedMealID)
    /// The meal was already cooked.
    case alreadyCooked(PlannedMealID)
    /// The recipe passed in is not the meal's recipe.
    case recipeMismatch(expected: RecipeID, actual: RecipeID)
}

/// One amount to take out of the pantry, as shown (and editable) on the confirm sheet.
public struct CookAmount: Sendable, Hashable {
    public var ingredientId: IngredientID
    public var quantity: Quantity

    public init(ingredientId: IngredientID, quantity: Quantity) {
        self.ingredientId = ingredientId
        self.quantity = quantity
    }
}

/// The pantry after a deduction and the deductions made, for the `CookLog`.
public struct PantryDeductionResult: Sendable, Hashable {
    /// Every input pantry item, in input order, with reduced quantities (never below zero).
    public let pantry: [PantryItem]
    /// One entry per pantry item touched, in the order they were deducted from.
    public let deductions: [PantryDeduction]

    public init(pantry: [PantryItem], deductions: [PantryDeduction]) {
        self.pantry = pantry
        self.deductions = deductions
    }
}

/// "Mark cooked" arithmetic (AC-9.6, plan section 6). Writing the `CookLog`, setting
/// `PlannedMeal.cooked` and the learning event are the service's job (T19).
public enum MarkCooked {
    /// AC-9.6: the amounts the confirm sheet proposes for `mealId`: recipe quantities × the
    /// meal's servings (Σ eating portions / recipe servings), summed per ingredient, in the
    /// recipe's units. Non-quantified lines are left out.
    ///
    /// Throws unless the plan is effectively approved and the meal is usable (not blocked by
    /// safety), has `recipe` and is not cooked yet (AC-5.3: no Mark cooked on drafts).
    public static func proposedAmounts(
        mealId: PlannedMealID,
        in plan: MealPlan,
        recipe: Recipe,
        ingredients: [IngredientID: Ingredient]
    ) throws(MarkCookedError) -> [CookAmount] {
        guard plan.isEffectivelyApproved else { throw MarkCookedError.planNotApproved }
        guard let meal = plan.meal(mealId) else { throw MarkCookedError.mealNotFound(mealId) }
        guard !meal.blockedBySafety else { throw MarkCookedError.blockedBySafety(mealId) }
        guard let recipeId = meal.recipeId else { throw MarkCookedError.emptyMeal(mealId) }
        guard meal.cooked == nil else { throw MarkCookedError.alreadyCooked(mealId) }
        guard recipeId == recipe.id else {
            throw MarkCookedError.recipeMismatch(expected: recipeId, actual: recipe.id)
        }
        let totals = IngredientRequirements.totals(
            of: [meal], recipes: [recipe.id: recipe], ingredients: ingredients)
        return totals.flatMap { requirement in
            requirement.total.quantifiedParts.map { CookAmount(ingredientId: requirement.ingredientId, quantity: $0) }
        }
    }

    /// AC-9.6: takes `amounts` out of `pantry`.
    ///
    /// For each amount, pantry items of that ingredient (resolved only; free text is never
    /// touched) whose unit converts are used earliest expiry first (items with no expiry last;
    /// ties by id), each down to at most zero. What the pantry cannot cover is simply not
    /// deducted: quantities never go below zero. Zero amounts deduct nothing.
    public static func deduct(
        _ amounts: [CookAmount],
        from pantry: [PantryItem],
        ingredients: [IngredientID: Ingredient]
    ) -> PantryDeductionResult {
        var items = pantry
        var deducted: [PantryItemID: Double] = [:]
        var order: [PantryItemID] = []

        for amount in amounts where amount.quantity.isQuantified && !amount.quantity.isZero {
            let profile = IngredientRequirements.profile(amount.ingredientId, in: ingredients)
            let candidates = items.indices
                .filter { items[$0].item.ingredientId == amount.ingredientId }
                .sorted { deductionPrecedes(items[$0], items[$1]) }
            var wanted = amount.quantity
            for index in candidates where !wanted.isZero {
                let stock = items[index].amount
                guard !stock.isZero, let wantedHere = wanted.converted(to: stock.unit, using: profile) else {
                    continue
                }
                let taken = min(stock.amount, wantedHere.amount)
                let left = stock.subtracting(Quantity(taken, stock.unit)) ?? Quantity(0, stock.unit)
                items[index].quantity = left.amount
                let id = items[index].id
                if deducted[id] == nil { order.append(id) }
                deducted[id, default: 0] += taken
                let takenInWanted = Quantity(taken, stock.unit).converted(to: wanted.unit, using: profile)
                    ?? Quantity(0, wanted.unit)
                wanted = wanted.subtracting(takenInWanted) ?? Quantity(0, wanted.unit)
                if wantedHere.amount <= stock.amount { wanted = Quantity(0, wanted.unit) }
            }
        }

        let units = Dictionary(items.map { ($0.id, $0.unit) }, uniquingKeysWith: { first, _ in first })
        let deductions = order.compactMap { id -> PantryDeduction? in
            guard let quantity = deducted[id], let unit = units[id] else { return nil }
            return PantryDeduction(pantryItemId: id, quantity: quantity, unit: unit)
        }
        return PantryDeductionResult(pantry: items, deductions: deductions)
    }

    /// Earliest expiry first; items with no expiry after all dated ones; ties by id.
    static func deductionPrecedes(_ lhs: PantryItem, _ rhs: PantryItem) -> Bool {
        switch (lhs.expiresOn, rhs.expiresOn) {
        case let (left?, right?) where left != right: return left < right
        case (.some, nil): return true
        case (nil, .some): return false
        default: return lhs.id.rawValue.utf8.lexicographicallyPrecedes(rhs.id.rawValue.utf8)
        }
    }
}
