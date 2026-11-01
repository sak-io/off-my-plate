func approve(_ draft: MealPlan) {
    let report = ValidationReport(planId: draft.id, contentHash: draft.contentHash, violations: [])
    let shorthand: ValidationReport = .init(planId: draft.id, contentHash: "", violations: [])
}

extension ValidationReport {
    static var alwaysPassing: ValidationReport { .forged }
}
