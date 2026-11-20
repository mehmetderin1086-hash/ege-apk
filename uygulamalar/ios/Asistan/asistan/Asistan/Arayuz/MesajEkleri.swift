import SwiftUI
import LinkPresentation
import SafariServices
import QuickLook
import Synchronization

/// Yanıta iliştirilen önizlenebilir sonuçlar: indirilen dosya, canlı indirme, kazınan tablo, web kaynakları.
/// Araçlar istek sırasında `EkDefteri`ne ekler; yanıt bitince ekler o yanıt balonuna bağlanır.
nonisolated struct MesajEki: Identifiable, Equatable, Sendable {
    enum Tur: Equatable, Sendable {
        /// Yerel dosya (Indirmeler klasöründe ad ya da tam yol).
        case dosya(url: URL, ad: String)
        /// İndirme yöneticisindeki kayıt: ilerleme canlı izlenir, bitince dosya önizlemesine döner.
        case indirme(UUID)
        /// Kazınan tablo (önizleme + dışa aktarma); `dosya` kaydedilmiş CSV/XLSX.
        case tablo(baslik: String, sutunlar: [String], satirlar: [[String]], kaynak: String?, dosya: URL?)
        /// Web kaynakları (istendiğinde önizlenir).
        case kaynaklar([String])
        /// Kazınan medya: görsel, video, YouTube, ses, belge/kitap (önizle, oynat, indir).
        case medya([MedyaOgesi])
        /// Telefonda yapılan iş (takvim/hatırlatıcı/alarm: Aç + 10 dk Geri al; arama/SMS/harita: yalnız Aç).
        case eylem(EylemKaydi)
        /// Hava durumu kartı (HavaAraci; saatlik sıcaklık/yağış/rüzgâr sekmeli).
        case hava(HavaOzeti)
        /// İzin reddi kartı (P1.10): "İzin ver" / "Ayarlar'ı aç" (`IzinEkKarti`, `Arayuz/IzinlerEkrani.swift`).
        case izin(IzinTuru)
    }
    var id = UUID()
    let tur: Tur
}

/// İstek süresince araçların ürettiği ekler (yalnız etkin istek; yanıt bitince boşaltılır).
@MainActor @Observable
final class EkDefteri {
    static let ortak = EkDefteri()
    private(set) var bekleyen: [MesajEki] = []
    static let enFazla = 40

    func ekle(_ e: MesajEki) {
        if case .kaynaklar(let yeni) = e.tur, let i = bekleyen.firstIndex(where: { if case .kaynaklar = $0.tur { true } else { false } }),
           case .kaynaklar(let eski) = bekleyen[i].tur {
            // Tek kaynak kartında birleştir (aynı adres bir kez).
            var gorulen = Set<String>()
            bekleyen[i] = MesajEki(tur: .kaynaklar((eski + yeni).filter { gorulen.insert($0).inserted }.prefix(12).map { $0 }))
            return
        }
        // Aynı turda aynı izin iki kez reddedilirse tek kart kalır.
        if case .izin = e.tur, bekleyen.contains(where: { $0.tur == e.tur }) { return }
        guard bekleyen.count < Self.enFazla else { return }
        bekleyen.append(e)
    }
    func al() -> [MesajEki] { defer { bekleyen = [] }; return bekleyen }
    func temizle() { bekleyen = [] }

    /// Araç metin çıktısındaki "Kaynaklar:" bölümünden adresleri ayıklar.
    nonisolated static func kaynaklar(_ metin: String) -> [String] {
        // Sondan aranır: sayfa metnindeki sahte "Kaynaklar:" satırı (yedek tarama, ham bulgular) kartı ele geçiremesin.
        guard let r = metin.range(of: "Kaynaklar:", options: .backwards) else { return [] }
        return metin[r.upperBound...].split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("https://") && URL(string: $0).map(WebSayfa.urlGuvenli) == true }
    }
}

// MARK: Görünümler

