import XCTest

/// Household tab, learning and delete-all (task T27): the reflect-back card (three answers),
/// What I've learned (Forget, edit stays soft), add a person (gate), allergies add/remove,
/// the 180-day card, Delete all data -> onboarding, and accessibility audits.
///
/// Seeds (`-OMPUITestSeed`, Debug builds only): `answered`, `learned` (soft facts and three
/// weekday re-rolls that propose a reflect-back card) and `stale` (answered 200 days ago).
/// Identifiers mirror `AccessibilityID` in OMPFeatures/Settings/SettingsAccessibilityID.swift
/// (this target cannot import it). Each wait is evaluated before its assertion: XCUIElement is
/// main-actor isolated and XCTAssert's autoclosure is not, under Swift 6 strict concurrency.
final class SettingsUITests: XCTestCase {
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

    @MainActor
    private func elements(_ app: XCUIApplication, prefix: String) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
    }

    /// Waits for `identifier`, then taps it.
    @MainActor
    private func tap(_ app: XCUIApplication, _ identifier: String, timeout: TimeInterval = 10) {
        let target = element(app, identifier)
        let shown = target.waitForExistence(timeout: timeout)
        XCTAssertTrue(shown, "Nothing with identifier \(identifier)")
        target.tap()
    }

    /// Scrolls a list until `identifier` can be tapped, then taps it.
    @MainActor
    private func scrollAndTap(_ app: XCUIApplication, _ identifier: String) {
        let target = element(app, identifier)
        var tries = 0
        while !(target.exists && target.isHittable) && tries < 8 {
            app.swipeUp()
            tries += 1
        }
        let reachable = target.exists && target.isHittable
        XCTAssertTrue(reachable, "Could not scroll to \(identifier)")
        target.tap()
    }

    @MainActor
    private func waitFor(_ app: XCUIApplication, _ identifier: String, timeout: TimeInterval = 10) {
        let shown = element(app, identifier).waitForExistence(timeout: timeout)
        XCTAssertTrue(shown, "Nothing with identifier \(identifier) appeared")
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
    private func openHousehold(_ app: XCUIApplication) {
        waitFor(app, "tab.plan.root", timeout: 20)
        tapTab(app, "Household")
        waitFor(app, "tab.household.root")
    }

    @MainActor
    private func settle() {
        let wait = XCTestExpectation(description: "settle")
        wait.isInverted = true
        _ = XCTWaiter().wait(for: [wait], timeout: 2)
    }

    // MARK: Reflect-back card (AC-12.2, AC-12.3)

    @MainActor
    private func answerReflectBack(button: String, message: String) {
        let app = launch(seed: "learned")
        waitFor(app, "reflect.card", timeout: 20)
        tap(app, button)
        let gone = element(app, "reflect.card").waitForNonExistence(timeout: 10)
        XCTAssertTrue(gone, "The card stays after answering")
        let toast = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", message)).firstMatch
        let announced = toast.waitForExistence(timeout: 5)
        XCTAssertTrue(announced, "No confirmation containing '\(message)'")
    }

    @MainActor
    func testReflectBackYes() throws {
        answerReflectBack(button: "reflect.yes", message: "Got it")
    }

    @MainActor
    func testReflectBackNotReally() throws {
        answerReflectBack(button: "reflect.no", message: "I won't plan around that")
    }

    @MainActor
    func testReflectBackDontAskAgain() throws {
        answerReflectBack(button: "reflect.never", message: "I won't ask about this again")
    }

    // MARK: What I've learned (AC-12.5)

    @MainActor
    private func openLearned(_ app: XCUIApplication) {
        openHousehold(app)
        scrollAndTap(app, "household.learned")
        waitFor(app, "learned.root")
        waitFor(app, "learned.row.0")
    }

    @MainActor
    func testForgetRemovesAFact() throws {
        let app = launch(seed: "learned")
        // The Plan tab stores the proposed fourth fact on launch; wait for it so the count
        // taken below does not change under the test.
        waitFor(app, "reflect.card", timeout: 20)
        openLearned(app)
        // Rows below the fold are not in the accessibility tree, so counting rows is unreliable:
        // check that the forgotten fact's own text is gone instead.
        let first = element(app, "learned.row.0")
        let firstShown = first.waitForExistence(timeout: 10)
        XCTAssertTrue(firstShown, "The learned list is missing seeded facts")
        let forgottenText = first.label
        XCTAssertFalse(forgottenText.isEmpty)

        tap(app, "learned.row.0")
        waitFor(app, "fact.sheet")
        tap(app, "fact.forget")
        let confirm = app.alerts.buttons["Forget"]
        let asked = confirm.waitForExistence(timeout: 5)
        XCTAssertTrue(asked, "No Forget confirmation (C-154)")
        confirm.tap()

        waitFor(app, "learned.root")
        let stillThere = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'learned.row.' AND label == %@", forgottenText)).firstMatch
        let gone = stillThere.waitForNonExistence(timeout: 10)
        XCTAssertTrue(gone, "The forgotten fact is still listed: \(forgottenText)")
    }

    @MainActor
    func testEditingAFactKeepsItSoft() throws {
        let app = launch(seed: "learned")
        // The Plan tab proposes the noticed fact on launch (it is stored then).
        waitFor(app, "reflect.card", timeout: 20)
        openLearned(app)
        // Rows: told, confirmed, noticed (the proposed "quick weekday" fact), starting guess.
        tap(app, "learned.row.2")
        waitFor(app, "fact.sheet")
        let origin = element(app, "fact.origin").label
        XCTAssertTrue(origin.contains("noticed"), "Unexpected origin: \(origin)")

        // The footer only POINTS to the allergies screen; no control offers a hard restriction.
        let hardButtons = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'never' OR label CONTAINS[c] 'allerg'"))
        XCTAssertEqual(hardButtons.count, 0, "The fact sheet offers a hard restriction")

        tap(app, "fact.save")
        waitFor(app, "learned.root")
        // Saved facts become 'You told me': stated, now listed with the first section.
        tap(app, "learned.row.1")
        waitFor(app, "fact.sheet")
        let saved = element(app, "fact.origin").label
        XCTAssertTrue(saved.contains("You said this"), "The edited fact is not stated: \(saved)")
    }

    // MARK: Household (AC-16.1, AC-3.2)

    @MainActor
    func testAddingAPersonOpensTheSafetyQuestion() throws {
        let app = launch(seed: "answered")
        openHousehold(app)
        tap(app, "household.addPerson")
        let name = element(app, "person.name")
        let nameShown = name.waitForExistence(timeout: 5)
        XCTAssertTrue(nameShown, "The add-person form did not open")
        name.tap()
        name.typeText("Asha")
        tap(app, "person.save")

        let title = element(app, "gate.cover.title")
        let covered = title.waitForExistence(timeout: 15)
        XCTAssertTrue(covered, "The safety question did not open for the new person")
        let label = title.label
        XCTAssertTrue(label.contains("Asha"), "The cover asks about the wrong person: \(label)")
    }

    @MainActor
    func testAddAndRemoveAnAvoidedFood() throws {
        let app = launch(seed: "answered")
        openHousehold(app)
        tap(app, "household.allergies")
        waitFor(app, "rules.root")
        let emptyShown = element(app, "rules.empty").exists
        XCTAssertTrue(emptyShown, "Nobody avoids anything yet, so C-037 should show")

        tap(app, "rules.add")
        waitFor(app, "rules.add.sheet")
        tap(app, "rules.add.chip.peanuts")
        tap(app, "rules.add.continue")
        waitFor(app, "rules.add.summary")
        // Nothing is saved until the explicit confirmation.
        tap(app, "rules.add.save")
        waitFor(app, "rules.row.0")

        tap(app, "rules.remove.0")
        let confirm = app.alerts.buttons["Remove"]
        let asked = confirm.waitForExistence(timeout: 5)
        XCTAssertTrue(asked, "No remove confirmation (C-036)")
        confirm.tap()
        let gone = element(app, "rules.row.0").waitForNonExistence(timeout: 10)
        XCTAssertTrue(gone, "The rule is still listed after confirming the removal")
    }

    @MainActor
    func testStillCorrectCardReconfirms() throws {
        let app = launch(seed: "stale")
        waitFor(app, "reconfirm.card", timeout: 20)
        tap(app, "reconfirm.yes")
        let gone = element(app, "reconfirm.card").waitForNonExistence(timeout: 10)
        XCTAssertTrue(gone, "The Still correct? card stays after Yes")
    }

    // MARK: Delete all data (AC-16.2)

    @MainActor
    func testDeleteAllDataRestartsOnboarding() throws {
        let app = launch(seed: "answered")
        openHousehold(app)
        scrollAndTap(app, "household.deleteAll")
        let confirm = app.alerts.buttons["Delete everything"]
        let asked = confirm.waitForExistence(timeout: 5)
        XCTAssertTrue(asked, "No delete confirmation (C-161)")
        // Cancelling keeps everything.
        app.alerts.buttons["Cancel"].tap()
        let stillThere = element(app, "household.deleteAll").exists
        XCTAssertTrue(stillThere, "Cancel left the Household tab")

        scrollAndTap(app, "household.deleteAll")
        let again = app.alerts.buttons["Delete everything"]
        let askedAgain = again.waitForExistence(timeout: 5)
        XCTAssertTrue(askedAgain)
        again.tap()
        waitFor(app, "onboarding.who", timeout: 20)
    }

    // MARK: Accessibility audits

    /// Runs the accessibility audit in two passes covering every audit type (one pass over a
    /// long screen timed out on iPad) and reports EVERY issue in one run. Exceptions live only in AccessibilityAudit.swift.
    @MainActor
    private func auditAll(_ app: XCUIApplication) {
        settle()
        ompAuditAll(app, knownIssue: "T28 (owner waiver 2026-10-14): audit findings on this screen are tracked in .autocraft/work/tracked.md")
    }

    @MainActor
    func testHouseholdPassesAccessibilityAudit() throws {
        let app = launch(seed: "answered")
        openHousehold(app)
        auditAll(app)
    }

    @MainActor
    func testWhatIveLearnedPassesAccessibilityAudit() throws {
        let app = launch(seed: "learned")
        openLearned(app)
        auditAll(app)
    }

    @MainActor
    func testAllergiesScreenAndAddSheetPassAccessibilityAudit() throws {
        let app = launch(seed: "answered")
        openHousehold(app)
        tap(app, "household.allergies")
        waitFor(app, "rules.root")
        auditAll(app)
        tap(app, "rules.add")
        waitFor(app, "rules.add.sheet")
        tap(app, "rules.add.chip.peanuts")
        auditAll(app)
    }

    @MainActor
    func testAboutPassesAccessibilityAudit() throws {
        let app = launch(seed: "answered")
        openHousehold(app)
        scrollAndTap(app, "household.about.disclaimer")
        waitFor(app, "about.root")
        auditAll(app)
    }
}
