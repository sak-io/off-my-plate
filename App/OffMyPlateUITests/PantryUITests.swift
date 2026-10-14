import UIKit
import XCTest

/// Pantry tab and Mark cooked (task T24): manual add, stale and unrecognised items, the voice
/// confirm card with a fake speech adapter (`-OMPUITestSpeech`), the denied and unavailable
/// variants, the cooked sheet editing the deduction, and an accessibility audit.
///
/// Launch arguments (Debug builds only): `-OMPUITestSeed answered|pantry` (`pantry` stocks salt,
/// oil, curry leaves, rice, stale milk and the unrecognised "masala mix", ids `ui-<ingredient>`)
/// and `-OMPUITestSpeech available|denied|unsupported`. Identifiers mirror `AccessibilityID` in
/// OMPFeatures/Pantry/PantryAccessibilityID.swift (this target cannot import it). Each wait is
/// evaluated before its assertion: XCUIElement is main-actor isolated and XCTAssert's
/// autoclosure is not, under Swift 6 strict concurrency.
final class PantryUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(seed: String = "answered", speech: String = "unsupported") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-OMPUITestSeed", seed, "-OMPUITestSpeech", speech]
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
    private func openPantry(seed: String = "answered", speech: String = "unsupported") -> XCUIApplication {
        let app = launch(seed: seed, speech: speech)
        let planShown = element(app, "tab.plan.root").waitForExistence(timeout: 15)
        XCTAssertTrue(planShown, "The app did not reach the Plan tab")
        tapTab(app, "Pantry")
        let shown = element(app, "tab.pantry.root").waitForExistence(timeout: 5)
        XCTAssertTrue(shown, "The Pantry tab did not open")
        return app
    }

    @MainActor
    private func settle(seconds: TimeInterval = 2) {
        let settle = XCTestExpectation(description: "settle")
        settle.isInverted = true
        _ = XCTWaiter().wait(for: [settle], timeout: seconds)
    }

    // MARK: Manual add

    @MainActor
    func testManualAddShowsTheItemInThePantry() throws {
        let app = openPantry()
        let empty = element(app, "pantry.empty").waitForExistence(timeout: 10)
        XCTAssertTrue(empty, "A new pantry does not show the empty state")

        element(app, "pantry.empty.add").tap()
        let form = element(app, "pantryForm.sheet").waitForExistence(timeout: 5)
        XCTAssertTrue(form, "The add form did not open")
        let save = element(app, "pantryForm.save")
        let saveEnabledEarly = save.isEnabled
        XCTAssertFalse(saveEnabledEarly, "Save is on before a name and an amount are present")

        let name = element(app, "pantryForm.name")
        name.tap()
        name.typeText("Rice")
        let suggestion = element(app, "pantryForm.suggestion.rice")
        let suggested = suggestion.waitForExistence(timeout: 5)
        XCTAssertTrue(suggested, "Typing Rice offers no Rice suggestion")
        suggestion.tap()

        let amount = element(app, "pantryForm.amount")
        amount.tap()
        amount.typeText("2")
        let enabled = NSPredicate(format: "isEnabled == true")
        let ready = expectation(for: enabled, evaluatedWith: save)
        let result = XCTWaiter().wait(for: [ready], timeout: 5)
        XCTAssertEqual(result, .completed, "Save stays off with a name and an amount")
        save.tap()

        let closed = element(app, "pantryForm.sheet").waitForNonExistence(timeout: 10)
        XCTAssertTrue(closed, "The form stays open after saving")
        let row = elements(app, prefix: "pantry.row.").firstMatch
        let rowShown = row.waitForExistence(timeout: 10)
        XCTAssertTrue(rowShown, "The saved item is not in the list")
        let rowLabel = row.label
        XCTAssertTrue(rowLabel.contains("Rice"), "The row does not say Rice: \(rowLabel)")
        let emptyGone = !element(app, "pantry.empty").exists
        XCTAssertTrue(emptyGone, "The empty state stays after adding an item")
    }

    // MARK: Stale and unrecognised items

    @MainActor
    func testStaleAndUnrecognisedItemsAreFlaggedAndStillHaveItClearsStale() throws {
        let app = openPantry(seed: "pantry")
        let stale = element(app, "pantry.stale.ui-milk").waitForExistence(timeout: 10)
        XCTAssertTrue(stale, "The 10-day-old fridge milk is not flagged as not checked in a while")
        let unresolved = element(app, "pantry.unresolved.ui-masala").exists
        XCTAssertTrue(unresolved, "The free-text item is not flagged as not recognised")
        let match = element(app, "pantry.match.ui-masala").exists
        XCTAssertTrue(match, "The free-text item has no Match it button")
        let freshStale = element(app, "pantry.stale.ui-rice").exists
        XCTAssertFalse(freshStale, "A recently confirmed item is flagged stale")

        element(app, "pantry.stillHaveIt.ui-milk").tap()
        let cleared = element(app, "pantry.stale.ui-milk").waitForNonExistence(timeout: 10)
        XCTAssertTrue(cleared, "Still have it does not clear the stale flag")

        element(app, "pantry.match.ui-masala").tap()
        let form = element(app, "pantryForm.sheet").waitForExistence(timeout: 5)
        XCTAssertTrue(form, "Match it did not open the edit form")
        let nameValue = element(app, "pantryForm.name").value as? String ?? ""
        XCTAssertTrue(nameValue.contains("masala mix"), "The form does not start from the typed text: \(nameValue)")
    }

    // MARK: Voice

    @MainActor
    func testVoiceShowsTheConfirmCardAndSavesOnlyAfterConfirming() throws {
        let app = openPantry(speech: "available")
        let empty = element(app, "pantry.empty").waitForExistence(timeout: 10)
        XCTAssertTrue(empty)

        element(app, "pantry.speak").tap()
        let confirm = element(app, "voice.confirm.add").waitForExistence(timeout: 10)
        XCTAssertTrue(confirm, "The confirm card did not appear")
        let first = element(app, "voice.item.0").label
        let second = element(app, "voice.item.1").label
        XCTAssertTrue(first.contains("Rice"), "First item is not rice: \(first)")
        XCTAssertTrue(second.contains("Egg"), "Second item is not eggs: \(second)")

        // Cancel: nothing was saved.
        element(app, "voice.cancel").tap()
        let closed = element(app, "voice.sheet").waitForNonExistence(timeout: 10)
        XCTAssertTrue(closed, "The voice sheet stays open after Cancel")
        let stillEmpty = element(app, "pantry.empty").waitForExistence(timeout: 5)
        XCTAssertTrue(stillEmpty, "Cancelling the voice card saved something")

        element(app, "pantry.speak").tap()
        let again = element(app, "voice.confirm.add").waitForExistence(timeout: 10)
        XCTAssertTrue(again, "The confirm card did not appear the second time")
        element(app, "voice.confirm.add").tap()
        let done = element(app, "voice.sheet").waitForNonExistence(timeout: 10)
        XCTAssertTrue(done, "The voice sheet stays open after confirming")
        let firstRow = elements(app, prefix: "pantry.row.").firstMatch.waitForExistence(timeout: 10)
        XCTAssertTrue(firstRow, "Confirming saved no items")
        let rows = elements(app, prefix: "pantry.row.").count
        XCTAssertEqual(rows, 2, "Expected rice and eggs in the pantry")
    }

    @MainActor
    func testVoiceDeniedExplainsAndOffersTypingInstead() throws {
        let app = openPantry(speech: "denied")
        let empty = element(app, "pantry.empty").waitForExistence(timeout: 10)
        XCTAssertTrue(empty)
        element(app, "pantry.speak").tap()
        let denied = element(app, "voice.denied").waitForExistence(timeout: 10)
        XCTAssertTrue(denied, "No permission-denied explanation (C-134)")
        let settings = element(app, "voice.openSettings").exists
        XCTAssertTrue(settings, "No Open Settings button")
        let typeInstead = element(app, "voice.typeInstead")
        let offered = typeInstead.exists
        XCTAssertTrue(offered, "No Type instead button")
        typeInstead.tap()
        let form = element(app, "pantryForm.sheet").waitForExistence(timeout: 10)
        XCTAssertTrue(form, "Type instead did not open the add form")
    }

    @MainActor
    func testVoiceUnavailableExplainsWithoutSettingsButton() throws {
        let app = openPantry(speech: "unsupported")
        let empty = element(app, "pantry.empty").waitForExistence(timeout: 10)
        XCTAssertTrue(empty)
        element(app, "pantry.empty.speak").tap()
        let unavailable = element(app, "voice.unavailable").waitForExistence(timeout: 10)
        XCTAssertTrue(unavailable, "No voice-unavailable explanation (C-135)")
        let settings = element(app, "voice.openSettings").exists
        XCTAssertFalse(settings, "Open Settings is offered although the device cannot do voice")
        let typeInstead = element(app, "voice.typeInstead").exists
        XCTAssertTrue(typeInstead, "No Type instead button")
    }

    // MARK: Mark cooked

    /// Makes the first plan and approves it, so meals can be marked cooked.
    @MainActor
    private func approvedPlan(_ app: XCUIApplication) {
        let makePlan = element(app, "plan.makePlan")
        let offered = makePlan.waitForExistence(timeout: 20)
        XCTAssertTrue(offered, "The empty Plan tab does not offer Make a plan")
        makePlan.tap()
        let approve = element(app, "plan.approve")
        let drafted = approve.waitForExistence(timeout: 30)
        XCTAssertTrue(drafted, "No draft plan with an Approve week button appeared")
        let draftCooked = elements(app, prefix: "plan.markCooked.").count
        XCTAssertEqual(draftCooked, 0, "Mark cooked is offered on a draft")
        approve.tap()
        let status = element(app, "plan.status")
        let approvedLabel = NSPredicate(format: "label CONTAINS %@", "Approved")
        let done = expectation(for: approvedLabel, evaluatedWith: status)
        let result = XCTWaiter().wait(for: [done], timeout: 20)
        let statusLabel = status.label
        XCTAssertEqual(result, .completed, "The plan did not become approved: \(statusLabel)")
    }

    @MainActor
    func testCookedSheetEditsTheDeductionAndUpdatesThePantry() throws {
        let app = launch(seed: "pantry")
        approvedPlan(app)

        let cook = elements(app, prefix: "plan.markCooked.").firstMatch
        let cookable = cook.waitForExistence(timeout: 10)
        XCTAssertTrue(cookable, "No Mark cooked after approval")
        cook.tap()
        let sheet = element(app, "cooked.sheet").waitForExistence(timeout: 10)
        XCTAssertTrue(sheet, "The cooked sheet did not open")

        // Any stocked ingredient line: the seeded pantry holds salt, oil, curry leaves and rice.
        let edit = elements(app, prefix: "cooked.edit.").firstMatch
        let editable = edit.waitForExistence(timeout: 10)
        XCTAssertTrue(editable, "The cooked sheet has no line that can be edited")
        let ingredient = String(edit.identifier.dropFirst("cooked.edit.".count))
        let amount = element(app, "cooked.amount.\(ingredient)")
        let before = amount.label
        edit.tap()
        let more = element(app, "cooked.more.\(ingredient)")
        let moreShown = more.waitForExistence(timeout: 5)
        XCTAssertTrue(moreShown, "Edit shows no plus button")
        more.tap()
        let after = element(app, "cooked.amount.\(ingredient)").label
        XCTAssertNotEqual(before, after, "Plus did not change the amount to take out")

        element(app, "cooked.update").tap()
        let closed = element(app, "cooked.sheet").waitForNonExistence(timeout: 10)
        XCTAssertTrue(closed, "The cooked sheet stays open after Update pantry")
        let cooked = elements(app, prefix: "plan.cooked.").firstMatch.waitForExistence(timeout: 10)
        XCTAssertTrue(cooked, "The meal is not marked cooked")

        tapTab(app, "Pantry")
        let row = element(app, "pantry.row.ui-\(ingredient)")
        let rowShown = row.waitForExistence(timeout: 10)
        XCTAssertTrue(rowShown, "The \(ingredient) item is missing from the pantry")
        let original = [
            "salt": "100 tsp", "coconut-oil": "100 tbsp", "curry-leaves": "500 g", "rice": "2 kg",
        ][ingredient] ?? "?"
        let changed = NSPredicate(format: "NOT (label CONTAINS %@)", original)
        let wait = expectation(for: changed, evaluatedWith: row)
        let result = XCTWaiter().wait(for: [wait], timeout: 10)
        let rowLabel = row.label
        XCTAssertEqual(result, .completed, "The pantry still says \(original) for \(ingredient): \(rowLabel)")
    }

    // MARK: Accessibility

    /// Runs the accessibility audit and reports EVERY issue in one run. No exceptions.
    @MainActor
    private func auditAll(_ app: XCUIApplication) {
        var found: [String] = []
        // Two passes covering every audit type: one pass over a long list timed out on iPad
        // ("Audit failed to complete in time"), so the work is split, not reduced.
        let visual: XCUIAccessibilityAuditType = [.contrast, .textClipped, .dynamicType]
        let rest = XCUIAccessibilityAuditType.all.subtracting(visual)
        for types in [visual, rest] {
        do {
            try app.performAccessibilityAudit(for: types) { issue in
                let label = issue.element?.label ?? "?"
                let id = issue.element?.identifier ?? ""
                let type = issue.element?.elementType.rawValue ?? 0
                let frame = issue.element?.frame ?? .zero
                let detail = String((issue.element?.debugDescription ?? "").prefix(300))
                found.append(
                    "\(issue.auditType) | \(issue.compactDescription) | label '\(label)' id '\(id)' type \(type) frame \(frame) | \(detail)")
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
    func testPantryListPassesAccessibilityAudit() throws {
        let app = openPantry(seed: "pantry")
        let listed = element(app, "pantry.stale.ui-milk").waitForExistence(timeout: 10)
        XCTAssertTrue(listed, "The stocked pantry did not load")
        // Let the insertion animations finish: the audit measured text mid-transition.
        settle()
        auditAll(app)
    }

    @MainActor
    func testEmptyPantryPassesAccessibilityAudit() throws {
        let app = openPantry()
        let empty = element(app, "pantry.empty").waitForExistence(timeout: 10)
        XCTAssertTrue(empty)
        settle()
        auditAll(app)
    }
}