/// Balonun altındaki ek kartları.
struct EkKartlari: View {
    let ekler: [MesajEki]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(ekler) { e in
                switch e.tur {
                case .dosya(let url, let ad): DosyaKarti(url: url, ad: ad)
                case .indirme(let id): IndirmeKarti(id: id)
                case .tablo(let b, let s, let r, let k, let d): TabloKarti(baslik: b, sutunlar: s, satirlar: r, kaynak: k, dosya: d)
                case .kaynaklar: EmptyView() // Kaynaklar saklanır, sohbet kartı gösterilmez.
                case .medya(let m): MedyaKarti(ogeler: m)
                case .eylem(let k): EylemKarti(kayit: k)
                case .hava(let h): HavaKarti(ozet: h)
                case .izin(let t): IzinEkKarti(tur: t)
                }
            }
        }
        .fontDesign(.default)
    }
}

/// Ortak kart zemini (HavaKarti da kullanır).
struct KartZemini: ViewModifier {
    @Environment(\.colorScheme) private var sema
    func body(content: Content) -> some View {
        content.padding(12)
            .background(Color(uiColor: .secondarySystemBackground).opacity(sema == .dark ? 0.9 : 0.85), in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }
}

nonisolated enum DosyaSimgesi {
    static func ad(_ uzanti: String) -> String {
        switch uzanti.lowercased() {
        case "pdf": "doc.richtext"
        case "jpg", "jpeg", "png", "heic", "gif", "webp": "photo"
        case "mp4", "mov", "webm", "mkv": "film"
        case "mp3", "m4a", "wav", "aac", "ogg": "waveform"
        case "xlsx", "xls", "csv": "tablecells"
        case "doc", "docx", "txt", "md", "rtf": "doc.text"
        case "zip", "rar", "7z": "archivebox"
        case "ppt", "pptx", "key": "rectangle.on.rectangle"
        case "json", "xml", "html": "curlybraces"
        default: "doc"
        }
    }
    static func boyut(_ url: URL) -> String? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }
    }
}

struct DosyaKarti: View {
    let url: URL
    let ad: String
    @State private var onizleme: URL?
    private var var_: Bool { FileManager.default.fileExists(atPath: url.path) }
    var body: some View {
        if !var_ {
            EksikEkSatiri(ad: ad, aciklama: "Dosya artık yok (silinmiş ya da taşınmış)").accessibilityIdentifier("dosya-karti-yok")
        } else {
        HStack(spacing: 12) {
            Image(systemName: DosyaSimgesi.ad(url.pathExtension)).font(.title2).frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(ad).font(.callout.weight(.medium)).lineLimit(2)
                Text([url.pathExtension.uppercased(), DosyaSimgesi.boyut(url)].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button { onizleme = url } label: { Image(systemName: "eye").frame(width: 40, height: 40) }
                .accessibilityLabel("Önizle").accessibilityIdentifier("ek-onizle")
            ShareLink(item: url) { Image(systemName: "square.and.arrow.up").frame(width: 40, height: 40) }.accessibilityLabel("Paylaş")
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onTapGesture { onizleme = url }
        .modifier(KartZemini())
        .quickLookPreview($onizleme)
        // Live açılmadan önce bütün sunumlar kapanır (tam ekran Live başka sunumun üstüne açılamıyor).
        .onReceive(NotificationCenter.default.publisher(for: .asistanSunumlariKapat)) { _ in onizleme = nil }
        .accessibilityElement(children: .contain).accessibilityIdentifier("dosya-karti")
        }
    }
}

/// Artık bulunmayan ek (silinmiş dosya ya da indirme kaydı): kart iz bırakmadan kaybolmasın.
private struct EksikEkSatiri: View {
    let ad: String
    let aciklama: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "questionmark.folder").font(.title2).frame(width: 36).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(ad).font(.callout.weight(.medium)).lineLimit(2)
                Text(aciklama).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .modifier(KartZemini())
    }
}

