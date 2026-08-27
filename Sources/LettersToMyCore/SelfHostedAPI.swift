import Foundation

// MARK: - Canonical API contract
//
// This file is the single transport + DTO layer for the LettersToMy
// self-hosted server (LettersToMy-SelfHostedSync). Every client feature
// — connection test, capability check, collaboration, backup provider,
// attachment storage — goes through SelfHostedAPIClient so the protocol
// is implemented exactly once.
//
// Contract (API v1):
//   * Base path: no prefix. Endpoints are /status, /invite, /members,
//     /branches, /folders, /backup/*, /attachment/*, /sync/*.
//   * Auth: `Authorization: Bearer <token>` on every request.
//   * Timestamps: Unix epoch MILLISECONDS as JSON numbers (Int64).
//   * Collections: always JSON arrays; the server never emits null.
//   * IDs: [A-Za-z0-9._-]{1,128} (UUID strings, hex invite codes).
//   * Errors: {"error":{"code":"...","message":"..."}} with codes
//     unauthorized, not_found, conflict, expired, payload_too_large,
//     invalid_request, method_not_allowed, internal.
//   * Roles: the wire values are exactly CollaborationRole raw values —
//     owner, parentAdmin, organizer, contributor, viewer, recipient.
//     Unknown roles are never defaulted to anything; they fail loudly.

// MARK: - Wire DTOs (mirror server JSON exactly)

public struct SelfHostedServerStatus: Codable, Sendable {
    public let service: String
    public let apiVersion: Int
    public let serverVersion: String
    public let capabilities: [String]
    public let syncs: [SelfHostedSyncMeta]
    public let attachments: [SelfHostedAttachmentMeta]
    public let recoveries: [SelfHostedBackupMeta]
    public let branches: Int
    public let folders: Int
    public let members: Int
    public let invitations: Int

    enum CodingKeys: String, CodingKey {
        case service
        case apiVersion = "api_version"
        case serverVersion = "server_version"
        case capabilities
        case syncs, attachments, recoveries
        case branches, folders, members, invitations
    }
}

public struct SelfHostedSyncMeta: Codable, Sendable {
    public let platform: String
    public let timestamp: Int64
    public let size: Int64
    public let kind: String
}

public struct SelfHostedAttachmentMeta: Codable, Sendable, Identifiable {
    public let id: String
    public let contentType: String
    public let size: Int64

    enum CodingKeys: String, CodingKey {
        case id
        case contentType = "content_type"
        case size
    }
}

public struct SelfHostedBackupMeta: Codable, Sendable, Identifiable {
    public let id: String
    public let timestamp: Int64
    public let size: Int64
    public let letterCount: Int

    enum CodingKeys: String, CodingKey {
        case id, timestamp, size
        case letterCount = "letter_count"
    }
}

public struct SelfHostedMember: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let role: CollaborationRole
    public let since: Int64
}

public struct SelfHostedInvitation: Codable, Sendable {
    public let code: String
    public let createdBy: String
    public let role: CollaborationRole
    public let branchIDs: [String]
    public let folderIDs: [String]
    public let expires: Int64

    enum CodingKeys: String, CodingKey {
        case code, role, expires
        case createdBy = "created_by"
        case branchIDs = "branch_ids"
        case folderIDs = "folder_ids"
    }

    public init(
        code: String,
        createdBy: String = "",
        role: CollaborationRole = .viewer,
        branchIDs: [String] = [],
        folderIDs: [String] = [],
        expires: Int64 = 0
    ) {
        self.code = code
        self.createdBy = createdBy
        self.role = role
        self.branchIDs = branchIDs
        self.folderIDs = folderIDs
        self.expires = expires
    }

