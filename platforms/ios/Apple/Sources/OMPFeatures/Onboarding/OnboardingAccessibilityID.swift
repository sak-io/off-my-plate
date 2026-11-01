/// Accessibility identifiers of the onboarding and safety screens (task T22). The UI tests in
/// `App/OffMyPlateUITests/OnboardingUITests.swift` run out of process and repeat these strings.
extension AccessibilityID {
    static let whoRoot = "onboarding.who"
    static let whoAdults = "onboarding.adults"
    static let whoChildren = "onboarding.children"
    static let whoFootnote = "onboarding.who.footnote"
    static let whoContinue = "onboarding.continue"

    static let safetyRoot = "safety.question"
    static let safetyBack = "safety.back"
    static let safetyNobody = "safety.nobody"
    static let safetyNobodyHint = "safety.nobody.hint"
    static let safetyText = "safety.text"
    static let safetyMic = "safety.mic"
    static let safetyVoiceNotice = "safety.voice.notice"
    static let safetyVoiceTypeInstead = "safety.voice.typeInstead"
    static let safetyContinue = "safety.continue"
    static let safetyContinueHint = "safety.continue.hint"
    static let safetySummary = "safety.summary"
    static let safetySummarySave = "safety.summary.save"
    static let safetySummaryChange = "safety.summary.change"
    static let safetyRemoveMember = "safety.removeMember"

    static func safetyChip(_ restriction: String) -> String { "safety.chip.\(restriction)" }
    static func safetyItem(_ index: Int) -> String { "safety.item.\(index)" }
    static func safetyItemRemove(_ index: Int) -> String { "safety.item.\(index).remove" }
    static func safetyItemPick(_ index: Int) -> String { "safety.item.\(index).pick" }
    static func safetyItemWho(_ index: Int) -> String { "safety.item.\(index).who" }

    static let cuisineRoot = "onboarding.cuisines"
    static let cuisineSkip = "onboarding.cuisines.skip"
    static let cuisineBack = "onboarding.cuisines.back"
    static let cuisineMakePlan = "onboarding.makePlan"
    static func cuisineChip(_ id: String) -> String { "onboarding.cuisine.\(id)" }

    static let planningRoot = "onboarding.planning"
    static let planningRetry = "onboarding.planning.retry"
}
