enum WeekPlanner {
    static func unblock(_ meal: inout PlannedMeal) {
        meal.blockedBySafety = false
    }
}
