extension PlannedMeal {
    public func replacingRecipe(with alternative: MealAlternative) -> PlannedMeal {
        var meal = self
        meal.blockedBySafety = false
        return meal
    }
}

extension WeekPlanner {
    public static func reroll(
        _ mealID: PlannedMealID, in plan: MealPlan, clearance: borrowing SafetyClearance
    ) throws(PlannerError) -> PlannedMeal? {
        nil
    }
}
