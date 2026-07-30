import Foundation

/// Syncs the Core Data database to a self-hosted LettersToMy
/// sync server. Push your platform's database, pull others'.
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

        var req = URLRequest(url: URL(string: "\(serverURL)/sync/push/\(platform)")!)
        req.httpMethod = "PUT"
        req.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        req.httpBody = data

        let (_, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
    }

    /// Download another platform's database from the server.
    func pullDatabase(platform: String = "android") async throws -> Data {
        var req = URLRequest(url: URL(string: "\(serverURL)/sync/pull/\(platform)")!)
        req.httpMethod = "GET"
        req.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}