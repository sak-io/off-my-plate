import UIKit
import XCTest

/// Onboarding and the safety question (task T22; AC-1.1-1.6, AC-2.1-2.6, AC-3.2, AC-3.4).
///
/// Launched with `-OMPUITestSeed empty` (no household: onboarding) or `unasked` (the safety
/// gate cover for two members). Identifiers mirror `AccessibilityID` in
/// OMPFeatures/Onboarding/OnboardingAccessibilityID.swift (this target cannot import it).
final class OnboardingUITests: XCTestCase {
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

    /// Waits for `identifier`, then returns it. Each wait is evaluated before its assertion
    /// (XCUIElement is main-actor isolated; XCTAssert's autoclosure is not).
    @MainActor
    @discardableResult
    private func waitFor(_ app: XCUIApplication, _ identifier: String, timeout: TimeInterval = 15) -> XCUIElement {
        let found = element(app, identifier)
        let exists = found.waitForExistence(timeout: timeout)
        XCTAssertTrue(exists, "\(identifier) did not appear")
        return found
    }

    @MainActor
    private func tap(_ app: XCUIApplication, _ identifier: String) {
        waitFor(app, identifier).tap()
    }

    /// From S-01 (2 adults, 0 children) to the safety question.
    @MainActor
    private func reachSafetyQuestion(_ app: XCUIApplication) {
        waitFor(app, "onboarding.who")
        tap(app, "onboarding.continue")
        waitFor(app, "safety.nobody")
    }

    @MainActor
    private func assertNoWayOut(_ app: XCUIApplication, allowBack: Bool) {
        var labels = ["Close", "Skip", "Cancel", "Dismiss"]
        if !allowBack { labels.append("Back") }
        let wayOut = app.buttons.matching(NSPredicate(format: "label IN %@", labels)).firstMatch.exists
        XCTAssertFalse(wayOut, "The safety question offers a way out")
        app.swipeDown(velocity: .fast)
        let stillShown = element(app, "safety.nobody").waitForExistence(timeout: 2)
        XCTAssertTrue(stillShown, "The safety question was dismissed by a swipe")
    }

    // MARK: S-01

    @MainActor
    func testWhoIsEatingBoundsAndContinue() throws {
        let app = launch(seed: "empty")
        waitFor(app, "onboarding.who")
        let adultsPlus = waitFor(app, "onboarding.adults.plus")
        let childrenPlus = element(app, "onboarding.children.plus")

        // Max: 2 adults + 10 more = 12 people; "+" disables at the cap.
        for _ in 0..<10 { adultsPlus.tap() }
        let adultsPlusEnabled = adultsPlus.isEnabled
        let childrenPlusEnabled = childrenPlus.isEnabled
        XCTAssertFalse(adultsPlusEnabled, "Adults can go past the cap of 12")
        XCTAssertFalse(childrenPlusEnabled, "Children can go past the cap of 12")

        // Invalid: nobody -> Continue disabled.
        let adultsMinus = element(app, "onboarding.adults.minus")
        for _ in 0..<12 { adultsMinus.tap() }
        let continueEnabled = element(app, "onboarding.continue").isEnabled
        XCTAssertFalse(continueEnabled, "Continue is enabled with nobody eating")
    }

    // MARK: S-02

    @MainActor
    func testSafetyQuestionHasNoSkipCloseOrSwipeAway() throws {
        let app = launch(seed: "empty")
        reachSafetyQuestion(app)
        let disclaimerShown = element(app, "disclaimer.C-090").exists
        XCTAssertTrue(disclaimerShown, "The safety disclaimer (C-090) is missing")
        assertNoWayOut(app, allowBack: true)
    }

    @MainActor
    func testNoNobodyLeadsToCuisinesThenPlan() throws {
        let app = launch(seed: "empty")
        reachSafetyQuestion(app)
        tap(app, "safety.nobody")
        waitFor(app, "onboarding.cuisines")
        tap(app, "onboarding.cuisines.skip")
        waitFor(app, "tab.plan.root", timeout: 30)
        let coverShown = element(app, "gate.cover").exists
        XCTAssertFalse(coverShown, "The gate cover shows although everyone answered")
    }

