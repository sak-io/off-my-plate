import UIKit
import XCTest

/// List tab (task T25, screen S-25): the no-approved-plan state, the aisle sections of an
/// approved plan, manual add + check + Bought everything, the pending-changes banner, Share, and
/// accessibility audits. "Check you have" needs low-confidence pantry items, which no UI test
/// seed has: it is covered in OMPFeaturesTests (`ShoppingViewModelTests`); Bought everything
/// adding to the pantry is covered in OMPServicesTests (`ShoppingServiceTests`).
///
/// Identifiers mirror `AccessibilityID` in OMPFeatures/Shopping/ShoppingAccessibilityID.swift and
/// the Plan ones (this target cannot import them). Each wait is evaluated before its assertion:
/// XCUIElement is main-actor isolated and XCTAssert's autoclosure is not, under Swift 6.
final class ShoppingUITests: XCTestCase {
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

    @MainActor
    private func settle() {
        let settle = XCTestExpectation(description: "settle")
        settle.isInverted = true
        _ = XCTWaiter().wait(for: [settle], timeout: 2)
    }

    /// Taps the tab titled `title`: a tab-bar button on iPhone; on iPad the `.sidebarAdaptable`
    /// tab bar or sidebar exposes it as a button (or a cell when the sidebar is open).
    @MainActor
    private func tapTab(_ app: XCUIApplication, _ title: String) {
        let inTabBar = app.tabBars.buttons[title]
        if inTabBar.waitForExistence(timeout: 3), inTabBar.isHittable {
            inTabBar.tap()
            return
        }
        let button = app.buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch
        if button.exists, button.isHittable {
            button.tap()
            return
        }
        let cell = app.cells.matching(NSPredicate(format: "label == %@", title)).firstMatch
        let cellShown = cell.waitForExistence(timeout: 3)
        XCTAssertTrue(cellShown, "No tab titled \(title)")
        cell.tap()
    }

    @MainActor
    private func openListTab(_ app: XCUIApplication) {
        tapTab(app, "List")
        let shown = element(app, "tab.list.root").waitForExistence(timeout: 10)
        XCTAssertTrue(shown, "The List tab did not open")
    }

    /// Launches, makes the first plan, approves the week and waits for the approved status.
    @MainActor
    private func launchWithApprovedPlan() -> XCUIApplication {
        let app = launch()
        let makePlan = element(app, "plan.makePlan")
        let offered = makePlan.waitForExistence(timeout: 20)
        XCTAssertTrue(offered, "The empty Plan tab does not offer Make a plan")
        makePlan.tap()
        let approve = element(app, "plan.approve")
        let drafted = approve.waitForExistence(timeout: 30)
        XCTAssertTrue(drafted, "No draft plan with an Approve week button appeared")
        approve.tap()
        let status = element(app, "plan.status")
        let approved = NSPredicate(format: "label CONTAINS %@", "Approved")
        let done = expectation(for: approved, evaluatedWith: status)
        let result = XCTWaiter().wait(for: [done], timeout: 20)
        XCTAssertEqual(result, .completed, "The plan did not become approved: \(status.label)")
        return app
    }

    /// Adds a manual item through the add field.
    @MainActor
    private func addItem(_ app: XCUIApplication, _ name: String) {
        let field = element(app, "shopping.add")
        let shown = field.waitForExistence(timeout: 10)
        XCTAssertTrue(shown, "No add field")
        field.tap()
        field.typeText(name + "\n")
    }

