import UIKit
import XCTest

/// Plan tab (task T23): make a plan, approve the week, edit an approved plan, regenerate with a
/// locked meal, and an accessibility audit of the draft plan. Voice "approve it" opens the
/// sheet only: covered in OMPFeaturesTests (`PlanViewModelTests`), as the Plan tab has no
/// voice control in v1.
///
/// Identifiers mirror `AccessibilityID` in OMPFeatures/Plan/PlanAccessibilityID.swift (this
/// target cannot import it). Each wait is evaluated before its assertion: XCUIElement is
/// main-actor isolated and XCTAssert's autoclosure is not, under Swift 6 strict concurrency.
final class PlanUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-OMPUITestSeed", "answered"]
        app.launch()
        return app
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Elements whose identifier starts with `prefix`.
    @MainActor
    private func elements(_ app: XCUIApplication, prefix: String) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
    }

    /// Launches, makes the first plan and waits for the draft with its Approve week button.
    @MainActor
    private func launchWithDraft() -> XCUIApplication {
        let app = launch()
        let makePlan = element(app, "plan.makePlan")
        let offered = makePlan.waitForExistence(timeout: 20)
        XCTAssertTrue(offered, "The empty Plan tab does not offer Make a plan")
        makePlan.tap()
        let approve = element(app, "plan.approve")
        let drafted = approve.waitForExistence(timeout: 30)
        XCTAssertTrue(drafted, "No draft plan with an Approve week button appeared")
        // Let the insertion animations finish: the audit measured text mid-transition.
        let settle = XCTestExpectation(description: "settle")
        settle.isInverted = true
        _ = XCTWaiter().wait(for: [settle], timeout: 2)
        return app
    }

    @MainActor
    private func approveWeek(_ app: XCUIApplication) {
        element(app, "plan.approve").tap()
        let status = element(app, "plan.status")
        let approved = NSPredicate(format: "label CONTAINS %@", "Approved")
        let done = expectation(for: approved, evaluatedWith: status)
        let result = XCTWaiter().wait(for: [done], timeout: 20)
        XCTAssertEqual(result, .completed, "The plan did not become approved: \(status.label)")
    }

    @MainActor
    private func openFirstMeal(_ app: XCUIApplication) {
        let first = elements(app, prefix: "plan.meal.").firstMatch
        let shown = first.waitForExistence(timeout: 10)
        XCTAssertTrue(shown, "The plan has no meal rows")
        first.tap()
        let detail = element(app, "meal.detail").waitForExistence(timeout: 5)
        XCTAssertTrue(detail, "The meal detail did not open")
    }

    @MainActor
    private func goBack(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        let hittable = back.waitForExistence(timeout: 5)
        XCTAssertTrue(hittable, "No back button")
        back.tap()
        let listShown = element(app, "plan.status").waitForExistence(timeout: 10)
        XCTAssertTrue(listShown, "The week did not reappear")
    }

    @MainActor
    func testApproveWholeWeekEnablesMarkCooked() throws {
        let app = launchWithDraft()
        let draftLabel = element(app, "plan.status").label
        XCTAssertTrue(draftLabel.contains("Draft"), "Not a draft: \(draftLabel)")
        let draftCooked = elements(app, prefix: "plan.markCooked.").count
        XCTAssertEqual(draftCooked, 0, "Mark cooked is offered on a draft")

        approveWeek(app)
        let approveGone = !element(app, "plan.approve").exists
        XCTAssertTrue(approveGone, "The Approve week button stays after approval")
        let cookable = elements(app, prefix: "plan.markCooked.").firstMatch.waitForExistence(timeout: 5)
        XCTAssertTrue(cookable, "No Mark cooked on today's meals after approval")
    }

    @MainActor
    func testEditingAnApprovedPlanShowsPendingChangesAndDiffSheet() throws {
        let app = launchWithDraft()
        approveWeek(app)

        openFirstMeal(app)
        let swap = element(app, "meal.swap")
        let swapShown = swap.waitForExistence(timeout: 5)
        XCTAssertTrue(swapShown)
        swap.tap()
        let sheet = element(app, "swap.sheet").waitForExistence(timeout: 5)
        XCTAssertTrue(sheet, "The swap sheet did not open")
        let option = elements(app, prefix: "swap.option.").firstMatch
        let offered = option.waitForExistence(timeout: 10)
        XCTAssertTrue(offered, "The swap sheet offers no alternatives")
        option.tap()
        let closed = element(app, "swap.sheet").waitForNonExistence(timeout: 10)
        XCTAssertTrue(closed, "The swap sheet stays open after choosing")
        goBack(app)

        let status = element(app, "plan.status")
        let pending = NSPredicate(format: "label CONTAINS[c] %@", "not approved")
        let waiting = expectation(for: pending, evaluatedWith: status)
        let result = XCTWaiter().wait(for: [waiting], timeout: 10)
        XCTAssertEqual(result, .completed, "No pending-changes status: \(status.label)")
        let changedRows = elements(app, prefix: "plan.changed.").count
        XCTAssertGreaterThan(changedRows, 0, "No row is marked Changed")

        let review = element(app, "plan.reviewChanges")
        let barShown = review.waitForExistence(timeout: 5)
        XCTAssertTrue(barShown, "No Review changes bar")
        review.tap()
        let diff = element(app, "approval.sheet").waitForExistence(timeout: 5)
        XCTAssertTrue(diff, "The approval diff sheet did not open")
        let change = element(app, "approval.change.0").exists
        XCTAssertTrue(change, "The diff lists no change")
        let approveButton = element(app, "approval.approve").exists
        XCTAssertTrue(approveButton, "The diff sheet has no Approve button")
        let stillPending = elements(app, prefix: "plan.changed.").count
        XCTAssertGreaterThan(stillPending, 0, "Opening the sheet approved something")

        element(app, "approval.discard").tap()
        let confirm = app.buttons["Discard"]
        let confirmShown = confirm.waitForExistence(timeout: 5)
        XCTAssertTrue(confirmShown, "No discard confirmation")
        confirm.tap()
        let sheetClosed = element(app, "approval.sheet").waitForNonExistence(timeout: 10)
        XCTAssertTrue(sheetClosed, "The diff sheet stays open after discarding")
        let approvedAgain = NSPredicate(format: "label CONTAINS %@", "Approved")
        let back = expectation(for: approvedAgain, evaluatedWith: element(app, "plan.status"))
        let backResult = XCTWaiter().wait(for: [back], timeout: 10)
        XCTAssertEqual(backResult, .completed, "The approved plan is not back after discarding")
    }

    /// Labels of the visible meal rows other than `mealID`, in order.
    @MainActor
    private func otherMealLabels(_ app: XCUIApplication, except mealID: String) -> [String] {
        elements(app, prefix: "plan.meal.").allElementsBoundByIndex
            .filter { $0.identifier != "plan.meal.\(mealID)" }
            .map(\.label)
    }

    @MainActor
    func testRegenerateKeepsLockedMeals() throws {
        let app = launchWithDraft()
        openFirstMeal(app)
        let lock = element(app, "meal.lock")
        let lockShown = lock.waitForExistence(timeout: 5)
        XCTAssertTrue(lockShown)
        lock.tap()
        goBack(app)

        let locked = elements(app, prefix: "plan.lock.").firstMatch
        let lockedShown = locked.waitForExistence(timeout: 10)
        XCTAssertTrue(lockedShown, "The meal does not show as locked")
        let mealID = String(locked.identifier.dropFirst("plan.lock.".count))
        let before = element(app, "plan.meal.\(mealID)").label
        let othersBefore = otherMealLabels(app, except: mealID)

        element(app, "plan.regenerate").tap()
        let replace = app.buttons["Replace"]
        let confirmShown = replace.waitForExistence(timeout: 5)
        XCTAssertTrue(confirmShown, "No regenerate confirmation")
        replace.tap()

        let enabled = NSPredicate(format: "isEnabled == true")
        let idle = expectation(for: enabled, evaluatedWith: element(app, "plan.regenerate"))
        let result = XCTWaiter().wait(for: [idle], timeout: 30)
        XCTAssertEqual(result, .completed, "Regenerate did not finish")
        let stillLocked = element(app, "plan.lock.\(mealID)").waitForExistence(timeout: 5)
        XCTAssertTrue(stillLocked, "The locked meal lost its lock")
        let after = element(app, "plan.meal.\(mealID)").label
        XCTAssertEqual(before, after, "Regenerate replaced a locked meal")
        let othersAfter = otherMealLabels(app, except: mealID)
        XCTAssertNotEqual(othersBefore, othersAfter, "Regenerate changed no unlocked meal (no-op?)")
    }

    /// Runs the accessibility audit and reports EVERY issue in one run. The only ignores are the
    /// owner-approved Dynamic Type exceptions on the system tab bar (tracked for T28).
    @MainActor
    private func auditAll(_ app: XCUIApplication) {
        var found: [String] = []
        // Two passes covering every audit type: one pass over this long list timed out on iPad
        // ("Audit failed to complete in time"), so the work is split, not reduced.
        let visual: XCUIAccessibilityAuditType = [.contrast, .textClipped, .dynamicType]
        let rest = XCUIAccessibilityAuditType.all.subtracting(visual)
        for types in [visual, rest] {
        do {
            try app.performAccessibilityAudit(for: types) { issue in
                let ignored = issue.auditType == .dynamicType && issue.element?.label == "Plan"
                let ipadChrome = UIDevice.current.userInterfaceIdiom == .pad && issue.auditType == .dynamicType
                    && issue.element == nil
                if !ignored && !ipadChrome {
                    let label = issue.element?.label ?? "?"
                    let id = issue.element?.identifier ?? ""
                    let type = issue.element?.elementType.rawValue ?? 0
                    let frame = issue.element?.frame ?? .zero
                    let detail = String((issue.element?.debugDescription ?? "").prefix(300))
                    found.append(
                        "\(issue.auditType) | \(issue.compactDescription) | label '\(label)' id '\(id)' type \(type) frame \(frame) | \(detail)")
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
        XCTAssertTrue(found.isEmpty, "Accessibility audit issues (\(found.count)):\n" + found.joined(separator: "\n") + tree)
    }

    @MainActor
    func testDraftPlanPassesAccessibilityAudit() throws {
        let app = launchWithDraft()
        auditAll(app)
    }
}
