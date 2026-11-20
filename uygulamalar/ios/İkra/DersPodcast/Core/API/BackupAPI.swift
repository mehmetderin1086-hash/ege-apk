import CryptoKit
import Foundation

// MARK: - #49 Mac'e artımlı yedek (sunucu: devServer ham yolları, `backup1` bayrağı)

/// Snapshot'taki tek dosya. `path` yedek düzenine göre (manifest.json, Audio/<id>.m4a …); `mtime` 1970'ten beri saniye.
nonisolated struct BackupFileRecord: Codable, Hashable, Sendable {
    var path: String
    var sha256: String
    var bytes: Int64
    var mtime: Double
}

nonisolated struct BackupSnapshotBody: Encodable, Sendable {
    var createdAt: String
    var device: String
    var appVersion: String
    var files: [BackupFileRecord]
}

nonisolated struct BackupCommitRequest: Encodable, Sendable { var snapshot: BackupSnapshotBody }
nonisolated struct BackupCommitResponse: Decodable, Sendable { var snapshotId: String }
nonisolated struct BackupMissingRequest: Encodable, Sendable { var hashes: [String] }
nonisolated struct BackupMissingResponse: Decodable, Sendable { var missing: [String] }
nonisolated struct BackupSnapshotRequest: Encodable, Sendable { var id: String }
nonisolated struct BackupSnapshotFiles: Decodable, Sendable { var files: [BackupFileRecord] }

/// Sunucudaki snapshot özeti (`files` dosya sayısı; dizi gelirse uzunluğu alınır).
nonisolated struct BackupSnapshotInfo: Decodable, Hashable, Sendable, Identifiable {
    var id: String
    var createdAt: String
    var device: String
    var files: Int
    var bytes: Int64

    private enum CodingKeys: String, CodingKey { case id, createdAt, device, files, bytes }

    init(id: String, createdAt: String, device: String, files: Int, bytes: Int64) {
        self.id = id
        self.createdAt = createdAt
        self.device = device
        self.files = files
        self.bytes = bytes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        createdAt = (try? c.decode(String.self, forKey: .createdAt)) ?? ""
        device = (try? c.decode(String.self, forKey: .device)) ?? ""
        if let n = try? c.decode(Int.self, forKey: .files) {
            files = n
        } else {
            files = (try? c.decode([BackupFileRecord].self, forKey: .files))?.count ?? 0
        }
        bytes = (try? c.decode(Int64.self, forKey: .bytes)) ?? 0
    }

    var date: Date? { try? Date(createdAt, strategy: .iso8601) }
}

nonisolated struct BackupListResponse: Decodable, Sendable { var snapshots: [BackupSnapshotInfo] }
nonisolated struct BackupDeleteResponse: Decodable, Sendable { var removedBlobs: Int? }
nonisolated private struct BackupEmptyBody: Encodable, Sendable {}

extension APIError {
    /// Mac'teki yedek kotası doldu (`POST /v1/backup/commit` → 507 `quota_exceeded`). Sunucu eski yedeği kendiliğinden silmez.
    nonisolated var isBackupQuotaExceeded: Bool { status == 507 || code == "quota_exceeded" }
}

nonisolated enum BackupBlobID {
    /// 64 küçük hex karakter (yol değildir).
    static func isValid(_ id: String) -> Bool {
        id.count == 64 && id.allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) }
    }

    /// Dosyayı 1 MB'lık parçalarla okuyarak SHA-256 (küçük hex). Yükleme özeti ve indirme doğrulaması aynı işlevi kullanır.
    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Yedek isteklerinin ağ kısıtı.
nonisolated enum BackupAPI {
    /// `allowsExpensive == false`: hücresel veride, kişisel erişim noktasında ve Düşük Veri Modu'nda istek gönderilmez
    /// (URLSession bağlantı hatası verir; çağıran bunu "ulaşılamadı" sayar).
    static func configure(_ request: inout URLRequest, allowsExpensive: Bool) {
        guard !allowsExpensive else { return }
        request.allowsExpensiveNetworkAccess = false
        request.allowsConstrainedNetworkAccess = false
    }
}

extension APIError {
    /// İndirilen yedek dosyasının özeti snapshot'taki özetle uyuşmuyor (bozuk ya da yarım indi).
    nonisolated static let backupHashMismatchCode = "hash_mismatch"
}

extension APIClient {
    nonisolated func backupMissing(_ hashes: [String]) async throws -> [String] {
        let r: BackupMissingResponse = try await post("/v1/backup/missing", BackupMissingRequest(hashes: hashes))
        return r.missing
    }

    nonisolated func backupCommit(_ snapshot: BackupSnapshotBody) async throws -> String {
        let r: BackupCommitResponse = try await post("/v1/backup/commit", BackupCommitRequest(snapshot: snapshot))
        return r.snapshotId
    }

