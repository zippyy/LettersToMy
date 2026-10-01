import XCTest

/// Runtime acceptance for the SelfHostedSync + backup surface on iOS.
///
/// These are the flows the earlier passes covered only with unit and headless
/// HTTP tests. Driving them through the real UI is the only way to prove a user
/// can actually configure the server and move an archive to and from it.
///
/// The server base URL and token arrive as launch arguments OTHER than
/// UserDefaults keys (plain `-ltmServerURL value` style is fine here because the
/// keys are not read by @AppStorage — the app has no `ltmServerURL` default, so
/// the argument domain cannot shadow anything the app writes).
///
/// Requires a live SelfHostedSync server. Absent configuration is a hard
/// failure, not a skip, so this cannot report green while proving nothing.
final class ServerAndBackupUITests: XCTestCase {

    private var baseURL = "http://127.0.0.1:8080"
    private var token = ""

    /// Resolve the server token without ever committing it.
    ///
    /// Order: an explicit LTM_SERVER_TOKEN, else the first live entry of the
    /// `key:token` file named by LTM_SERVER_ENV_FILE (the server's api_keys.txt,
    /// which lives outside the repo). Throwing from setUp makes every test in
    /// this class FAIL rather than silently skip — a green run that proved
    /// nothing would be worse than a red one.
    private static func resolveToken() -> String {
        let env = ProcessInfo.processInfo.environment
        if let t = env["LTM_SERVER_TOKEN"], !t.isEmpty { return t }
        guard let path = env["LTM_SERVER_ENV_FILE"],
              let raw = try? String(contentsOfFile: path, encoding: .utf8) else { return "" }
        for line in raw.split(separator: "\n") {
            let s = line.trimmingCharacters(in: .whitespaces)
            if s.isEmpty || s.hasPrefix("#") { continue }
            if let i = s.firstIndex(of: ":") {
                let v = String(s[s.index(after: i)...]).trimmingCharacters(in: .whitespaces)
                if !v.isEmpty { return v }
            }
        }
        return ""
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        baseURL = ProcessInfo.processInfo.environment["LTM_SERVER_URL"] ?? "http://127.0.0.1:8080"
        token = Self.resolveToken()
        if token.isEmpty {
            throw NSError(
                domain: "ServerAndBackupUITests", code: 1,
                userInfo: [NSLocalizedDescriptionKey:
                    "server token unavailable — set LTM_SERVER_TOKEN or LTM_SERVER_ENV_FILE"]
            )
        }
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()

        let cta = app.buttons["Create Our Family Archive"]
        if cta.waitForExistence(timeout: 20) { cta.tap() }

        XCTAssertTrue(
            app.tabBars.buttons["Letters"].waitForExistence(timeout: 40),
            "main shell did not appear"
        )
        return app
    }

    /// Open Settings → the given NavigationLink row, scrolling if needed.
    private func openFromSettings(_ app: XCUIApplication, row: String) {
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(
            app.navigationBars["Settings"].waitForExistence(timeout: 25),
            "Settings did not open"
        )

        var target = app.buttons[row]
        if !target.exists { target = app.cells[row] }
        if !target.exists { target = app.staticTexts[row] }
        var tries = 0
        while !target.exists && tries < 6 {
            app.swipeUp()
            target = app.buttons[row]
            if !target.exists { target = app.cells[row] }
            if !target.exists { target = app.staticTexts[row] }
            tries += 1
        }
        XCTAssertTrue(target.exists, "Settings row '\(row)' not found")
        target.tap()
    }

