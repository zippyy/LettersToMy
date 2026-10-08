import XCTest

/// The Backups surface: reachable, with a configured self-hosted destination and
/// its real controls present.
///
/// CONSOLIDATION (§11): this suite previously re-tested the three connection
/// states (`valid` / `invalid token` / `offline`) that `ConnectionStateUITests`
/// already owns as a strict superset — it covers the same three conditions plus
/// relaunch persistence and post-outage reconnection. Keeping both meant two
/// copies of the same contract, maintained twice, and the duplicated copy is
/// where a field-clearing defect in the shared helper silently broke all four
/// tests. The connection-state tests were therefore REMOVED from here, not
/// fixed into a parallel existence.
///
/// Retained coverage (all in `ConnectionStateUITests`):
///   valid token      -> testValidTokenReportsConnected
///   invalid token    -> testInvalidTokenReportsAuthenticationFailed
///   offline server   -> testServerOfflineReportsUnreachable
///   relaunch offline -> testOfflineAppUsabilityAndRelaunch
///   reconnect        -> testReconnectUsesPersistedConfiguration
///
/// What is left here is the one contract nothing else proves cheaply: the
/// Backups screen itself opens, offers the self-hosted destination, accepts a
/// passphrase, and enables its upload + restore controls. `BackupJourneyUITests`
/// drives the same screen but only as part of a ~13-minute seeded journey; this
/// is the fast, independent check that the surface is intact.
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

    /// The Backups screen renders its real controls, accepts a passphrase, and
    /// offers the self-hosted destination plus its restore entry.
    func testBackup_screenReachableWithSelfHostedDestination() {
        let app = launchConfigured()
        let connected = ltmWaitForConnected(app, timeout: 60)
        XCTAssertTrue(connected.hasPrefix("API v"),
                      "server not connected; cannot exercise the backup screen (saw '\(connected)')")

        XCTAssertTrue(ltmOpenSettingsRow(app, row: "Manage Backups"), "'Manage Backups' row not found")
        XCTAssertTrue(ltmBackupDestinationAppeared(app),
                      "Backups destination did not open")
        ltmCapture(app, "backups-screen")

        let passphrase = app.secureTextFields["Passphrase"].firstMatch
        XCTAssertTrue(passphrase.waitForExistence(timeout: 20), "passphrase field missing")
        passphrase.tap()
        passphrase.typeText(ltmBackupPassphrase())
        ltmDismissKeyboard(app)

        let upNow = app.buttons["Back Up Now"].firstMatch
        XCTAssertTrue(upNow.waitForExistence(timeout: 20),
                      "no 'Back Up Now' control: \(ltmVisibleTexts(app))")

        XCTAssertTrue(ltmScrollTo(app, "Restore from Self-Hosted Server"),
                      "self-hosted restore entry not offered: \(ltmVisibleTexts(app))")
    }
}