struct IndirmeKarti: View {
    let id: UUID
    private var kayit: IndirmeKaydi? { IndirmeYoneticisi.ortak.kayitlar.first { $0.id == id } }
    var body: some View {
        if let k = kayit, k.durum == "done", let u = IndirmeYoneticisi.ortak.dosyaURL(k) {
            DosyaKarti(url: u, ad: k.ad)
        } else if let k = kayit, k.durum == "done" {
            // Kayıt tamam ama dosya yok (Dosyalar'dan silinmiş ya da taşınmış).
            EksikEkSatiri(ad: k.ad, aciklama: "Dosya artık yok (silinmiş ya da taşınmış)").accessibilityIdentifier("indirme-karti-yok")
        } else if kayit == nil {
            EksikEkSatiri(ad: "İndirme", aciklama: "İndirme kaydı silinmiş").accessibilityIdentifier("indirme-karti-yok")
        } else if let k = kayit {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: k.durum == "failed" ? "exclamationmark.triangle" : "arrow.down.circle").foregroundStyle(k.durum == "failed" ? .orange : .accentColor)
                    Text(k.ad).font(.callout.weight(.medium)).lineLimit(1)
                    Spacer()
                    if k.etkin { Button { Task { await IndirmeYoneticisi.ortak.iptal(id) } } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain).accessibilityLabel("İndirmeyi iptal et") }
                }
                if k.etkin {
                    if k.toplam > 0 { ProgressView(value: Double(k.alinan), total: Double(k.toplam)) } else { ProgressView() }
                    Text(k.toplam > 0 ? "\(ByteCountFormatter.string(fromByteCount: k.alinan, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: k.toplam, countStyle: .file))" : k.durumMetni)
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                } else {
                    Text(k.hata ?? k.durumMetni).font(.caption).foregroundStyle(.secondary)
                }
            }
            .modifier(KartZemini()).accessibilityElement(children: .contain).accessibilityIdentifier("indirme-karti")
        }
    }
}

struct TabloKarti: View {
    let baslik: String
    let sutunlar: [String]
    let satirlar: [[String]]
    let kaynak: String?
    let dosya: URL?
    @State private var tam = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "tablecells")
                Text(baslik).font(.callout.weight(.semibold)).lineLimit(1)
                Spacer()
                Text("\(satirlar.count) satır").font(.caption).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    GridRow { ForEach(sutunlar.prefix(6).indices, id: \.self) { Text(sutunlar[$0]).font(.caption.weight(.semibold)).lineLimit(1) } }
                    Divider()
                    ForEach(satirlar.prefix(5).indices, id: \.self) { i in
                        GridRow { ForEach(sutunlar.prefix(6).indices, id: \.self) { j in Text(j < satirlar[i].count ? satirlar[i][j] : "").font(.caption).lineLimit(1).frame(maxWidth: 160, alignment: .leading) } }
                    }
                }
            }
            HStack {
                Button("Tümünü gör", systemImage: "arrow.up.left.and.arrow.down.right") { tam = true }.accessibilityIdentifier("tablo-tumu")
                Spacer()
                if let dosya { ShareLink(item: dosya) { Label("Dışa aktar", systemImage: "square.and.arrow.up") } }
            }
            .font(.footnote)
        }
        .modifier(KartZemini())
        .accessibilityElement(children: .contain).accessibilityIdentifier("tablo-karti")
        .sheet(isPresented: $tam) { TabloEkrani(baslik: baslik, sutunlar: sutunlar, satirlar: satirlar, kaynak: kaynak, dosya: dosya) }
        .onReceive(NotificationCenter.default.publisher(for: .asistanSunumlariKapat)) { _ in tam = false }
    }
}

/// Tam ekran tablo: arama, sütuna göre sıralama, dışa aktarma.
/// Süzme/sıralama yalnız sorgu ya da sıra değişince bir kez hesaplanır; satırlar tembel çizilir (binlerce satırda donmaz).
struct TabloEkrani: View {
    let baslik: String
    let sutunlar: [String]
    let satirlar: [[String]]
    let kaynak: String?
    let dosya: URL?
    @Environment(\.dismiss) private var kapat
    @State private var sorgu = ""
    @State private var siraSutun: Int?
    @State private var artan = true
    @State private var kaynakAcik: URL?
    @State private var gorunen: [[String]] = []
    private let genislik: CGFloat = 150

