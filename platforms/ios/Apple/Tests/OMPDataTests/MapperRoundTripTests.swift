import Foundation
import OMPDomain
import SwiftData
import Testing

@testable import OMPData

/// Domain -> record -> domain for every record type and every enum case (ADR 0003).
/// Records live in a throwaway in-memory context; nothing is saved.
@Suite("Record mappers")
struct MapperRoundTripTests {
    @Test("members and rules round-trip, including soft delete, school days and both scopes")
    func memberAndRule() throws {
        let scratch = try Scratch()
        let household = richHousehold()
        for (index, member) in household.members.enumerated() {
            let record = scratch.inserted(MemberRecord(id: ""))
            try record.apply(member, sortIndex: index)
            #expect(record.sortIndex == index)
            #expect(try record.domain() == member)
        }
        for (index, rule) in household.rules.enumerated() {
            let record = scratch.inserted(RuleRecord(id: ""))
            try record.apply(rule, sortIndex: index)
            #expect(try record.domain() == rule)
        }
    }

    @Test("tag and weekday sets are stored as sorted raw values")
    func setsAreSorted() throws {
        let scratch = try Scratch()
        let household = richHousehold()
        let member = scratch.inserted(MemberRecord(id: ""))
        try member.apply(household.members[0], sortIndex: 0)
        #expect(member.schoolDays == ["friday", "monday", "wednesday"])
        let rule = scratch.inserted(RuleRecord(id: ""))
        try rule.apply(household.rules[0], sortIndex: 0)
        #expect(rule.excludedTags == ["garlic", "mushroom", "onion", "rootVegetable"])
        #expect(rule.scopeKind == "household")
        #expect(rule.scopeMemberId == nil)
    }

    @Test("household scalar columns round-trip")
    func household() throws {
        let scratch = try Scratch()
        let household = richHousehold()
        let record = scratch.inserted(HouseholdRecord(id: ""))
        try record.apply(household)
        #expect(try record.domain(members: household.members, rules: household.rules) == household)
    }

    @Test("meal plans round-trip with and without approval; status and approval are columns")
    func mealPlan() throws {
        let scratch = try Scratch()
        let approved = richApprovedPlan()
        let record = scratch.inserted(MealPlanRecord(id: ""))
        try record.apply(approved)
        #expect(record.status == "approved")
        #expect(record.seriesId == "s1")
        #expect(record.approvalApprover == "thisDevice")
        #expect(record.approvalContentHash == approved.approval?.contentHash)
        #expect(try record.domain() == approved)

        let draft = fixturePlan("p9", series: "s9", revision: 1, meals: richMeals())
        try record.apply(draft)
        #expect(record.approvalApprover == nil)
        #expect(record.approvalApprovedAt == nil)
        #expect(record.approvalContentHash == nil)
        #expect(try record.domain() == draft)
    }

    @Test("a plan record with a half-written approval is refused, not treated as approved or draft")
    func incompleteApprovalIsRefused() throws {
        let scratch = try Scratch()
        let record = scratch.inserted(MealPlanRecord(id: ""))
        try record.apply(richApprovedPlan())
        record.approvalContentHash = nil
        #expect(throws: PersistenceError.incompleteApproval(planId: "p1")) { try record.domain() }
    }

    @Test("pantry items round-trip for an ingredient and for free text")
    func pantryItem() throws {
        let scratch = try Scratch()
        let items = [
            fixturePantryItem("a", quantity: 2),
            PantryItem(
                id: "b", item: .freeText("that green chutney"), quantity: 0.5, unit: .cup, location: .freezer,
                purchasedAt: fixtureNow, expiresOn: fixtureMonday, lastConfirmedAt: fixtureNow, source: .notesImport),
        ]
        for item in items {
            let record = scratch.inserted(PantryItemRecord(id: ""))
            try record.apply(item)
            #expect(try record.domain() == item)
        }
    }

    @Test("a pantry record with both or neither of ingredient and free text is refused")
    func pantryItemNeedsExactlyOneRef() throws {
        let scratch = try Scratch()
        let record = scratch.inserted(PantryItemRecord(id: ""))
        try record.apply(fixturePantryItem("a", quantity: 1))
        record.freeText = "rice"
        #expect(throws: PersistenceError.self) { try record.domain() }
        record.ingredientId = nil
        record.freeText = nil
        #expect(throws: PersistenceError.self) { try record.domain() }
    }

