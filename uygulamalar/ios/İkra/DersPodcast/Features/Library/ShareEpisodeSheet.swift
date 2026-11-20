import SwiftData
import SwiftUI

/// #44/#45: paylaş: bölüm işaretli ses, çalışma föyü, seri kitapçığı, klip, bağlantı, podcast akışı.
struct ShareEpisodeSheet: View {
    let episode: Episode
    @Environment(\.dismiss) private var dismiss
    @Environment(PlayerController.self) private var player
    @Query(sort: \Episode.seriesIndex) private var all: [Episode]
    @State private var busy: String?
    @State private var shareURL: URL?
    @State private var note: String?
    @State private var showClip = false
    @State private var inFeed = false

    var body: some View {
        NavigationStack {
            List {
                if episode.status == .ready, episode.audioURL != nil {
                    Section {
                        action("Ses (bölüm işaretli, kapaklı)", "waveform") {
                            let url = try await ChapterAudioExport.export(episode)
                            if !ChapterAudioExport.lastExportHadChapters, !(episode.timeline?.chapters.isEmpty ?? true) {
                                note = "Bu cihazda bölüm işaretleri dosyaya yazılamadı; podcast akışında işaretler bulunur."
                            }
                            return url
                        }
                        Button { showClip = true } label: {
                            Label("Klip paylaş (60 sn)", systemImage: "scissors").frame(minHeight: 44)
                        }
                    } header: {
                        Text("Ses")
                    }
                }
                Section {
                    action("Çalışma föyü (PDF)", "doc.richtext") { try await EpisodeExporter.writePDFInBackground(episode) }
                    action("Çalışma föyü (Markdown)", "doc.text") { try EpisodeExporter.writeMarkdown(episode) }
                    if let seriesID = episode.seriesID {
                        let members = all.filter { $0.seriesID == seriesID && $0.status == .ready }
                        if members.count > 1 {
                            action("Serinin kitapçığı (PDF, \(members.count) bölüm)", "book") { try await StudySheetExport.writeSeriesPDF(members) }
                        }
                    }
                } header: {
                    Text("Notlarınla föy")
                } footer: {
                    Text("Föyde yer imlerin, Cornell notların, kavramlar, formüller ve slaytlar bulunur; başlığa dokununca uygulama o anda açılır.")
                }
                Section {
                    ShareLink(item: AppLink.episode(episode.id, time: nil, play: false).url) {
                        Label("Uygulama bağlantısı", systemImage: "link").frame(minHeight: 44)
                    }
                    if episode.status == .ready {
                        Button {
                            Task { await toggleFeed() }
                        } label: {
                            Label(inFeed ? "Podcast akışından çıkar" : "Podcast akışına ekle", systemImage: "dot.radiowaves.left.and.right")
                                .frame(minHeight: 44)
                        }
                        .disabled(busy != nil)
                    }
                }
                if let busy { Section { HStack { ProgressView(); Text(busy) } } }
                if let note { Section { Text(note).font(.caption).foregroundStyle(.secondary) } }
            }
            .navigationTitle("Paylaş")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } } }
            .onAppear { inFeed = PodcastFeed.published.contains(episode.id) }
            .sheet(item: $shareURL) { ShareSheet(items: [$0]) }
            .sheet(isPresented: $showClip) {
                ClipShareSheet(episode: episode, start: player.episode?.id == episode.id ? player.currentTime : episode.lastPosition)
            }
        }
    }

    private func action(_ title: String, _ symbol: String, make: @escaping () async throws -> URL) -> some View {
        Button {
            Task {
                busy = "\(title) hazırlanıyor…"
                note = nil
                defer { busy = nil }
                do { shareURL = try await make() } catch { note = error.localizedDescription }
            }
        } label: {
            Label(title, systemImage: symbol).frame(minHeight: 44)
        }
        .disabled(busy != nil)
    }

    private func toggleFeed() async {
        busy = inFeed ? "Akıştan çıkarılıyor…" : "Akışa ekleniyor…"
        defer { busy = nil }
        do {
            if inFeed { try await PodcastFeed.remove(episode) } else { try await PodcastFeed.publish(episode) }
            inFeed.toggle()
        } catch {
            note = error.localizedDescription
        }
    }
}
