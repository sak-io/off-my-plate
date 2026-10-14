import UIKit
import XCTest

/// App shell (task T21): tabs, the root safety-gate cover, and an accessibility audit.
///
/// The app is launched with `-OMPUITestSeed <seed>` (Debug builds only): a fresh in-memory
/// store with a known household, so tests never touch real data. Identifiers mirror
/// `AccessibilityID` in OMPFeatures/Shell/AccessibilityID.swift (this target cannot import it).
///
/// Each wait is evaluated before its assertion: XCUIElement is main-actor isolated and
/// XCTAssert's autoclosure is not, under Swift 6 strict concurrency.
final class AppShellUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(seed: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-OMPUITestSeed", seed]
        app.launch()
        return app
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
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
    func testLaunchShowsPlanTabAndSwitchesBetweenAllTabs() throws {
        let app = launch(seed: "answered")

        let planShown = element(app, "tab.plan.root").waitForExistence(timeout: 15)
        XCTAssertTrue(planShown, "The Plan tab is not selected after launch")
        let disclaimerShown = element(app, "disclaimer.C-091").exists
        XCTAssertTrue(disclaimerShown, "The plan disclaimer footer (C-091) is missing")
        let coverShown = element(app, "gate.cover").exists
        XCTAssertFalse(coverShown, "The gate cover shows although everyone answered")

        for (title, identifier) in [
            ("List", "tab.list.root"), ("Pantry", "tab.pantry.root"), ("Household", "tab.household.root"),
            ("Plan", "tab.plan.root"),
        ] {
            tapTab(app, title)
            let shown = element(app, identifier).waitForExistence(timeout: 5)
            XCTAssertTrue(shown, "Tapping \(title) did not show its tab")
        }
    }

    @MainActor
    func testDisclaimerIsReachableFromHousehold() throws {
        let app = launch(seed: "answered")
        let planShown = element(app, "tab.plan.root").waitForExistence(timeout: 15)
        XCTAssertTrue(planShown)

        tapTab(app, "Household")
        let row = element(app, "household.about.disclaimer")
        // The About row sits below the fold on small screens: scroll the list to it.
        var scrolls = 0
        while !(row.exists && row.isHittable) && scrolls < 6 {
            app.swipeUp()
            scrolls += 1
        }
        let rowShown = row.waitForExistence(timeout: 5)
        XCTAssertTrue(rowShown, "Household has no row for the medical disclaimer (AC-2.6)")
        row.tap()
        let noteShown = element(app, "disclaimer.C-092").waitForExistence(timeout: 5)
        XCTAssertTrue(noteShown, "The full disclaimer (C-092) did not open")
    }

    @MainActor
    func testGateCoverShowsWhenAMemberIsUnaskedAndCannotBeSwipedAway() throws {
        let app = launch(seed: "unasked")

        let title = element(app, "gate.cover.title")
        let titleShown = title.waitForExistence(timeout: 15)
        XCTAssertTrue(titleShown, "The safety gate cover did not show for an unasked member")
        let label = title.label
        XCTAssertTrue(label.contains("Child 1"), "The cover asks about the wrong member: \(label)")
        let progress = element(app, "gate.cover.progress").label
        XCTAssertEqual(progress, "1 of 2")
        let disclaimerShown = element(app, "disclaimer.C-090").exists
        XCTAssertTrue(disclaimerShown, "The safety disclaimer (C-090) is missing on the cover")

        // No close, skip or back, and a downward swipe must not dismiss it.
        let closeExists = app.buttons.matching(NSPredicate(format: "label IN %@", ["Close", "Skip", "Back", "Cancel"]))
            .firstMatch.exists
        XCTAssertFalse(closeExists, "The gate cover offers a way out")
        app.swipeDown(velocity: .fast)
        let stillShown = title.waitForExistence(timeout: 2)
        XCTAssertTrue(stillShown, "The gate cover was dismissed by a swipe")
    }

    /// Runs the accessibility audit and reports EVERY issue in one run (the plain call stops at
    /// the first, which costs one CI cycle per issue). Fails if any issue is not ignored.
    /// The only ignores in use are the owner-approved Dynamic Type exceptions (tracked for T28):
    /// the system "Plan" label, and on iPad the element-less Dynamic Type issues that the
    /// system tab bar / sidebar items raise (one per tab). Every other audit type still fails.
    @MainActor
    private func auditAll(_ app: XCUIApplication, ignoreDynamicTypeOnPlanLabel: Bool = false) {
        var found: [String] = []
        do {
            try app.performAccessibilityAudit { issue in
                let ignored = ignoreDynamicTypeOnPlanLabel && issue.auditType == .dynamicType
                    && issue.element?.label == "Plan"
                let ipadChrome = UIDevice.current.userInterfaceIdiom == .pad && ignoreDynamicTypeOnPlanLabel
                    && issue.auditType == .dynamicType && issue.element == nil
                if !ignored && !ipadChrome {
                    let label = issue.element?.label ?? "?"
                    let id = issue.element?.identifier ?? ""
                    let kind = issue.element?.elementType.rawValue ?? 0
                    let frame = issue.element?.frame ?? .zero
                    let debug = String((issue.element?.debugDescription ?? "").prefix(300))
                    found.append(
                        "\(issue.auditType) | \(issue.compactDescription) | label '\(label)' id '\(id)' type \(kind) frame \(frame) \(debug)")
                }
                return true
            }
        } catch {
            found.append("audit threw: \(error)")
        }
        XCTAssertTrue(found.isEmpty, "Accessibility audit issues (\(found.count)):\n" + found.joined(separator: "\n"))
    }

    @MainActor
    func testShellPassesAccessibilityAudit() throws {
        let app = launch(seed: "answered")
        let planShown = element(app, "tab.plan.root").waitForExistence(timeout: 15)
        XCTAssertTrue(planShown)
        auditAll(app, ignoreDynamicTypeOnPlanLabel: true)
    }

    @MainActor
    func testGateCoverPassesAccessibilityAudit() throws {
        let app = launch(seed: "unasked")
        let titleShown = element(app, "gate.cover.title").waitForExistence(timeout: 15)
        XCTAssertTrue(titleShown)
        auditAll(app)
    }
}
