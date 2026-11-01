import XCTest

/// Notes import (task T26, flow F10): the app drains the Share Extension's inbox when it
/// launches and shows toast C-111. The real App Group is not available in CI simulators
/// (unsigned builds), so the Debug app takes `-OMPUITestInbox twoItems`, which drops an inbox
/// file with two items into a temporary folder and drains that (see `UITestInbox` in
/// App/OffMyPlate/CompositionRoot.swift). The merge itself is covered by `ImportServiceTests`
/// (Core) and `ImportDrainTests` (OMPFeatures); the Share Extension screen cannot be driven
/// from here (a separate process), its model is covered by `OMPShareTests`.
///
/// The toast hides itself after 4 s, so it is not part of an accessibility audit: the audit
/// helper needs longer than that.
final class ImportUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-OMPUITestSeed", "answered"] + arguments
        app.launch()
        return app
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    func testDroppedInboxFileIsMergedAndAnnounced() throws {
        let app = launch(arguments: ["-OMPUITestInbox", "twoItems"])

        let toast = element(app, "toast")
        let shown = toast.waitForExistence(timeout: 20)
        XCTAssertTrue(shown, "No toast after the inbox file was dropped")
        let label = toast.label
        XCTAssertEqual(label, "Added 2 items from Notes.")
    }

    @MainActor
    func testNoInboxFixtureShowsNoToast() throws {
        let app = launch(arguments: [])

        let planShown = element(app, "tab.plan.root").waitForExistence(timeout: 15)
        XCTAssertTrue(planShown, "The Plan tab is not shown after launch")
        let settle = XCTestExpectation(description: "settle")
        settle.isInverted = true
        _ = XCTWaiter().wait(for: [settle], timeout: 2)
        let toastShown = element(app, "toast").exists
        XCTAssertFalse(toastShown, "A toast appeared although nothing was imported")
    }
}
