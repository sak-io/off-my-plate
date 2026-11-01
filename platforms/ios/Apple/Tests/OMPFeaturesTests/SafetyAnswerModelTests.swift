import Foundation
import OMPCapture
import OMPDomain
import OMPServices
import Testing

@testable import OMPFeatures

@Suite("SafetyAnswerModel (S-02, S-02b, gate cover)")
@MainActor
struct SafetyAnswerModelTests {
    /// A stored household of `adults` + `children`, all unasked, and a household-variant model.
    private func onboardingModel(
        adults: Int = 2, children: Int = 1, repositories: Repositories = .inMemory(),
        speech: (any SpeechCapture)? = nil, counter: FinishCounter = FinishCounter()
    ) async throws -> (SafetyAnswerModel, SafetyServices, FinishCounter) {
        let services = makeSafetyServices(repositories)
        try await services.household.createHousehold(adults: adults, children: children)
        let stored = try await storedHousehold(services)
        let model = SafetyAnswerModel(
            subject: .household(members: stored.activeMembers), services: services, speech: speech,
            onFinished: { counter.count += 1 })
        return (model, services, counter)
    }

    private func memberModel(
        _ index: Int, repositories: Repositories = .inMemory(), counter: FinishCounter = FinishCounter()
    ) async throws -> (SafetyAnswerModel, SafetyServices, Member) {
        let services = makeSafetyServices(repositories)
        try await services.household.createHousehold(adults: 1, children: 2)
        let stored = try await storedHousehold(services)
        let member = stored.activeMembers[index]
        let model = SafetyAnswerModel(
            subject: .member(member, householdMemberCount: stored.activeMembers.count), services: services,
            speech: nil, onFinished: { counter.count += 1 })
        return (model, services, member)
    }

    private func restriction(_ id: String) -> RestrictionID { RestrictionID(id) }

    // MARK: No, nobody

    @Test("No, nobody confirms every member as having nothing to avoid and saves no rules")
    func nobody() async throws {
        let (model, services, counter) = try await onboardingModel()
        #expect(model.canChooseNobody)
        await model.chooseNobody()
        let stored = try await storedHousehold(services)
        #expect(stored.activeMembers.allSatisfy { $0.safetyStatus == .confirmedNone })
        #expect(stored.rules.isEmpty)
        #expect(counter.count == 1)
    }

    @Test("No, nobody is disabled while the list has items, and does nothing if forced")
    func nobodyDisabledWithItems() async throws {
        let (model, services, counter) = try await onboardingModel()
        model.toggleChip(restriction("peanuts"))
        #expect(!model.canChooseNobody)
        await model.chooseNobody()
        let stored = try await storedHousehold(services)
        #expect(stored.activeMembers.allSatisfy { $0.safetyStatus == .unasked })
        #expect(counter.count == 0)
    }

    // MARK: Chips -> candidates -> explicit confirm

    @Test("Chips add rows; tapping a chip again removes it; nothing is saved until confirmed")
    func chipsAreCandidatesOnly() async throws {
        let (model, services, _) = try await onboardingModel()
        model.toggleChip(restriction("peanuts"))
        model.toggleChip(restriction("beef"))
        #expect(model.items.count == 2)
        #expect(model.isChipSelected(restriction("peanuts")))
        model.toggleChip(restriction("beef"))
        #expect(!model.isChipSelected(restriction("beef")))
        #expect(model.items.count == 1)
        let stored = try await storedHousehold(services)
        #expect(stored.rules.isEmpty)
        #expect(stored.activeMembers.allSatisfy { $0.safetyStatus == .unasked })
    }

    @Test("Continue shows the summary; Yes, save this saves household-scope rules and answers everyone")
    func chipsThenConfirm() async throws {
        let (model, services, counter) = try await onboardingModel()
        model.toggleChip(restriction("peanuts"))
        model.toggleChip(restriction("beef"))
        #expect(model.canContinue)
        model.continueToSummary()
        #expect(model.phase == .summary)
        #expect(model.summaryRows.map(\.who) == [SafetyCopy.everyone])
        #expect(model.summaryRows.first?.items.count == 2)
        await model.confirmSummary()
        let stored = try await storedHousehold(services)
        #expect(Set(stored.rules.map(\.restriction)) == [restriction("peanuts"), restriction("beef")])
        #expect(stored.rules.allSatisfy { $0.scope == .household })
        #expect(stored.activeMembers.allSatisfy { $0.safetyStatus == .stated })
        #expect(counter.count == 1)
    }

