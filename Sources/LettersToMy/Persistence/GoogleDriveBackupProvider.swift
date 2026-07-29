import Foundation
import LettersToMyCore

/// Stores backup archives on Google Drive. Requires OAuth 2.0
/// credentials configured in the app.
@MainActor
final class GoogleDriveBackupProvider: BackupProvider, @unchecked Sendable {
    nonisolated let destination: BackupDestination = .googleDrive

    // These must be set from a Google Cloud Console OAuth client.
    nonisolated(unsafe) static var clientID: String?
    nonisolated(unsafe) static var clientSecret: String?
    nonisolated(unsafe) static var refreshToken: String?

    nonisolated(unsafe) private static var accessToken: String?
    nonisolated(unsafe) private static var tokenExpiry: TimeInterval = 0

    nonisolated func isReady() async -> Bool {
        (try? await refreshAccessTokenIfNeeded()) != nil
    }

    func store(archive: Data, manifest: BackupManifest) async throws -> BackupRemoteHandle {
        let token = try await getAccessToken()
        let filename = "\(manifest.archiveID.uuidString).letterstomy"

        var req = URLRequest(url: URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = """
        {"name":"\(filename)","parents":["appDataFolder"]}
        """.data(using: .utf8)

        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let location = http.allHeaderFields["Location"] as? String,
              let uploadURL = URL(string: location) else {
            throw BackupError.providerError(.googleDrive, "Failed to initiate upload.")
        }

        var uploadReq = URLRequest(url: uploadURL)
        uploadReq.httpMethod = "PUT"
        uploadReq.httpBody = archive
        uploadReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (_, uploadResp) = try await URLSession.shared.data(for: uploadReq)
        guard let uploadHTTP = uploadResp as? HTTPURLResponse,
              uploadHTTP.statusCode == 200 || uploadHTTP.statusCode == 201 else {
            throw BackupError.providerError(.googleDrive, "Upload failed.")
        }

        return BackupRemoteHandle(
            identifier: filename,
            location: location,
            metadata: ["filename": filename]
        )
    }

    func retrieve(handle: BackupRemoteHandle) async throws -> Data {
        let token = try await getAccessToken()
        let filename = handle.metadata["filename"] ?? handle.identifier

        var listReq = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files?q=name='\(filename)'&spaces=appDataFolder")!)
        listReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (listData, _) = try await URLSession.shared.data(for: listReq)

        guard let json = try? JSONSerialization.jsonObject(with: listData) as? [String: Any],
              let files = json["files"] as? [[String: Any]],
              let fileID = files.first?["id"] as? String else {
            throw BackupError.providerError(.googleDrive, "File not found.")
        }

        var dlReq = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files/\(fileID)?alt=media")!)
        dlReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, dlResp) = try await URLSession.shared.data(for: dlReq)
        guard let http = dlResp as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw BackupError.providerError(.googleDrive, "Download failed.")
        }
        return data
    }

    nonisolated func listRemoteBackups() async throws -> [BackupRemoteHandle] {
        let token = try await getAccessToken()
        var req = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files?q=name+contains+'.letterstomy'&spaces=appDataFolder")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let files = json["files"] as? [[String: Any]] else { return [] }

        return files.compactMap { file in
            guard let name = file["name"] as? String else { return nil }
            return BackupRemoteHandle(
                identifier: name,
                location: name,
                metadata: ["filename": name]
            )
        }
    }

    nonisolated func remove(handle: BackupRemoteHandle) async throws {
        let token = try await getAccessToken()
        let filename = handle.metadata["filename"] ?? handle.identifier

        var listReq = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files?q=name='\(filename)'&spaces=appDataFolder")!)
        listReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (listData, _) = try await URLSession.shared.data(for: listReq)

        guard let json = try? JSONSerialization.jsonObject(with: listData) as? [String: Any],
              let files = json["files"] as? [[String: Any]],
              let fileID = files.first?["id"] as? String else { return }

        var delReq = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files/\(fileID)")!)
        delReq.httpMethod = "DELETE"
        delReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try? await URLSession.shared.data(for: delReq)
    }

    nonisolated func availableSpace() async throws -> Int64? { nil }

    // MARK: - OAuth

    private nonisolated func getAccessToken() async throws -> String {
        if let token = Self.accessToken, Date().timeIntervalSince1970 < Self.tokenExpiry {
            return token
        }
        return try await refreshAccessToken()
    }

    private nonisolated func refreshAccessTokenIfNeeded() async throws -> String {
        try await getAccessToken()
    }

    private func refreshAccessToken() async throws -> String {
        guard let clientID = Self.clientID,
              let clientSecret = Self.clientSecret,
              let refreshToken = Self.refreshToken else {
            throw BackupError.providerError(.googleDrive, "Google Drive not configured.")
        }

        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "client_id=\(clientID)&client_secret=\(clientSecret)&refresh_token=\(refreshToken)&grant_type=refresh_token"
        req.httpBody = body.data(using: .utf8)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String else {
            throw BackupError.providerError(.googleDrive, "OAuth token refresh failed.")
        }

        Self.accessToken = token
        Self.tokenExpiry = Date().timeIntervalSince1970 + ((json["expires_in"] as? TimeInterval) ?? 3600)
        return token
    }
}