import Foundation
import OMPCapture
import OMPDomain
import OMPServices
import Testing

@testable import OMPFeatures

@Suite("OnboardingModel (S-01, S-03, S-04; flow F1)")
@MainActor
struct OnboardingModelTests {
    private func make(
        repositories: Repositories = .inMemory(), counter: FinishCounter = FinishCounter()
    ) -> (OnboardingModel, SafetyServices, FinishCounter) {
        let services = makeSafetyServices(repositories)
        let model = OnboardingModel(services: services, speech: nil, onFinished: { counter.count += 1 })
        return (model, services, counter)
    }

    // MARK: S-01 (AC-1.1-1.3)

    @Test("Defaults to 2 adults and 0 children; Continue is enabled")
    func defaults() {
        let (model, _, _) = make()
        #expect(model.adults == 2)
        #expect(model.children == 0)
        #expect(model.canContinueFromWho)
        #expect(model.step == .whoIsEating)
    }

    @Test("Nobody is not allowed: total 0 disables Continue")
    func zeroPeople() {
        let (model, _, _) = make()
        model.adults = 0
        model.children = 0
        #expect(!model.canContinueFromWho)
    }

    @Test("The household cap is 12 in total and the steppers stop at it")
    func cap() {
        let (model, _, _) = make()
        model.adults = 8
        model.children = 4
        #expect(model.atMemberLimit)
        #expect(model.canContinueFromWho)
        #expect(model.maxAdults == 8)
        #expect(model.maxChildren == 4)
        model.children = 5
        #expect(model.maxAdults == 7)
    }

    @Test("Continue creates the members, all unasked, and opens the safety question")
    func continueCreatesUnaskedMembers() async throws {
        let (model, services, _) = make()
        model.adults = 2
        model.children = 1
        await model.continueFromWho()
        #expect(model.step == .safety)
        let stored = try await storedHousehold(services)
        #expect(stored.activeMembers.map(\.label.role) == [.adult, .adult, .child])
        #expect(stored.activeMembers.allSatisfy { $0.safetyStatus == .unasked })
        #expect(model.safetyModel?.whoOptions.count == 3)
    }

    @Test("Planning stays refused until the safety question is answered")
    func planningRefusedBeforeAnswer() async throws {
        let (model, services, _) = make()
        await model.continueFromWho()
        var refused = false
        do {
            _ = try await services.plans.generateWeek()
        } catch ServiceError.gateRefused {
            refused = true
        }
        #expect(refused)
    }

    @Test("Back from the safety question returns to S-01 and the question stays unanswered")
    func backKeepsQuestionOpen() async throws {
        let (model, services, _) = make()
        await model.continueFromWho()
        model.backToWho()
        #expect(model.step == .whoIsEating)
        #expect(try await storedHousehold(services).activeMembers.allSatisfy { $0.safetyStatus == .unasked })
        await model.continueFromWho()
        #expect(model.step == .safety)
        #expect(try await storedHousehold(services).activeMembers.count == 2)
    }

    // MARK: Safety -> cuisines

    @Test("No, nobody moves on to the cuisines step")
    func nobodyThenCuisines() async throws {
        let (model, _, _) = make()
        await model.continueFromWho()
        await model.safetyModel?.chooseNobody()
        #expect(model.step == .cuisines)
    }

    @Test("Chips, summary and Yes, save this move on to the cuisines step")
    func chipsThenCuisines() async throws {
        let (model, services, _) = make()
        await model.continueFromWho()
        let answer = try #require(model.safetyModel)
        answer.toggleChip("peanuts")
        answer.continueToSummary()
        await answer.confirmSummary()
        #expect(model.step == .cuisines)
        #expect(try await storedHousehold(services).rules.count == 1)
    }

    @Test("Raising the counts after answering asks the question again for the new person only")
    func raiseCountsAsksNewMemberOnly() async throws {
        let (model, services, _) = make()
        await model.continueFromWho()
        await model.safetyModel?.chooseNobody()
        model.backFromCuisines()
        #expect(model.step == .whoIsEating)
        model.children = 1
        await model.continueFromWho()
        #expect(model.step == .safety)
        let answer = try #require(model.safetyModel)
        let asked = try #require(answer.subjectMember)
        #expect(asked.label == MemberLabel(role: .child, number: 1))
        let stored = try await storedHousehold(services)
        #expect(stored.activeMembers.filter { $0.safetyStatus == .unasked }.map(\.id) == [asked.id])
        // Answering the new person finishes the question.
        await answer.chooseNobody()
        #expect(model.step == .cuisines)
    }