    /// Arrays decode with `[]` defaults so a server that omits or nulls
    /// them still decodes (the canonical server emits `[]`).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try c.decode(String.self, forKey: .code)
        createdBy = try c.decodeIfPresent(String.self, forKey: .createdBy) ?? ""
        role = try c.decodeIfPresent(CollaborationRole.self, forKey: .role) ?? .viewer
        branchIDs = try c.decodeIfPresent([String].self, forKey: .branchIDs) ?? []
        folderIDs = try c.decodeIfPresent([String].self, forKey: .folderIDs) ?? []
        expires = try c.decodeIfPresent(Int64.self, forKey: .expires) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(code, forKey: .code)
        try c.encode(createdBy, forKey: .createdBy)
        try c.encode(role, forKey: .role)
        try c.encode(branchIDs, forKey: .branchIDs)
        try c.encode(folderIDs, forKey: .folderIDs)
        try c.encode(expires, forKey: .expires)
    }
}

public struct SelfHostedBranch: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let kind: FamilyBranchKind
    public let isSeeded: Bool
    public let memberIDs: [String]
    public let createdAt: Int64

    enum CodingKeys: String, CodingKey {
        case id, name, kind
        case isSeeded = "is_seeded"
        case memberIDs = "member_ids"
        case createdAt = "created_at"
    }

    public init(
        id: String,
        name: String,
        kind: FamilyBranchKind = .custom,
        isSeeded: Bool = false,
        memberIDs: [String] = [],
        createdAt: Int64 = 0
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.isSeeded = isSeeded
        self.memberIDs = memberIDs
        self.createdAt = createdAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        kind = try c.decodeIfPresent(FamilyBranchKind.self, forKey: .kind) ?? .custom
        isSeeded = try c.decodeIfPresent(Bool.self, forKey: .isSeeded) ?? false
        memberIDs = try c.decodeIfPresent([String].self, forKey: .memberIDs) ?? []
        createdAt = try c.decodeIfPresent(Int64.self, forKey: .createdAt) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(kind, forKey: .kind)
        try c.encode(isSeeded, forKey: .isSeeded)
        try c.encode(memberIDs, forKey: .memberIDs)
        try c.encode(createdAt, forKey: .createdAt)
    }
}

public struct SelfHostedFolder: Codable, Sendable, Identifiable {
    public let id: String
    public let branchID: String
    public let parentID: String?
    public let name: String
    public let memberIDs: [String]
    public let createdAt: Int64

    enum CodingKeys: String, CodingKey {
        case id, name
        case branchID = "branch_id"
        case parentID = "parent_id"
        case memberIDs = "member_ids"
        case createdAt = "created_at"
    }

    public init(
        id: String,
        branchID: String,
        parentID: String? = nil,
        name: String,
        memberIDs: [String] = [],
        createdAt: Int64 = 0
    ) {
        self.id = id
        self.branchID = branchID
        self.parentID = parentID
        self.name = name
        self.memberIDs = memberIDs
        self.createdAt = createdAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        branchID = try c.decode(String.self, forKey: .branchID)
        parentID = try c.decodeIfPresent(String.self, forKey: .parentID)
        name = try c.decode(String.self, forKey: .name)
        memberIDs = try c.decodeIfPresent([String].self, forKey: .memberIDs) ?? []
        createdAt = try c.decodeIfPresent(Int64.self, forKey: .createdAt) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(branchID, forKey: .branchID)
        try c.encodeIfPresent(parentID, forKey: .parentID)
        try c.encode(name, forKey: .name)
        try c.encode(memberIDs, forKey: .memberIDs)
        try c.encode(createdAt, forKey: .createdAt)
    }
}

// MARK: - Errors

public enum SelfHostedAPIError: LocalizedError, Sendable, Equatable {
    case invalidURL(String)
    case unreachable(String)
    case timeout
    case unauthorized
    case notFound(String)
    case conflict(String)
    case invitationExpired
    case payloadTooLarge
    case invalidRequest(String)
    case serverError(Int, String)
    case incompatibleServer(String)
    case invalidResponse(String)
    case httpStatus(Int, String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let base):
            return "The server URL is not valid: \(base)"
        case .unreachable(let detail):
            return "Server unreachable: \(detail)"
        case .timeout:
            return "The server did not respond in time."
        case .unauthorized:
            return "Authentication failed. Check the API token."
        case .notFound(let detail):
            return "Not found: \(detail)"
        case .conflict(let detail):
            return "Conflict: \(detail)"
        case .invitationExpired:
            return "This invitation has expired."
        case .payloadTooLarge:
            return "The upload exceeds the server's size limit."
        case .invalidRequest(let detail):
            return "The server rejected the request: \(detail)"
        case .serverError(let status, let detail):
            return "Server error (\(status)): \(detail)"
        case .incompatibleServer(let detail):
            return "Incompatible server: \(detail)"
        case .invalidResponse(let detail):
            return "The server returned malformed data: \(detail)"
        case .httpStatus(let status, let detail):
            return "HTTP \(status): \(detail)"
        }
    }
}

