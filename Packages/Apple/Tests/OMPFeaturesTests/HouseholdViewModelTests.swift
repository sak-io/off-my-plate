import Foundation
import OMPDomain
import OMPServices
import Testing

@testable import OMPFeatures

@Suite("HouseholdViewModel (S-30, S-31, S-33, delete all; AC-3.5, AC-16.1, AC-16.2)")
@MainActor
struct HouseholdViewModelTests {
    private func twoAdults() -> (Member, Member) {
        (member(.adult, 1, .confirmedNone), member(.adult, 2, .confirmedNone))
    }

    // MARK: S-30 people

    @Test("Each person's row reads Not answered, Nothing to avoid or Avoids ... (C-110a)")
    func statusTexts() async {
        let unasked = member(.child, 1, .unasked)
        let none = member(.adult, 2, .confirmedNone)
        let avoids = member(.adult, 1, .stated)
        let env = await SettingsEnv.make(
            members: [avoids, none, unasked], rules: [testRule("peanuts", for: .member(avoids.id))])
        #expect(env.people.statusText(of: unasked) == SettingsCopy.statusNotAnswered)
        #expect(env.people.statusText(of: none) == SettingsCopy.statusNothing)
        #expect(env.people.statusText(of: avoids) == SettingsCopy.statusAvoids("Peanuts"))
        #expect(env.people.status(of: unasked) == .notAnswered)
    }

    @Test("Adding a person creates an unasked member and raises the safety gate for them (AC-3.2)")
    func addPersonRaisesGate() async throws {
        let (first, second) = twoAdults()
        let env = await SettingsEnv.make(members: [first, second])
        #expect(env.app.gateStatus == .clear)

        let added = await env.people.addPerson(name: "  Asha ", ageBand: .child)
        #expect(added)
        await env.app.refresh()

        let stored = try #require(env.app.household)
        let newcomer = try #require(stored.activeMembers.last)
        #expect(newcomer.name == "Asha")
        #expect(newcomer.label == MemberLabel(role: .child, number: 1))
        #expect(newcomer.ageBand == .child)
        #expect(newcomer.safetyStatus == .unasked)
        #expect(env.app.gateStatus == .unanswered([newcomer.id]))
        #expect(env.app.membersNeedingAnswer.map(\.id) == [newcomer.id])
    }

    @Test("Name and age group are optional: a bare Add works")
    func addWithoutDetails() async throws {
        let (first, _) = twoAdults()
        let env = await SettingsEnv.make(members: [first])
        let added = await env.people.addPerson(name: "", ageBand: nil)
        #expect(added)
        await env.app.refresh()
        let newcomer = try #require(env.app.household?.activeMembers.last)
        #expect(newcomer.name == nil)
        #expect(newcomer.ageBand == nil)
        #expect(newcomer.label.role == .adult)
    }

    @Test("Toddlers and children are Child n, everyone else Adult n")
    func roleFollowsAgeGroup() {
        #expect(HouseholdViewModel.role(for: .toddler) == .child)
        #expect(HouseholdViewModel.role(for: .child) == .child)
        #expect(HouseholdViewModel.role(for: .teen) == .adult)
        #expect(HouseholdViewModel.role(for: .senior) == .adult)
        #expect(HouseholdViewModel.role(for: nil) == .adult)
    }

    @Test("A failed add shows the save-failed alert and keeps the household")
    func addFailure() async {
        let (first, _) = twoAdults()
        let base = InMemoryRepository<Household>([household([first])])
        let env = await SettingsEnv.make(
            members: [first], householdRepository: WriteFailingHouseholdRepository(base: base))
        let added = await env.people.addPerson(name: "X", ageBand: .adult)
        #expect(!added)
        #expect(env.people.saveFailed)
        #expect(await base.fetch()?.activeMembers.count == 1)
    }

    @Test("Saving a name stores it and clearing it brings the generated label back")
    func renamePerson() async throws {
        let (first, second) = twoAdults()
        let env = await SettingsEnv.make(members: [first, second])
        var saved = await env.people.savePerson(first, name: "Meera", ageBand: first.ageBand)
        #expect(saved)
        let named = try #require(env.app.household?.member(first.id))
        #expect(named.displayName == "Meera")
        saved = await env.people.savePerson(named, name: "", ageBand: named.ageBand)
        #expect(saved)
        #expect(env.app.household?.member(first.id)?.displayName == first.label.displayName)
    }

