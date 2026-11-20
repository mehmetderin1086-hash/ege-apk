import SwiftUI

/// YouTube'da arama (yt-dlp `ytsearch`), sonuçtan doğrudan indirme.
struct AraGorunumu: View {
    @Environment(Yonlendirici.self) private var yonlendirici
    @State private var sorgu = ""
    @State private var sonuclar: [ListeOgesi] = []
    @State private var araniyor = false
    @State private var hata: String?
    @State private var gecmis: [String] = UserDefaults.standard.stringArray(forKey: "aramaGecmisi") ?? []
    @State private var gorev: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            List {
                if araniyor {
                    HStack { Spacer(); ProgressView("Aranıyor…"); Spacer() }.listRowBackground(Color.clear)
                } else if let hata {
                    ContentUnavailableView("Arama başarısız", systemImage: "exclamationmark.triangle", description: Text(hata))
                } else if sonuclar.isEmpty {
                    if gecmis.isEmpty {
                        ContentUnavailableView("YouTube'da ara", systemImage: "magnifyingglass",
                                               description: Text("Sonuca dokunup kalite seç ya da kaydırarak hızlıca indir."))
                    } else {
                        Section("Son aramalar") {
                            ForEach(gecmis, id: \.self) { kayit in
                                Button { sorgu = kayit; ara() } label: { Label(kayit, systemImage: "clock.arrow.circlepath") }.tint(.primary)
                            }
                            .onDelete { gecmis.remove(atOffsets: $0); gecmisiKaydet() }
                        }
                    }
                } else {
                    ForEach(sonuclar) { oge in satir(oge) }
                }
            }
            .navigationTitle("Ara")
            .searchable(text: $sorgu, prompt: "Video, kanal, şarkı…")
            .onSubmit(of: .search, ara)
        }
    }

    private func satir(_ oge: ListeOgesi) -> some View {
        Button {
            if let adres = oge.adres { yonlendirici.bilgi = BilgiIstegi(adres: adres, baslik: oge.title, kapak: oge.thumbnail) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                KucukResim(adres: oge.thumbnail, sure: oge.duration, genislik: 132)
                VStack(alignment: .leading, spacing: 4) {
                    Text(oge.title ?? "").font(.subheadline.weight(.medium)).lineLimit(3)
                    Text([oge.uploader, oge.viewCount.map { "\($0.formatted(.number.notation(.compactName))) izlenme" }, oge.canli ? "CANLI" : nil]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .tint(.primary)
        .swipeActions(edge: .trailing) {
            Button { hizli(oge, .video) } label: { Label("Video", systemImage: "film") }.tint(Color.kepce)
        }
        .swipeActions(edge: .leading) {
            Button { hizli(oge, .ses) } label: { Label("Ses", systemImage: "music.note") }.tint(.indigo)
        }
        .contextMenu {
            Button { hizli(oge, .video) } label: { Label("Video indir", systemImage: "film") }
            Button { hizli(oge, .ses) } label: { Label("Yalnız ses indir", systemImage: "music.note") }
            if let adres = oge.adres {
                Button { UIPasteboard.general.string = adres } label: { Label("Bağlantıyı kopyala", systemImage: "doc.on.doc") }
                ShareLink(item: adres)
            }
        }
    }

    private func hizli(_ oge: ListeOgesi, _ tur: IndirmeTuru) {
        guard let adres = oge.adres else { return }
        IndirmeKuyrugu.shared.ekle(adres: adres, secim: .hizli(tur), baslik: oge.title, kapak: oge.thumbnail, sure: oge.duration)
        yonlendirici.bildirim = tur == .ses ? "Ses sıraya eklendi" : "Video sıraya eklendi"
    }

    private func ara() {
        let metin = sorgu.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !metin.isEmpty else { return }
        // Bağlantı yapıştırıldıysa doğrudan aç.
        if let adres = PaylasimKutusu.adresBul(metin) { yonlendirici.bilgi = BilgiIstegi(adres: adres); return }
        gecmis.removeAll { $0 == metin }
        gecmis.insert(metin, at: 0)
        gecmis = Array(gecmis.prefix(15))
        gecmisiKaydet()
        gorev?.cancel()
        araniyor = true
        hata = nil
        gorev = Task {
            do {
                let bilgi = try await PythonMotoru.shared.ara(metin)
                if Task.isCancelled { return }
                sonuclar = bilgi.entries ?? []
            } catch {
                if !Task.isCancelled { hata = error.localizedDescription }
            }
            araniyor = false
        }
    }

    private func gecmisiKaydet() { UserDefaults.standard.set(gecmis, forKey: "aramaGecmisi") }
}
