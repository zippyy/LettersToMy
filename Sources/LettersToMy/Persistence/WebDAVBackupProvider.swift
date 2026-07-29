import Foundation
import LettersToMyCore

/// Stores backup archives on any WebDAV-compatible server
/// (Nextcloud, ownCloud, Apache mod_dav, etc).
final class WebDAVBackupProvider: BackupProvider, @unchecked Sendable {
    let destination: BackupDestination = .webDAV
    private let baseURL: URL
    private let username: String?
    private let password: String?

    init(baseURL: URL, username: String? = nil, password: String? = nil) {
        self.baseURL = baseURL
        self.username = username
        self.password = password
    }

    func isReady() async -> Bool {
        // Quick connectivity check
        var req = URLRequest(url: baseURL)
        req.httpMethod = "PROPFIND"
        req.setValue("0", forHTTPHeaderField: "Depth")
        applyAuth(to: &req)

        guard let (_, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse else { return false }
        return (200...299).contains(http.statusCode) || http.statusCode == 401
    }

    func store(archive: Data, manifest: BackupManifest) async throws -> BackupRemoteHandle {
        let filename = "\(manifest.archiveID.uuidString).letterstomy"
        let fileURL = baseURL.appendingPathComponent(filename)

        var req = URLRequest(url: fileURL)
        req.httpMethod = "PUT"
        req.httpBody = archive
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        applyAuth(to: &req)

        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw BackupError.providerError(.webDAV, "Upload failed: \((resp as? HTTPURLResponse)?.statusCode ?? 0)")
        }

        return BackupRemoteHandle(
            identifier: filename,
            location: fileURL.absoluteString,
            metadata: ["url": fileURL.absoluteString]
        )
    }

    func retrieve(handle: BackupRemoteHandle) async throws -> Data {
        let urlString = handle.metadata["url"] ?? handle.location
        guard let url = URL(string: urlString) else {
            throw BackupError.providerError(.webDAV, "Invalid URL in handle.")
        }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        applyAuth(to: &req)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw BackupError.providerError(.webDAV, "Download failed.")
        }
        return data
    }

    func listRemoteBackups() async throws -> [BackupRemoteHandle] {
        var req = URLRequest(url: baseURL)
        req.httpMethod = "PROPFIND"
        req.setValue("1", forHTTPHeaderField: "Depth")
        applyAuth(to: &req)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else { return [] }

        return parsePROPFIND(data: data, baseURL: baseURL)
    }

    func remove(handle: BackupRemoteHandle) async throws {
        let urlString = handle.metadata["url"] ?? handle.location
        guard let url = URL(string: urlString) else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        applyAuth(to: &req)
        _ = try? await URLSession.shared.data(for: req)
    }

    func availableSpace() async throws -> Int64? { nil }

    // MARK: - Private

    private func applyAuth(to request: inout URLRequest) {
        if let username, let password {
            let credentials = "\(username):\(password)"
            guard let encoded = credentials.data(using: .utf8)?.base64EncodedString() else { return }
            request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
        }
    }

    private func parsePROPFIND(data: Data, baseURL: URL) -> [BackupRemoteHandle] {
        // Simple XML parsing for PROPFIND responses — extract href elements
        guard let xml = String(data: data, encoding: .utf8) else { return [] }
        var handles: [BackupRemoteHandle] = []

        let pattern = #"<D:href>([^<]+)</D:href>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let range = NSRange(xml.startIndex..., in: xml)
        regex.enumerateMatches(in: xml, range: range) { match, _, _ in
            guard let match, let r = Range(match.range(at: 1), in: xml) else { return }
            let path = String(xml[r])
            guard path.hasSuffix(".letterstomy") else { return }
            let fullURL = URL(string: path, relativeTo: baseURL) ?? baseURL.appendingPathComponent(path)
            let filename = fullURL.lastPathComponent
            handles.append(BackupRemoteHandle(
                identifier: filename,
                location: fullURL.absoluteString,
                metadata: ["url": fullURL.absoluteString]
            ))
        }

        return handles
    }
}