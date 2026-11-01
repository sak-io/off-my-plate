import Foundation
import OMPDomain
import Testing

/// Fixtures for the safety gate tests. All instants are in UTC so day counting is exact.
enum GateFixture {
    static let utc = TimeZone(identifier: "UTC")!
    /// 2026-10-12T00:00:00Z.
    static let confirmed = Date(timeIntervalSince1970: 1_791_763_200)
    static let day: TimeInterval = 86_400

    static let peanuts = Restriction(id: "peanuts", labelKey: "restriction.peanuts", excludedTags: [.peanut])
    static let jain = Restriction(
        id: "jain", labelKey: "restriction.jain", excludedTags: [.rootVegetable, .onion, .garlic, .mushroom])

    static func member(
        _ id: MemberID, _ role: MemberRole = .adult, number: Int = 1, status: SafetyStatus = .confirmedNone,
        confirmedAt: Date? = confirmed, ageBand: AgeBand? = .adult, deletedAt: Date? = nil
    ) -> Member {
        Member(
            id: id, label: MemberLabel(role: role, number: number), ageBand: ageBand, safetyStatus: status,
            safetyConfirmedAt: confirmedAt, deletedAt: deletedAt)
    }

    static func household(_ members: [Member], rules: [Rule] = []) -> Household {
        Household(id: "h1", members: members, rules: rules, createdAt: confirmed, updatedAt: confirmed)
    }

    /// Three unasked members as onboarding creates them.
    static func onboarded() throws -> Household {
        var counter = 0
        return try Household.onboarding(id: "h1", adults: 2, children: 1, now: confirmed) {
            counter += 1
            return MemberID("m\(counter)")
        }
    }

    static func refusal(_ result: Result<SafetyClearance, GateRefusal>) -> GateRefusal? {
        if case .failure(let refusal) = result { return refusal }
        return nil
    }

    static func clearance(_ result: Result<SafetyClearance, GateRefusal>) -> SafetyClearance? {
        if case .success(let clearance) = result { return clearance }
        return nil
    }
}

@Suite("SafetyGate.evaluate (AC-3.1, AC-3.2, G3, ADR 0007)")
struct SafetyGateEvaluateTests {
    typealias F = GateFixture

    @Test("a freshly onboarded household is refused, listing every member")
    func onboardedHouseholdIsRefused() throws {
        let result = SafetyGate.evaluate(try F.onboarded(), now: F.confirmed, timeZone: F.utc)
        #expect(F.refusal(result) == .safetyUnanswered(["m1", "m2", "m3"]))
    }

    @Test("the refusal lists only the unasked members, in stored order")
    func refusalListsOnlyUnaskedMembers() {
        let household = F.household([
            F.member("a"), F.member("b", status: .unasked, confirmedAt: nil), F.member("c", status: .stated),
            F.member("d", status: .unasked, confirmedAt: nil),
        ])
        let result = SafetyGate.evaluate(household, now: F.confirmed, timeZone: F.utc)
        #expect(F.refusal(result) == .safetyUnanswered(["b", "d"]))
        #expect(F.refusal(result)?.memberIDs == ["b", "d"])
    }

    @Test("a deleted unasked member does not block")
    func deletedMemberDoesNotBlock() throws {
        let household = F.household([
            F.member("a"), F.member("gone", status: .unasked, confirmedAt: nil, deletedAt: F.confirmed),
        ])
        let clearance = try #require(F.clearance(SafetyGate.evaluate(household, now: F.confirmed, timeZone: F.utc)))
        #expect(clearance.members.map(\.id) == ["a"])
    }

    @Test("a deleted member with an overdue answer does not block")
    func deletedOverdueMemberDoesNotBlock() {
        let household = F.household([
            F.member("a"),
            F.member("gone", confirmedAt: F.confirmed.addingTimeInterval(-400 * F.day), deletedAt: F.confirmed),
        ])
        #expect(F.clearance(SafetyGate.evaluate(household, now: F.confirmed, timeZone: F.utc)) != nil)
    }

