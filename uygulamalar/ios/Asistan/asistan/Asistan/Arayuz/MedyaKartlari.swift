import SwiftUI
import AVKit

/// Web'den kazınan tek medya öğesi (görsel, video, YouTube, ses, belge/kitap).
nonisolated struct MedyaOgesi: Identifiable, Equatable, Hashable, Sendable {
    enum Tur: String, Sendable, CaseIterable { case gorsel, video, youtube, ses, belge }
    var id: String { url.absoluteString }
    let tur: Tur
    let url: URL
    let ad: String

    /// YouTube video kimliği (küçük resim ve gömülü oynatma için).
    var youtubeKimligi: String? {
        guard tur == .youtube else { return nil }
        if url.host?.contains("youtu.be") == true { return url.pathComponents.dropFirst().first }
        if let v = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "v" })?.value { return v }
        if let i = url.pathComponents.firstIndex(where: { $0 == "embed" || $0 == "shorts" }), i + 1 < url.pathComponents.count { return url.pathComponents[i + 1] }
        return nil
    }

    /// Kartta kendiliğinden yüklenebilir mi: yalnız herkese açık https (yerel/özel ağ adresleri kazınmış olsa da çekilmez).
    var guvenli: Bool { WebSayfa.urlGuvenli(url) }
}

/// Medya kartı: türlere göre bölümler; her öğe önizlenir, oynatılır ya da indirilir.
struct MedyaKarti: View {
    let ogeler: [MedyaOgesi]
    @State private var galeri: GaleriAcilis?
    @State private var video: MedyaOgesi?
    @State private var safari: SafariHedefi?
    @State private var cal = SesCalar.ortak

    private func grup(_ t: MedyaOgesi.Tur...) -> [MedyaOgesi] { ogeler.filter { t.contains($0.tur) && $0.guvenli } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            let gorseller = grup(.gorsel)
            if !gorseller.isEmpty {
                Bolum(baslik: "Görseller", sayi: gorseller.count, simge: "photo.on.rectangle", indirilecek: gorseller)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 8) {
                        ForEach(Array(gorseller.prefix(40).enumerated()), id: \.element.id) { i, g in
                            Button { galeri = GaleriAcilis(ogeler: gorseller, baslangic: i) } label: {
                                AsyncImage(url: g.url) { faz in
                                    switch faz {
                                    case .success(let r): r.resizable().scaledToFill()
                                    case .failure: Color.secondary.opacity(0.15).overlay(Image(systemName: "photo.badge.exclamationmark").foregroundStyle(.secondary))
                                    default: Color.secondary.opacity(0.15).overlay(ProgressView())
                                    }
                                }
                                    .frame(width: 92, height: 92).clipShape(.rect(cornerRadius: 10))
                            }
                            .buttonStyle(.plain).accessibilityLabel("Görsel: \(g.ad)").accessibilityIdentifier("medya-gorsel")
                        }
                    }
                }
                .frame(height: 92)
            }
            let videolar = grup(.video, .youtube)
            if !videolar.isEmpty {
                Bolum(baslik: "Videolar", sayi: videolar.count, simge: "film", indirilecek: videolar.filter { IndirmeYoneticisi.dogrudanMedya($0.url) })
                ForEach(videolar.prefix(15)) { v in
                    MedyaSatiri(oge: v, onizle: { if v.tur == .youtube { safari = SafariHedefi(url: v.url) } else { video = v } })
                }
            }
            let sesler = grup(.ses)
            if !sesler.isEmpty {
                Bolum(baslik: "Sesler", sayi: sesler.count, simge: "waveform", indirilecek: sesler)
                ForEach(sesler.prefix(15)) { s in MedyaSatiri(oge: s, onizle: { cal.degistir(s.url) }) }
            }
            let belgeler = grup(.belge)
            if !belgeler.isEmpty {
                Bolum(baslik: "Belgeler ve kitaplar", sayi: belgeler.count, simge: "books.vertical", indirilecek: belgeler)
                ForEach(belgeler.prefix(25)) { b in BelgeSatiri(oge: b) }
            }
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground).opacity(0.85), in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        .accessibilityElement(children: .contain).accessibilityIdentifier("medya-karti")
        .fullScreenCover(item: $galeri) { GorselGalerisi(acilis: $0) }
        .sheet(item: $video) { v in VideoOynatici(url: v.url, ad: v.ad) }
        .sheet(item: $safari) { SafariSayfasi(url: $0.url).ignoresSafeArea() }
        .onReceive(NotificationCenter.default.publisher(for: .asistanSunumlariKapat)) { _ in galeri = nil; video = nil; safari = nil }
    }
}

