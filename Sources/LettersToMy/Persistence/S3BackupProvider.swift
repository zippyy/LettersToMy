import CommonCrypto
import Foundation
import LettersToMyCore

/// Stores backup archives on any S3-compatible object storage
/// (AWS S3, MinIO, DigitalOcean Spaces, Backblaze B2, etc).
final class S3BackupProvider: BackupProvider, @unchecked Sendable {
    let destination: BackupDestination = .s3Compatible
    private let endpointURL: URL
    private let bucket: String
    private let accessKey: String
    private let secretKey: String
    private let region: String

    init(endpointURL: URL, bucket: String, accessKey: String, secretKey: String, region: String = "us-east-1") {
        self.endpointURL = endpointURL
        self.bucket = bucket
        self.accessKey = accessKey
        self.secretKey = secretKey
        self.region = region
    }

    func isReady() async -> Bool {
        // HEAD on the bucket to verify connectivity
        guard let req = try? signedRequest(method: "HEAD", path: "") else { return false }
        guard let (_, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse else { return false }
        return (200...299).contains(http.statusCode) || http.statusCode == 403
    }

    func store(archive: Data, manifest: BackupManifest) async throws -> BackupRemoteHandle {
        let key = "\(manifest.archiveID.uuidString).letterstomy"
        var req = try signedRequest(method: "PUT", path: key)
        req.httpBody = archive
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        req.setValue("\(archive.count)", forHTTPHeaderField: "Content-Length")

        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw BackupError.providerError(.s3Compatible, "Upload failed.")
        }

        let location = "\(bucket)/\(key)"
        return BackupRemoteHandle(
            identifier: key,
            location: location,
            metadata: ["key": key, "bucket": bucket]
        )
    }

    func retrieve(handle: BackupRemoteHandle) async throws -> Data {
        let key = handle.metadata["key"] ?? handle.identifier
        let req = try signedRequest(method: "GET", path: key)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw BackupError.providerError(.s3Compatible, "Download failed.")
        }
        return data
    }

    func listRemoteBackups() async throws -> [BackupRemoteHandle] {
        let req = try signedRequest(method: "GET", path: "")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else { return [] }

        return parseS3ListXML(data: data)
    }

    func remove(handle: BackupRemoteHandle) async throws {
        let key = handle.metadata["key"] ?? handle.identifier
        let req = try signedRequest(method: "DELETE", path: key)
        _ = try? await URLSession.shared.data(for: req)
    }

    func availableSpace() async throws -> Int64? { nil }

    // MARK: - AWS Signature V4

    private func signedRequest(method: String, path: String) throws -> URLRequest {
        let url = endpointURL
            .appendingPathComponent(bucket)
            .appendingPathComponent(path)

        let now = Date()
        let dateStamp = ISO8601DateFormatter.short.string(from: now)
        let amzDate = ISO8601DateFormatter.long.string(from: now)

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(amzDate, forHTTPHeaderField: "X-Amz-Date")
        req.setValue("UNSIGNED-PAYLOAD", forHTTPHeaderField: "X-Amz-Content-SHA256")

        let signedHeaders = "host;x-amz-content-sha256;x-amz-date"
        let canonicalRequest = [
            method,
            url.path.isEmpty ? "/" : url.path,
            "", // query string
            "host:\(url.host ?? "")\nx-amz-content-sha256:UNSIGNED-PAYLOAD\nx-amz-date:\(amzDate)\n",
            signedHeaders,
            "UNSIGNED-PAYLOAD"
        ].joined(separator: "\n")

        let scope = "\(dateStamp)/\(region)/s3/aws4_request"
        let stringToSign = [
            "AWS4-HMAC-SHA256",
            amzDate,
            scope,
            sha256(canonicalRequest)
        ].joined(separator: "\n")

        guard let signingKey = hmacSignatureV4(dateStamp: dateStamp) else {
            throw BackupError.providerError(.s3Compatible, "Failed to sign request.")
        }
        guard let signature = hmac(stringToSign, keyData: signingKey) else {
            throw BackupError.providerError(.s3Compatible, "Failed to sign request.")
        }

        req.setValue(
            "AWS4-HMAC-SHA256 Credential=\(accessKey)/\(scope),SignedHeaders=\(signedHeaders),Signature=\(signature)",
            forHTTPHeaderField: "Authorization"
        )

        return req
    }

    private func hmacSignatureV4(dateStamp: String) -> Data? {
        guard let kDate = hmac(dateStamp, key: "AWS4\(secretKey)"),
              let kRegion = hmac(region, keyData: kDate),
              let kService = hmac("s3", keyData: kRegion),
              let kSigning = hmac("aws4_request", keyData: kService) else {
            return nil
        }
        return kSigning
    }

    private func hmac(_ string: String, key: String) -> Data? {
        guard let keyData = key.data(using: .utf8) else { return nil }
        return hmac(string, keyData: keyData)
    }

    private func hmac(_ string: String, keyData: Data) -> Data? {
        guard let stringData = string.data(using: .utf8) else { return nil }
        var result = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        keyData.withUnsafeBytes { keyBytes in
            stringData.withUnsafeBytes { dataBytes in
                CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256),
                       keyBytes.baseAddress, keyData.count,
                       dataBytes.baseAddress, stringData.count,
                       &result)
            }
        }
        return Data(result)
    }

    private func sha256(_ string: String) -> String {
        guard let data = string.data(using: .utf8) else { return "" }
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { bytes in
            // CC_SHA256 returns a digest pointer (non-Void), so capture
            // it explicitly to satisfy the unused-result warning.
            _ = CC_SHA256(bytes.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    private func parseS3ListXML(data: Data) -> [BackupRemoteHandle] {
        guard let xml = String(data: data, encoding: .utf8) else { return [] }
        var handles: [BackupRemoteHandle] = []

        let pattern = #"<Key>([^<]+)</Key>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(xml.startIndex..., in: xml)
        regex.enumerateMatches(in: xml, range: range) { match, _, _ in
            guard let match, let r = Range(match.range(at: 1), in: xml) else { return }
            let key = String(xml[r])
            guard key.hasSuffix(".letterstomy") else { return }
            handles.append(BackupRemoteHandle(
                identifier: key,
                location: "\(bucket)/\(key)",
                metadata: ["key": key, "bucket": bucket]
            ))
        }
        return handles
    }
}

extension ISO8601DateFormatter {
    nonisolated(unsafe) static let short: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        return f
    }()
    nonisolated(unsafe) static let long: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withFullTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        return f
    }()
}