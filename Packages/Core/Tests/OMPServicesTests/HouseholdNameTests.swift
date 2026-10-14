import Foundation
import OMPDomain
import OMPServices
import Testing

@Suite("Member names (AC-16.1, T27)")
struct HouseholdNameTests {
    @Test("A name is trimmed and stored; empty text clears it")
    func setAndClear() async throws {
        let env = ServicesEnv()
        let household = try await env.onboardWithoutRules()
        let id = try #require(household.members.first?.id)

        let named = try await env.households.setName("  Asha  ", for: id)
        #expect(named.member(id)?.name == "Asha")
        #expect(try await env.household().member(id)?.name == "Asha")

        let cleared = try await env.households.setName("   ", for: id)
        #expect(cleared.member(id)?.name == nil)
    }

    @Test("A name never changes safety status or rules")
    func leavesSafetyAlone() async throws {
        let env = ServicesEnv()
        let before = try await env.onboardWithoutRules()
        let id = try #require(before.members.first?.id)
        let after = try await env.households.setName("Asha", for: id)
        #expect(after.member(id)?.safetyStatus == before.member(id)?.safetyStatus)
        #expect(after.member(id)?.safetyConfirmedAt == before.member(id)?.safetyConfirmedAt)
        #expect(after.rules == before.rules)
    }

    @Test("A very long name is cut")
    func longName() async throws {
        let env = ServicesEnv()
        let household = try await env.onboardWithoutRules()
        let id = try #require(household.members.first?.id)
        let named = try await env.households.setName(String(repeating: "a", count: 100), for: id)
        #expect(named.member(id)?.name?.count == HouseholdService.maxNameLength)
    }

    @Test("An unknown member is refused and nothing changes")
    func unknownMember() async throws {
        let env = ServicesEnv()
        let before = try await env.onboardWithoutRules()
        let error = await serviceError { _ = try await env.households.setName("X", for: MemberID.generate()) }
        #expect(error == .invalidInput("no such member"))
        #expect(try await env.household() == before)
    }

    @Test("Control, newline and bidi characters are stripped")
    func stripsControlCharacters() async throws {
        let env = ServicesEnv()
        let household = try await env.onboardWithoutRules()
        let id = try #require(household.members.first?.id)
        let named = try await env.households.setName("A\nsha\u{202E}\u{200B}\t", for: id)
        #expect(named.member(id)?.name == "Asha")
    }

    @Test("Text that is empty after cleaning clears the name")
    func emptyAfterCleaning() async throws {
        let env = ServicesEnv()
        let household = try await env.onboardWithoutRules()
        let id = try #require(household.members.first?.id)
        _ = try await env.households.setName("Asha", for: id)
        let cleared = try await env.households.setName("\u{202E}\n\u{200B}", for: id)
        #expect(cleared.member(id)?.name == nil)
    }

    @Test("Cutting to the limit leaves no trailing space")
    func trimsAfterCut() async throws {
        let env = ServicesEnv()
        let household = try await env.onboardWithoutRules()
        let id = try #require(household.members.first?.id)
        let text = String(repeating: "a", count: HouseholdService.maxNameLength - 1) + " bbb"
        let named = try await env.households.setName(text, for: id)
        #expect(named.member(id)?.name == String(repeating: "a", count: HouseholdService.maxNameLength - 1))
    }

    @Test("A removed member cannot be renamed")
    func removedMember() async throws {
        let env = ServicesEnv()
        let household = try await env.onboardWithoutRules()
        let id = try #require(household.members.last?.id)
        _ = try await env.households.removeMember(id)
        let error = await serviceError { _ = try await env.households.setName("X", for: id) }
        #expect(error == .invalidInput("no such member"))
    }

    @Test("ZWNJ and ZWJ survive: a Malayalam name with a chillu and a ZWJ emoji")
    func keepsJoiners() async throws {
        let env = ServicesEnv()
        let household = try await env.onboardWithoutRules()
        let id = try #require(household.members.first?.id)
        let malayalam = "\u{0D05}\u{0D2E}\u{0D32}\u{0D4D}\u{200D}\u{0D2F}\u{0D3E}\u{200C}\u{0D33}\u{0D02}"
        let named = try await env.households.setName(malayalam, for: id)
        #expect(named.member(id)?.name == malayalam)
        let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"
        let emoji = try await env.households.setName(family, for: id)
        #expect(emoji.member(id)?.name == family)
    }

    @Test("Other format characters are still stripped next to joiners")
    func stripsOthersNextToJoiners() async throws {
        let env = ServicesEnv()
        let household = try await env.onboardWithoutRules()
        let id = try #require(household.members.first?.id)
        let named = try await env.households.setName("A\u{200D}\u{202E}B\u{200B}", for: id)
        #expect(named.member(id)?.name == "A\u{200D}B")
    }

    @Test("The length cut never lands inside a grapheme cluster")
    func cutKeepsClusters() async throws {
        let env = ServicesEnv()
        let household = try await env.onboardWithoutRules()
        let id = try #require(household.members.first?.id)
        let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"
        let text = String(repeating: "a", count: HouseholdService.maxNameLength - 1) + family + "zzz"
        let named = try await env.households.setName(text, for: id)
        let stored = try #require(named.member(id)?.name)
        #expect(stored == String(repeating: "a", count: HouseholdService.maxNameLength - 1) + family)
    }
}