    @Test("Unchanged counts after answering skip straight to the cuisines step")
    func unchangedCountsSkipAnsweredQuestion() async throws {
        let (model, _, _) = make()
        await model.continueFromWho()
        await model.safetyModel?.chooseNobody()
        model.backFromCuisines()
        await model.continueFromWho()
        #expect(model.step == .cuisines)
    }

    @Test("Lowering the counts removes the highest-numbered members and rules tagged only to them")
    func lowerCounts() async throws {
        let (model, services, _) = make()
        model.adults = 3
        await model.continueFromWho()
        let answer = try #require(model.safetyModel)
        let third = try #require(answer.whoOptions.last)
        answer.toggleChip("milk")
        let itemID = try #require(answer.items.first?.id)
        answer.setScope(.member(third.id), for: itemID)
        answer.continueToSummary()
        await answer.confirmSummary()
        #expect(try await storedHousehold(services).rules.count == 1)

        model.backFromCuisines()
        model.adults = 2
        await model.continueFromWho()
        let stored = try await storedHousehold(services)
        #expect(stored.activeMembers.count == 2)
        #expect(stored.member(third.id)?.isDeleted == true)
        #expect(stored.rules.isEmpty)
        #expect(model.step == .cuisines)
    }

    // MARK: S-03 and S-04

    private func reachCuisines(_ model: OnboardingModel) async {
        await model.continueFromWho()
        await model.safetyModel?.chooseNobody()
    }

    @Test("Skip stores no cuisine facts and makes the plan")
    func skipStoresNothing() async throws {
        let repositories = Repositories.inMemory()
        let (model, _, counter) = make(repositories: repositories)
        await reachCuisines(model)
        await model.continueFromCuisines(skip: true)
        let facts = try await repositories.facts.fetchAll()
        #expect(facts.isEmpty)
        #expect(counter.count == 1)
    }

    @Test("Picked cuisines are stored as stated facts; 'A bit of everything' stores nothing")
    func pickedCuisines() async throws {
        let repositories = Repositories.inMemory()
        let (model, _, _) = make(repositories: repositories)
        await reachCuisines(model)
        let all = CuisineChoice.all
        model.toggleCuisine(all[0])
        model.toggleCuisine(all[3])
        await model.continueFromCuisines(skip: false)
        let facts = try await repositories.facts.fetchAll()
        #expect(facts.count == 2)
        #expect(facts.allSatisfy { $0.origin == .stated })

        let (everything, _, _) = make(repositories: .inMemory())
        await reachCuisines(everything)
        everything.toggleCuisine(all[0])
        everything.toggleCuisine(all[4])
        #expect(everything.selectedCuisines == ["everything"])
    }

    @Test("Making the plan saves a draft behind the gate, then reports done")
    func makesFirstPlan() async throws {
        let repositories = Repositories.inMemory()
        let (model, _, counter) = make(repositories: repositories)
        await reachCuisines(model)
        await model.continueFromCuisines(skip: true)
        #expect(model.step == .planning)
        #expect(model.planningPhase == .working)
        let plans = try await repositories.mealPlans.fetchAll()
        #expect(plans.count == 1)
        #expect(plans.first?.status == .draft)
        #expect(counter.count == 1)
    }

    @Test("A retry after a draft already exists still finishes")
    func retryWithExistingDraft() async throws {
        let (model, _, counter) = make()
        await reachCuisines(model)
        await model.continueFromCuisines(skip: true)
        await model.makePlan()
        #expect(counter.count == 2)
        #expect(model.planningPhase == .working)
    }

    @Test("A plan failure shows the error state with a retry")
    func planFailure() async throws {
        let (model, services, counter) = make()
        // The household was never created, so the planner refuses.
        _ = services
        await model.makePlan()
        #expect(model.planningPhase == .failed)
        #expect(counter.count == 0)
    }
}
