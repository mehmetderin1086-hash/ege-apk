import SwiftUI

struct OfficialMealsView: View {
    @ObservedObject private var store = OfficialMealStore.shared
    @ObservedObject private var player = AdhanPlayer.shared
    @State private var query = ""
    @State private var voice = "Tümü"
    @State private var offlineOnly = false
    private var voices: [String] { Array(Set(store.tracks.map(\.voice))).sorted() }
    private var filtered: [OfficialMealTrack] {
        store.tracks.filter {
            (voice == "Tümü" || $0.voice == voice) && (!offlineOnly || store.downloaded.contains($0.id)) &&
            (query.isEmpty || ($0.title + " " + $0.voice + " " + $0.provider).localizedStandardContains(query))
        }
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Sesli mealler", systemImage: "headphones").font(.title3.weight(.semibold))
                        Spacer()
                        Text("\(store.downloaded.count) hazır").font(.subheadline.weight(.medium))
                    }
                    Text("Vav Radyo · Diyanet Kur’an Radyo").font(.subheadline).foregroundStyle(.white.opacity(0.85))
                    if !store.pending.isEmpty || store.externalTransferActive {
                        ProgressView(value: Double(store.downloaded.count), total: Double(max(1, store.tracks.count)))
                            .tint(EzanDesign.gold)
                        HStack {
                            Text(store.externalTransferActive ? "Arşiv yükleniyor" : store.paused ? "Duraklatıldı" : "\(store.pending.count) kayıt sırada")
                                .font(.caption)
                            Spacer()
                            if !store.externalTransferActive {
                                Button(store.paused ? "Devam et" : "Duraklat") { store.setPaused(!store.paused) }
                                    .font(.subheadline).buttonStyle(.bordered)
                            }
                        }
                    } else if store.downloaded.count < store.tracks.count {
                        Button { store.enqueue(store.tracks) } label: {
                            Label("Tümünü indir", systemImage: "arrow.down.circle").frame(minHeight: 38)
                        }.buttonStyle(.bordered)
                    }
                }.foregroundStyle(.white).padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(EzanDesign.heroGradient).clipShape(RoundedRectangle(cornerRadius: 22))
                HStack {
                    Image(systemName: "magnifyingglass")
                    TextField("Sûre, cüz veya seslendirmen ara", text: $query).font(.body)
                }.padding(16).sekineCard()
                HStack {
                    Menu {
                        Picker("Seslendiren", selection: $voice) {
                            Text("Tümü").tag("Tümü")
                            ForEach(voices, id: \.self) { Text($0).tag($0) }
                        }
                    } label: { Label(voice == "Tümü" ? "Seslendiren" : voice, systemImage: "person.wave.2").font(.subheadline).frame(minHeight: 44) }
                    Spacer()
                    Toggle("İndirilen", isOn: $offlineOnly).font(.subheadline).fixedSize()
                }
                if player.isPlaying {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(player.activeTitle).font(.headline)
                            Text(player.activeSubtitle).font(.caption).foregroundStyle(Palette.textSecondary)
                        }
                        Spacer()
                        Button { player.stop() } label: { Image(systemName: "stop.circle.fill").font(.largeTitle) }.accessibilityLabel("Oynatmayı durdur")
                    }.padding(16).sekineCard(active: true)
                }
                EzanSectionTitle(title: "Kayıtlar", detail: "\(filtered.count) kayıt")
                if filtered.isEmpty { ContentUnavailableView.search(text: query) }
                ForEach(filtered) { track in
                    HStack(alignment: .center, spacing: 12) {
                        Button { store.play(track) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "play.circle.fill").font(.system(size: 34)).foregroundStyle(Palette.accent)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(track.title).font(.body.weight(.semibold)).foregroundStyle(Palette.textPrimary).multilineTextAlignment(.leading)
                                    Text("\(track.voice) · \(track.provider)").font(.caption).foregroundStyle(Palette.textSecondary)
                                    if let error = store.failures[track.id] { Text(error).font(.caption).foregroundStyle(.red) }
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain)
                        if store.downloaded.contains(track.id) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.accent).frame(width: 44).accessibilityLabel("Çevrimdışı hazır")
                        } else if store.active.contains(track.id) {
                            ProgressView().frame(width: 44).accessibilityLabel("İndiriliyor")
                        } else if store.pending.contains(track.id) {
                            Image(systemName: "clock").foregroundStyle(Palette.textSecondary).frame(width: 44).accessibilityLabel("İndirme sırasında")
                        } else {
                            Button { store.enqueue([track]) } label: { Image(systemName: "arrow.down.circle").font(.title2).frame(width: 44, height: 44) }.accessibilityLabel("\(track.title) indir")
                        }
                    }.padding(16).sekineCard()
                }
                Text("Kayıtlar, yayıncıların sunduğu özgün seslendirmelerdir. Her yayıncının arşivinde bulunabilen dosyalar listelenir.")
                    .font(.caption).foregroundStyle(Palette.textSecondary)
            }.padding(20)
        }.background(Palette.background)
            .task {
                while !Task.isCancelled {
                    await store.refreshTransferredFiles()
                    try? await Task.sleep(for: .seconds(15))
                }
            }
    }
}