private struct Bolum: View {
    let baslik: String; let sayi: Int; let simge: String
    /// Doğrudan indirilebilir öğeler ("Tümünü indir"); YouTube gibi sayfa videoları hariç.
    var indirilecek: [MedyaOgesi] = []
    @State private var bilgi: String?
    var body: some View {
        HStack {
            Label("\(baslik) (\(sayi))", systemImage: simge).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            Spacer()
            if let bilgi { Text(bilgi).font(.caption2).foregroundStyle(.secondary) }
            else if indirilecek.count > 1 {
                Button("Tümünü indir", systemImage: "arrow.down.circle") { Task { await hepsiniIndir() } }
                    .font(.caption.weight(.medium)).buttonStyle(.plain).accessibilityIdentifier("tumunu-indir")
            }
        }
    }
    private func hepsiniIndir() async {
        var n = 0
        for o in indirilecek.prefix(IndirmeYoneticisi.enFazlaEtkin) { if (try? await IndirmeYoneticisi.ortak.ekle(o.url.absoluteString, tur: "file")) != nil { n += 1 } }
        bilgi = n == indirilecek.count ? "\(n) indirme başladı; bitenler sohbete gelecek" : "\(n)/\(indirilecek.count) başladı (sınır \(IndirmeYoneticisi.enFazlaEtkin))"
    }
}

/// Video/ses satırı: önizle/oynat + indir; indirme başlayınca canlı kart.
private struct MedyaSatiri: View {
    let oge: MedyaOgesi
    let onizle: () -> Void
    @State private var indirme: UUID?
    @State private var bilgi: String?
    @State private var cal = SesCalar.ortak

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button(action: onizle) {
                    ZStack {
                        if let k = oge.youtubeKimligi, let u = URL(string: "https://img.youtube.com/vi/\(k)/mqdefault.jpg") {
                            AsyncImage(url: u) { $0.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.15) }
                        } else { Color.secondary.opacity(0.12) }
                        Image(systemName: oynuyor ? "pause.fill" : "play.fill").foregroundStyle(.white).padding(8).background(.black.opacity(0.5), in: Circle())
                    }
                    .frame(width: oge.tur == .ses ? 44 : 72, height: 44).clipShape(.rect(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(oge.tur == .ses ? (oynuyor ? "Duraklat" : "Dinle") : "Oynat").accessibilityIdentifier("medya-oynat")
                VStack(alignment: .leading, spacing: 1) {
                    Text(oge.ad).font(.callout).lineLimit(2)
                    Text(oge.url.host?.replacingOccurrences(of: "www.", with: "") ?? "").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Button { Task { await indir() } } label: { Image(systemName: "arrow.down.circle").font(.title3).frame(width: 40, height: 40) }
                    .buttonStyle(.plain).disabled(indirme != nil).accessibilityLabel("İndir").accessibilityIdentifier("medya-indir")
            }
            if let indirme { IndirmeKarti(id: indirme) }
            if let bilgi { Text(bilgi).font(.caption).foregroundStyle(.secondary) }
        }
    }

    private var oynuyor: Bool { oge.tur == .ses && cal.calan == oge.url && cal.oynuyor }

    private func indir() async {
        let k = IndirmeYoneticisi.ortak
        if oge.tur == .youtube || (oge.tur == .video && !IndirmeYoneticisi.dogrudanMedya(oge.url) && oge.url.pathExtension.lowercased() != "m3u8") {
            // Gömülü Kepçe motoru uygulama içinde indirir; Kepçe devri/medya bulucu yalnız İndirmeler ekranındaki yedek.
            do { indirme = try k.motorluEkle(oge.url.absoluteString, tur: "video") } catch { bilgi = error.localizedDescription }
            return
        }
        do { indirme = try await k.ekle(oge.url.absoluteString, tur: "file") } catch { bilgi = error.localizedDescription }
    }
}