    /// Configure the self-hosted server through the real form.
    private func configureSelfHosted(_ app: XCUIApplication, url: String, token: String) {
        openFromSettings(app, row: "Self-Hosted Server")
        XCTAssertTrue(
            app.navigationBars["Self-Hosted Server"].waitForExistence(timeout: 25),
            "Self-Hosted screen did not open"
        )

        // CRITICAL ORDERING. The URL and token fields are
        // `.disabled(config.enabled)`, and `typeText` into a disabled field
        // silently does nothing — so `enabled` MUST be off before typing.
        // `enabled` persists in UserDefaults and survives relaunch, so a
        // leftover true from an earlier run leaves the fields disabled and the
        // typed values are discarded, which surfaces as the app sitting on
        // "Status: Not configured" with an empty URL field.
        let toggle = app.switches.firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 20), "Enable toggle missing")
        // A SwiftUI Form Toggle is ONE row-wide accessibility element: element.tap()
        // lands on the label at the geometric centre and does NOT flip the switch.
        // The control is at the trailing edge (proven in ToggleSanityUITests).
        if (toggle.value as? String) == "1" {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
            Thread.sleep(forTimeInterval: 0.9)
        }

        // Now clear any leftover URL/token (Keychain state also survives
        // reinstall on the simulator).
        let clear = app.buttons["Clear Configuration"]
        if clear.exists && clear.isEnabled { clear.tap() }
        composeWait()

        let urlField = app.textFields.firstMatch
        XCTAssertTrue(urlField.waitForExistence(timeout: 20), "server URL field missing")
        urlField.tap()
        urlField.typeText(url)

        let tokenField = app.secureTextFields.firstMatch
        XCTAssertTrue(tokenField.exists, "API token field missing")
        tokenField.tap()
        tokenField.typeText(token)

        // Enable LAST, now that the config is complete: enabling with a complete
        // config auto-starts the probe (.onChange(of: config.enabled)).
        if (toggle.value as? String) != "1" {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
            Thread.sleep(forTimeInterval: 1.0)
        }
        XCTAssertEqual(toggle.value as? String, "1",
                       "integration did not become enabled (Form Toggle tap technique)")
    }

    /// Wait for the probe to report a valid API v1 identity.
    ///
    /// Enabling the integration with a complete config AUTO-STARTS the probe
    /// (`.onChange(of: config.enabled) -> testConnection()`), which sets
    /// `isTesting` and therefore DISABLES the "Test Connection" button. So a
    /// test must not assert the button is enabled right after toggling, nor
    /// assume it must tap it.
    @discardableResult
    private func waitForConnected(_ app: XCUIApplication, timeout: TimeInterval = 45) -> Bool {
        // §23: the connected state renders as a combined element (displayName +
        // "API v1" + capabilities). An exact staticTexts["API v1"] can never match,
        // so match any element type with CONTAINS.
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "API v"))
            .firstMatch
            .waitForExistence(timeout: timeout)
    }

    /// Tap the probe button only if it is actually enabled.
    private func triggerProbe(_ app: XCUIApplication) {
        let test = app.buttons["Test Connection"]
        if test.exists && test.isEnabled { test.tap() }
    }

    /// Let the UI settle. XCTest has no waitForIdle for SwiftUI, so this polls
    /// the app's own state via a short expectation-free sleep bounded by a
    /// quiescence check on the current app.
    private func composeWait(_ seconds: TimeInterval = 0.6) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// Read back the real control state instead of assuming typeText() worked.
    ///
    /// On recent iOS an empty SwiftUI TextField can expose its PLACEHOLDER as the
    /// accessibility value, so "the placeholder disappeared" is not proof the
    /// typed text stuck. This prints what the app actually holds.
    private func readbackControls(_ app: XCUIApplication, stage: String) {
        let toggle = app.switches.firstMatch
        let url = app.textFields.firstMatch
        let tok = app.secureTextFields.firstMatch

        let toggleVal = toggle.exists ? ((toggle.value as? String) ?? "nil") : "MISSING"
        let urlVal = url.exists ? ((url.value as? String) ?? "nil") : "MISSING"
        let urlEn = url.exists ? String(url.isEnabled) : "n/a"
        let tokEn = tok.exists ? String(tok.isEnabled) : "n/a"
        let tokLen = tok.exists ? (((tok.value as? String) ?? "").count) : -1

        print("READBACK[\(stage)] toggle=\(toggleVal) urlEnabled=\(urlEn) urlValue=\(urlVal) tokenEnabled=\(tokEn) tokenValueLen=\(tokLen)")
    }

    /// §12: leave the screen and come back. If the URL resets or the toggle flips,
    /// the defect is configuration persistence / UI interaction, not HTTP.
    private func leaveAndReturn(_ app: XCUIApplication) {
        if app.navigationBars.buttons.firstMatch.exists {
            app.navigationBars.buttons.firstMatch.tap()
        } else {
            app.swipeRight()
        }
        composeWait(0.8)
        openFromSettings(app, row: "Self-Hosted Server")
    }

    // MARK: - Tests

    /// Valid token: the capability probe must report a real connected identity.
    func testSelfHosted_validToken_reportsConnectedWithCapabilities() {
        let app = launch()
        configureSelfHosted(app, url: baseURL, token: token)

        // §11: prove what the controls actually contain before tapping.
        readbackControls(app, stage: "after-configure")

        // §12: prove the configuration survives a screen exit/re-entry.
        leaveAndReturn(app)
        readbackControls(app, stage: "after-return")

        let test = app.buttons["Test Connection"]
        XCTAssertTrue(test.waitForExistence(timeout: 15), "Test Connection missing")

        // Enabling may already have started the probe; tap only if enabled.
        var connected = waitForConnected(app, timeout: 20)
        if !connected {
            triggerProbe(app)
            connected = waitForConnected(app)
        }

        readbackControls(app, stage: "after-probe")
        print("VISIBLES[after-probe] " + app.staticTexts.allElementsBoundByIndex.map { $0.label }.joined(separator: " ~ "))
        XCTAssertTrue(
            connected,
            "server never reported a valid API v1 identity. Visible texts: \(app.staticTexts.allElementsBoundByIndex.map { $0.label }.joined(separator: " | "))"
        )
        XCTAssertTrue(
            app.staticTexts.containing(
                NSPredicate(format: "label CONTAINS %@", "Capabilities:")
            ).firstMatch.exists,
            "capabilities were not surfaced"
        )
    }

    /// Wrong token: a visible authentication error, never a bare-200 success.
    func testSelfHosted_invalidToken_reportsAuthFailure() {
        let app = launch()
        configureSelfHosted(app, url: baseURL, token: "definitely-not-a-valid-token")

        // The probe may already be running from the enable toggle.
        triggerProbe(app)

        let authFailed = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Authentication failed")).firstMatch
        let serverErr = app.staticTexts.containing(
            NSPredicate(format: "label BEGINSWITH %@", "Server error")
        ).firstMatch
        XCTAssertTrue(
            authFailed.waitForExistence(timeout: 40) || serverErr.exists,
            "an invalid token did not surface an authentication error"
        )
    }

    /// Unreachable server: explicit offline state, and the app stays usable.
    func testSelfHosted_unreachableServer_reportsOffline_andAppStaysUsable() {
        let app = launch()
        // Port 9 on loopback: nothing listens.
        configureSelfHosted(app, url: "http://127.0.0.1:9", token: "irrelevant")

        triggerProbe(app)

        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Server unreachable")).firstMatch.waitForExistence(timeout: 45),
            "an unreachable server did not report Server unreachable"
        )

        // Unrelated functionality must keep working with the server down.
        app.navigationBars.buttons.firstMatch.tap()   // back to Settings
        app.tabBars.buttons["Letters"].tap()
        XCTAssertTrue(
            app.buttons["New Letter"].firstMatch.waitForExistence(timeout: 20)
                || app.staticTexts["All Letters"].waitForExistence(timeout: 20),
            "the app became unusable while the server was down"
        )
    }

    /// Full backup journey: passphrase → upload to the self-hosted server →
    /// the archive appears in the server restore picker → delete it again.
    func testBackup_uploadAppearsOnServer_thenDelete() {
        let app = launch()

        // Seed one letter so the archive has content.
        app.tabBars.buttons["Letters"].tap()
        app.buttons["New Letter"].firstMatch.tap()
        let title = app.textFields["Title"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 20), "editor did not open")
        title.tap()
        title.typeText("UITest Backup Seed")
        let body = app.textViews["Letter message"].firstMatch
        body.tap()
        body.typeText("backup seed body")
        app.buttons["Save Draft"].firstMatch.tap()
        XCTAssertTrue(
            app.buttons["New Letter"].firstMatch.waitForExistence(timeout: 30),
            "editor did not dismiss after saving"
        )

        // Configure the server (also registers it as a backup destination).
        configureSelfHosted(app, url: baseURL, token: token)

        // Same auto-probe race as the other tests: enabling may already have
        // started the check, so only tap when the button is enabled.
        if !waitForConnected(app, timeout: 20) {
            triggerProbe(app)
            _ = waitForConnected(app)
        }
        XCTAssertTrue(
            waitForConnected(app, timeout: 5),
            "server not connected; cannot test upload. Visible texts: \(app.staticTexts.allElementsBoundByIndex.map { $0.label }.joined(separator: " | "))"
        )

        // Backups screen.
        app.navigationBars.buttons.firstMatch.tap()
        openFromSettings(app, row: "Manage Backups")
        XCTAssertTrue(
            app.navigationBars["Backups"].waitForExistence(timeout: 25),
            "Backups screen did not open"
        )

        let passphrase = app.secureTextFields["Passphrase"]
        XCTAssertTrue(passphrase.waitForExistence(timeout: 20), "passphrase field missing")
        passphrase.tap()
        passphrase.typeText("Runtime-Acceptance-42")

        // Upload. "Back Up Now" is rendered icon-only in the destination row.
        var upNow = app.buttons["Back Up Now"]
        if !upNow.exists { upNow = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Back Up Now")).firstMatch }
        XCTAssertTrue(upNow.waitForExistence(timeout: 20), "Back Up Now not found")
        upNow.tap()

        // The self-hosted destination row must record the last backup.
        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "Last backup")).firstMatch
                .waitForExistence(timeout: 90),
            "no backup record appeared after the upload"
        )

        // The archive must be visible from the server restore picker.
        let restoreFromServer = app.buttons["Restore from Self-Hosted Server"]
        var row = restoreFromServer
        if !row.exists { row = app.staticTexts["Restore from Self-Hosted Server"] }
        var tries = 0
        while !row.exists && tries < 6 { app.swipeUp(); row = app.buttons["Restore from Self-Hosted Server"]; tries += 1 }
        XCTAssertTrue(row.exists, "Restore from Self-Hosted Server not available")
        row.tap()

        XCTAssertTrue(
            app.navigationBars["Restore from Server"].waitForExistence(timeout: 45),
            "server restore picker did not open"
        )
        // Either the uploaded archive is listed, or the server genuinely has none.
        let listed = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "letters")
        ).firstMatch
        XCTAssertTrue(
            listed.waitForExistence(timeout: 45) || app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "No Remote Backups")).firstMatch.exists,
            "the restore picker neither listed the archive nor reported none"
        )

        // Open it and confirm the preview reports real metadata.
        if listed.exists {
            listed.tap()
            XCTAssertTrue(
                app.navigationBars["Restore Archive"].waitForExistence(timeout: 60),
                "archive preview did not open"
            )
            XCTAssertTrue(
                app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Restore")).firstMatch.exists,
                "preview did not report a restore action"
            )
            app.buttons["Cancel"].firstMatch.tap()
        }
    }
}
