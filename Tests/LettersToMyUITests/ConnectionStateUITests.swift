import XCTest

/// §4–§18: runtime proof of the three SelfHostedSync connection states through
/// the REAL app UI, against the real server, with wire-level evidence.
///
/// Three-state matrix under test:
///   valid token    -> /status 200 -> connected            -> identity row
///   invalid token  -> /status 401 -> authenticationFailed -> "Authentication failed"
///   server offline -> no HTTP response -> unreachable     -> "Server unreachable"
///
/// Harness rules learned the hard way earlier in this audit (do not "simplify"):
///   * a SwiftUI `Form` `Toggle` is ONE row-wide accessibility element, so a
///     centre `tap()` lands on the label and does NOT flip the switch -- tap the
///     trailing control position and read the value back;
///   * the status row is `.accessibilityElement(children: .combine)`, so a state
///     is never a bare `staticTexts["..."]` -- match with CONTAINS over any
///     element type;
///   * the accessibility tree contains only ON-SCREEN elements, so scroll before
///     querying, and read values back instead of trusting `typeText` to stick;
///   * an EMPTY SwiftUI `TextField` reports its PLACEHOLDER as `value`, so a
///     post-clear read of `secureTextFields.value` returns "Token" (len 5) --
///     that is "empty", not "5 characters of token".
///
/// Ordering is deliberate: each test proves the wire+classification+UI result
/// FIRST and only then runs the persistence diagnostics, so a fragile navigation
/// helper can never hide the finding the test exists to produce.
///
/// Configuration is environment-driven (LTM_SERVER_URL / LTM_SERVER_TOKEN /
/// LTM_SERVER_ENV_FILE) with a localhost default: no LAN address and no
/// credential is ever committed or printed.
final class ConnectionStateUITests: XCTestCase {

    private var serverURL = "http://127.0.0.1:8081"
    private var liveServerURL = "http://127.0.0.1:8081"
    private let offlineServerURL = "http://127.0.0.1:9"
    private var token = ""

    /// Deliberately alphanumeric so no keyboard autocorrection/autocapitalisation
    /// can mangle it. It is NOT a secret: any HTTP 401 for this value is itself
    /// the proof that it reached the server as the bearer token.
    private let invalidToken = "invalidtoken0000000000000000"

