import AVFoundation
import SwiftUI

/// #44: transkriptten 60 sn'lik klip paylaşımı (ses + o aralığın metni + uygulama bağlantısı).
struct ClipShareSheet: View {
    let episode: Episode
    let start: Double

    @Environment(\.dismiss) private var dismiss
    @State private var from: Double = 0
    @State private var busy = false
    @State private var error: String?
    @State private var shareItems: ShareItems?

    private struct ShareItems: Identifiable {
        let id = UUID()
        var items: [Any]
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Başlangıç", value: from.clockText)
                    LabeledContent("Bitiş", value: ClipShare.range(start: from, duration: episode.duration).end.clockText)
                    ViewThatFits(in: .horizontal) {
                        HStack { shiftButtons }
                        VStack(alignment: .leading) { shiftButtons }
                    }
                } footer: {
                    Text("Klip en fazla 60 saniyedir; paylaşılan metinde bölümü o anda açan bağlantı bulunur.")
                }
                let text = ClipShare.transcript(episode.timeline, start: from, end: ClipShare.range(start: from, duration: episode.duration).end,
                                                settings: episode.settings)
                if !text.isEmpty {
                    Section("Bu aralıkta") { Text(text).font(.callout).lineLimit(12) }
                }
                if let error { Section { Text(error).foregroundStyle(.red).font(.caption) } }
                Section {
                    Button {
                        Task { await make() }
                    } label: {
                        HStack { if busy { ProgressView() }; Text(busy ? "Klip hazırlanıyor…" : "Klibi paylaş") }
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .disabled(busy || episode.audioURL == nil)
                }
            }
            .navigationTitle("Klip paylaş")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } } }
            .onAppear { from = ClipShare.range(start: start, duration: episode.duration).start }
            .sheet(item: $shareItems) { ShareSheet(items: $0.items) }
        }
    }

    @ViewBuilder private var shiftButtons: some View {
        Button("−10 sn") { from = ClipShare.range(start: from - 10, duration: episode.duration).start }
            .buttonStyle(.bordered).frame(minHeight: 44)
            .accessibilityLabel("Başlangıcı 10 saniye geri al")
        Button("+10 sn") { from = ClipShare.range(start: from + 10, duration: episode.duration).start }
            .buttonStyle(.bordered).frame(minHeight: 44)
            .accessibilityLabel("Başlangıcı 10 saniye ileri al")
    }

    private func make() async {
        guard let audio = episode.audioURL else { return }
        busy = true
        error = nil
        defer { busy = false }
        let range = ClipShare.range(start: from, duration: episode.duration)
        let output = URL.temporaryDirectory.appending(path: "\(ChapterAudioExport.fileName(episode.title)) \(Int(range.start) / 60)-\(String(format: "%02d", Int(range.start) % 60)).m4a")
        do {
            try await ClipShare.export(audio: audio, start: range.start, end: range.end, title: "\(episode.title) · \(range.start.clockText)", to: output)
            let link = AppLink.episode(episode.id, time: range.start, play: true).url
            let caption = "\(episode.title) · \(range.start.clockText)\n\(link.absoluteString)"
            shareItems = ShareItems(items: [output, caption])
        } catch {
            self.error = error.localizedDescription
        }
    }
}

enum ClipShare {
    static let length: Double = 60

    /// Klip aralığı: [başlangıç, başlangıç + 60] ve bölüm sınırları içinde (bölüm sonuna yakınsa geriye kayar).
    nonisolated static func range(start: Double, duration: Double, length: Double = 60) -> (start: Double, end: Double) {
        guard duration > 0, duration.isFinite else { return (0, 0) }
        let len = min(length, duration)
        let s = min(max(0, start.isFinite ? start : 0), duration - len)
        return (s, s + len)
    }

    /// Aralıkla kesişen turların metni (konuşmacı adıyla).
    nonisolated static func transcript(_ timeline: Timeline?, start: Double, end: Double, settings: PodcastSettings?) -> String {
        guard let timeline else { return "" }
        return timeline.turns.filter { $0.end > start && $0.start < end }.map { turn in
            let name = settings?.displayName(for: turn.speaker) ?? turn.speaker.rawValue
            return "\(name): \(turn.text)"
        }.joined(separator: "\n")
    }

    @concurrent
    nonisolated static func export(audio: URL, start: Double, end: Double, title: String, to output: URL) async throws {
        let asset = AVURLAsset(url: audio)
        try? FileManager.default.removeItem(at: output)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw APIError(status: 0, code: "export", message: "Klip hazırlanamadı.")
        }
        session.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), end: CMTime(seconds: end, preferredTimescale: 600))
        let titleItem = AVMutableMetadataItem()
        titleItem.identifier = .commonIdentifierTitle
        titleItem.value = title as NSString
        session.metadata = [titleItem]
        try await session.export(to: output, as: .m4a)
    }
}
