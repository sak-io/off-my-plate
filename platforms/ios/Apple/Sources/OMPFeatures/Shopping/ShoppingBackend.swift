import Foundation
import OMPDomain
import OMPServices

/// What the List tab knows about the plan behind the list (AC-10.1, AC-10.2).
public struct ShoppingPlanInfo: Sendable, Hashable {
    /// The week of the effectively approved plan, or nil when there is none.
    public var approvedRange: ClosedRange<LocalDate>?
    /// A draft exists and nothing is approved yet (C-140 offers "Go to plan").
    public var hasDraft: Bool
    /// An approved plan has a draft revision waiting for approval (C-142).
    public var hasPendingChanges: Bool

    public init(approvedRange: ClosedRange<LocalDate>?, hasDraft: Bool, hasPendingChanges: Bool) {
        self.approvedRange = approvedRange
        self.hasDraft = hasDraft
        self.hasPendingChanges = hasPendingChanges
    }

    public static let none = ShoppingPlanInfo(approvedRange: nil, hasDraft: false, hasPendingChanges: false)
}

/// What the List tab needs from the use-case services (task T25). The live implementation wraps
/// `ShoppingService`; tests use a fake. Every change to the list goes through the service: the
/// screen never writes the repositories itself.
public protocol ShoppingBackend: Sendable {
    /// Re-derives the plan lines and returns the whole list.
    func refresh() async throws -> [ShoppingItem]
    /// The stored list as it is.
    func items() async throws -> [ShoppingItem]
    func planInfo() async throws -> ShoppingPlanInfo
    func addManual(name: String) async throws
    func setChecked(_ id: ShoppingItemID, _ checked: Bool) async throws
    func remove(_ id: ShoppingItemID) async throws
    /// Moves every checked item into the pantry; returns how many pantry items were added.
    func boughtEverything() async throws -> Int
    func shareText() async throws -> String
}

/// The services as the List tab uses them.
public final class LiveShoppingBackend: ShoppingBackend {
    private let shopping: ShoppingService
    private let plans: PlanService

    public init(context: ServiceContext) {
        self.shopping = ShoppingService(context: context)
        self.plans = PlanService(context: context)
    }

    public func refresh() async throws -> [ShoppingItem] {
        try await shopping.refresh()
    }

    public func items() async throws -> [ShoppingItem] {
        try await shopping.items()
    }

    public func planInfo() async throws -> ShoppingPlanInfo {
        guard let series = try await plans.currentSeriesID() else { return .none }
        let approved = try await plans.activeApprovedPlan(series: series)
        let working = try await plans.workingPlan(series: series)
        let diff = try await plans.pendingDiff(series: series)
        return ShoppingPlanInfo(
            approvedRange: approved.map { $0.weekStart...$0.endDate },
            hasDraft: approved == nil && working?.status == .draft,
            hasPendingChanges: diff != nil)
    }

    public func addManual(name: String) async throws {
        _ = try await shopping.addManual(ShoppingItemInput(name: name))
    }

    public func setChecked(_ id: ShoppingItemID, _ checked: Bool) async throws {
        _ = try await shopping.setChecked(id, checked)
    }

    public func remove(_ id: ShoppingItemID) async throws {
        try await shopping.remove(id)
    }

    public func boughtEverything() async throws -> Int {
        try await shopping.boughtEverything().count
    }

    public func shareText() async throws -> String {
        try await shopping.shareText()
    }
}