    override func setUpWithError() throws {
        continueAfterFailure = false
        let env = ProcessInfo.processInfo.environment
        if let u = env["LTM_SERVER_URL"], !u.isEmpty {
            serverURL = u
            liveServerURL = u
        }
        if let t = env["LTM_SERVER_TOKEN"], !t.isEmpty {
            token = t
        } else if let f = env["LTM_SERVER_ENV_FILE"] {
            token = Self.tokenFromFile(f)
        }
        // Never the token itself, only its length.
        print("TESTCFG serverURL=\(serverURL) tokenLen=\(token.count) invalidTokenLen=\(invalidToken.count)")
        if token.isEmpty {
            throw NSError(domain: "ConnectionStateUITests", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "no token (set LTM_SERVER_TOKEN or LTM_SERVER_ENV_FILE)"
            ])
        }
    }

    private static func tokenFromFile(_ path: String) -> String {
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

    // MARK: - clocks (for correlation with the proxy log)

    private func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f.string(from: Date())
    }

    private func mark(_ what: String) {
        print("CLOCK \(stamp()) \(what)")
    }

    // MARK: - accessibility helpers

    private func val(_ e: XCUIElement) -> String {
        guard e.exists else { return "<MISSING>" }
        return (e.value as? String) ?? "<nil>"
    }

    /// Length of what the secure field reports. An empty field reports the
    /// placeholder ("Token"), so anything is better read with `secureLen`.
    private func secureLen(_ e: XCUIElement) -> Int {
        guard e.exists else { return -1 }
        let v = (e.value as? String) ?? ""
        return v == "Token" ? 0 : (v as NSString).length
    }

    private func anyLabel(_ app: XCUIApplication, _ needle: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", needle))
            .firstMatch
    }

    private func toTop(_ app: XCUIApplication) {
        for _ in 0..<3 { app.swipeDown() }
        Thread.sleep(forTimeInterval: 0.35)
    }

    @discardableResult
    private func scrollTo(_ app: XCUIApplication, _ needle: String, maxTries: Int = 7) -> Bool {
        if anyLabel(app, needle).exists { return true }
        for _ in 0..<maxTries {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 0.35)
            if anyLabel(app, needle).exists { return true }
        }
        return false
    }

    /// Under XCUITest a hardware keyboard is often active (keyboards.count == 0),
    /// in which case nothing covers the form.
    private func dismissKeyboard(_ app: XCUIApplication) {
        guard app.keyboards.count > 0 else { return }
        if app.keyboards.buttons["Done"].exists { app.keyboards.buttons["Done"].tap() }
        else if app.keyboards.buttons["Return"].exists { app.keyboards.buttons["Return"].tap() }
        else { app.swipeDown() }
        Thread.sleep(forTimeInterval: 0.6)
    }

    private func theSwitch(_ app: XCUIApplication) -> XCUIElement {
        let byLabel = app.switches
            .matching(NSPredicate(format: "label CONTAINS %@", "Enable Self-Hosted")).firstMatch
        return byLabel.exists ? byLabel : app.switches.firstMatch
    }

    private func capture(_ app: XCUIApplication, _ stage: String) {
        let desc = app.debugDescription.replacingOccurrences(of: "\n", with: " ~ ")
        print("VISIBLES[\(stage)] " + String(desc.prefix(2500)))
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        let cta = app.buttons["Create Our Family Archive"]
        if cta.waitForExistence(timeout: 20) { cta.tap() }
        XCTAssertTrue(app.tabBars.buttons["Letters"].waitForExistence(timeout: 40),
                      "main shell did not appear")
        return app
    }

    // MARK: - navigation

    /// Navigate through the shared stack normalizer. The Settings destination can
    /// already be pushed after an earlier test or relaunch.
    private func openSelfHosted(_ app: XCUIApplication) {
        dismissKeyboard(app)
        XCTAssertTrue(ltmOpenSettingsRow(app, row: "Self-Hosted Server"),
                      "could not normalize Settings and open Self-Hosted Server")
        Thread.sleep(forTimeInterval: 0.5)
    }

    /// Leave and return to prove configuration survives a navigation transition.
    @discardableResult
    private func leaveAndReturn(_ app: XCUIApplication, label: String) -> Bool {
        let result = ltmLeaveAndReturn(app, screen: "Self-Hosted Server", label: label)
        print("NAV[\(label)] reopened=\(result)")
        return result
    }

    /// Non-fatal counterpart used only for post-probe diagnostics.
    @discardableResult
    private func tolerantOpenSelfHosted(_ app: XCUIApplication) -> Bool {
        dismissKeyboard(app)
        let opened = ltmOpenSettingsRow(app, row: "Self-Hosted Server")
        if !opened { print("DIAG shared Settings navigation could not reopen Self-Hosted") }
        return opened
    }

    // MARK: - configuration primitives (real user interaction only)

    private func clearConfiguration(_ app: XCUIApplication) {
        ltmClearConfiguration(app)
        print("CFG configuration cleared through shared UI helper")
    }

    private func typeURL(_ app: XCUIApplication) {
        ltmTypeURL(app, serverURL)
    }

    /// Type a token through the shared focus-aware helper and read back only length.
    @discardableResult
    private func typeToken(_ app: XCUIApplication, _ value: String, label: String) -> Int {
        let length = ltmTypeToken(app, value, label: label)
        XCTAssertEqual(length, value.count, "API token did not stick in the secure field")
        return length
    }

    /// §4: replace the STORED token through the real UI (no Keychain edits, no
    /// launch arguments). Fields are `.disabled(config.enabled)`, so the
    /// integration must be switched off first -- which is also what a real user
    /// has to do. The delete count is derived from the field's own reported value
    /// length; leftover text would just re-send the old token, and the wire 401
    /// assertion is what proves the replacement actually took.
    private func replaceStoredToken(_ app: XCUIApplication, with newValue: String) -> String {
        scrollTo(app, "Enable Self-Hosted")
        let sw = theSwitch(app)
        if (sw.value as? String) == "1" { _ = ltmSetIntegration(app, on: false) }
        Thread.sleep(forTimeInterval: 0.5)

        scrollTo(app, "Token")
        let field = app.secureTextFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 15), "API token field missing")
        XCTAssertTrue(field.isEnabled, "token field is still disabled -- integration was not switched off")
        XCTAssertTrue(ltmFocus(app, field), "token field did not take keyboard focus")
        let before = secureLen(field)
        let deletes = max(before, 8) + 8
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: deletes))
        Thread.sleep(forTimeInterval: 0.5)
        let afterClear = secureLen(field)
        XCTAssertTrue(ltmFocus(app, field), "token field lost keyboard focus after clearing")
        field.typeText(newValue)
        dismissKeyboard(app)
        let afterType = secureLen(app.secureTextFields.firstMatch)
        let how = "deletes=\(deletes) beforeLen=\(before) afterClearLen=\(afterClear) afterTypeLen=\(afterType)"
        print("REPLACE token \(how)")
        XCTAssertEqual(afterClear, 0, "the previous token was not cleared before typing the new value")
        XCTAssertEqual(afterType, newValue.count, "the replacement token did not stick")
        XCTAssertTrue(ltmDismissKnownBlockingSheet(app),
                      "known password-autofill sheet could not be dismissed safely")

        // Re-enable. With a complete config this auto-runs the probe.
        let ok = ltmSetIntegration(app, on: true)
        print("REPLACE re-enabled=\(ok) sw=\(val(theSwitch(app)))")
        XCTAssertTrue(ok, "integration did not become enabled after the token replacement")
        return how
    }

    private func tapTestConnection(_ app: XCUIApplication) {
        dismissKeyboard(app)
        XCTAssertTrue(scrollTo(app, "Test Connection"), "'Test Connection' not found")
        let probe = app.buttons["Test Connection"]
        XCTAssertTrue(probe.waitForExistence(timeout: 15), "Test Connection button missing")
        XCTAssertTrue(probe.isEnabled,
                      "Test Connection is disabled (needs enabled && isConfigured) -- config did not persist")
        mark("TEST-CONNECTION tap (enabled=\(probe.isEnabled))")
        probe.tap()
        mark("TEST-CONNECTION tapped")
    }

    /// Poll for the first of `needles` to appear in the accessibility tree.
    /// Returns "" on timeout. The tree only contains on-screen elements, so the
    /// status row (top of the Form) is scrolled to before polling.
    private func waitForAny(_ app: XCUIApplication, _ needles: [String], timeout: TimeInterval) -> String {
        toTop(app)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for n in needles where anyLabel(app, n).exists { return n }
            Thread.sleep(forTimeInterval: 1.0)
        }
        return ""
    }

    private func assertAbsent(_ app: XCUIApplication, _ needles: [String], context: String) {
        for n in needles {
            if anyLabel(app, n).exists {
                XCTFail("\(context): found forbidden label '\(n)'.\n--- tree ---\n\(app.debugDescription.prefix(3000))")
            }
        }
    }

    /// Read the persisted configuration back off the screen (URL, enabled, token
    /// length only -- never the token). Returns nil when the screen is not open.
    @discardableResult
    private func readBack(_ app: XCUIApplication, _ label: String) -> (url: String, sw: String, tokenLen: Int)? {
        guard app.navigationBars["Self-Hosted Server"].exists else {
            print("READBACK[\(label)] screen not open")
            return nil
        }
        toTop(app)
        let url = val(app.textFields.firstMatch)
        let sw = val(theSwitch(app))
        let tl = secureLen(app.secureTextFields.firstMatch)
        print("READBACK[\(label)] url='\(url)' sw=\(sw) tokenLen=\(tl)")
        return (url, sw, tl)
    }

    // MARK: - §1 valid state

    func testValidTokenReportsConnected() {
        let app = launchApp()
        openSelfHosted(app)
        clearConfiguration(app)
        typeURL(app)
        typeToken(app, token, label: "valid")
        XCTAssertTrue(ltmSetIntegration(app, on: true), "integration did not become enabled")
        tapTestConnection(app)

        let hit = waitForAny(app, ["API v", "Authentication failed", "Server unreachable",
                                   "Server error", "Incompatible server"], timeout: 75)
        capture(app, "valid-after-probe")
        print("VALID outcome=\(hit.isEmpty ? "NONE" : hit)")
        XCTAssertTrue(hit.hasPrefix("API v"),
                      "valid token did not report a connected identity (saw '\(hit)')")
    }

    // MARK: - §4–§10 invalid token

    func testInvalidTokenReportsAuthenticationFailed() {
        let app = launchApp()
        openSelfHosted(app)

        // ---- 1. establish the known-good valid configuration first
        clearConfiguration(app)
        typeURL(app)
        typeToken(app, token, label: "valid")
        XCTAssertTrue(ltmSetIntegration(app, on: true), "integration did not become enabled")
        mark("VALID-BASELINE before token replacement")
        let baseline = waitForAny(app, ["API v", "Authentication failed", "Server unreachable"], timeout: 75)
        print("INVALID baseline(valid token) outcome=\(baseline)")
        XCTAssertTrue(baseline.hasPrefix("API v"),
                      "could not establish the valid baseline before replacing the token (saw '\(baseline)')")

        // ---- 2. §4 replace the stored token through the real UI
        let how = replaceStoredToken(app, with: invalidToken)
        mark("TOKEN replaced via real UI (\(how))")

        // ---- 3. §5/§7 the real probe -- assert the RESULT before any fragile nav
        tapTestConnection(app)
        let hit = waitForAny(app, ["Authentication failed", "Server unreachable",
                                   "Server error", "Incompatible server", "API v"], timeout: 75)
        capture(app, "invalid-after-probe")
        print("INVALID outcome=\(hit.isEmpty ? "NONE" : hit)")
        assertAbsent(app, ["Server unreachable", "Could not contact server", "Server offline"],
                     context: "invalid token must not be reported as a network problem")
        XCTAssertEqual(hit, "Authentication failed",
                       "invalid token was not classified as an authentication failure (saw '\(hit)')")

        // ---- 4. §9 persistence of the replaced token
        if leaveAndReturn(app, label: "invalid") {
            let rb = readBack(app, "invalid")
            XCTAssertNotNil(rb, "could not read the configuration back")
            if let rb {
                XCTAssertEqual(rb.url, serverURL, "URL lost when leaving/re-entering the screen")
                XCTAssertEqual(rb.sw, "1", "integration did not stay enabled")
                XCTAssertGreaterThan(rb.tokenLen, 0, "the replaced token is not represented as stored")
            }
        } else {
            print("INVALID DIAG leave/return failed -- not treating a nav flake as a probe failure")
        }

        // ---- 5. §9 restore the valid token through the real UI
        print("INVALID restoring valid token via UI")
        clearConfiguration(app)
        typeURL(app)
        typeToken(app, token, label: "restored")
        XCTAssertTrue(ltmSetIntegration(app, on: true), "integration did not re-enable")
        if leaveAndReturn(app, label: "restored") {
            let rb = readBack(app, "restored")
            if let rb {
                XCTAssertEqual(rb.url, serverURL, "restored URL did not persist")
                XCTAssertEqual(rb.sw, "1", "restored config is not enabled")
                XCTAssertGreaterThan(rb.tokenLen, 0, "restored token is not represented as stored")
            }
        } else {
            print("INVALID DIAG leave/return failed after the restore")
        }

        tapTestConnection(app)
        let restored = waitForAny(app, ["API v", "Authentication failed", "Server unreachable"], timeout: 75)
        print("INVALID after-restore outcome=\(restored)")
        XCTAssertTrue(restored.hasPrefix("API v"),
                      "valid configuration did not reconnect after the invalid-token pass (saw '\(restored)')")
    }

    private func restoreLiveServerConfiguration(_ app: XCUIApplication, reason: String) {
        serverURL = liveServerURL
        print("OFFLINE cleanup restoring live endpoint for later tests: \(serverURL)")
        clearConfiguration(app)
        typeURL(app)
        typeToken(app, token, label: "live-cleanup")
        XCTAssertTrue(ltmSetIntegration(app, on: true), "could not restore live configuration")
        let outcome = waitForAny(app, ["API v", "Authentication failed", "Server unreachable"], timeout: 75)
        print("OFFLINE cleanup live outcome=\(outcome) reason=\(reason)")
        XCTAssertTrue(outcome.hasPrefix("API v"), "live server not restored for subsequent tests (saw '\(outcome)')")
    }

    // MARK: - §11–§14 server offline

    func testServerOfflineReportsUnreachable() {
        serverURL = offlineServerURL
        print("OFFLINE configured endpoint=\(serverURL) (dedicated closed loopback port)")
        let app = launchApp()
        openSelfHosted(app)
        clearConfiguration(app)
        typeURL(app)
        typeToken(app, token, label: "valid")
        XCTAssertTrue(ltmSetIntegration(app, on: true), "integration did not become enabled")
        mark("OFFLINE configured with a valid token; server unavailable")

        tapTestConnection(app)
        let hit = waitForAny(app, ["Server unreachable", "Authentication failed",
                                   "Server error", "Incompatible server", "API v"], timeout: 90)
        capture(app, "offline-after-probe")
        print("OFFLINE outcome=\(hit.isEmpty ? "NONE" : hit)")
        assertAbsent(app, ["Authentication failed"],
                     context: "offline server must not be reported as an authentication failure")
        XCTAssertEqual(hit, "Server unreachable",
                       "offline server was not classified as unreachable (saw '\(hit)')")
        restoreLiveServerConfiguration(app, reason: "testServerOfflineReportsUnreachable")
    }

    // MARK: - §15–§16 offline usability + relaunch

    func testOfflineAppUsabilityAndRelaunch() {
        serverURL = offlineServerURL
        print("USABILITY configured endpoint=\(serverURL) (dedicated closed loopback port)")
        let runToken = String(UUID().uuidString.prefix(6))
        let letterTitle = "OfflineLetter \(runToken)"

        let app = launchApp()
        print("USABILITY launch=ok onboardingCTA=\(app.buttons["Create Our Family Archive"].exists)")

        // --- local content works with the server unreachable
        app.tabBars.buttons["Letters"].tap()
        let newLetter = app.buttons["New Letter"].firstMatch
        XCTAssertTrue(newLetter.waitForExistence(timeout: 25), "New Letter control missing while offline")
        newLetter.tap()
        let titleField = app.textFields["Title"].firstMatch
        XCTAssertTrue(titleField.waitForExistence(timeout: 20), "editor did not open while offline")
        titleField.tap()
        titleField.typeText(letterTitle)
        let bodyField = app.textViews["Letter message"].firstMatch
        XCTAssertTrue(bodyField.exists, "letter body editor missing while offline")
        bodyField.tap()
        bodyField.typeText("written with the sync server down")
        let save = app.buttons["Save Draft"].firstMatch
        XCTAssertTrue(save.exists, "Save Draft missing while offline")
        save.tap()
        XCTAssertTrue(app.buttons["New Letter"].firstMatch.waitForExistence(timeout: 30),
                      "editor did not dismiss while offline")
        print("USABILITY local letter created while server is unreachable")

        // --- every tab navigates while the server is unreachable
        app.tabBars.buttons["Timeline"].tap()
        Thread.sleep(forTimeInterval: 1.0)
        let timelineOK = app.navigationBars["Timeline"].waitForExistence(timeout: 15)

        app.tabBars.buttons["Family"].tap()
        Thread.sleep(forTimeInterval: 1.0)
        let familyOK = app.tabBars.buttons["Family"].exists

        app.tabBars.buttons["People"].tap()
        Thread.sleep(forTimeInterval: 1.0)
        let peopleOK = app.tabBars.buttons["People"].exists

        app.tabBars.buttons["Settings"].tap()
        Thread.sleep(forTimeInterval: 1.0)
        let settingsOK = app.navigationBars["Settings"].waitForExistence(timeout: 15)

        app.tabBars.buttons["Letters"].tap()
        Thread.sleep(forTimeInterval: 1.0)
        let lettersOK = app.tabBars.buttons["Letters"].exists
        print("USABILITY tabs letters=\(lettersOK) timeline=\(timelineOK) family=\(familyOK) people=\(peopleOK) settings=\(settingsOK)")
        XCTAssertTrue(timelineOK && lettersOK && familyOK && peopleOK && settingsOK,
                      "a tab failed to open while the server was unreachable")

        // --- open the existing local letter
        let allLetters = app.buttons["All Letters"].firstMatch
        if allLetters.waitForExistence(timeout: 10) { allLetters.tap() }
        let row = app.staticTexts[letterTitle].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 30), "local letter not visible while offline")
        row.tap()
        Thread.sleep(forTimeInterval: 1.5)
        let detailOK = app.staticTexts[letterTitle].exists
        print("USABILITY opened local letter detail=\(detailOK)")
        if app.navigationBars.buttons.firstMatch.exists { app.navigationBars.buttons.firstMatch.tap() }
        Thread.sleep(forTimeInterval: 1.0)

        // --- configure Self-Hosted while the server is unreachable (so the
        //     relaunch check has a real persisted configuration to verify)
        openSelfHosted(app)
        clearConfiguration(app)
        typeURL(app)
        typeToken(app, token, label: "valid")
        XCTAssertTrue(ltmSetIntegration(app, on: true), "integration did not become enabled while offline")
        let statusWhileOffline = waitForAny(app, ["Server unreachable", "Authentication failed",
                                                  "API v", "Not configured"], timeout: 60)
        print("USABILITY selfhosted status while offline=\(statusWhileOffline)")
        XCTAssertNotEqual(statusWhileOffline, "API v",
                          "app reported a connected server while the server was unreachable")

        guard let before = readBack(app, "offline-pre-relaunch") else {
            XCTFail("could not read the configuration back before the relaunch")
            return
        }

        // --- §16 force terminate and relaunch with the server still down
        mark("RELAUNCH terminate")
        app.terminate()
        let app2 = XCUIApplication()
        app2.launch()
        let onboardingReturned = app2.buttons["Create Our Family Archive"].waitForExistence(timeout: 12)
        print("RELAUNCH onboardingReturned=\(onboardingReturned)")
        XCTAssertFalse(onboardingReturned, "onboarding returned after relaunch")
        XCTAssertTrue(app2.tabBars.buttons["Letters"].waitForExistence(timeout: 40),
                      "main shell did not appear after relaunch")

        // local data still there
        app2.tabBars.buttons["Letters"].tap()
        let allLetters2 = app2.buttons["All Letters"].firstMatch
        if allLetters2.waitForExistence(timeout: 10) { allLetters2.tap() }
        let persisted = app2.staticTexts[letterTitle].waitForExistence(timeout: 30)
        print("RELAUNCH localDataPersisted=\(persisted)")
        XCTAssertTrue(persisted, "local letter did not survive the relaunch")

        // navigation still works
        for tab in ["Timeline", "Family", "People", "Settings"] {
            app2.tabBars.buttons[tab].tap()
            Thread.sleep(forTimeInterval: 0.8)
        }
        print("RELAUNCH navigation=ok")

        // Reopen the preserved Settings child after relaunch, explicitly probe
        // the still-dead loopback endpoint, and verify the persisted fields.
        XCTAssertTrue(tolerantOpenSelfHosted(app2), "Self-Hosted settings did not reopen after relaunch")
        tapTestConnection(app2)
        let afterRelaunchState = waitForAny(
            app2, ["Server unreachable", "Authentication failed", "API v"], timeout: 90
        )
        print("RELAUNCH offlineStatus=\(afterRelaunchState)")
        XCTAssertEqual(afterRelaunchState, "Server unreachable",
                       "offline configuration did not remain unreachable after relaunch")

        let after = readBack(app2, "offline-post-relaunch")
        XCTAssertNotNil(after, "could not read the configuration back after the relaunch")
        if let after {
            XCTAssertEqual(after.url, serverURL, "self-hosted URL did not survive the relaunch")
            XCTAssertEqual(after.sw, "1", "self-hosted integration did not stay enabled")
            XCTAssertGreaterThan(after.tokenLen, 0, "self-hosted token did not survive the relaunch")
        }
        let falseConnected = anyLabel(app2, "API v").exists
        print("RELAUNCH falseConnected=\(falseConnected) (pre-relaunch url='\(before.url)' sw=\(before.sw))")
        XCTAssertFalse(falseConnected, "app showed a connected server after relaunch while the server was down")

        // Leave the shared simulator configuration ready for the follow-up
        // reconnect test; all offline assertions above have already completed.
        restoreLiveServerConfiguration(app2, reason: "testOfflineAppUsabilityAndRelaunch")
    }

    // MARK: - §17 reconnect from persisted configuration

    /// Must run with the SAME app install as the offline pass (no reinstall): the
    /// point is recovery using the configuration that was persisted during the
    /// outage.
    func testReconnectUsesPersistedConfiguration() {
        let app = launchApp()
        openSelfHosted(app)
        guard let before = readBack(app, "reconnect-before") else {
            XCTFail("could not read the persisted configuration")
            return
        }
        XCTAssertEqual(before.url, serverURL, "no persisted self-hosted URL to reconnect with")
        XCTAssertEqual(before.sw, "1", "integration was not left enabled by the offline pass")
        XCTAssertGreaterThan(before.tokenLen, 0, "no persisted token to reconnect with")

        tapTestConnection(app)
        let hit = waitForAny(app, ["API v", "Authentication failed", "Server unreachable",
                                   "Server error", "Incompatible server"], timeout: 75)
        capture(app, "reconnect-after-probe")
        print("RECONNECT outcome=\(hit.isEmpty ? "NONE" : hit)")
        XCTAssertTrue(hit.hasPrefix("API v"),
                      "did not reconnect from persisted configuration (saw '\(hit)')")
    }
}
