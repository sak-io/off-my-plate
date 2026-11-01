import Foundation
import OMPDomain
import Testing

@Suite("Plan content hash and effective approval (ADR 0008, AC-5.5)")
struct PlanContentHashTests {
    @Test("the canonical encoding is pinned: sorted keys, sorted meals, null for an empty recipe")
    func goldenEncoding() {
        let plan = PlanFixture.draft(meals: [
            PlanFixture.meal("b", day: 1, slot: .lunch, recipe: "poha", locked: true),
            PlanFixture.meal("a", day: 0, slot: .dinner, recipe: nil),
        ])
        let expected =
            #"{"meals":[{"date":"2026-10-12","locked":false,"recipeId":null,"servings":[{"memberId":"m-adult","notEating":false,"portion":1.0},{"memberId":"m-child","notEating":false,"portion":0.6}],"slot":"dinner"},"#
            + #"{"date":"2026-10-13","locked":true,"recipeId":"poha","servings":[{"memberId":"m-adult","notEating":false,"portion":1.0},{"memberId":"m-child","notEating":false,"portion":0.6}],"slot":"lunch"}],"weekStart":"2026-10-12"}"#
        #expect(plan.canonicalContent == expected)
        // Independently computed (Python hashlib) over the same bytes.
        #expect(plan.contentHash == "7c913135e425595b842fa39b9403874d1d6fa4f77fedad5ee718a062f42086bd")
        #expect(plan.contentHash == SHA256.hexDigest(of: expected))
    }

    @Test("cooking, explanations, empty reason, safety flag, meal ids and plan metadata don't change the hash")
    func excludedFieldsDoNotChangeHash() {
        let plan = PlanFixture.draft()
        var changed = plan
        changed.meals[0].cooked = CookRef(cookLogId: "cook-1", cookedAt: Sample.later)
        changed.meals[0].reasons = [.quickWeekday(.dinner), .cookedOften]
        changed.meals[1].emptyReason = .removedByValidator
        changed.meals[2].blockedBySafety = true
        changed.meals[2] = PlannedMeal(
            id: "renamed", date: changed.meals[2].date, slot: changed.meals[2].slot,
            recipeId: changed.meals[2].recipeId, locked: changed.meals[2].locked, servings: changed.meals[2].servings,
            blockedBySafety: true)
        changed.status = .approved
        changed.revision = 4
        changed.basedOn = "plan-0"
        changed.seriesId = "series-9"
        changed.contentVersion = "seed-2"
        changed.createdAt = Sample.later
        changed.approval = PlanApproval(approvedAt: Sample.later, contentHash: "x")
        #expect(changed.contentHash == plan.contentHash)
    }

    @Test("meal order and serving order don't change the hash; -0.0 equals 0.0")
    func orderIndependence() {
        let plan = PlanFixture.draft()
        var reordered = plan
        reordered.meals.reverse()
        reordered.meals[0].servings.reverse()
        #expect(reordered.contentHash == plan.contentHash)

        var zero = plan
        zero.meals[0].servings[0].portion = 0.0
        var negativeZero = plan
        negativeZero.meals[0].servings[0].portion = -0.0
        #expect(zero.contentHash == negativeZero.contentHash)
    }

    @Test("every content field changes the hash")
    func includedFieldsChangeHash() {
        let plan = PlanFixture.draft()
        let mutations: [(String, (inout MealPlan) -> Void)] = [
            ("recipe", { $0.meals[0].recipeId = "poha" }),
            ("emptied", { $0.meals[0].recipeId = nil }),
            ("locked", { $0.meals[0].locked.toggle() }),
            ("portion", { $0.meals[0].servings[1].portion = 0.4 }),
            ("not eating", { $0.meals[0].servings[1].notEating = true }),
            ("member", { $0.meals[0].servings[1].memberId = "m-other" }),
            ("serving added", { $0.meals[0].servings.append(MealServing(memberId: "m-new", portion: 1)) }),
            ("date", { $0.meals[0].date = Sample.monday.adding(days: 5) }),
            ("slot", { $0.meals[0].slot = .lunch }),
            ("week start", { $0.weekStart = Sample.monday.adding(days: 1) }),
            ("meal added", { $0.meals.append(PlanFixture.meal("meal-9", day: 3, slot: .lunchbox)) }),
            ("meal removed", { _ = $0.meals.removeLast() }),
        ]
        var hashes: Set<String> = [plan.contentHash]
        for (name, mutate) in mutations {
            var changed = plan
            mutate(&changed)
            #expect(changed.contentHash != plan.contentHash, "\(name) should change the hash")
            hashes.insert(changed.contentHash)
        }
        #expect(hashes.count == mutations.count + 1)
    }

    @Test("ids with quotes, backslashes and control characters are escaped, so they can't forge structure")
    func escaping() {
        let plan = PlanFixture.draft(meals: [PlanFixture.meal("m", recipe: RecipeID("a\"b\\c\nd\u{1}"))])
        #expect(plan.canonicalContent.contains(#""recipeId":"a\"b\\c\nd\u0001""#))
    }

    @Test("an approved plan with an unchanged hash is effectively approved")
    func effectivelyApproved() throws {
        let plan = try PlanFixture.approved()
        #expect(plan.isEffectivelyApproved)
        #expect(plan.usableApprovedMeals == plan.meals)
    }

    @Test("AC-5.5: tampering with any meal voids effective approval")
    func tamperVoidsApproval() throws {
        var plan = try PlanFixture.approved()
        plan.meals[1].recipeId = "chole-chawal"
        #expect(plan.status == .approved)
        #expect(!plan.isEffectivelyApproved)
        #expect(plan.usableApprovedMeals.isEmpty)
    }

    @Test("cooking a meal keeps the plan effectively approved")
    func cookingKeepsApproval() throws {
        var plan = try PlanFixture.approved()
        plan.meals[0].cooked = CookRef(cookLogId: "cook-1", cookedAt: Sample.later)
        #expect(plan.isEffectivelyApproved)
    }

    @Test("a draft, a superseded plan or a plan without an approval record is not effectively approved")
    func notApprovedStatuses() throws {
        let approved = try PlanFixture.approved()
        for status in [PlanStatus.draft, .superseded, .discarded] {
            var plan = approved
            plan.status = status
            #expect(!plan.isEffectivelyApproved)
        }
        var missingRecord = approved
        missingRecord.approval = nil
        #expect(!missingRecord.isEffectivelyApproved)
    }

    @Test("R1: blocked meals are excluded from the usable meals")
    func blockedMealsExcluded() throws {
        var plan = try PlanFixture.approved()
        plan.meals[1].blockedBySafety = true
        #expect(plan.isEffectivelyApproved)
        #expect(plan.usableApprovedMeals.map(\.id) == ["meal-1", "meal-3"])
    }
}
