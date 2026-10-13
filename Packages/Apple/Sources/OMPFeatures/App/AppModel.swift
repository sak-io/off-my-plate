import Foundation
import Observation
import OMPDomain
import OMPServices

/// The app-wide model the shell observes (task T21).
///
/// Holds the repositories the composition root wired (SwiftData in the app, in-memory in tests
/// and previews) and exposes the safety `gateStatus`. The use-case services of T18/T19 will be
/// added here when they land; screens then talk to services, not repositories.
@MainActor
@Observable
public final class AppModel {
    /// The repositories, as wired by the composition root.
    public let repositories: Repositories
    private let clock: any DomainClock
    private let storeFailed: Bool

    /// The household as last loaded, or nil when there is none yet.
    public private(set) var household: Household?
    /// The safety gate status of `household`, re-evaluated by `refresh()`.
    public private(set) var gateStatus: GateStatus

    /// - Parameters:
    ///   - repositories: where data lives.
    ///   - clock: the clock the gate evaluates with (the 180-day re-check is time-based).
    public init(repositories: Repositories, clock: any DomainClock) {
        self.repositories = repositories
        self.clock = clock
        self.storeFailed = false
        self.gateStatus = .loading
    }

    private init(failedStoreWith clock: any DomainClock) {
        self.repositories = .inMemory()
        self.clock = clock
        self.storeFailed = true
        self.gateStatus = .loadFailed
    }

    /// A model for when the store could not be opened: shows C-096 and never pretends there is
    /// no household (which would restart onboarding over the user's data).
    public static func storeUnavailable(clock: any DomainClock) -> AppModel {
        AppModel(failedStoreWith: clock)
    }

    /// The non-deleted members the gate is waiting on, in stored order.
    public var membersNeedingAnswer: [Member] {
        guard case .unanswered(let ids) = gateStatus, let household else { return [] }
        return ids.compactMap { household.member($0) }
    }

    /// Reloads the household and re-evaluates the gate. Call on launch, when the app becomes
    /// active (the 180-day check depends on the date) and after any household change.
    public func refresh() async {
        guard !storeFailed else { return }
        do {
            let loaded = try await repositories.household.fetch()
            household = loaded
            gateStatus = GateStatus.evaluate(loaded, now: clock.now, timeZone: clock.timeZone)
        } catch {
            let kind = OMPLog.errorKind(error)
            OMPLog.app.error("Household load failed: \(kind, privacy: .public)")
            gateStatus = .loadFailed
        }
        // Locals only: log interpolations are autoclosures, and only data-free values go in.
        let statusName = gateStatus.logName
        let blockedCount = gateStatus.blockedMemberCount
        OMPLog.gate.info(
            "Gate status \(statusName, privacy: .public); members blocking \(blockedCount, privacy: .public)")
    }
}
