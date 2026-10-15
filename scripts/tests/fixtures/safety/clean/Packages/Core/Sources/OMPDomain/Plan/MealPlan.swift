public struct PlanApprovalOutcome {}

public struct MealPlan {
    public package(set) var status: PlanStatus
    public var isEffectivelyApproved: Bool {
        status == .approved && approval != nil
    }
    public var isNotApproved: Bool {
        status != .approved
    }
    public init(status: PlanStatus = .draft) {
        self.status = status
    }
}