    nonisolated static func hesapla(_ satirlar: [[String]], sorgu: String, sutun: Int?, artan: Bool) -> [[String]] {
        var r = sorgu.isEmpty ? satirlar : satirlar.filter { $0.contains { $0.localizedStandardContains(sorgu) } }
        guard let s = sutun else { return r }
        // Anahtarlar bir kez çözülür (karşılaştırmada tekrar tekrar dönüştürülmez).
        let anahtarli = r.map { satir -> (Double?, String, [String]) in
            let x = s < satir.count ? satir[s] : ""
            return (Double(x.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".").filter { $0.isNumber || $0 == "." || $0 == "-" }), x, satir)
        }
        let sayisal = anahtarli.allSatisfy { $0.0 != nil || $0.1.isEmpty }
        r = anahtarli.sorted { a, b in
            if sayisal { return artan ? (a.0 ?? 0) < (b.0 ?? 0) : (a.0 ?? 0) > (b.0 ?? 0) }
            let k = a.1.localizedStandardCompare(b.1)
            return artan ? k == .orderedAscending : k == .orderedDescending
        }.map(\.2)
        return r
    }

    var body: some View {
        NavigationStack {
            ScrollView(.horizontal) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        ForEach(gorunen.indices, id: \.self) { i in
                            HStack(alignment: .top, spacing: 12) {
                                ForEach(sutunlar.indices, id: \.self) { j in
                                    Text(j < gorunen[i].count ? gorunen[i][j] : "").font(.footnote).lineLimit(4).frame(width: genislik, alignment: .leading)
                                }
                            }
                            .padding(.horizontal).padding(.vertical, 6)
                            .background(i % 2 == 0 ? Color.clear : Color.secondary.opacity(0.06))
                        }
                    } header: {
                        HStack(spacing: 12) {
                            ForEach(sutunlar.indices, id: \.self) { j in
                                Button {
                                    if siraSutun == j { artan.toggle() } else { siraSutun = j; artan = true }
                                } label: {
                                    HStack(spacing: 2) {
                                        Text(sutunlar[j]).font(.footnote.weight(.semibold)).lineLimit(2)
                                        if siraSutun == j { Image(systemName: artan ? "chevron.up" : "chevron.down").font(.caption2) }
                                    }.frame(width: genislik, alignment: .leading)
                                }.buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal).padding(.vertical, 8).background(.bar)
                    }
                }
            }
            .searchable(text: $sorgu, prompt: "Tabloda ara")
            .navigationTitle(baslik).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Kapat") { kapat() } }
                ToolbarItemGroup(placement: .primaryAction) {
                    if let k = kaynak, let u = URL(string: k), u.scheme == "https" { Button("Kaynak", systemImage: "safari") { kaynakAcik = u } }
                    if let dosya { ShareLink(item: dosya) { Image(systemName: "square.and.arrow.up") } }
                }
            }
            .task(id: "\(sorgu)|\(siraSutun ?? -1)|\(artan)") {
                let (r, q, s, a) = (satirlar, sorgu, siraSutun, artan)
                gorunen = await Task.detached(priority: .userInitiated) { TabloEkrani.hesapla(r, sorgu: q, sutun: s, artan: a) }.value
            }
            .sheet(item: Binding(get: { kaynakAcik.map(SafariHedefi.init) }, set: { kaynakAcik = $0?.url })) { SafariSayfasi(url: $0.url).ignoresSafeArea() }
        }
    }
}

/// Kaynaklar: katlanmış gelir; açınca her kaynak başlık + site kartıdır, dokununca uygulama içinde önizlenir.
struct KaynakKartlari: View {
    let adresler: [String]
    @State private var acik = false
    @State private var hedef: SafariHedefi?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation(.easeOut(duration: 0.2)) { acik.toggle() } } label: {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                    Text("Kaynaklar (\(adresler.count))").font(.footnote.weight(.semibold))
                    ForEach(adresler.prefix(4), id: \.self) { a in Text(URL(string: a)?.host?.replacingOccurrences(of: "www.", with: "") ?? "").font(.caption2).lineLimit(1).padding(.horizontal, 6).padding(.vertical, 2).background(.quaternary, in: Capsule()) }
                    Spacer(minLength: 0)
                    Image(systemName: acik ? "chevron.up" : "chevron.down").font(.caption)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityIdentifier("kaynaklar-dugmesi")
            if acik {
                ForEach(adresler, id: \.self) { a in
                    if let u = URL(string: a) { KaynakSatiri(url: u) { hedef = SafariHedefi(url: u) } }
                }
            }
        }
        .modifier(KartZemini())
        .sheet(item: $hedef) { SafariSayfasi(url: $0.url).ignoresSafeArea() }
        .onReceive(NotificationCenter.default.publisher(for: .asistanSunumlariKapat)) { _ in hedef = nil }
    }
}

