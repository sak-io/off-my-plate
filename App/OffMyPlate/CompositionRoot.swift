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
            wireSafety(model, repositories: repositories, clock: clock, speech: UITestSpeech.fake(arguments: arguments))
            // Notes import (T26): UI tests drop a fixture into a temporary inbox, never the App Group.
            if let inbox = UITestInbox(arguments: arguments) {
                wireImports(
                    model, repositories: repositories, clock: clock, inbox: inbox.makeStorage(now: clock.now),
                    processed: InMemoryProcessedImportStore())
            }
            return model
        }
        #endif

        do {
            let store = try PersistenceStore(location: try StoreLocation.appDefault())
            let repositories = store.makeRepositories()
            let model = AppModel(
                repositories: repositories, clock: clock, planBackend: makePlanBackend(repositories, clock: clock))
            wireSafety(model, repositories: repositories, clock: clock, speech: OnDeviceSpeechCapture(backend: SystemSpeechBackend()))
            wireImports(
                model, repositories: repositories, clock: clock, inbox: appGroupInbox(),
                processed: store.makeProcessedImportStore())
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
            model.pantryBackend = LivePantryBackend(context: context)
            model.shoppingBackend = LiveShoppingBackend(context: context)
        } catch {
            let kind = OMPLog.errorKind(error)
            OMPLog.app.fault("Seed library could not be loaded: \(kind, privacy: .public)")
        }
    }

    /// The Share Extension's inbox folder in the App Group (ADR 0011), or nil when the group is
    /// not available (an unsigned build): the app then simply has nothing to import.
    private static func appGroupInbox() -> (any InboxStorage)? {
        let groupID = Bundle.main.object(forInfoDictionaryKey: "OMPAppGroupIdentifier") as? String ?? ""
        guard !groupID.isEmpty,
            let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)
        else {
            OMPLog.app.info("App Group not available: Notes import is off")
            return nil
        }
        return DirectoryInboxStorage(root: container.appendingPathComponent(InboxFiles.directoryName, isDirectory: true))
    }

    /// Gives the model an `ImportService` over the inbox (T26); the model drains it at launch and
    /// whenever the scene becomes active. Imports add list/pantry rows and staple events only.
    private static func wireImports(
        _ model: AppModel, repositories: Repositories, clock: any DomainClock, inbox: (any InboxStorage)?,
        processed: any ProcessedImportStore
    ) {
        guard let inbox else { return }
        do {
            let context = ServiceContext(
                repositories: repositories, clock: clock, library: PlanningLibrary(seed: try SeedLoader.loadBundled()))
            model.importService = ImportService(context: context, inbox: inbox, processedImports: processed)
        } catch {
            let kind = OMPLog.errorKind(error)
            OMPLog.app.fault("Seed library could not be loaded for imports: \(kind, privacy: .public)")
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
/// Inbox fixtures for the UI tests: `-OMPUITestInbox <name>` (Debug builds only). The files go to
/// a fresh temporary folder, so the tests never depend on the App Group (CI simulators run
/// unsigned) or on real data.
enum UITestInbox: String {
    /// Two free-text items for the shopping list: the toast reads "Added 2 items from Notes."
    case twoItems

    static let argument = "-OMPUITestInbox"

    init?(arguments: [String]) {
        guard let index = arguments.firstIndex(of: Self.argument), arguments.indices.contains(index + 1)
        else { return nil }
        self.init(rawValue: arguments[index + 1])
    }

    func makeStorage(now: Date) -> any InboxStorage {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("omp-uitest-inbox-\(UUID().uuidString)", isDirectory: true)
        switch self {
        case .twoItems:
            do {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                let item = try InboxImport(
                    createdAt: now, destination: .shoppingList,
                    items: [InboxImport.Item(name: "Curry leaves"), InboxImport.Item(name: "Jaggery")])
                try item.encoded().write(to: root.appendingPathComponent(item.fileName))
            } catch {
                OMPLog.app.fault("UI test inbox fixture could not be written")
            }
        }
        return DirectoryInboxStorage(root: root)
    }
}

/// Households the UI tests start with: `-OMPUITestSeed <name>` (Debug builds only, never in
/// Release). Every seed uses a fresh in-memory store, so tests never touch real data.
enum UITestSeed: String {
    /// No household (before onboarding).
    case empty
    /// Adult 1 and Child 1, both answered today: no gate cover.
    case answered
    /// Adult 1 answered; Child 1 and Child 2 unasked: the gate cover shows "1 of 2".
    case unasked
    /// Like `answered`, plus a stocked pantry: salt, oil and curry leaves (in nearly every seed
    /// recipe), rice, stale milk and the unrecognised "masala mix" (T24).
    case pantry

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
        case .answered, .pantry:
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
            household: InMemoryRepository<Household>(seeded), mealPlans: empty.mealPlans,
            pantry: InMemoryRepository<PantryItem>(self == .pantry ? Self.pantryItems(now: now) : []),
            shopping: empty.shopping, cookLogs: empty.cookLogs, facts: empty.facts,
            learningEvents: empty.learningEvents, promptStates: empty.promptStates)
    }

    private static func pantryItem(
        _ id: String, _ ingredient: String, _ quantity: Double, _ unit: MeasureUnit, _ location: StorageLocation,
        confirmed: Date, expiresOn: LocalDate? = nil
    ) -> PantryItem {
        PantryItem(
            id: PantryItemID(id), item: .ingredient(IngredientID(ingredient)), quantity: quantity, unit: unit,
            location: location, expiresOn: expiresOn, lastConfirmedAt: confirmed, source: .manual)
    }

    private static func pantryItems(now: Date) -> [PantryItem] {
        let tenDaysAgo = now.addingTimeInterval(-10 * 86_400)
        return [
            pantryItem("ui-salt", "salt", 100, .teaspoon, .shelf, confirmed: now),
            pantryItem("ui-coconut-oil", "coconut-oil", 100, .tablespoon, .shelf, confirmed: now),
            pantryItem("ui-curry-leaves", "curry-leaves", 500, .gram, .fridge, confirmed: now),
            pantryItem("ui-rice", "rice", 2, .kilogram, .shelf, confirmed: now),
            // Fridge items are stale after 7 days (AC-9.7).
            pantryItem("ui-milk", "milk", 1, .litre, .fridge, confirmed: tenDaysAgo),
            PantryItem(
                id: PantryItemID("ui-masala"), item: .freeText("masala mix"), quantity: 1, unit: .piece,
                location: .shelf, lastConfirmedAt: now, source: .manual),
        ]
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

#if DEBUG
/// The speech adapter UI tests run with: `-OMPUITestSpeech available|denied|unavailable`
/// (Debug builds only). The default is on-device-unsupported, as before T24.
enum UITestSpeech {
    static let argument = "-OMPUITestSpeech"

    @MainActor
    static func fake(arguments: [String]) -> FakeSpeechCapture {
        let value = arguments.firstIndex(of: argument).flatMap { index in
            arguments.indices.contains(index + 1) ? arguments[index + 1] : nil
        }
        switch value {
        case "available":
            return FakeSpeechCapture(
                availability: .available,
                scriptedTranscripts: [
                    SpeechTranscript(text: "I bought 2 kg rice and a dozen eggs", isFinal: true)
                ])
        case "denied":
            return FakeSpeechCapture(availability: .permissionDenied)
        default:
            return FakeSpeechCapture(availability: .onDeviceUnsupported)
        }
    }
}
#endif
