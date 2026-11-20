import Foundation
import AVFoundation
import SwiftUI

struct OfficialMealTrack: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let voice: String
    let provider: String
    let url: String
    let sourceURL: String
}

/// A disk-backed queue. iOS owns the background transfers, not a view's lifetime.
@MainActor
final class OfficialMealStore: NSObject, ObservableObject {
    static let shared = OfficialMealStore()
    nonisolated static let sessionID = "com.mehmetderin.ezanvaktipro.official-meals"
    @Published private(set) var tracks: [OfficialMealTrack] = []
    @Published private(set) var downloaded: Set<String> = []
    @Published private(set) var pending: [String] = []
    @Published private(set) var active: Set<String> = []
    @Published private(set) var failures: [String: String] = [:]
    @Published private(set) var status = "Dinlemek veya çevrimdışı indirmek için bir kayıt seçin."
    @Published var paused = false
    @Published private(set) var externalTransferActive = false
    var backgroundCompletion: (() -> Void)?
    private var ready = false
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionID)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.allowsCellularAccess = true
        config.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    nonisolated static var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("OfficialMealAudio", isDirectory: true)
    }
    override init() {
        super.init()
        if let url = Bundle.main.url(forResource: "official_meal_audio", withExtension: "json"),
           let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode([OfficialMealTrack].self, from: data) { tracks = decoded }
        try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        downloaded = Set(((try? FileManager.default.contentsOfDirectory(atPath: Self.directory.path)) ?? []).filter { $0.hasSuffix(".mp3") }.map { String($0.dropLast(4)) })
        let valid = Set(tracks.map(\.id))
        pending = (UserDefaults.standard.stringArray(forKey: "meal.download.queue") ?? []).filter { valid.contains($0) && !downloaded.contains($0) }
        paused = UserDefaults.standard.bool(forKey: "meal.download.paused")
        session.getAllTasks { tasks in
            Task { @MainActor in
                self.active = Set(tasks.compactMap(\.taskDescription))
                await self.refreshTransferredFiles()
                self.ready = true
                self.pump()
            }
        }
    }
    private struct TransferManifest: Decodable, Sendable {
        let active: Bool
        let updated: Double
        let files: [String: Int64]
        let failedIDs: [String]
    }

    func refreshTransferredFiles() async {
        let directory = Self.directory
        let valid = Set(tracks.map(\.id))
        let result = await Task.detached(priority: .utility) { () -> (TransferManifest, Set<String>)? in
            guard let data = try? Data(contentsOf: directory.appendingPathComponent("transfer-manifest.json")),
                  let manifest = try? JSONDecoder().decode(TransferManifest.self, from: data) else { return nil }
            var verified: Set<String> = []
            for (name, expected) in manifest.files where name.hasSuffix(".mp3") {
                let id = String(name.dropLast(4))
                guard valid.contains(id), expected > 1024 else { continue }
                let attrs = try? FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent(name).path)
                if (attrs?[.size] as? NSNumber)?.int64Value == expected { verified.insert(id) }
            }
            return (manifest, verified)
        }.value
        guard let (manifest, verified) = result else { return }
        let wasExternal = externalTransferActive
        externalTransferActive = manifest.active && Date().timeIntervalSince1970 - manifest.updated < 180
        let own = Set(UserDefaults.standard.stringArray(forKey: "meal.download.validated") ?? [])
        downloaded = verified.union(own.filter { valid.contains($0) && FileManager.default.fileExists(atPath: directory.appendingPathComponent($0 + ".mp3").path) })
        for id in manifest.failedIDs where valid.contains(id) && !downloaded.contains(id) {
            failures[id] = "Yayıncıdaki ses dosyasına erişilemiyor."
        }
        var seen: Set<String> = []
        pending = (pending + (UserDefaults.standard.stringArray(forKey: "meal.download.queue") ?? [])).filter {
            valid.contains($0) && !downloaded.contains($0) && !manifest.failedIDs.contains($0) && seen.insert($0).inserted
        }
        if externalTransferActive && !wasExternal {
            session.getAllTasks { tasks in tasks.forEach { $0.cancel() } }
        }
        persist()
        pump()
    }

    func localURL(_ track: OfficialMealTrack) -> URL { Self.directory.appendingPathComponent(track.id + ".mp3") }
    func play(_ track: OfficialMealTrack) {
        guard let url = downloaded.contains(track.id) ? localURL(track) : URL(string: track.url) else { return }
        AdhanPlayer.shared.playLocalOrRemoteFile(url: url, title: track.title, subtitle: "\(track.provider) · \(track.voice)")
    }
    func enqueue(_ selected: [OfficialMealTrack]) {
        let existing = Set(pending).union(active).union(downloaded)
        pending.append(contentsOf: selected.map(\.id).filter { !existing.contains($0) })
        for track in selected { failures.removeValue(forKey: track.id) }
        paused = false
        persist()
        pump()
    }
    func setPaused(_ value: Bool) {
        // Already running transfers finish safely; new transfers wait.
        paused = value
        persist()
        pump()
    }
    private func persist() {
        UserDefaults.standard.set(pending, forKey: "meal.download.queue")
        UserDefaults.standard.set(paused, forKey: "meal.download.paused")
    }
    private func pump() {
        guard ready else { return }
        if externalTransferActive {
            status = "\(downloaded.count) kayıt hazır · arşiv yükleniyor"
            writeStatus()
            return
        }
        if paused { status = "İndirme duraklatıldı."; writeStatus(); return }
        let capacity = (try? Self.directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage ?? Int64.max
        guard capacity > 512 * 1024 * 1024 else {
            paused = true; persist(); status = "Depolama azaldığı için indirme duraklatıldı."; return
        }
        for id in pending where active.count < 2 && !active.contains(id) && !downloaded.contains(id) {
            guard let track = tracks.first(where: { $0.id == id }), let url = URL(string: track.url) else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 90
            request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            request.setValue(track.sourceURL, forHTTPHeaderField: "Referer")
            let task = session.downloadTask(with: request)
            task.taskDescription = id
            active.insert(id)
            task.resume()
        }
        status = pending.isEmpty ? "\(downloaded.count) kayıt çevrimdışı hazır." : "\(downloaded.count) hazır · \(pending.count) sırada. Kayıtlar indiriliyor."
        writeStatus()
    }
    private func writeStatus() {
        // Read-only device diagnostics; the UI uses published state directly.
        let values: [String: Any] = ["downloaded": downloaded.count, "pending": pending.count, "active": active.count, "failed": failures.count, "paused": paused, "status": status]
        if let data = try? JSONSerialization.data(withJSONObject: values) {
            try? data.write(to: Self.directory.appendingPathComponent("status.json"), options: .atomic)
        }
    }
    private func complete(_ id: String, error: String?) {
        active.remove(id)
        pending.removeAll { $0 == id }
        if let error { failures[id] = error } else { downloaded.insert(id) }
        if error == nil {
            var own = Set(UserDefaults.standard.stringArray(forKey: "meal.download.validated") ?? [])
            own.insert(id)
            UserDefaults.standard.set(Array(own), forKey: "meal.download.validated")
        }
        persist(); pump()
    }
}

