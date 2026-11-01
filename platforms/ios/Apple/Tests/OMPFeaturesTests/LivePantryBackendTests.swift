import Foundation
import OMPDomain
import OMPServices
import Testing

@testable import OMPFeatures

/// The live backend over the real `PantryService` and in-memory repositories: the screens' view
/// of the services (adds, voice, Mark cooked) without a UI.
@Suite("LivePantryBackend (integration)")
@MainActor
struct LivePantryBackendTests {
    private static let clock = FixedClock(now: fixtureNow, timeZone: utc)
    private static let today = LocalDate(year: 2026, month: 10, day: 12)!

    private static func ingredient(_ id: String, _ name: String, _ unit: MeasureUnit, _ location: StorageLocation)
        -> Ingredient
    {
        Ingredient(
            id: IngredientID(id), name: name, tagStatus: .verified, aisle: .grainsAndFlours, defaultUnit: unit,
            defaultLocation: location)
    }

    private static let dal = Recipe(
        id: "dal", title: "Dal rice", region: "kerala", mealTypes: [.dinner], servings: 2, prepMinutes: 5,
        cookMinutes: 20,
        ingredients: [
            RecipeIngredientLine(ingredientId: "rice", quantity: 300, unit: .gram),
            RecipeIngredientLine(ingredientId: "onion", quantity: 2, unit: .piece),
            RecipeIngredientLine(ingredientId: "ginger", quantity: 10, unit: .gram),
        ],
        steps: ["Cook."], declaredTags: [], provenance: RecipeProvenance(source: "test"),
        review: RecipeReview(status: .signedOff))

    private static func makeBackend(approved: Bool = true) async throws
        -> (LivePantryBackend, ServiceContext, MealPlan)
    {
        let library = PlanningLibrary(
            recipes: [dal],
            ingredients: [
                ingredient("rice", "Rice", .gram, .shelf), ingredient("onion", "Onion", .piece, .shelf),
                ingredient("ginger", "Ginger", .gram, .fridge),
            ], restrictions: [], contentVersion: "test")
        let context = ServiceContext(repositories: .inMemory(), clock: clock, library: library)
        let a = MemberID("a1")
        let b = MemberID("a2")
        let meal = PlannedMeal(
            id: "m1", date: today, slot: .dinner, recipeId: "dal",
            servings: [MealServing(memberId: a, portion: 1), MealServing(memberId: b, portion: 1)])
        func plan(_ approval: PlanApproval?) -> MealPlan {
            MealPlan(
                id: "p1", seriesId: "s1", revision: 1, basedOn: nil, weekStart: today,
                status: approved ? .approved : .draft, meals: [meal], approval: approval, contentVersion: "test",
                createdAt: fixtureNow)
        }
        let hash = plan(nil).contentHash
        let stored = plan(approved ? PlanApproval(approvedAt: fixtureNow, contentHash: hash) : nil)
        try await context.repositories.mealPlans.save(stored)
        return (LivePantryBackend(context: context), context, stored)
    }

    @Test("AC-9.1: add, update, reconfirm and delete go through the service")
    func crud() async throws {
        let (backend, _, _) = try await Self.makeBackend()
        let added = try await backend.add(
            PantryItemInput(name: "Rice", ingredientId: "rice", quantity: 2, unit: .kilogram, location: .shelf))
        #expect(added.item == .ingredient("rice"))
        #expect(try await backend.items().count == 1)
        let changed = try await backend.update(
            added.id, with: PantryItemInput(name: "Rice", ingredientId: "rice", quantity: 3, unit: .kilogram, location: .shelf))
        #expect(changed.quantity == 3)
        try await backend.reconfirm(added.id)
        try await backend.delete(added.id)
        #expect(try await backend.items().isEmpty)
        #expect(backend.defaults(for: "rice") == IngredientDefaults(name: "Rice", unit: .gram, location: .shelf))
        #expect(backend.defaults(for: "unknown") == nil)
    }

    @Test("AC-9.2: free text is kept as typed, never counted until matched")
    func freeText() async throws {
        let (backend, _, _) = try await Self.makeBackend()
        let item = try await backend.add(
            PantryItemInput(name: "masala mix", quantity: 1, unit: .piece, location: .shelf))
        #expect(item.item == .freeText("masala mix"))
    }

