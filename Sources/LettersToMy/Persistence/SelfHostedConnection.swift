import Foundation
import LettersToMyCore

// MARK: - Connection state

enum SelfHostedConnectionState: Equatable {
    case notConfigured
    case checking
    case connected(SelfHostedServerIdentity)
    case authenticationFailed
    case unreachable(String)
    case incompatible(String)
    case serverError(String)

    var label: String {
        switch self {
        case .notConfigured: "Not configured"
        case .checking: "Checking…"
        case .connected(let identity): identity.displayName
        case .authenticationFailed: "Authentication failed"
        case .unreachable: "Server unreachable"
        case .incompatible(let detail): "Incompatible server — \(detail)"
        case .serverError(let detail): "Server error — \(detail)"
        }
    }

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var systemImage: String {
        switch self {
        case .notConfigured: "circle.dashed"
        case .checking: "ellipsis.circle"
        case .connected: "checkmark.circle.fill"
        case .authenticationFailed, .incompatible, .serverError: "exclamationmark.triangle.fill"
        case .unreachable: "wifi.slash"
        }
    }

    /// Map an identity-probe failure onto the matching user-facing state.
    ///
    /// `SelfHostedCapabilityCheck` returns a nil identity for EVERY API error,
    /// including a 401, so the error itself must be consulted to tell "your
    /// token is wrong" apart from "the server is down". Collapsing them into
    /// `.unreachable` sends the user to debug the network for what is actually
    /// an authentication problem — and left `.authenticationFailed` dead.
    ///
    /// Static (not a View method) so it can be covered by a unit test.
    static func fromIdentityFailure(
        _ report: SelfHostedCapabilityReport
    ) -> SelfHostedConnectionState {
        let error: SelfHostedAPIError? = {
            if case .failure(let e) = report.collaboration { return e }
            if case .failure(let e) = report.backups { return e }
            if case .failure(let e) = report.attachments { return e }
            return nil
        }()

        switch error {
        case .unauthorized:
            return .authenticationFailed
        case .timeout:
            return .unreachable("the server did not respond in time")
        case .unreachable(let detail):
            return .unreachable(detail)
        case .incompatibleServer(let detail):
            return .incompatible(detail)
        case .serverError(let code, let detail):
            return .serverError("HTTP \(code): \(detail)")
        case .some(let other):
            return .serverError(other.localizedDescription)
        case .none:
            return .unreachable("could not contact server")
        }
    }
}