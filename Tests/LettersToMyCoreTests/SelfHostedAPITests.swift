import Testing
import Foundation
@testable import LettersToMyCore

// MARK: - URLProtocol stub

/// Routes URLSession traffic through an in-process handler so contract
/// tests never touch the network.
///
/// The handler is a mutable static; the suite is serialized so parallel
/// test execution can never race on it.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    /// The suite is serialized, so this global is only touched from one
    /// test at a time.
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct SelfHostedAPITests {

func makeClient() throws -> SelfHostedAPIClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    let session = URLSession(configuration: config)
    return try SelfHostedAPIClient(
        serverURL: "https://selfhosted.example.com",
        apiToken: "test-token",
        session: session
    )
}

func stub(_ status: Int, _ body: String) {
    StubURLProtocol.requestHandler = { request in
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (response, Data(body.utf8))
    }
}

// MARK: - Status identity

@Test func statusIdentityDecodes() async throws {
    let json = """
    {
      "service": "LettersToMy-SelfHostedSync",
      "api_version": 1,
      "server_version": "0.3.0",
      "capabilities": ["collaboration", "backups", "attachments"],
      "syncs": [],
      "attachments": [],
      "recoveries": [],
      "branches": 0, "folders": 0, "members": 0, "invitations": 0
    }
    """
    stub(200, json)
    let client = try makeClient()
    let identity = try await client.serverIdentity()
    #expect(identity.service == "LettersToMy-SelfHostedSync")
    #expect(identity.apiVersion == 1)
    #expect(identity.serverVersion == "0.3.0")
    #expect(identity.supports("collaboration"))
    #expect(identity.supports("backups"))
    #expect(identity.supports("attachments"))
    #expect(!identity.supports("time-travel"))
}