// MARK: - Server identity

public struct SelfHostedServerIdentity: Sendable, Equatable {
    public let service: String
    public let apiVersion: Int
    public let serverVersion: String
    public let capabilities: [String]

    public var displayName: String {
        "\(service) v\(serverVersion) (API v\(apiVersion))"
    }

    public func supports(_ capability: String) -> Bool {
        capabilities.contains(capability)
    }
}

// MARK: - Structured error envelope

private struct ServerErrorEnvelope: Decodable {
    struct ErrorBody: Decodable {
        let code: String
        let message: String
    }
    let error: ErrorBody
}

// MARK: - API client

/// Single shared HTTP client for the LettersToMy self-hosted server.
/// Immutable after init; safe to share across tasks.
public final class SelfHostedAPIClient: @unchecked Sendable {
    /// The service identifier the client requires in /status.
    public static let expectedService = "LettersToMy-SelfHostedSync"
    /// The only API version this client understands.
    public static let supportedAPIVersion = 1
    /// Capabilities the current client actually exercises.
    public static let supportedCapabilities = ["collaboration", "backups", "attachments"]
    /// Capability that marks the (unwired) raw database snapshot storage.
    public static let snapshotCapability = "device-snapshots"

    private let baseURL: URL
    private let token: String
    private let session: URLSession

    public init(serverURL: String, apiToken: String, session: URLSession? = nil) throws {
        let trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let base = URL(string: trimmed),
              base.scheme != nil,
              base.host != nil else {
            throw SelfHostedAPIError.invalidURL(serverURL)
        }
        self.baseURL = base
        self.token = apiToken
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        self.session = session ?? URLSession(configuration: config)
    }

    // MARK: - Connection / identity

    /// Fetch /status and validate that this is a compatible
    /// LettersToMy-SelfHostedSync server. Throws .incompatibleServer
    /// for anything else, .unauthorized for a bad token, and
    /// .unreachable/.timeout for transport failures.
    public func serverIdentity() async throws -> SelfHostedServerIdentity {
        let data = try await get("/status", context: "status")
        let status: SelfHostedServerStatus = try decode(SelfHostedServerStatus.self, from: data, context: "status")
        guard status.service == SelfHostedAPIClient.expectedService else {
            throw SelfHostedAPIError.incompatibleServer(
                "service is \"\(status.service)\", expected \"\(SelfHostedAPIClient.expectedService)\"")
        }
        guard status.apiVersion == SelfHostedAPIClient.supportedAPIVersion else {
            throw SelfHostedAPIError.incompatibleServer(
                "API version \(status.apiVersion), client supports \(SelfHostedAPIClient.supportedAPIVersion)")
        }
        return SelfHostedServerIdentity(
            service: status.service,
            apiVersion: status.apiVersion,
            serverVersion: status.serverVersion,
            capabilities: status.capabilities
        )
    }

    // MARK: - Collaboration: invitations

    public func createInvite(
        createdBy: String,
        role: CollaborationRole,
        branchIDs: [String] = [],
        folderIDs: [String] = []
    ) async throws -> SelfHostedInvitation {
        let body: [String: Any] = [
            "created_by": createdBy,
            "role": role.rawValue,
            "branch_ids": branchIDs,
            "folder_ids": folderIDs
        ]
        let data = try await post("/invite", body: body, context: "createInvite")
        return try decode(SelfHostedInvitation.self, from: data, context: "createInvite")
    }

