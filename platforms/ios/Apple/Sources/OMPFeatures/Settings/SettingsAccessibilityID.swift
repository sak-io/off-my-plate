/// Accessibility identifiers of the Household tab and the learning screens (task T27). The UI
/// tests in `App/OffMyPlateUITests/SettingsUITests.swift` run out of process and repeat these
/// strings.
extension AccessibilityID {
    static let householdPerson = "household.person."  // + index
    static let householdAddPerson = "household.addPerson"
    static let householdAllergies = "household.allergies"
    static let householdLearned = "household.learned"
    static let householdAbout = "household.about.disclaimer"
    static let householdDeleteAll = "household.deleteAll"
    static let householdSaveFailed = "household.saveFailed"

    static let personSheet = "person.sheet"
    static let personName = "person.name"
    static let personAge = "person.age"
    static let personSave = "person.save"
    static let personRemove = "person.remove"
    static let personCancel = "person.cancel"

    static let rulesRoot = "rules.root"
    static let rulesEmpty = "rules.empty"
    static let rulesAdd = "rules.add"
    static let rulesDone = "rules.done"
    static func rulesRow(_ index: Int) -> String { "rules.row.\(index)" }
    static func rulesRemove(_ index: Int) -> String { "rules.remove.\(index)" }
    static let addRuleSheet = "rules.add.sheet"
    static let addRuleWho = "rules.add.who"
    static let addRuleText = "rules.add.text"
    static let addRuleTextAdd = "rules.add.textAdd"
    static let addRuleContinue = "rules.add.continue"
    static let addRuleSave = "rules.add.save"
    static let addRuleChange = "rules.add.change"
    static let addRuleCancel = "rules.add.cancel"
    static let addRuleSummary = "rules.add.summary"
    static func addRuleChip(_ restriction: String) -> String { "rules.add.chip.\(restriction)" }

    static let learnedRoot = "learned.root"
    static let learnedEmpty = "learned.empty"
    static let learnedIntro = "learned.intro"
    static let learnedSafetyLink = "learned.safetyLink"
    static let learnedLoadFailed = "learned.failed"
    static func learnedRow(_ index: Int) -> String { "learned.row.\(index)" }
    static func learnedConfirm(_ index: Int) -> String { "learned.thatsRight.\(index)" }

    static let factSheet = "fact.sheet"
    static let factOrigin = "fact.origin"
    static let factWho = "fact.who"
    static let factStrength = "fact.strength"
    static let factSave = "fact.save"
    static let factForget = "fact.forget"

    static let reflectCard = "reflect.card"
    static let reflectYes = "reflect.yes"
    static let reflectNo = "reflect.no"
    static let reflectNever = "reflect.never"

    static let reconfirmCard = "reconfirm.card"
    static let reconfirmYes = "reconfirm.yes"
    static let reconfirmChange = "reconfirm.change"
    static let planSafetySummary = "plan.safetySummary"
    static let planSafetyChange = "plan.safetyChange"

    static let aboutRoot = "about.root"
    static let aboutVersion = "about.version"
}
