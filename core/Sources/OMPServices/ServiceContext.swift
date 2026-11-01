import Foundation
import OMPDomain
import OMPRecipes
import OMPSafetyCheck

/// The recipe content the services plan and validate with (ADR 0007, ADR 0010).
///
/// Holds two **independent** views of the same raw recipes and ingredients: the planner's
/// tag index (`PlannerLibrary`) and the validator's raw data (`SafetyCheckLibrary`), plus the
/// restriction catalog the safety screens pick from. Built once at launch.
public struct PlanningLibrary: Sendable {
    /// The seed content version every plan records (ADR 0010). A change triggers the R1
    /// re-check of open plans (`SafetyService.recheckIfLibraryChanged()`).
    public let contentVersion: String
    public let planner: PlannerLibrary
    public let safety: SafetyCheckLibrary
    /// Restrictions offered on the safety screen. Rules are only ever built from these, so a
    /// caller cannot hand in its own (weaker) tag set.
    public let restrictions: [Restriction]
    /// The recipes and ingredients by id, for shopping, Mark cooked and learning (they never
    /// feed a safety decision).
    public let recipesByID: [RecipeID: Recipe]
    public let ingredientsByID: [IngredientID: Ingredient]
    /// Resolves typed, spoken or imported names to taxonomy ingredients.
    public let resolver: IngredientResolver

    public init(recipes: [Recipe], ingredients: [Ingredient], restrictions: [Restriction], contentVersion: String) {
        self.contentVersion = contentVersion
        self.planner = PlannerLibrary(recipes: recipes, ingredients: ingredients, contentVersion: contentVersion)
        self.safety = SafetyCheckLibrary(recipes: recipes, ingredients: ingredients)
        self.restrictions = restrictions
        self.recipesByID = Dictionary(recipes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.ingredientsByID = Dictionary(ingredients.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.resolver = IngredientResolver(ingredients: ingredients)
    }

    /// The library for the bundled (or any loaded) seed content.
    public init(seed: SeedLibrary) {
        self.init(
            recipes: seed.recipes, ingredients: seed.ingredients, restrictions: seed.catalog.restrictions,
            contentVersion: seed.contentVersion)
    }

    /// The catalog restriction with `id`.
    public func restriction(_ id: RestrictionID) -> Restriction? {
        restrictions.first { $0.id == id }
    }
}

/// Something the services want a developer to see. Never contains personal data beyond ids.
public enum ServiceDiagnostic: Sendable, Hashable {
    /// The independent validator rejected meals the planner produced. That is a planner bug
    /// (plan section 5): the meals were emptied with `.removedByValidator` and never shown.
    case validatorRejectedPlannerOutput(planId: MealPlanID, meals: [PlannedMealID])
}

/// Why a service call was refused. Nothing is saved when one is thrown. Repository errors are
/// passed through unchanged.
public enum ServiceError: Error, Sendable, Hashable {
    /// Onboarding has not created a household yet.
    case noHousehold
    /// Onboarding was run although a household already exists.
    case householdAlreadyExists
    /// The safety gate refused (AC-3.1, AC-3.3, G3); the refusal says who must answer.
    case gateRefused(GateRefusal)
    /// The planner found its clearance stale (the household changed, or the gate no longer
    /// passes). Evaluate the gate again.
    case clearanceNotValid
    case planNotFound(MealPlanID)
    /// The plan is not the one being worked on in its series (a draft revision exists, or it
    /// is superseded or discarded); reload the working plan.
    case notWorkingPlan(MealPlanID)
    case mealNotFound(PlannedMealID)
    /// Locked meals never change (AC-8.3); unlock first.
    case mealLocked(PlannedMealID)
    /// The recipe is not one of the safe alternatives for that meal (AC-8.1).
    case recipeNotOffered(RecipeID)
    /// No other safe recipe exists for that meal (UI copy C-067).
    case noOtherSafeRecipe(PlannedMealID)
    /// The validator, run at call time against the current rules, found violations
    /// (AC-4.2): the plan cannot be approved.
    case validationFailed(violatingMeals: [PlannedMealID])
    /// A first plan of a week is still a draft; approve, regenerate or discard it first.
    case openDraftExists(MealPlanID)
    /// The restriction is not in the catalog.
    case unknownRestriction(RestrictionID)
    case lifecycle(PlanLifecycleError)
    case safetyTransition(SafetyTransitionError)
    case householdSize(HouseholdSizeError)
    /// Mark cooked is not available for that meal (AC-5.3, AC-9.6, R1).
    case markCooked(MarkCookedError)
    case pantryItemNotFound(PantryItemID)
    case shoppingItemNotFound(ShoppingItemID)
    case factNotFound(FactID)
    /// The ingredient is not in the taxonomy.
    case unknownIngredient(IngredientID)
    /// The meal's recipe is not in the loaded library.
    case recipeNotInLibrary(RecipeID)
    /// Input the service cannot accept (an empty name, a negative amount, a plan item that
    /// cannot be removed by hand, ...). The text is for developers, not for display.
    case invalidInput(String)
}

/// Serialises the services' read-validate-write sequences (one at a time, FIFO).
///
/// Every mutating use case runs under this lock, so a hard-rule change and an approval can
/// never interleave between "validate" and "save" (T13 review-1: rules changing between
/// validation and approval). Not re-entrant: a locked operation must not call another one.
actor ServiceLock {
    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !isLocked {
            isLocked = true
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiters.append(continuation)
        }
    }

    /// Hands the lock to the next waiter (it stays locked), or unlocks.
    func release() {
        if waiters.isEmpty {
            isLocked = false
        } else {
            let next = waiters.removeFirst()
            next.resume()
        }
    }
}

/// What every service shares: repositories, clock, recipe content, id factory, diagnostics and
/// the lock. The composition root builds one and passes it to every service.
public final class ServiceContext: Sendable {
    public let repositories: Repositories
    public let clock: any DomainClock
    public let library: PlanningLibrary
    let makeID: @Sendable () -> String
    let diagnostics: @Sendable (ServiceDiagnostic) -> Void
    let lock = ServiceLock()

