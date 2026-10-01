import XCTest

/// Shared interaction support for the SelfHosted / backup UI suites.
///
/// Every helper here encodes a MEASURED XCTest behaviour that produced a false
/// "product" failure at least once during this audit. They live in one place so
/// the suites cannot drift apart and re-learn the same lessons:
///
///  * a SwiftUI `Form` `Toggle` is ONE row-wide accessibility element, so
///    `element.tap()` lands on the label and does NOT flip the switch — tap the
///    trailing control position and read the value back;
///  * the connection-status row uses `.accessibilityElement(children: .combine)`,
///    so a state is never a bare `staticTexts["..."]` — match with CONTAINS;
///  * an EMPTY SwiftUI `TextField`/`SecureField` reports its PLACEHOLDER as
///    `value` ("Token", length 5) — normalise before treating it as content;
///  * iOS 26 PRESERVES each tab's navigation stack, so re-tapping Settings lands
///    back on the pushed screen and `navigationBars["Settings"]` never appears;
///  * the accessibility tree contains only ON-SCREEN elements, so scroll to a
///    settled position before querying, and never tap a coordinate while the
///    scroll is still animating (it lands on the navigation bar instead).
extension XCTestCase {

    // MARK: - server configuration (environment-driven; never committed)

    /// Server URL. A loopback default is a legitimate test default; a LAN
    /// address is not, and no credential is ever baked in here.
    func ltmServerURL(_ fallback: String = "http://127.0.0.1:8081") -> String {
        let env = ProcessInfo.processInfo.environment
        if let u = env["LTM_SERVER_URL"], !u.isEmpty { return u }
        return fallback
    }

    /// Resolve the server token without ever committing or printing it.
    /// Order: explicit LTM_SERVER_TOKEN, else the first live entry of the
    /// `key:token` file named by LTM_SERVER_ENV_FILE (which lives outside the
    /// repo). Absent configuration is a HARD FAILURE, never a skip — a green
    /// run that proved nothing is worse than a red one.
    func ltmServerToken() -> String {
        let env = ProcessInfo.processInfo.environment
        if let t = env["LTM_SERVER_TOKEN"], !t.isEmpty { return t }
        guard let path = env["LTM_SERVER_ENV_FILE"] else { return "" }
        return Self.ltmTokenFromFile(path)
    }

    static func ltmTokenFromFile(_ path: String) -> String {
        guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else { return "" }
        for line in raw.split(separator: "\n") {
            let s = line.trimmingCharacters(in: .whitespaces)
            if s.isEmpty || s.hasPrefix("#") { continue }
            if let i = s.firstIndex(of: ":") {
                let v = String(s[s.index(after: i)...]).trimmingCharacters(in: .whitespaces)
                if !v.isEmpty { return v }
            } else { return s }
        }
        return ""
    }

    func ltmRequireToken(file: StaticString = #filePath, line: UInt = #line) throws -> String {
        let t = ltmServerToken()
        if t.isEmpty {
            throw NSError(domain: "LTMSupport", code: 1, userInfo: [
                NSLocalizedDescriptionKey:
                    "no server token (set LTM_SERVER_TOKEN or LTM_SERVER_ENV_FILE)"
            ])
        }
        return t
    }

    /// The backup passphrase, supplied at RUNTIME and never committed.
    ///
    /// §28 forbids a committed passphrase. It must also be SHARED across
    /// stages, not generated per process: one stage creates the archive and a
    /// later stage restores it, so a per-process value would make the restore
    /// fail for a reason that has nothing to do with the product.
    func ltmBackupPassphrase() -> String {
        let env = ProcessInfo.processInfo.environment
        if let p = env["LTM_BACKUP_PASSPHRASE"], !p.isEmpty { return p }
        // Only for a standalone ad-hoc run. Any real gate must set the env var
        // (the journey stages depend on agreeing on the value).
        return "runtime-only-passphrase-not-a-secret"
    }

    // MARK: - clocks