    public func lookupInvite(code: String) async throws -> SelfHostedInvitation {
        let data = try await get("/invite/\(code)", context: "lookupInvite(\(code))")
        return try decode(SelfHostedInvitation.self, from: data, context: "lookupInvite(\(code))")
    }

    /// Accept an invitation as a new member. Returns the accepted member's
    /// role. Throws .invitationExpired for HTTP 410.
    public func acceptInvite(code: String, memberID: String, memberName: String) async throws -> CollaborationRole {
        let body: [String: Any] = ["member_id": memberID, "member_name": memberName]
        let data = try await post("/invite/\(code)", body: body, context: "acceptInvite(\(code))")
        struct AcceptResponse: Decodable {
            let role: CollaborationRole
        }
        let resp = try decode(AcceptResponse.self, from: data, context: "acceptInvite(\(code))")
        return resp.role
    }

    public func revokeInvite(code: String) async throws {
        _ = try await delete("/invite/\(code)", context: "revokeInvite(\(code))")
    }

    // MARK: - Collaboration: members

    public func listMembers() async throws -> [SelfHostedMember] {
        let data = try await get("/members", context: "listMembers")
        return try decode([SelfHostedMember].self, from: data, context: "listMembers")
    }

    public func updateMember(id: String, name: String, role: CollaborationRole) async throws {
        let body: [String: Any] = ["id": id, "name": name, "role": role.rawValue]
        _ = try await put("/members", body: body, context: "updateMember(\(id))")
    }

    public func removeMember(id: String) async throws {
        let path = try url("/members", queryItems: [URLQueryItem(name: "id", value: id)])
        _ = try await send(method: "DELETE", url: path, body: nil, context: "removeMember(\(id))")
    }

    // MARK: - Collaboration: branches

    public func listBranches() async throws -> [SelfHostedBranch] {
        let data = try await get("/branches", context: "listBranches")
        return try decode([SelfHostedBranch].self, from: data, context: "listBranches")
    }

    public func createBranch(_ branch: SelfHostedBranch) async throws {
        let body: [String: Any] = [
            "id": branch.id,
            "name": branch.name,
            "kind": branch.kind.rawValue,
            "is_seeded": branch.isSeeded,
            "member_ids": branch.memberIDs
        ]
        _ = try await post("/branches", body: body, context: "createBranch(\(branch.id))")
    }

    public func getBranch(id: String) async throws -> SelfHostedBranch {
        let data = try await get("/branches/\(id)", context: "getBranch(\(id))")
        return try decode(SelfHostedBranch.self, from: data, context: "getBranch(\(id))")
    }

    public func updateBranch(_ branch: SelfHostedBranch) async throws {
        let body: [String: Any] = [
            "name": branch.name,
            "kind": branch.kind.rawValue,
            "is_seeded": branch.isSeeded,
            "member_ids": branch.memberIDs
        ]
        _ = try await put("/branches/\(branch.id)", body: body, context: "updateBranch(\(branch.id))")
    }

    public func deleteBranch(id: String) async throws {
        _ = try await delete("/branches/\(id)", context: "deleteBranch(\(id))")
    }

    // MARK: - Collaboration: folders

    public func listFolders(branchID: String? = nil) async throws -> [SelfHostedFolder] {
        var query: [URLQueryItem] = []
        if let branchID {
            query.append(URLQueryItem(name: "branch_id", value: branchID))
        }
        let path = try url("/folders", queryItems: query)
        let data = try await send(method: "GET", url: path, body: nil, context: "listFolders")
        return try decode([SelfHostedFolder].self, from: data, context: "listFolders")
    }

    public func createFolder(_ folder: SelfHostedFolder) async throws {
        var body: [String: Any] = [
            "id": folder.id,
            "branch_id": folder.branchID,
            "name": folder.name,
            "member_ids": folder.memberIDs
        ]
        if let parentID = folder.parentID {
            body["parent_id"] = parentID
        }
        _ = try await post("/folders", body: body, context: "createFolder(\(folder.id))")
    }

