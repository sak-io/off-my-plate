import Foundation
import OMPDomain
import Testing

@Suite("Plan diff for the approval sheet (AC-5.4, S-13 Was/Now)")
struct PlanDiffTests {
    typealias Fixture = PlanFixture

    private func diff(_ change: (inout [PlannedMeal]) -> Void) -> PlanDiff {
        let old = Fixture.draft()
        var new = Fixture.draft(id: "plan-2")
        change(&new.meals)
        return PlanDiff(from: old, to: new)
    }

    @Test("identical content gives an empty diff")
    func identical() {
        let result = diff { _ in }
        #expect(result.isEmpty)
        #expect(result.listedChanges.isEmpty)
    }

    @Test("cooking, explanations, blocked flags and serving order are not changes")
    func ignoredFields() {
        let result = diff { meals in
            meals[0].cooked = CookRef(cookLogId: "cook-1", cookedAt: Sample.later)
            meals[1].reasons = [.cookedOften]
            meals[2].blockedBySafety = true
            meals[2].servings.reverse()
        }
        #expect(result.isEmpty)
    }

    @Test("a different recipe is a swap with Was and Now")
    func swapped() throws {
        let result = diff { meals in meals[1].recipeId = "chole-chawal" }
        let change = try #require(result.changes.first)
        #expect(result.changes.count == 1)
        #expect(change.kinds == [.swapped])
        #expect(change.was?.recipeId == "rajma-chawal")
        #expect(change.now?.recipeId == "chole-chawal")
        #expect(change.date == Sample.monday.adding(days: 1) && change.slot == .lunch)
        #expect(change.isListed)
    }

    @Test("filling an empty slot is a swap from nothing")
    func filledFromEmpty() throws {
        let old = Fixture.draft(meals: [Fixture.meal("meal-1", recipe: nil)])
        let new = Fixture.draft(id: "plan-2", meals: [Fixture.meal("meal-1", recipe: "poha")])
        let change = try #require(PlanDiff(from: old, to: new).changes.first)
        #expect(change.kinds == [.swapped])
        #expect(change.was?.recipeId == nil && change.now?.recipeId == "poha")
    }

    @Test("a slot that loses its recipe is emptied")
    func emptied() throws {
        let result = diff { meals in meals[0].recipeId = nil }
        let change = try #require(result.changes.first)
        #expect(change.kinds == [.emptied])
        #expect(change.was?.recipeId == "dal-tadka" && change.now?.isEmpty == true)
    }

    @Test("a new slot is added; a dropped slot is removed")
    func addedAndRemoved() {
        let result = diff { meals in
            meals.append(Fixture.meal("lunchbox-1", day: 0, slot: .lunchbox, recipe: "poha"))
            meals.removeAll { $0.id == "meal-3" }
        }
        #expect(result.changes.map(\.kinds) == [[.added], [.removed]])
        #expect(result.changes[0].was == nil && result.changes[0].now?.id == "lunchbox-1")
        #expect(result.changes[1].was?.id == "meal-3" && result.changes[1].now == nil)
    }

    @Test(
        "portion, not-eating and member changes are servings changes",
        arguments: [
            "portion", "notEating", "memberAdded",
        ])
    func servingsChanged(change: String) throws {
        let result = diff { meals in
            switch change {
            case "portion": meals[0].servings[1].portion = 0.4
            case "notEating": meals[0].servings[1].notEating = true
            default: meals[0].servings.append(MealServing(memberId: "m-child-3", portion: 0.6))
            }
        }
        let only = try #require(result.changes.first)
        #expect(result.changes.count == 1)
        #expect(only.kinds == [.servingsChanged])
        #expect(only.isListed)
    }

    @Test("a lock-only change is in the diff but not listed on S-13")
    func lockOnly() throws {
        let result = diff { meals in meals[2].locked = false }
        let change = try #require(result.changes.first)
        #expect(change.kinds == [.lockChanged])
        #expect(!change.isListed)
        #expect(result.listedChanges.isEmpty)
        #expect(!result.isEmpty)
    }

    @Test("several kinds on one meal are reported together in a fixed order")
    func multipleKinds() throws {
        let result = diff { meals in
            meals[0].locked = true
            meals[0].servings[0].portion = 1.2
            meals[0].recipeId = "poha"
        }
        let change = try #require(result.changes.first)
        #expect(change.kinds == [.swapped, .servingsChanged, .lockChanged])
        #expect(change.isListed)
    }

