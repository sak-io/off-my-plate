public struct ValidationReport: Encodable, Sendable {
    package init(planId: MealPlanID, contentHash: String, violations: [Violation]) {}
}

extension ValidationReport {
    public var passedForEveryone: Bool { true }
}
