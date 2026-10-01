import XCTest

/// §5 isolated identity probe: valid server + valid token -> connected.
///
/// ORDERING IS DELIBERATE: configure -> tap -> observe. A previous run died in a
/// navigation helper BEFORE the probe was tapped, producing zero evidence about
/// the probe itself; persistence checks are therefore demoted to printed
/// diagnostics that cannot abort the probe sequence.
///
/// Three harness defects each produced a false "product" failure earlier in this
/// audit, and each is handled explicitly here:
///   1. typing into a `.disabled(config.enabled)` field silently does nothing;
///   2. the accessibility tree contains only ON-SCREEN elements, so a scrolled
///      Form or an on-screen keyboard reports existing controls as MISSING;
///   3. "the placeholder disappeared" is NOT proof the text stuck (§11) -- values
///      are read back and compared against the exact intended string.
final class IdentityProbeUITests: XCTestCase {

    private var serverURL = "http://127.0.0.1:8080"
    private var token = ""

    override func setUpWithError() throws {
        continueAfterFailure = false
        let env = ProcessInfo.processInfo.environment
        if let u = env["LTM_SERVER_URL"], !u.isEmpty { serverURL = u }
        if let t = env["LTM_SERVER_TOKEN"], !t.isEmpty {
            token = t
        } else if let f = env["LTM_SERVER_ENV_FILE"] {
            token = Self.tokenFromFile(f)
        }
        // Non-secret: the URL must be visible, the token never is.
        print("TESTCFG serverURL=\(serverURL) tokenLen=\(token.count)")
        if token.isEmpty {
            throw NSError(domain: "IdentityProbeUITests", code: 1, userInfo: [
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

    // MARK: - helpers

    private func val(_ e: XCUIElement) -> String {
        guard e.exists else { return "<MISSING>" }
        return (e.value as? String) ?? "<nil>"
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

    /// Dismiss the software keyboard. Under XCUITest a hardware keyboard is often
    /// active (keyboards.count == 0), in which case nothing covers the form.
    private func dismissKeyboard(_ app: XCUIApplication) {
        guard app.keyboards.count > 0 else { return }
        if app.keyboards.buttons["Done"].exists { app.keyboards.buttons["Done"].tap() }
        else if app.keyboards.buttons["Return"].exists { app.keyboards.buttons["Return"].tap() }
        else { app.swipeDown() }
        Thread.sleep(forTimeInterval: 0.6)
    }

    /// The Enable switch, matched by label so a stray switch cannot be picked up.
    private func theSwitch(_ app: XCUIApplication) -> XCUIElement {
        let byLabel = app.switches
            .matching(NSPredicate(format: "label CONTAINS %@", "Enable Self-Hosted")).firstMatch
        return byLabel.exists ? byLabel : app.switches.firstMatch
    }

    private func capture(_ app: XCUIApplication, _ stage: String) {
        // debugDescription is one bounded snapshot; enumerating live element
        // arrays can throw when the hierarchy mutates mid-iteration.
        let desc = app.debugDescription
            .replacingOccurrences(of: "\n", with: " ~ ")
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

    /// Navigate with the shared state-aware helper. The Settings stack may still
    /// be pushed after a previous test or process relaunch.
    private func openSelfHosted(_ app: XCUIApplication) {
        dismissKeyboard(app)
        XCTAssertTrue(ltmOpenSettingsRow(app, row: "Self-Hosted Server"),
                      "could not normalize Settings and open Self-Hosted Server")
    }

    // MARK: - the single test

    func testValidServerReportsConnected() {
        let app = launchApp()
        openSelfHosted(app)
        toTop(app)

        // Use the shared keyboard-aware configuration path: direct typeText calls
        // occasionally lost focus during simulator-driven navigation.
        ltmClearConfiguration(app)
        ltmTypeURL(app, serverURL)
        let urlRead = val(app.textFields.firstMatch)
        let tokLen = ltmTypeToken(app, token, label: "valid-server")
        XCTAssertEqual(tokLen, token.count, "server token did not stick in the secure field")

        // Enabling with a complete config auto-runs the probe via .onChange.
        XCTAssertTrue(ltmDismissKnownBlockingSheet(app),
                      "known password-autofill sheet could not be dismissed safely")
        XCTAssertTrue(ltmSetIntegration(app, on: true), "integration did not become enabled")
        let sw2 = theSwitch(app)
        print("CFG configured url='\(urlRead)' sw=\(val(sw2)) tokenLen=\(tokLen)")
        capture(app, "after-configure")

        // ---- 6. tap Test Connection (the observable probe trigger)
        dismissKeyboard(app)
        XCTAssertTrue(scrollTo(app, "Test Connection"), "'Test Connection' not found")
        let probe = app.buttons["Test Connection"]
        XCTAssertTrue(probe.waitForExistence(timeout: 15), "Test Connection button missing")
        print("PROBE tapButton enabled=\(probe.isEnabled) at \(Date())")
        if probe.isEnabled {
            probe.tap()
        } else {
            probe.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        print("PROBE tapped at \(Date())")

        // ---- 7. poll for a terminal state (scroll so off-screen states are seen)
        let deadline = Date().addingTimeInterval(75)
        var success = false
        var failure = ""
        while Date() < deadline {
            if anyLabel(app, "API v").exists || anyLabel(app, "Capabilities:").exists {
                success = true
                break
            }
            for f in ["Authentication failed", "Server unreachable", "Server error", "Incompatible server"] {
                if anyLabel(app, f).exists { failure = f; break }
            }
            if !failure.isEmpty { break }
            Thread.sleep(forTimeInterval: 1.0)
        }
        capture(app, "after-probe")
        print("PROBE outcome success=\(success) failureLabel='\(failure)'")

        // ---- 8. persistence diagnostics AFTER the probe (cannot mask it now)
        if let back = app.navigationBars["Self-Hosted Server"].buttons.firstMatch as XCUIElement?,
           back.exists {
            back.tap()
            _ = app.navigationBars["Settings"].waitForExistence(timeout: 20)
            _ = tolerantOpenSelfHosted(app)
            print("CFG afterReturn url='\(val(app.textFields.firstMatch))' sw=\(val(theSwitch(app))) tokenLen=\((val(app.secureTextFields.firstMatch) as NSString).length)")
        }

        XCTAssertTrue(success,
            "no connected evidence within 75s (failure label: '\(failure)'). Correlate the "
            + "selfhosted-probe oslog and the proxy request log to find which layer stalled.")
    }

    /// §15 the real persistence path.
    ///
    /// `SelfHostedConfig.shared` is a singleton, so an in-process readback keeps
    /// the token in memory even if the Keychain WRITE silently failed. Only a
    /// process relaunch forces a read-back from storage, which is what makes this
    /// the real test of Keychain write+read. The whole point: if the token is gone
    /// after relaunch then `isConfigured` is false, `testConnection()` short-circuits
    /// at its guard, and no probe can ever run — with no visible explanation.
    func testConfigurationSurvivesRelaunch() {
        let app = launchApp()
        openSelfHosted(app)
        toTop(app)

        // Configure through the shared, keyboard-aware harness primitives. A
        // direct typeText after tap lost keyboard focus on this path; secure
        // fields may also trigger the known, explicitly-dismissed AutoFill sheet.
        ltmClearConfiguration(app)
        ltmTypeURL(app, serverURL)
        let tokenLength = ltmTypeToken(app, token, label: "identity-relaunch")
        XCTAssertEqual(tokenLength, token.count, "server token did not stick in the secure field")
        XCTAssertTrue(ltmDismissKnownBlockingSheet(app),
                      "known password-autofill sheet could not be dismissed safely")
        XCTAssertTrue(ltmSetIntegration(app, on: true), "integration did not become enabled")
        print("PERSIST configured url='\(val(app.textFields.firstMatch))' sw=\(val(theSwitch(app))) tokenLen=\((val(app.secureTextFields.firstMatch) as NSString).length)")

        // ---- kill the process: the only step that forces a read from storage
        app.terminate()
        let app2 = XCUIApplication()
        app2.launch()
        let cta = app2.buttons["Create Our Family Archive"]
        if cta.waitForExistence(timeout: 15) { cta.tap() }
        XCTAssertTrue(app2.tabBars.buttons["Letters"].waitForExistence(timeout: 40),
                      "main shell did not appear after relaunch")
        openSelfHosted(app2)
        toTop(app2)

        let url = val(app2.textFields.firstMatch)
        let swRead = val(theSwitch(app2))
        let tokLen = (val(app2.secureTextFields.firstMatch) as NSString).length
        print("PERSIST afterRelaunch url='\(url)' sw=\(swRead) tokenLen=\(tokLen) expectedUrl='\(serverURL)'")

        XCTAssertEqual(url, serverURL, "URL did not survive relaunch (UserDefaults read path)")
        XCTAssertGreaterThan(tokLen, 0,
            "token did NOT survive relaunch -- the Keychain write failed silently, so "
            + "isConfigured is false and no probe can ever start")

        // ---- and it must still connect on the relaunched instance
        dismissKeyboard(app2)
        XCTAssertTrue(scrollTo(app2, "Test Connection"), "'Test Connection' not found after relaunch")
        let probe = app2.buttons["Test Connection"]
        XCTAssertTrue(probe.waitForExistence(timeout: 15), "Test Connection missing after relaunch")
        print("PROBE(relaunch) enabled=\(probe.isEnabled) at \(Date())")
        if probe.isEnabled { probe.tap() }
        else { probe.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }

        let deadline = Date().addingTimeInterval(75)
        var success = false
        var failure = ""
        while Date() < deadline {
            if anyLabel(app2, "API v").exists || anyLabel(app2, "Capabilities:").exists { success = true; break }
            for f in ["Authentication failed", "Server unreachable", "Server error", "Incompatible server"] {
                if anyLabel(app2, f).exists { failure = f; break }
            }
            if !failure.isEmpty { break }
            Thread.sleep(forTimeInterval: 1.0)
        }
        capture(app2, "after-relaunch-probe")
        print("PROBE(relaunch) outcome success=\(success) failureLabel='\(failure)'")
        XCTAssertTrue(success, "did not connect after relaunch (failure label: '\(failure)')")
    }

    /// Non-fatal counterpart to `openSelfHosted` for POST-PROBE diagnostics.
    /// Uses the same stack normalization but keeps the probe result authoritative.
    @discardableResult
    private func tolerantOpenSelfHosted(_ app: XCUIApplication) -> Bool {
        dismissKeyboard(app)
        let opened = ltmOpenSettingsRow(app, row: "Self-Hosted Server")
        if !opened { print("DIAG shared Settings navigation could not reopen Self-Hosted") }
        return opened
    }
}