    @Test("Changing the age group across child and adult asks the safety question again (AC-3.4)")
    func ageGroupCrossing() async throws {
        var child = member(.child, 1, .confirmedNone)
        child.ageBand = .child
        let (adult, _) = twoAdults()
        let env = await SettingsEnv.make(members: [adult, child])
        #expect(env.app.gateStatus == .clear)

        let saved = await env.people.savePerson(child, name: "", ageBand: .adult)
        #expect(saved)
        #expect(env.app.gateStatus == .unanswered([child.id]))
        #expect(env.app.household?.member(child.id)?.safetyStatus == .unasked)
    }

    @Test("Removing a person works after confirmation, and the last person cannot be removed")
    func removePerson() async throws {
        let (first, second) = twoAdults()
        let env = await SettingsEnv.make(members: [first, second])
        #expect(env.people.canRemove(second))
        let removed = await env.people.removePerson(second)
        #expect(removed)
        #expect(env.people.members.map(\.id) == [first.id])
        #expect(!env.people.canRemove(first))
        let refused = await env.people.removePerson(first)
        #expect(!refused)
        #expect(env.people.members.count == 1)
    }

    // MARK: S-33 allergies

    @Test("Rules are listed by person, household-wide ones first")
    func ruleGroups() async {
        let (first, second) = twoAdults()
        let env = await SettingsEnv.make(
            members: [first, second],
            rules: [
                testRule("peanuts", for: .member(second.id)), testRule("beef", for: .household),
                testRule("milk", for: .member(first.id)),
            ])
        let groups = env.people.ruleGroups
        #expect(groups.map(\.title) == [SettingsCopy.everyone, first.displayName, second.displayName])
        #expect(groups.map { $0.rows.map(\.item) } == [["Beef"], ["Dairy/milk"], ["Peanuts"]])
    }

    @Test("Adding a rule goes through the safety service and stays after a reload (AC-3.5)")
    func addRule() async throws {
        let (first, second) = twoAdults()
        let env = await SettingsEnv.make(members: [first, second])
        let saved = await env.people.addRules([RuleRequest(restriction: "peanuts", scope: .member(first.id))])
        #expect(saved)
        let stored = try #require(try await env.repositories.household.fetch())
        #expect(stored.rules.map(\.restriction) == ["peanuts"])
        #expect(stored.rules.first?.excludedTags == [.peanut])
        #expect(stored.member(first.id)?.safetyStatus == .stated)
        let updated = try #require(env.app.household?.member(first.id))
        #expect(env.people.statusText(of: updated) == SettingsCopy.statusAvoids("Peanuts"))
    }

    @Test("A rule already in force is not added twice")
    func noDuplicateRule() async throws {
        let (first, _) = twoAdults()
        let env = await SettingsEnv.make(
            members: [first], rules: [testRule("peanuts", for: .member(first.id))])
        let saved = await env.people.addRules([RuleRequest(restriction: "peanuts", scope: .member(first.id))])
        #expect(saved)
        #expect(try await env.repositories.household.fetch()?.rules.count == 1)
    }

    @Test("Removing a rule is explicit and leaves the other rules")
    func removeRule() async throws {
        let (first, _) = twoAdults()
        let env = await SettingsEnv.make(
            members: [first],
            rules: [testRule("peanuts", for: .member(first.id)), testRule("beef", for: .household)])
        let row = try #require(env.people.ruleRows.first { $0.item == "Peanuts" })
        let removed = await env.people.removeRule(row)
        #expect(removed)
        #expect(try await env.repositories.household.fetch()?.rules.map(\.restriction) == ["beef"])
    }

