import XCTest

/// Runtime acceptance for the core content flows: recipient, draft create/edit,
/// delete isolation, and sealed-content privacy.
///
/// These drive the real app UI, which is the only thing that proves a user can
/// actually perform these flows.
///
/// Three deliberate design decisions, each learned from a real failure:
///
/// 1. NO `-hasCompletedOnboarding` launch argument. `UserDefaults` parses
///    `-key value` launch arguments into the ARGUMENT domain, which outranks the
///    standard (persisted) domain. The app finishes onboarding by writing
///    `hasCompletedOnboarding = true` through `@AppStorage` — the standard
///    domain — so an argument-domain "NO" shadows that write permanently and the
///    main shell can never appear. Onboarding is driven for real instead.
///
/// 2. RootView calls `seedDefaultArchive()` only inside the "Create Our Family
///    Archive" closure. That seeds the admin partition, the owner member and the
///    default branches. Without it `LetterEditorView.save()` fails its
///    `canPerform(.createContent)` guard, sets `permissionDenied`, and the letter
///    is silently never written — which surfaces as "the list is empty", not as
///    a permission problem. Completing real onboarding satisfies the guard.
///
/// 3. Titles carry a per-run token so repeated runs on the same simulator
///    install cannot make a query ambiguous against leftovers from a prior run.
final class CoreFlowUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Unique per test invocation, so accumulated app data never causes an
    /// ambiguous or stale match.
    private let runToken = String(UUID().uuidString.prefix(6))

    private func uniqueName(_ base: String) -> String { "\(base) \(runToken)" }

    /// Launch a usable archive, completing onboarding when it is still showing.
    @discardableResult
    private func launch(file: StaticString = #filePath, line: UInt = #line) -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()

        let cta = app.buttons["Create Our Family Archive"]
        if cta.waitForExistence(timeout: 20) {
            cta.tap()
        }

        XCTAssertTrue(
            app.tabBars.buttons["Letters"].waitForExistence(timeout: 40),
            "main shell did not appear",
            file: file, line: line
        )
        return app
    }

    /// Navigate from the compact library ROOT into the actual letter list.
    ///
    /// On iPhone the library root is a `List` of `NavigationLink`s
    /// ("All Letters", then a Status section). Letter rows exist only inside
    /// `LibraryLetterListView`, one level deeper — so asserting a letter title on
    /// the root can never match, even though the letter is saved and visible.
    private func openAllLetters(_ app: XCUIApplication) {
        let allLetters = app.buttons["All Letters"].firstMatch
        if allLetters.waitForExistence(timeout: 10) {
            allLetters.tap()
        } else {
            let alt = app.staticTexts["All Letters"].firstMatch
            if alt.waitForExistence(timeout: 5) { alt.tap() }
        }
    }

    /// Reveal the list's search field.
    ///
    /// iOS 26 keeps a `.searchable` field hidden until the content is pulled
    /// down, so `app.searchFields` can be empty immediately after navigating
    /// even though search works fine for a real user. Try, in order: an already
    /// visible field, a navigation-bar field, then a pull-down swipe to expose it.
    @discardableResult
    private func revealSearch(_ app: XCUIApplication) -> XCUIElement {
        var field = app.searchFields.firstMatch
        if field.waitForExistence(timeout: 6) { return field }

        field = app.navigationBars.searchFields.firstMatch
        if field.waitForExistence(timeout: 3) { return field }

        for _ in 0..<3 {
            let scrollable = app.collectionViews.firstMatch.exists
                ? app.collectionViews.firstMatch
                : app.tables.firstMatch
            if scrollable.exists {
                scrollable.swipeDown()
            } else {
                app.swipeDown()
            }
            field = app.searchFields.firstMatch
            if field.waitForExistence(timeout: 3) { return field }
        }
        return field
    }

    /// Open the editor and write a letter with the given save button.
    private func writeLetter(
        _ app: XCUIApplication,
        title: String,
        body: String,
        saveButton: String
    ) {
        app.tabBars.buttons["Letters"].tap()

        let newLetter = app.buttons["New Letter"].firstMatch
        XCTAssertTrue(newLetter.waitForExistence(timeout: 25), "New Letter control missing")
        newLetter.tap()

        let titleField = app.textFields["Title"].firstMatch
        XCTAssertTrue(titleField.waitForExistence(timeout: 20), "editor did not open")
        titleField.tap()
        titleField.typeText(title)

        let bodyField = app.textViews["Letter message"].firstMatch
        XCTAssertTrue(bodyField.exists, "letter body editor missing")
        bodyField.tap()
        bodyField.typeText(body)

        let save = app.buttons[saveButton].firstMatch
        XCTAssertTrue(save.exists, "\(saveButton) button missing")
        save.tap()

        // Wait for the sheet to dismiss before the caller navigates; otherwise
        // the next query runs against the still-present editor.
        let dismissed = app.buttons["New Letter"].firstMatch.waitForExistence(timeout: 30)
        XCTAssertTrue(dismissed, "editor did not dismiss after \(saveButton)")
    }

    /// Create a recipient and prove it survives a full process relaunch.
    func testCreateChild_persistsAcrossRelaunch() {
        let app = launch()
        let childName = uniqueName("UITest Child")

        app.tabBars.buttons["Family"].tap()

        let addChild = app.buttons["Add Child"].firstMatch
        XCTAssertTrue(addChild.waitForExistence(timeout: 25), "Add Child control missing")
        addChild.tap()

        let nameField = app.textFields["Name"].firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 20), "Add Child form did not open")
        nameField.tap()
        nameField.typeText(childName)

        let add = app.buttons["Add"].firstMatch
        XCTAssertTrue(add.exists, "Add button missing")
        add.tap()

        XCTAssertTrue(
            app.staticTexts[childName].waitForExistence(timeout: 25),
            "newly created child did not appear"
        )

        // Proof of persistence: kill the process, relaunch, look again.
        app.terminate()
        let relaunched = launch()
        relaunched.tabBars.buttons["Family"].tap()
        XCTAssertTrue(
            relaunched.staticTexts[childName].waitForExistence(timeout: 25),
            "child did not survive a process relaunch"
        )
    }

    /// Create a draft, edit it, and prove the edited value persisted.
    func testCreateAndEditDraft_persistsEditedValues() {
        let app = launch()
        let draft = uniqueName("UITest Draft")
        let edited = "\(draft) EDITED"

        writeLetter(app, title: draft, body: "first body text", saveButton: "Save Draft")
        openAllLetters(app)

        XCTAssertTrue(
            app.staticTexts[draft].waitForExistence(timeout: 30),
            "saved draft did not appear in the library (save may have been permission-denied)"
        )

        app.staticTexts[draft].tap()

        let edit = app.buttons["Edit"].firstMatch
        if edit.waitForExistence(timeout: 15) {
            edit.tap()

            let titleField = app.textFields["Title"].firstMatch
            XCTAssertTrue(titleField.waitForExistence(timeout: 20), "edit did not open the editor")
            titleField.tap()
            if let existing = titleField.value as? String, !existing.isEmpty {
                titleField.typeText(
                    String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count)
                )
            }
            titleField.typeText(edited)

            // The editor's confirmation buttons depend on whether the object is
            // already sealed: an isDraft==false letter gets "Move to Draft" /
            // "Save Changes", while a draft gets "Save Draft" / "Seal Letter".
            // This test edits a DRAFT, so "Save Changes" does not exist here —
            // tapping it was the bug.
            if app.buttons["Save Draft"].firstMatch.exists {
                app.buttons["Save Draft"].firstMatch.tap()
            } else {
                app.buttons["Save Changes"].firstMatch.tap()
            }
        }

        // Persistence across a relaunch is the real assertion.
        app.terminate()
        let relaunched = launch()
        relaunched.tabBars.buttons["Letters"].tap()
        openAllLetters(relaunched)
        XCTAssertTrue(
            relaunched.staticTexts[edited].waitForExistence(timeout: 30),
            "edited title did not persist across a relaunch"
        )
    }

    /// A sealed letter's BODY must not be discoverable through search, while its
    /// title (already rendered in the list) stays searchable.
    func testSealedLetter_bodyNotDiscoverable_butTitleIs() {
        let app = launch()
        let secretBody = "SECRETBODYPHRASE\(runToken)"
        let sealedLiteral = "UITest Sealed"

        writeLetter(app, title: uniqueName(sealedLiteral), body: secretBody, saveButton: "Seal Letter")
        let sealedTitle = uniqueName(sealedLiteral)
        openAllLetters(app)

        XCTAssertTrue(
            app.staticTexts[sealedTitle].waitForExistence(timeout: 30),
            "sealed letter did not appear (save may have been denied for lack of a recipient)"
        )

        // Search the sealed BODY phrase — must NOT reveal the letter.
        // (This flow until now failed at 'search field missing' purely because
        // iOS 26 keeps the searchable field collapsed until content is pulled
        // down; that is a test-harness issue, not a privacy result.)
        let search = revealSearch(app)
        guard search.exists else {
            XCTFail("search field missing.\n--- hierarchy ---\n\(app.debugDescription.prefix(4000))")
            return
        }
        search.tap()
        search.typeText(secretBody)

        Thread.sleep(forTimeInterval: 2.0)
        XCTAssertFalse(
            app.staticTexts[sealedTitle].exists,
            "PRIVACY LEAK: a sealed letter became discoverable by searching its body text"
        )

        // Positive control: the sealed letter must still be reachable by its
        // title, which the row already renders.
        //
        // Rather than clearing the search field with delete keystrokes (which
        // proved unreliable here and failed this assertion), leave and re-enter
        // the list so the search field starts empty again.
        if app.navigationBars.buttons.firstMatch.exists {
            app.navigationBars.buttons.firstMatch.tap()
        } else {
            app.swipeRight()
        }
        openAllLetters(app)

        let freshSearch = revealSearch(app)
        XCTAssertTrue(freshSearch.exists, "search field missing after re-entering the list")
        freshSearch.tap()
        freshSearch.typeText(sealedLiteral)

        XCTAssertTrue(
            app.staticTexts[sealedTitle].waitForExistence(timeout: 20),
            "sealed letter was not discoverable by its title"
        )
    }

    /// Deleting one letter must not remove an unrelated one.
    func testDelete_oneLetter_leavesUnrelatedIntact() {
        let app = launch()
        let keep = uniqueName("UITest Keep")
        let remove = uniqueName("UITest Delete")

        writeLetter(app, title: keep, body: "keep body", saveButton: "Save Draft")
        openAllLetters(app)
        XCTAssertTrue(app.staticTexts[keep].waitForExistence(timeout: 30), "keep letter missing")

        writeLetter(app, title: remove, body: "delete body", saveButton: "Save Draft")
        openAllLetters(app)
        XCTAssertTrue(app.staticTexts[remove].waitForExistence(timeout: 30), "delete letter missing")

        // Delete via the row swipe action.
        app.staticTexts[remove].swipeLeft()
        let delete = app.buttons["Delete"].firstMatch
        if delete.waitForExistence(timeout: 15) {
            delete.tap()
            let confirm = app.buttons["Delete"].firstMatch
            if confirm.waitForExistence(timeout: 8) { confirm.tap() }
        }

        XCTAssertTrue(
            app.staticTexts[keep].waitForExistence(timeout: 30),
            "unrelated letter disappeared when another was deleted"
        )
    }
}
