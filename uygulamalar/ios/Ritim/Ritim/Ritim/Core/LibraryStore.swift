import Foundation
import CryptoKit
import AVFoundation
import Combine
import UIKit

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var tracks: [MediaTrack] = []
    @Published private(set) var playlists: [MediaPlaylist] = []
    @Published var errorMessage: String?
    @Published private(set) var isScanningMetadata = false
    @Published private(set) var metadataScanProgress = 0.0
    @Published private(set) var metadataScanMessage: String?
    let directory: URL
    let artworkDirectory: URL
    private let metadataStore: MediaMetadataStore
    private let metadataScanningAllowed: @MainActor () -> Bool
    private var metadataScanTask: Task<Void, Never>?
    private var metadataBackgroundObserver: NSObjectProtocol?
    private let stateURL: URL
    private struct State: Codable { var version: Int? = 1; var tracks: [MediaTrack]; var playlists: [MediaPlaylist]; var seeded: Bool }
    private var seeded = false
    private var canWrite = true

    init(directory: URL? = nil, seed: Bool = true,
         metadataScanningAllowed: @escaping @MainActor () -> Bool = { UIApplication.shared.applicationState == .active }) {
        self.directory = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Media", isDirectory: true)
        artworkDirectory = self.directory.deletingLastPathComponent().appendingPathComponent("Artwork", isDirectory: true)
        metadataStore = MediaMetadataStore(directory: artworkDirectory)
        self.metadataScanningAllowed = metadataScanningAllowed
        stateURL = self.directory.deletingLastPathComponent().appendingPathComponent("library.json")
        do {
            try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: stateURL.path) {
                let state = try JSONDecoder().decode(State.self, from: Data(contentsOf: stateURL))
                tracks = state.tracks; playlists = state.playlists; seeded = state.seeded
            }
            if seed && !seeded { seedOriginals() }
        } catch {
            // Preserve damaged state for recovery instead of silently replacing the library.
            canWrite = false
            errorMessage = "Kütüphane okunamadı: \(error.localizedDescription)"
        }
        metadataBackgroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.cancelMetadataScan() }
        }
    }

    deinit {
        metadataScanTask?.cancel()
        if let metadataBackgroundObserver { NotificationCenter.default.removeObserver(metadataBackgroundObserver) }
    }

    func url(for track: MediaTrack) -> URL { directory.appendingPathComponent(track.fileName) }
    var storageBytes: Int64 { tracks.reduce(0) { $0 + $1.fileSize } }

    func artworkURL(for track: MediaTrack) -> URL? {
        let live = tracks.first(where: { $0.id == track.id }) ?? track
        return MediaMetadataStore.artworkURL(named: live.artworkFileName, directory: artworkDirectory)
    }

    /// Explicit, foreground-only migration. Never runs at launch or from playback.
    func scanEmbeddedMetadata() async {
        guard !isScanningMetadata, canWrite, metadataScanningAllowed() else { return }
        isScanningMetadata = true
        metadataScanProgress = 0
        metadataScanMessage = "Parça bilgileri okunuyor…"
        let pendingIDs = tracks.map(\.id)
        let operation = Task { @MainActor [weak self] in
            guard let self else { return }
            var changed = 0, unreadable = 0
            defer { self.isScanningMetadata = false; self.metadataScanTask = nil }
            do {
                for (offset, id) in pendingIDs.enumerated() {
                    try Task.checkCancellation()
                    guard self.metadataScanningAllowed() else { throw CancellationError() }
                    if let track = self.tracks.first(where: { $0.id == id }) {
                        let metadata: EmbeddedMediaMetadata
                        do { metadata = try await self.metadataStore.read(url: self.url(for: track), trackID: id) }
                        catch is CancellationError { throw CancellationError() }
                        catch { unreadable += 1; self.metadataScanProgress = Double(offset + 1) / Double(pendingIDs.count); continue }
                        do {
                            try Task.checkCancellation()
                            guard self.metadataScanningAllowed() else { throw CancellationError() }
                            // Resolve the live row AFTER awaiting. User edits and deletions win.
                            if let index = self.tracks.firstIndex(where: { $0.id == id }) {
                                let previous = self.tracks[index]
                                if let number = metadata.trackNumber { self.tracks[index].trackNumber = number }
                                if let number = metadata.discNumber { self.tracks[index].discNumber = number }
                                if let album = metadata.album { self.tracks[index].album = album }
                                if let artwork = metadata.artworkFileName { self.tracks[index].artworkFileName = artwork }
                                if self.tracks[index] != previous {
                                    do { try self.persist() } catch { self.tracks[index] = previous; throw error }
                                    changed += 1
                                }
                                if metadata.artworkFileName != nil { await self.metadataStore.removeArtwork(named: previous.artworkFileName) }
                            } else { await self.metadataStore.removeArtwork(named: metadata.artworkFileName) }
                        } catch {
                            await self.metadataStore.removeArtwork(named: metadata.artworkFileName)
                            throw error
                        }
                    }
                    self.metadataScanProgress = Double(offset + 1) / Double(pendingIDs.count)
                }
                self.metadataScanProgress = 1
                self.metadataScanMessage = "\(changed) parçanın bilgileri güncellendi." + (unreadable > 0 ? " \(unreadable) dosya okunamadı." : "")
            } catch is CancellationError {
                self.metadataScanMessage = "Tarama durduruldu. Kaydedilen bilgiler korundu."
            } catch { self.metadataScanMessage = "Tarama tamamlanamadı: \(error.localizedDescription)" }
        }
        metadataScanTask = operation
        await withTaskCancellationHandler { await operation.value } onCancel: { operation.cancel() }
    }

    func cancelMetadataScan() { metadataScanTask?.cancel() }

    func importFiles(_ urls: [URL]) async {
        var failures: [String] = []
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            do { _ = try await importDownloadedFile(url, title: nil, artist: nil, sourceURL: nil) }
            catch { failures.append("\(url.lastPathComponent): \(error.localizedDescription)") }
            if access { url.stopAccessingSecurityScopedResource() }
        }
        if !failures.isEmpty { errorMessage = failures.joined(separator: "\n") }
    }

    @discardableResult
    func importDownloadedFile(_ source: URL, title: String?, artist: String?, sourceURL: String?, downloadQuality: DownloadQuality? = nil,
                              downloadEntryID: UUID? = nil, playlistIDs: [UUID] = []) async throws -> MediaTrack {
        let ext = source.pathExtension.lowercased()
        guard MediaURLPolicy.extensions.contains(ext) else { throw RitimError.message("Bu medya biçimi desteklenmiyor.") }
        let size = (try source.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
        guard size > 0 && size <= 1_073_741_824 else { throw RitimError.message("Dosya boş veya 1 GB sınırından büyük.") }
        let id = UUID()
        let destination = directory.appendingPathComponent("\(id.uuidString).\(ext)")
        // Large completed downloads must not block playback controls and track
        // transitions on the main actor while they are copied into the library.
        let copy = Task.detached(priority: .utility) {
            try FileManager.default.copyItem(at: source, to: destination)
        }
        do {
            try await copy.value
            try Task.checkCancellation()
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        var importedArtwork: String?
        do {
            let asset = AVURLAsset(url: destination)
            guard try await asset.load(.isPlayable) else { throw RitimError.message("Bu dosya iPhone'da oynatılamıyor. MP3 veya H.264/AAC MP4 kullan.") }
            let duration = try await asset.load(.duration).seconds
            guard duration.isFinite, duration > 0 else { throw RitimError.message("Dosya geçerli bir ses veya video içermiyor.") }
            let video = try await !asset.loadTracks(withMediaType: .video).isEmpty
            let metadata = (try? await metadataStore.read(url: destination, trackID: id, includeArtwork: metadataScanningAllowed())) ?? EmbeddedMediaMetadata()
            importedArtwork = metadata.artworkFileName
            let track = MediaTrack(id: id, title: nonempty(title) ?? nonempty(metadata.title) ?? source.deletingPathExtension().lastPathComponent,
                                   artist: nonempty(artist) ?? nonempty(metadata.artist) ?? "Bilinmeyen sanatçı",
                                   kind: video ? .video : .audio, fileName: destination.lastPathComponent,
                                   duration: duration, sourceURL: sourceURL, fileSize: Int64(size),
                                   downloadQuality: sourceURL.flatMap(URL.init(string:)).map(MediaURLPolicy.isYouTube) == true ? downloadQuality : nil,
                                   downloadEntryID: downloadEntryID, album: metadata.album, artworkFileName: metadata.artworkFileName, discNumber: metadata.discNumber, trackNumber: metadata.trackNumber)
            let previousPlaylists = playlists
            // Native work is cancelled as soon as the app enters background.
            // Metadata loading above can suspend: do not consume a playlist's
            // reserved slot after that job has already returned to the queue.
            try Task.checkCancellation()
            tracks.insert(track, at: 0)
            if let downloadEntryID { resolveDownloadSlots(track: track, entryID: downloadEntryID, playlistIDs: playlistIDs) }
            do { try persist() } catch { tracks.removeAll { $0.id == id }; playlists = previousPlaylists; throw error }
            return track
        } catch {
            try? FileManager.default.removeItem(at: destination)
            await metadataStore.removeArtwork(named: importedArtwork)
            throw error
        }
    }

    /// Only a previously validated import with exact provenance can complete an
    /// interrupted queue row. Unrelated same-URL imports are never adopted.
    func recoveredDownload(for entry: DownloadEntry) async -> MediaTrack? {
        guard let source = try? MediaURLPolicy.canonicalInput(entry.sourceURL) else { return nil }
        for track in tracks where track.downloadEntryID == entry.id {
            guard let savedSource = track.sourceURL.flatMap({ try? MediaURLPolicy.canonicalInput($0) }), savedSource == source,
                  !MediaURLPolicy.isYouTube(source) ||
                    ((track.downloadQuality ?? .standard) == entry.effectiveQuality && URL(fileURLWithPath: track.fileName).pathExtension.lowercased() == entry.format.rawValue),
                  track.fileSize > 0 else { continue }
            let file = url(for: track)
            guard file.deletingLastPathComponent().standardizedFileURL.path == directory.standardizedFileURL.path,
                  MediaURLPolicy.extensions.contains(file.pathExtension.lowercased()) else { continue }
            guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true,
                  Int64(values.fileSize ?? 0) == track.fileSize else { continue }
            let asset = AVURLAsset(url: file)
            guard (try? await asset.load(.isPlayable)) == true,
                  let duration = try? await asset.load(.duration).seconds, duration.isFinite, duration > 0,
                  tracks.contains(where: { $0.id == track.id }) else { continue }
            return track
        }
        return nil
    }

    func reserveDownloadOrder(_ slots: [PlaylistDownloadSlot], in playlistID: UUID) throws {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        let previous = playlists
        var order = playlists[index].downloadOrder ?? playlists[index].trackIDs.map { PlaylistDownloadSlot(trackID: $0) }
        for slot in slots {
            if let trackID = slot.trackID, order.contains(where: { $0.trackID == trackID }) { continue }
            if let entryID = slot.entryID, order.contains(where: { $0.entryID == entryID }) { continue }
            order.append(slot)
        }
        playlists[index].downloadOrder = order
        materializeDownloadOrder(at: index)
        do { try persist() } catch { playlists = previous; throw error }
    }

    func completeRecoveredDownload(_ track: MediaTrack, entry: DownloadEntry) throws {
        guard tracks.contains(where: { $0.id == track.id && $0.downloadEntryID == entry.id }) else {
            throw RitimError.message("Kurtarılan indirme artık kütüphanede yok.")
        }
        let previous = playlists
        resolveDownloadSlots(track: track, entryID: entry.id,
                             playlistIDs: [entry.playlistID].compactMap { $0 } + (entry.additionalPlaylistIDs ?? []))
        do { try persist() } catch { playlists = previous; throw error }
    }

    func pruneDownloadReservations(retained: [UUID: Set<UUID>]) throws {
        let previous = playlists
        for index in playlists.indices {
            guard var order = playlists[index].downloadOrder else { continue }
            let playlistID = playlists[index].id
            order.removeAll { slot in
                guard slot.trackID == nil, let entryID = slot.entryID else { return false }
                return retained[entryID]?.contains(playlistID) != true
            }
            playlists[index].downloadOrder = order
            materializeDownloadOrder(at: index)
        }
        guard playlists != previous else { return }
        do { try persist() } catch { playlists = previous; throw error }
    }

    private func resolveDownloadSlots(track: MediaTrack, entryID: UUID, playlistIDs: [UUID]) {
        for index in playlists.indices {
            if var order = playlists[index].downloadOrder {
                let hasSlot = order.contains { $0.entryID == entryID }
                for slot in order.indices where order[slot].entryID == entryID {
                    order[slot] = PlaylistDownloadSlot(trackID: track.id)
                }
                if !hasSlot, playlistIDs.contains(playlists[index].id), !order.contains(where: { $0.trackID == track.id }) {
                    order.append(PlaylistDownloadSlot(trackID: track.id))
                }
                playlists[index].downloadOrder = order
                materializeDownloadOrder(at: index)
            } else if playlistIDs.contains(playlists[index].id), !playlists[index].trackIDs.contains(track.id) {
                playlists[index].trackIDs.append(track.id)
            }
        }
    }

    private func materializeDownloadOrder(at index: Int) {
        guard let order = playlists[index].downloadOrder else { return }
        let available = Set(tracks.map(\.id))
        var seen: Set<UUID> = []
        playlists[index].trackIDs = order.compactMap(\.trackID).filter { available.contains($0) && seen.insert($0).inserted }
        if order.allSatisfy({ $0.trackID != nil }) { playlists[index].downloadOrder = nil }
    }

    private func synchronizeManualPlaylistChanges() {
        for index in playlists.indices {
            guard var order = playlists[index].downloadOrder else { continue }
            let ids = Set(playlists[index].trackIDs)
            order.removeAll { $0.trackID.map { !ids.contains($0) } ?? false }
            let orderedIDs = Set(order.compactMap(\.trackID))
            order.append(contentsOf: playlists[index].trackIDs.filter { !orderedIDs.contains($0) }.map { PlaylistDownloadSlot(trackID: $0) })
            playlists[index].downloadOrder = order.allSatisfy { $0.trackID != nil } ? nil : order
        }
    }

    func setFavorites(_ ids: Set<UUID>, value: Bool) {
        mutate { for i in tracks.indices where ids.contains(tracks[i].id) { tracks[i].isFavorite = value } }
    }
    func updateMetadata(_ ids: Set<UUID>, artist: String, album: String) {
        let artist = nonempty(artist), album = nonempty(album)
        mutate {
            for i in tracks.indices where ids.contains(tracks[i].id) {
                if let artist { tracks[i].artist = String(artist.prefix(200)) }
                if let album { tracks[i].album = String(album.prefix(200)) }
            }
        }
    }
    func updatePlaylist(_ id: UUID, name: String, detail: String) {
        guard let name = nonempty(name) else { return }
        mutate {
            if let i = playlists.firstIndex(where: { $0.id == id }) {
                playlists[i].name = String(name.prefix(80)); playlists[i].detail = String(detail.prefix(1000))
            }
        }
    }
    func setPlaylistCover(_ playlist: MediaPlaylist, trackID: UUID?) {
        guard trackID == nil || tracks(in: playlist).contains(where: { $0.id == trackID }) else { return }
        mutate { if let i = playlists.firstIndex(where: { $0.id == playlist.id }) { playlists[i].coverTrackID = trackID } }
    }
    func togglePinned(_ playlist: MediaPlaylist) {
        mutate { if let i = playlists.firstIndex(where: { $0.id == playlist.id }) { playlists[i].isPinned = !(playlists[i].isPinned ?? false) } }
    }
    func exportBackup(includeMedia: Bool) async throws -> URL {
        try await LibraryArchive.shared.export(root: directory.deletingLastPathComponent(), tracks: tracks,
                                              playlists: playlists, includeMedia: includeMedia)
    }

    func restoreBackup(_ archive: URL) async throws -> Int {
        guard canWrite else { throw RitimError.message("Önce mevcut kitaplığın okunma hatasını gider.") }
        let (manifest, staging) = try await LibraryArchive.shared.unpack(archive)
        defer { try? FileManager.default.removeItem(at: staging) }
        // Validate playable assets before changing either the live files or journal.
        if manifest.includesMedia {
            for track in manifest.tracks {
                try Task.checkCancellation()
                let asset = AVURLAsset(url: staging.appendingPathComponent("Media/" + track.fileName))
                guard try await asset.load(.isPlayable) else { throw RitimError.message("Yedekte oynatılamayan medya var.") }
            }
        }
        let matched = try await LibraryArchive.shared.matchingTracks(manifest: manifest, staging: staging, tracks: tracks, root: directory.deletingLastPathComponent())
        let previousTracks = tracks, previousPlaylists = playlists
        var addedFiles: [URL] = []
        var mapping: [UUID: UUID] = [:]
        var additions: [MediaTrack] = []
        do {
            for source in manifest.tracks {
                if let matchedID = matched[source.id], let current = tracks.first(where: { $0.id == matchedID }),
                   FileManager.default.fileExists(atPath: url(for: current).path) {
                    mapping[source.id] = current.id
                    continue
                }
                guard manifest.includesMedia else { continue }
                var restored = source
                restored.id = tracks.contains(where: { $0.id == source.id }) ? UUID() : source.id
                restored.downloadEntryID = nil
                restored.fileName = UUID().uuidString + "." + (source.fileName as NSString).pathExtension
                restored.artworkFileName = nil
                let target = url(for: restored)
                try FileManager.default.moveItem(at: staging.appendingPathComponent("Media/" + source.fileName), to: target)
                addedFiles.append(target)
                restored.fileSize = Int64((try target.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0)
                if let artwork = source.artworkFileName {
                    let old = staging.appendingPathComponent("Artwork/" + artwork)
                    if FileManager.default.fileExists(atPath: old.path) {
                        try FileManager.default.createDirectory(at: artworkDirectory, withIntermediateDirectories: true)
                        let name = restored.id.uuidString + ".jpg"
                        let destination = artworkDirectory.appendingPathComponent(name)
                        try FileManager.default.copyItem(at: old, to: destination)
                        addedFiles.append(destination); restored.artworkFileName = name
                    }
                }
                let oldLyrics = staging.appendingPathComponent("Lyrics/" + source.id.uuidString + ".json")
                if let data = try? Data(contentsOf: oldLyrics), var lyrics = try? JSONDecoder().decode(TrackLyrics.self, from: data) {
                    lyrics.trackID = restored.id
                    let folder = directory.deletingLastPathComponent().appendingPathComponent("Lyrics")
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    let destination = folder.appendingPathComponent(restored.id.uuidString + ".json")
                    try JSONEncoder().encode(lyrics).write(to: destination, options: .atomic)
                    addedFiles.append(destination)
                }
                mapping[source.id] = restored.id; additions.append(restored)
            }
            tracks.append(contentsOf: additions)
            for source in manifest.playlists {
                // Existing lists and pending download reservations always win.
                guard !playlists.contains(where: { $0.id == source.id }) else { continue }
                var restored = source
                restored.trackIDs = source.trackIDs.compactMap { mapping[$0] }
                restored.downloadOrder = nil
                restored.coverTrackID = source.coverTrackID.flatMap { mapping[$0] }
                guard !restored.trackIDs.isEmpty else { continue }
                playlists.append(restored)
            }
            try persist()
            return additions.count
        } catch {
            tracks = previousTracks; playlists = previousPlaylists
            addedFiles.forEach { try? FileManager.default.removeItem(at: $0) }
            throw error
        }
    }

    func inspectStorage() async -> String {
        let snapshot = tracks, folder = directory
        return await Task.detached(priority: .utility) {
            let missing = snapshot.filter { !FileManager.default.fileExists(atPath: folder.appendingPathComponent($0.fileName).path) }
            let duplicates = Dictionary(grouping: snapshot, by: { LibrarySearch.key($0.title + " " + $0.artist) }).values.filter { $0.count > 1 }.count
            let root = folder.deletingLastPathComponent()
            let categories = [("Medya", "Media"), ("Kapaklar", "Artwork"), ("Şarkı sözleri", "Lyrics"), ("İndirme ara dosyaları", "NativeDownloads")]
            let sizes = categories.map { title, name -> String in
                var bytes: Int64 = 0
                if let files = FileManager.default.enumerator(at: root.appendingPathComponent(name), includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]) {
                    for case let file as URL in files {
                        if let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]), values.isRegularFile == true, values.isSymbolicLink != true {
                            bytes += Int64(values.fileSize ?? 0)
                        }
                    }
                }
                return title + ": " + ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
            }.joined(separator: "\n")
            return "\(missing.count) eksik dosya • \(duplicates) olası yinelenen grup. Hiçbir dosya silinmedi.\n" + sizes
        }.value
    }

    func toggleFavorite(_ track: MediaTrack) { mutate { if let i = tracks.firstIndex(where: { $0.id == track.id }) { tracks[i].isFavorite.toggle() } } }
    func recordPlay(_ track: MediaTrack) { mutate { if let i = tracks.firstIndex(where: { $0.id == track.id }) { tracks[i].playCount += 1; tracks[i].lastPlayedAt = Date() } } }
    func rename(_ track: MediaTrack, title: String, artist: String) {
        guard let title = nonempty(title) else { return }
        mutate { if let i = tracks.firstIndex(where: { $0.id == track.id }) { tracks[i].title = String(title.prefix(200)); tracks[i].artist = String((nonempty(artist) ?? "Bilinmeyen sanatçı").prefix(200)) } }
    }
    func delete(_ track: MediaTrack) {
        let previousTracks = tracks, previousPlaylists = playlists
        let artwork = artworkURL(for: track)
        do {
            tracks.removeAll { $0.id == track.id }
            for i in playlists.indices { playlists[i].trackIDs.removeAll { $0 == track.id } }
            synchronizeManualPlaylistChanges()
            try persist()
            if FileManager.default.fileExists(atPath: url(for: track).path) { try FileManager.default.removeItem(at: url(for: track)) }
            if let artwork { try? FileManager.default.removeItem(at: artwork) }
        } catch {
            tracks = previousTracks; playlists = previousPlaylists
            try? persist()
            errorMessage = error.localizedDescription
        }
    }
    func createPlaylist(name: String) {
        guard let name = nonempty(name) else { return }
        mutate { playlists.append(MediaPlaylist(name: String(name.prefix(80)))) }
    }
    @discardableResult
    func createPlaylist(name: String, trackIDs: [UUID]) throws -> MediaPlaylist {
        guard let name = nonempty(name) else { throw RitimError.message("Liste için bir ad gerekli.") }
        let allowed = Set(tracks.map(\.id))
        var seen = Set<UUID>()
        let ids = trackIDs.filter { allowed.contains($0) && seen.insert($0).inserted }
        guard !ids.isEmpty else { throw RitimError.message("Önerilen parçalar artık kitaplığında yok.") }
        let playlist = MediaPlaylist(name: String(name.prefix(80)), trackIDs: ids)
        playlists.append(playlist)
        do { try persist(); return playlist }
        catch { playlists.removeAll { $0.id == playlist.id }; throw error }
    }
    func deletePlaylist(_ playlist: MediaPlaylist) { mutate { playlists.removeAll { $0.id == playlist.id } } }
    func add(_ track: MediaTrack, to playlist: MediaPlaylist) {
        add([track], to: playlist)
    }
    /// Commit a batch once, preserving the selection order and pending download slots.
    @discardableResult
    func add(_ selection: [MediaTrack], to playlist: MediaPlaylist) -> Bool {
        guard let index = playlists.firstIndex(where: { $0.id == playlist.id }) else { return false }
        let allowed = Set(tracks.map(\.id))
        var seen = Set(playlists[index].trackIDs)
        let additions = selection.map(\.id).filter { allowed.contains($0) && seen.insert($0).inserted }
        guard !additions.isEmpty else { return true }
        let previous = playlists
        playlists[index].trackIDs.append(contentsOf: additions)
        synchronizeManualPlaylistChanges()
        do { try persist(); return true }
        catch { playlists = previous; errorMessage = error.localizedDescription; return false }
    }
    func remove(_ track: MediaTrack, from playlist: MediaPlaylist) {
        mutate { if let i = playlists.firstIndex(where: { $0.id == playlist.id }) { playlists[i].trackIDs.removeAll { $0 == track.id } } }
    }
    func tracks(in playlist: MediaPlaylist) -> [MediaTrack] {
        let live = playlists.first(where: { $0.id == playlist.id }) ?? playlist
        return live.trackIDs.compactMap { id in tracks.first { $0.id == id } }
    }
    private func nonempty(_ value: String?) -> String? { let text = value?.trimmingCharacters(in: .whitespacesAndNewlines); return text?.isEmpty == false ? text : nil }
    private func mutate(_ body: () -> Void) {
        let previousTracks = tracks, previousPlaylists = playlists
        body()
        synchronizeManualPlaylistChanges()
        do { try persist() } catch { tracks = previousTracks; playlists = previousPlaylists; errorMessage = error.localizedDescription }
    }
    private func persist() throws {
        guard canWrite else { throw RitimError.message("Kütüphane kaydı okunamadığı için mevcut veriler korunuyor. library.json dosyasını yedekten geri yükle.") }
        let data = try JSONEncoder().encode(State(tracks: tracks, playlists: playlists, seeded: seeded))
        try data.write(to: stateURL, options: .atomic)
    }
    private func seedOriginals() {
        let demos = [("gece-yolu", "Gece Yolu"), ("kiyi", "Kıyı"), ("yorunge", "Yörünge")]
        for (file, title) in demos {
            guard let source = Bundle.main.url(forResource: file, withExtension: "m4a") else { continue }
            let dest = directory.appendingPathComponent(file + ".m4a")
            do {
                if !FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.copyItem(at: source, to: dest) }
                let size = (try dest.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
                tracks.append(MediaTrack(title: title, artist: "Ritim Studio • Özgün demo", fileName: dest.lastPathComponent, duration: 32, fileSize: Int64(size)))
            } catch { errorMessage = error.localizedDescription }
        }
        seeded = true
        do { try persist() } catch { errorMessage = error.localizedDescription }
    }
}

