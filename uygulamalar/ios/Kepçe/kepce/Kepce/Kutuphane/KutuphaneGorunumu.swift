import SwiftUI

struct KutuphaneGorunumu: View {
    @Environment(Yonlendirici.self) private var yonlendirici
    private let kutuphane = Kutuphane.shared
    @State private var arama = ""
    @State private var suzgec = Suzgec.tumu
    @State private var siralama = Siralama.yeni
    @State private var adlandirilan: KutuphaneOgesi?
    @State private var yeniAd = ""
    @State private var sira: [KutuphaneOgesi]?
    @State private var ileti: String?
    @State private var secilenler: Set<UUID> = []
    @State private var duzen: EditMode = .inactive
    private var seciliOgeler: [KutuphaneOgesi] { gorunen.filter { secilenler.contains($0.id) } }

    enum Suzgec: String, CaseIterable, Identifiable { case tumu = "Tümü", video = "Video", ses = "Ses"; var id: Self { self } }
    enum Siralama: String, CaseIterable, Identifiable { case yeni = "En yeni", ad = "Ada göre", boyut = "Boyuta göre"; var id: Self { self } }

    private var gorunen: [KutuphaneOgesi] {
        var liste = kutuphane.ogeler.filter { oge in
            switch suzgec {
            case .tumu: true
            case .video: !oge.sesMi
            case .ses: oge.sesMi
            }
        }
        let metin = arama.trimmingCharacters(in: .whitespaces)
        if !metin.isEmpty {
            liste = liste.filter { $0.baslik.localizedStandardContains(metin) || ($0.yazar?.localizedStandardContains(metin) ?? false) }
        }
        switch siralama {
        case .yeni: liste.sort { $0.tarih > $1.tarih }
        case .ad: liste.sort { $0.baslik.localizedStandardCompare($1.baslik) == .orderedAscending }
        case .boyut: liste.sort { $0.boyut > $1.boyut }
        }
        return liste
    }

