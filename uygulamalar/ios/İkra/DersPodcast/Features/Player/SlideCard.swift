import SwiftData
import SwiftUI

// MARK: - Öneri 21: oynatmayla senkron slaytlar

struct SlideCard: View {
    var episode: Episode
    /// #16/#50: görüntülenen bölüm çalmıyorsa gösterilecek konu (çalıyorsa oynatıcının konusu).
    var focusChapter: Int? = nil
    @State private var showFull = false
    @Environment(PlayerController.self) private var player
    @Environment(\.modelContext) private var context
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        Group {
            if let slides = episode.slides, let slide = slides.first(where: { $0.chapterIndex == chapter }) ?? slides.first {
                // Kompakt kart: transkriptten yer çalmaz. Dokununca slaytın tamamı yarım sayfada açılır.
                Button { showFull = true } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: slide.symbol).font(.title3).foregroundStyle(Theme.gradient).frame(width: 28)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(slide.title)
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("\(slide.bullets.count) madde\(slide.formula?.isEmpty == false ? " · formül" : "") · dokun ve gör")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "arrow.up.left.and.arrow.down.right").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint("Slaytın tüm maddelerini göster")
                .sheet(isPresented: $showFull) {
                    SlideDetail(slide: slide).presentationDetents([.medium, .large])
                }
                .padding(12)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .id(slide.chapterIndex)
                .transition(.opacity)
                .animation(.smooth, value: chapter)
            } else {
                Button {
                    Task { await generate() }
                } label: {
                    Label(loading ? "Slaytlar hazırlanıyor…" : "Senkron slaytları oluştur", systemImage: "rectangle.on.rectangle.angled")
                        .font(.subheadline.bold())
                }
                .buttonStyle(.bordered)
                .disabled(loading)
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            }
        }
        .padding(.horizontal, 16)
    }

    /// Görüntülenen bölümün konusu (başka bölüm çalarken onun konu indeksi kullanılmaz).
    private var chapter: Int {
        player.episode?.id == episode.id ? player.currentChapterIndex : (focusChapter ?? 0)
    }

    private func generate() async {
        loading = true
        error = nil
        defer { loading = false }
        do { try await StudyMaterials.buildSlides(episode, context: context) }
        catch { self.error = error.localizedDescription }
    }
}

/// Slaytın tam hali: maddeler kesilmeden, kaydırılabilir.
struct SlideDetail: View {
    var slide: LessonSlide

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: slide.symbol).font(.title).foregroundStyle(Theme.gradient)
                    Text(slide.title).font(.title3.bold()).fixedSize(horizontal: false, vertical: true)
                }
                ForEach(slide.bullets, id: \.self) { bullet in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Circle().fill(.tint).frame(width: 7, height: 7)
                        Text(bullet).font(.body).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let formula = slide.formula, !formula.isEmpty {
                    Text(formula)
                        .font(.system(.body, design: .monospaced).bold())
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(22)
        }
    }
}