    @Test(
        "TR-3: a confirmed status without safetyConfirmedAt fails closed as unanswered",
        arguments: [SafetyStatus.confirmedNone, .stated])
    func confirmedWithoutTimestampFailsClosed(status: SafetyStatus) {
        let household = F.household([F.member("a"), F.member("b", status: status, confirmedAt: nil)])
        let result = SafetyGate.evaluate(household, now: F.confirmed, timeZone: F.utc)
        #expect(F.refusal(result) == .safetyUnanswered(["b"]))
        #expect(SafetyGate.approvalRefusal(for: household) == .safetyUnanswered(["b"]))
    }

    @Test("180-day boundary: day 180 is cleared, day 181 is due")
    func reconfirmationBoundary() {
        let household = F.household([F.member("a"), F.member("b", status: .stated)])
        let day180 = F.confirmed.addingTimeInterval(180 * F.day)
        let day181 = F.confirmed.addingTimeInterval(181 * F.day)
        // Late on day 180 is still day 180: whole calendar days count, not hours.
        let lateDay180 = day181.addingTimeInterval(-1)

        #expect(F.clearance(SafetyGate.evaluate(household, now: day180, timeZone: F.utc)) != nil)
        #expect(F.clearance(SafetyGate.evaluate(household, now: lateDay180, timeZone: F.utc)) != nil)
        #expect(F.refusal(SafetyGate.evaluate(household, now: day181, timeZone: F.utc)) == .reconfirmationDue(["a", "b"]))
    }

    @Test("the 180-day count uses calendar days in the given time zone")
    func reconfirmationUsesTimeZone() {
        let kolkata = TimeZone(identifier: "Asia/Kolkata")!  // UTC+05:30, no DST
        // Confirmed 2026-10-11T20:00Z, which is already 2026-10-12 in Kolkata.
        let confirmedAt = F.confirmed.addingTimeInterval(-4 * 3_600)
        let household = F.household([F.member("a", confirmedAt: confirmedAt)])
        // Exactly 181 days later is still 01:30 in Kolkata, on Kolkata day 181.
        let now = confirmedAt.addingTimeInterval(181 * F.day)
        #expect(F.refusal(SafetyGate.evaluate(household, now: now, timeZone: kolkata)) == .reconfirmationDue(["a"]))
        // One day earlier is day 180 in Kolkata: still valid.
        #expect(F.clearance(SafetyGate.evaluate(household, now: now - F.day, timeZone: kolkata)) != nil)
    }

    @Test("unanswered takes precedence over an overdue answer")
    func unansweredTakesPrecedence() {
        let household = F.household([
            F.member("old", confirmedAt: F.confirmed.addingTimeInterval(-300 * F.day)),
            F.member("new", status: .unasked, confirmedAt: nil),
        ])
        #expect(F.refusal(SafetyGate.evaluate(household, now: F.confirmed, timeZone: F.utc)) == .safetyUnanswered(["new"]))
    }

    @Test("evaluate(clock:) uses the clock's instant and time zone")
    func evaluateWithClock() {
        let household = F.household([F.member("a")])
        let clock = FixedClock(now: F.confirmed.addingTimeInterval(181 * F.day), timeZone: F.utc)
        #expect(F.refusal(SafetyGate.evaluate(household, clock: clock)) == .reconfirmationDue(["a"]))
    }

    @Test("m3: the 180-day count is in local calendar days across a DST change (Europe/London)")
    func reconfirmationAcrossDST() {
        let london = TimeZone(identifier: "Europe/London")!
        // 2026-07-01 00:30 BST (UTC+1) = 2026-06-30T23:30Z.
        let confirmedAt = Date(timeIntervalSince1970: 1_782_862_200)
        let household = F.household([F.member("a", confirmedAt: confirmedAt)])
        // 2026-12-28T23:50Z = 2026-12-28 23:50 GMT: local day 180, although more than 181 x 24 h
        // have elapsed. Still cleared.
        let lateDay180 = Date(timeIntervalSince1970: 1_798_501_800)
        #expect(F.clearance(SafetyGate.evaluate(household, now: lateDay180, timeZone: london)) != nil)
        // 2026-12-29T00:10Z = 2026-12-29 00:10 GMT: local day 181. Due.
        let earlyDay181 = Date(timeIntervalSince1970: 1_798_503_000)
        #expect(F.refusal(SafetyGate.evaluate(household, now: earlyDay181, timeZone: london)) == .reconfirmationDue(["a"]))
    }