    @Test("meals with new ids are paired by date and slot (regenerate)")
    func pairsByDateAndSlot() {
        let old = Fixture.draft()
        let new = Fixture.draft(
            id: "plan-2",
            meals: [
                Fixture.meal("new-1", day: 0, slot: .dinner, recipe: "dal-tadka"),
                Fixture.meal("new-2", day: 1, slot: .lunch, recipe: "chole-chawal"),
                Fixture.meal("new-3", day: 2, slot: .dinner, recipe: "aloo-gobi", locked: true),
            ])
        let result = PlanDiff(from: old, to: new)
        #expect(result.changes.map(\.kinds) == [[.swapped], [.swapped]])
        #expect(result.changes.map { $0.was?.recipeId } == ["rajma-chawal", "palak-paneer"])
        #expect(result.changes.map { $0.now?.recipeId } == ["chole-chawal", "aloo-gobi"])
    }

    @Test("changes are ordered by date, then slot order, then meal id")
    func ordering() {
        let old = Fixture.draft(meals: [])
        let new = Fixture.draft(
            id: "plan-2",
            meals: [
                Fixture.meal("z", day: 1, slot: .breakfast),
                Fixture.meal("y", day: 0, slot: .lunchbox),
                Fixture.meal("b", day: 0, slot: .lunch),
                Fixture.meal("a", day: 0, slot: .lunch),
                Fixture.meal("x", day: 0, slot: .breakfast),
            ])
        let result = PlanDiff(from: old, to: new)
        #expect(result.changes.compactMap { $0.now?.id } == ["x", "a", "b", "y", "z"])
        #expect(result.listedChanges.count == 5)
    }

    @Test("the S-13 example: two swaps give 'Approve 2 changes?'")
    func screenExample() throws {
        let approved = try Fixture.approved()
        let revision = try PlanLifecycle.edit(approved, newRevisionId: "plan-2", now: Sample.later) { meals in
            meals[1].recipeId = "chole-chawal"
            meals[2].recipeId = "aloo-gobi"
            meals[0].locked = true
        }
        let result = PlanDiff(from: approved, to: revision)
        #expect(result.listedChanges.count == 2)
        #expect(result.listedChanges.map { $0.now?.recipeId } == ["chole-chawal", "aloo-gobi"])
        #expect(result.changes.count == 3)
    }

    @Test("a meal moved to another day or slot shows as changes at both places")
    func movedMeal() {
        let moved = diff { meals in
            meals[0].date = Sample.monday.adding(days: 3)
            meals[0].slot = .lunch
        }
        #expect(moved.changes.map(\.kinds) == [[.removed], [.added]])
        #expect(moved.changes[0].was?.id == "meal-1" && moved.changes[1].now?.id == "meal-1")

        // Moved onto an occupied slot: the old slot is removed, the new one gains a meal.
        let onto = diff { meals in
            meals[0].date = Sample.monday.adding(days: 1)
            meals[0].slot = .lunch
        }
        #expect(onto.changes.map(\.kinds) == [[.removed], [.added]])
        #expect(onto.listedChanges.count == 2)
    }

    @Test("whenever a meal edit changes the hash, the diff lists it (lock-only: in changes)")
    func hashChangeImpliesDiff() {
        let mutations: [(String, (inout [PlannedMeal]) -> Void)] = [
            ("recipe", { $0[0].recipeId = "poha" }),
            ("emptied", { $0[0].recipeId = nil }),
            ("portion", { $0[0].servings[1].portion = 0.4 }),
            ("not eating", { $0[0].servings[1].notEating = true }),
            ("member", { $0[0].servings[1].memberId = "m-other" }),
            ("serving added", { $0[0].servings.append(MealServing(memberId: "m-new", portion: 1)) }),
            ("date", { $0[0].date = Sample.monday.adding(days: 5) }),
            ("slot", { $0[0].slot = .lunch }),
            ("date onto occupied slot", { $0[0].date = Sample.monday.adding(days: 2) }),
            ("meal added", { $0.append(Fixture.meal("meal-9", day: 3, slot: .lunchbox)) }),
            ("meal removed", { _ = $0.removeLast() }),
        ]
        let old = Fixture.draft()
        for (name, mutate) in mutations {
            var new = Fixture.draft(id: "plan-2")
            mutate(&new.meals)
            #expect(new.contentHash != old.contentHash, "\(name) should change the hash")
            #expect(!PlanDiff(from: old, to: new).listedChanges.isEmpty, "\(name) should be listed")
        }
        var locked = Fixture.draft(id: "plan-2")
        locked.meals[0].locked = true
        #expect(locked.contentHash != old.contentHash)
        #expect(!PlanDiff(from: old, to: locked).isEmpty)
    }
}