    @Test("Change returns to the list with every row kept")
    func changeKeepsRows() async throws {
        let (model, _, _) = try await onboardingModel()
        model.toggleChip(restriction("milk"))
        model.continueToSummary()
        model.backToEntry()
        #expect(model.phase == .entry)
        #expect(model.items.count == 1)
    }

    @Test("A per-person item gives that person a row and 'Everyone else: nothing to avoid'")
    func perPersonSummary() async throws {
        let (model, services, _) = try await onboardingModel()
        let adult1 = try await storedHousehold(services).activeMembers[0]
        model.toggleChip(restriction("peanuts"))
        let itemID = try #require(model.items.first?.id)
        model.setScope(.member(adult1.id), for: itemID)
        model.continueToSummary()
        #expect(model.summaryRows.map(\.who) == [adult1.displayName, SafetyCopy.everyoneElse])
        #expect(model.summaryRows.last?.items.isEmpty == true)
        await model.confirmSummary()
        let stored = try await storedHousehold(services)
        #expect(stored.member(adult1.id)?.safetyStatus == .stated)
        let others = stored.activeMembers.filter { $0.id != adult1.id }
        #expect(others.allSatisfy { $0.safetyStatus == .confirmedNone })
    }

    @Test("Who? is hidden for a one-person household")
    func whoHiddenForOne() async throws {
        let (model, _, _) = try await onboardingModel(adults: 1, children: 0)
        #expect(model.whoOptions.isEmpty)
        #expect(model.items.isEmpty)
    }

    // MARK: Text and unmapped items

    @Test("Typed text becomes candidate rows; an unknown word is unresolved and blocks Continue")
    func unmappedBlocksContinue() async throws {
        let (model, services, _) = try await onboardingModel()
        model.draftText = "no beef, kiwi"
        model.submitText()
        #expect(model.draftText.isEmpty)
        #expect(model.items.contains { $0.restrictionID == restriction("beef") })
        #expect(model.hasUnresolved)
        #expect(!model.canContinue)
        model.continueToSummary()
        #expect(model.phase == .entry)
        await model.confirmSummary()
        let stored = try await storedHousehold(services)
        #expect(stored.rules.isEmpty)
        #expect(stored.activeMembers.allSatisfy { $0.safetyStatus == .unasked })
    }

    @Test("Picking the closest match resolves an unmapped row")
    func pickClosest() async throws {
        let (model, _, _) = try await onboardingModel()
        model.draftText = "kiwi"
        model.submitText()
        let unresolved = try #require(model.items.first)
        #expect(unresolved.isUnresolved)
        model.resolve(unresolved.id, to: restriction("milk"))
        #expect(!model.hasUnresolved)
        #expect(model.items.first?.restrictionID == restriction("milk"))
        #expect(model.canContinue)
    }

    @Test("Removing an unmapped row clears the block")
    func removeUnmapped() async throws {
        let (model, _, _) = try await onboardingModel()
        model.draftText = "kiwi"
        model.submitText()
        let id = try #require(model.items.first?.id)
        model.remove(id)
        #expect(model.items.isEmpty)
        #expect(model.canChooseNobody)
    }

    @Test("A name in the text is only a hint: the row still applies to everyone")
    func memberHintDoesNotAssign() async throws {
        let (model, _, _) = try await onboardingModel()
        model.draftText = "Meera has a peanut allergy"
        model.submitText()
        #expect(model.items.contains { $0.restrictionID == restriction("peanuts") })
        #expect(model.items.allSatisfy { $0.scope == .household })
    }