    @Test("m4: a confirmation dated more than one day in the future counts as due")
    func futureConfirmationIsDue() {
        let tomorrow = F.household([F.member("a", confirmedAt: F.confirmed.addingTimeInterval(F.day))])
        #expect(F.clearance(SafetyGate.evaluate(tomorrow, now: F.confirmed, timeZone: F.utc)) != nil)
        let inTwoDays = F.household([F.member("a", confirmedAt: F.confirmed.addingTimeInterval(2 * F.day))])
        #expect(F.refusal(SafetyGate.evaluate(inTwoDays, now: F.confirmed, timeZone: F.utc)) == .reconfirmationDue(["a"]))
        let farFuture = F.household([F.member("a", confirmedAt: F.confirmed.addingTimeInterval(365 * F.day))])
        #expect(F.refusal(SafetyGate.evaluate(farFuture, now: F.confirmed, timeZone: F.utc)) == .reconfirmationDue(["a"]))
    }

    @Test("U4: approval is blocked by an unasked member but not by an overdue answer")
    func approvalRefusal() {
        let overdue = F.household([F.member("a", confirmedAt: F.confirmed.addingTimeInterval(-400 * F.day))])
        #expect(SafetyGate.approvalRefusal(for: overdue) == nil)
        let unasked = F.household([F.member("a"), F.member("b", status: .unasked, confirmedAt: nil)])
        #expect(SafetyGate.approvalRefusal(for: unasked) == .safetyUnanswered(["b"]))
    }
}

@Suite("SafetyClearance snapshot (ADR 0007)")
struct SafetyClearanceTests {
    typealias F = GateFixture

    @Test("the clearance snapshot does not change when the household is edited afterwards")
    func snapshotIsImmutable() throws {
        let rule = Rule(id: "r1", scope: .member("a"), restriction: F.peanuts, createdAt: F.confirmed)
        var household = F.household([F.member("a", status: .stated), F.member("b")], rules: [rule])
        let clearance = try #require(F.clearance(SafetyGate.evaluate(household, now: F.confirmed, timeZone: F.utc)))
        let before = clearance

        household.addMember(role: .child, ageBand: .child, at: F.confirmed, id: "c")
        try household.addRule(
            Rule(id: "r2", scope: .household, restriction: F.jain, createdAt: F.confirmed), at: F.confirmed)
        household.settings.snacksEnabled = true

        #expect(clearance == before)
        #expect(clearance.members.map(\.id) == ["a", "b"])
        #expect(clearance.rules == [rule])
        #expect(clearance.settings.snacksEnabled == false)
        #expect(clearance.householdID == "h1")
        #expect(clearance.issuedAt == F.confirmed)
        #expect(!clearance.matches(household))
    }

    @Test("matches the household it was issued for; not another household")
    func matchesOnlyItsHousehold() throws {
        let household = F.household([F.member("a")])
        let clearance = try #require(F.clearance(SafetyGate.evaluate(household, now: F.confirmed, timeZone: F.utc)))
        #expect(clearance.matches(household))
        let other = Household(id: "h2", members: household.members, createdAt: F.confirmed, updatedAt: F.confirmed)
        #expect(!clearance.matches(other))
    }

    @Test("M2: a clearance is not valid once re-confirmation is due, even for an unchanged household")
    func clearanceExpires() throws {
        let household = F.household([F.member("a")])
        let clearance = try #require(F.clearance(SafetyGate.evaluate(household, now: F.confirmed, timeZone: F.utc)))
        #expect(clearance.isValid(for: household, now: F.confirmed, timeZone: F.utc))
        #expect(clearance.isValid(for: household, now: F.confirmed.addingTimeInterval(180 * F.day), timeZone: F.utc))
        #expect(clearance.matches(household))
        #expect(!clearance.isValid(for: household, now: F.confirmed.addingTimeInterval(181 * F.day), timeZone: F.utc))
    }

    @Test("M2: a clearance is not valid for an edited household")
    func clearanceInvalidAfterEdit() throws {
        var household = F.household([F.member("a")])
        let clearance = try #require(F.clearance(SafetyGate.evaluate(household, now: F.confirmed, timeZone: F.utc)))
        household.settings.snacksEnabled = true
        #expect(!clearance.isValid(for: household, now: F.confirmed, timeZone: F.utc))
    }