    public func updateFolder(_ folder: SelfHostedFolder) async throws {
        var body: [String: Any] = [
            "branch_id": folder.branchID,
            "name": folder.name,
            "member_ids": folder.memberIDs
        ]
        if let parentID = folder.parentID {
            body["parent_id"] = parentID
        }
        _ = try await put("/folders/\(folder.id)", body: body, context: "updateFolder(\(folder.id))")
    }

    public func deleteFolder(id: String) async throws {
        _ = try await delete("/folders/\(id)", context: "deleteFolder(\(id))")
    }

    // MARK: - Backup (opaque encrypted archives)

    public func uploadBackup(id: String, data: Data) async throws -> SelfHostedBackupMeta {
        let path = try url("/backup/push", queryItems: [URLQueryItem(name: "id", value: id)])
        let resp = try await send(method: "PUT", url: path, body: data, context: "uploadBackup(\(id))")
        return try decode(SelfHostedBackupMeta.self, from: resp, context: "uploadBackup(\(id))")
    }

    public func listBackups() async throws -> [SelfHostedBackupMeta] {
        let data = try await get("/backup/list", context: "listBackups")
        return try decode([SelfHostedBackupMeta].self, from: data, context: "listBackups")
    }

    public func downloadBackup(id: String) async throws -> Data {
        try await get("/backup/pull/\(id)", context: "downloadBackup(\(id))")
    }

    public func deleteBackup(id: String) async throws {
        _ = try await delete("/backup/\(id)", context: "deleteBackup(\(id))")
    }

    // MARK: - Attachments (opaque blobs)

    public func uploadAttachment(id: String, data: Data) async throws {
        let path = try url("/attachment/upload", queryItems: [URLQueryItem(name: "id", value: id)])
        _ = try await send(method: "PUT", url: path, body: data, context: "uploadAttachment(\(id))")
    }

    public func listAttachments() async throws -> [SelfHostedAttachmentMeta] {
        let data = try await get("/attachment/list", context: "listAttachments")
        return try decode([SelfHostedAttachmentMeta].self, from: data, context: "listAttachments")
    }

    public func downloadAttachment(id: String) async throws -> Data {
        try await get("/attachment/download/\(id)", context: "downloadAttachment(\(id))")
    }

    public func deleteAttachment(id: String) async throws {
        _ = try await delete("/attachment/\(id)", context: "deleteAttachment(\(id))")
    }

    // MARK: - HTTP plumbing

    /// Build a URL from the configured base + path, preserving scheme,
    /// host, port, and any base path (e.g. behind a reverse proxy).
    /// IDs inside `path` are passed through; query items are encoded by
    /// URLComponents.
    private func url(_ path: String, queryItems: [URLQueryItem] = []) throws -> URL {
        var components = URLComponents()
        components.scheme = baseURL.scheme
        components.host = baseURL.host
        components.port = baseURL.port
        components.path = baseURL.path + path
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw SelfHostedAPIError.invalidURL(baseURL.absoluteString + path)
        }
        return url
    }

    private func get(_ path: String, context: String) async throws -> Data {
        let target = try url(path)
        return try await send(method: "GET", url: target, body: nil, context: context)
    }

    private func post(_ path: String, body: [String: Any], context: String) async throws -> Data {
        let target = try url(path)
        let payload = try JSONSerialization.data(withJSONObject: body)
        return try await send(method: "POST", url: target, body: payload, context: context)
    }

    private func put(_ path: String, body: [String: Any], context: String) async throws -> Data {
        let target = try url(path)
        let payload = try JSONSerialization.data(withJSONObject: body)
        return try await send(method: "PUT", url: target, body: payload, context: context)
    }

    private func delete(_ path: String, context: String) async throws -> Data {
        let target = try url(path)
        return try await send(method: "DELETE", url: target, body: nil, context: context)
    }

    private func send(
        method: String,
        url: URL,
        body: Data?,
        context: String
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            if method == "POST" || method == "PUT" {
                request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            }
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw transportError(error)
        } catch {
            throw SelfHostedAPIError.unreachable(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw SelfHostedAPIError.invalidResponse("no HTTP response for \(context)")
        }

        guard (200...299).contains(http.statusCode) else {
            throw errorFor(status: http.statusCode, data: data, context: context)
        }
        return data
    }

    private func transportError(_ error: URLError) -> SelfHostedAPIError {
        switch error.code {
        case .timedOut:
            return .timeout
        case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
             .cannotFindHost, .dnsLookupFailed, .internationalRoamingOff:
            return .unreachable(error.localizedDescription)
        default:
            return .unreachable(error.localizedDescription)
        }
    }

    private func errorFor(status: Int, data: Data, context: String) -> SelfHostedAPIError {
        if let envelope = try? JSONDecoder().decode(ServerErrorEnvelope.self, from: data) {
            switch envelope.error.code {
            case "unauthorized":
                return .unauthorized
            case "not_found":
                return .notFound(envelope.error.message)
            case "conflict":
                return .conflict(envelope.error.message)
            case "expired":
                return .invitationExpired
            case "payload_too_large":
                return .payloadTooLarge
            case "invalid_request":
                return .invalidRequest(envelope.error.message)
            case "method_not_allowed":
                return .httpStatus(status, envelope.error.message)
            default:
                return .serverError(status, envelope.error.message)
            }
        }
        let body = String(data: data, encoding: .utf8) ?? "<non-text body>"
        return SelfHostedAPIError.httpStatus(status, "\(context): \(body)")
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data, context: String) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw SelfHostedAPIError.invalidResponse("\(context): \(error.localizedDescription)")
        }
    }
}

