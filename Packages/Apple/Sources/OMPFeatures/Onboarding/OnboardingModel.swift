import Foundation
import Observation
import OMPCapture
import OMPDomain
import OMPServices

/// A cuisine chip on S-03 (C-035b). The ids are the seed catalog's cuisine ids.
struct CuisineChoice: Identifiable, Hashable, Sendable {
    /// `nil` for "A bit of everything": it stores nothing (the same as Skip).
    let cuisine: CuisineID?
    let title: String
    let identifier: String
    var id: String { identifier }

    nonisolated static var all: [CuisineChoice] {
        [
            CuisineChoice(
                cuisine: "northIndian",
                title: String(localized: "cuisine.northIndian", defaultValue: "North Indian"), identifier: "northIndian"),
            CuisineChoice(
                cuisine: "southIndian",
                title: String(localized: "cuisine.southIndian", defaultValue: "South Indian"), identifier: "southIndian"),
            CuisineChoice(
                cuisine: "westIndian",
                title: String(localized: "cuisine.westIndian", defaultValue: "Gujarati / Maharashtrian"),
                identifier: "westIndian"),
            CuisineChoice(
                cuisine: "eastIndian",
                title: String(localized: "cuisine.eastIndian", defaultValue: "Bengali / East Indian"),
                identifier: "eastIndian"),
            CuisineChoice(
                cuisine: nil,
                title: String(localized: "cuisine.everything", defaultValue: "A bit of everything"),
                identifier: "everything"),
        ]
    }
}

/// First launch (flow F1, AC-1.1-1.6): Who's eating -> safety question -> cuisines -> first plan.
/// Three questions at most; the optional detail is never required.
///
/// The model only calls the services. The household is created at S-01 Continue with every
/// member `unasked`, so planning stays blocked (gate) until the safety question is answered.
@MainActor
@Observable
final class OnboardingModel {
    enum Step: Equatable { case whoIsEating, safety, cuisines, planning }
    enum PlanningPhase: Equatable { case working, failed }

    static let memberLimit = Household.memberCountRange.upperBound

    private let services: SafetyServices
    private let speech: (any SpeechCapture)?
    private let onFinished: @MainActor () async -> Void

    private(set) var step: Step = .whoIsEating
    var adults = 2
    var children = 0
    private(set) var selectedCuisines: Set<String> = []
    private(set) var isWorking = false
    var saveFailed = false
    private(set) var planningPhase: PlanningPhase = .working
    private(set) var isSlow = false
    /// The S-02 model for the current safety page; rebuilt each time the page is entered.
    private(set) var safetyModel: SafetyAnswerModel?

    init(
        services: SafetyServices, speech: (any SpeechCapture)?,
        onFinished: @escaping @MainActor () async -> Void
    ) {
        self.services = services
        self.speech = speech
        self.onFinished = onFinished
    }

    // MARK: S-01

    var total: Int { adults + children }
    var maxAdults: Int { max(0, Self.memberLimit - children) }
    var maxChildren: Int { max(0, Self.memberLimit - adults) }
    var canContinueFromWho: Bool { Household.memberCountRange.contains(total) && !isWorking }
    var atMemberLimit: Bool { total >= Self.memberLimit }

