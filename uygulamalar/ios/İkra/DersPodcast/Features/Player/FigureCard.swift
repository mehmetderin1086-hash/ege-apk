import SwiftData
import SwiftUI

// MARK: - Şekil ↔ transkript eşlemesi (figuremap.json, bölüm klasöründe)

extension Episode {
    var figureMap: [FigureMapEntry]? {
        get { (try? Data(contentsOf: directory.appending(path: "figuremap.json"))).flatMap { try? JSONDecoder().decode([FigureMapEntry].self, from: $0) } }
        set {
            let url = directory.appending(path: "figuremap.json")
            if let newValue { try? JSONEncoder().encode(newValue).write(to: url) } else { try? FileManager.default.removeItem(at: url) }
        }
    }
}

enum FigureMapper {
    /// Bu oturumda denenmiş bölümler (başarısız istek her açılışta tekrarlanmasın).
    private static var attempted = Set<UUID>()

    /// Kaynak şekilleri varsa ve eşleme yoksa sunucudan alır (oturumda bir kez).
    static func ensure(_ episode: Episode) async {
        let figures = episode.sourceFigures
        guard !figures.isEmpty, episode.figureMap == nil, let timeline = episode.timeline,
              attempted.insert(episode.id).inserted else { return }
        let chapters = timeline.chapters.prefix(15).map { chapter in
            FigureMapRequest.Chapter(index: chapter.id, title: chapter.title,
                                     turns: timeline.turns.filter { $0.chapterIndex == chapter.id }.prefix(60)
                                        .map { FigureMapRequest.Turn(index: $0.id, text: String($0.text.prefix(300))) })
        }
        let request = FigureMapRequest(figures: figures.prefix(30).map { .init(id: $0.id, caption: $0.caption, page: $0.page) },
                                       chapters: Array(chapters))
        guard let map = try? await APIClient.shared.figureMap(request), episode.modelContext != nil else { return }
        episode.figureMap = map
    }

    /// O an gösterilecek şekil: aynı bölümde, konuşulan tura en yakın (önceki) eşleşme; yoksa bölüm düzeyi eşleşme.
    static func figure(for map: [FigureMapEntry], chapter: Int, turn: Int?) -> String? {
        let inChapter = map.filter { $0.chapterIndex == chapter && $0.confidence >= 0.4 }
        if let turn, let hit = inChapter.filter({ ($0.turnIndex ?? Int.max) <= turn }).max(by: { ($0.turnIndex ?? -1) < ($1.turnIndex ?? -1) }) {
            return hit.figureId
        }
        return inChapter.first { $0.turnIndex == nil }?.figureId ?? inChapter.min { ($0.turnIndex ?? 0) < ($1.turnIndex ?? 0) }?.figureId
    }
}

/// Dinlerken: anlatılan konuya ait kaynak şekli (kompakt kart; dokununca tam ekran).
struct FigureCard: View {
    var episode: Episode
    /// #16: görüntülenen bölüm çalmıyorsa gösterilecek konu.
    var focusChapter: Int? = nil
    @Environment(PlayerController.self) private var player
    @State private var map: [FigureMapEntry]?
    @State private var figures: [SourceFigure] = []
    @State private var zoom: SourceFigure?
    @State private var thumbs: [String: UIImage] = [:]

