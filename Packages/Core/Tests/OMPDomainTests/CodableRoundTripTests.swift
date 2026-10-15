import Foundation
import OMPDomain
import Testing

/// Wraps a value so every round trip has a keyed top-level JSON object (no fragments).
private struct Box<Value: Codable & Equatable>: Codable, Equatable {
    let value: Value
}

/// Encodes with sorted keys (as persistence and the inbox will), decodes, and returns the
/// decoded value plus the JSON text.
private func roundTrip<Value: Codable & Equatable>(_ value: Value) throws -> (Value, String) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(Box(value: value))
    let decoded = try JSONDecoder().decode(Box<Value>.self, from: data)
    return (decoded.value, String(decoding: data, as: UTF8.self))
}

@Suite("Codable round trips")
struct CodableRoundTripTests {
    @Test("Household with members, rules and settings")
    func household() throws {
        let (decoded, _) = try roundTrip(Sample.household)
        #expect(decoded == Sample.household)
    }

    @Test("Member with every optional unset")
    func minimalMember() throws {
        let member = Member(id: "m", label: MemberLabel(role: .adult, number: 3))
        let (decoded, _) = try roundTrip(member)
        #expect(decoded == member)
    }

    @Test("Restriction, Ingredient and Recipe")
    func catalogTypes() throws {
        #expect(try roundTrip(Sample.jain).0 == Sample.jain)
        #expect(try roundTrip([Sample.ghee, Sample.hing]).0 == [Sample.ghee, Sample.hing])
        #expect(try roundTrip(Sample.recipe).0 == Sample.recipe)
    }

    @Test("MealPlan, PlannedMeal, MealServing and PlanApproval (approved and draft)")
    func plans() throws {
        #expect(try roundTrip(Sample.approvedPlan).0 == Sample.approvedPlan)
        #expect(try roundTrip(Sample.draftPlan).0 == Sample.draftPlan)
    }

    @Test("PantryItem (resolved and free text), ShoppingItem and CookLog")
    func pantryAndShopping() throws {
        let pantry = [Sample.pantryResolved, Sample.pantryFreeText]
        let shopping = [Sample.shoppingDerived, Sample.shoppingManual]
        #expect(try roundTrip(pantry).0 == pantry)
        #expect(try roundTrip(shopping).0 == shopping)
        #expect(try roundTrip(Sample.cookLog).0 == Sample.cookLog)
    }

    @Test("Fact, LearningEvent and PromptState, every case")
    func learning() throws {
        #expect(try roundTrip(Sample.facts).0 == Sample.facts)
        #expect(try roundTrip(Sample.learningEvents).0 == Sample.learningEvents)
        #expect(try roundTrip(Sample.promptStates).0 == Sample.promptStates)
    }

    @Test("ValidationReport encodes (it is deliberately not Decodable); violations round-trip")
    func validationReport() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Sample.report)
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("\"contentHash\":\"abc123\""))
        #expect(json.contains("\"planId\":\"plan-2\""))
        #expect(try roundTrip(Sample.report.violations).0 == Sample.report.violations)
    }

    @Test("GateRefusal and every ExplanationReason")
    func refusalsAndReasons() throws {
        let refusals: [GateRefusal] = [.safetyUnanswered([Sample.adultID]), .reconfirmationDue([])]
        #expect(try roundTrip(refusals).0 == refusals)
        let reasons: [ExplanationReason] = [
            .usesYourIngredient("ghee"), .usesExpiringIngredient("paneer"), .quickWeekday(.dinner),
            .goodForLunchboxes, .differentFromYesterday, .cookedOften, .cuisineYouLike("southIndian"),
            .repeatedFewSafeOptions, .lockedMealNoLongerSafe,
        ]
        #expect(try roundTrip(reasons).0 == reasons)
    }

    @Test("every raw-value enum case round-trips")
    func rawValueEnums() throws {
        #expect(try roundTrip(FoodTag.allCases).0 == FoodTag.allCases)
        #expect(try roundTrip(AgeBand.allCases).0 == AgeBand.allCases)
        #expect(try roundTrip(SafetyStatus.allCases).0 == SafetyStatus.allCases)
        #expect(try roundTrip(MeasureUnit.allCases).0 == MeasureUnit.allCases)
        #expect(try roundTrip(Aisle.allCases).0 == Aisle.allCases)
        #expect(try roundTrip(MealSlot.allCases).0 == MealSlot.allCases)
        #expect(try roundTrip(PlanStatus.allCases).0 == PlanStatus.allCases)
        #expect(try roundTrip(FactOrigin.allCases).0 == FactOrigin.allCases)
        #expect(try roundTrip(FactStatus.allCases).0 == FactStatus.allCases)
        #expect(try roundTrip(RerollReason.allCases).0 == RerollReason.allCases)
        #expect(try roundTrip(EmptyMealReason.allCases).0 == EmptyMealReason.allCases)
    }

    @Test("stable wire spellings: units, the default fact origin, dates and ids")
    func wireSpellings() throws {
        let (_, unitJSON) = try roundTrip([MeasureUnit.tablespoon, .toTaste])
        #expect(unitJSON == "{\"value\":[\"tbsp\",\"toTaste\"]}")
        let (_, originJSON) = try roundTrip(FactOrigin.appDefault)
        #expect(originJSON == "{\"value\":\"default\"}")
        let (_, planJSON) = try roundTrip(Sample.draftPlan)
        #expect(planJSON.contains("\"weekStart\":\"2026-10-12\""))
        #expect(planJSON.contains("\"seriesId\":\"series-1\""))
    }
}