@Test func incompatibleServiceRejected() async throws {
    stub(200, #"{"service":"nginx","api_version":1,"server_version":"x","capabilities":[],"syncs":[],"attachments":[],"recoveries":[],"branches":0,"folders":0,"members":0,"invitations":0}"#)
    let client = try makeClient()
    do {
        _ = try await client.serverIdentity()
        Issue.record("expected incompatibleServer error")
    } catch let error as SelfHostedAPIError {
        guard case .incompatibleServer = error else {
            Issue.record("expected incompatibleServer, got \(error)")
            return
        }
    }
}

@Test func wrongAPIVersionRejected() async throws {
    stub(200, #"{"service":"LettersToMy-SelfHostedSync","api_version":2,"server_version":"x","capabilities":[],"syncs":[],"attachments":[],"recoveries":[],"branches":0,"folders":0,"members":0,"invitations":0}"#)
    let client = try makeClient()
    do {
        _ = try await client.serverIdentity()
        Issue.record("expected incompatibleServer error")
    } catch let error as SelfHostedAPIError {
        guard case .incompatibleServer = error else {
            Issue.record("expected incompatibleServer, got \(error)")
            return
        }
    }
}

// MARK: - Error mapping

@Test func unauthorizedMaps() async throws {
    stub(401, #"{"error":{"code":"unauthorized","message":"The API token is missing or invalid."}}"#)
    let client = try makeClient()
    await #expect(throws: SelfHostedAPIError.unauthorized) {
        try await client.listMembers()
    }
}

@Test func notFoundMaps() async throws {
    stub(404, #"{"error":{"code":"not_found","message":"branch not found"}}"#)
    let client = try makeClient()
    await #expect(throws: SelfHostedAPIError.notFound("branch not found")) {
        try await client.getBranch(id: "missing")
    }
}

@Test func conflictMaps() async throws {
    stub(409, #"{"error":{"code":"conflict","message":"a member with this id already exists"}}"#)
    let client = try makeClient()
    await #expect(throws: SelfHostedAPIError.conflict("a member with this id already exists")) {
        _ = try await client.acceptInvite(code: "ABC123", memberID: "m1", memberName: "M")
    }
}

@Test func expiredInviteMaps() async throws {
    stub(410, #"{"error":{"code":"expired","message":"invitation expired"}}"#)
    let client = try makeClient()
    await #expect(throws: SelfHostedAPIError.invitationExpired) {
        _ = try await client.lookupInvite(code: "EXPIRED")
    }
}

@Test func payloadTooLargeMaps() async throws {
    stub(413, #"{"error":{"code":"payload_too_large","message":"upload exceeds the configured limit"}}"#)
    let client = try makeClient()
    await #expect(throws: SelfHostedAPIError.payloadTooLarge) {
        _ = try await client.uploadBackup(id: "big", data: Data())
    }
}

@Test func invalidRequestMaps() async throws {
    stub(400, #"{"error":{"code":"invalid_request","message":"unknown role superuser"}}"#)
    let client = try makeClient()
    await #expect(throws: SelfHostedAPIError.invalidRequest("unknown role superuser")) {
        _ = try await client.createInvite(createdBy: "o", role: .viewer)
    }
}

@Test func plainTextErrorStillSurfaces() async throws {
    stub(500, "internal server exploded")
    let client = try makeClient()
    do {
        _ = try await client.listBranches()
        Issue.record("expected httpStatus error")
    } catch let error as SelfHostedAPIError {
        guard case .httpStatus(500, _) = error else {
            Issue.record("expected httpStatus(500, _), got \(error)")
            return
        }
    }
}

// MARK: - Invitation decode

@Test func invitationDecodesArrays() async throws {
    let json = """
    {"code":"ABC123","created_by":"owner-1","role":"organizer",
     "branch_ids":["b1","b2"],"folder_ids":[],"expires":1787851693356}
    """
    stub(200, json)
    let client = try makeClient()
    let invite = try await client.lookupInvite(code: "ABC123")
    #expect(invite.code == "ABC123")
    #expect(invite.createdBy == "owner-1")
    #expect(invite.role == .organizer)
    #expect(invite.branchIDs == ["b1", "b2"])
    #expect(invite.folderIDs.isEmpty)
    #expect(invite.expires == 1787851693356) // Unix milliseconds
}

@Test func invitationToleratesNullArrays() async throws {
    let json = """
    {"code":"ABC123","created_by":"owner-1","role":"viewer",
     "branch_ids":null,"folder_ids":null,"expires":1787851693356}
    """
    stub(200, json)
    let client = try makeClient()
    let invite = try await client.lookupInvite(code: "ABC123")
    #expect(invite.branchIDs.isEmpty)
    #expect(invite.folderIDs.isEmpty)
}

// MARK: - Branch / folder decode

@Test func branchDecodesNullMemberIDs() async throws {
    let json = """
    {"id":"b1","name":"Maternal","kind":"maternal","is_seeded":false,
     "member_ids":null,"created_at":1787851693356}
    """
    stub(200, json)
    let client = try makeClient()
    let branch = try await client.getBranch(id: "b1")
    #expect(branch.id == "b1")
    #expect(branch.kind == .maternal)
    #expect(branch.memberIDs.isEmpty)
    #expect(!branch.isSeeded)
    #expect(branch.createdAt == 1787851693356)
}

// MARK: - Role contract

@Test func allRolesDecode() async throws {
    for role in ["owner", "parentAdmin", "organizer", "contributor", "viewer", "recipient"] {
        stub(200, #"[{"id":"m1","name":"M","role":"\#(role)","since":1787851693356}]"#)
        let client = try makeClient()
        let members = try await client.listMembers()
        #expect(members.first?.role.rawValue == role)
    }
}

@Test func unknownRoleFailsLoudly() async throws {
    stub(200, #"[{"id":"m1","name":"M","role":"superuser","since":1787851693356}]"#)
    let client = try makeClient()
    do {
        _ = try await client.listMembers()
        Issue.record("expected invalidResponse error")
    } catch let error as SelfHostedAPIError {
        guard case .invalidResponse = error else {
            Issue.record("expected invalidResponse, got \(error)")
            return
        }
    }
}

// MARK: - Request construction

@Test func createInviteSendsCanonicalBody() async throws {
    var capturedURL: URL?
    var capturedMethod: String?
    var capturedAuth: String?
    var capturedBody: Data?
    StubURLProtocol.requestHandler = { request in
        capturedURL = request.url
        capturedMethod = request.httpMethod
        capturedAuth = request.value(forHTTPHeaderField: "Authorization")
        capturedBody = request.httpBody ?? drainBody(from: request)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let body = try! JSONSerialization.data(withJSONObject: [
            "code": "ABC123", "created_by": "owner-1", "role": "organizer",
            "branch_ids": ["b1"], "folder_ids": [], "expires": 1787851693356
        ])
        return (response, body)
    }
    let client = try makeClient()
    _ = try await client.createInvite(createdBy: "owner-1", role: .organizer, branchIDs: ["b1"])
    #expect(capturedURL?.path == "/invite")
    #expect(capturedMethod == "POST")
    #expect(capturedAuth == "Bearer test-token")
    let body = try #require(capturedBody)
    let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(json["role"] as? String == "organizer")
    #expect(json["created_by"] as? String == "owner-1")
    #expect(json["branch_ids"] as? [String] == ["b1"])
}

/// URLSession delivers the request body as a stream to URLProtocol, not
/// as `httpBody`; drain the stream when httpBody is absent.
private func drainBody(from request: URLRequest) -> Data? {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }
    var data = Data()
    let bufferSize = 4096
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }
    while stream.hasBytesAvailable {
        let read = stream.read(buffer, maxLength: bufferSize)
        if read <= 0 { break }
        data.append(buffer, count: read)
    }
    return data
}

@Test func memberDeletionUsesEncodedQueryItem() async throws {
    var captured: URL?
    StubURLProtocol.requestHandler = { request in
        captured = request.url
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (response, Data())
    }
    let client = try makeClient()
    try await client.removeMember(id: "m-1")
    let url = try #require(captured)
    #expect(url.path == "/members")
    #expect(url.query == "id=m-1")
}

@Test func authHeaderSentOnAllRequests() async throws {
    var headers: [String: String] = [:]
    StubURLProtocol.requestHandler = { request in
        headers = request.allHTTPHeaderFields ?? [:]
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (response, Data("[]".utf8))
    }
    let client = try makeClient()
    _ = try await client.listFolders(branchID: "b1")
    #expect(headers["Authorization"] == "Bearer test-token")
}

@Test func baseURLValidation() {
    for bad in ["not a url", "", "127.0.0.1:8080"] {
        do {
            _ = try SelfHostedAPIClient(serverURL: bad, apiToken: "x")
            Issue.record("expected invalidURL for \(bad)")
        } catch let error as SelfHostedAPIError {
            guard case .invalidURL = error else {
                Issue.record("expected invalidURL, got \(error)")
                return
            }
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }
}

@Test func portAndProxyBasePathPreserved() async throws {
    var captured: URL?
    StubURLProtocol.requestHandler = { request in
        captured = request.url
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (response, Data("[]".utf8))
    }
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    let session = URLSession(configuration: config)
    let client = try SelfHostedAPIClient(
        serverURL: "http://192.168.1.50:8080/letters2my",
        apiToken: "t",
        session: session
    )
    _ = try await client.listMembers()
    let url = try #require(captured)
    #expect(url.scheme == "http")
    #expect(url.host == "192.168.1.50")
    #expect(url.port == 8080)
    #expect(url.path == "/letters2my/members")
}

// MARK: - Backup flow decode

@Test func backupRoundTripDTOs() async throws {
    stub(200, #"{"id":"backup-1","timestamp":1787851693356,"size":4096,"letter_count":3}"#)
    let client = try makeClient()
    let meta = try await client.uploadBackup(id: "backup-1", data: Data(repeating: 0, count: 4096))
    #expect(meta.id == "backup-1")
    #expect(meta.size == 4096)
    #expect(meta.letterCount == 3)
    #expect(meta.timestamp == 1787851693356)
}

}