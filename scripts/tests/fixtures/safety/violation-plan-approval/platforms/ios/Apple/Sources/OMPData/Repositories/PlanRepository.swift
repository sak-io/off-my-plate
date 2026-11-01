func save(_ plan: MealPlan) {
    let approval = PlanApproval(approvedAt: now, contentHash: plan.contentHash)
}