    /// Continue on S-01: creates the household (or, after Back, adds or removes only the people
    /// that changed), then moves on to the safety question.
    func continueFromWho() async {
        guard canContinueFromWho else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await applyCounts()
            try await enterSafety()
        } catch {
            fail(error)
        }
    }

    /// Creates the household, or reconciles the stored one with the counts on screen: raising a
    /// count adds `unasked` members, lowering removes the highest-numbered members and the
    /// rules that were tagged only to them (F1 edge paths).
    private func applyCounts() async throws {
        guard let stored = try await services.household.household() else {
            try await services.household.createHousehold(adults: adults, children: children)
            return
        }
        for (role, wanted) in [(MemberRole.adult, adults), (MemberRole.child, children)] {
            let current = stored.activeMembers.filter { $0.label.role == role }
                .sorted { $0.label.number < $1.label.number }
            if wanted > current.count {
                for _ in current.count..<wanted {
                    try await services.household.addMember(role: role, ageBand: role == .adult ? .adult : .child)
                }
            } else if wanted < current.count {
                for member in current.suffix(current.count - wanted).reversed() {
                    let onlyForThem = stored.rules.filter { $0.scope == .member(member.id) }
                    for rule in onlyForThem { try await services.safety.removeRule(rule.id) }
                    try await services.household.removeMember(member.id)
                }
            }
        }
    }

    // MARK: S-02

    /// Opens the safety question for what is still unanswered: everyone (the onboarding
    /// variant with the Who? menu), or, when only some members are unasked (people added after
    /// going back), those members one by one. Skips to S-03 when nobody is unasked.
    private func enterSafety() async throws {
        guard let stored = try await services.household.household() else { throw ServiceError.noHousehold }
        let active = stored.activeMembers
        let unasked = active.filter { $0.safetyStatus == .unasked }
        safetyModel = nil
        if unasked.isEmpty {
            step = .cuisines
        } else if unasked.count == active.count {
            safetyModel = SafetyAnswerModel(
                subject: .household(members: active), services: services, speech: speech,
                onFinished: { [weak self] in await self?.safetyAnswered() })
            step = .safety
        } else if let first = unasked.first {
            safetyModel = SafetyAnswerModel(
                subject: .member(first, householdMemberCount: active.count), services: services, speech: speech,
                onFinished: { [weak self] in await self?.safetyAnswered() })
            step = .safety
        }
    }

    /// The services saved an answer: ask for whoever is still unasked, else go on.
    private func safetyAnswered() async {
        do {
            try await enterSafety()
        } catch {
            fail(error)
        }
    }

    /// Back from S-02 to S-01. The question stays unanswered; nothing is skipped.
    func backToWho() {
        safetyModel?.viewDisappeared()
        safetyModel = nil
        step = .whoIsEating
    }

    // MARK: S-03

    func toggleCuisine(_ choice: CuisineChoice) {
        if selectedCuisines.contains(choice.identifier) {
            selectedCuisines.remove(choice.identifier)
        } else if choice.cuisine == nil {
            selectedCuisines = [choice.identifier]
        } else {
            selectedCuisines.remove("everything")
            selectedCuisines.insert(choice.identifier)
        }
    }

    /// Back from S-03. The safety answers are already saved, so this returns to S-01 (the
    /// question is not asked twice; it is edited later in the Household tab).
    func backFromCuisines() {
        step = .whoIsEating
    }

    /// "Make my plan" (picked cuisines) or "Skip" (nothing stored).
    func continueFromCuisines(skip: Bool) async {
        guard !isWorking else { return }
        isWorking = true
        if !skip {
            let picked = CuisineChoice.all.compactMap { choice in
                selectedCuisines.contains(choice.identifier) ? choice.cuisine : nil
            }
            if !picked.isEmpty {
                do {
                    try await services.household.recordCuisines(picked)
                } catch {
                    isWorking = false
                    fail(error)
                    return
                }
            }
        }
        isWorking = false
        step = .planning
        await makePlan()
    }

    // MARK: S-04

    /// Makes the first draft week. The planner runs behind the safety gate and the independent
    /// validator inside `PlanService`; a draft that already exists (a retry) counts as done.
    func makePlan() async {
        planningPhase = .working
        isSlow = false
        let slowTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { self?.isSlow = true }
        }
        defer { slowTimer.cancel() }
        do {
            _ = try await services.plans.generateWeek()
        } catch ServiceError.openDraftExists {
            // A previous attempt already made the draft.
        } catch {
            let kind = OMPLog.errorKind(error)
            OMPLog.app.error("First plan failed: \(kind, privacy: .public)")
            planningPhase = .failed
            return
        }
        await onFinished()
    }

    private func fail(_ error: any Error) {
        let kind = OMPLog.errorKind(error)
        OMPLog.app.error("Onboarding step failed: \(kind, privacy: .public)")
        saveFailed = true
    }
}
