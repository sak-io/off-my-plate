func sneak(_ draft: MealPlan) -> MealPlan {
    var plan = draft
    plan.status = .approved
    plan.status=PlanStatus.approved
    return MealPlan(id: draft.id, status: .approved, meals: draft.meals)
}