    func ltmStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f.string(from: Date())
    }

    func ltmMark(_ what: String) { print("CLOCK \(ltmStamp()) \(what)") }

    // MARK: - element reads

    func ltmVal(_ e: XCUIElement) -> String {
        guard e.exists else { return "<MISSING>" }
        return (e.value as? String) ?? "<nil>"
    }

    /// Length of a secure field's content. An empty field reports its
    /// placeholder, so "Token" means EMPTY, not five characters.
    func ltmSecureLen(_ e: XCUIElement) -> Int {
        guard e.exists else { return -1 }
        let v = (e.value as? String) ?? ""
        if v.isEmpty { return 0 }
        return (v as NSString).length
    }

    func ltmAnyLabel(_ app: XCUIApplication, _ needle: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", needle))
            .firstMatch
    }

    func ltmCapture(_ app: XCUIApplication, _ stage: String) {
        let desc = app.debugDescription.replacingOccurrences(of: "\n", with: " ~ ")
        print("VISIBLES[\(stage)] " + String(desc.prefix(2200)))
    }

    /// Every label under an element, read from ONE snapshot.
    ///
    /// Do NOT use `staticTexts.allElementsBoundByIndex.map { $0.label }`.
    /// `.count` takes a snapshot and indexing then walks a potentially STALE
    /// one; when SwiftUI re-renders between the two — which it does the moment
    /// a photo picker dismisses — XCTest raises an UNCATCHABLE failure:
    ///   "Failed to get matching snapshot: No matches found for Element at index N"
    /// `debugDescription` is a single bounded snapshot, so parsing it cannot
    /// race the hierarchy.
    func ltmTexts(of element: XCUIElement) -> String {
        guard element.exists else { return "<missing>" }
        let desc = element.debugDescription
        var labels: [String] = []
        var search = desc[...]
        while let r = search.range(of: "label: '") {
            let after = search[r.upperBound...]
            guard let end = after.firstIndex(of: "'") else { break }
            let label = String(after[..<end])
            if !label.isEmpty && !labels.contains(label) { labels.append(label) }
            search = after[end...]
        }
        return labels.joined(separator: " | ")
    }

    /// Fallback evidence when an assertion fails and the accessibility shape was
    /// not what was expected.
    func ltmVisibleTexts(_ app: XCUIApplication) -> String {
        ltmTexts(of: app)
    }

    /// Image count as a SINGLE snapshot.
    ///
    /// Deliberately not `images.element(boundBy:)` on a captured array: that is
    /// the stale-snapshot pattern that raises an uncatchable XCTest failure when
    /// the hierarchy re-renders between the count and the index.
    func ltmImageCount(_ app: XCUIApplication) -> Int {
        app.images.count
    }

    // MARK: - scroll

    func ltmToTop(_ app: XCUIApplication, sweeps: Int = 3) {
        for _ in 0..<sweeps { app.swipeDown() }
        Thread.sleep(forTimeInterval: 0.35)
    }

    @discardableResult
    func ltmScrollTo(_ app: XCUIApplication, _ needle: String, maxTries: Int = 7) -> Bool {
        if ltmAnyLabel(app, needle).exists { return true }
        for _ in 0..<maxTries {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 0.35)
            if ltmAnyLabel(app, needle).exists { return true }
        }
        return false
    }

    /// Dismiss the software keyboard — MINIMAL BY DESIGN.
    ///
    /// Do NOT loop, and do NOT swipe down repeatedly. An earlier "thorough"
    /// version tapped Return then swiped down three times; inside the letter
    /// editor (a sheet) those swipes DISMISS THE SHEET, so the letter is lost
    /// and the failure surfaces much later as "Save Draft button missing".
    /// (That regression cost a full run.)
    ///
    /// One tap, and a single swipe only when no key is available. If the
    /// keyboard still refuses to go (Return inserts a newline in a multi-line
    /// text view) that is harmless: the tree re-checks and the scroll helpers
    /// cope with an offset form.
    func ltmDismissKeyboard(_ app: XCUIApplication) {
        guard app.keyboards.count > 0 else { return }
        if app.keyboards.buttons["Done"].exists { app.keyboards.buttons["Done"].tap() }
        else if app.keyboards.buttons["Return"].exists { app.keyboards.buttons["Return"].tap() }
        Thread.sleep(forTimeInterval: 0.6)
    }

    /// True when the software keyboard is still covering part of the screen.
    func ltmKeyboardUp(_ app: XCUIApplication) -> Bool { app.keyboards.count > 0 }

    // MARK: - the Form toggle

    /// Match the Enable switch by LABEL so a stray switch cannot be picked up.
    func ltmEnableSwitch(_ app: XCUIApplication) -> XCUIElement {
        let byLabel = app.switches
            .matching(NSPredicate(format: "label CONTAINS %@", "Enable Self-Hosted")).firstMatch
        return byLabel.exists ? byLabel : app.switches.firstMatch
    }

    /// Flip a `Form` Toggle to a target value by tapping the TRAILING control
    /// region, then verify the value actually changed.
    @discardableResult
    func ltmSetToggle(_ sw: XCUIElement, on: Bool) -> Bool {
        let want = on ? "1" : "0"
        if (sw.value as? String) == want { return true }
        sw.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        Thread.sleep(forTimeInterval: 0.9)
        return (sw.value as? String) == want
    }

    /// Flip the integration toggle, scrolling to a SETTLED position first.
    ///
    /// The scroll matters: tapping a coordinate while a swipe is still
    /// animating lands on the navigation bar rather than the row, which leaves
    /// the switch at 0 and looks like a product failure.
    @discardableResult
    func ltmSetIntegration(_ app: XCUIApplication, on: Bool) -> Bool {
        XCTAssertTrue(ltmScrollTo(app, "Enable Self-Hosted"), "Enable toggle not found")
        guard ltmDismissKnownBlockingSheet(app) else {
            ltmSettingsFailureSnapshot(app, "known AutoFill sheet blocked the integration toggle")
            return false
        }
        Thread.sleep(forTimeInterval: 0.4)
        let sw = ltmEnableSwitch(app)
        let ok = ltmSetToggle(sw, on: on)
        print("CFG toggle on=\(on) ok=\(ok) value=\(ltmVal(sw))")
        return ok
    }

    // MARK: - launch + navigation

    /// The app's main shell, as each form factor ACTUALLY renders it.
    ///
    /// MEASURED (iPad Pro 13-inch M5 / iOS 26.2, hierarchy captured in
    /// `evidence/ipad-hierarchy-probe.txt`): on regular-width iPad the five
    /// `TabView` destinations render as a top-edge segmented control whose
    /// members are plain `Button`s — there is NO `TabBar` container at all
    /// (`tabBars.count == 0`). `LibraryView` then renders its own
    /// `NavigationSplitView` (sidebar `CollectionView` labelled "Sidebar",
    /// content list, detail pane).
    ///
    /// So polling `tabBars.buttons["Letters"]` can NEVER succeed on iPad. That
    /// single wrong assumption is what made all three iPad tests report
    /// "main shell did not appear" while the app was in fact running the full
    /// shell — a UI TEST defect, not a product defect.
    func ltmMainShellAppeared(_ app: XCUIApplication, timeout: TimeInterval = 40) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if app.tabBars.buttons["Letters"].exists { return true }
            // iPad/regular width: no tab bar, so identify the shell by a real
            // destination control plus rendered navigation chrome.
            if app.buttons["Letters"].exists && app.navigationBars.count > 0 { return true }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return false
    }

    /// Activate a top-level destination on EITHER form factor.
    ///
    /// iPhone has a tab bar; regular-width iPad has the segmented
    /// destination `Button`s. Both are matched by the same user-visible label,
    /// so the suites no longer encode one form factor's shell.
    @discardableResult
    func ltmOpenDestination(_ app: XCUIApplication, _ name: String,
                            file: StaticString = #filePath, line: UInt = #line) -> Bool {
        if let el = ltmDestinationElement(app, name) {
            if el.isHittable { el.tap() }
            else { el.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
            Thread.sleep(forTimeInterval: 0.9)
            return true
        }
        XCTFail("destination '\(name)' is not reachable on this form factor",
                file: file, line: line)
        return false
    }

    /// The control that switches to a top-level destination, or nil if absent.
    func ltmDestinationElement(_ app: XCUIApplication, _ name: String) -> XCUIElement? {
        let tab = app.tabBars.buttons[name]
        if tab.exists { return tab }
        let button = app.buttons[name].firstMatch
        if button.exists { return button }
        return nil
    }

    /// True when the shell is the compact (tab-bar) presentation.
    func ltmUsesTabBar(_ app: XCUIApplication) -> Bool { app.tabBars.buttons.count > 0 }

    @discardableResult
    func ltmLaunch(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) -> XCUIApplication {
        app.launch()
        // Real onboarding (no launch-argument shortcut): an argument-domain
        // value would permanently shadow the app's own @AppStorage write.
        let cta = app.buttons["Create Our Family Archive"]
        if cta.waitForExistence(timeout: 20) { cta.tap() }
        XCTAssertTrue(ltmMainShellAppeared(app, timeout: 40),
                      "main shell did not appear", file: file, line: line)
        return app
    }

    /// Poll for a StaticText whose label CONTAINS `needle`.
    ///
    /// Label matching (not `staticTexts[needle]`) because a SwiftUI list row
    /// and a detail pane can both render the same string, and because the
    /// element may take a moment to appear after a split-view selection.
    func ltmWaitForText(_ app: XCUIApplication, _ needle: String,
                        timeout: TimeInterval = 15) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        let query = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", needle))
        while Date() < deadline {
            if query.firstMatch.exists { return true }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return false
    }

    func ltmSelfHostedRow(_ app: XCUIApplication) -> XCUIElement {
        let button = app.buttons["Self-Hosted Server"]
        if button.exists { return button }
        return app.cells["Self-Hosted Server"]
    }

    /// Settings → tap the "Self-Hosted Server" row from a settled scroll position.
    @discardableResult
    func ltmTapSelfHostedRow(_ app: XCUIApplication) -> Bool {
        for _ in 0..<3 { app.swipeDown(); Thread.sleep(forTimeInterval: 0.35) }
        var row = ltmSelfHostedRow(app)
        var tries = 0
        while !(row.exists && row.isHittable) && tries < 8 {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 0.6)
            row = ltmSelfHostedRow(app)
            tries += 1
        }
        guard row.exists else { return false }
        Thread.sleep(forTimeInterval: 0.6)
        if row.isHittable { row.tap() }
        else { row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
        if app.navigationBars["Self-Hosted Server"].waitForExistence(timeout: 10) { return true }
        Thread.sleep(forTimeInterval: 0.8)
        row = ltmSelfHostedRow(app)
        guard row.exists else { return false }
        if row.isHittable { row.tap() }
        else { row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
        return app.navigationBars["Self-Hosted Server"].waitForExistence(timeout: 15)
    }

    func ltmOpenSelfHosted(_ app: XCUIApplication,
                           file: StaticString = #filePath, line: UInt = #line) {
        ltmDismissKeyboard(app)
        XCTAssertTrue(ltmGoToSettingsRoot(app),
                      "could not reach the Settings root", file: file, line: line)
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertTrue(ltmTapSelfHostedRow(app),
                      "could not open the Self-Hosted Server screen", file: file, line: line)
        Thread.sleep(forTimeInterval: 0.5)
    }

    /// Capture one accessibility-tree snapshot for navigation failures. The
    /// filtered sections include the selected destination when XCTest exposes it,
    /// navigation titles, visible controls, rows, and modal blockers. Do not
    /// enumerate live XCUIElement arrays here: SwiftUI can re-render mid-read.
    func ltmSettingsFailureSnapshot(_ app: XCUIApplication, _ reason: String) {
        let snapshot = app.debugDescription
        let lines = snapshot.components(separatedBy: "\n")
        let destinations = ["Letters", "Timeline", "Family", "People", "Settings"]
        let destinationLines = lines.filter { line in
            destinations.contains { line.contains("label: '\($0)'") }
        }
        let selectedLines = destinationLines.filter {
            $0.localizedCaseInsensitiveContains("selected")
        }
        let navLines = lines.filter { $0.contains("NavigationBar") }
        let buttonLines = lines.filter { $0.contains("Button") || $0.contains("Tab") }
        let textLines = lines.filter { $0.contains("StaticText") }
        let cellLines = lines.filter { $0.contains("Cell") }
        let modalLines = lines.filter {
            let lower = $0.lowercased()
            return lower.contains("sheet") || lower.contains("alert") ||
                lower.contains("dialog") || lower.contains("popover")
        }
        func bounded(_ values: [String], _ max: Int = 1800) -> String {
            String(values.joined(separator: " | ").prefix(max))
        }
        let selected = selectedLines.isEmpty
            ? "not exposed; candidates: \(bounded(destinationLines, 900))"
            : bounded(selectedLines, 900)
        print("NAV FAILURE[\(reason)] selectedDestination=\(selected)")
        print("NAV FAILURE[\(reason)] navigationTitles=\(bounded(navLines, 900))")
        print("NAV FAILURE[\(reason)] BackButton=\(snapshot.contains("BackButton")) modalIndicators=\(bounded(modalLines, 900))")
        print("NAV FAILURE[\(reason)] visibleButtons=\(bounded(buttonLines))")
        print("NAV FAILURE[\(reason)] visibleStaticText=\(bounded(textLines))")
        print("NAV FAILURE[\(reason)] visibleCells=\(bounded(cellLines))")
    }

    /// Dismiss only the known iOS password-autofill prompt that can cover the
    /// app after a SecureField is entered. It is a real blocking sheet, not an
    /// app confirmation; use its explicit non-destructive action, never a generic
    /// Close or outside tap.
    @discardableResult
    func ltmDismissKnownBlockingSheet(_ app: XCUIApplication) -> Bool {
        let prompt = app.sheets["Save Password?"]
        guard prompt.exists else { return true }
        let notNow = prompt.buttons["Not Now"]
        guard notNow.exists && notNow.isHittable else { return false }
        notNow.tap()
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if !app.sheets["Save Password?"].exists { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return false
    }

    /// Normalize to the Settings root without assuming how the app got here.
    /// iOS 26 preserves each destination's NavigationStack across tab switches
    /// and relaunches. Settings is a TabBar button on iPhone and a top-edge
    /// segmented-style Button on regular-width iPad.
    @discardableResult
    func ltmGoToSettingsRoot(_ app: XCUIApplication, timeout: TimeInterval = 30) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        let settingsChildTitles = [
            "Self-Hosted Server", "Backups", "Recovery Contacts",
            "Add Recovery Contact", "Restore from Server", "Restore Archive"
        ]

        while Date() < deadline {
            // iOS can surface this exact AutoFill sheet after an API token was
            // entered in a SecureField. Dismiss it only via its explicit
            // non-destructive "Not Now" button; otherwise report the blocker.
            if app.sheets["Save Password?"].exists {
                if ltmDismissKnownBlockingSheet(app) { continue }
                ltmSettingsFailureSnapshot(app, "blocking Save Password sheet has no safe action")
                return false
            }
            // Only dismiss a blocker through its explicit, safe Cancel action.
            // Never swipe a sheet away or tap an ambiguous generic Close button.
            let alertCancel = app.alerts.buttons["Cancel"]
            if alertCancel.exists && alertCancel.isHittable {
                alertCancel.tap()
                continue
            }
            let sheetCancel = app.sheets.buttons["Cancel"]
            if sheetCancel.exists && sheetCancel.isHittable {
                sheetCancel.tap()
                continue
            }
            if app.alerts.count > 0 || app.sheets.count > 0 {
                ltmSettingsFailureSnapshot(app, "blocking modal has no safe Cancel action")
                return false
            }

            let settingsRoot = app.navigationBars["Settings"]
            let back = app.navigationBars.buttons["BackButton"]
            if settingsRoot.exists && !back.exists { return true }

            let isKnownSettingsChild = settingsChildTitles.contains {
                app.navigationBars[$0].exists
            }
            if back.exists && back.isHittable && isKnownSettingsChild {
                back.tap()
                _ = settingsRoot.waitForExistence(
                    timeout: min(8, max(1, deadline.timeIntervalSinceNow))
                )
                continue
            }

            guard let settingsDestination = ltmDestinationElement(app, "Settings") else {
                Thread.sleep(forTimeInterval: 0.25)
                continue
            }
            if settingsDestination.isSelected {
                if back.exists && back.isHittable {
                    back.tap()
                    _ = settingsRoot.waitForExistence(
                        timeout: min(8, max(1, deadline.timeIntervalSinceNow))
                    )
                    continue
                }
                if settingsRoot.exists { return true }
            } else if settingsDestination.isHittable {
                settingsDestination.tap()
            }
            // Re-evaluate observable state after the action; a tap is not proof.
            Thread.sleep(forTimeInterval: 0.25)
        }

        ltmSettingsFailureSnapshot(app, "Settings root timeout")
        return false
    }

    /// Open a Settings row by its semantic label, regardless of whether SwiftUI
    /// exposes it as a Button, Cell, or combined accessibility row. Normalize the
    /// child stack AND the Form scroll position before tapping. A visible/hittable
    /// row alone is insufficient immediately after switching tabs or restoring a
    /// preserved Settings stack: the first tap can land during a stale scroll
    /// geometry update and leave the NavigationLink unopened.
    @discardableResult
    func ltmOpenSettingsRow(_ app: XCUIApplication, row: String, timeout: TimeInterval = 35) -> Bool {
        ltmDismissKeyboard(app)
        let screenTitle = row == "Manage Backups" ? "Backups" : row
        let targetScreen = app.navigationBars[screenTitle]
        let backButton = app.navigationBars.buttons["BackButton"]
        if targetScreen.exists && backButton.exists { return true }

        let deadline = Date().addingTimeInterval(timeout)
        guard ltmGoToSettingsRoot(app, timeout: min(30, timeout)) else {
            ltmSettingsFailureSnapshot(app, "cannot normalize before row '\(row)'")
            return false
        }

        // The first Settings section has a visible semantic header. Scroll down
        // only while that marker is absent, checking the resulting accessibility
        // state after each gesture instead of assuming a fixed number of swipes
        // or a particular prior offset.
        let settingsRoot = app.navigationBars["Settings"]
        let topMarker = app.staticTexts["Preview"]
        var reachedListTop = false
        for _ in 0..<8 {
            if settingsRoot.exists && !backButton.exists && topMarker.exists && topMarker.isHittable {
                reachedListTop = true
                break
            }
            guard settingsRoot.exists && !backButton.exists && Date() < deadline else { break }
            app.swipeDown()
            Thread.sleep(forTimeInterval: 0.35)
        }
        guard reachedListTop else {
            ltmSettingsFailureSnapshot(app, "Settings list top marker not reached before row '\(row)'")
            return false
        }

        func rowElement() -> XCUIElement {
            let button = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", row)).firstMatch
            if button.exists { return button }
            let cell = app.cells.matching(NSPredicate(format: "label CONTAINS %@", row)).firstMatch
            if cell.exists { return cell }
            return app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS %@", row))
                .firstMatch
        }

        // Settings rows are below the top marker. Scroll until the requested
        // row is visible, then reacquire it and require stable geometry before
        // tapping so no XCUIElement from a previous Form snapshot is reused.
        for _ in 0..<10 {
            guard Date() < deadline else { break }
            let candidate = rowElement()
            if candidate.exists && candidate.isHittable {
                let initialFrame = candidate.frame
                Thread.sleep(forTimeInterval: 0.4)
                let settled = rowElement()
                if settled.exists && settled.isHittable && settled.frame.equalTo(initialFrame) {
                    settled.tap()
                    let opened = targetScreen.waitForExistence(
                        timeout: min(12, max(1, deadline.timeIntervalSinceNow))
                    )
                    if !opened {
                        ltmSettingsFailureSnapshot(app, "row '\(row)' tapped but destination did not appear")
                    }
                    return opened
                }
                // A re-render or moving row invalidates the prior element; read
                // the current state again without issuing another tap.
                continue
            }
            app.swipeUp()
            Thread.sleep(forTimeInterval: 0.35)
        }

        ltmSettingsFailureSnapshot(app, "Settings row '\(row)' not tappable after scroll normalization")
        return false
    }

    /// Pop back to the Settings root and re-enter a Self-Hosted-style screen.
    /// iOS 26 preserves the per-tab stack, so an explicit pop is required; a
    /// process relaunch is the fallback (and a stronger persistence proof).
    @discardableResult
    func ltmLeaveAndReturn(_ app: XCUIApplication, screen: String, label: String) -> Bool {
        ltmDismissKeyboard(app)
        if app.navigationBars[screen].exists,
           let back = app.navigationBars[screen].buttons.firstMatch as XCUIElement?,
           back.exists {
            back.tap()
        }
        if app.navigationBars["Settings"].waitForExistence(timeout: 10) {
            print("NAV[\(label)] popped back to Settings")
            Thread.sleep(forTimeInterval: 0.7)
            let ok = ltmOpenSettingsRow(app, row: screen)
            print("NAV[\(label)] reopened=\(ok)")
            if ok { return true }
        }
        print("NAV[\(label)] pop did not settle -- falling back to a process relaunch")
        app.terminate()
        let app2 = XCUIApplication()
        app2.launch()
        let cta = app2.buttons["Create Our Family Archive"]
        if cta.waitForExistence(timeout: 12) { cta.tap() }
        guard app2.tabBars.buttons["Settings"].waitForExistence(timeout: 40) else {
            print("NAV[\(label)] main shell did not appear after relaunch")
            return false
        }
        let ok = ltmOpenSettingsRow(app2, row: screen)
        print("NAV[\(label)] reopened after relaunch=\(ok)")
        return ok
    }

    // MARK: - self-hosted configuration through the real form

    /// Switch the integration OFF and clear URL + token, as a real user must
    /// before the (disabled-when-enabled) fields accept input.
    func ltmClearConfiguration(_ app: XCUIApplication) {
        _ = ltmSetIntegration(app, on: false)
        if ltmScrollTo(app, "Clear Configuration") {
            let clear = app.buttons["Clear Configuration"]
            if clear.exists && clear.isEnabled {
                clear.tap()
                Thread.sleep(forTimeInterval: 0.8)
            }
        }
        ltmDismissKeyboard(app)
    }

    /// Replace a text field's contents regardless of what it already holds.
    ///
    /// MEASURED FAILURE this exists to prevent: the product persists the server
    /// URL in `UserDefaults`, and the simulator keeps that store across
    /// launches, so the field can arrive ALREADY POPULATED by an earlier run.
    /// `typeText` appends at the caret, which produced
    /// `http://127.0.0.1:8081http://127.0.0.1:8081` and failed
    /// `ServerAndBackupUITests` in setup on all four tests, with ZERO requests
    /// reaching the server — a self-inflicted red suite, not a product fault.
    ///
    /// The product's own "Clear Configuration" button is NOT a sufficient
    /// answer here: it is `.disabled(!config.isConfigured)`, so when only part
    /// of the config survived it silently does nothing and the stale value
    /// remains. Clearing the field is the test's job.
    /// Tap until the software keyboard is actually up.
    ///
    /// MEASURED: `field.tap()` can return before the field takes focus, and the
    /// following `typeText` then fails HARD with "Neither element nor any
    /// descendant has keyboard focus" — an uncatchable XCTest failure that looks
    /// like a product problem. Waiting for the keyboard to appear is the only
    /// reliable signal that focus landed.
    @discardableResult
    func ltmFocus(_ app: XCUIApplication, _ field: XCUIElement, tries: Int = 8) -> Bool {
        for _ in 0..<tries {
            if app.keyboards.count > 0 { return true }
            field.tap()
            Thread.sleep(forTimeInterval: 0.6)
        }
        return app.keyboards.count > 0
    }

    func ltmReplaceText(_ app: XCUIApplication, _ field: XCUIElement, _ text: String) {
        func current() -> String { (field.value as? String) ?? "" }

        // TRIPLE TAP selects the whole field on iOS, which is caret-independent:
        // tapping to place a caret put it mid-string and a delete run then left
        // `...:8081:8081://127...` behind. `typeKey` is avoided entirely because
        // it requires the simulator's hardware keyboard and throws without it.
        for attempt in 1...3 {
            ltmFocus(app, field)
            field.tap(withNumberOfTaps: 3, numberOfTouches: 1)
            Thread.sleep(forTimeInterval: 0.5)
            if current().isEmpty { break }
            ltmFocus(app, field)
            field.typeText(text)
            Thread.sleep(forTimeInterval: 0.5)
            if current() == text { return }
            print("CFG replace attempt=\(attempt) value='\(current().prefix(60))'")
            // Fallback: select all from the edit menu, then overwrite.
            field.press(forDuration: 1.0)
            if app.menuItems["Select All"].waitForExistence(timeout: 2) {
                app.menuItems["Select All"].tap()
                Thread.sleep(forTimeInterval: 0.4)
                ltmFocus(app, field)
                field.typeText(text)
                Thread.sleep(forTimeInterval: 0.5)
                if current() == text { return }
            } else {
                app.tap()
                Thread.sleep(forTimeInterval: 0.3)
            }
        }
        // Give the caller the real value to assert on rather than a silent pass.
        ltmFocus(app, field)
        field.tap(withNumberOfTaps: 3, numberOfTouches: 1)
        Thread.sleep(forTimeInterval: 0.3)
        field.typeText(text)
        Thread.sleep(forTimeInterval: 0.4)
    }

    func ltmTypeURL(_ app: XCUIApplication, _ url: String,
                    file: StaticString = #filePath, line: UInt = #line) {
        ltmToTop(app)
        _ = ltmScrollTo(app, "letters.example.com")
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 20),
                      "server URL field missing", file: file, line: line)
        ltmReplaceText(app, field, url)
        ltmDismissKeyboard(app)
        ltmToTop(app)
        let read = ltmVal(app.textFields.firstMatch)
        print("CFG urlTyped='\(read)' intended='\(url)' match=\(read == url)")
        XCTAssertEqual(read, url, "server URL did not stick in the field", file: file, line: line)
    }

    @discardableResult
    func ltmTypeToken(_ app: XCUIApplication, _ value: String, label: String) -> Int {
        _ = ltmScrollTo(app, "Token")
        let field = app.secureTextFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 15), "API token field missing")
        // A secure field reports its PLACEHOLDER as `value` when empty, so it
        // must not be treated as pre-existing content to select.
        let hadContent = ltmSecureLen(field) > 0
        ltmFocus(app, field)
        Thread.sleep(forTimeInterval: 0.4)
        if hadContent {
            // Hardware-keyboard-independent clear, as in `ltmReplaceText`.
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue,
                                  count: 120))
            Thread.sleep(forTimeInterval: 0.4)
        }
        ltmFocus(app, field)
        field.typeText(value)
        ltmDismissKeyboard(app)
        let len = ltmSecureLen(app.secureTextFields.firstMatch)
        print("CFG token[\(label)] fieldLen=\(len) intendedLen=\(value.count)")
        return len
    }

    /// Full configure-the-server flow, ending with the integration ENABLED.
    func ltmConfigureSelfHosted(_ app: XCUIApplication, url: String, token: String) {
        ltmOpenSelfHosted(app)
        ltmClearConfiguration(app)
        ltmTypeURL(app, url)
        ltmTypeToken(app, token, label: "valid")
        XCTAssertTrue(ltmSetIntegration(app, on: true),
                      "integration did not become enabled")
    }

    /// Poll for the first of `needles` to appear in the accessibility tree.
    /// Returns "" on timeout. Scrolls to the top first: the tree only contains
    /// on-screen elements and the status/identity row sits at the top.
    func ltmWaitForAny(_ app: XCUIApplication, _ needles: [String], timeout: TimeInterval) -> String {
        ltmToTop(app)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for n in needles where ltmAnyLabel(app, n).exists { return n }
            Thread.sleep(forTimeInterval: 1.0)
        }
        return ""
    }

    func ltmAssertAbsent(_ app: XCUIApplication, _ needles: [String], context: String) {
        for n in needles where ltmAnyLabel(app, n).exists {
            XCTFail("\(context): found forbidden label '\(n)'.\n--- tree ---\n\(app.debugDescription.prefix(2500))")
        }
    }

    /// Tap "Test Connection", which is only enabled with a complete config.
    func ltmTapTestConnection(_ app: XCUIApplication,
                             file: StaticString = #filePath, line: UInt = #line) {
        ltmDismissKeyboard(app)
        XCTAssertTrue(ltmScrollTo(app, "Test Connection"),
                      "'Test Connection' not found", file: file, line: line)
        let probe = app.buttons["Test Connection"]
        XCTAssertTrue(probe.waitForExistence(timeout: 15),
                      "Test Connection button missing", file: file, line: line)
        XCTAssertTrue(probe.isEnabled,
                      "Test Connection is disabled (needs enabled && isConfigured)",
                      file: file, line: line)
        ltmMark("TEST-CONNECTION tap")
        probe.tap()
        ltmMark("TEST-CONNECTION tapped")
    }

    /// Wait for the connected identity row (or return the failure label).
    @discardableResult
    func ltmWaitForConnected(_ app: XCUIApplication, timeout: TimeInterval = 75) -> String {
        ltmWaitForAny(app, ["API v", "Authentication failed", "Server unreachable",
                            "Server error", "Incompatible server"], timeout: timeout)
    }
}
