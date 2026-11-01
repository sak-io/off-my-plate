import Foundation
import OMPDomain
import OMPServices
import Testing

@testable import OMPFeatures

/// 2026-10-12T00:00:00Z.
let fixtureNow = Date(timeIntervalSince1970: 1_791_763_200)
let utc = TimeZone(identifier: "UTC")!

func member(_ role: MemberRole, _ number: Int, _ status: SafetyStatus, confirmedDaysAgo: Int? = 0,
            name: String? = nil, deleted: Bool = false) -> Member {
    Member(
        id: MemberID.generate(),
        label: MemberLabel(role: role, number: number),
        name: name,
        safetyStatus: status,
        safetyConfirmedAt: status == .unasked ? nil
            : confirmedDaysAgo.map { fixtureNow.addingTimeInterval(-Double($0) * 86_400) },
        deletedAt: deleted ? fixtureNow : nil)
}

func household(_ members: [Member]) -> Household {
    Household(id: HouseholdID.generate(), members: members, createdAt: fixtureNow, updatedAt: fixtureNow)
}

@Suite("GateStatus mirrors SafetyGate.evaluate")
struct GateStatusTests {
    @Test("No household means onboarding has not run; no cover, no badge")
    func noHousehold() {
        let status = GateStatus.evaluate(nil, now: fixtureNow, timeZone: utc)
        #expect(status == .noHousehold)
        #expect(!status.showsGateCover)
        #expect(!status.blocksPlanning)
    }

    @Test("Everyone answered: clear")
    func clear() {
        let status = GateStatus.evaluate(
            household([member(.adult, 1, .confirmedNone), member(.child, 1, .stated)]), now: fixtureNow,
            timeZone: utc)
        #expect(status == .clear)
        #expect(!status.showsGateCover)
        #expect(!status.blocksPlanning)
    }

    @Test("An unasked member shows the cover and blocks planning (AC-3.1)")
    func unasked() {
        let child = member(.child, 1, .unasked)
        let status = GateStatus.evaluate(
            household([member(.adult, 1, .confirmedNone), child]), now: fixtureNow, timeZone: utc)
        #expect(status == .unanswered([child.id]))
        #expect(status.showsGateCover)
        #expect(status.blocksPlanning)
        #expect(status.blockedMemberCount == 1)
    }

    @Test("A deleted unasked member never blocks")
    func deletedMemberDoesNotBlock() {
        let status = GateStatus.evaluate(
            household([member(.adult, 1, .confirmedNone), member(.child, 1, .unasked, deleted: true)]),
            now: fixtureNow, timeZone: utc)
        #expect(status == .clear)
    }

    @Test("An answer older than 180 days blocks drafts but does not show the cover (G3)")
    func reconfirmationDue() {
        let adult = member(.adult, 1, .confirmedNone, confirmedDaysAgo: 181)
        let status = GateStatus.evaluate(household([adult]), now: fixtureNow, timeZone: utc)
        #expect(status == .reconfirmationDue([adult.id]))
        #expect(!status.showsGateCover)
        #expect(status.blocksPlanning)
    }

    @Test("An answered member with no confirmation date fails closed")
    func answeredWithoutDateIsUnanswered() {
        let adult = member(.adult, 1, .confirmedNone, confirmedDaysAgo: nil)
        #expect(GateStatus.evaluate(household([adult]), now: fixtureNow, timeZone: utc).showsGateCover)
    }

    @Test("Load failures neither show the cover nor badge")
    func loadFailed() {
        #expect(!GateStatus.loadFailed.showsGateCover)
        #expect(!GateStatus.loading.blocksPlanning)
    }
}

@Suite("Member display names (AC-1.2)")
struct MemberDisplayNameTests {
    @Test("Generated labels read Adult n / Child n")
    func generatedLabels() {
        #expect(member(.adult, 2, .unasked).displayName == "Adult 2")
        #expect(member(.child, 3, .unasked).displayName == "Child 3")
    }

    @Test("A custom name wins; a blank one falls back to the label")
    func customName() {
        #expect(member(.child, 1, .unasked, name: "Asha").displayName == "Asha")
        #expect(member(.child, 1, .unasked, name: "   ").displayName == "Child 1")
    }

    @Test("Gate cover copy C-030 and C-030a interpolate name and progress")
    func gateCopy() {
        #expect(
            SafetyGateCover.title(for: member(.child, 3, .unasked))
                == "Does Child 3 have an allergy or something they must avoid?")
        #expect(SafetyGateCover.progressText(index: 1, total: 2) == "1 of 2")
    }

    @Test("Tabs have distinct titles and icons in the designed order")
    func tabs() {
        #expect(AppTab.allCases.map(\.title) == ["Plan", "List", "Pantry", "Household"])
        #expect(Set(AppTab.allCases.map(\.systemImage)).count == 4)
    }
}
