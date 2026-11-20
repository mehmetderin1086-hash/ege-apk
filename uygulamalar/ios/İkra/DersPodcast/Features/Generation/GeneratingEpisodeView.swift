import SwiftData
import SwiftUI

/// Seslendirme sürerken ya da yarım kaldığında bölüm ekranı. #7: onay bekleyen bölümde senaryo önizlemesi.
struct GeneratingEpisodeView: View {
    var episode: Episode
    @Environment(GenerationCoordinator.self) private var generator
    @Environment(\.modelContext) private var context
    @State private var preview = PreviewPlayer()

    var body: some View {
        if episode.needsApproval {
            ScriptPreviewView(episode: episode)
        } else {
            progress
        }
    }

    private var progress: some View {
        ScrollView {
            VStack(spacing: 20) {
                EpisodeArtwork(title: episode.title, size: 110, cover: episode.visuals?.cover)
                    .padding(.top, 24)
                Text(episode.title)
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                if generator.isRunning(episode) {
                    PulsingWave()
                    if let until = generator.retryUntil[episode.id] {
                        VStack(spacing: 6) {
                            // Asıl neden (kota, ağ) bölüme yazılır; yoksa genel metin.
                            Text(episode.errorMessage ?? "Ses hizmeti beklemede. Otomatik devam edecek.")
                                .font(.subheadline).multilineTextAlignment(.center)
                            Text(until, style: .timer).monospacedDigit()
                            Button("Şimdi dene", systemImage: "arrow.clockwise") { generator.retryVoicingNow(episode) }
                                .buttonStyle(.bordered)
                                .frame(minHeight: 44)
                        }
                        .padding(.horizontal, 24)
                    }
                    Text(generator.progressText(for: episode.id) ?? "Seslendiriliyor · \(episode.scenesDone)/\(episode.scenesTotal) sahne")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    ProgressView(value: episode.progress).padding(.horizontal, 48)
                    Button("Durdur", role: .destructive) { generator.cancel(episode) }
                        .buttonStyle(.bordered)
                    PreviewBar(episode: episode, preview: preview)
                    if generator.hasPreviousAudio(episode) {
                        Button("Vazgeç, eski sese dön", systemImage: "arrow.uturn.backward") {
                            preview.stop()
                            generator.restorePreviousAudio(episode, context: context)
                        }
                        .font(.subheadline)
                    }
                } else {
                    if let message = episode.errorMessage {
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    Text(FailedEpisodeView.preservedText(episode))
                        .font(.footnote).foregroundStyle(.secondary)
                    ProgressView(value: episode.progress).padding(.horizontal, 48)
                    if generator.hasPreviousAudio(episode) {
                        Button("Eski sese dön", systemImage: "arrow.uturn.backward") { generator.restorePreviousAudio(episode, context: context) }
                            .buttonStyle(.bordered)
                    }
                    Button {
                        if episode.canResume { generator.resume(episode, context: context, userInitiated: true) }
                        else { generator.recoverAudio(episode, context: context) }
                    } label: {
                        Label("Devam et", systemImage: "play.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, 48)
                    .disabled(episode.script == nil || episode.settings == nil)
                }

                if let error = generator.verifyError[episode.id] {
                    Label("Doğrulama yapılamadı: \(error)", systemImage: "exclamationmark.shield")
                        .font(.caption).foregroundStyle(.orange)
                        .padding(.horizontal, 24)
                }

                if let script = episode.script {
                    GroupBox("Özet") {
                        Text(script.summary).font(.callout).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 24)
        }
    }
}

/// Üretimi başarısız bölüm: kalan sesi kurtarma ve silme.
struct FailedEpisodeView: View {
    var episode: Episode
    var onDelete: () -> Void
    @Environment(GenerationCoordinator.self) private var generator
    @Environment(\.modelContext) private var context

    var body: some View {
        ContentUnavailableView {
            Label("Bölüm oluşturulamadı", systemImage: "exclamationmark.triangle")
        } description: {
            Text(episode.errorMessage ?? "Bilinmeyen bir hata oluştu.")
        } actions: {
            if episode.script != nil, episode.settings != nil {
                // #4: neyin korunduğunu söyle.
                Text(Self.preservedText(episode) + ". Yalnızca eksik sahneler seslendirilecek.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Seslendirmeye devam et") { generator.recoverAudio(episode, context: context) }
                    .buttonStyle(.borderedProminent)
            }
            Button("Bölümü sil", role: .destructive) { onDelete() }
                .buttonStyle(.bordered)
        }
    }

    /// "Senaryo kayıtlı · 34/52 sahne hazır"
    static func preservedText(_ episode: Episode) -> String {
        guard let script = episode.script, let settings = episode.settings else { return "Senaryo okunamadı" }
        let total = script.flatScenes.count
        let ready = script.flatScenes.indices.filter {
            FileManager.default.fileExists(atPath: GenerationCoordinator.sceneURL(episode, settings: settings, index: $0).path)
        }.count
        return preservedText(ready: ready, total: total)
    }

    nonisolated static func preservedText(ready: Int, total: Int) -> String {
        "Senaryo kayıtlı · \(min(ready, total))/\(total) sahne hazır"
    }
}