// Stream media in bounded chunks; backup never loads the whole archive into RAM.
struct LibraryBackupManifest: Codable {
    var version = 1
    var includesMedia: Bool
    var tracks: [MediaTrack]
    var playlists: [MediaPlaylist]
    var files: [File]
    struct File: Codable { var path: String; var size: UInt64 }
}

actor LibraryArchive {
    static let shared = LibraryArchive()
    private let magic = Data("RITIMBK1".utf8)
    private let chunkSize = 1_048_576
    private func validName(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." && !value.contains("/") && !value.contains("\\")
    }
    private func validate(_ manifest: LibraryBackupManifest) throws {
        guard manifest.version == 1, manifest.tracks.count <= 100_000, manifest.files.count <= 300_000,
              Set(manifest.tracks.map(\.id)).count == manifest.tracks.count,
              Set(manifest.playlists.map(\.id)).count == manifest.playlists.count,
              Set(manifest.files.map(\.path)).count == manifest.files.count,
              manifest.tracks.allSatisfy({ validName($0.fileName) && ($0.artworkFileName.map(validName) ?? true) })
        else { throw RitimError.message("Yedek kayıtları geçersiz veya desteklenmiyor.") }
        let media = Set(manifest.tracks.map { "Media/" + $0.fileName })
        let artwork = Set(manifest.tracks.compactMap(\.artworkFileName).map { "Artwork/" + $0 })
        let lyrics = Set(manifest.tracks.map { "Lyrics/" + $0.id.uuidString + ".json" })
        guard manifest.files.allSatisfy({ file in
            file.size <= 4_294_967_296 && ((manifest.includesMedia && media.contains(file.path)) || artwork.contains(file.path) || lyrics.contains(file.path))
        }) else { throw RitimError.message("Yedekte izin verilmeyen bir dosya var.") }
        if manifest.includesMedia {
            guard media.isSubset(of: Set(manifest.files.map(\.path))) else { throw RitimError.message("Tam yedekte medya dosyaları eksik.") }
        }
    }
    func export(root: URL, tracks: [MediaTrack], playlists: [MediaPlaylist], includeMedia: Bool) throws -> URL {
        let fm = FileManager.default
        var paths = Set<String>()
        for track in tracks {
            if includeMedia { paths.insert("Media/" + track.fileName) }
            if let name = track.artworkFileName, fm.fileExists(atPath: root.appendingPathComponent("Artwork/" + name).path) { paths.insert("Artwork/" + name) }
            let lyric = "Lyrics/" + track.id.uuidString + ".json"
            if fm.fileExists(atPath: root.appendingPathComponent(lyric).path) { paths.insert(lyric) }
        }
        // Validate names before resolving any source URL.
        var manifest = LibraryBackupManifest(includesMedia: includeMedia, tracks: tracks, playlists: playlists, files: paths.sorted().map { .init(path: $0, size: 0) })
        try validate(manifest)
        for i in manifest.files.indices {
            let url = root.appendingPathComponent(manifest.files[i].path)
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  url.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path + "/") else {
                throw RitimError.message("Yedeklenecek dosya güvenle okunamadı.")
            }
            manifest.files[i].size = UInt64(max(0, values.fileSize ?? 0))
        }
        try validate(manifest)
        let header = try JSONEncoder().encode(manifest)
        guard header.count <= 64 * chunkSize else { throw RitimError.message("Yedek bilgisi çok büyük.") }
        let output = fm.temporaryDirectory.appendingPathComponent("Ritim-\(UUID().uuidString).ritimbackup")
        fm.createFile(atPath: output.path, contents: nil)
        let writer = try FileHandle(forWritingTo: output)
        var succeeded = false
        defer { try? writer.close(); if !succeeded { try? fm.removeItem(at: output) } }
        try writer.write(contentsOf: magic)
        var length = UInt64(header.count).bigEndian
        try withUnsafeBytes(of: &length) { try writer.write(contentsOf: Data($0)) }
        try writer.write(contentsOf: header)
        for file in manifest.files {
            try Task.checkCancellation()
            let reader = try FileHandle(forReadingFrom: root.appendingPathComponent(file.path))
            do {
                var remaining = file.size
                var digest = SHA256()
                while remaining > 0 {
                    try Task.checkCancellation()
                    let data = try reader.read(upToCount: Int(min(UInt64(chunkSize), remaining))) ?? Data()
                    guard !data.isEmpty else { throw RitimError.message("Yedek sırasında kaynak dosya değişti.") }
                    try writer.write(contentsOf: data); digest.update(data: data); remaining -= UInt64(data.count)
                }
                guard (try reader.read(upToCount: 1) ?? Data()).isEmpty else { throw RitimError.message("Yedek sırasında kaynak dosya değişti.") }
                try writer.write(contentsOf: Data(digest.finalize()))
                try reader.close()
            } catch { try? reader.close(); throw error }
        }
        try writer.synchronize()
        succeeded = true
        return output
    }
    func matchingTracks(manifest: LibraryBackupManifest, staging: URL, tracks: [MediaTrack], root: URL) throws -> [UUID: UUID] {
        let byID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        func digest(_ url: URL) throws -> Data {
            let reader = try FileHandle(forReadingFrom: url)
            defer { try? reader.close() }
            var hash = SHA256()
            while let data = try reader.read(upToCount: chunkSize), !data.isEmpty {
                try Task.checkCancellation(); hash.update(data: data)
            }
            return Data(hash.finalize())
        }
        var matches: [UUID: UUID] = [:]
        var cachedDigests: [UUID: Data] = [:]
        let sizes = Dictionary(uniqueKeysWithValues: manifest.files.map { ($0.path, $0.size) })
        for source in manifest.tracks {
            if !manifest.includesMedia {
                if let current = byID[source.id], current.fileSize == source.fileSize,
                   FileManager.default.fileExists(atPath: root.appendingPathComponent("Media/" + current.fileName).path) {
                    matches[source.id] = current.id
                }
                continue
            }
            let size = sizes["Media/" + source.fileName] ?? 0
            let sourceDigest = try digest(staging.appendingPathComponent("Media/" + source.fileName))
            let candidates = tracks.filter { $0.fileSize >= 0 && UInt64($0.fileSize) == size }
                .sorted { $0.id == source.id && $1.id != source.id }
            for current in candidates {
                let url = root.appendingPathComponent("Media/" + current.fileName)
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                let hash: Data
                if let cached = cachedDigests[current.id] { hash = cached }
                else { hash = try digest(url); cachedDigests[current.id] = hash }
                if hash == sourceDigest { matches[source.id] = current.id; break }
            }
        }
        return matches
    }
    func unpack(_ archive: URL) throws -> (LibraryBackupManifest, URL) {
        let reader = try FileHandle(forReadingFrom: archive)
        defer { try? reader.close() }
        func exact(_ count: Int) throws -> Data {
            let data = try reader.read(upToCount: count) ?? Data()
            guard data.count == count else { throw RitimError.message("Yedek eksik veya bozuk.") }
            return data
        }
        guard try exact(8) == magic else { throw RitimError.message("Bu bir Ritim yedeği değil.") }
        let length = try exact(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        guard length <= 64 * chunkSize else { throw RitimError.message("Yedek başlığı çok büyük.") }
        let manifest = try JSONDecoder().decode(LibraryBackupManifest.self, from: exact(Int(length)))
        try validate(manifest)
        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appendingPathComponent("RitimRestore-\(UUID().uuidString)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        var succeeded = false
        defer { if !succeeded { try? fm.removeItem(at: staging) } }
        for file in manifest.files {
            try Task.checkCancellation()
            let target = staging.appendingPathComponent(file.path)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            fm.createFile(atPath: target.path, contents: nil)
            let writer = try FileHandle(forWritingTo: target)
            do {
                var remaining = file.size
                var digest = SHA256()
                while remaining > 0 {
                    try Task.checkCancellation()
                    let data = try exact(Int(min(UInt64(chunkSize), remaining)))
                    digest.update(data: data); try writer.write(contentsOf: data); remaining -= UInt64(data.count)
                }
                guard try exact(32) == Data(digest.finalize()) else { throw RitimError.message("Yedekteki dosyanın bütünlüğü doğrulanamadı.") }
                try writer.close()
            } catch { try? writer.close(); throw error }
        }
        guard (try reader.read(upToCount: 1) ?? Data()).isEmpty else { throw RitimError.message("Yedekte beklenmeyen ek veri var.") }
        succeeded = true
        return (manifest, staging)
    }
}
