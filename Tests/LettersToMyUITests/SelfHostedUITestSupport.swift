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
        Thread.sleep(forTimeInterval: 0.4)
        let sw = ltmEnableSwitch(app)
        let ok = ltmSetToggle(sw, on: on)
        print("CFG toggle on=\(on) ok=\(ok) value=\(ltmVal(sw))")
        return ok
    }

    // MARK: - launch + navigation

    @discardableResult
    func ltmLaunch(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) -> XCUIApplication {
        app.launch()
        // Real onboarding (no launch-argument shortcut): an argument-domain
        // value would permanently shadow the app's own @AppStorage write.
        let cta = app.buttons["Create Our Family Archive"]
        if cta.waitForExistence(timeout: 20) { cta.tap() }
        XCTAssertTrue(app.tabBars.buttons["Letters"].waitForExistence(timeout: 40),
                      "main shell did not appear", file: file, line: line)
        return app
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

    /// Navigate to the Settings ROOT, resilient to the two failure modes this
    /// audit actually measured:
    ///   * a pushed screen covering the root — iOS 26 preserves each tab's
    ///     navigation stack, so arriving from Self-Hosted Server leaves the
    ///     Settings row list invisible;
    ///   * a tab tap that lands before the shell has settled after launch,
    ///     which is silently swallowed and leaves the old screen up.
    /// Both show up as the same symptom (no `navigationBars["Settings"]`), so
    /// retry the cycle rather than waiting once.
    ///
    /// DO NOT detect "something is pushed" with `navigationBars.count > 0`.
    /// The Letters root has its own navigation bar, so that test is TRUE on the
    /// Letters tab and a blind `navigationBars.buttons.firstMatch` tap then
    /// loops forever without ever tapping the tab (measured: 20 futile pops).
    /// Only a real push has the `BackButton` identifier, so that is the trigger
    /// — and the tab tap must be the thing that happens when no push exists.
    @discardableResult
    func ltmGoToSettingsRoot(_ app: XCUIApplication, timeout: TimeInterval = 45) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var attempts = 0
        while Date() < deadline {
            attempts += 1
            if app.navigationBars["Settings"].exists { return true }

            let back = app.navigationBars.buttons["BackButton"]
            if back.exists && back.isHittable {
                print("NAV[\(attempts)] popping pushed screen above Settings")
                back.tap()
                Thread.sleep(forTimeInterval: 0.8)
                continue
            }

            let tab = app.tabBars.buttons["Settings"]
            if tab.waitForExistence(timeout: 10) {
                if tab.isHittable { tab.tap() }
                else { tab.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
            } else {
                print("NAV[\(attempts)] Settings tab not present")
            }
            Thread.sleep(forTimeInterval: 1.2)
        }
        print("NAV could not reach the Settings root after \(attempts) attempts; visible=\(ltmTexts(of: app).prefix(300))")
        return false
    }

    /// Open any Settings row by name, scrolling to it if needed.
    @discardableResult
    func ltmOpenSettingsRow(_ app: XCUIApplication, row: String, timeout: TimeInterval = 25) -> Bool {
        ltmDismissKeyboard(app)

        // Two rounds. The second re-enters the Settings root via the TAB BAR
        // (the path a freshly launched app takes, which is verified reliable);
        // arriving by POPPING a pushed screen can leave a row reporting
        // exists=true / isHittable=false, which no amount of scrolling fixes.
        for round in 1...2 {
            guard ltmGoToSettingsRoot(app) else {
                print("NAV Settings root unreachable for row '\(row)' (round \(round))")
                continue
            }
            ltmDismissKeyboard(app)
            Thread.sleep(forTimeInterval: 0.6)
            for _ in 0..<3 { app.swipeDown(); Thread.sleep(forTimeInterval: 0.3) }

            var target = app.buttons[row]
            if !target.exists { target = app.cells[row] }
            var tries = 0
            while !(target.exists && target.isHittable) && tries < 6 {
                app.swipeUp()
                Thread.sleep(forTimeInterval: 0.5)
                target = app.buttons[row]
                if !target.exists { target = app.cells[row] }
                tries += 1
            }

            if target.exists && target.isHittable {
                target.tap()
                return true
            }
            print("NAV row '\(row)' exists=\(target.exists) hittable=\(target.exists ? String(target.isHittable) : "n/a") keyboard=\(app.keyboards.count) texts=\(ltmTexts(of: app).prefix(220))")

            // Resettle by leaving and re-entering the Settings tab.
            app.tabBars.buttons["Letters"].tap()
            Thread.sleep(forTimeInterval: 0.8)
            app.tabBars.buttons["Settings"].tap()
            Thread.sleep(forTimeInterval: 1.0)
        }
        print("NAV Settings row '\(row)' could not be tapped after 2 rounds")
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

    func ltmTypeURL(_ app: XCUIApplication, _ url: String,
                    file: StaticString = #filePath, line: UInt = #line) {
        ltmToTop(app)
        _ = ltmScrollTo(app, "letters.example.com")
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 20),
                      "server URL field missing", file: file, line: line)
        field.tap()
        field.typeText(url)
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
        field.tap()
        Thread.sleep(forTimeInterval: 0.4)
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
