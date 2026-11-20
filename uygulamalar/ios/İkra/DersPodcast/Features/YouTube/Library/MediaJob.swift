import Foundation
import Observation

/// Sunucu medya işi (`/v1/media/*`): başlat → hazırlanmasını bekle → dosyayı diske indir (`GET /v1/files/{id}`).
/// Çevrimdışı video (#14) ve altyazılı video (#36) ortak kullanır; indirme belleğe alınmaz, ilerleme gösterilir.
@MainActor @Observable
final class MediaJobRunner {
    enum Phase: Equatable {
        case idle
        /// Sunucu hazırlıyor (video indiriyor / altyazı gömüyor).
        case server
        /// Dosya telefona iniyor.
        case download
        case done
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    /// Geçerli aşamanın ilerlemesi (0...1).
    private(set) var progress = 0.0
    /// Sunucunun adım iletisi (ör. uyarılar dahil).
    private(set) var message = ""
    private(set) var receivedBytes: Int64 = 0
    private(set) var totalBytes: Int64 = 0
    /// Sunucunun işin sonunda bildirdiği uyarılar.
    private(set) var warnings: [String] = []

    /// Sunucuda hazırlanmış ama telefona inmesi yarıda kalmış dosya (sunucu 24 saat saklar).
    private struct ReadyFile {
        var key: Data
        var fileId: String
        var bytes: Int64
        var warnings: [String]
    }

    private var task: Task<Void, Never>?
    private var jobId: String?
    @ObservationIgnored private var ready: ReadyFile?

    var isRunning: Bool { phase == .server || phase == .download }

    /// İsteğin kimliği: aynı ayarlarla yinelenen istek aynı anahtarı verir.
    nonisolated static func requestKey(_ request: MediaStartRequest) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(request)) ?? Data()
    }

    /// Hazır dosya yeni istekle aynı ayarlara aitse kimliğini verir (sunucuda baştan hazırlatmamak için).
    nonisolated static func reusableFile(readyKey: Data?, fileId: String?, requestKey: Data) -> String? {
        guard let readyKey, let fileId, !fileId.isEmpty, !requestKey.isEmpty, readyKey == requestKey else { return nil }
        return fileId
    }

    /// İşi başlatır; dosya `destination`'a inince `onFinish` çağrılır.
    /// Önceki deneme indirme aşamasında koptuysa ve istek aynıysa sunucudaki hazır dosya yeniden indirilir.
    func begin(_ request: MediaStartRequest, destination: URL, onFinish: @escaping @MainActor (URL) -> Void) {
        guard !isRunning else { return }
        let key = Self.requestKey(request)
        let reuse = Self.reusableFile(readyKey: ready?.key, fileId: ready?.fileId, requestKey: key)
        if reuse == nil { ready = nil }
        phase = reuse == nil ? .server : .download
        progress = 0
        message = reuse == nil ? "Sıraya alınıyor" : "Hazır dosya indiriliyor"
        receivedBytes = 0
        totalBytes = ready?.bytes ?? 0
        warnings = ready?.warnings ?? []
        jobId = nil
        task = Task {
            do {
                if let reuse {
                    do {
                        try await download(fileId: reuse, to: destination)
                    } catch let error as APIError where error.status == 404 {
                        // Sunucu dosyayı silmiş: aynı çağrıda bir kez baştan hazırlat.
                        ready = nil
                        try Task.checkCancellation()
                        try await prepareAndDownload(request, key: key, to: destination)
                    }
                } else {
                    try await prepareAndDownload(request, key: key, to: destination)
                }
                ready = nil
                phase = .done
                progress = 1
                onFinish(destination)
            } catch is CancellationError {
                phase = .idle
                message = "İptal edildi."
                // Dosya hazırsa sunucuda kalsın: yeniden denemede baştan hazırlanmaz.
                if ready == nil, let id = jobId { Task { await APIClient.shared.mediaCancel(jobId: id) } }
            } catch {
                phase = .failed(error.localizedDescription)
            }
            task = nil
        }
    }

    /// Durdurur; sunucudaki iş de (dosya henüz hazır değilse) iptal edilir.
    func cancel() {
        task?.cancel()
    }

    func reset() {
        guard !isRunning else { return }
        phase = .idle
        progress = 0
        message = ""
        ready = nil
    }

    private func prepareAndDownload(_ request: MediaStartRequest, key: Data, to destination: URL) async throws {
        phase = .server
        progress = 0
        message = "Sıraya alınıyor"
        receivedBytes = 0
        totalBytes = 0
        warnings = []
        // Başlatma isteği iptalden yalıtılır: istek ulaştıysa iş sunucuda başlar, kimliği kaybetmeyelim.
        let id = try await Task { try await APIClient.shared.mediaStart(request) }.value
        jobId = id
        try Task.checkCancellation()
        let finished = try await waitForServer(id)
        guard let fileId = finished.fileId, !fileId.isEmpty else {
            throw APIError(status: 0, code: "no_file", message: "Sunucu dosyayı hazırlayamadı.")
        }
        ready = ReadyFile(key: key, fileId: fileId, bytes: finished.bytes ?? 0, warnings: finished.warnings)
        totalBytes = finished.bytes ?? 0
        warnings = finished.warnings
        phase = .download
        progress = 0
        try await download(fileId: fileId, to: destination)
    }

    private func waitForServer(_ id: String) async throws -> MediaStatus {
        var networkFailures = 0
        while true {
            try await Task.sleep(for: .seconds(1.5))
            let status: MediaStatus
            do {
                status = try await APIClient.shared.mediaStatus(jobId: id)
                networkFailures = 0
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as APIError where error.status == 404 {
                throw APIError(status: 404, code: "not_found", message: "İş sunucuda bulunamadı (sunucu yeniden başlamış olabilir). Yeniden dene.")
            } catch let error as APIError where error.status == 401 || error.status == 400 || error.status == 429 {
                throw error
            } catch {
                networkFailures += 1
                if networkFailures >= 8 { throw error }
                message = "Bağlantı bekleniyor…"
                try await Task.sleep(for: .seconds(2))
                continue
            }
            progress = status.progress
            if !status.message.isEmpty { message = status.message }
            switch status.state {
            case .queued, .running: continue
            case .done: return status
            case .error: throw APIError(status: 0, code: "job", message: status.error ?? "Sunucu işi tamamlayamadı.")
            case .canceled: throw APIError(status: 0, code: "cancelled", message: "İş sunucuda iptal edildi.")
            }
        }
    }

    private func download(fileId: String, to destination: URL) async throws {
        let monitor = TransferMonitor()
        // Bayt ilerlemesini yokla (görev vekili kilitle okunur).
        let poll = Task {
            while !Task.isCancelled {
                progress = monitor.downloadFraction
                receivedBytes = monitor.receivedBytes
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
        defer { poll.cancel() }
        try await APIClient.shared.downloadFile(id: fileId, to: destination, monitor: monitor)
        receivedBytes = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int64) ?? receivedBytes
    }
}

nonisolated enum ByteFormat {
    static func string(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