    /// - Parameters:
    ///   - makeID: raw id factory for new entities (default: lowercased UUIDs).
    ///   - diagnostics: receives programmer-error reports (the app logs them).
    public init(
        repositories: Repositories,
        clock: any DomainClock,
        library: PlanningLibrary,
        makeID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() },
        diagnostics: @escaping @Sendable (ServiceDiagnostic) -> Void = { _ in }
    ) {
        self.repositories = repositories
        self.clock = clock
        self.library = library
        self.makeID = makeID
        self.diagnostics = diagnostics
    }

    /// Runs `body` while holding the service lock.
    func serialized<T>(_ body: () async throws -> T) async throws -> T {
        await lock.acquire()
        do {
            let value = try await body()
            await lock.release()
            return value
        } catch {
            await lock.release()
            throw error
        }
    }
}

/// Maps the domain's typed errors to `ServiceError`; anything else passes through.
func mappingDomainErrors<T>(_ body: () throws -> T) throws -> T {
    do {
        return try body()
    } catch let error as PlanLifecycleError {
        throw ServiceError.lifecycle(error)
    } catch let error as SafetyTransitionError {
        throw ServiceError.safetyTransition(error)
    } catch let error as HouseholdSizeError {
        throw ServiceError.householdSize(error)
    } catch let error as MarkCookedError {
        throw ServiceError.markCooked(error)
    } catch let error as PlannerError {
        switch error {
        case .clearanceNotValid: throw ServiceError.clearanceNotValid
        case .mealNotFound(let id): throw ServiceError.mealNotFound(id)
        case .mealLocked(let id): throw ServiceError.mealLocked(id)
        }
    }
}