/// Decodes hand-written JSON: pins the stored wire shapes so a rename or a change of Codable
/// strategy fails here instead of silently orphaning stored data. Decoding only, because
/// `Set` encoding order is not stable.
private func decode<Value: Decodable>(_ type: Value.Type, _ json: String) throws -> Value {
    try JSONDecoder().decode(type, from: Data(json.utf8))
}

@Suite("Golden JSON shapes")
struct GoldenJSONTests {
    @Test("PlannedMeal with reasons, servings and absent optionals")
    func plannedMeal() throws {
        let json = """
            {"blockedBySafety":false,"date":"2026-10-12","id":"meal-1","locked":true,
             "reasons":[{"usesYourIngredient":{"_0":"ghee"}},{"quickWeekday":{"_0":"dinner"}},{"goodForLunchboxes":{}}],
             "recipeId":"dal-tadka",
             "servings":[{"memberId":"a","notEating":false,"portion":1},{"memberId":"c","notEating":true,"portion":0.6}],
             "slot":"dinner"}
            """
        let expected = PlannedMeal(
            id: "meal-1", date: Sample.monday, slot: .dinner, recipeId: "dal-tadka", locked: true,
            servings: [
                MealServing(memberId: "a", portion: 1.0),
                MealServing(memberId: "c", portion: 0.6, notEating: true),
            ],
            reasons: [.usesYourIngredient("ghee"), .quickWeekday(.dinner), .goodForLunchboxes])
        #expect(try decode(PlannedMeal.self, json) == expected)
    }

    @Test("member-scoped Rule (dates are seconds since 2001-01-01)")
    func memberRule() throws {
        let json = """
            {"createdAt":813456000,"excludedTags":["peanut"],"id":"rule-1","kind":"hard",
             "restriction":"peanuts","scope":{"member":{"_0":"member-child-1"}},"source":"user"}
            """
        #expect(try decode(Rule.self, json) == Sample.memberRule)
    }

    @Test("both PantryItemRef cases")
    func pantryItemRef() throws {
        #expect(try decode(PantryItemRef.self, #"{"ingredient":{"_0":"ghee"}}"#) == .ingredient("ghee"))
        #expect(try decode(PantryItemRef.self, #"{"freeText":{"_0":"mystery pickle"}}"#) == .freeText("mystery pickle"))
    }

    @Test("LearningEventKind with labelled payload, optional reason present and absent")
    func learningEventKind() throws {
        let withReason = #"{"rerolled":{"recipe":"upma","slot":"breakfast","reason":"tooLong"}}"#
        let withoutReason = #"{"rerolled":{"recipe":"upma","slot":"breakfast"}}"#
        #expect(
            try decode(LearningEventKind.self, withReason)
                == .rerolled(recipe: "upma", slot: .breakfast, reason: .tooLong))
        #expect(
            try decode(LearningEventKind.self, withoutReason) == .rerolled(recipe: "upma", slot: .breakfast, reason: nil))
    }

    @Test("FactKey for a member and for the household")
    func factKey() throws {
        let member = #"{"statement":{"dislikesIngredient":{"_0":"okra"}},"subject":{"member":{"_0":"c"}}}"#
        let household = #"{"statement":{"prefersQuickWeekday":{}},"subject":{"household":{}}}"#
        #expect(
            try decode(FactKey.self, member)
                == FactKey(subject: .member("c"), statement: .dislikesIngredient("okra")))
        #expect(
            try decode(FactKey.self, household) == FactKey(subject: .household, statement: .prefersQuickWeekday))
    }
}