// MARK: - Capability check
//
// Runs the same end-to-end flows the contract checker executable runs
// against a LIVE server: identity, collaboration round trip, backup
// round trip, attachment round trip. Every object it creates carries a
// unique run prefix and is deleted afterwards.

public struct SelfHostedCapabilityReport: Sendable {
    public var identity: SelfHostedServerIdentity?
    public var collaboration: Result<String, SelfHostedAPIError>
    public var backups: Result<String, SelfHostedAPIError>
    public var attachments: Result<String, SelfHostedAPIError>

    public init(
        identity: SelfHostedServerIdentity?,
        collaboration: Result<String, SelfHostedAPIError>,
        backups: Result<String, SelfHostedAPIError>,
        attachments: Result<String, SelfHostedAPIError>
    ) {
        self.identity = identity
        self.collaboration = collaboration
        self.backups = backups
        self.attachments = attachments
    }

    public var allPassed: Bool {
        if case .success = collaboration, case .success = backups, case .success = attachments {
            return true
        }
        return false
    }
}

public struct SelfHostedCapabilityCheck {
    private let client: SelfHostedAPIClient
    private let runID: String

    public init(client: SelfHostedAPIClient, runID: String = "run-\(UUID().uuidString.prefix(8))") {
        self.client = client
        self.runID = runID
    }

    /// Run every supported flow against the live server. Creates only
    /// runID-prefixed objects and removes them before returning.
    public func run() async -> SelfHostedCapabilityReport {
        let identity: SelfHostedServerIdentity?
        do {
            identity = try await client.serverIdentity()
        } catch let error as SelfHostedAPIError {
            return SelfHostedCapabilityReport(
                identity: nil,
                collaboration: .failure(error),
                backups: .failure(error),
                attachments: .failure(error)
            )
        } catch {
            let err = SelfHostedAPIError.unreachable(error.localizedDescription)
            return SelfHostedCapabilityReport(identity: nil, collaboration: .failure(err), backups: .failure(err), attachments: .failure(err))
        }

        let collaboration = await runCollaboration()
        let backups = await runBackups()
        let attachments = await runAttachments()

        return SelfHostedCapabilityReport(
            identity: identity,
            collaboration: collaboration,
            backups: backups,
            attachments: attachments
        )
    }