    var body: some View {
        NavigationStack {
            List(selection: $secilenler) {
                if kutuphane.ogeler.isEmpty {
                    ContentUnavailableView("Kütüphane boş", systemImage: "play.square.stack",
                                           description: Text("İndirdiğin videolar ve sesler burada toplanır. Dosyalar uygulamasında \"Kepçe\" klasöründe de görünürler."))
                } else {
                    Section {
                        Picker("Süzgeç", selection: $suzgec) { ForEach(Suzgec.allCases) { Text($0.rawValue).tag($0) } }
                            .pickerStyle(.segmented)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                    }
                    Section {
                        ForEach(gorunen) { oge in
                            KutuphaneSatiri(oge: oge, paylas: !duzen.isEditing)
                                .contentShape(.rect)
                                .tag(oge.id)
                                .onTapGesture { if !duzen.isEditing { yonlendirici.oynatilan = oge } }
                                .contextMenu { menu(oge) }
                                .swipeActions {
                                    Button(role: .destructive) { withAnimation { kutuphane.sil(oge) } } label: { Label("Sil", systemImage: "trash") }
                                    ShareLink(item: kutuphane.url(oge), preview: Paylasim.onizleme(oge)) { Label("Paylaş", systemImage: "square.and.arrow.up") }.tint(.blue)
                                }
                        }
                    } footer: {
                        Text("\(gorunen.count) öğe · \(BicimSecici.boyutMetni(gorunen.reduce(0) { $0 + $1.boyut }))")
                    }
                }
            }
            .navigationTitle(duzen.isEditing ? "\(secilenler.count) seçili" : "Kütüphane")
            .environment(\.editMode, $duzen)
            .safeAreaInset(edge: .bottom) {
                if duzen.isEditing {
                    HStack(spacing: 12) {
                        ShareLink(items: seciliOgeler.map { kutuphane.url($0) }) {
                            Label("Paylaş (\(secilenler.count))", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(secilenler.isEmpty)
                        Button(role: .destructive) {
                            withAnimation { seciliOgeler.forEach(kutuphane.sil); secilenler = [] }
                        } label: { Label("Sil", systemImage: "trash").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered)
                        .disabled(secilenler.isEmpty)
                    }
                    .controlSize(.large)
                    .padding()
                    .background(.bar)
                }
            }
            .searchable(text: $arama, prompt: "Kütüphanede ara")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !kutuphane.ogeler.isEmpty {
                        Button(duzen.isEditing ? "Bitti" : "Seç") {
                            withAnimation { duzen = duzen.isEditing ? .inactive : .active; secilenler = [] }
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sıralama", selection: $siralama) { ForEach(Siralama.allCases) { Text($0.rawValue).tag($0) } }
                        let sesler = gorunen.filter(\.sesMi)
                        if !sesler.isEmpty {
                            Button { sira = sesler } label: { Label("Sesleri sırayla çal", systemImage: "play.circle") }
                            Button { sira = sesler.shuffled() } label: { Label("Karışık çal", systemImage: "shuffle") }
                        }
                    } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
                }
            }
            .alert("Yeniden adlandır", isPresented: Binding(get: { adlandirilan != nil }, set: { if !$0 { adlandirilan = nil } })) {
                TextField("Ad", text: $yeniAd)
                Button("Vazgeç", role: .cancel) {}
                Button("Kaydet") { if let oge = adlandirilan, !yeniAd.isEmpty { kutuphane.yenidenAdlandir(oge, yeniAd) } }
            }
            .alert(ileti ?? "", isPresented: Binding(get: { ileti != nil }, set: { if !$0 { ileti = nil } })) { Button("Tamam") {} }
            .fullScreenCover(item: Binding(get: { sira.map { SiraKimligi(ogeler: $0) } }, set: { sira = $0?.ogeler })) { s in
                Oynatici(oge: s.ogeler[0], sira: s.ogeler)
            }
        }
    }

    @ViewBuilder private func menu(_ oge: KutuphaneOgesi) -> some View {
        Button { yonlendirici.oynatilan = oge } label: { Label("Oynat", systemImage: "play.fill") }
        PaylasMenusu(oge: oge)
        if !oge.sesMi && oge.tur != .ham {
            Button {
                Task {
                    do { try await Kutuphane.fotograflaraKaydet(kutuphane.url(oge)); ileti = "Fotoğraflar'a kaydedildi." }
                    catch { ileti = error.localizedDescription }
                }
            } label: { Label("Fotoğraflar'a kaydet", systemImage: "photo.on.rectangle") }
        }
        Button { yeniAd = oge.baslik; adlandirilan = oge } label: { Label("Yeniden adlandır", systemImage: "pencil") }
        if let kaynak = URL(string: oge.kaynak), !oge.kaynak.isEmpty {
            Link(destination: kaynak) { Label("Kaynağı aç", systemImage: "safari") }
            Button { yonlendirici.bilgi = BilgiIstegi(adres: oge.kaynak, baslik: oge.baslik) } label: { Label("Başka biçimde indir", systemImage: "arrow.down.circle") }
        }
        Button(role: .destructive) { withAnimation { kutuphane.sil(oge) } } label: { Label("Sil", systemImage: "trash") }
    }
}

private struct SiraKimligi: Identifiable {
    let id = UUID()
    let ogeler: [KutuphaneOgesi]
}

struct KutuphaneSatiri: View {
    let oge: KutuphaneOgesi
    var paylas = true
    private let kutuphane = Kutuphane.shared

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .bottomLeading) {
                KucukResim(yerel: kutuphane.kapakURL(oge), sure: oge.sure, genislik: oge.sesMi ? 64 : 112)
                    .frame(width: 112, alignment: .leading)
                if let konum = oge.konum, let sure = oge.sure, sure > 0, konum > 5 {
                    ProgressView(value: min(1, konum / sure)).tint(Color.kepce).frame(width: oge.sesMi ? 64 : 112).scaleEffect(y: 0.6, anchor: .bottom)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(oge.baslik).font(.subheadline.weight(.medium)).lineLimit(2)
                if let yazar = oge.yazar { Text(yazar).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                HStack(spacing: 4) {
                    Image(systemName: oge.sesMi ? "music.note" : (oge.tur == .ham ? "doc" : "film"))
                    Text("\(oge.etiket) · \(BicimSecici.boyutMetni(oge.boyut))")
                    if !oge.altyazilar.isEmpty { Image(systemName: "captions.bubble") }
                }
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if paylas { PaylasDugmesi(oge: oge).foregroundStyle(Color.kepce) }
        }
    }
}
