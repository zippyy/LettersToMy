import Foundation

/// Syncs the Core Data database to a self-hosted LettersToMy
/// sync server. Push your platform's database, pull others'.
///
/// NOTE: This service is not wired into any UI/settings flow yet. It is
/// kept compiling and hardened so a future self-hosted sync preference
/// can enable it without inheriting crashes or silent failures.
final class SelfHostedSyncService: Sendable {
    private let serverURL: String
    private let apiToken: String
    private let session: URLSession
    private let platform = "ios"

    init(serverURL: String, apiToken: String) {
        self.serverURL = serverURL.hasSuffix("/") ? String(serverURL.dropLast()) : serverURL
        self.apiToken = apiToken
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        self.session = URLSession(configuration: config)
    }

    /// Upload the Core Data SQLite file to the server.
    func pushDatabase() async throws {
        let dbURL = PersistenceController.shared.dbURL
        let data = try Data(contentsOf: dbURL)

        var req = try URLRequest(url: url("/sync/push/\(platform)"))
        req.httpMethod = "PUT"
        req.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        req.httpBody = data

        try await send(req)
    }

    /// Download another platform's database from the server.
    func pullDatabase(platform: String = "android") async throws -> Data {
        var req = try URLRequest(url: url("/sync/pull/\(platform)"))
        req.httpMethod = "GET"
        req.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
            throw SelfHostedError.httpStatus(status, path: "/sync/pull/\(platform)")
        }
        return data
    }

    // MARK: - Helpers

    private func url(_ path: String) throws -> URL {
        guard let base = URL(string: serverURL),
              let url = URL(string: path, relativeTo: base) else {
            throw SelfHostedError.invalidURL(path: path, base: serverURL)
        }
        return url
    }

    private func send(_ request: URLRequest) async throws {
        let (_, resp) = try await session.data(for: request)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
            throw SelfHostedError.httpStatus(status, path: request.url?.path ?? "")
        }
    }
}