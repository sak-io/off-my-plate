/// Accessibility identifiers the UI tests query (`App/OffMyPlateUITests`). The UI tests run
/// out of process and cannot import this module, so they repeat these strings.
enum AccessibilityID {
    static let gateCover = "gate.cover"
    static let gateTitle = "gate.cover.title"
    static let gateProgress = "gate.cover.progress"
    static let loadFailed = "shell.loadFailed"

    static func tabRoot(_ tab: AppTab) -> String {
        "tab.\(tab.rawValue).root"
    }
}
