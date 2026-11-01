import UIKit
import XCTest

/// Task T28: AC-13.2 (no network requests) and the cold-start number (NFR).
///
/// The Debug app takes `-OMPUITestDenyNetwork`: it registers a URLProtocol that records and fails
/// every URL request, and shows the count as the accessibility element `debug.networkAttempts`
/// (label `net:<count>`). The lint `scripts/lint-no-network.sh` keeps network code out of the
/// sources; this is the runtime evidence across the main flows. Each wait is evaluated before its
/// assertion: XCUIElement is main-actor isolated and XCTAssert's autoclosure is not, under Swift 6.
final class OfflineAndPerformanceUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    private func pause(_ seconds: TimeInterval) {
        let pause = XCTestExpectation(description: "pause")
        pause.isInverted = true
        _ = XCTWaiter().wait(for: [pause], timeout: seconds)
    }

    /// Same approach as AppShellUITests: tab bar button on iPhone; button or cell on iPad.
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
    func testMainFlowsMakeNoNetworkRequests() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-OMPUITestSeed", "answered", "-OMPUITestDenyNetwork"]
        app.launch()

        // The probe must be installed, or "zero" would prove nothing.
        let counter = element(app, "debug.networkAttempts")
        let probeShown = counter.waitForExistence(timeout: 20)
        XCTAssertTrue(probeShown, "The network-denial probe is not installed (DEBUG build with -OMPUITestDenyNetwork?)")

        // Plan: make the first plan.
        let makePlan = element(app, "plan.makePlan")
        let offered = makePlan.waitForExistence(timeout: 20)
        XCTAssertTrue(offered, "The empty Plan tab does not offer Make a plan")
        makePlan.tap()
        let drafted = element(app, "plan.approve").waitForExistence(timeout: 30)
        XCTAssertTrue(drafted, "No draft plan appeared")

        // The other tabs.
        for (title, identifier) in [
            ("List", "tab.list.root"), ("Pantry", "tab.pantry.root"), ("Household", "tab.household.root"),
            ("Plan", "tab.plan.root"),
        ] {
            tapTab(app, title)
            let shown = element(app, identifier).waitForExistence(timeout: 10)
            XCTAssertTrue(shown, "Tapping \(title) did not show its tab")
        }

        // The counter refreshes every 0.5 s: let it catch up before reading.
        pause(2)
        XCTAssertEqual(counter.label, "net:0", "The app attempted network requests")
    }

    /// Cold start (NFR: < 1.5 s on iPhone 12-class). Shared CI simulators are far too noisy for a
    /// hard threshold, so this RECORDS the number: the XCTest log prints the launch time per
    /// iteration and its average, and the xcresult carries the metric.
    @MainActor
    func testColdLaunchTimeIsRecorded() throws {
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTApplicationLaunchMetric()], options: options) {
            let app = XCUIApplication()
            app.launchArguments = ["-OMPUITestSeed", "answered"]
            app.launch()
            app.terminate()
        }
    }

    /// Time from process launch until the Plan tab is on screen, logged (no threshold).
    @MainActor
    func testLaunchToInteractiveIsLogged() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-OMPUITestSeed", "answered"]
        let clock = ContinuousClock()
        let start = clock.now
        app.launch()
        let ready = element(app, "plan.makePlan").waitForExistence(timeout: 30)
        let elapsed = clock.now - start
        XCTAssertTrue(ready, "The Plan tab was not interactive after launch")
        let note = "Launch to interactive (Plan tab ready): \(elapsed) (NFR budget 1.5 s on iPhone 12-class; CI is not a threshold)"
        print(note)
        let attachment = XCTAttachment(string: note)
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
