import Foundation
import OMPDomain
import Testing

@testable import OMPData

/// Golden tests for the persisted JSON formats OMPData owns (TR-4). If one of these fails
/// after a domain refactor, the stored format changed: add a new DTO version and a decoding
/// branch instead of editing version 1.
@Suite("Persisted DTO formats")
struct PlanContentDTOTests {
    /// `PlanContentDTO` v1 for `richMeals()`, exactly as a v1 build writes it.
    static let planContentV1Golden = """
        {"meals":[\
        {"blockedBySafety":false,"cooked":{"cookLogId":"c1","cookedAt":813456000},"date":"2026-10-12",\
        "id":"m1","locked":true,\
        "reasons":[{"ingredientId":"rice","kind":"usesYourIngredient"},{"kind":"quickWeekday","slot":"dinner"}],\
        "recipeId":"dal-tadka",\
        "servings":[{"memberId":"a1","notEating":false,"portion":1},{"memberId":"c1","notEating":false,"portion":0.6}],\
        "slot":"dinner"},\
        {"blockedBySafety":true,"date":"2026-10-13","emptyReason":"noSafeRecipe","id":"m2","locked":false,\
        "reasons":[{"cuisineId":"southIndian","kind":"cuisineYouLike"},{"kind":"goodForLunchboxes"},\
        {"kind":"differentFromYesterday"},{"kind":"cookedOften"},\
        {"ingredientId":"curd","kind":"usesExpiringIngredient"},{"kind":"repeatedFewSafeOptions"}],\
        "servings":[{"memberId":"c1","notEating":true,"portion":0.6}],"slot":"lunchbox"}\
        ],"version":1}
        """

    static let deductionsV1Golden = """
        {"deductions":[{"pantryItemId":"a","quantity":0.2,"unit":"kg"},{"pantryItemId":"b","quantity":15,"unit":"tbsp"}],\
        "version":1}
        """

    static let deductions = [
        PantryDeduction(pantryItemId: "a", quantity: 0.2, unit: .kilogram),
        PantryDeduction(pantryItemId: "b", quantity: 15, unit: .tablespoon),
    ]

    /// Structural JSON equality (key order and `1` vs `1.0` do not matter).
    private func jsonObject(_ data: Data) throws -> NSDictionary {
        try #require(try JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }

    @Test("v1 golden plan content decodes to the expected meals")
    func goldenDecodes() throws {
        let meals = try PlanContentDTO.decodeMeals(from: Data(Self.planContentV1Golden.utf8))
        #expect(meals == richMeals())
    }

    @Test("encoding writes exactly the v1 golden structure")
    func encodingMatchesGolden() throws {
        let written = try jsonObject(PlanContentDTO.encode(richMeals()))
        let golden = try jsonObject(Data(Self.planContentV1Golden.utf8))
        #expect(written == golden)
        #expect(written["version"] as? Int == PlanContentDTO.currentVersion)
    }

    @Test("encoding is deterministic (sorted keys)")
    func encodingIsDeterministic() throws {
        #expect(try PlanContentDTO.encode(richMeals()) == PlanContentDTO.encode(richMeals()))
        let text = String(decoding: try PlanContentDTO.encode([]), as: UTF8.self)
        #expect(text == #"{"meals":[],"version":1}"#)
    }

    @Test("a newer content version is refused, not misread")
    func newerVersionIsRefused() {
        let data = Data(#"{"meals":[],"version":2}"#.utf8)
        #expect(throws: PersistenceError.unsupportedPlanContentVersion(2)) {
            try PlanContentDTO.decodeMeals(from: data)
        }
    }

    @Test("content without a version, or not JSON, is unreadable")
    func missingVersionIsUnreadable() {
        #expect(throws: PersistenceError.unreadablePlanContent(planId: "p")) {
            try PlanContentDTO.decodeMeals(from: Data(#"{"meals":[]}"#.utf8), planId: "p")
        }
        #expect(throws: PersistenceError.unreadablePlanContent(planId: "p")) {
            try PlanContentDTO.decodeMeals(from: Data(), planId: "p")
        }
    }

    @Test("an unknown slot or reason kind in v1 content is refused")
    func unknownValuesAreRefused() {
        let badSlot = Data(
            #"{"meals":[{"blockedBySafety":false,"date":"2026-10-12","id":"m","locked":false,"reasons":[],"servings":[],"slot":"brunch"}],"version":1}"#
                .utf8)
        #expect(throws: PersistenceError.invalidValue(entity: "PlannedMeal", field: "slot", value: "brunch")) {
            try PlanContentDTO.decodeMeals(from: badSlot)
        }
        let badReason = Data(
            #"{"meals":[{"blockedBySafety":false,"date":"2026-10-12","id":"m","locked":false,"reasons":[{"kind":"tasty"}],"servings":[],"slot":"dinner"}],"version":1}"#
                .utf8)
        #expect(throws: PersistenceError.invalidValue(entity: "PlannedMeal", field: "reason.kind", value: "tasty")) {
            try PlanContentDTO.decodeMeals(from: badReason)
        }
    }

    @Test("cook-log deductions v1: golden decodes, encoding matches, newer version refused")
    func deductionsGolden() throws {
        let golden = Data(Self.deductionsV1Golden.utf8)
        #expect(try PantryDeductionsDTO.decode(from: golden) == Self.deductions)
        #expect(try jsonObject(PantryDeductionsDTO.encode(Self.deductions)) == jsonObject(golden))
        #expect(throws: PersistenceError.unsupportedDeductionsVersion(2)) {
            try PantryDeductionsDTO.decode(from: Data(#"{"deductions":[],"version":2}"#.utf8))
        }
        #expect(throws: PersistenceError.unreadableDeductions(cookLogId: "c")) {
            try PantryDeductionsDTO.decode(from: Data(), cookLogId: "c")
        }
    }
}