extension OfficialMealStore: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.taskDescription,
              id.range(of: "^[a-zA-Z0-9-]+$", options: .regularExpression) != nil else { return }
        let destination = Self.directory.appendingPathComponent(id + ".mp3")
        do {
            guard let response = downloadTask.response as? HTTPURLResponse, (200...299).contains(response.statusCode),
                  !((response.mimeType ?? "").contains("text")),
                  ((try? location.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 1024 else { throw URLError(.badServerResponse) }
            try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.moveItem(at: location, to: destination) }
            Task { @MainActor in
                do {
                    let playable = try await AVURLAsset(url: destination).load(.isPlayable)
                    guard playable else { throw URLError(.cannotDecodeContentData) }
                    self.complete(id, error: nil)
                } catch {
                    try? FileManager.default.removeItem(at: destination)
                    self.complete(id, error: "Ses dosyası doğrulanamadı; tekrar deneyin.")
                }
            }
        } catch {
            Task { @MainActor in self.complete(id, error: error.localizedDescription) }
        }
    }
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let id = task.taskDescription else { return }
        Task { @MainActor in
            if (error as NSError).code == NSURLErrorCancelled && self.externalTransferActive {
                self.active.remove(id)
                self.persist(); self.pump()
            } else { self.complete(id, error: error.localizedDescription) }
        }
    }
    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            self.backgroundCompletion?()
            self.backgroundCompletion = nil
        }
    }
}