    @Test("One word can select several restrictions, each its own row, without duplicates")
    func nutsSelectsTwo() async throws {
        let (model, _, _) = try await onboardingModel()
        model.draftText = "nuts"
        model.submitText()
        model.toggleChip(restriction("peanuts"))
        #expect(model.items.compactMap(\.restrictionID).sorted { $0.rawValue < $1.rawValue }
            == [restriction("peanuts"), restriction("tree-nuts")])
    }

    @Test("A newline from the text field submits the text")
    func newlineSubmits() async throws {
        let (model, _, _) = try await onboardingModel()
        model.draftText = "no beef\n"
        model.draftTextChanged()
        #expect(model.items.contains { $0.restrictionID == restriction("beef") })
    }

    // MARK: Save failure

    @Test("A failed save keeps the answers and shows the error; nobody is marked answered")
    func saveFailureKeepsAnswers() async throws {
        let seeded = makeSafetyServices()
        try await seeded.household.createHousehold(adults: 1, children: 1)
        let seededHousehold = try await storedHousehold(seeded)
        let base = InMemoryRepository<Household>([seededHousehold])
        let empty = Repositories.inMemory()
        let repositories = Repositories(
            household: WriteFailingHouseholdRepository(base: base), mealPlans: empty.mealPlans,
            pantry: empty.pantry, shopping: empty.shopping, cookLogs: empty.cookLogs, facts: empty.facts,
            learningEvents: empty.learningEvents, promptStates: empty.promptStates)
        let services = makeSafetyServices(repositories)
        let members = try await storedHousehold(services).activeMembers
        let counter = FinishCounter()
        let model = SafetyAnswerModel(
            subject: .household(members: members), services: services, speech: nil,
            onFinished: { counter.count += 1 })
        model.toggleChip(restriction("peanuts"))
        model.continueToSummary()
        await model.confirmSummary()
        #expect(model.saveFailed)
        #expect(model.items.count == 1)
        #expect(counter.count == 0)
        #expect(!model.isSaving)
        let stored = try await storedHousehold(services)
        #expect(stored.activeMembers.allSatisfy { $0.safetyStatus == .unasked })
    }

    // MARK: Gate-cover (member) variant

    @Test("'No, nothing' answers only that member")
    func memberNothing() async throws {
        let (model, services, member) = try await memberModel(1)
        #expect(model.whoOptions.isEmpty)
        await model.chooseNobody()
        let stored = try await storedHousehold(services)
        #expect(stored.member(member.id)?.safetyStatus == .confirmedNone)
        #expect(stored.activeMembers.filter { $0.safetyStatus == .unasked }.count == 2)
    }

    @Test("Items for an added member become rules scoped to that member only")
    func memberItems() async throws {
        let (model, services, member) = try await memberModel(2)
        model.toggleChip(restriction("milk"))
        model.continueToSummary()
        #expect(model.summaryRows.map(\.who) == [member.displayName])
        await model.confirmSummary()
        let stored = try await storedHousehold(services)
        #expect(stored.rules.map(\.scope) == [.member(member.id)])
        #expect(stored.member(member.id)?.safetyStatus == .stated)
    }

    @Test("A household-wide rule already covering the member makes 'No, nothing' a stated answer")
    func memberCoveredByHouseholdRule() async throws {
        let services = makeSafetyServices()
        try await services.household.createHousehold(adults: 1, children: 0)
        let first = try await storedHousehold(services).activeMembers[0]
        try await services.safety.confirmSafetyAnswers([RuleRequest(restriction: "beef", scope: .household)])
        let added = try await services.household.addMember(role: .child, ageBand: .child)
        #expect(added.safetyStatus == .unasked)
        let model = SafetyAnswerModel(
            subject: .member(added, householdMemberCount: 2), services: services, speech: nil, onFinished: {})
        await model.chooseNobody()
        let stored = try await storedHousehold(services)
        #expect(stored.member(added.id)?.safetyStatus == .stated)
        #expect(stored.member(first.id)?.safetyStatus == .stated)
        #expect(stored.rules.count == 1)
    }

    @Test("Retrying a member save does not duplicate rules already in force")
    func memberRetryNoDuplicates() async throws {
        let (model, services, member) = try await memberModel(1)
        try await services.safety.addRule(RuleRequest(restriction: "milk", scope: .member(member.id)))
        model.toggleChip(restriction("milk"))
        model.continueToSummary()
        await model.confirmSummary()
        let stored = try await storedHousehold(services)
        #expect(stored.rules.filter { $0.restriction == restriction("milk") }.count == 1)
        #expect(stored.member(member.id)?.safetyStatus == .stated)
    }

    @Test("Added by mistake removes the member; the last member cannot be removed")
    func removeSubject() async throws {
        let (model, services, member) = try await memberModel(2)
        #expect(model.canRemoveSubject)
        await model.removeSubject()
        let stored = try await storedHousehold(services)
        #expect(stored.member(member.id)?.isDeleted == true)

        let solo = makeSafetyServices()
        try await solo.household.createHousehold(adults: 1, children: 0)
        let only = try await storedHousehold(solo).activeMembers[0]
        let soloModel = SafetyAnswerModel(
            subject: .member(only, householdMemberCount: 1), services: solo, speech: nil, onFinished: {})
        #expect(!soloModel.canRemoveSubject)
        await soloModel.removeSubject()
        #expect(try await storedHousehold(solo).member(only.id)?.isDeleted == false)
    }

    @Test("The household variant offers no remove-person escape")
    func noEscapeInOnboardingVariant() async throws {
        let (model, _, _) = try await onboardingModel()
        #expect(!model.canRemoveSubject)
        #expect(model.subjectMember == nil)
    }

    // MARK: Voice (T30)

    private func settle(_ model: SafetyAnswerModel) async {
        for _ in 0..<500 where model.voice == .listening { await Task.yield() }
    }

    @Test("A spoken answer becomes candidate rows, never saved rules")
    func voiceFillsRows() async throws {
        let fake = FakeSpeechCapture(
            availability: .available, scriptedTranscripts: [SpeechTranscript(text: "no peanuts", isFinal: true)])
        let (model, services, _) = try await onboardingModel(speech: fake)
        await model.micTapped()
        await settle(model)
        #expect(fake.startCount == 1)
        #expect(model.items.contains { $0.restrictionID == restriction("peanuts") })
        let stored = try await storedHousehold(services)
        #expect(stored.rules.isEmpty)
    }

    @Test("Text submitted after Continue (late transcript) adds no rows behind the summary")
    func lateTextIgnoredInSummary() async throws {
        let fake = FakeSpeechCapture(availability: .available)
        let (model, _, _) = try await onboardingModel(speech: fake)
        model.toggleChip(restriction("milk"))
        model.continueToSummary()
        model.draftText = "no beef"
        model.submitText()
        #expect(model.items.count == 1)
        #expect(model.phase == .summary)
        #expect(fake.stopCount >= 1)
    }

    @Test("Denied permission shows the notice; chips and text still work")
    func voiceDenied() async throws {
        let fake = FakeSpeechCapture(availability: .permissionDenied)
        let (model, _, _) = try await onboardingModel(speech: fake)
        await model.micTapped()
        #expect(model.voice == .unavailable(.permissionDenied))
        model.toggleChip(restriction("beef"))
        #expect(model.canContinue)
        model.dismissVoiceNotice()
        #expect(model.voice == .idle)
    }

    @Test("Permission is requested just in time when the mic is tapped")
    func voicePermissionPrompt() async throws {
        let fake = FakeSpeechCapture(availability: .needsPermission, availabilityAfterPrompt: .permissionDenied)
        let (model, _, _) = try await onboardingModel(speech: fake)
        await model.micTapped()
        #expect(fake.requestAuthorizationCount == 1)
        #expect(model.voice == .unavailable(.permissionDenied))
    }

    @Test("Without a speech adapter the mic explains instead of crashing")
    func voiceMissing() async throws {
        let (model, _, _) = try await onboardingModel(speech: nil)
        await model.micTapped()
        #expect(model.voice == .unavailable(.recognizerUnavailable))
    }
}
