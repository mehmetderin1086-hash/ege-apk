import SwiftData
import SwiftUI

/// #38/#39/#42: bölümü düzenle: ad, seri, ders bağı, dinlendi, podcast akışı.
struct EpisodeOrganizeSheet: View {
    let episode: Episode
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Course.createdAt) private var courses: [Course]
    @Query(sort: \Episode.createdAt, order: .reverse) private var episodes: [Episode]
    @State private var title = ""
    @State private var series: UUID?
    @State private var newSeriesName = ""
    @State private var courseID: UUID?
    @State private var finished = false
    @State private var inFeed = false
    @State private var feedBusy = false
    @State private var error: String?

    /// "Yeni seri…" seçeneğinin işareti.
    static let newSeriesTag = UUID(uuidString: "00000000-0000-0000-0000-00000000005E")!

    private var allSeries: [(id: UUID, title: String)] {
        var seen = Set<UUID>()
        return episodes.compactMap { e in
            guard let id = e.seriesID, seen.insert(id).inserted else { return nil }
            return (id, e.seriesTitle ?? "Seri")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Ad") {
                    TextField("Bölüm adı", text: $title, axis: .vertical)
                        .lineLimit(1...4)
                        .onChange(of: title) { _, text in
                            if text.count > EpisodeTitle.maxLength { title = String(text.prefix(EpisodeTitle.maxLength)) }
                        }
                }
                Section {
                    Picker("Seri", selection: $series) {
                        Text("Seri yok").tag(UUID?.none)
                        ForEach(allSeries, id: \.id) { Text($0.title).tag(UUID?.some($0.id)) }
                        Text("Yeni seri…").tag(UUID?.some(Self.newSeriesTag))
                    }
                    // Başlık bölüm üstünde; satır etiketi yinelenmesin, seçili ad tam genişliği kullansın.
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if series == Self.newSeriesTag {
                        TextField("Yeni serinin adı", text: $newSeriesName)
                            .onChange(of: newSeriesName) { _, text in
                                if text.count > 120 { newSeriesName = String(text.prefix(120)) }
                            }
                    }
                } header: {
                    Text("Seri")
                } footer: {
                    Text("Seriye eklenen bölüm sona yerleşir; sırayı seri sayfasında sürükleyerek değiştirebilirsin.")
                }
                Section {
                    Picker("Ders", selection: $courseID) {
                        Text("Ders yok").tag(UUID?.none)
                        ForEach(courses) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                } header: {
                    Text("Ders")
                } footer: {
                    Text("Bölümü bir derse bağlarsan Plan sekmesinde o dersin altında görünür.")
                }
                Section {
                    Toggle("Dinlendi", isOn: $finished)
                    if episode.status == .ready {
                        Toggle(isOn: Binding(get: { inFeed }, set: { on in Task { await setFeed(on) } })) {
                            HStack { Text("Podcast akışında"); if feedBusy { ProgressView() } }
                        }
                        .disabled(feedBusy)
                    }
                    if let error { Text(error).font(.caption).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Kaydet") { save() } }
            }
            .onAppear {
                title = episode.title
                series = episode.seriesID
                courseID = episode.courseID
                finished = episode.isFinished
                inFeed = PodcastFeed.published.contains(episode.id)
            }
        }
    }

    private func setFeed(_ on: Bool) async {
        feedBusy = true
        error = nil
        defer { feedBusy = false }
        do {
            if on { try await PodcastFeed.publish(episode) } else { try await PodcastFeed.remove(episode) }
            inFeed = on
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func save() {
        if let name = EpisodeTitle.cleaned(title) { episode.title = name }
        episode.courseID = courseID
        if finished != episode.isFinished { QuickActions.setFinished(episode, finished) }
        if series != episode.seriesID {
            let oldSeries = episode.seriesID
            if series == Self.newSeriesTag {
                let seriesName = newSeriesName.trimmingCharacters(in: .whitespacesAndNewlines)
                episode.seriesID = UUID()
                episode.seriesTitle = String((seriesName.isEmpty ? episode.title : seriesName).prefix(120))
                episode.seriesIndex = 1
            } else if let target = series {
                episode.seriesID = target
                episode.seriesTitle = episodes.first { $0.seriesID == target }?.seriesTitle ?? "Seri"
                episode.seriesIndex = (episodes.filter { $0.seriesID == target && $0.id != episode.id }.map(\.seriesIndex).max() ?? 0) + 1
            } else {
                episode.seriesID = nil
                episode.seriesTitle = nil
                episode.seriesIndex = 0
            }
            // Eski seride kalanların sırası kapanır (seri sayfasında "1., 3., 4." kalmasın).
            if let oldSeries { SeriesOps.closeGaps(context: context, only: oldSeries, excluding: episode.id) }
        }
        try? context.save()
        dismiss()
    }
}
