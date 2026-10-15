public enum PlanValidator {
    public static func validate(_ plan: MealPlan) -> ValidationReport {
        ValidationReport(planId: plan.id, contentHash: plan.contentHash, violations: [])
    }
}