    @MainActor
    func testChipsLeadToCandidateReviewThenExplicitConfirm() throws {
        let app = launch(seed: "empty")
        reachSafetyQuestion(app)
        tap(app, "safety.chip.peanuts")
        waitFor(app, "safety.item.0")
        let nobodyEnabled = element(app, "safety.nobody").isEnabled
        XCTAssertFalse(nobodyEnabled, "'No, nobody' is enabled next to a must-avoid item")

        tap(app, "safety.continue")
        waitFor(app, "safety.summary")
        // Nothing is saved yet: Change goes back to the list with the row kept.
        tap(app, "safety.summary.change")
        waitFor(app, "safety.item.0")
        tap(app, "safety.continue")
        waitFor(app, "safety.summary")
        tap(app, "safety.summary.save")
        waitFor(app, "onboarding.cuisines")
    }

    @MainActor
    func testUnmappedItemForcesPickOrRemove() throws {
        let app = launch(seed: "empty")
        reachSafetyQuestion(app)
        let field = waitFor(app, "safety.text")
        field.tap()
        field.typeText("kiwi\n")
        waitFor(app, "safety.item.0.pick")
        let continueEnabled = element(app, "safety.continue").isEnabled
        XCTAssertFalse(continueEnabled, "Continue is enabled with an unrecognised item")
        let nobodyEnabled = element(app, "safety.nobody").isEnabled
        XCTAssertFalse(nobodyEnabled)
        let hintShown = element(app, "safety.continue.hint").exists
        XCTAssertTrue(hintShown, "The reason Continue is disabled (C-025) is missing")

        // Removing the row clears the block.
        tap(app, "safety.item.0.remove")
        let gone = element(app, "safety.item.0").waitForNonExistence(timeout: 5)
        XCTAssertTrue(gone)
        let nobodyEnabledAgain = element(app, "safety.nobody").isEnabled
        XCTAssertTrue(nobodyEnabledAgain)
    }

    // MARK: Added-member / gate-cover variant (F4)

    @MainActor
    func testAddedMemberVariantAsksOneMemberAtATime() throws {
        let app = launch(seed: "unasked")
        let title = waitFor(app, "gate.cover.title")
        let first = title.label
        XCTAssertTrue(first.contains("Child 1"), "Wrong member: \(first)")
        waitFor(app, "safety.nobody")
        waitFor(app, "safety.removeMember")
        assertNoWayOut(app, allowBack: false)
        let whoShown = element(app, "safety.item.0.who").exists
        XCTAssertFalse(whoShown, "The Who? menu is shown for a single member")

        tap(app, "safety.nobody")
        let second = element(app, "gate.cover.title")
        let predicate = NSPredicate(format: "label CONTAINS %@", "Child 2")
        let asked = expectation(for: predicate, evaluatedWith: second)
        wait(for: [asked], timeout: 10)
        tap(app, "safety.nobody")
        waitFor(app, "tab.plan.root")
        let coverShown = element(app, "gate.cover").waitForNonExistence(timeout: 5)
        XCTAssertTrue(coverShown, "The cover stayed although everyone answered")
    }

    @MainActor
    func testAddedByMistakeRemovesTheMember() throws {
        let app = launch(seed: "unasked")
        waitFor(app, "gate.cover.title")
        tap(app, "safety.removeMember")
        let confirm = app.alerts.buttons["Remove"].firstMatch
        let confirmShown = confirm.waitForExistence(timeout: 5)
        XCTAssertTrue(confirmShown, "The remove confirmation (C-034) did not appear")
        confirm.tap()
        let second = element(app, "gate.cover.title")
        let predicate = NSPredicate(format: "label CONTAINS %@", "Child 2")
        let asked = expectation(for: predicate, evaluatedWith: second)
        wait(for: [asked], timeout: 10)
    }

    // MARK: Accessibility audits

    /// Reports EVERY audit issue in one run, like AppShellUITests.
    @MainActor
    private func auditAll(_ app: XCUIApplication) {
        ompAuditAll(app)
    }

    @MainActor
    func testWhoIsEatingPassesAccessibilityAudit() throws {
        let app = launch(seed: "empty")
        waitFor(app, "onboarding.who")
        auditAll(app)
    }

    @MainActor
    func testSafetyQuestionPassesAccessibilityAudit() throws {
        let app = launch(seed: "empty")
        reachSafetyQuestion(app)
        tap(app, "safety.chip.peanuts")
        waitFor(app, "safety.item.0")
        auditAll(app)
    }

    @MainActor
    func testCuisinesPassAccessibilityAudit() throws {
        let app = launch(seed: "empty")
        reachSafetyQuestion(app)
        tap(app, "safety.nobody")
        waitFor(app, "onboarding.cuisines")
        auditAll(app)
    }
}