    @Test("n3: rules scoped to deleted members are left out of the clearance")
    func clearanceDropsDeletedMembersRules() throws {
        let kept = Rule(id: "r1", scope: .household, restriction: F.peanuts, createdAt: F.confirmed)
        let dropped = Rule(id: "r2", scope: .member("gone"), restriction: F.jain, createdAt: F.confirmed)
        let household = F.household(
            [F.member("a", status: .stated), F.member("gone", status: .stated, deletedAt: F.confirmed)],
            rules: [kept, dropped])
        let clearance = try #require(F.clearance(SafetyGate.evaluate(household, now: F.confirmed, timeZone: F.utc)))
        #expect(clearance.rules == [kept])
        #expect(clearance.matches(household))
    }

    @Test("rules(covering:) returns the member's rules plus household-scope rules")
    func rulesCovering() throws {
        let own = Rule(id: "r1", scope: .member("a"), restriction: F.peanuts, createdAt: F.confirmed)
        let shared = Rule(id: "r2", scope: .household, restriction: F.jain, createdAt: F.confirmed)
        let household = F.household([F.member("a", status: .stated), F.member("b", status: .stated)], rules: [own, shared])
        let clearance = try #require(F.clearance(SafetyGate.evaluate(household, now: F.confirmed, timeZone: F.utc)))
        #expect(clearance.rules(covering: "a") == [own, shared])
        #expect(clearance.rules(covering: "b") == [shared])
    }
}

/// (from, to, resets to unasked) for AC-3.4.
let ageBandCrossings: [(AgeBand?, AgeBand?, Bool)] = [
    (.child, .teen, true),
    (.teen, .child, true),
    (.toddler, .adult, true),
    (.child, nil, true),
    (nil, .adult, true),
    (.infant, .child, false),
    (.teen, .adult, false),
    (.adult, .senior, false),
    (.child, .child, false),
]

@Suite("Safety status transitions (plan 4.1; AC-2.2, AC-2.3, AC-3.2, AC-3.4, G3)")
struct SafetyTransitionTests {
    typealias F = GateFixture
    let later = GateFixture.confirmed.addingTimeInterval(GateFixture.day)

    @Test("AC-2.2: \"No, nobody\" makes every current member confirmedNone with confirmedAt, then clears")
    func noNobody() throws {
        var household = try F.onboarded()
        household.members[2].deletedAt = F.confirmed
        try household.confirmNobodyAvoidsAnything(at: later)
        #expect(household.members[0...1].allSatisfy { $0.safetyStatus == .confirmedNone && $0.safetyConfirmedAt == later })
        #expect(household.members[2].safetyStatus == .unasked)
        #expect(household.updatedAt == later)
        #expect(F.clearance(SafetyGate.evaluate(household, now: later, timeZone: F.utc)) != nil)
    }

    @Test("\"No, nobody\" is refused while hard rules exist, and changes nothing")
    func noNobodyWithRules() throws {
        var household = F.household(
            [F.member("a", status: .stated)],
            rules: [Rule(id: "r1", scope: .member("a"), restriction: F.peanuts, createdAt: F.confirmed)])
        let before = household
        #expect(throws: SafetyTransitionError.householdHasRules) { try household.confirmNobodyAvoidsAnything(at: later) }
        #expect(household == before)
    }

    @Test("m1: rules scoped to a deleted member do not block \"No, nobody\"")
    func noNobodyIgnoresDeletedMembersRules() throws {
        var household = F.household(
            [F.member("a", status: .unasked, confirmedAt: nil), F.member("gone", status: .stated, deletedAt: F.confirmed)],
            rules: [Rule(id: "r1", scope: .member("gone"), restriction: F.peanuts, createdAt: F.confirmed)])
        try household.confirmNobodyAvoidsAnything(at: later)
        #expect(household.members[0].safetyStatus == .confirmedNone)
        #expect(F.clearance(SafetyGate.evaluate(household, now: later, timeZone: F.utc)) != nil)
    }

    @Test("\"No, nobody\" is refused while a household-scope rule exists")
    func noNobodyWithHouseholdRule() {
        var household = F.household(
            [F.member("a", status: .stated)],
            rules: [Rule(id: "r1", scope: .household, restriction: F.peanuts, createdAt: F.confirmed)])
        #expect(throws: SafetyTransitionError.householdHasRules) { try household.confirmNobodyAvoidsAnything(at: later) }
    }

