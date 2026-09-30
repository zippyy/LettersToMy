import Testing
import Foundation
@testable import LettersToMy
@testable import LettersToMyCore

/// Regression coverage for the SelfHostedSync connection-state mapping.
///
/// DEFECT THIS PROVES: `SelfHostedSettingsView.testConnection()` used to route
/// EVERY identity-probe failure to `.unreachable("could not contact server")`.
/// Because `SelfHostedCapabilityCheck.run()` returns a nil identity for any
/// `SelfHostedAPIError` — including `.unauthorized` (HTTP 401) — a *wrong API
/// token* was reported to the user as a network problem, and the declared
/// `SelfHostedConnectionState.authenticationFailed` case was never assigned
/// anywhere in the codebase (dead state).
///
/// These tests fail against the old collapse-to-unreachable behaviour and pass
/// against `SelfHostedConnectionState.fromIdentityFailure(_:)`.
@Suite("Self-hosted connection state mapping")
struct SelfHostedConnectionStateTests {

    /// Build a failed probe report the way the real capability check does:
    /// no identity, and the same error on every feature probe.
    private func report(
        failingWith error: SelfHostedAPIError
    ) -> SelfHostedCapabilityReport {
        SelfHostedCapabilityReport(
            identity: nil,
            collaboration: .failure(error),
            backups: .failure(error),
            attachments: .failure(error)
        )
    }

    @Test("a rejected token is reported as authentication failure, not unreachable")
    func unauthorizedMapsToAuthenticationFailed() {
        let state = SelfHostedConnectionState.fromIdentityFailure(
            report(failingWith: .unauthorized)
        )
        #expect(state == .authenticationFailed)
        #expect(state.label == "Authentication failed")
        // The whole point: it must NOT masquerade as a network failure.
        #expect(state != .unreachable("could not contact server"))
        #expect(!state.isConnected)
    }

    @Test("a transport failure is reported as unreachable")
    func transportFailureMapsToUnreachable() {
        let state = SelfHostedConnectionState.fromIdentityFailure(
            report(failingWith: .unreachable("connection refused"))
        )
        guard case .unreachable(let detail) = state else {
            Issue.record("expected .unreachable, got \(state)")
            return
        }
        #expect(detail == "connection refused")
        #expect(state.label == "Server unreachable")
    }

    @Test("a timeout is reported as unreachable with a round-trip explanation")
    func timeoutMapsToUnreachable() {
        let state = SelfHostedConnectionState.fromIdentityFailure(
            report(failingWith: .timeout)
        )
        #expect(state == .unreachable("the server did not respond in time"))
    }

    @Test("a foreign or wrong-version server is reported as incompatible")
    func incompatibleServerMapsToIncompatible() {
        let state = SelfHostedConnectionState.fromIdentityFailure(
            report(failingWith: .incompatibleServer("API version 2, client supports 1"))
        )
        #expect(state == .incompatible("API version 2, client supports 1"))
    }

    @Test("a server-side error is surfaced with its status code")
    func serverErrorMapsToServerError() {
        let state = SelfHostedConnectionState.fromIdentityFailure(
            report(failingWith: .serverError(500, "boom"))
        )
        #expect(state == .serverError("HTTP 500: boom"))
    }

    /// Distinct causes must stay distinguishable — the old code made these
    /// three indistinguishable from each other.
    @Test("auth, transport and server faults map to three different states")
    func distinctCausesAreDistinguishable() {
        let auth = SelfHostedConnectionState.fromIdentityFailure(
            report(failingWith: .unauthorized))
        let net = SelfHostedConnectionState.fromIdentityFailure(
            report(failingWith: .unreachable("nope")))
        let srv = SelfHostedConnectionState.fromIdentityFailure(
            report(failingWith: .serverError(503, "maintenance")))

        #expect(auth != net)
        #expect(net != srv)
        #expect(auth != srv)

        // And their user-facing labels must differ too, since the label is what
        // the user actually reads.
        let labels = Set([auth.label, net.label, srv.label])
        #expect(labels.count == 3)
    }
}
