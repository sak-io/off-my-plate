public struct UserConfirmation: Sendable, Hashable {
    public init() {}
}

public enum PlanLifecycle {
    public static func approve(_ draft: MealPlan, confirmation: UserConfirmation, now: Date) -> MealPlan {
        var approved = draft
        approved.status = .approved
        approved.approval = PlanApproval(approver: .thisDevice, approvedAt: now, contentHash: "")
        for index in approved.meals.indices {
            approved.meals[index].blockedBySafety = false
        }
        return approved
    }
}
