import Testing

@Test func approves() {
    let report = ValidationReport(planId: "p", contentHash: "h", violations: [])
    let outcome = PlanLifecycle.approve(draft, confirmation: UserConfirmation(), validation: report)
    var plan = MealPlan(status: .approved, approval: PlanApproval(approvedAt: now, contentHash: "h"))
    plan.meals[0].blockedBySafety = false
}

@Test(.disabled("a non-safety test may be disabled outside the safety suite"))
func notInTheSuite() {}