/// Belge/kitap satırı: önizle (geçici indirip Hızlı Bakış) ya da kalıcı indir.
private struct BelgeSatiri: View {
    let oge: MedyaOgesi
    @State private var onizleme: URL?
    @State private var hazirlaniyor = false
    @State private var indirme: UUID?
    @State private var hata: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: DosyaSimgesi.ad(oge.url.pathExtension)).font(.title3).frame(width: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(oge.ad).font(.callout).lineLimit(2)
                    Text("\(oge.url.pathExtension.uppercased()) · \(oge.url.host?.replacingOccurrences(of: "www.", with: "") ?? "")").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if hazirlaniyor { ProgressView().frame(width: 40, height: 40) } else {
                    Button { Task { await onizle() } } label: { Image(systemName: "eye").frame(width: 40, height: 40) }
                        .buttonStyle(.plain).accessibilityLabel("Önizle").accessibilityIdentifier("belge-onizle")
                }
                Button { Task { do { indirme = try await IndirmeYoneticisi.ortak.ekle(oge.url.absoluteString, tur: "file") } catch { hata = error.localizedDescription } } } label: {
                    Image(systemName: "arrow.down.circle").font(.title3).frame(width: 40, height: 40)
                }
                .buttonStyle(.plain).disabled(indirme != nil).accessibilityLabel("İndir")
            }
            if let indirme { IndirmeKarti(id: indirme) }
            if let hata { Text(hata).font(.caption).foregroundStyle(.orange) }
        }
        .quickLookPreview($onizleme)
        .onReceive(NotificationCenter.default.publisher(for: .asistanSunumlariKapat)) { _ in onizleme = nil }
    }

    private func onizle() async {
        hazirlaniyor = true; hata = nil
        defer { hazirlaniyor = false }
        do { onizleme = try await UzakOnizleme.indir(oge.url) } catch { hata = "Önizlenemedi: \(error.localizedDescription)" }
    }
}

/// Uzak dosyayı geçici klasöre indirir (önizleme için; en çok 60 MB).
nonisolated enum UzakOnizleme {
    /// @concurrent: ad çözümlemesi (getaddrinfo) eşzamanlıdır, ana iş parçacığında koşmasın.
    @concurrent static func indir(_ url: URL) async throws -> URL {
        guard url.scheme == "https", WebSayfa.urlGuvenli(url), !WebSayfa.ozeleCozuluyor(url.host ?? "") else { throw IndirmeHatasi.metin("Yalnız herkese açık https adresleri önizlenir.") }
        // Yönlendirme, istek gönderilmeden temsilcide denetlenir (özel adrese hiç gidilmez).
        let oturum = URLSession(configuration: .ephemeral, delegate: WebSayfa.Yonlendirme(), delegateQueue: nil)
        defer { oturum.finishTasksAndInvalidate() }
        let (gecici, yanit) = try await oturum.download(from: url)
        guard let h = yanit as? HTTPURLResponse, (200..<300).contains(h.statusCode) else { throw IndirmeHatasi.metin("Sunucu dosyayı vermedi.") }
        guard let son = h.url, son.scheme == "https", WebSayfa.urlGuvenli(son) else { throw IndirmeHatasi.metin("Güvensiz yönlendirme.") }
        let boyut = (try? gecici.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard boyut <= 60_000_000 else { throw IndirmeHatasi.metin("Dosya önizleme için çok büyük; İndir'i kullan.") }
        let ad = IndirmeYoneticisi.dosyaAdi(h.suggestedFilename ?? url.lastPathComponent)
        let hedef = FileManager.default.temporaryDirectory.appending(path: "onizleme-\(UUID().uuidString.prefix(8))-\(ad)")
        try? FileManager.default.removeItem(at: hedef)
        try FileManager.default.moveItem(at: gecici, to: hedef)
        return hedef
    }
}

/// Satır içi ses çalar (tek seferde bir ses).
@MainActor @Observable
final class SesCalar {
    static let ortak = SesCalar()
    private var oynatici: AVPlayer?
    private(set) var calan: URL?
    private(set) var oynuyor = false
    /// Açık video oynatıcı sayısı (VideoOynatici sayfası). Video açıkken ses oturumu bırakılmaz: setActive(false) videoyu da keser.
    private(set) var acikVideo = 0
    /// Ses kartı ya da açık bir video uygulamanın kendi medyasını çalıyor mu (SesOturumu.oturumBirakilir girdisi).
    var medyaCaliyor: Bool { Self.medyaCaliyor(oynuyor: oynuyor, acikVideo: acikVideo) }
    nonisolated static func medyaCaliyor(oynuyor: Bool, acikVideo: Int) -> Bool { oynuyor || acikVideo > 0 }
    /// Medya durunca (duraklatma, bitiş, son videonun kapanması) çağrılır; SesOturumu oturum bırakma kararını yeniden verir
    /// (video kapanınca kısılan müzik geri gelsin). Ana aktörde çağrılır.
    @ObservationIgnored var bitti: (() -> Void)?
    private var bitisGozlemcisi: (any NSObjectProtocol)?
    func videoAcildi() {
        acikVideo += 1
        SesOturumuKapisi.istek.artir()   // yolda bir oturum bırakma videoyu durdurmasın
    }
    func videoKapandi() {
        acikVideo = max(0, acikVideo - 1)
        bittiyseBildir()
    }
    private func bittiyseBildir() { if !medyaCaliyor { bitti?() } }
    func degistir(_ url: URL) {
        if calan == url, let o = oynatici {
            if oynuyor { o.pause() } else { SesOturumuKapisi.istek.artir(); o.play() }   // yolda bir oturum bırakma çaları durdurmasın
            oynuyor.toggle()
            if !oynuyor { bittiyseBildir() }
            return
        }
        oynatici?.pause()
        let o = AVPlayer(url: url); oynatici = o; calan = url
        // Bitişte simge "Dinle"ye döner; oynatıcı bırakılır, yeniden dokununca yeni oynatıcıyla baştan çalar.
        if let g = bitisGozlemcisi { NotificationCenter.default.removeObserver(g) }
        let kimlik = ObjectIdentifier(o)
        bitisGozlemcisi = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: o.currentItem, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let o = self.oynatici, ObjectIdentifier(o) == kimlik else { return }
                o.pause()
                self.oynatici = nil
                self.oynuyor = false
                self.bittiyseBildir()
            }
        }
        SesOturumuKapisi.istek.artir()   // yolda bir oturum bırakma çaları durdurmasın
        o.play(); oynuyor = true
    }
}