    @Test("m2: a rule with no excluded tags is refused")
    func emptyRuleRefused() {
        var household = F.household([F.member("a")])
        let empty = Rule(id: "r1", scope: .member("a"), restriction: "none", excludedTags: [], createdAt: later)
        let before = household
        #expect(throws: SafetyTransitionError.emptyRule("r1")) { try household.addRule(empty, at: later) }
        #expect(throws: SafetyTransitionError.emptyRule("r1")) { try household.confirmSafetyAnswers(rules: [empty], at: later) }
        #expect(household == before)
    }

    @Test("M1: a member added after a household rule answers with confirmMemberAnswer and becomes stated")
    func addedMemberCoveredByHouseholdRule() throws {
        let rule = Rule(id: "r1", scope: .household, restriction: F.peanuts, createdAt: F.confirmed)
        var household = F.household([F.member("a", status: .stated)], rules: [rule])
        household.addMember(role: .child, ageBand: .child, at: later, id: "new")
        #expect(F.refusal(SafetyGate.evaluate(household, now: later, timeZone: F.utc)) == .safetyUnanswered(["new"]))
        try household.confirmMemberAnswer(for: "new", at: later)
        #expect(household.member("new")?.safetyStatus == .stated)
        #expect(household.member("new")?.safetyConfirmedAt == later)
        #expect(household.rules == [rule])
        #expect(F.clearance(SafetyGate.evaluate(household, now: later, timeZone: F.utc)) != nil)
    }

    @Test("M1: an uncovered member answers with confirmMemberAnswer and becomes confirmedNone")
    func uncoveredMemberAnswer() throws {
        var household = F.household([F.member("a")])
        household.addMember(role: .adult, ageBand: .adult, at: later, id: "new")
        try household.confirmMemberAnswer(for: "new", at: later)
        #expect(household.member("new")?.safetyStatus == .confirmedNone)
        #expect(F.clearance(SafetyGate.evaluate(household, now: later, timeZone: F.utc)) != nil)
        #expect(throws: SafetyTransitionError.unknownMember("x")) { try household.confirmMemberAnswer(for: "x", at: later) }
    }

    @Test("AC-2.3 + U1: confirmed rules make covered members stated and everyone else confirmedNone")
    func confirmRulesPerMember() throws {
        var household = try F.onboarded()
        let rule = Rule(id: "r1", scope: .member("m3"), restriction: F.peanuts, createdAt: later)
        try household.confirmSafetyAnswers(rules: [rule], at: later)
        #expect(household.rules == [rule])
        #expect(household.members.map(\.safetyStatus) == [.confirmedNone, .confirmedNone, .stated])
        #expect(household.members.allSatisfy { $0.safetyConfirmedAt == later })
        #expect(F.clearance(SafetyGate.evaluate(household, now: later, timeZone: F.utc)) != nil)
    }

    @Test("G3: a \"Not sure who\" (household-scope) rule makes every member stated")
    func notSureWhoIsHouseholdScope() throws {
        var household = try F.onboarded()
        let rule = Rule(id: "r1", scope: .household, restriction: F.peanuts, createdAt: later)
        try household.confirmSafetyAnswers(rules: [rule], at: later)
        #expect(household.members.allSatisfy { $0.safetyStatus == .stated })
        let clearance = try #require(F.clearance(SafetyGate.evaluate(household, now: later, timeZone: F.utc)))
        let ids: [MemberID] = ["m1", "m2", "m3"]
        #expect(ids.allSatisfy { clearance.rules(covering: $0) == [rule] })
    }

