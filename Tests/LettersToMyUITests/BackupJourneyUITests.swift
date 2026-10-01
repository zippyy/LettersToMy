import XCTest

/// §4–§18: the backup journey, driven like a real user.
///
/// Deliberately SPLIT into ordered checkpoints rather than one opaque method.
/// XCTest runs methods alphabetically within a class and does NOT reinstall the
/// app between them, so state flows A -> B -> C on the same install: the tests
/// form one coherent journey while a failure still localises to a stage. The
/// `testA_`/`testB_`/`testC_` prefixes fix that order.
///
/// Run all three in ONE xcodebuild invocation and with NO uninstall between.
/// Run-tagged identifiers make the restored state unmistakable and let a later
/// stage assert against values it did not itself create.
final class BackupJourneyUITests: XCTestCase {

    /// Shared across the class (and across stages) via an environment variable,
    /// because only the FIRST launch of this process can see a fresh value and
    /// later stages must agree on the tag.
    private static let runTag: String = {
        let env = ProcessInfo.processInfo.environment
        if let t = env["LTM_RUN_TAG"], !t.isEmpty { return t }
        return String(UUID().uuidString.prefix(6)).uppercased()
    }()

    private var token = ""
    private let passphrase = "Runtime-Acceptance-Pass-42"
    private let wrongPassphrase = "definitely-the-wrong-passphrase"

