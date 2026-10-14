import Foundation
import OMPCapture
import OMPData
import OMPDomain
import OMPFeatures
import OMPRecipes
import OMPServices

/// The composition root (ADR 0004): the only place that chooses concrete implementations.
///
/// Production: the SwiftData store (`PersistenceStore`, T20) in the app's own container.
/// UI tests (Debug builds only): an in-memory store seeded by a launch argument, see
/// `UITestSeed`. The use-case services of T18/T19 are wired here when they land.
@MainActor
enum CompositionRoot {
    static func makeAppModel(arguments: [String]) -> AppModel {
        let clock = SystemClock(timeZone: TimeZone.autoupdatingCurrent)

        #if DEBUG
        if let seed = UITestSeed(arguments: arguments) {
            OMPLog.app.info("UI test seed \(seed.rawValue, privacy: .public): in-memory store")
            let repositories = seed.repositories(now: clock.now)
            let model = AppModel(
                repositories: repositories, clock: clock, planBackend: makePlanBackend(repositories, clock: clock))
            // UI tests never touch the microphone or the speech service.
            wireSafety(model, repositories: repositories, clock: clock, speech: FakeSpeechCapture(availability: .onDeviceUnsupported))
            return model
        }
        #endif

        do {
            let store = try PersistenceStore(location: try StoreLocation.appDefault())
            let repositories = store.makeRepositories()
            let model = AppModel(
                repositories: repositories, clock: clock, planBackend: makePlanBackend(repositories, clock: clock))
            wireSafety(model, repositories: repositories, clock: clock, speech: OnDeviceSpeechCapture(backend: SystemSpeechBackend()))
            return model
        } catch {
            let kind = OMPLog.errorKind(error)
            OMPLog.app.fault("Store could not be opened: \(kind, privacy: .public)")
            return AppModel.storeUnavailable(clock: clock)
        }
    }

    /// Builds the use-case services (T18) over the same repositories and gives them to the
    /// model, with the bundled seed library and the safety keyword table (T16).
    private static func wireSafety(
        _ model: AppModel, repositories: Repositories, clock: any DomainClock, speech: any SpeechCapture
    ) {
        do {
            let seed = try SeedLoader.loadBundled()
            let context = ServiceContext(
                repositories: repositories, clock: clock, library: PlanningLibrary(seed: seed),
                diagnostics: { _ in OMPLog.app.fault("The validator rejected planner output") })
            model.safetyServices = SafetyServices(
                context: context, parser: SafetyTextParser(keywords: seed.catalog.restrictionKeywords))
            model.speechCapture = speech
        } catch {
            let kind = OMPLog.errorKind(error)
            OMPLog.app.fault("Seed library could not be loaded: \(kind, privacy: .public)")
        }
    }

    /// The planning services over the bundled recipe library, or nil when the library cannot be
    /// loaded (the Plan tab then shows C-052 and nothing is planned).
    private static func makePlanBackend(_ repositories: Repositories, clock: any DomainClock) -> (any PlanBackend)? {
        do {
            let library = PlanningLibrary(seed: try SeedLoader.loadBundled())
            let context = ServiceContext(
                repositories: repositories, clock: clock, library: library,
                diagnostics: { diagnostic in
                    switch diagnostic {
                    case .validatorRejectedPlannerOutput(let planId, let meals):
                        let count = meals.count
                        OMPLog.app.fault(
                            "Validator rejected planner output: \(count, privacy: .public) meals; plan \(planId.rawValue, privacy: .private)")
                    }
                })
            return LivePlanBackend(context: context)
        } catch {
            let kind = OMPLog.errorKind(error)
            OMPLog.app.fault("Recipe library could not be loaded: \(kind, privacy: .public)")
            return nil
        }
    }
}

#if DEBUG
/// Households the UI tests start with: `-OMPUITestSeed <name>` (Debug builds only, never in
/// Release). Every seed uses a fresh in-memory store, so tests never touch real data.
enum UITestSeed: String {
    /// No household (before onboarding).
    case empty
    /// Adult 1 and Child 1, both answered today: no gate cover.
    case answered
    /// Adult 1 answered; Child 1 and Child 2 unasked: the gate cover shows "1 of 2".
    case unasked

    static let argument = "-OMPUITestSeed"

    init?(arguments: [String]) {
        guard let index = arguments.firstIndex(of: Self.argument), arguments.indices.contains(index + 1)
        else { return nil }
        self.init(rawValue: arguments[index + 1])
    }

    func repositories(now: Date) -> Repositories {
        let empty = Repositories.inMemory()
        let seeded: [Household]
        switch self {
        case .empty:
            return empty
        case .answered:
            seeded = [Self.household(now: now, members: [
                Self.member(.adult, 1, answeredAt: now), Self.member(.child, 1, answeredAt: now),
            ])]
        case .unasked:
            seeded = [Self.household(now: now, members: [
                Self.member(.adult, 1, answeredAt: now), Self.member(.child, 1, answeredAt: nil),
                Self.member(.child, 2, answeredAt: nil),
            ])]
        }
        return Repositories(
            household: InMemoryRepository<Household>(seeded), mealPlans: empty.mealPlans, pantry: empty.pantry,
            shopping: empty.shopping, cookLogs: empty.cookLogs, facts: empty.facts,
            learningEvents: empty.learningEvents, promptStates: empty.promptStates)
    }

    private static func household(now: Date, members: [Member]) -> Household {
        Household(id: HouseholdID.generate(), members: members, createdAt: now, updatedAt: now)
    }

    private static func member(_ role: MemberRole, _ number: Int, answeredAt: Date?) -> Member {
        Member(
            id: MemberID.generate(),
            label: MemberLabel(role: role, number: number),
            ageBand: role == .adult ? .adult : .child,
            safetyStatus: answeredAt == nil ? .unasked : .confirmedNone,
            safetyConfirmedAt: answeredAt)
    }
}
#endif
