func perform() {
    try PlanLifecycle.approve(draft, confirmation: UserConfirmation(), validation: report, now: now)
}