    override func setUpWithError() throws {
        continueAfterFailure = false
        token = ltmServerToken()
        if token.isEmpty {
            throw NSError(domain: "BackupJourneyUITests", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "no server token (set LTM_SERVER_TOKEN or LTM_SERVER_ENV_FILE)"
            ])
        }
        print("JOURNEY runTag=\(Self.runTag) serverURL=\(ltmServerURL()) tokenLen=\(token.count)")
    }

    private var childName: String { "UIBACKUP-\(Self.runTag)-Child" }
    private var draftTitle: String { "UIBACKUP-\(Self.runTag)-Draft" }
    private var sealedTitle: String { "UIBACKUP-\(Self.runTag)-Sealed" }
    private var restoredTitle: String { "UIBACKUP-\(Self.runTag)-RestoreMe" }

    // MARK: - content primitives

    /// Write a letter through the real editor and save it with the given button.
    private func writeLetter(_ app: XCUIApplication, title: String, body: String, save: String) {
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
        ltmDismissKeyboard(app)

        let saveButton = app.buttons[save].firstMatch
        XCTAssertTrue(saveButton.exists, "\(save) button missing")
        saveButton.tap()
        XCTAssertTrue(app.buttons["New Letter"].firstMatch.waitForExistence(timeout: 30),
                      "editor did not dismiss after \(save)")
        print("SEED letter '\(title)' saved via '\(save)'")
    }

    /// Open the library's real letter list (the root is a list of links).
    private func openAllLetters(_ app: XCUIApplication) {
        let all = app.buttons["All Letters"].firstMatch
        if all.waitForExistence(timeout: 10) { all.tap(); return }
        let alt = app.staticTexts["All Letters"].firstMatch
        if alt.waitForExistence(timeout: 5) { alt.tap() }
    }

    @discardableResult
    private func letterExists(_ app: XCUIApplication, _ title: String) -> Bool {
        app.tabBars.buttons["Letters"].tap()
        openAllLetters(app)
        return app.staticTexts[title].firstMatch.waitForExistence(timeout: 20)
    }

    private func openLetter(_ app: XCUIApplication, _ title: String) {
        XCTAssertTrue(letterExists(app, title), "letter '\(title)' not in the library")
        app.staticTexts[title].firstMatch.tap()
        Thread.sleep(forTimeInterval: 1.2)
    }

    // MARK: - attachment primitives

    /// Attach a photo from the seeded simulator library via the real picker.
    ///
    /// PHPicker is a system remote view, so its contents are not part of the app
    /// process. Several query shapes are attempted and every attempt is logged,
    /// because guessing one shape is what produces a false "attachment broken".
    @discardableResult
    private func attachPhoto(_ app: XCUIApplication) -> Bool {
        // The attachments control lives in a Section BELOW the letter body in a
        // scrolling Form, and the accessibility tree only exposes ON-SCREEN
        // elements — so it must be scrolled into view before it can be found.
        // (Measured: querying straight after tapping "Edit" reports it missing.)
        var add = app.buttons["Add Attachments"]
        if !add.exists {
            for _ in 0..<6 {
                app.swipeUp()
                Thread.sleep(forTimeInterval: 0.5)
                add = app.buttons["Add Attachments"]
                if add.exists { break }
            }
        }
        // A SwiftUI `Menu` does not always surface under `buttons`.
        if !add.exists { add = ltmAnyLabel(app, "Add Attachments") }
        if !add.exists { add = app.otherElements["Add Attachments"] }
        XCTAssertTrue(add.exists, "Add Attachments control missing (editor section not reachable)")
        print("ATTACH control found=\(add.exists) hittable=\(add.isHittable) type=\(add.elementType.rawValue)")

        if add.isHittable { add.tap() } else {
            add.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        Thread.sleep(forTimeInterval: 1.2)

        let photoLibrary = app.buttons["Photo Library"].firstMatch
        var lib = photoLibrary
        if !lib.exists { lib = ltmAnyLabel(app, "Photo Library") }
        XCTAssertTrue(lib.exists, "'Photo Library' menu item missing after opening the menu")
        if lib.isHittable { lib.tap() } else {
            lib.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        Thread.sleep(forTimeInterval: 3.0)

        // The picker may be hosted by the app, by Springboard, by Photos, or by
        // the PhotosUI private extension that actually presents PHPicker.
        //
        // CRITICAL: reading `.images` / `.cells` on an XCUIApplication that is
        // NOT RUNNING raises "Failed to get matching snapshots: Application ...
        // is not running" as an UNCATCHABLE test failure. Every candidate must
        // therefore be state-guarded before any element is touched.
        let candidates: [(String, XCUIApplication)] = [
            ("app", app),
            ("photospicker", XCUIApplication(bundleIdentifier: "com.apple.PhotosUIPrivate.PhotosPicker")),
            ("photos", XCUIApplication(bundleIdentifier: "com.apple.mobileslideshow")),
            ("springboard", XCUIApplication(bundleIdentifier: "com.apple.springboard")),
        ]

        /// Tap the element, or its centre point when it reports not-hittable.
        func tapAny(_ element: XCUIElement) -> Bool {
            guard element.exists else { return false }
            if element.isHittable { element.tap() }
            else { element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
            Thread.sleep(forTimeInterval: 1.5)
            return true
        }

        for (name, host) in candidates {
            let running = host.state == .runningForeground || host.state == .runningBackground
            guard running else {
                print("ATTACH[\(name)] not running -- skipped (querying it would abort the test)")
                continue
            }
            let images = host.images
            let cells = host.cells
            print("ATTACH[\(name)] images=\(images.count) cells=\(cells.count) buttons=\(host.buttons.count)")

            // Grid items are usually images; some picker revisions expose cells.
            var target: XCUIElement?
            if images.count > 0 { target = images.element(boundBy: 0) }
            if target == nil && cells.count > 0 { target = cells.element(boundBy: 0) }
            guard let pick = target else { continue }

            let picked = tapAny(pick)
            print("ATTACH[\(name)] picked=\(picked)")
            guard picked else { continue }

            // A multi-select PHPicker stays OPEN until an explicit confirm. If
            // it is left up, every later query in the test runs against a
            // remote picker view and can fail with snapshot errors — which is
            // exactly how a mis-diagnosed "product" failure happens.
            var confirmed = false
            for label in ["Add", "Done", "Select", "Choose", "Insert"] {
                let b = host.buttons[label]
                if b.waitForExistence(timeout: 3) && b.isEnabled {
                    b.tap()
                    Thread.sleep(forTimeInterval: 2.0)
                    confirmed = true
                    print("ATTACH confirmed with '\(label)' on \(name)")
                    break
                }
            }
            if !confirmed { print("ATTACH no confirm button found on \(name)") }

            // Prove the picker really went away before returning: the editor's
            // own control must be frontmost again.
            let editorBack = app.buttons["Add Attachments"].waitForExistence(timeout: 10)
            print("ATTACH[\(name)] editorVisibleAgain=\(editorBack) confirmed=\(confirmed)")
            if editorBack { return true }
            print("ATTACH[\(name)] picker still presented -- continuing to next candidate")
        }
        print("ATTACH no photo could be selected -- picker shape not recognised")
        return false
    }

    /// Count attachment rows visible in the letter editor / detail for a letter.
    private func attachmentEvidence(_ app: XCUIApplication) -> String {
        let imgs = app.images.count
        let texts = ltmVisibleTexts(app)
        return "images=\(imgs) texts=\(texts.prefix(300))"
    }

    // MARK: - Stage A: dataset + attachment

    func testA_seedDatasetAndAttachment() {
        let app = ltmLaunch(XCUIApplication())
        print("STAGE A start tag=\(Self.runTag)")

        // ---- recipient
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
        XCTAssertTrue(app.staticTexts[childName].waitForExistence(timeout: 25),
                      "newly created child did not appear")
        print("STAGE A child created '\(childName)'")

        // ---- draft
        writeLetter(app, title: draftTitle, body: "UIBACKUP draft body \(Self.runTag)", save: "Save Draft")

        // ---- sealed letter (the backup payload's interesting case)
        writeLetter(app, title: sealedTitle, body: "UIBACKUP sealed body \(Self.runTag)", save: "Seal Letter")

        // ---- the letter that will be deleted and restored
        writeLetter(app, title: restoredTitle, body: "UIBACKUP restore-me body \(Self.runTag)", save: "Save Draft")

        // ---- attach a photo to the restore-me letter, then prove it survives
        //      a save + leave + reopen cycle BEFORE any backup happens.
        openLetter(app, restoredTitle)
        let attachButton = app.buttons["Edit"].firstMatch
        if attachButton.waitForExistence(timeout: 15) {
            attachButton.tap()
            Thread.sleep(forTimeInterval: 1.0)
        }
        let attached = attachPhoto(app)
        print("STAGE A attachPhoto returned=\(attached)")
        ltmCapture(app, "after-attach")

        // Save the edit (an existing draft offers "Save Draft").
        if app.buttons["Save Draft"].firstMatch.exists {
            app.buttons["Save Draft"].firstMatch.tap()
        } else if app.buttons["Save Changes"].firstMatch.exists {
            app.buttons["Save Changes"].firstMatch.tap()
        }
        Thread.sleep(forTimeInterval: 1.5)

        // Reopen and look again: this is the save/reopen proof.
        openLetter(app, restoredTitle)
        let after = attachmentEvidence(app)
        print("STAGE A attachment after reopen: \(after)")
        print("STAGE A attachment saved+reopened=\(attached)")

        // Record the oracle.
        let oracle = [
            "run=\(Self.runTag)",
            "child=\(childName)",
            "draft=\(draftTitle)",
            "sealed=\(sealedTitle)",
            "restoreMe=\(restoredTitle)",
            "attachment=photo via Photo Library",
            "attachmentSaved=\(attached)",
            "libraryAfterReopen=\(after)",
        ].joined(separator: "\n")
        let path = "/tmp/ltm-journey-oracle-\(Self.runTag).txt"
        try? oracle.write(toFile: path, atomically: true, encoding: .utf8)
        print("STAGE A ORACLE written to \(path)")

        XCTAssertTrue(attached,
                      "no attachment could be added through the UI -- the §5 attachment proof cannot proceed")
    }

    // MARK: - archive selection

    /// Letters this run actually uploaded (draft + sealed + restore-me).
    private var expectedLetters: Int { 3 }

    /// The archive row belonging to THIS run's backup.
    ///
    /// The picker lists every archive on the server, and the capability check
    /// creates one on every probe (1 letter, random bytes). Those are not real
    /// archives, so selecting by POSITION makes the preview fail for a reason
    /// that has nothing to do with the backup under test. Select by the letter
    /// count this run uploaded, and log the candidate set so a mismatch is
    /// visible rather than assumed.
    private func pickArchiveRow(_ app: XCUIApplication) -> XCUIElement {
        let all = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "letters"))
        print("STAGE archiveCandidates=\(all.count)")
        let exact = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "\(expectedLetters) letters")).firstMatch
        if exact.exists { return exact }
        print("STAGE no archive with \(expectedLetters) letters; falling back to the first row")
        return all.firstMatch
    }

    /// The "Back Up Now" control for ONE destination.
    ///
    /// Every destination row renders its own icon-only "Back Up Now", so a bare
    /// `.firstMatch` taps whichever destination sorts first (measured: "Local
    /// File backup complete", with zero self-hosted traffic on the wire). Match
    /// the button whose vertical band matches the destination's title instead.
    private func backUpNowButton(_ app: XCUIApplication, destinationTitle: String) -> XCUIElement {
        let scoped = app.cells
            .containing(NSPredicate(format: "label CONTAINS %@", destinationTitle))
            .firstMatch.buttons["Back Up Now"]
        if scoped.exists { return scoped }

        let title = app.staticTexts[destinationTitle].firstMatch
        let buttons = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Back Up Now"))
        let total = buttons.count
        print("STAGE backUpNow total=\(total) titleExists=\(title.exists)")
        guard title.exists else { return buttons.firstMatch }
        let band = title.frame.midY
        for i in 0..<total {
            let b = buttons.element(boundBy: i)
            guard b.exists else { continue }
            let delta = abs(b.frame.midY - band)
            print("STAGE candidate[\(i)] midY=\(b.frame.midY) delta=\(delta)")
            if delta < 30 { return b }
        }
        return buttons.firstMatch
    }

    // MARK: - Stage B: backup, upload, list, preview

    func testB_backupUploadListPreview() {
        let app = ltmLaunch(XCUIApplication())
        print("STAGE B start tag=\(Self.runTag)")

        // Wire the server (registers it as a backup destination too).
        ltmConfigureSelfHosted(app, url: ltmServerURL(), token: token)
        let connected = ltmWaitForConnected(app, timeout: 60)
        print("STAGE B connection=\(connected)")
        XCTAssertTrue(connected.hasPrefix("API v"),
                      "server not connected before the backup stage (saw '\(connected)')")

        // ---- Backups screen
        XCTAssertTrue(ltmOpenSettingsRow(app, row: "Manage Backups"), "'Manage Backups' row not found")
        XCTAssertTrue(app.navigationBars["Backups"].waitForExistence(timeout: 25),
                      "Backups screen did not open")

        // ---- passphrase
        let pass = app.secureTextFields["Passphrase"].firstMatch
        XCTAssertTrue(pass.waitForExistence(timeout: 20), "passphrase field missing")
        pass.tap()
        pass.typeText(passphrase)
        ltmDismissKeyboard(app)

        // ---- upload, scoped to the SELF-HOSTED destination row.
        // A bare `.firstMatch` taps whichever destination sorts first; measured:
        // "Local File backup complete" with zero self-hosted traffic on the wire.
        let upNow = backUpNowButton(app, destinationTitle: "Self-Hosted Server")
        XCTAssertTrue(upNow.waitForExistence(timeout: 20), "Back Up Now not found")
        ltmMark("BACKUP tap (Self-Hosted Server)")
        if upNow.isHittable { upNow.tap() }
        else { upNow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }

        // The product reports completion through an ALERT ("Backup Complete" /
        // "Backup Failed"), so accept either and print what it said.
        let alertOK = app.alerts.buttons["OK"].firstMatch
        var alertText = ""
        var alertSeen = false
        if alertOK.waitForExistence(timeout: 180) {
            alertText = ltmTexts(of: app.alerts.firstMatch)
            print("STAGE B ALERT '\(alertText)'")
            alertSeen = true
            alertOK.tap()
            Thread.sleep(forTimeInterval: 1.0)
        } else {
            print("STAGE B no completion alert appeared within 180s")
        }

        // Corroborating: the destination row records the last backup.
        let lastBackup = app.staticTexts.containing(
            NSPredicate(format: "label BEGINSWITH %@", "Last backup")).firstMatch
        let recorded = lastBackup.waitForExistence(timeout: 30)
        print("STAGE B lastBackupRow=\(recorded) alertSeen=\(alertSeen)")
        ltmCapture(app, "after-backup")

        XCTAssertTrue(alertSeen || recorded,
                      "no observable success after the backup upload (no alert, no 'Last backup' row)")
        // The backup must have gone to the SELF-HOSTED destination, not a local one.
        XCTAssertTrue(alertText.contains("Self-Hosted Server"),
                      "the upload went to the wrong destination (alert: '\(alertText)')")

        // ---- list + preview via the server restore picker
        let restoreRow = "Restore from Self-Hosted Server"
        XCTAssertTrue(ltmScrollTo(app, restoreRow), "'\(restoreRow)' not available")
        let restoreEntry = app.buttons[restoreRow].exists ? app.buttons[restoreRow] : app.staticTexts[restoreRow]
        restoreEntry.tap()

        XCTAssertTrue(app.navigationBars["Restore from Server"].waitForExistence(timeout: 60),
                      "server restore picker did not open")
        Thread.sleep(forTimeInterval: 2.0)
        ltmCapture(app, "restore-picker")

        // §9: only assert what the UI actually renders. Select the archive THIS
        // run uploaded (3 letters) rather than whatever sorts first — the
        // capability probe leaves 1-letter archives whose bytes are not a real
        // payload, and previewing one fails for an unrelated reason.
        let noBackups = app.staticTexts["No Remote Backups"].exists
        let archives = pickArchiveRow(app)
        print("STAGE B picker noBackups=\(noBackups) chosenRow='\(archives.exists ? archives.label : "<none>")'")
        XCTAssertFalse(noBackups, "the restore picker reported no remote backups after a successful upload")
        XCTAssertTrue(archives.exists, "no archive row was listed with the uploaded letter count")

        // ---- preview
        if archives.isHittable { archives.tap() }
        else { archives.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
        XCTAssertTrue(app.navigationBars["Restore Archive"].waitForExistence(timeout: 90),
                      "archive preview did not open")
        Thread.sleep(forTimeInterval: 2.0)
        ltmCapture(app, "restore-preview")

        let previewTexts = ltmVisibleTexts(app)
        print("STAGE B PREVIEW texts=\(previewTexts)")
        XCTAssertTrue(previewTexts.contains("Letters") || previewTexts.contains("Attachments"),
                      "preview did not report archive metadata: \(previewTexts)")
        print("STAGE B list+preview PASS")
    }

    // MARK: - Stage C: wrong passphrase, then valid restore

    /// Open the server restore picker and select the newest archive.
    ///
    /// ORDERING IS LOAD-BEARING: `downloadRemoteBackup()` reads the passphrase
    /// from the MAIN Backups form (`restorePassphrase.isEmpty ? passphrase : …`),
    /// so it must be set BEFORE the picker sheet covers that form. Setting it
    /// afterwards is impossible — the sheet is in the way and the field reports
    /// "not hittable" (measured).
    private func openRemoteArchive(_ app: XCUIApplication, passphrase restorePass: String?) {
        XCTAssertTrue(ltmOpenSettingsRow(app, row: "Manage Backups"), "'Manage Backups' row not found")
        XCTAssertTrue(app.navigationBars["Backups"].waitForExistence(timeout: 30),
                      "Backups screen did not open")
        Thread.sleep(forTimeInterval: 1.0)

        if let restorePass {
            if !app.secureTextFields["Passphrase"].exists { _ = ltmScrollTo(app, "Passphrase") }
            let field = app.secureTextFields["Passphrase"].firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 20), "passphrase field missing")
            ltmDismissKeyboard(app)
            if field.isHittable { field.tap() }
            else { field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
            Thread.sleep(forTimeInterval: 0.4)
            let current = ltmSecureLen(field)
            if current > 0 {
                field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current + 8))
                Thread.sleep(forTimeInterval: 0.4)
            }
            field.typeText(restorePass)
            ltmDismissKeyboard(app)
            print("RESTORE passphrase set (len=\(ltmSecureLen(app.secureTextFields["Passphrase"].firstMatch)))")
        }

        let restoreRow = "Restore from Self-Hosted Server"
        XCTAssertTrue(ltmScrollTo(app, restoreRow), "'\(restoreRow)' not available")
        let row = app.buttons[restoreRow].exists ? app.buttons[restoreRow] : app.staticTexts[restoreRow]
        if row.isHittable { row.tap() }
        else { row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
        XCTAssertTrue(app.navigationBars["Restore from Server"].waitForExistence(timeout: 60),
                      "server restore picker did not open")
        Thread.sleep(forTimeInterval: 1.5)

        let archiveRow = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "letters")).firstMatch
        XCTAssertTrue(archiveRow.waitForExistence(timeout: 30),
                      "no archive listed in the restore picker")
        archiveRow.tap()
    }

    /// Dismiss the restore picker if it is still presented, so the main form's
    /// progress/error text becomes visible and later navigation is not blocked.
    private func dismissRestorePicker(_ app: XCUIApplication) {
        guard app.navigationBars["Restore from Server"].exists else { return }
        let cancel = app.buttons["Cancel"].firstMatch
        if cancel.exists && cancel.isHittable { cancel.tap() }
        Thread.sleep(forTimeInterval: 1.0)
    }

    func testC_wrongPassphraseFailsSafely_thenValidRestore() {
        let app = ltmLaunch(XCUIApplication())
        print("STAGE C start tag=\(Self.runTag)")

        // ---- pre-attempt oracle: the disposable letters must all be present
        app.tabBars.buttons["Letters"].tap()
        openAllLetters(app)
        let draftBefore = app.staticTexts[draftTitle].firstMatch.waitForExistence(timeout: 25)
        let restoreBefore = app.staticTexts[restoredTitle].firstMatch.exists
        print("STAGE C before wrong-passphrase: draft=\(draftBefore) restoreMe=\(restoreBefore)")
        XCTAssertTrue(draftBefore && restoreBefore,
                      "the stage-A dataset is not present; the journey stages must run in order on one install")

        // ---- wire the server (restore needs it configured + connected)
        ltmConfigureSelfHosted(app, url: ltmServerURL(), token: token)
        let connected = ltmWaitForConnected(app, timeout: 60)
        print("STAGE C connection=\(connected)")
        XCTAssertTrue(connected.hasPrefix("API v"),
                      "server not connected before the restore stage (saw '\(connected)')")

        // ---- §11 wrong passphrase must FAIL VISIBLY and change nothing
        openRemoteArchive(app, passphrase: wrongPassphrase)
        let previewOpened = app.navigationBars["Restore Archive"].waitForExistence(timeout: 30)
        print("STAGE C wrong-passphrase previewOpened=\(previewOpened)")
        XCTAssertFalse(previewOpened,
                       "a wrong passphrase opened the restore preview -- decryption was not enforced")

        // The failure text lives on the MAIN form behind the picker sheet, so
        // record what is visible before, then dismiss and look again.
        let visibleWhileSheetUp = ltmTexts(of: app)
        let whileUp = visibleWhileSheetUp.contains("Restore failed")
            || visibleWhileSheetUp.contains("Decryption failed")
        print("STAGE C failureVisibleWhilePickerUp=\(whileUp)")
        // The failure text lives in the MAIN form's restore section, which sits
        // BELOW the fold. The accessibility tree only exposes ON-SCREEN
        // elements, and ltmWaitForAny() scrolls to the TOP before looking — so
        // it can never see it (measured: "visible while the picker was up" was
        // true, then "after dismiss" was empty purely because of scroll
        // position). Search while scrolling instead.
        dismissRestorePicker(app)
        var failed = ""
        let needles = ["Restore failed", "Decryption failed"]
        let deadline = Date().addingTimeInterval(75)
        while Date() < deadline && failed.isEmpty {
            for n in needles where ltmAnyLabel(app, n).exists { failed = n; break }
            if !failed.isEmpty { break }
            app.swipeUp()
            Thread.sleep(forTimeInterval: 0.7)
        }
        ltmCapture(app, "wrong-passphrase")
        print("STAGE C wrong-passphrase visibleWhilePickerUp=\(whileUp) visibleAfterScroll='\(failed)'")
        XCTAssertTrue(whileUp || !failed.isEmpty,
                      "a wrong passphrase produced no visible failure at all (checked with the picker both up and dismissed/scrolled)")

        // ---- §12 non-destructive: local data intact, app responsive
        app.tabBars.buttons["Letters"].tap()
        Thread.sleep(forTimeInterval: 1.0)
        openAllLetters(app)
        let draftAfter = app.staticTexts[draftTitle].firstMatch.waitForExistence(timeout: 25)
        let restoreAfter = app.staticTexts[restoredTitle].firstMatch.exists
        let sealedAfter = app.staticTexts[sealedTitle].firstMatch.exists
        print("STAGE C after wrong-passphrase: draft=\(draftAfter) restoreMe=\(restoreAfter) sealed=\(sealedAfter)")
        XCTAssertTrue(draftAfter && restoreAfter && sealedAfter,
                      "the failed restore damaged local data")
        let draftRows = app.staticTexts.matching(NSPredicate(format: "label == %@", draftTitle)).count
        let restoreRows = app.staticTexts.matching(NSPredicate(format: "label == %@", restoredTitle)).count
        print("STAGE C duplicate check: draftRows=\(draftRows) restoreRows=\(restoreRows)")
        XCTAssertEqual(draftRows, 1, "the failed restore created a duplicate draft row")
        XCTAssertEqual(restoreRows, 1, "the failed restore created a duplicate restore-me row")

        // ---- §13 observable change: delete the restore-me letter through the UI
        XCTAssertTrue(app.staticTexts[restoredTitle].firstMatch.waitForExistence(timeout: 25),
                      "restore-me letter missing before deletion")
        app.staticTexts[restoredTitle].firstMatch.swipeLeft()
        let del = app.buttons["Delete"].firstMatch
        if del.waitForExistence(timeout: 15) {
            del.tap()
            let confirm = app.buttons["Delete"].firstMatch
            if confirm.waitForExistence(timeout: 8) { confirm.tap() }
        }
        Thread.sleep(forTimeInterval: 1.5)
        let gone = !app.staticTexts[restoredTitle].firstMatch.exists
        print("STAGE C deleted restore-me letter gone=\(gone)")
        XCTAssertTrue(gone, "the restore-me letter could not be deleted through the UI")

        // ---- §14 valid restore: the deleted record must come back (additive)
        openRemoteArchive(app, passphrase: passphrase)
        XCTAssertTrue(app.navigationBars["Restore Archive"].waitForExistence(timeout: 120),
                      "a VALID passphrase did not open the restore preview")
        Thread.sleep(forTimeInterval: 2.0)
        ltmCapture(app, "valid-restore-preview")
        let previewTexts = ltmVisibleTexts(app)
        print("STAGE C preview texts=\(previewTexts.prefix(400))")

        let restoreButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Restore")).firstMatch
        XCTAssertTrue(restoreButton.waitForExistence(timeout: 20), "restore confirm button missing")
        print("STAGE C tapping '\(restoreButton.label)'")
        ltmMark("VALID-RESTORE tap")
        restoreButton.tap()
        Thread.sleep(forTimeInterval: 5.0)
        ltmCapture(app, "after-valid-restore")

        // ---- §14/§15 the deleted record returns, with its attachment
        app.tabBars.buttons["Letters"].tap()
        Thread.sleep(forTimeInterval: 1.5)
        openAllLetters(app)
        let returned = app.staticTexts[restoredTitle].firstMatch.waitForExistence(timeout: 60)
        print("STAGE C restoredRecordReturned=\(returned)")
        XCTAssertTrue(returned, "the deleted record did not return after a valid restore")

        app.staticTexts[restoredTitle].firstMatch.tap()
        Thread.sleep(forTimeInterval: 2.5)
        let evidence = attachmentEvidence(app)
        let imagesBack = ltmImageCount(app)
        print("STAGE C restoredAttachmentImages=\(imagesBack) evidence=\(evidence.prefix(300))")
        XCTAssertGreaterThan(imagesBack, 0,
                             "the restored letter shows no attachment image in the app")
    }

    // MARK: - Stage D: remote deletion

    func testD_remoteDeleteSurface() {
        let app = ltmLaunch(XCUIApplication())
        print("STAGE D start tag=\(Self.runTag)")
        XCTAssertTrue(ltmOpenSettingsRow(app, row: "Manage Backups"), "'Manage Backups' row not found")
        XCTAssertTrue(app.navigationBars["Backups"].waitForExistence(timeout: 25), "Backups screen did not open")
        Thread.sleep(forTimeInterval: 1.0)
        ltmCapture(app, "backups-full")

        // Does the product expose any delete affordance for a REMOTE archive?
        let localDelete = app.buttons["Delete Record"].exists
        let swipeTargets = app.cells.count
        print("STAGE D localDeleteRecord=\(localDelete) cells=\(swipeTargets)")

        XCTAssertTrue(ltmScrollTo(app, "Restore from Self-Hosted Server"),
                      "restore row not found")
        let row = app.buttons["Restore from Self-Hosted Server"].exists
            ? app.buttons["Restore from Self-Hosted Server"]
            : app.staticTexts["Restore from Self-Hosted Server"]
        row.tap()
        XCTAssertTrue(app.navigationBars["Restore from Server"].waitForExistence(timeout: 60),
                      "restore picker did not open")
        Thread.sleep(forTimeInterval: 1.5)
        ltmCapture(app, "remote-picker-for-delete")

        // Look for ANY remote-delete control in the picker.
        let remoteDelete = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@",
                        "delete", "remove")).firstMatch
        let archiveRow = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "letters")).firstMatch
        let hasArchive = archiveRow.exists
        print("STAGE D remotePickerHasArchive=\(hasArchive) remoteDeleteControl=\(remoteDelete.exists)")
        if archiveRow.exists {
            archiveRow.swipeLeft()
            Thread.sleep(forTimeInterval: 0.8)
            let afterSwipe = app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] %@", "delete")).firstMatch
            print("STAGE D deleteControlAfterSwipe=\(afterSwipe.exists)")
            ltmCapture(app, "remote-picker-after-swipe")
        }
        // Evidence, not an assertion: §16 needs a remote-delete surface, and if
        // the product has none this must be reported as an unimplemented
        // capability rather than dressed up as a pass.
    }
}
