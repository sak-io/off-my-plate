import Foundation
import OMPDomain
import OMPSafetyCheck
import OMPServices
import Testing

/// A clock tests can move forward.
final class TestClock: DomainClock, @unchecked Sendable {
    private let lock = NSLock()
    private var instant: Date
    let timeZone: TimeZone

    init(now: Date, timeZone: TimeZone) {
        self.instant = now
        self.timeZone = timeZone
    }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return instant
    }

    func advance(days: Int) {
        lock.lock()
        defer { lock.unlock() }
        instant = instant.addingTimeInterval(Double(days) * 86_400)
    }
}

/// Deterministic ids: "id-1", "id-2", ...
final class IDCounter: @unchecked Sendable {
    private let lock = NSLock()
    private let prefix: String
    private var next = 0

    init(prefix: String = "id") {
        self.prefix = prefix
    }

    func make() -> String {
        lock.lock()
        defer { lock.unlock() }
        next += 1
        return "\(prefix)-\(next)"
    }
}

/// Collects service diagnostics.
final class DiagnosticsRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [ServiceDiagnostic] = []

    func record(_ diagnostic: ServiceDiagnostic) {
        lock.lock()
        defer { lock.unlock() }
        stored.append(diagnostic)
    }

    var all: [ServiceDiagnostic] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}

/// A hand-built recipe library and service wiring for the T18 tests.
///
/// Each of breakfast, lunch and dinner has exactly three recipes, so with the 3-day variety
/// rule every recipe of a slot appears in a 7-day plan; in particular the peanut breakfast
/// `b-poha` is always planned for a household without a peanut rule.
enum ServicesFixture {
    static let utc = TimeZone(identifier: "UTC")!
    static let now = Date(timeIntervalSince1970: 1_791_763_200)  // 2026-10-12T00:00:00Z, a Monday
    static let today = LocalDate(year: 2026, month: 10, day: 12)!

    static let peanut: RestrictionID = "peanut"
    static let milk: RestrictionID = "milk"
    static let peanutRecipe: RecipeID = "b-poha"

    static func ingredient(_ id: IngredientID, tags: Set<FoodTag> = [], mayContain: Set<FoodTag> = []) -> Ingredient {
        Ingredient(
            id: id, name: id.rawValue, tags: tags, mayContain: mayContain, tagStatus: .verified, aisle: .other,
            defaultUnit: .gram, defaultLocation: .shelf)
    }

    static func ingredients(uradMayContainPeanut: Bool = false) -> [Ingredient] {
        [
            ingredient("rice"),
            ingredient("urad", mayContain: uradMayContainPeanut ? [.peanut] : []),
            ingredient("poha-flakes"),
            ingredient("peanuts", tags: [.peanut]),
            ingredient("semolina", tags: [.wheat, .gluten]),
            ingredient("vegetables"),
            ingredient("toor-dal"),
            ingredient("rajma"),
            ingredient("curd", tags: [.milk]),
            ingredient("atta", tags: [.wheat, .gluten]),
            ingredient("lemon"),
            ingredient("chana"),
        ]
    }

    static func recipe(_ id: RecipeID, _ types: Set<MealType>, _ lines: [IngredientID], lunchbox: Bool = false) -> Recipe {
        Recipe(
            id: id, title: id.rawValue, region: "southIndian", mealTypes: types, lunchboxSuitable: lunchbox,
            servings: 4, prepMinutes: 10, cookMinutes: 20,
            ingredients: lines.map { RecipeIngredientLine(ingredientId: $0, quantity: 100, unit: .gram) },
            steps: ["Cook."], declaredTags: [], provenance: RecipeProvenance(source: "test"),
            review: RecipeReview(status: .signedOff))
    }

