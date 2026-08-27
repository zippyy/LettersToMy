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
}