    @Test("AC-9.6: the proposal compares the recipe amounts with the pantry in the recipe's unit")
    func proposal() async throws {
        let (backend, _, _) = try await Self.makeBackend()
        _ = try await backend.add(
            PantryItemInput(name: "Rice", ingredientId: "rice", quantity: 2, unit: .kilogram, location: .shelf))
        _ = try await backend.add(
            PantryItemInput(name: "Onion", ingredientId: "onion", quantity: 1, unit: .piece, location: .shelf))
        let proposal = try await backend.cookProposal(plan: "p1", meal: "m1")
        #expect(proposal.mealTitle == "Dal rice")
        let byName = Dictionary(uniqueKeysWithValues: proposal.lines.map { ($0.name, $0) })
        #expect(byName["Rice"]?.proposed == Quantity(300, .gram))
        #expect(byName["Rice"]?.have == Quantity(2000, .gram))
        #expect(byName["Onion"]?.proposed == Quantity(2, .piece))
        #expect(byName["Onion"]?.have == Quantity(1, .piece))
        #expect(byName["Ginger"] != nil)
        #expect(byName["Ginger"]?.have == nil)
    }

    @Test("AC-9.6: Mark cooked takes the edited amounts out, never below zero, and logs the meal")
    func markCooked() async throws {
        let (backend, context, _) = try await Self.makeBackend()
        let rice = try await backend.add(
            PantryItemInput(name: "Rice", ingredientId: "rice", quantity: 2, unit: .kilogram, location: .shelf))
        let onion = try await backend.add(
            PantryItemInput(name: "Onion", ingredientId: "onion", quantity: 1, unit: .piece, location: .shelf))
        try await backend.markCooked(
            plan: "p1", meal: "m1",
            amounts: [
                CookAmount(ingredientId: "rice", quantity: Quantity(250, .gram)),
                CookAmount(ingredientId: "onion", quantity: Quantity(2, .piece)),
            ])
        let items = try await backend.items()
        let riceLeft = items.first { $0.id == rice.id }?.quantity ?? -1
        #expect(abs(riceLeft - 1.75) < 1e-9)
        #expect(items.first { $0.id == onion.id }?.quantity == 0)
        #expect(try await context.repositories.cookLogs.fetchAll().count == 1)
        let plan = try await context.repositories.mealPlans.fetch(id: "p1")
        #expect(plan?.meal("m1")?.cooked != nil)
    }

    @Test("AC-5.3, AC-9.6: a draft plan cannot be cooked, and nothing changes")
    func draftRefused() async throws {
        let (backend, context, _) = try await Self.makeBackend(approved: false)
        _ = try await backend.add(
            PantryItemInput(name: "Rice", ingredientId: "rice", quantity: 2, unit: .kilogram, location: .shelf))
        do {
            _ = try await backend.cookProposal(plan: "p1", meal: "m1")
            Issue.record("A draft plan produced a cooked sheet proposal")
        } catch let error as ServiceError {
            #expect(error == .markCooked(.planNotApproved))
        }
        do {
            try await backend.markCooked(
                plan: "p1", meal: "m1", amounts: [CookAmount(ingredientId: "rice", quantity: Quantity(250, .gram))])
            Issue.record("A draft plan was marked cooked")
        } catch let error as ServiceError {
            #expect(error == .markCooked(.planNotApproved))
        }
        #expect(try await backend.items().first?.quantity == 2)
        #expect(try await context.repositories.cookLogs.fetchAll().isEmpty)
    }

    @Test("AC-9.4: voice parses without saving; only confirmVoice stores")
    func voiceConfirmToSave() async throws {
        let (backend, _, _) = try await Self.makeBackend()
        let result = backend.parseSpoken("I bought 2 kg rice")
        #expect(result.pantryItems.count == 1)
        #expect(try await backend.items().isEmpty)
        let outcome = try await backend.confirmVoice(result.commands)
        #expect(outcome.added.count == 1)
        #expect(try await backend.items().first?.quantity == 2)
        #expect(try await backend.items().first?.source == .voice)
    }
}
