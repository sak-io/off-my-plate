import XCTest

/// Walking skeleton (task T02): the app launches to the home screen and navigates to the
/// second screen and back. Identifiers mirror `AccessibilityID` in OMPFeatures/RootView.swift.
final class WalkingSkeletonUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsHomeAndNavigatesToSecondScreenAndBack() throws {
        let app = XCUIApplication()
        app.launch()

        // Each wait is evaluated before the assertion: XCUIElement is main-actor isolated
        // and XCTAssert's autoclosure is not, under Swift 6 strict concurrency.
        let homeTitle = app.descendants(matching: .any)["home.title"]
        let homeShown = homeTitle.waitForExistence(timeout: 15)
        XCTAssertTrue(homeShown, "The home screen did not appear after launch")

        let openNext = app.buttons["home.openNext"]
        let openNextShown = openNext.waitForExistence(timeout: 5)
        XCTAssertTrue(openNextShown, "The home screen has no button to the next screen")
        openNext.tap()

        let secondTitle = app.descendants(matching: .any)["second.title"]
        let secondShown = secondTitle.waitForExistence(timeout: 5)
        XCTAssertTrue(secondShown, "Tapping the button did not open the second screen")

        let back = app.navigationBars.buttons.element(boundBy: 0)
        let backShown = back.waitForExistence(timeout: 5)
        XCTAssertTrue(backShown, "The second screen has no back button")
        back.tap()

        let homeShownAgain = homeTitle.waitForExistence(timeout: 5)
        XCTAssertTrue(homeShownAgain, "Back did not return to the home screen")
    }
}