    @Test("shopping items round-trip with every optional set and unset")
    func shoppingItem() throws {
        let scratch = try Scratch()
        let items = [
            ShoppingItem(id: "s1", key: "manual:soap", name: "Soap", aisle: .other, origin: .manual),
            ShoppingItem(
                id: "s2", key: "plan:rice:mass:checkYouHave", ingredientId: "rice", name: "Rice", quantity: 1.5,
                unit: .kilogram, aisle: .grainsAndFlours, checkedOff: true, origin: .plan, group: .checkYouHave),
        ]
        for item in items {
            let record = scratch.inserted(ShoppingItemRecord(id: ""))
            try record.apply(item)
            #expect(try record.domain() == item)
        }
    }

    @Test("cook logs round-trip with deductions")
    func cookLog() throws {
        let scratch = try Scratch()
        let log = CookLog(
            id: "c", planId: "p", mealId: "m", recipeId: "r", cookedAt: fixtureNow.addingTimeInterval(0.001),
            deductions: [
                PantryDeduction(pantryItemId: "a", quantity: 0.2, unit: .kilogram),
                PantryDeduction(pantryItemId: "b", quantity: 15, unit: .tablespoon),
            ])
        let record = scratch.inserted(CookLogRecord(id: ""))
        try record.apply(log)
        #expect(try record.domain() == log)
    }

    @Test("facts round-trip for every statement, subject, origin and status")
    func facts() throws {
        let scratch = try Scratch()
        for fact in allFacts() {
            let record = scratch.inserted(FactRecord(id: ""))
            try record.apply(fact)
            #expect(try record.domain() == fact)
        }
    }

    @Test("learning events round-trip for every kind")
    func learningEvents() throws {
        let scratch = try Scratch()
        for event in allLearningEvents() {
            let record = scratch.inserted(LearningEventRecord(id: ""))
            try record.apply(event)
            #expect(try record.domain() == event)
        }
    }

    @Test("prompt states round-trip")
    func promptState() throws {
        let scratch = try Scratch()
        let state = PromptState(promptId: "lunchbox", lastShownAt: fixtureNow, dismissedAt: fixtureNow, answeredAt: nil)
        let record = scratch.inserted(PromptStateRecord(promptId: ""))
        try record.apply(state)
        #expect(try record.domain() == state)
    }

    @Test("an unknown stored enum value is refused with the field name")
    func unknownEnumValueIsRefused() throws {
        let scratch = try Scratch()
        let member = scratch.inserted(MemberRecord(id: ""))
        try member.apply(richHousehold().members[0], sortIndex: 0)
        member.safetyStatus = "skipped"
        #expect(throws: PersistenceError.invalidValue(entity: "Member", field: "safetyStatus", value: "skipped")) {
            try member.domain()
        }

        let rule = scratch.inserted(RuleRecord(id: ""))
        try rule.apply(richHousehold().rules[0], sortIndex: 0)
        rule.excludedTags = ["peanut", "nuts"]
        #expect(throws: PersistenceError.invalidValue(entity: "Rule", field: "excludedTags", value: "nuts")) {
            try rule.domain()
        }
    }

    @Test("an empty id is never written")
    func emptyIdIsRefused() throws {
        let scratch = try Scratch()
        let record = scratch.inserted(PantryItemRecord(id: ""))
        #expect(throws: PersistenceError.emptyIdentifier(entity: "PantryItem")) {
            try record.apply(fixturePantryItem("", quantity: 1))
        }
        let fact = scratch.inserted(FactRecord(id: ""))
        let memberFact = Fact(
            id: "f", subject: .member(""), statement: .prefersQuickWeekday, origin: .stated, confidence: 1,
            status: .active, createdAt: fixtureNow, updatedAt: fixtureNow)
        #expect(throws: PersistenceError.emptyIdentifier(entity: "Fact")) { try fact.apply(memberFact) }
    }

    @Test("record defaults fail closed: a new member is unasked and a new rule covers the household")
    func defaultsFailClosed() throws {
        let scratch = try Scratch()
        #expect(scratch.inserted(MemberRecord(id: "x")).safetyStatus == SafetyStatus.unasked.rawValue)
        #expect(scratch.inserted(RuleRecord(id: "x")).scopeKind == "household")
    }
}

/// A throwaway in-memory context that keeps its container alive (one per test; not Sendable).
private final class Scratch {
    let store: PersistenceStore
    let context: ModelContext

    init() throws {
        store = try PersistenceStore(location: .inMemory)
        context = ModelContext(store.container)
    }

    func inserted<Record: PersistentModel>(_ record: Record) -> Record {
        context.insert(record)
        return record
    }
}