    nonisolated func backupList() async throws -> [BackupSnapshotInfo] {
        let r: BackupListResponse = try await post("/v1/backup/list", BackupEmptyBody())
        return r.snapshots
    }

    nonisolated func backupSnapshot(id: String) async throws -> [BackupFileRecord] {
        let r: BackupSnapshotFiles = try await post("/v1/backup/snapshot", BackupSnapshotRequest(id: id))
        return r.files
    }

    /// `POST /v1/backup/delete { id }` → `{ ok, removedBlobs }`: snapshot'ı ve artık hiçbir yedeğin başvurmadığı
    /// dosyaları siler (kota aşımından çıkış yolu). Bilinmeyen kimlik 404.
    @discardableResult
    nonisolated func backupDelete(id: String) async throws -> Int {
        let r: BackupDeleteResponse = try await post("/v1/backup/delete", BackupSnapshotRequest(id: id))
        return r.removedBlobs ?? 0
    }

    /// `PUT /v1/backup/blob/{sha256}`: gövde diskten akıtılır. Sunucu SHA-256'yı doğrular; yanıt `{ ok, bytes }`.
    /// `allowsExpensive == false` (otomatik yedek): hücresel veride ve Düşük Veri Modu'nda yüklenmez.
    @concurrent
    nonisolated func backupUpload(file: URL, sha256: String, allowsExpensive: Bool = true) async throws {
        guard BackupBlobID.isValid(sha256) else { throw APIError(status: 0, code: "bad_hash", message: "Geçersiz dosya özeti.") }
        var request = try backupRequest(path: "/v1/backup/blob/\(sha256)", allowsExpensive: allowsExpensive)
        request.httpMethod = "PUT"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 600
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.upload(for: request, fromFile: file)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw APIError.network(error)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw APIError(status: status, code: status == 413 ? "too_large" : "http_\(status)",
                           message: status == 413 ? "Dosya yedek sınırını aşıyor." : "Yedek yüklenemedi (\(status)). \(String(decoding: data.prefix(300), as: UTF8.self))")
        }
    }

    /// Otomatik yedekten önce ağ yoklaması: kısıtlı istek hücresel veride ve Düşük Veri Modu'nda hiç gönderilmez, bağlantı hatası verir.
    /// Sunucunun yanıt kodu önemsizdir (bilinmeyen özet 404 döner); yalnız isteğin bu ağdan çıkabildiği sınanır.
    @concurrent
    nonisolated func backupProbeUnmetered() async throws {
        var request = try backupRequest(path: "/v1/backup/blob/\(String(repeating: "0", count: 64))", allowsExpensive: false)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 20
        do {
            _ = try await URLSession.shared.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw APIError.network(error)
        }
    }

    /// `GET /v1/backup/blob/{sha256}`: dosyayı diske indirir, özetini doğrular ve `destination`'a taşır.
    /// Özet uyuşmazsa geçici dosya silinir, `destination`'a dokunulmaz ve `hash_mismatch` fırlatılır.
    @concurrent
    nonisolated func backupDownload(sha256: String, to destination: URL) async throws {
        guard BackupBlobID.isValid(sha256) else { throw APIError(status: 0, code: "bad_hash", message: "Geçersiz dosya özeti.") }
        let request = try backupRequest(path: "/v1/backup/blob/\(sha256)")
        let temp: URL
        let response: URLResponse
        do {
            (temp, response) = try await URLSession.shared.download(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw APIError.network(error)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            try? FileManager.default.removeItem(at: temp)
            throw APIError(status: status, code: status == 404 ? "not_found" : "http_\(status)", message: "Yedek dosyası indirilemedi (\(status)).")
        }
        guard (try? BackupBlobID.sha256(of: temp)) == sha256 else {
            try? FileManager.default.removeItem(at: temp)
            throw APIError(status: 0, code: APIError.backupHashMismatchCode, message: "Yedek dosyası bozuk indi.")
        }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temp, to: destination)
    }

    nonisolated private func backupRequest(path: String, allowsExpensive: Bool = true) throws -> URLRequest {
        guard let token = PersonalToken.current, !token.isEmpty else {
            throw APIError(status: 401, code: "unauthorized", message: "Sunucu erişim anahtarı girilmemiş. Ayarlar → Sunucu bölümünden ekle.")
        }
        var request = URLRequest(url: Config.apiBaseURL.appending(path: path))
        request.setValue(token, forHTTPHeaderField: "x-personal-token")
        request.setValue(InstallID.current.uuidString.lowercased(), forHTTPHeaderField: "X-Install-Id")
        BackupAPI.configure(&request, allowsExpensive: allowsExpensive)
        return request
    }
}
