enum RecordMappers {
    static func plan(_ record: PlanRecord) -> MealPlan {
        let approval = PlanApproval(approvedAt: record.approvedAt, contentHash: record.hash)
        var plan = MealPlan(status: .approved, approval: approval)
        plan.status = .approved
        plan.meals[0].blockedBySafety = false
        return plan
    }
}