private struct KaynakSatiri: View {
    let url: URL
    let ac: () -> Void
    @State private var baslik: String?
    var body: some View {
        Button(action: ac) {
            HStack(spacing: 10) {
                Image(systemName: "globe").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(baslik ?? url.host ?? url.absoluteString).font(.callout).lineLimit(2)
                    Text(url.host?.replacingOccurrences(of: "www.", with: "") ?? "").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "eye").foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Kaynağı önizle: \(baslik ?? url.host ?? "")").accessibilityIdentifier("kaynak-satiri")
        .task { baslik = await BaglantiBasligi.getir(url) }
    }
}

/// Bağlantı başlığı (LinkPresentation); oturum boyunca önbellekte.
@MainActor
enum BaglantiBasligi {
    private static var onbellek: [URL: String] = [:]
    static func getir(_ url: URL) async -> String? {
        if let b = onbellek[url] { return b }
        let s = LPMetadataProvider(); s.timeout = 6
        guard let m = try? await s.startFetchingMetadata(for: url), let t = m.title, !t.isEmpty else { return nil }
        onbellek[url] = t
        return t
    }
}

struct SafariHedefi: Identifiable { let url: URL; var id: String { url.absoluteString } }

struct SafariSayfasi: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ c: SFSafariViewController, context: Context) {}
}