    private func runCollaboration() async -> Result<String, SelfHostedAPIError> {
        let memberID = "\(runID)-member"
        let branchID = "\(runID)-branch"
        let folderID = "\(runID)-folder"

        do {
            // Invitation lifecycle
            let invite = try await client.createInvite(createdBy: memberID, role: .organizer)
            let lookedUp = try await client.lookupInvite(code: invite.code)
            guard lookedUp.role == .organizer else {
                throw SelfHostedAPIError.invalidResponse("invite role \(lookedUp.role.rawValue), expected organizer")
            }
            let acceptedRole = try await client.acceptInvite(
                code: invite.code, memberID: memberID, memberName: "Capability Check")
            guard acceptedRole == .organizer else {
                throw SelfHostedAPIError.invalidResponse("accepted role \(acceptedRole.rawValue), expected organizer")
            }

            // Member list reflects the new member
            let members = try await client.listMembers()
            guard members.contains(where: { $0.id == memberID }) else {
                throw SelfHostedAPIError.invalidResponse("member \(memberID) missing from member list")
            }

            // Branch lifecycle
            try await client.createBranch(SelfHostedBranch(id: branchID, name: "Capability Branch", kind: .custom))
            var branch = try await client.getBranch(id: branchID)
            branch = SelfHostedBranch(
                id: branchID, name: "Capability Branch Renamed",
                kind: branch.kind, memberIDs: [memberID])
            try await client.updateBranch(branch)
            let updatedBranch = try await client.getBranch(id: branchID)
            guard updatedBranch.name == "Capability Branch Renamed",
                  updatedBranch.memberIDs.contains(memberID) else {
                throw SelfHostedAPIError.invalidResponse("branch update not reflected")
            }

            // Folder lifecycle
            try await client.createFolder(SelfHostedFolder(id: folderID, branchID: branchID, name: "Capability Folder"))
            let folders = try await client.listFolders(branchID: branchID)
            guard folders.contains(where: { $0.id == folderID }) else {
                throw SelfHostedAPIError.invalidResponse("folder missing from branch filter")
            }

            // Cleanup (best effort)
            try? await client.deleteFolder(id: folderID)
            try? await client.deleteBranch(id: branchID)
            try? await client.removeMember(id: memberID)

            return .success("invite → accept → member → branch → folder (5 ops)")
        } catch let error as SelfHostedAPIError {
            return .failure(error)
        } catch {
            return .failure(.unreachable(error.localizedDescription))
        }
    }

    private func runBackups() async -> Result<String, SelfHostedAPIError> {
        let id = "\(runID)-backup"
        let payload = Data((0..<4096).map { UInt8($0 % 251) })

        do {
            let meta = try await client.uploadBackup(id: id, data: payload)
            guard meta.id == id, meta.size == Int64(payload.count) else {
                throw SelfHostedAPIError.invalidResponse("backup meta mismatch: \(meta)")
            }
            let listed = try await client.listBackups()
            guard listed.contains(where: { $0.id == id }) else {
                throw SelfHostedAPIError.invalidResponse("uploaded backup missing from list")
            }
            let downloaded = try await client.downloadBackup(id: id)
            guard downloaded == payload else {
                throw SelfHostedAPIError.invalidResponse("backup bytes differ after round trip")
            }
            try? await client.deleteBackup(id: id)
            return .success("push → list → pull → byte-compare → delete (5 ops)")
        } catch let error as SelfHostedAPIError {
            return .failure(error)
        } catch {
            return .failure(.unreachable(error.localizedDescription))
        }
    }

    private func runAttachments() async -> Result<String, SelfHostedAPIError> {
        let id = "\(runID)-att"
        let payload = Data((0..<2048).map { UInt8(($0 * 7) % 256) })

        do {
            try await client.uploadAttachment(id: id, data: payload)
            let listed = try await client.listAttachments()
            guard listed.contains(where: { $0.id == id }) else {
                throw SelfHostedAPIError.invalidResponse("uploaded attachment missing from list")
            }
            let downloaded = try await client.downloadAttachment(id: id)
            guard downloaded == payload else {
                throw SelfHostedAPIError.invalidResponse("attachment bytes differ after round trip")
            }
            try? await client.deleteAttachment(id: id)
            return .success("upload → list → download → byte-compare → delete (5 ops)")
        } catch let error as SelfHostedAPIError {
            return .failure(error)
        } catch {
            return .failure(.unreachable(error.localizedDescription))
        }
    }
}