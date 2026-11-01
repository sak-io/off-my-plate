import UIKit
import XCTest

/// The one accessibility-audit helper every UI test uses (so the exceptions live in ONE place).
///
/// - Runs the audit in two passes that together cover every audit type: a single pass over a
///   long list timed out on iPad ("Audit failed to complete in time"), so the work is split,
///   not reduced.
/// - Reports EVERY issue in one run (the plain call stops at the first), with element type,
///   frame and description, and the bottom of the element tree for diagnosis.
/// - Owner-approved exceptions (2026-10-14, tracked for T28 which must find the real cause and
///   delete them): on iPad, issues that have NO element at all (the system tab bar / sidebar,
///   one per tab); and, when asked, Dynamic Type on the system "Plan" label. Any issue that
///   names an element still fails the test.
@MainActor
func ompAuditAll(_ app: XCUIApplication, ignoreDynamicTypeOnPlanLabel: Bool = false, knownIssue: String? = nil) {
    var found: [String] = []
    let visual: XCUIAccessibilityAuditType = [.contrast, .textClipped, .dynamicType]
    let rest = XCUIAccessibilityAuditType.all.subtracting(visual)
    let isPad = UIDevice.current.userInterfaceIdiom == .pad
    for types in [visual, rest] {
        do {
            try app.performAccessibilityAudit(for: types) { issue in
                let planLabel = ignoreDynamicTypeOnPlanLabel && issue.auditType == .dynamicType
                    && issue.element?.label == "Plan"
                let ipadChrome = isPad && issue.element == nil
                if !planLabel && !ipadChrome {
                    let label = issue.element?.label ?? "?"
                    let id = issue.element?.identifier ?? ""
                    let type = issue.element?.elementType.rawValue ?? 0
                    let frame = issue.element?.frame ?? .zero
                    let detail = String((issue.element?.debugDescription ?? "").prefix(300))
                    found.append(
                        "\(issue.auditType) | \(issue.compactDescription) | label '\(label)' id '\(id)' type \(type) frame \(frame) | detail: \(issue.detailedDescription) | \(detail)")
                }
                return true
            }
        } catch {
            found.append("audit threw: \(error)")
        }
    }
    // Only the bottom of the screen (y >= 560): the full tree is dominated by list rows.
    let bottom = app.debugDescription.split(separator: "\n").filter { line in
        guard let r = line.range(of: "{{") else { return false }
        let nums = line[r.upperBound...].prefix(while: { $0 != "}" }).split(separator: ",")
        return Double(nums.last?.trimmingCharacters(in: .whitespaces) ?? "") ?? 0 >= 560
    }.joined(separator: "\n")
    let tree = found.isEmpty ? "" : "\nBottom of screen (y >= 560):\n" + String(bottom.prefix(6000))
    if let knownIssue, !found.isEmpty {
        // Owner-approved waiver (2026-10-14, batch 4): these screens' audit findings are tracked for
        // T28 (real fix with Accessibility Inspector). The audit still runs and reports every issue;
        // the failure is recorded as an EXPECTED failure. Non-strict on purpose: findings move
        // between runs, and a lucky pass must not turn the suite red.
        let options = XCTExpectedFailure.Options()
        options.isStrict = false
        XCTExpectFailure(knownIssue, options: options)
    }
    XCTAssertTrue(
        found.isEmpty, "Accessibility audit issues (\(found.count)):\n" + found.joined(separator: "\n") + tree)
}
