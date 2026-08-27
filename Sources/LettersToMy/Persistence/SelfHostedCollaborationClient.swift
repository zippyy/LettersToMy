import Foundation

// MARK: - Errors

/// Errors surfaced by the self-hosted collaboration client.
enum SelfHostedError: LocalizedError {
    case invalidURL(path: String, base: String)
    case httpStatus(Int, path: String)
    case responseDataCorrupted(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let path, let base):
            return "Invalid self-hosted URL: path \"\(path)\" against base \"\(base)\"."
        case .httpStatus(let status, let path):
            return "Self-hosted server returned HTTP \(status) for \(path)."
        case .responseDataCorrupted(let detail):
            return "Self-hosted server returned malformed data: \(detail)."
        }
    }
}

// MARK: - Data types

struct ServerMember: Codable, Identifiable {
    let id: String
    let name: String
    let role: String
    let since: Int64
}

struct ServerInvitation: Codable {
    let code: String
    let createdBy: String
    let role: String
    let branchIDs: [String]?
    let folderIDs: [String]?
    let expires: Int64

    enum CodingKeys: String, CodingKey {
        case code, role, expires
        case createdBy = "created_by"
        case branchIDs = "branch_ids"
        case folderIDs = "folder_ids"
    }
}

struct ServerBranch: Codable, Identifiable {
    let id: String
    let name: String
    let kind: String
    let isSeeded: Bool
    let memberIDs: [String]
    let createdAt: Int64

    enum CodingKeys: String, CodingKey {
        case id, name, kind
        case isSeeded = "is_seeded"
        case memberIDs = "member_ids"
        case createdAt = "created_at"
    }
}

struct ServerFolder: Codable, Identifiable {
    let id: String
    let branchID: String
    let parentID: String?
    let name: String
    let memberIDs: [String]
    let createdAt: Int64

    enum CodingKeys: String, CodingKey {
        case id, name
        case branchID = "branch_id"
        case parentID = "parent_id"
        case memberIDs = "member_ids"
        case createdAt = "created_at"
    }
}

// MARK: - Client

/// Talks to the self-hosted LettersToMy-SelfHostedSync server.
/// Handles cross-platform invitations, members, branches, and folders.
final class SelfHostedCollaborationClient: Sendable {
    private let serverURL: String
    private let apiToken: String
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(serverURL: String, apiToken: String) {
        self.serverURL = serverURL.hasSuffix("/") ? String(serverURL.dropLast()) : serverURL
        self.apiToken = apiToken
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    // MARK: - Invitations

    func createInvite(createdBy: String, role: String, branchIDs: [String] = [], folderIDs: [String] = []) async throws -> ServerInvitation {
        let body: [String: Any] = [
            "created_by": createdBy,
            "role": role,
            "branch_ids": branchIDs,
            "folder_ids": folderIDs
        ]
        let data = try await post("/invite", body: body)
        return try decode(ServerInvitation.self, from: data, context: "createInvite")
    }

    func lookupInvite(code: String) async throws -> ServerInvitation {
        let data = try await get("/invite/\(code)")
        return try decode(ServerInvitation.self, from: data, context: "lookupInvite(\(code))")
    }

    func acceptInvite(code: String, memberID: String, memberName: String) async throws -> String {
        let body = ["member_id": memberID, "member_name": memberName]
        let data = try await post("/invite/\(code)", body: body)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let role = json["role"] as? String else {
            throw SelfHostedError.responseDataCorrupted("acceptInvite(\(code)) returned no role")
        }
        return role
    }

    func revokeInvite(code: String) async throws {
        _ = try await delete("/invite/\(code)")
    }

    // MARK: - Members

    func listMembers() async throws -> [ServerMember] {
        let data = try await get("/members")
        return try decode([ServerMember].self, from: data, context: "listMembers")
    }

    func updateRole(memberID: String, name: String, role: String) async throws {
        let body: [String: Any] = ["id": memberID, "name": name, "role": role]
        _ = try await put("/members", body: body)
    }

    func removeMember(memberID: String) async throws {
        _ = try await delete("/members?id=\(memberID)")
    }

    // MARK: - Branches

    func listBranches() async throws -> [ServerBranch] {
        let data = try await get("/branches")
        return try decode([ServerBranch].self, from: data, context: "listBranches")
    }

    func createBranch(_ branch: ServerBranch) async throws {
        let data = try encoder.encode(branch)
        let json = try JSONSerialization.jsonObject(with: data)
        _ = try await post("/branches", body: json as? [String: Any] ?? [:])
    }

    func updateBranch(_ branch: ServerBranch) async throws {
        let data = try encoder.encode(branch)
        let json = try JSONSerialization.jsonObject(with: data)
        _ = try await put("/branches/\(branch.id)", body: json as? [String: Any] ?? [:])
    }

    func deleteBranch(id: String) async throws {
        _ = try await delete("/branches/\(id)")
    }

    // MARK: - Folders

    func listFolders(branchID: String? = nil) async throws -> [ServerFolder] {
        let path = branchID.map { "/folders?branch_id=\($0)" } ?? "/folders"
        let data = try await get(path)
        return try decode([ServerFolder].self, from: data, context: "listFolders(\(branchID ?? "all"))")
    }

    func createFolder(_ folder: ServerFolder) async throws {
        let data = try encoder.encode(folder)
        let json = try JSONSerialization.jsonObject(with: data)
        _ = try await post("/folders", body: json as? [String: Any] ?? [:])
    }

    func updateFolder(_ folder: ServerFolder) async throws {
        let data = try encoder.encode(folder)
        let json = try JSONSerialization.jsonObject(with: data)
        _ = try await put("/folders/\(folder.id)", body: json as? [String: Any] ?? [:])
    }

    func deleteFolder(id: String) async throws {
        _ = try await delete("/folders/\(id)")
    }

    // MARK: - HTTP helpers

    private func get(_ path: String) async throws -> Data {
        var req = try URLRequest(url: url(path))
        req.httpMethod = "GET"
        return try await send(req)
    }

    private func post(_ path: String, body: [String: Any]) async throws -> Data {
        var req = try URLRequest(url: url(path))
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await send(req)
    }

    private func put(_ path: String, body: [String: Any]) async throws -> Data {
        var req = try URLRequest(url: url(path))
        req.httpMethod = "PUT"
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await send(req)
    }

    private func delete(_ path: String) async throws -> Data {
        var req = try URLRequest(url: url(path))
        req.httpMethod = "DELETE"
        return try await send(req)
    }

    private func url(_ path: String) throws -> URL {
        // Build the URL defensively instead of force-unwrapping an
        // interpolated string, so a malformed server URL or invitation
        // code fails with a usable error rather than crashing.
        guard let base = URL(string: serverURL),
              let url = URL(string: path, relativeTo: base) else {
            throw SelfHostedError.invalidURL(path: path, base: serverURL)
        }
        return url
    }

    private func send(_ request: URLRequest) async throws -> Data {
        var req = request
        req.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
            throw SelfHostedError.httpStatus(status, path: request.url?.path ?? "")
        }
        return data
    }

    /// Decode a response, throwing a descriptive error when the server
    /// returns malformed data. A decode failure must never be reported as
    /// "zero records" — that hides corruption and breaks debugging.
    private func decode<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        context: String
    ) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw SelfHostedError.responseDataCorrupted("\(context): \(error.localizedDescription)")
        }
    }
}