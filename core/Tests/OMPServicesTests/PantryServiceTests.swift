import Foundation
import OMPDomain
import OMPServices
import Testing

@Suite("PantryService: CRUD, voice confirm-to-save and Mark cooked (AC-9.x, T19)")
struct PantryServiceTests {
    @Test("a manual item is saved with source manual; a known name resolves, an unknown one stays free text (AC-9.1, AC-9.2)")
    func addManual() async throws {
        let env = ServicesBEnv()
        let rice = try await env.pantry.add(
            PantryItemInput(name: "  Rice ", quantity: 2, unit: .kilogram, location: .shelf))
        #expect(rice.item == .ingredient("rice"))
        #expect(rice.source == .manual)
        #expect(rice.lastConfirmedAt == ServicesFixture.now)

        let pickle = try await env.pantry.add(
            PantryItemInput(name: "Mango pickle", quantity: 1, unit: .piece, location: .shelf))
        #expect(pickle.item == .freeText("Mango pickle"))
        #expect(try await env.pantry.items().count == 2)
    }

    @Test("empty names and impossible amounts are refused and nothing is saved")
    func addRefusesBadInput() async throws {
        let env = ServicesBEnv()
        let blank = await serviceError {
            _ = try await env.pantry.add(PantryItemInput(name: "   ", quantity: 1, unit: .piece, location: .shelf))
        }
        guard case .invalidInput? = blank else {
            Issue.record("expected invalidInput, got \(String(describing: blank))")
            return
        }
        for bad in [-1.0, Double.nan, Double.infinity] {
            let error = await serviceError {
                _ = try await env.pantry.add(
                    PantryItemInput(name: "rice", quantity: bad, unit: .gram, location: .shelf))
            }
            guard case .invalidInput? = error else {
                Issue.record("expected invalidInput for \(bad), got \(String(describing: error))")
                return
            }
        }
        let unknown = await serviceError {
            _ = try await env.pantry.add(
                PantryItemInput(name: "x", ingredientId: "no-such", quantity: 1, unit: .gram, location: .shelf))
        }
        #expect(unknown == .unknownIngredient("no-such"))
        #expect(try await env.pantry.items().isEmpty)
    }

    @Test("pantry changes re-derive the shopping list; free text does not cover a need until resolved (AC-9.2, AC-9.3)")
    func changesRederiveList() async throws {
        let env = ServicesBEnv()
        _ = try await env.base.approvedWeek()
        try await env.shopping.refresh()
        let needed = try await env.lines(for: ServicesBFixture.rice, origin: .plan)
        try #require(!needed.isEmpty)

        // Free text never counts toward plan needs (AC-9.2).
        let basmati = try await env.pantry.add(
            PantryItemInput(name: "Basmati", quantity: 100, unit: .kilogram, location: .shelf))
        #expect(basmati.item == .freeText("Basmati"))
        #expect(try await env.lines(for: ServicesBFixture.rice, origin: .plan) == needed)

        // Resolving it lets it cover the need.
        let resolved = try await env.pantry.resolve(basmati.id, to: ServicesBFixture.rice)
        #expect(resolved.item == .ingredient("rice"))
        #expect(try await env.lines(for: ServicesBFixture.rice, origin: .plan).isEmpty)

        // Editing it down brings the line back; deleting it too (AC-9.3).
        _ = try await env.pantry.update(
            basmati.id, with: PantryItemInput(name: "rice", quantity: 1, unit: .gram, location: .shelf))
        let backAgain = try await env.lines(for: ServicesBFixture.rice, origin: .plan)
        #expect(!backAgain.isEmpty)
        _ = try await env.pantry.update(
            basmati.id, with: PantryItemInput(name: "rice", quantity: 100, unit: .kilogram, location: .shelf))
        #expect(try await env.lines(for: ServicesBFixture.rice, origin: .plan).isEmpty)
        try await env.pantry.delete(basmati.id)
        let afterDelete = try await env.lines(for: ServicesBFixture.rice, origin: .plan)
        #expect(!afterDelete.isEmpty)

        let missing = await serviceError { try await env.pantry.delete("nope") }
        #expect(missing == .pantryItemNotFound("nope"))
    }

    @Test("voice is confirm-to-save: parsing saves nothing, confirming applies add, out and remove (AC-9.4)")
    func voiceConfirmToSave() async throws {
        let env = ServicesBEnv()
        let parsed = env.pantry.parseSpoken("I bought 2 kg rice")
        #expect(!parsed.commands.isEmpty)
        #expect(try await env.pantry.items().isEmpty)

        let outcome = try await env.pantry.confirmVoice([
            .add([spoken("rice", qty: 2, unit: .kilogram), spoken("eggs", qty: 12)])
        ])
        #expect(outcome.added.count == 2)
        let items = try await env.pantry.items()
        #expect(items.allSatisfy { $0.source == .voice })
        let eggs = try #require(items.first { $0.item == .ingredient("eggs") })
        #expect(eggs.quantity == 12)
        #expect(eggs.unit == .piece)
        // Fridge items with a known shelf life get a use-by day.
        #expect(eggs.expiresOn == ServicesFixture.today.adding(days: 14))

        let out = try await env.pantry.confirmVoice([.markOut([spoken("rice")])])
        #expect(out.markedOut.count == 1)
        let afterOut = try await env.pantry.items()
        let riceAfterOut = afterOut.first { $0.item == .ingredient("rice") }
        #expect(riceAfterOut?.quantity == 0)

        let removed = try await env.pantry.confirmVoice([.remove([spoken("rice")]), .openApprovalSheet])
        #expect(removed.removed.count == 1)
        #expect(try await env.pantry.items().map(\.item) == [.ingredient("eggs")])
    }

