import SwiftUI
import UniformTypeIdentifiers

struct IndirGorunumu: View {
    @Environment(Yonlendirici.self) private var yonlendirici
    @Environment(\.scenePhase) private var evre
    private let kuyruk = IndirmeKuyrugu.shared
    private let kutuphane = Kutuphane.shared
    @State private var adres = ""
    @State private var panodaBaglanti = false
    @State private var sonPanoSayaci = -1
    @FocusState private var odak: Bool
    @State private var topluAcik = false
    @State private var suzgec = Suzgec.tumu

    enum Suzgec: String, CaseIterable, Identifiable { case tumu = "Tümü", etkin = "Sürenler", biten = "Biten", hatali = "Hatalı"; var id: Self { self } }

    /// Sürenler, sıradakiler (sırasıyla), duraklatılanlar, hatalılar, bitenler (yeniden eskiye).
    private var siraliIsler: [IndirmeIsi] {
        let liste = kuyruk.isler
        let siralanmis = liste.filter { $0.durum.etkin } + liste.filter { $0.durum == .bekliyor } + liste.filter { $0.durum == .duraklatildi }
            + liste.filter { $0.durum == .hata } + liste.filter { $0.durum == .tamam }.reversed()
        switch suzgec {
        case .tumu: return siralanmis
        case .etkin: return siralanmis.filter { $0.durum.etkin || $0.durum == .bekliyor || $0.durum == .duraklatildi }
        case .biten: return siralanmis.filter { $0.durum == .tamam }
        case .hatali: return siralanmis.filter { $0.durum == .hata }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    baglantiAlani
                } footer: {
                    Text("YouTube ve yt-dlp'nin desteklediği 1000'den fazla siteden bağlantı yapıştır. Uygulamalarda **Paylaş → Kepçe** ile de ekleyebilirsin.")
                }

                if panodaBaglanti && adres.isEmpty {
                    Section { panoKarti }
                }

                if kuyruk.isler.isEmpty {
                    Section {
                        ContentUnavailableView("Sıra boş", systemImage: "tray",
                                               description: Text("İndirdiklerin burada ilerler, bitince Kütüphane'ye geçer."))
                    }
                } else {
                    if let bitis = kuyruk.beklemeBitis, bitis > Date() { Section { beklemeKarti(bitis) } }
                    Section { ozet }
                    if kuyruk.isler.count > 8 {
                        Section {
                            Picker("Süzgeç", selection: $suzgec) { ForEach(Suzgec.allCases) { Text($0.rawValue).tag($0) } }
                                .pickerStyle(.segmented)
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets())
                        }
                    }
                    Section {
                        ForEach(siraliIsler) { is_ in
                            IsSatiri(is_: is_)
                                .swipeActions {
                                    Button(role: .destructive) { kuyruk.kaldir(is_.id) } label: { Label("Kaldır", systemImage: "trash") }
                                }
                                .contextMenu { menu(is_) }
                        }
                    } header: {
                        HStack {
                            Text("Sıra")
                            Spacer()
                            Menu {
                                Button { kuyruk.hepsiniDuraklat() } label: { Label("Tümünü duraklat", systemImage: "pause.fill") }
                                Button { kuyruk.hepsiniSurdur() } label: { Label("Tümünü sürdür", systemImage: "play.fill") }
                                Button { kuyruk.hatalilariYenidenDene() } label: { Label("Hatalıları yeniden dene", systemImage: "arrow.clockwise") }
                                Divider()
                                Button { withAnimation { kuyruk.bitenleriTemizle() } } label: { Label("Bitenleri temizle", systemImage: "checkmark.circle") }
                                Button(role: .destructive) { withAnimation { kuyruk.bekleyenleriKaldir() } } label: {
                                    Label("Bekleyen ve hatalıları kaldır", systemImage: "trash")
                                }
                            } label: { Label("İşlemler", systemImage: "ellipsis.circle").labelStyle(.titleAndIcon) }
                            .font(.caption).textCase(nil)
                        }
                    }
                }
            }
            .navigationTitle("Kepçe")
            .sheet(isPresented: $topluAcik) { TopluEkleSayfasi() }
            .animation(.default, value: kuyruk.isler.map(\.durum))
            .onChange(of: evre, initial: true) { _, yeni in if yeni == .active { panoyuDenetle() } }
        }
    }

    private var baglantiAlani: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "link").foregroundStyle(.secondary)
                TextField("https://youtube.com/watch?v=…", text: $adres)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($odak)
                    .submitLabel(.go)
                    .onSubmit(getir)
                if !adres.isEmpty {
                    Button { adres = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain)
                } else {
                    PasteButton(payloadType: String.self) { metinler in
                        if let ilk = metinler.first { adres = PaylasimKutusu.adresBul(ilk) ?? ilk }
                    }
                    .labelStyle(.iconOnly)
                    .buttonBorderShape(.capsule)
                }
            }
            HStack(spacing: 8) {
                Button(action: getir) {
                    Label("Seçerek indir", systemImage: "slider.horizontal.3").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Menu {
                    Button { hizli(.video) } label: { Label("Video (\(Ayarlar.cozunurlukAdi(Ayarlar.shared.enFazlaCozunurluk)))", systemImage: "film") }
                    Button { hizli(.ses) } label: { Label("Yalnız ses (M4A)", systemImage: "music.note") }
                    Button { hizli(.ham) } label: { Label("Özgün dosya", systemImage: "doc") }
                } label: {
                    Label("Hızlı", systemImage: "bolt.fill").frame(maxWidth: .infinity)
                } primaryAction: {
                    hizli(Ayarlar.shared.hizliTur)
                }
                .buttonStyle(.bordered)
            }
            .disabled(gecerliAdres == nil)
            .controlSize(.large)
            Button { topluAcik = true } label: {
                Label("Toplu indir · liste · kanal", systemImage: "square.stack.3d.down.right").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var ozet: some View {
        let isler = kuyruk.isler
        let suren = isler.filter { $0.durum.etkin }.count, sirada = isler.filter { $0.durum == .bekliyor }.count
        let biten = isler.filter { $0.durum == .tamam }.count, hatali = isler.filter { $0.durum == .hata }.count
        let hiz = isler.reduce(0.0) { $0 + $1.hiz }
        return HStack(spacing: 14) {
            sayi(suren, "sürüyor", .blue)
            sayi(sirada, "sırada", .secondary)
            sayi(biten, "bitti", .green)
            if hatali > 0 { sayi(hatali, "hatalı", .red) }
            Spacer()
            if hiz > 0 { Text("\(BicimSecici.boyutMetni(Int64(hiz)))/sn").font(.subheadline.monospacedDigit().weight(.semibold)) }
        }
    }

    private func sayi(_ n: Int, _ ad: String, _ renk: Color) -> some View {
        VStack(spacing: 0) {
            Text("\(n)").font(.headline.monospacedDigit()).foregroundStyle(renk)
            Text(ad).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func beklemeKarti(_ bitis: Date) -> some View {
        HStack {
            Image(systemName: "tortoise.fill").foregroundStyle(.orange)
            VStack(alignment: .leading) {
                Text("YouTube hız sınırı koydu").font(.subheadline.weight(.semibold))
                Text("Sıra \(bitis, style: .timer) sonra kendiliğinden sürecek.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Şimdi dene") { kuyruk.beklemeyiBitir() }.font(.caption).buttonStyle(.bordered)
        }
    }

    private var panoKarti: some View {
        HStack {
            Image(systemName: "doc.on.clipboard").font(.title3).foregroundStyle(Color.kepce)
            VStack(alignment: .leading) {
                Text("Panoda bir bağlantı var").font(.subheadline.weight(.semibold))
                Text("Yapıştırıp bilgisini getir").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            PasteButton(payloadType: String.self) { metinler in
                guard let ilk = metinler.first else { return }
                adres = PaylasimKutusu.adresBul(ilk) ?? ilk
                sonPanoSayaci = UIPasteboard.general.changeCount
                panodaBaglanti = false
                getir()
            }
            .buttonBorderShape(.capsule)
            .labelStyle(.iconOnly)
        }
    }

    private var gecerliAdres: String? {
        let temiz = adres.trimmingCharacters(in: .whitespacesAndNewlines)
        if let bulunan = PaylasimKutusu.adresBul(temiz) { return bulunan }
        // "youtu.be/…" gibi şemasız yazımlar
        if !temiz.isEmpty, !temiz.contains(" "), temiz.contains("."), let url = URL(string: "https://\(temiz)"), url.host() != nil { return url.absoluteString }
        return nil
    }

    private func getir() {
        guard let adres = gecerliAdres else { return }
        odak = false
        yonlendirici.bilgi = BilgiIstegi(adres: adres)
    }

    private func hizli(_ tur: IndirmeTuru) {
        guard let adres = gecerliAdres else { return }
        odak = false
        yonlendirici.hizliIndir(adres, tur: tur)
        self.adres = ""
    }

    /// İzin penceresi açmadan panoda web adresi olup olmadığını yoklar.
    private func panoyuDenetle() {
        guard Ayarlar.shared.panoyuIzle else { panodaBaglanti = false; return }
        let pano = UIPasteboard.general
        guard pano.changeCount != sonPanoSayaci else { return }
        Task { panodaBaglanti = await Self.panodaAdresVar() }
    }

    /// UIKit sonucu arka plan kuyruğunda verir: geri çağrı ana aktöre bağlı olmamalı (yoksa Swift 6 çalışma zamanında çöker).
    nonisolated private static func panodaAdresVar() async -> Bool {
        await withCheckedContinuation { devam in
            UIPasteboard.general.detectPatterns(for: [.probableWebURL]) { @Sendable sonuc in
                devam.resume(returning: (try? sonuc.get())?.contains(.probableWebURL) ?? false)
            }
        }
    }

    @ViewBuilder private func menu(_ is_: IndirmeIsi) -> some View {
        if is_.durum == .tamam, let id = is_.kutuphaneID, let oge = kutuphane.ogeler.first(where: { $0.id == id }) {
            Button { yonlendirici.oynatilan = oge } label: { Label("Oynat", systemImage: "play.fill") }
            PaylasMenusu(oge: oge)
        }
        if is_.durum.etkin || is_.durum == .bekliyor {
            Button { kuyruk.duraklat(is_.id) } label: { Label("Duraklat", systemImage: "pause.fill") }
        }
        if is_.durum == .duraklatildi { Button { kuyruk.surdur(is_.id) } label: { Label("Sürdür", systemImage: "play.fill") } }
        if is_.durum == .bekliyor { Button { kuyruk.oneAl(is_.id) } label: { Label("Öne al", systemImage: "arrow.up.to.line") } }
        if is_.durum == .hata { Button { kuyruk.yenidenDene(is_.id) } label: { Label("Yeniden dene", systemImage: "arrow.clockwise") } }
        Button { yonlendirici.bilgi = BilgiIstegi(adres: is_.adres, baslik: is_.baslik, kapak: is_.kapak) } label: {
            Label("Başka biçimde indir", systemImage: "slider.horizontal.3")
        }
        Button { UIPasteboard.general.string = is_.adres } label: { Label("Bağlantıyı kopyala", systemImage: "doc.on.doc") }
        Button(role: .destructive) { kuyruk.kaldir(is_.id) } label: { Label("Kaldır", systemImage: "trash") }
    }
}

struct IsSatiri: View {
    var is_: IndirmeIsi
    @Environment(Yonlendirici.self) private var yonlendirici
    private let kuyruk = IndirmeKuyrugu.shared

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            KucukResim(adres: is_.kapak, sure: is_.sure, genislik: 100)
            VStack(alignment: .leading, spacing: 4) {
                Text(is_.baslik).font(.subheadline.weight(.medium)).lineLimit(2)
                HStack(spacing: 4) {
                    Image(systemName: simge).foregroundStyle(renk)
                    Text(durumMetni).foregroundStyle(is_.durum == .hata ? .red : .secondary)
                }
                .font(.caption)
                .lineLimit(is_.durum == .hata ? 4 : 1)
                if is_.durum == .tamam || is_.durum == .bekliyor, let not = is_.hata {
                    Text(not).font(.caption2).foregroundStyle(.orange).lineLimit(2)
                }
                if is_.durum == .indiriliyor || is_.durum == .duraklatildi {
                    ProgressView(value: is_.ilerleme).tint(is_.durum == .duraklatildi ? .secondary : Color.kepce)
                    Text(ayrinti).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                } else if is_.durum == .hazirlaniyor || is_.durum == .isleniyor {
                    ProgressView().progressViewStyle(.linear)
                }
            }
            Spacer(minLength: 0)
            dugme
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var dugme: some View {
        switch is_.durum {
        case .indiriliyor, .hazirlaniyor, .bekliyor:
            Button { kuyruk.duraklat(is_.id) } label: { Image(systemName: "pause.circle.fill").font(.title2) }.buttonStyle(.plain).foregroundStyle(.secondary)
        case .duraklatildi:
            Button { kuyruk.surdur(is_.id) } label: { Image(systemName: "play.circle.fill").font(.title2) }.buttonStyle(.plain).foregroundStyle(Color.kepce)
        case .hata:
            Button { kuyruk.yenidenDene(is_.id) } label: { Image(systemName: "arrow.clockwise.circle.fill").font(.title2) }.buttonStyle(.plain).foregroundStyle(Color.kepce)
        case .tamam:
            if let id = is_.kutuphaneID, let oge = Kutuphane.shared.ogeler.first(where: { $0.id == id }) {
                VStack(spacing: 6) {
                    Button { yonlendirici.oynatilan = oge } label: { Image(systemName: "play.circle.fill").font(.title2) }.buttonStyle(.plain).foregroundStyle(.green)
                    PaylasDugmesi(oge: oge).foregroundStyle(Color.kepce)
                }
            }
        case .isleniyor:
            EmptyView()
        }
    }

    private var simge: String {
        switch is_.durum {
        case .bekliyor: "clock"
        case .hazirlaniyor: "magnifyingglass"
        case .indiriliyor: "arrow.down"
        case .isleniyor: "gearshape"
        case .tamam: "checkmark.circle.fill"
        case .hata: "exclamationmark.triangle.fill"
        case .duraklatildi: "pause"
        }
    }

    private var renk: Color {
        switch is_.durum {
        case .tamam: .green
        case .hata: .red
        default: .secondary
        }
    }

    private var durumMetni: String {
        if is_.durum == .hata { return is_.hata ?? "Hata" }
        if let etiket = is_.etiket, is_.durum != .hazirlaniyor { return "\(is_.durum.ad) · \(etiket)" }
        return "\(is_.durum.ad) · \(is_.secim.tur.ad)"
    }

    private var ayrinti: String {
        var parcalar = ["\(BicimSecici.boyutMetni(is_.alinan)) / \(BicimSecici.boyutMetni(is_.toplam))"]
        if is_.durum == .indiriliyor {
            if is_.hiz > 0 { parcalar.append("\(BicimSecici.boyutMetni(Int64(is_.hiz)))/sn") }
            if let kalan = is_.kalanSure { parcalar.append("\(BicimSecici.sureMetni(kalan)) kaldı") }
        }
        return parcalar.joined(separator: " · ")
    }
}
