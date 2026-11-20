import SwiftData
import SwiftUI

/// #14 (indirme kısmı): dersin videosunu sunucuda hazırlatıp telefona indirir; oynatıcı (I1) `lesson.videoFileName`'i kullanır.
struct OfflineVideoView: View {
    var context: LessonContext

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var runner = MediaJobRunner()
    @State private var quality = 480
    @State private var hasFile = false
    @State private var confirmDelete = false
    @State private var confirmClose = false
    @State private var fileBytes: Int64 = 0

    private var lesson: VideoLesson { context.lesson }
    private var canDownload: Bool { !lesson.url.isEmpty && !lesson.videoID.hasPrefix("upload-") }

    /// Tahmini boyut (MB/dk: 360p ≈ 4, 480p ≈ 7).
    private var estimate: Int64 {
        Int64(lesson.duration / 60 * (quality == 360 ? 4 : 7) * 1_048_576)
    }

    var body: some View {
        NavigationStack {
            Form {
                if hasFile {
                    Section {
                        Label("Video bu telefonda", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        if fileBytes > 0 { LabeledContent("Boyut", value: ByteFormat.string(fileBytes)) }
                        Button("Videoyu sil", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    } footer: {
                        Text("Oynatıcı çevrimdışı videoyu kullanır; resim içinde resim ve kilit ekranı da çalışır.")
                    }
                } else if !canDownload {
                    Section {
                        Label("Bu ders yüklediğin bir kayıttan oluştu; sunucuda indirilecek bir video yok.", systemImage: "info.circle")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        Picker("Kalite", selection: $quality) {
                            Text("360p").tag(360)
                            Text("480p").tag(480)
                        }
                        .modifier(AccessiblePickerStyle())
                        .disabled(runner.isRunning)
                        if lesson.duration > 0 {
                            LabeledContent("Tahmini boyut", value: "≈ " + ByteFormat.string(estimate))
                        }
                    } footer: {
                        Text("Video önce sunucuda hazırlanır, sonra telefona indirilir.")
                    }
                    progressSection
                }
            }
            .navigationTitle("Çevrimdışı video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { if runner.isRunning { confirmClose = true } else { dismiss() } }
                }
            }
            .onAppear(perform: refresh)
            .onDisappear { runner.cancel() }
            .interactiveDismissDisabled(runner.isRunning)
            .confirmationDialog("İşlem sürüyor", isPresented: $confirmClose, titleVisibility: .visible) {
                Button("Durdur ve kapat", role: .destructive) {
                    runner.cancel()
                    dismiss()
                }
                Button("Devam et", role: .cancel) {}
            } message: {
                Text("Sayfayı kapatırsan indirme durur.")
            }
            .confirmationDialog("Çevrimdışı video silinsin mi?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Sil", role: .destructive, action: deleteFile)
            } message: {
                Text("Ders ve transkript kalır; video yeniden indirilebilir.")
            }
        }
        .debugNarrowScreen()
    }

    @ViewBuilder
    private var progressSection: some View {
        Section {
            switch runner.phase {
            case .idle, .failed:
                Button {
                    start()
                } label: {
                    Label("İndir", systemImage: "arrow.down.circle").font(.headline).frame(maxWidth: .infinity)
                }
                if case .failed(let message) = runner.phase {
                    Label(message, systemImage: "xmark.octagon").font(.footnote).foregroundStyle(.red)
                } else if !runner.message.isEmpty {
                    Text(runner.message).font(.footnote).foregroundStyle(.secondary)
                }
            case .server, .download, .done:
                VStack(alignment: .leading, spacing: 8) {
                    Text(runner.phase == .download ? "Telefona indiriliyor" : "Sunucuda hazırlanıyor").font(.subheadline.weight(.semibold))
                    ProgressView(value: runner.progress)
                    HStack {
                        Text(runner.phase == .download && runner.totalBytes > 0
                             ? "\(ByteFormat.string(runner.receivedBytes)) / \(ByteFormat.string(runner.totalBytes))"
                             : runner.message)
                            .font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                        Spacer()
                        Text("%\(Int((runner.progress * 100).rounded()))").font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                Button("Durdur", systemImage: "stop.circle", role: .destructive) { runner.cancel() }
                    .disabled(!runner.isRunning)
            }
        }
    }

    private func refresh() {
        hasFile = lesson.hasVideoFile
        fileBytes = lesson.videoURL.flatMap { try? FileManager.default.attributesOfItem(atPath: $0.path)[.size] as? Int64 } ?? 0
    }

    private func start() {
        let request = MediaStartRequest(kind: .video, url: lesson.url, quality: quality,
                                        allowOther: ImportLinks.needsAllowOther(lesson.url) ? true : nil)
        let destination = lesson.directory.appending(path: "video.mp4")
        runner.begin(request, destination: destination) { url in
            VideoFiles.excludeFromBackup(url)
            lesson.videoFileName = url.lastPathComponent
            try? modelContext.save()
            refresh()
            runner.reset()
        }
    }

    private func deleteFile() {
        if let url = lesson.videoURL { try? FileManager.default.removeItem(at: url) }
        lesson.videoFileName = nil
        try? modelContext.save()
        runner.reset()
        refresh()
    }
}
