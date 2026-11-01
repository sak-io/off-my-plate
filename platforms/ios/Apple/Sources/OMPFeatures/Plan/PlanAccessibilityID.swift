/// Accessibility identifiers of the Plan screens. The UI tests (`App/OffMyPlateUITests`) repeat
/// these strings; per-meal ones end with the planned meal's raw id.
extension AccessibilityID {
    static let planStatus = "plan.status"
    static let planBanner = "plan.banner"
    static let planBannerDismiss = "plan.banner.dismiss"
    static let planBlocked = "plan.blocked"
    static let planBlockedAnswer = "plan.blocked.answer"
    static let planError = "plan.error"
    static let planErrorRetry = "plan.error.retry"
    static let planLoading = "plan.loading"
    static let planEmpty = "plan.empty"
    static let planMakePlan = "plan.makePlan"
    static let planRegenerate = "plan.regenerate"
    static let planApprove = "plan.approve"
    static let planReviewChanges = "plan.reviewChanges"
    static let planList = "plan.list"
    static let planSafetyChanged = "plan.safetyChanged"
    static let planUpdate = "plan.update"
    static let mealBlocked = "meal.blocked"
    static func planBlockedMeal(_ id: String) -> String { "plan.blockedMeal.\(id)" }

    static let mealDetail = "meal.detail"
    static let mealLock = "meal.lock"
    static let mealSwap = "meal.swap"
    static let mealMarkCooked = "meal.markCooked"
    static let mealDraftCaption = "meal.draftCaption"
    static let lunchboxCard = "lunchbox.card"
    static let lunchboxYes = "lunchbox.yes"
    static let lunchboxNo = "lunchbox.no"
    static let lunchboxNotNow = "lunchbox.notNow"

    static let swapSheet = "swap.sheet"
    static let swapCancel = "swap.cancel"
    static let swapPickForMe = "swap.pickForMe"
    static let swapEmpty = "swap.empty"
    static func swapReason(_ raw: String) -> String { "swap.reason.\(raw)" }
    static func swapOption(_ recipe: String) -> String { "swap.option.\(recipe)" }

    static let approvalSheet = "approval.sheet"
    static let approvalApprove = "approval.approve"
    static let approvalDiscard = "approval.discard"
    static let approvalNotYet = "approval.notYet"
    static let approvalSafety = "approval.safety"
    static let approvalFailed = "approval.failed"
    static let approvalFailedOK = "approval.failed.ok"
    static func approvalChange(_ index: Int) -> String { "approval.change.\(index)" }

    static let schoolSheet = "schoolLunches.sheet"
    static let schoolCancel = "schoolLunches.cancel"
    static let schoolSave = "schoolLunches.save"
    static func schoolChild(_ id: String) -> String { "schoolLunches.child.\(id)" }
    static func schoolDay(_ raw: String) -> String { "schoolLunches.day.\(raw)" }

    static func planDay(_ iso: String) -> String { "plan.day.\(iso)" }
    static func planMeal(_ id: String) -> String { "plan.meal.\(id)" }
    static func planLock(_ id: String) -> String { "plan.lock.\(id)" }
    static func planChanged(_ id: String) -> String { "plan.changed.\(id)" }
    static func planCooked(_ id: String) -> String { "plan.cooked.\(id)" }
    static func planMarkCooked(_ id: String) -> String { "plan.markCooked.\(id)" }
    static func planWhy(_ id: String) -> String { "plan.why.\(id)" }
    static func planWhyText(_ id: String) -> String { "plan.whyText.\(id)" }
}