/// Kartların kalıcı biçimi. Dosya yolları Indirmeler klasörüne göre göreli saklanır (uygulama yeniden kurulunca kap yolu değişir);
/// büyük tablolar 300 satırla sınırlanır (tamamı Excel/CSV dosyasında durur).
nonisolated enum EkKalici {
    struct MedyaDTO: Codable { var tur: String; var url: String; var ad: String }
    struct EkDTO: Codable {
        var t: String
        var ad: String?, yol: String?, baslik: String?, kaynak: String?
        var sutunlar: [String]?, satirlar: [[String]]?, adresler: [String]?
        var kimlik: UUID?, medya: [MedyaDTO]?
        /// Eski kayıtlarda yok (nil); eklenmesi geriye uyumludur.
        var eylem: EylemKaydi? = nil
        /// Hava kartı özeti; eski kayıtlarda yok (nil), geriye uyumlu.
        var hava: HavaOzeti? = nil
    }
    static let onek = "I:"
    static let enFazlaSatir = 300

    static func yolKodla(_ u: URL) -> String {
        let kok = IndirmeYoneticisi.klasorYolu
        return u.path.hasPrefix(kok + "/") ? onek + String(u.path.dropFirst(kok.count + 1)) : u.path
    }
    static func yolCoz(_ y: String) -> URL {
        y.hasPrefix(onek) ? URL(filePath: IndirmeYoneticisi.klasorYolu).appending(path: String(y.dropFirst(onek.count))) : URL(filePath: y)
    }

    // Kullanıcı fotoğrafları: Application Support/MesajGorselleri/<ad>.jpg (kap yolundan bağımsız, yalnız ad saklanır).
    static var gorselKlasoru: URL {
        let k = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
        return k.appendingPathComponent("MesajGorselleri", isDirectory: true)
    }
    /// Görselleri diske yazar (en çok 1600 px, JPEG); dönen adlar mesajla birlikte saklanır.
    static func gorselleriKaydet(_ resimler: [UIImage]) -> [String] {
        guard !resimler.isEmpty else { return [] }
        try? FileManager.default.createDirectory(at: gorselKlasoru, withIntermediateDirectories: true)
        let adlar: [String] = resimler.compactMap { r in
            guard let cg = r.kucultulmus(1600), let v = UIImage(cgImage: cg).jpegData(compressionQuality: 0.75) else { return nil }
            let ad = UUID().uuidString + ".jpg"
            return (try? v.write(to: gorselKlasoru.appendingPathComponent(ad), options: .atomic)) != nil ? ad : nil
        }
        if !adlar.isEmpty { sonKayit.withLock { $0 = adlar } }
        return adlar
    }
    /// P2.12: Son gönderilen fotoğrafların / taranmış sayfaların adları (pdfIslem 'gorsel:son' kaynağı). Yalnız bellekte.
    private static let sonKayit = Mutex<[String]>([])
    static var sonKaydedilenler: [String] { sonKayit.withLock { $0 } }
    static func gorselleriYukle(_ veri: Data?) -> [UIImage] {
        guard let veri, let d = try? JSONDecoder().decode([EkDTO].self, from: veri) else { return [] }
        return d.filter { $0.t == "gorsel" }.compactMap { e in e.ad.flatMap { UIImage(contentsOfFile: gorselKlasoru.appendingPathComponent($0).path) } }
    }
    /// P3.9: kalıcı mesajın fotoğraf adları (dosya okunmaz); sohbet açılışında küçük resim `GorselOnbellegi` ile yüklenir.
    static func gorselAdlari(_ veri: Data?) -> [String] {
        guard let veri, let d = try? JSONDecoder().decode([EkDTO].self, from: veri) else { return [] }
        return d.filter { $0.t == "gorsel" }.compactMap { $0.ad }.filter { !$0.isEmpty }
    }
    /// Fotoğraf adının dosya yolu (yalnız son yol bileşeni kullanılır; klasör dışına çıkılmaz).
    static func gorselURL(_ ad: String) -> URL {
        gorselKlasoru.appendingPathComponent((ad as NSString).lastPathComponent)
    }

    static func kodla(_ ekler: [MesajEki], gorselAdlari: [String] = []) -> Data? {
        guard !ekler.isEmpty || !gorselAdlari.isEmpty else { return nil }
        let gorseller = gorselAdlari.map { EkDTO(t: "gorsel", ad: $0) }
        let d: [EkDTO] = gorseller + ekler.map { e in
            switch e.tur {
            case .dosya(let u, let ad): EkDTO(t: "dosya", ad: ad, yol: yolKodla(u))
            case .indirme(let id): EkDTO(t: "indirme", kimlik: id)
            case .tablo(let b, let s, let r, let k, let f): EkDTO(t: "tablo", yol: f.map(yolKodla), baslik: b, kaynak: k, sutunlar: s, satirlar: Array(r.prefix(enFazlaSatir)))
            case .kaynaklar(let k): EkDTO(t: "kaynak", adresler: k)
            case .medya(let m): EkDTO(t: "medya", medya: m.map { MedyaDTO(tur: $0.tur.rawValue, url: $0.url.absoluteString, ad: $0.ad) })
            case .eylem(let k): EkDTO(t: "eylem", eylem: k)
            case .hava(let h): EkDTO(t: "hava", hava: h)
            case .izin(let t): EkDTO(t: "izin", ad: t.rawValue)
            }
        }
        return try? JSONEncoder().encode(d)
    }

    static func coz(_ veri: Data?) -> [MesajEki] {
        guard let veri, let d = try? JSONDecoder().decode([EkDTO].self, from: veri) else { return [] }
        return d.compactMap { e in
            switch e.t {
            case "dosya": if let y = e.yol { return MesajEki(tur: .dosya(url: yolCoz(y), ad: e.ad ?? "Dosya")) }
            case "indirme": if let k = e.kimlik { return MesajEki(tur: .indirme(k)) }
            case "tablo": if let s = e.sutunlar, let r = e.satirlar { return MesajEki(tur: .tablo(baslik: e.baslik ?? "Tablo", sutunlar: s, satirlar: r, kaynak: e.kaynak, dosya: e.yol.map(yolCoz))) }
            case "kaynak": if let a = e.adresler { return MesajEki(tur: .kaynaklar(a)) }
            case "eylem": if let k = e.eylem { return MesajEki(tur: .eylem(k)) }
            case "hava": if let h = e.hava { return MesajEki(tur: .hava(h)) }
            case "izin": if let a = e.ad, let t = IzinTuru(rawValue: a) { return MesajEki(tur: .izin(t)) }
            case "medya":
                let o = (e.medya ?? []).compactMap { m -> MedyaOgesi? in
                    guard let t = MedyaOgesi.Tur(rawValue: m.tur), let u = URL(string: m.url) else { return nil }
                    return MedyaOgesi(tur: t, url: u, ad: m.ad)
                }
                if !o.isEmpty { return MesajEki(tur: .medya(o)) }
            default: break
            }
            return nil
        }
    }
}