    @Test("Unrecognised typed text never becomes a rule")
    func typedText() async {
        let (first, _) = twoAdults()
        let env = await SettingsEnv.make(members: [first])
        let model = AddRuleModel(read: { env.people.readSafetyText($0) })
        model.draftText = "kiwi"
        model.submitText()
        #expect(model.unrecognised.count == 1)
        #expect(model.chosen.isEmpty)
        #expect(!model.canContinue)
        model.draftText = "no beef"
        model.submitText()
        #expect(model.chosen == ["beef"])
        #expect(!model.canContinue)
        model.removeUnrecognised(model.unrecognised[0])
        #expect(model.canContinue)
        model.continueToSummary()
        #expect(model.phase == .summary)
        #expect(model.requests == [RuleRequest(restriction: "beef", scope: .household)])
        model.backToEntry()
        #expect(model.phase == .entry)
    }

    @Test("Continue is refused with nothing chosen")
    func continueNeedsAChoice() {
        let model = AddRuleModel(read: { _ in SafetyTextReading(restrictions: [], unrecognised: []) })
        model.continueToSummary()
        #expect(model.phase == .entry)
        model.toggle("milk")
        #expect(model.isChosen("milk"))
        model.toggle("milk")
        #expect(!model.isChosen("milk"))
    }

    // MARK: Summary and the 180-day card (C-061, C-040)

    @Test("The safety summary names who avoids what, and is nil when nobody avoids anything")
    func summary() async {
        let (first, second) = twoAdults()
        let none = await SettingsEnv.make(members: [first, second])
        #expect(none.people.safetySummary == nil)

        let env = await SettingsEnv.make(
            members: [first, second],
            rules: [testRule("peanuts", for: .member(first.id)), testRule("beef", for: .household)])
        #expect(
            env.people.safetySummary
                == "\(SettingsCopy.summaryAvoids(who: first.displayName, items: "Peanuts")); "
                + SettingsCopy.summaryAvoids(who: SettingsCopy.summaryEveryone, items: "Beef"))
    }

    @Test("Yes, still correct re-confirms the 180-day check and clears the block")
    func reconfirm() async throws {
        let old = member(.adult, 1, .confirmedNone, confirmedDaysAgo: 200)
        let env = await SettingsEnv.make(members: [old])
        #expect(env.app.gateStatus == .reconfirmationDue([old.id]))
        let done = await env.people.reconfirm()
        #expect(done)
        #expect(env.app.gateStatus == .clear)
        #expect(env.app.household?.member(old.id)?.safetyConfirmedAt == fixtureNow)
    }

    // MARK: Delete all data (AC-16.2)

    @Test("Delete all data empties every store and restarts onboarding")
    func deleteAll() async throws {
        let (first, _) = twoAdults()
        let env = await SettingsEnv.make(
            members: [first], facts: [softFact(.cuisineAffinity("southIndian"), .stated)],
            events: quickWeekdayEvents())
        #expect(env.app.household != nil)

        await env.people.deleteAll()

        #expect(!env.people.deleteFailed)
        #expect(try await env.repositories.household.fetch() == nil)
        #expect(try await env.repositories.facts.fetchAll().isEmpty)
        #expect(try await env.repositories.learningEvents.fetchAll().isEmpty)
        #expect(env.app.household == nil)
        #expect(env.app.gateStatus == .noHousehold)
        #expect(env.app.onboardingActive)
    }

    @Test("A failed delete says so, keeps the app on the tabs and does not restart onboarding")
    func deleteFailure() async {
        let (first, _) = twoAdults()
        let base = InMemoryRepository<Household>([household([first])])
        let env = await SettingsEnv.make(
            members: [first], householdRepository: WriteFailingHouseholdRepository(base: base))
        await env.people.deleteAll()
        #expect(env.people.deleteFailed)
        #expect(!env.app.onboardingActive)
        #expect(env.app.household != nil)
    }

    @Test("Without services the screens are unavailable and change nothing")
    func noBackend() async {
        let app = AppModel(repositories: .inMemory(), clock: FixedClock(now: fixtureNow, timeZone: utc))
        let people = HouseholdViewModel(app: app)
        #expect(!people.isAvailable)
        let added = await people.addPerson(name: "A", ageBand: nil)
        #expect(!added)
        let saved = await people.addRules([RuleRequest(restriction: "peanuts", scope: .household)])
        #expect(!saved)
    }
}