    // MARK: Mark cooked

    /// A meal of `plan` whose recipe uses rice.
    private func riceMeal(in plan: MealPlan, library: PlanningLibrary) throws -> PlannedMeal {
        var found: PlannedMeal?
        for meal in plan.meals {
            guard let recipeID = meal.recipeId, let recipe = library.recipesByID[recipeID] else { continue }
            if recipe.ingredients.contains(where: { $0.ingredientId == ServicesBFixture.rice }) {
                found = meal
                break
            }
        }
        return try #require(found)
    }

    @Test("Mark cooked is refused on a draft (AC-5.3, AC-9.6)")
    func markCookedRefusedOnDraft() async throws {
        let env = ServicesBEnv()
        try await env.base.onboardWithoutRules()
        let draft = try await env.base.plans.generateWeek().plan
        let meal = try #require(draft.meals.first { $0.recipeId != nil })
        let error = await serviceError { _ = try await env.pantry.markCooked(plan: draft.id, meal: meal.id) }
        #expect(error == .markCooked(.planNotApproved))
        let proposal = await serviceError { _ = try await env.pantry.proposedCookAmounts(plan: draft.id, meal: meal.id) }
        #expect(proposal == .markCooked(.planNotApproved))
        #expect(try await env.repositories.cookLogs.fetchAll().isEmpty)
    }

    @Test("Mark cooked deducts, never below zero, writes the log, the meal link and a cooked event (AC-9.6, AC-12.1)")
    func markCookedDeducts() async throws {
        let env = ServicesBEnv()
        let approved = try await env.base.approvedWeek()
        let meal = try riceMeal(in: approved, library: env.base.context.library)
        let recipeID = try #require(meal.recipeId)

        let proposed = try await env.pantry.proposedCookAmounts(plan: approved.id, meal: meal.id)
        let riceAmount = try #require(proposed.first { $0.ingredientId == ServicesBFixture.rice })
        #expect(riceAmount.quantity.amount > 0)

        // 10 g in the pantry: less than the meal needs, so it goes to exactly zero, not below.
        let item = try await env.pantry.add(
            PantryItemInput(name: "rice", quantity: 10, unit: .gram, location: .shelf))
        let log = try await env.pantry.markCooked(plan: approved.id, meal: meal.id)
        #expect(log.recipeId == recipeID)
        #expect(log.planId == approved.id)
        #expect(log.mealId == meal.id)
        #expect(log.deductions == [PantryDeduction(pantryItemId: item.id, quantity: 10, unit: .gram)])
        let after = try #require(try await env.repositories.pantry.fetch(id: item.id))
        #expect(after.quantity == 0)

        #expect(try await env.repositories.cookLogs.fetchAll() == [log])
        let stored = try await env.base.storedPlan(approved.id)
        #expect(stored.meal(meal.id)?.cooked?.cookLogId == log.id)
        // Cooking never voids the approval (ADR 0008).
        #expect(stored.isEffectivelyApproved)
        #expect(try await env.events().contains { $0.kind == .cooked(recipe: recipeID) })

        let again = await serviceError { _ = try await env.pantry.markCooked(plan: approved.id, meal: meal.id) }
        #expect(again == .markCooked(.alreadyCooked(meal.id)))
    }

    @Test("edited amounts on the confirm sheet are what is deducted (AC-9.6)")
    func markCookedUsesEditedAmounts() async throws {
        let env = ServicesBEnv()
        let approved = try await env.base.approvedWeek()
        let meal = try riceMeal(in: approved, library: env.base.context.library)
        let item = try await env.pantry.add(
            PantryItemInput(name: "rice", quantity: 1, unit: .kilogram, location: .shelf))

        let log = try await env.pantry.markCooked(
            plan: approved.id, meal: meal.id,
            amounts: [CookAmount(ingredientId: ServicesBFixture.rice, quantity: Quantity(250, .gram))])
        #expect(log.deductions.count == 1)
        let after = try #require(try await env.repositories.pantry.fetch(id: item.id))
        #expect(abs(after.quantity - 0.75) < 1e-9)
    }

    @Test("unknown plans and meals are reported")
    func markCookedUnknown() async throws {
        let env = ServicesBEnv()
        let approved = try await env.base.approvedWeek()
        let noPlan = await serviceError { _ = try await env.pantry.markCooked(plan: "nope", meal: "x") }
        #expect(noPlan == .planNotFound("nope"))
        let noMeal = await serviceError { _ = try await env.pantry.markCooked(plan: approved.id, meal: "nope") }
        #expect(noMeal == .markCooked(.mealNotFound("nope")))
    }
}
