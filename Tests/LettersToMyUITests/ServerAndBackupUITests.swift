import XCTest

/// Server-side runtime proof: the SelfHostedSync connection states plus a
/// backup-to-server smoke, driven through the real UI.
///
/// History: an earlier revision of this file reported "4/4 green" while in fact
/// executing four FAILURES. It predated every interaction lesson this audit
/// learned, so it failed in *setup* (after a scroll-position mismatch the
/// trailing-edge toggle tap landed on the navigation bar) and never reached
/// product code — zero requests on the wire. It is now built on the shared
/// `SelfHostedUITestSupport` helpers that encode those lessons, so a red result
/// here means a real problem rather than a harness artefact.
///
/// Requires a live SelfHostedSync server. Absent configuration is a HARD
/// FAILURE, not a skip, so this cannot report green while proving nothing.
final class ServerAndBackupUITests: XCTestCase {

    private var baseURL = "http://127.0.0.1:8081"
    private var token = ""

    override func setUpWithError() throws {
        continueAfterFailure = false
        baseURL = ltmServerURL()
        token = try ltmRequireToken()
        print("TESTCFG serverURL=\(baseURL) tokenLen=\(token.count)")
    }

    private func launchConfigured() -> XCUIApplication {
        let app = ltmLaunch(XCUIApplication())
        ltmConfigureSelfHosted(app, url: baseURL, token: token)
        return app
    }

    // MARK: - connection states

    /// Valid token: the probe must report a real connected identity and the
    /// capabilities it exercised.
    func testSelfHosted_validToken_reportsConnectedWithCapabilities() {
        let app = launchConfigured()
        let outcome = ltmWaitForConnected(app, timeout: 75)
        ltmCapture(app, "valid-after-probe")
        print("SERVERSUITE valid outcome=\(outcome)")
        XCTAssertTrue(outcome.hasPrefix("API v"),
                      "valid token did not report a connected identity (saw '\(outcome)')")

        ltmToTop(app)
        XCTAssertTrue(ltmAnyLabel(app, "Capabilities:").exists,
                      "capabilities were not surfaced: \(ltmVisibleTexts(app))")
    }

    /// Invalid token: a visible authentication error, never a bare-200 success,
    /// and never misreported as a network problem.
    func testSelfHosted_invalidToken_reportsAuthFailure() {
        let app = ltmLaunch(XCUIApplication())
        ltmOpenSelfHosted(app)
        ltmClearConfiguration(app)
        ltmTypeURL(app, baseURL)
        ltmTypeToken(app, "definitely-not-a-valid-token", label: "invalid")
        XCTAssertTrue(ltmSetIntegration(app, on: true), "integration did not become enabled")

        let outcome = ltmWaitForConnected(app, timeout: 75)
        ltmCapture(app, "invalid-after-probe")
        print("SERVERSUITE invalid outcome=\(outcome)")
        ltmAssertAbsent(app, ["Server unreachable", "Could not contact server", "Server offline"],
                        context: "invalid token must not be reported as a network problem")
        XCTAssertEqual(outcome, "Authentication failed",
                       "invalid token was not classified as an authentication failure (saw '\(outcome)')")
    }

    /// Unreachable server: explicit offline state, and the app stays usable.
    func testSelfHosted_unreachableServer_reportsOffline_andAppStaysUsable() {
        let app = ltmLaunch(XCUIApplication())
        // Port 9 on loopback: nothing listens.
        ltmConfigureSelfHosted(app, url: "http://127.0.0.1:9", token: "irrelevant")

        let outcome = ltmWaitForConnected(app, timeout: 90)
        ltmCapture(app, "offline-after-probe")
        print("SERVERSUITE offline outcome=\(outcome)")
        ltmAssertAbsent(app, ["Authentication failed"],
                        context: "an unreachable server must not report an authentication failure")
        XCTAssertTrue(outcome.hasPrefix("Server unreachable"),
                      "unreachable server not reported as offline (saw '\(outcome)')")

        // Unrelated functionality keeps working with the server down.
        app.tabBars.buttons["Letters"].tap()
        XCTAssertTrue(
            app.buttons["New Letter"].firstMatch.waitForExistence(timeout: 20)
                || app.staticTexts["All Letters"].waitForExistence(timeout: 20),
            "the app became unusable while the server was down"
        )
    }

    // MARK: - backup smoke

    /// The Backups screen renders its real controls, accepts a passphrase, and
    /// offers the self-hosted destination plus its restore entry. The full
    /// upload/list/preview/restore journey lives in `BackupJourneyUITests`; this
    /// is the smoke that the surface exists and is reachable.
    func testBackup_screenReachableWithSelfHostedDestination() {
        let app = launchConfigured()
        let connected = ltmWaitForConnected(app, timeout: 60)
        XCTAssertTrue(connected.hasPrefix("API v"),
                      "server not connected; cannot exercise the backup screen (saw '\(connected)')")

        XCTAssertTrue(ltmOpenSettingsRow(app, row: "Manage Backups"), "'Manage Backups' row not found")
        XCTAssertTrue(app.navigationBars["Backups"].waitForExistence(timeout: 25),
                      "Backups screen did not open")
        ltmCapture(app, "backups-screen")

        let passphrase = app.secureTextFields["Passphrase"].firstMatch
        XCTAssertTrue(passphrase.waitForExistence(timeout: 20), "passphrase field missing")
        passphrase.tap()
        passphrase.typeText("Runtime-Acceptance-Pass-42")
        ltmDismissKeyboard(app)

        let upNow = app.buttons["Back Up Now"].firstMatch
        XCTAssertTrue(upNow.waitForExistence(timeout: 20),
                      "no 'Back Up Now' control: \(ltmVisibleTexts(app))")

        XCTAssertTrue(ltmScrollTo(app, "Restore from Self-Hosted Server"),
                      "self-hosted restore entry not offered: \(ltmVisibleTexts(app))")
    }
}
