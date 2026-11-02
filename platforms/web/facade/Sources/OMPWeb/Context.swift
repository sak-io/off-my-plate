import Foundation
import OMPDomain
import OMPRecipes
import OMPServices

/// The per-call context every request must carry: the host's clock and zone, never ambient defaults
/// (on Wasm `TimeZone.current` is GMT and `Locale.current` is en_001, docs/windows/w02-report.md).
struct CallContext: Sendable {
    let now: Date
    let timeZone: TimeZone
    let locale: String

    static func parse(_ value: JSONValue?) throws -> CallContext {
        guard let value, case .object = value else {
            throw FacadeError("missing_context", "Every request needs a ctx with now, timeZone and locale.")
        }
        guard let nowText = value["now"]?.stringValue, let zoneText = value["timeZone"]?.stringValue,
            let locale = value["locale"]?.stringValue
        else {
            throw FacadeError("missing_context", "ctx needs now, timeZone and locale (all strings).")
        }
        guard let instant = ISODate.parse(nowText) else {
            throw FacadeError.badContext("ctx.now is not an ISO-8601 instant.")
        }
        guard !zoneText.isEmpty, let zone = TimeZone(identifier: zoneText) else {
            throw FacadeError.badContext("ctx.timeZone is not a known time zone identifier.")
        }
        guard !locale.isEmpty, locale.count <= 35 else {
            throw FacadeError.badContext("ctx.locale is empty or too long.")
        }
        guard instant >= Limits.earliestNow, instant < Limits.latestNow else {
            throw FacadeError.badContext("ctx.now must be between the years 2000 and 2100.")
        }
        // Whole seconds: stored dates are written with second precision, so nothing is lost on export/import.
        let whole = Date(timeIntervalSince1970: instant.timeIntervalSince1970.rounded(.down))
        return CallContext(now: whole, timeZone: zone, locale: locale)
    }
}

/// The clock the services read. Set from `ctx` at the start of every call; calls never overlap.
final class FacadeClock: DomainClock, @unchecked Sendable {
    private let lock = NSLock()
    private var currentNow: Date
    private var currentZone: TimeZone

    init() {
        currentNow = Date(timeIntervalSince1970: 0)
        currentZone = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0)!
    }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return currentNow
    }

    var timeZone: TimeZone {
        lock.lock()
        defer { lock.unlock() }
        return currentZone
    }

    func set(_ context: CallContext) {
        lock.lock()
        defer { lock.unlock() }
        currentNow = context.now
        currentZone = context.timeZone
    }
}

/// Deterministic ids ("w1", "w2", ...): the counter is part of the exported state, so ids stay unique
/// after a reload and a transcript replays byte-for-byte.
final class IDSource: @unchecked Sendable {
    private let lock = NSLock()
    private var counter: Int

    init(counter: Int = 0) { self.counter = counter }

    var current: Int {
        lock.lock()
        defer { lock.unlock() }
        return counter
    }

    func next() -> String {
        lock.lock()
        defer { lock.unlock() }
        counter += 1
        return "w\(counter)"
    }
}

/// The seed content, loaded and validated once per process from the embedded bytes (no Bundle).
struct SeedContent: Sendable {
    let library: PlanningLibrary
    let parser: SafetyTextParser

    static let shared: Result<SeedContent, FacadeError> = {
        do {
            let seed = try SeedLoader.load(try SeedLoader.embeddedFiles())
            return .success(
                SeedContent(
                    library: PlanningLibrary(seed: seed),
                    parser: SafetyTextParser(keywords: seed.catalog.restrictionKeywords)))
        } catch {
            return .failure(FacadeError("seed_unavailable", "The built-in recipe content could not be loaded."))
        }
    }()
}

/// One set of in-memory repositories with the services built over them.
struct Engine: Sendable {
    let repositories: Repositories
    let ids: IDSource
    let context: ServiceContext
    let households: HouseholdService
    let safety: SafetyService
    let plans: PlanService

    init(repositories: Repositories, clock: FacadeClock, ids: IDSource, content: SeedContent) {
        self.repositories = repositories
        self.ids = ids
        let source = ids
        self.context = ServiceContext(
            repositories: repositories, clock: clock, library: content.library,
            makeID: { source.next() }, diagnostics: { _ in })
        self.households = HouseholdService(context: context)
        self.safety = SafetyService(context: context)
        self.plans = PlanService(context: context)
    }
}