struct VideoOynatici: View {
    let url: URL
    let ad: String
    @Environment(\.dismiss) private var kapat
    @State private var oynatici: AVPlayer?
    var body: some View {
        NavigationStack {
            Group { if let oynatici { VideoPlayer(player: oynatici) } else { ProgressView() } }
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(ad).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Kapat") { oynatici?.pause(); kapat() } } }
        }
        // Sayaç açılış/kapanışla eşlenir; Kapat düğmesi de kapat() üzerinden onDisappear'a düşer (sayaç sıfırın altına inmez).
        .onAppear { SesCalar.ortak.videoAcildi(); let o = AVPlayer(url: url); oynatici = o; o.play() }
        .onDisappear { oynatici?.pause(); SesCalar.ortak.videoKapandi() }
    }
}

struct GaleriAcilis: Identifiable { let id = UUID(); let ogeler: [MedyaOgesi]; let baslangic: Int }

/// Tam ekran görsel galerisi: kaydırarak gez, paylaş ya da indir.
struct GorselGalerisi: View {
    let acilis: GaleriAcilis
    @Environment(\.dismiss) private var kapat
    @State private var secili = 0
    @State private var bilgi: String?
    var body: some View {
        NavigationStack {
            TabView(selection: $secili) {
                ForEach(Array(acilis.ogeler.enumerated()), id: \.element.id) { i, g in
                    AsyncImage(url: g.url) { faz in
                        switch faz {
                        case .success(let r): r.resizable().scaledToFit()
                        case .failure:
                            VStack(spacing: 8) {
                                Image(systemName: "photo.badge.exclamationmark").font(.largeTitle)
                                Text("Görsel yüklenemedi").font(.callout)
                            }
                            .foregroundStyle(.white.opacity(0.8))
                        default: ProgressView().tint(.white)
                        }
                    }.tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .background(Color.black)
            .navigationTitle("\(secili + 1) / \(acilis.ogeler.count)").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Kapat") { kapat() } }
                ToolbarItemGroup(placement: .primaryAction) {
                    if secili < acilis.ogeler.count {
                        ShareLink(item: acilis.ogeler[secili].url) { Image(systemName: "square.and.arrow.up") }
                        Button { Task { do { _ = try await IndirmeYoneticisi.ortak.ekle(acilis.ogeler[secili].url.absoluteString, tur: "file"); bilgi = "İndirmelere eklendi" } catch { bilgi = error.localizedDescription } } } label: { Image(systemName: "arrow.down.circle") }
                            .accessibilityLabel("Görseli indir")
                    }
                }
            }
            .overlay(alignment: .bottom) { if let bilgi { Text(bilgi).font(.caption).padding(8).background(.thinMaterial, in: Capsule()).padding(.bottom, 40) } }
            .onAppear { secili = acilis.baslangic }
        }
    }
}
