import XCTest

/// §22–§24: iPad split-view / navigation runtime gate.
///
/// A focused FORM-FACTOR smoke test, not a second backup journey. `LibraryView`
/// is the app's own `NavigationSplitView` (guarded by `horizontalSizeClass`),
/// and this project has historically had compact-selection deadlocks there, so
/// the point is selection behaviour across the presentations the device can
/// actually reach.
///
/// MEASURED FORM-FACTOR CONTRACT (iPad Pro 13-inch M5 / iOS 26.2; full tree in
/// `evidence/ipad-hierarchy-probe.txt`):
///   * `tabBars.count == 0` — on regular-width iPad the five `TabView`
///     destinations render as a top-edge segmented control of plain `Button`s.
///     Any test that waits for `tabBars["Letters"]` on iPad can never pass.
///   * `LibraryView` renders a real `NavigationSplitView`: sidebar
///     `CollectionView` labelled "Sidebar" with an "All Letters" `Cell`, a
///     content column titled "All Letters", and a detail pane that shows
///     "Select a Letter" until something is selected.
///   * `app.cells` spans BOTH columns, so `cells.firstMatch` is the sidebar's
///     "All Letters" row, not a letter. Every selection below therefore targets
///     the cell containing a specific letter title.
///   * the shell never reaches COMPACT width on a full-screen iPad of this
///     size (portrait on a 13-inch iPad is still regular width), so rotation
///     cannot produce the collapsed stack path. The compact stack is covered
///     by `CoreFlowUITests` on iPhone instead of being faked here.
///
/// Requires a live SelfHostedSync server config so the Letters list has the
/// same content the other suites create; it does not perform a backup.
final class IPadSplitViewUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        print("IPAD start form-factor split-view gate")
    }

    // MARK: - per-test identity

    /// XCTest builds a fresh instance per test method, so each test's letters
    /// are uniquely named and the tests never depend on each other's data.
    private let tag = String(UUID().uuidString.prefix(5)).uppercased()
    private var firstTitle: String { "IPAD-\(tag)-A" }
    private var secondTitle: String { "IPAD-\(tag)-B" }
    /// Bodies are rendered ONLY by the detail pane (a list row shows the title
    /// and the schedule summary, never the body), so matching a body is a
    /// genuine proof that the detail followed the selection.
    private var firstBody: String { "ipad-a-body-\(tag.lowercased())" }
    private var secondBody: String { "ipad-b-body-\(tag.lowercased())" }

    // MARK: - local helpers

    /// The list row for a specific letter. Never `cells.firstMatch`: in a split
    /// view that is a sidebar row.
    private func letterCell(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        app.cells
            .containing(NSPredicate(format: "label CONTAINS %@", title))
            .firstMatch
    }

    /// Open the library's "All Letters" destination.
    ///
    /// In a split view the sidebar row is a `Cell` whose child is a
    /// `StaticText`; on iPhone the same destination is a pushed `Button`/link.
    /// Match both, preferring the tappable cell.
    private func openAllLetters(_ app: XCUIApplication) {
        let cell = letterCell(app, "All Letters")
        if cell.waitForExistence(timeout: 12), cell.isHittable {
            cell.tap()
            Thread.sleep(forTimeInterval: 1.2)
            return
        }
        let text = app.staticTexts["All Letters"].firstMatch
        if text.waitForExistence(timeout: 6) {
            text.tap()
            Thread.sleep(forTimeInterval: 1.0)
        }
    }

    /// Write a letter through the real editor and save it as a draft.
    private func write(_ app: XCUIApplication, title: String, body: String) {
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
        ltmDismissKeyboard(app)

        let save = app.buttons["Save Draft"].firstMatch
        XCTAssertTrue(save.exists, "'Save Draft' missing")
        save.tap()
        XCTAssertTrue(app.buttons["New Letter"].firstMatch.waitForExistence(timeout: 30),
                      "editor did not dismiss after saving")
        Thread.sleep(forTimeInterval: 1.2)
    }

    /// Create `title` in the Letters destination and select its row.
    private func createAndSelect(_ app: XCUIApplication, title: String, body: String) {
        ltmOpenDestination(app, "Letters")
        openAllLetters(app)
        write(app, title: title, body: body)
        openAllLetters(app)
        let row = letterCell(app, title)
        XCTAssertTrue(row.waitForExistence(timeout: 25), "letter '\(title)' is not listed")
        row.tap()
        Thread.sleep(forTimeInterval: 1.5)
    }

    // MARK: - §22 split-view navigation and selection

    func testSplitViewNavigationAndSelection() {
        let app = ltmLaunch(XCUIApplication())
        print("IPAD launched usesTabBar=\(ltmUsesTabBar(app)) navBars=\(app.navigationBars.count) cells=\(app.cells.count)")

        // ---- Letters destination reachable (tab on iPhone, segmented button on iPad)
        ltmOpenDestination(app, "Letters")
        Thread.sleep(forTimeInterval: 1.2)
        XCTAssertTrue(app.navigationBars["Letters"].waitForExistence(timeout: 25),
                      "the Letters destination rendered no navigation chrome")

        openAllLetters(app)
        let hasList = app.cells.count > 0
            || ltmWaitForText(app, "New Letter", timeout: 15)
            || ltmWaitForText(app, "No Letters Yet", timeout: 5)
        XCTAssertTrue(hasList, "the Letters destination did not render a usable list")

        // ---- two letters so selection has something distinct to switch between
        write(app, title: firstTitle, body: firstBody)
        openAllLetters(app)
        write(app, title: secondTitle, body: secondBody)
        openAllLetters(app)

        XCTAssertTrue(ltmWaitForText(app, firstTitle, timeout: 25),
                      "first iPad letter not listed")
        XCTAssertTrue(ltmWaitForText(app, secondTitle, timeout: 25),
                      "second iPad letter not listed")

        // ---- select A: the DETAIL pane must render A's body
        let rowA = letterCell(app, firstTitle)
        XCTAssertTrue(rowA.waitForExistence(timeout: 20), "no list row for letter A")
        rowA.tap()
        XCTAssertTrue(ltmWaitForText(app, firstBody, timeout: 25),
                      "selecting letter A did not render its detail")
        print("IPAD selected A; detail rendered")

        // ---- select B: the detail must FOLLOW, and A must no longer be shown
        let rowB = letterCell(app, secondTitle)
        XCTAssertTrue(rowB.waitForExistence(timeout: 20), "no list row for letter B")
        rowB.tap()
        XCTAssertTrue(ltmWaitForText(app, secondBody, timeout: 25),
                      "selecting letter B did not render its detail")
        let afterSelect = ltmTexts(of: app)
        XCTAssertFalse(afterSelect.contains(firstBody),
                       "the detail went stale: letter A's body is still shown after selecting B")
        print("IPAD selected B; detail changed, no stale detail")

        // ---- switch major section and come back
        var sections: [String: Bool] = [:]
        for name in ["Timeline", "Family", "People", "Settings", "Letters"] {
            ltmOpenDestination(app, name)
            Thread.sleep(forTimeInterval: 1.2)
            sections[name] = ltmDestinationElement(app, name)?.isSelected ?? false
        }
        print("IPAD sections=\(sections)")
        XCTAssertTrue(sections.values.allSatisfy { $0 },
                      "a major destination never became selected on iPad: \(sections)")

        // Returning to Letters must leave a usable library, not a blank pane.
        openAllLetters(app)
        XCTAssertTrue(ltmWaitForText(app, firstTitle, timeout: 25),
                      "the library did not come back after the destination round trip")
        print("IPAD destination round trip ok; library usable")
    }

    // MARK: - §23 rotation

    /// The split view must stay usable across a rotation cycle and keep
    /// working selection. iPad supports all four orientations
    /// (`UISupportedInterfaceOrientations~ipad`), so this is a real check.
    func testRotationKeepsSplitViewUsable() {
        let app = ltmLaunch(XCUIApplication())
        createAndSelect(app, title: firstTitle, body: firstBody)
        XCTAssertTrue(ltmWaitForText(app, firstBody, timeout: 25),
                      "the detail was not rendering before the rotation")

        let before = app.navigationBars.count
        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 3.0)
        print("IPAD landscape navBars=\(before) -> \(app.navigationBars.count)")
        XCTAssertTrue(ltmDestinationElement(app, "Letters") != nil,
                      "the Letters destination disappeared after rotating to landscape")
        XCTAssertTrue(app.buttons["New Letter"].firstMatch.exists || app.cells.count > 0,
                      "no usable content after rotating to landscape")

        XCUIDevice.shared.orientation = .portrait
        Thread.sleep(forTimeInterval: 3.0)
        print("IPAD portrait navBars=\(app.navigationBars.count)")
        XCTAssertTrue(ltmDestinationElement(app, "Letters") != nil,
                      "the Letters destination disappeared after rotating back to portrait")

        // Selection must not deadlock after a rotation cycle.
        openAllLetters(app)
        let row = letterCell(app, firstTitle)
        XCTAssertTrue(row.waitForExistence(timeout: 20),
                      "the letter row vanished after the rotation cycle")
        row.tap()
        XCTAssertTrue(ltmWaitForText(app, firstBody, timeout: 25),
                      "selection after rotation did not render the detail")
        print("IPAD post-rotation selection ok")
        XCTAssertTrue(app.state == .runningForeground, "app left the foreground after rotation")
    }

    // MARK: - §24 narrowest presentation available

    /// COMPACT WIDTH IS NOT REACHABLE ON THIS DEVICE, and this test does not
    /// pretend otherwise. A full-screen 13-inch iPad in portrait is still
    /// regular width, so `LibraryView.splitBody` stays in effect and rotation
    /// cannot collapse the split; there is no Slide Over window available to a
    /// UI test either. The genuine collapsed-stack path (push, pop, no stale
    /// detail) is exercised by `CoreFlowUITests` on iPhone.
    ///
    /// What is verified here is the equivalent contract for the narrowest
    /// presentation the device can produce: the list stays reachable, a
    /// selection renders detail, and a SECOND selection replaces it without
    /// leaving a stale detail — the compact-selection deadlock this project has
    /// hit before.
    func testCompactWidthNavigation() {
        let app = ltmLaunch(XCUIApplication())

        XCUIDevice.shared.orientation = .portrait
        Thread.sleep(forTimeInterval: 2.5)

        let windowWidth = app.windows.firstMatch.frame.width
        print("IPAD narrowest windowWidth=\(windowWidth) (a full-screen 13-inch iPad stays regular width)")

        createAndSelect(app, title: firstTitle, body: firstBody)
        XCTAssertTrue(ltmWaitForText(app, firstBody, timeout: 25),
                      "the narrowest presentation did not render the selected detail")
        print("IPAD narrow first selection rendered detail")

        // A second selection must work after the round trip: no stale detail.
        ltmOpenDestination(app, "Letters")
        openAllLetters(app)
        write(app, title: secondTitle, body: secondBody)
        openAllLetters(app)

        let rowA = letterCell(app, firstTitle)
        XCTAssertTrue(rowA.waitForExistence(timeout: 20), "letter A row missing")
        rowA.tap()
        XCTAssertTrue(ltmWaitForText(app, firstBody, timeout: 25),
                      "selecting letter A did not render its detail")

        let rowB = letterCell(app, secondTitle)
        XCTAssertTrue(rowB.waitForExistence(timeout: 20), "letter B row missing")
        rowB.tap()
        XCTAssertTrue(ltmWaitForText(app, secondBody, timeout: 25),
                      "the second selection did not render its detail")
        XCTAssertFalse(ltmTexts(of: app).contains(firstBody),
                       "a second selection left the previous letter's detail on screen")
        print("IPAD narrow second selection changed the detail, no stale detail")

        XCTAssertTrue(app.state == .runningForeground,
                      "app left the foreground during narrow-presentation navigation")
    }
}
