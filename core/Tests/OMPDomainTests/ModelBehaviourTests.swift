import Foundation
import OMPDomain
import Testing

@Suite("Onboarding household (AC-1.2, AC-1.3)")
struct HouseholdOnboardingTests {
    @Test("A adults and C children become A+C labelled members, all unasked, no rules")
    func createsLabelledUnaskedMembers() throws {
        var counter = 0
        let household = try Household.onboarding(id: "h", adults: 2, children: 3, now: Sample.now) {
            counter += 1
            return MemberID("m\(counter)")
        }
        #expect(household.members.count == 5)
        #expect(
            household.members.map(\.label) == [
                MemberLabel(role: .adult, number: 1), MemberLabel(role: .adult, number: 2),
                MemberLabel(role: .child, number: 1), MemberLabel(role: .child, number: 2),
                MemberLabel(role: .child, number: 3),
            ])
        #expect(household.members.map(\.id) == ["m1", "m2", "m3", "m4", "m5"])
        #expect(household.members.allSatisfy { $0.safetyStatus == .unasked && $0.safetyConfirmedAt == nil })
        #expect(household.members.allSatisfy { $0.name == nil && !$0.isDeleted && !$0.needsSchoolLunch })
        #expect(household.members.map(\.ageBand) == [.adult, .adult, .child, .child, .child])
        #expect(household.rules.isEmpty)
        #expect(household.settings == HouseholdSettings(snacksEnabled: false, weekStartsOn: .monday))
        #expect(household.createdAt == Sample.now && household.updatedAt == Sample.now)
    }

    @Test("the default 2 adults, 0 children gives Adult 1 and Adult 2")
    func defaultCounts() throws {
        let household = try Household.onboarding(id: "h", adults: 2, children: 0, now: Sample.now)
        #expect(household.members.map(\.label.role) == [.adult, .adult])
        #expect(Set(household.members.map(\.id)).count == 2)
    }

    @Test("one child alone is a valid household")
    func singleChild() throws {
        let household = try Household.onboarding(id: "h", adults: 0, children: 1, now: Sample.now)
        #expect(household.members.map(\.label) == [MemberLabel(role: .child, number: 1)])
    }

    @Test("rejects fewer than 1 member, more than 12, and negative counts")
    func rejectsOutOfRange() throws {
        #expect(throws: HouseholdSizeError.tooFew(total: 0)) {
            try Household.onboarding(id: "h", adults: 0, children: 0, now: Sample.now)
        }
        #expect(throws: HouseholdSizeError.tooMany(total: 13)) {
            try Household.onboarding(id: "h", adults: 7, children: 6, now: Sample.now)
        }
        #expect(throws: HouseholdSizeError.negativeCount) {
            try Household.onboarding(id: "h", adults: 3, children: -1, now: Sample.now)
        }
        let twelve = try Household.onboarding(id: "h", adults: 6, children: 6, now: Sample.now)
        #expect(twelve.members.count == 12)
    }

    @Test("a member added later gets the next unused label and starts unasked (AC-3.2)")
    func nextLabel() {
        let household = Sample.household  // Adult 1, Child 1, deleted Child 2
        #expect(household.nextLabel(for: .adult) == MemberLabel(role: .adult, number: 2))
        #expect(household.nextLabel(for: .child) == MemberLabel(role: .child, number: 3))
        let added = Member(id: "new", label: household.nextLabel(for: .child))
        #expect(added.safetyStatus == .unasked)
    }
}

@Suite("Portion defaults (AC-6.2)")
struct PortionDefaultTests {
    @Test(
        "default portion by age band",
        arguments: zip(
            [AgeBand.adult, AgeBand.teen, AgeBand.senior, AgeBand.child, AgeBand.toddler, AgeBand.infant],
            [1.0, 1.0, 1.0, 0.6, 0.4, 0.4]
        ))
    func byAgeBand(band: AgeBand, expected: Double) {
        #expect(band.defaultPortion == expected)
        let member = Member(id: "m", label: MemberLabel(role: .adult, number: 1), ageBand: band)
        #expect(member.defaultPortion == expected)
        #expect(MealServing(defaultFor: member) == MealServing(memberId: "m", portion: expected, notEating: false))
    }

    @Test("an unknown age band gets a full portion")
    func unknownBand() {
        let member = Member(id: "m", label: MemberLabel(role: .child, number: 1))
        #expect(member.defaultPortion == 1.0)
    }