    @MainActor
    private func itemRow(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "shopping.item.", text)
        ).firstMatch
    }

    @MainActor
    func testNoApprovedPlanOffersGoToPlan() throws {
        let app = launch()
        openListTab(app)
        let card = element(app, "shopping.noPlan").waitForExistence(timeout: 10)
        XCTAssertTrue(card, "No 'Approve your plan' card")
        let goToPlan = element(app, "shopping.goToPlan")
        goToPlan.tap()
        let planShown = element(app, "plan.makePlan").waitForExistence(timeout: 10)
        XCTAssertTrue(planShown, "Go to plan did not open the Plan tab")
    }

    @MainActor
    func testApprovedPlanShowsAisleSections() throws {
        let app = launchWithApprovedPlan()
        openListTab(app)
        let range = element(app, "shopping.range").waitForExistence(timeout: 10)
        XCTAssertTrue(range, "The list does not say which week it is for")
        let sections = elements(app, prefix: "shopping.section.").firstMatch.waitForExistence(timeout: 10)
        XCTAssertTrue(sections, "The approved plan produced no aisle section")
        let items = elements(app, prefix: "shopping.item.").firstMatch.exists
        XCTAssertTrue(items, "The approved plan produced no list item")
        let noPlan = element(app, "shopping.noPlan").exists
        XCTAssertFalse(noPlan, "The no-plan card shows although the plan is approved")
    }

    @MainActor
    func testBoughtEverythingRemovesCheckedItems() throws {
        let app = launch()
        openListTab(app)
        addItem(app, "Paneer")
        let row = itemRow(app, containing: "Paneer")
        let added = row.waitForExistence(timeout: 10)
        XCTAssertTrue(added, "The manual item did not appear")

        let bought = element(app, "shopping.bought")
        let disabledAtFirst = !bought.isEnabled
        XCTAssertTrue(disabledAtFirst, "Bought everything is enabled with nothing checked")

        row.tap()
        let checkedPredicate = NSPredicate(format: "value == %@", "Checked")
        let checkedWait = expectation(for: checkedPredicate, evaluatedWith: row)
        let checkedResult = XCTWaiter().wait(for: [checkedWait], timeout: 10)
        XCTAssertEqual(checkedResult, .completed, "The item did not become checked")
        let enabled = NSPredicate(format: "isEnabled == true")
        let enabledWait = expectation(for: enabled, evaluatedWith: bought)
        let enabledResult = XCTWaiter().wait(for: [enabledWait], timeout: 10)
        XCTAssertEqual(enabledResult, .completed, "Bought everything stays disabled with a checked item")

        bought.tap()
        let confirm = app.buttons["Add to pantry"]
        let confirmShown = confirm.waitForExistence(timeout: 5)
        XCTAssertTrue(confirmShown, "No Bought everything confirmation")
        confirm.tap()
        let gone = itemRow(app, containing: "Paneer").waitForNonExistence(timeout: 10)
        XCTAssertTrue(gone, "The bought item stays on the list")
    }

    @MainActor
    func testPendingPlanChangesShowBanner() throws {
        let app = launchWithApprovedPlan()
        // Swap one meal: the approved plan gets a draft revision.
        let first = elements(app, prefix: "plan.meal.").firstMatch
        let mealShown = first.waitForExistence(timeout: 10)
        XCTAssertTrue(mealShown, "The plan has no meal rows")
        first.tap()
        let swap = element(app, "meal.swap")
        let swapShown = swap.waitForExistence(timeout: 5)
        XCTAssertTrue(swapShown, "No Swap button on the meal")
        swap.tap()
        let option = elements(app, prefix: "swap.option.").firstMatch
        let offered = option.waitForExistence(timeout: 10)
        XCTAssertTrue(offered, "The swap sheet offers no alternatives")
        option.tap()
        let closed = element(app, "swap.sheet").waitForNonExistence(timeout: 10)
        XCTAssertTrue(closed, "The swap sheet stays open after choosing")

        openListTab(app)
        let banner = element(app, "shopping.pending").waitForExistence(timeout: 10)
        XCTAssertTrue(banner, "No pending-changes banner on the list")
    }

    @MainActor
    func testShareOffersTheListAsText() throws {
        let app = launch()
        openListTab(app)
        addItem(app, "Paneer")
        let added = itemRow(app, containing: "Paneer").waitForExistence(timeout: 10)
        XCTAssertTrue(added, "The manual item did not appear")
        let share = element(app, "shopping.share")
        let shareShown = share.waitForExistence(timeout: 5)
        XCTAssertTrue(shareShown, "No Share button")
        share.tap()
        let activity = app.otherElements["ActivityListView"]
        let copy = app.buttons["Copy"]
        let presented = activity.waitForExistence(timeout: 10) || copy.waitForExistence(timeout: 5)
        XCTAssertTrue(presented, "Share did not present the system share sheet")
    }

    /// Runs the accessibility audit and reports EVERY issue in one run. No exceptions.
    @MainActor
    private func auditAll(_ app: XCUIApplication) {
        ompAuditAll(app)
    }

    @MainActor
    func testNoPlanListPassesAccessibilityAudit() throws {
        let app = launch()
        openListTab(app)
        let card = element(app, "shopping.noPlan").waitForExistence(timeout: 10)
        XCTAssertTrue(card, "No 'Approve your plan' card")
        settle()
        auditAll(app)
    }

    @MainActor
    func testApprovedListPassesAccessibilityAudit() throws {
        let app = launchWithApprovedPlan()
        openListTab(app)
        let items = elements(app, prefix: "shopping.item.").firstMatch.waitForExistence(timeout: 10)
        XCTAssertTrue(items, "The approved plan produced no list item")
        settle()
        auditAll(app)
    }
}