    static let recipes: [Recipe] = [
        recipe("b-idli", [.breakfast], ["rice", "urad"]),
        recipe("b-poha", [.breakfast], ["poha-flakes", "peanuts"]),
        recipe("b-upma", [.breakfast], ["semolina", "vegetables"]),
        recipe("l-rajma", [.lunch], ["rajma", "rice"]),
        recipe("l-sambar", [.lunch], ["toor-dal", "rice", "vegetables"]),
        recipe("l-curd-rice", [.lunch], ["curd", "rice"]),
        recipe("d-dal", [.dinner], ["toor-dal", "rice"]),
        recipe("d-chapati", [.dinner], ["atta", "vegetables"]),
        recipe("d-pulao", [.dinner], ["rice", "vegetables"]),
        recipe("x-lemon-rice", [], ["rice", "lemon"], lunchbox: true),
        recipe("x-paratha", [], ["atta", "vegetables"], lunchbox: true),
        recipe("x-chana", [], ["chana"], lunchbox: true),
    ]

    static let restrictions: [Restriction] = [
        Restriction(id: peanut, labelKey: "restriction.peanut", excludedTags: [.peanut]),
        Restriction(id: milk, labelKey: "restriction.milk", excludedTags: [.milk]),
    ]

    static func library(version: String = "test-1", uradMayContainPeanut: Bool = false) -> PlanningLibrary {
        PlanningLibrary(
            recipes: recipes, ingredients: ingredients(uradMayContainPeanut: uradMayContainPeanut),
            restrictions: restrictions, contentVersion: version)
    }

    static func safetyLibrary(uradMayContainPeanut: Bool = false) -> SafetyCheckLibrary {
        SafetyCheckLibrary(recipes: recipes, ingredients: ingredients(uradMayContainPeanut: uradMayContainPeanut))
    }
}

/// One wired set of services over in-memory repositories.
struct ServicesEnv: Sendable {
    let repositories: Repositories
    let clock: TestClock
    let diagnostics: DiagnosticsRecorder
    let context: ServiceContext
    let households: HouseholdService
    let safety: SafetyService
    let plans: PlanService
    let lunchbox: LunchboxService

    init(
        library: PlanningLibrary = ServicesFixture.library(),
        repositories: Repositories = .inMemory(),
        clock: TestClock = TestClock(now: ServicesFixture.now, timeZone: ServicesFixture.utc),
        idPrefix: String = "id"
    ) {
        let ids = IDCounter(prefix: idPrefix)
        let diagnostics = DiagnosticsRecorder()
        self.repositories = repositories
        self.clock = clock
        self.diagnostics = diagnostics
        self.context = ServiceContext(
            repositories: repositories, clock: clock, library: library, makeID: { ids.make() },
            diagnostics: { diagnostics.record($0) })
        self.households = HouseholdService(context: context)
        self.safety = SafetyService(context: context)
        self.plans = PlanService(context: context)
        self.lunchbox = LunchboxService(context: context)
    }

    /// The same repositories and clock with another library (a seed update).
    func withLibrary(_ library: PlanningLibrary) -> ServicesEnv {
        ServicesEnv(library: library, repositories: repositories, clock: clock, idPrefix: library.contentVersion)
    }

    /// Onboarding with one adult and one child who both avoid nothing.
    @discardableResult
    func onboardWithoutRules() async throws -> Household {
        try await households.createHousehold(adults: 1, children: 1)
        return try await safety.confirmNobodyAvoidsAnything().household
    }

    /// Onboarding, a generated draft and its approval.
    func approvedWeek() async throws -> MealPlan {
        try await onboardWithoutRules()
        let draft = try await plans.generateWeek()
        return try await plans.approve(draft.plan.id, confirmation: UserConfirmation()).approved
    }

    func storedPlan(_ id: MealPlanID) async throws -> MealPlan {
        let plan = try await repositories.mealPlans.fetch(id: id)
        return try #require(plan)
    }

    func household() async throws -> Household {
        let household = try await repositories.household.fetch()
        return try #require(household)
    }
}

/// The `ServiceError` thrown by `body`, or `nil` (recording an issue) if it threw something else
/// or nothing.
func serviceError(_ body: () async throws -> Void) async -> ServiceError? {
    do {
        try await body()
        Issue.record("expected a ServiceError, but nothing was thrown")
        return nil
    } catch let error as ServiceError {
        return error
    } catch {
        Issue.record("unexpected error: \(error)")
        return nil
    }
}

extension MealPlan {
    /// The meals that use `recipe`.
    func meals(using recipe: RecipeID) -> [PlannedMeal] {
        meals.filter { $0.recipeId == recipe }
    }
}