    @Test("a per-member override wins over the age band")
    func overrideWins() {
        let member = Member(id: "m", label: MemberLabel(role: .child, number: 1), ageBand: .child, portionOverride: 0.8)
        #expect(member.defaultPortion == 0.8)
        #expect(MealServing(defaultFor: member).portion == 0.8)
    }
}

@Suite("Model helpers")
struct ModelHelperTests {
    @Test("rule scopes: household covers everyone, member scope covers only that member")
    func ruleScopes() {
        #expect(RuleScope.household.covers(Sample.adultID))
        #expect(RuleScope.member(Sample.childID).covers(Sample.childID))
        #expect(!RuleScope.member(Sample.childID).covers(Sample.adultID))
        #expect(Sample.household.rules(covering: Sample.childID).map(\.id) == ["rule-1", "rule-2"])
        #expect(Sample.household.rules(covering: Sample.adultID).map(\.id) == ["rule-2"])
    }

    @Test("a rule snapshots its restriction's tags and defaults to hard/user")
    func ruleSnapshot() {
        #expect(Sample.householdRule.excludedTags == [.rootVegetable, .onion, .garlic, .mushroom])
        #expect(Sample.householdRule.restriction == "jain")
        #expect(Sample.householdRule.kind == .hard)
        #expect(Sample.householdRule.source == .user)
    }

    @Test("active members exclude soft-deleted ones; lookup still finds them")
    func activeMembers() {
        #expect(Sample.household.activeMembers.map(\.id) == [Sample.adultID, Sample.childID])
        #expect(Sample.household.member("member-child-2")?.isDeleted == true)
        #expect(Sample.household.member("nobody") == nil)
    }

    @Test("a plan covers 7 days from its start date, across a month end")
    func planDates() throws {
        let start = try #require(LocalDate(year: 2026, month: 10, day: 28))
        let plan = MealPlan(id: "p", seriesId: "s", weekStart: start, meals: [], contentVersion: "v", createdAt: Sample.now)
        #expect(plan.dates.map(\.isoString) == [
            "2026-10-28", "2026-10-29", "2026-10-30", "2026-10-31", "2026-11-01", "2026-11-02", "2026-11-03",
        ])
        #expect(plan.endDate.isoString == "2026-11-03")
        #expect(plan.status == .draft && plan.revision == 1 && plan.approval == nil)
    }

    @Test("planned meal eaters skip members who are not eating; empty meals have no recipe")
    func mealHelpers() {
        #expect(Sample.filledMeal.eaterIDs == [Sample.adultID])
        #expect(!Sample.filledMeal.isEmpty)
        #expect(Sample.emptyMeal.isEmpty)
        #expect(Sample.approvedPlan.meal("meal-2") == Sample.emptyMeal)
    }

    @Test("lunchbox has no recipe meal type; the others map one to one")
    func slotMealTypes() {
        #expect(MealSlot.lunchbox.mealType == nil)
        #expect(MealSlot.breakfast.mealType == .breakfast)
        #expect(MealSlot.snack.mealType == .snack)
    }

    @Test("unit dimensions")
    func unitDimensions() {
        #expect(MeasureUnit.kilogram.dimension == .mass)
        #expect(MeasureUnit.cup.dimension == .volume)
        #expect(MeasureUnit.dozen.dimension == .count)
        #expect(MeasureUnit.toTaste.dimension == .unquantified)
    }

    @Test("pantry ref exposes the ingredient only when resolved")
    func pantryRef() {
        #expect(Sample.pantryResolved.item.ingredientId == "ghee")
        #expect(Sample.pantryFreeText.item.ingredientId == nil)
    }

    @Test("validation report: passed flag and failing meals listed once in order")
    func reportHelpers() {
        #expect(!Sample.report.passedForEveryone)
        #expect(Sample.report.violatingMealIDs == ["meal-1", "meal-2"])
        let clean = ValidationReport(planId: "p", contentHash: "h", violations: [])
        #expect(clean.passedForEveryone && clean.violatingMealIDs.isEmpty)
    }

    @Test("gate refusal exposes its members")
    func refusalMembers() {
        #expect(GateRefusal.safetyUnanswered([Sample.childID]).memberIDs == [Sample.childID])
        #expect(GateRefusal.reconfirmationDue([Sample.adultID, Sample.childID]).memberIDs.count == 2)
    }

    @Test("fact key combines subject and statement")
    func factKey() {
        let fact = Sample.facts[1]
        #expect(fact.key == FactKey(subject: .member(Sample.childID), statement: .dislikesIngredient("okra")))
        #expect(fact.key != Sample.facts[0].key)
    }
}