    @Test("confirmSafetyAnswers refuses empty, duplicate and inactive-member rules without changes")
    func confirmRulesValidation() throws {
        var household = try F.onboarded()
        household.members[2].deletedAt = F.confirmed
        let before = household
        let rule = Rule(id: "r1", scope: .member("m1"), restriction: F.peanuts, createdAt: later)
        #expect(throws: SafetyTransitionError.noRules) { try household.confirmSafetyAnswers(rules: [], at: later) }
        #expect(throws: SafetyTransitionError.duplicateRule("r1")) {
            try household.confirmSafetyAnswers(rules: [rule, rule], at: later)
        }
        #expect(throws: SafetyTransitionError.ruleForInactiveMember("m3")) {
            try household.confirmSafetyAnswers(
                rules: [Rule(id: "r2", scope: .member("m3"), restriction: F.peanuts, createdAt: later)], at: later)
        }
        #expect(throws: SafetyTransitionError.ruleForInactiveMember("nobody")) {
            try household.confirmSafetyAnswers(
                rules: [Rule(id: "r3", scope: .member("nobody"), restriction: F.peanuts, createdAt: later)], at: later)
        }
        #expect(household == before)
    }

    @Test("per-member none: unasked -> confirmedNone; refused while rules cover the member")
    func perMemberNone() throws {
        var household = F.household(
            [F.member("a", status: .unasked, confirmedAt: nil), F.member("b", status: .stated)],
            rules: [Rule(id: "r1", scope: .member("b"), restriction: F.peanuts, createdAt: F.confirmed)])
        try household.confirmNothingToAvoid(for: "a", at: later)
        #expect(household.members[0].safetyStatus == .confirmedNone && household.members[0].safetyConfirmedAt == later)
        #expect(throws: SafetyTransitionError.memberHasRules("b")) { try household.confirmNothingToAvoid(for: "b", at: later) }
        #expect(throws: SafetyTransitionError.unknownMember("x")) { try household.confirmNothingToAvoid(for: "x", at: later) }
    }

    @Test("confirmedNone -> stated when a rule is added for the member")
    func addRuleForMember() throws {
        var household = F.household([F.member("a"), F.member("b")])
        try household.addRule(Rule(id: "r1", scope: .member("a"), restriction: F.peanuts, createdAt: later), at: later)
        #expect(household.members[0].safetyStatus == .stated && household.members[0].safetyConfirmedAt == later)
        #expect(household.members[1].safetyStatus == .confirmedNone && household.members[1].safetyConfirmedAt == F.confirmed)
    }

    @Test("a household-scope rule added later leaves unasked members unasked (fails closed)")
    func addHouseholdRuleKeepsUnasked() throws {
        var household = F.household([F.member("a"), F.member("new", status: .unasked, confirmedAt: nil)])
        try household.addRule(Rule(id: "r1", scope: .household, restriction: F.jain, createdAt: later), at: later)
        #expect(household.members.map(\.safetyStatus) == [.stated, .unasked])
        #expect(F.refusal(SafetyGate.evaluate(household, now: later, timeZone: F.utc)) == .safetyUnanswered(["new"]))
    }

    @Test("stated -> confirmedNone only when the member's last rule is removed")
    func removeRule() throws {
        let r1 = Rule(id: "r1", scope: .member("a"), restriction: F.peanuts, createdAt: F.confirmed)
        let r2 = Rule(id: "r2", scope: .member("a"), restriction: F.jain, createdAt: F.confirmed)
        var household = F.household([F.member("a", status: .stated), F.member("b", status: .unasked, confirmedAt: nil)], rules: [r1, r2])
        try household.removeRule("r1", confirmedAt: later)
        #expect(household.members[0].safetyStatus == .stated && household.members[0].safetyConfirmedAt == F.confirmed)
        try household.removeRule("r2", confirmedAt: later)
        #expect(household.members[0].safetyStatus == .confirmedNone && household.members[0].safetyConfirmedAt == later)
        #expect(household.members[1].safetyStatus == .unasked)
        #expect(throws: SafetyTransitionError.unknownRule("r2")) { try household.removeRule("r2", confirmedAt: later) }
    }

    @Test("AC-3.2: an added member is unasked and blocks planning until answered")
    func addMemberBlocks() throws {
        var household = F.household(
            [F.member("a", status: .stated)],
            rules: [Rule(id: "r1", scope: .household, restriction: F.peanuts, createdAt: F.confirmed)])
        let added = household.addMember(role: .adult, ageBand: .adult, at: later, id: "new")
        #expect(added.safetyStatus == .unasked && added.safetyConfirmedAt == nil)
        #expect(added.label == MemberLabel(role: .adult, number: 2))
        #expect(household.members.last == added)
        #expect(F.refusal(SafetyGate.evaluate(household, now: later, timeZone: F.utc)) == .safetyUnanswered(["new"]))

        try household.addRule(Rule(id: "r2", scope: .member("new"), restriction: F.jain, createdAt: later), at: later)
        #expect(household.member("new")?.safetyStatus == .stated)
        #expect(F.clearance(SafetyGate.evaluate(household, now: later, timeZone: F.utc)) != nil)
    }

    @Test("U3: removing an unasked new member unblocks planning")
    func removeMemberUnblocks() throws {
        var household = F.household([F.member("a")])
        household.addMember(role: .child, ageBand: .child, at: later, id: "new")
        try household.removeMember("new", at: later)
        #expect(household.member("new")?.deletedAt == later)
        #expect(F.clearance(SafetyGate.evaluate(household, now: later, timeZone: F.utc)) != nil)
        #expect(throws: SafetyTransitionError.deletedMember("new")) { try household.removeMember("new", at: later) }
    }

    @Test("q1: the last active member cannot be removed")
    func lastMemberCannotBeRemoved() {
        var household = F.household([F.member("a"), F.member("gone", deletedAt: F.confirmed)])
        let before = household
        #expect(throws: SafetyTransitionError.lastMember("a")) { try household.removeMember("a", at: later) }
        #expect(household == before)
    }

    @Test(
        "AC-3.4: age band crossing child/grown (or to/from unknown) resets to unasked",
        arguments: ageBandCrossings)
    func ageBandCrossing(from: AgeBand?, to: AgeBand?, resets: Bool) throws {
        for status in [SafetyStatus.confirmedNone, .stated] {
            var household = F.household([F.member("a", status: status, ageBand: from)])
            let crossed = try household.setAgeBand(to, for: "a", at: later)
            #expect(crossed == resets)
            #expect(household.members[0].ageBand == to)
            #expect(household.members[0].safetyStatus == (resets ? .unasked : status))
            #expect(household.members[0].safetyConfirmedAt == (resets ? nil : F.confirmed))
            let cleared = F.clearance(SafetyGate.evaluate(household, now: later, timeZone: F.utc)) != nil
            #expect(cleared == !resets)
        }
    }

    @Test("age band reset keeps the member's rules for the re-confirmation")
    func ageBandResetKeepsRules() throws {
        let rule = Rule(id: "r1", scope: .member("a"), restriction: F.peanuts, createdAt: F.confirmed)
        var household = F.household([F.member("a", .child, status: .stated, ageBand: .child)], rules: [rule])
        try household.setAgeBand(.teen, for: "a", at: later)
        #expect(household.rules == [rule])
        #expect(household.members[0].safetyStatus == .unasked)
        // M1: re-confirming the kept rules unblocks without inventing or removing a rule.
        try household.confirmMemberAnswer(for: "a", at: later)
        #expect(household.members[0].safetyStatus == .stated)
        #expect(household.rules == [rule])
        #expect(F.clearance(SafetyGate.evaluate(household, now: later, timeZone: F.utc)) != nil)
    }

    @Test("G3: \"Still correct?\" refreshes the date of answered members and clears the due refusal")
    func stillCorrect() throws {
        let old = F.confirmed.addingTimeInterval(-181 * F.day)
        var household = F.household([
            F.member("a", confirmedAt: old), F.member("b", status: .stated, confirmedAt: old),
            F.member("c", status: .unasked, confirmedAt: nil),
        ])
        let refreshed = try household.reconfirmSafety(at: F.confirmed)
        #expect(refreshed == ["a", "b"])
        #expect(household.members.map(\.safetyConfirmedAt) == [F.confirmed, F.confirmed, nil])
        #expect(household.members.map(\.safetyStatus) == [.confirmedNone, .stated, .unasked])
        // Still refused: "c" must answer the full question, not a one-tap refresh.
        #expect(F.refusal(SafetyGate.evaluate(household, now: F.confirmed, timeZone: F.utc)) == .safetyUnanswered(["c"]))
    }

    @Test("\"Still correct?\" for specific members only refreshes those")
    func stillCorrectForSomeMembers() throws {
        let old = F.confirmed.addingTimeInterval(-181 * F.day)
        var household = F.household([F.member("a", confirmedAt: old), F.member("b", confirmedAt: old)])
        let refreshed = try household.reconfirmSafety(for: ["a", "a"], at: F.confirmed)
        #expect(refreshed == ["a"])  // n1: duplicates collapse
        #expect(F.refusal(SafetyGate.evaluate(household, now: F.confirmed, timeZone: F.utc)) == .reconfirmationDue(["b"]))
        #expect(throws: SafetyTransitionError.unknownMember("x")) { try household.reconfirmSafety(for: ["x"], at: F.confirmed) }
    }
}