    var body: some View {
        Group {
            if let figure = current {
                Button { zoom = figure } label: {
                    HStack(spacing: 12) {
                        if let image = thumbs[figure.id] {
                            Image(uiImage: image).resizable().scaledToFit().frame(width: 96, height: 64)
                                .background(Color.white).clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Şimdi anlatılan şekil").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                            Text(figure.caption.isEmpty ? "Kaynak şekli" : figure.caption).font(.footnote.weight(.semibold)).lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.left.and.arrow.down.right").foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .transition(.opacity)
            }
        }
        .animation(.smooth, value: current?.id)
        .task(id: current?.id) {
            guard let figure = current, thumbs[figure.id] == nil else { return }
            thumbs[figure.id] = await DeckAssets.thumbnail(episode.figureURL(figure.id))
        }
        .task(id: episode.id) {
            figures = episode.sourceFigures
            map = episode.figureMap
            if map == nil, !figures.isEmpty {
                await FigureMapper.ensure(episode)
                map = episode.figureMap
            }
        }
        .fullScreenCover(item: $zoom) { FigureZoomView(episode: episode, figure: $0) }
    }

    private var current: SourceFigure? {
        let playing = player.episode?.id == episode.id
        guard let map, let id = FigureMapper.figure(for: map, chapter: playing ? player.currentChapterIndex : (focusChapter ?? 0),
                                                    turn: playing ? player.currentTurnIndex : nil) else { return nil }
        return figures.first { $0.id == id }
    }
}

/// Tam ekran şekil: iki parmakla yakınlaştırma, paylaşma, etiket quiz'i.
struct FigureZoomView: View {
    @Environment(\.dismiss) private var dismiss
    var episode: Episode
    var figure: SourceFigure
    @State private var scale: CGFloat = 1
    @State private var base: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var last: CGSize = .zero
    @State private var quiz = false
    @State private var image: UIImage?

    var body: some View {
        NavigationStack {
            GeometryReader { _ in
                if let image {
                    Image(uiImage: image).resizable().interpolation(.high).scaledToFit()
                        .scaleEffect(scale).offset(offset)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .gesture(MagnifyGesture()
                            .onChanged { scale = max(1, min(6, base * $0.magnification)) }
                            .onEnded { _ in
                                base = scale
                                if scale <= 1 { withAnimation { resetZoom() } }
                            })
                        // Sürükleme yalnızca yakınlaştırılmışken: eskiden her sürüklemede resim yana kayıp öyle kalıyordu.
                        .simultaneousGesture(DragGesture()
                            .onChanged {
                                guard scale > 1 else { return }
                                offset = CGSize(width: last.width + $0.translation.width, height: last.height + $0.translation.height)
                            }
                            .onEnded { _ in last = offset })
                        .onTapGesture(count: 2) { withAnimation { if scale > 1 { resetZoom() } else { scale = 2.5; base = 2.5 } } }
                        .background(Color.white)
                        .clipped()
                }
            }
            .navigationTitle(figure.caption.isEmpty ? "Şekil" : figure.caption)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } }
                ToolbarItemGroup(placement: .bottomBar) {
                    Text("\(figure.documentName) · s. \(figure.page)").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    ShareLink(item: episode.figureURL(figure.id)) { Image(systemName: "square.and.arrow.up") }
                    Button("Etiketleri tahmin et", systemImage: "questionmark.square.dashed") { quiz = true }
                }
            }
            .sheet(isPresented: $quiz) { LabelQuizView(episode: episode) }
            .task { image = UIImage(contentsOfFile: episode.figureURL(figure.id).path) }
        }
    }

    private func resetZoom() {
        scale = 1; base = 1; offset = .zero; last = .zero
    }
}

/// Bölümün tüm kaynak şekilleri.
struct FigureGalleryView: View {
    @Environment(\.dismiss) private var dismiss
    var episode: Episode
    @State private var zoom: SourceFigure?
    @State private var quiz = false
    @State private var figures: [SourceFigure] = []
    @State private var thumbs: [String: UIImage] = [:]

    var body: some View {
        NavigationStack {
            ScrollView {
                if figures.isEmpty {
                    ContentUnavailableView("Kaynak şekli yok", systemImage: "photo.on.rectangle",
                                           description: Text("Slayt destesi ekranından kitap sayfası fotoğrafı ekle; şekiller kesilip burada toplanır."))
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                    ForEach(figures, id: \.id) { figure in
                        Button { zoom = figure } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                if let image = thumbs[figure.id] {
                                    Image(uiImage: image).resizable().scaledToFit().frame(height: 120).frame(maxWidth: .infinity)
                                        .background(Color.white).clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                Text(figure.caption.isEmpty ? "Şekil \(figure.id)" : figure.caption).font(.caption.weight(.semibold)).lineLimit(2)
                                Text("s. \(figure.page)").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .navigationTitle("Şekiller")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Etiket quiz'i", systemImage: "questionmark.square.dashed") { quiz = true }.disabled(figures.isEmpty)
                }
            }
            .fullScreenCover(item: $zoom) { FigureZoomView(episode: episode, figure: $0) }
            .sheet(isPresented: $quiz) { LabelQuizView(episode: episode) }
            .task {
                figures = episode.sourceFigures
                for f in figures where thumbs[f.id] == nil { thumbs[f.id] = await DeckAssets.thumbnail(episode.figureURL(f.id)) }
            }
        }
    }
}

