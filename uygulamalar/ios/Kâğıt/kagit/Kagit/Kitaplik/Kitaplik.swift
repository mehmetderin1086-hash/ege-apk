import Foundation
import KagitKit
import UniformTypeIdentifiers

/// Kitaplıktaki bir dosya ya da klasör. Kimlik: kitaplık köküne göre göreli yol.
struct KitaplikOgesi: Identifiable, Hashable, Sendable {
    var id: String { yol }
    /// Köke göre göreli yol ("Sınavlar/9A/deneme.pdf"). Kök klasör için "".
    let yol: String
    let url: URL
    let klasorMu: Bool
    let boyut: Int64
    let degistirilme: Date

    var ad: String { klasorMu ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent }
    var tamAd: String { url.lastPathComponent }
    var uzanti: String { url.pathExtension.lowercased() }
    var tur: UTType? { UTType(filenameExtension: uzanti) }
    var pdfMi: Bool { !klasorMu && uzanti == "pdf" }
    var gorselMi: Bool { !klasorMu && (tur?.conforms(to: .image) ?? false) }
    /// Üst klasörün göreli yolu.
    var ustYol: String { (yol as NSString).deletingLastPathComponent }
}

/// Kullanıcının kitaplıktaki öge başına bilgileri (dosyanın kendisinde saklanmaz).
struct OgeBilgisi: Codable, Hashable, Sendable {
    var yildiz = false
    var etiketler: [String] = []
    var sonAcilma: Date?
    var sonSayfa: Int?
}

/// Belgeler klasörü üzerinde çalışan kitaplık. Dosyalar uygulamasında
/// "iPhone'umda › Kâğıt" olarak görünür; dışarıda yapılan değişiklikler `tara()` ile alınır.
@Observable
final class Kitaplik {
    static let paylasilan = Kitaplik()

    let kok: URL
    let cop: URL
    private let bilgiDosyasi: URL

    private(set) var ogeler: [KitaplikOgesi] = []
    private(set) var copOgeleri: [KitaplikOgesi] = []
    private(set) var bilgiler: [String: OgeBilgisi] = [:]
    private(set) var taraniyor = false
    @ObservationIgnored private var gelenAliniyor = false

    /// Tarama sonrası çağrılan kancalar (Spotlight dizini vb.).
    @ObservationIgnored var taramaSonrasi: [@MainActor ([KitaplikOgesi]) -> Void] = []

    init(kok: URL? = nil) {
        let fm = FileManager.default
        self.kok = kok ?? fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        cop = self.kok.appendingPathComponent(".Cop", isDirectory: true)
        let destek = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? fm.createDirectory(at: destek, withIntermediateDirectories: true)
        bilgiDosyasi = destek.appendingPathComponent(kok == nil ? "kitaplik.json" : "kitaplik-\(abs(self.kok.path.hashValue)).json")
        if let veri = try? Data(contentsOf: bilgiDosyasi),
           let b = try? JSONDecoder().decode([String: OgeBilgisi].self, from: veri) {
            bilgiler = b
        }
    }

    // MARK: - Tarama

    func tara() async {
        taraniyor = true
        let kok = kok, cop = cop
        let (bulunan, copta) = await Task.detached(priority: .userInitiated) {
            (Self.listele(kok, kok: kok, gizliHaric: true), Self.listele(cop, kok: kok, gizliHaric: false))
        }.value
        ogeler = bulunan
        copOgeleri = copta.filter { $0.ustYol == ".Cop" }
        taraniyor = false
        // Silinmiş dosyaların bilgilerini at
        let yollar = Set(ogeler.map(\.yol))
        let eski = bilgiler.count
        bilgiler = bilgiler.filter { yollar.contains($0.key) }
        if eski != bilgiler.count { bilgiKaydet() }
        for kanca in taramaSonrasi { kanca(ogeler) }
    }

    nonisolated private static func listele(_ dizin: URL, kok: URL, gizliHaric: Bool) -> [KitaplikOgesi] {
        let fm = FileManager.default
        let anahtarlar: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        guard let sayac = fm.enumerator(at: dizin, includingPropertiesForKeys: anahtarlar,
                                        options: gizliHaric ? [.skipsHiddenFiles] : []) else { return [] }
        let kokYol = kok.standardizedFileURL.path
        var sonuc: [KitaplikOgesi] = []
        for case let url as URL in sayac {
            let ad = url.lastPathComponent
            if ad == "Inbox" || ad.hasSuffix(".kagit-gecici") || ad == ".DS_Store" { sayac.skipDescendants(); continue }
            let d = try? url.resourceValues(forKeys: Set(anahtarlar))
            let tam = url.standardizedFileURL.path
            let yol = tam.hasPrefix(kokYol + "/") ? String(tam.dropFirst(kokYol.count + 1)) : ad
            sonuc.append(KitaplikOgesi(yol: yol, url: url, klasorMu: d?.isDirectory ?? false,
                                       boyut: Int64(d?.fileSize ?? 0),
                                       degistirilme: d?.contentModificationDate ?? .distantPast))
        }
        return sonuc
    }

    // MARK: - Sorgular

    func url(_ yol: String) -> URL { yol.isEmpty ? kok : kok.appendingPathComponent(yol) }

    func oge(yol: String) -> KitaplikOgesi? { ogeler.first { $0.yol == yol } }

    func oge(url: URL) -> KitaplikOgesi? {
        let hedef = url.standardizedFileURL.path
        return ogeler.first { $0.url.standardizedFileURL.path == hedef }
    }

    /// Klasörün doğrudan içeriği: önce klasörler, sonra dosyalar.
    func icerik(_ klasorYolu: String, siralama: Siralama = .tarih) -> [KitaplikOgesi] {
        let cocuklar = ogeler.filter { $0.ustYol == klasorYolu }
        let klasorler = cocuklar.filter(\.klasorMu).sorted { $0.ad.localizedStandardCompare($1.ad) == .orderedAscending }
        return klasorler + siralama.sirala(cocuklar.filter { !$0.klasorMu })
    }

    var belgeler: [KitaplikOgesi] { ogeler.filter { !$0.klasorMu } }
    var pdfler: [KitaplikOgesi] { ogeler.filter(\.pdfMi) }
    var klasorler: [KitaplikOgesi] { ogeler.filter(\.klasorMu) }

    func sonAcilanlar(_ n: Int = 12) -> [KitaplikOgesi] {
        let acilan = belgeler.filter { bilgiler[$0.yol]?.sonAcilma != nil }
            .sorted { (bilgiler[$0.yol]?.sonAcilma ?? .distantPast) > (bilgiler[$1.yol]?.sonAcilma ?? .distantPast) }
        let yeni = belgeler.sorted { $0.degistirilme > $1.degistirilme }
        var gorulen = Set<String>()
        return (acilan + yeni).filter { gorulen.insert($0.yol).inserted }.prefix(n).map { $0 }
    }

    var yildizlilar: [KitaplikOgesi] { belgeler.filter { bilgiler[$0.yol]?.yildiz == true } }

    var tumEtiketler: [String] {
        Array(Set(bilgiler.values.flatMap(\.etiketler))).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func etiketli(_ etiket: String) -> [KitaplikOgesi] {
        belgeler.filter { bilgiler[$0.yol]?.etiketler.contains(etiket) == true }
    }

    /// Ad (ve klasör yolu) içinde Türkçe'ye duyarlı arama.
    func ara(_ metin: String) -> [KitaplikOgesi] {
        let a = TurkceMetin.anahtar(metin)
        guard !a.isEmpty else { return [] }
        return ogeler.filter { TurkceMetin.anahtar($0.yol).contains(a) }
            .sorted { $0.degistirilme > $1.degistirilme }
    }

    func bilgi(_ oge: KitaplikOgesi) -> OgeBilgisi { bilgiler[oge.yol] ?? OgeBilgisi() }

    // MARK: - Bilgi güncelleme

    func acildi(_ oge: KitaplikOgesi, sayfa: Int? = nil) {
        var b = bilgi(oge)
        b.sonAcilma = Date()
        if let sayfa { b.sonSayfa = sayfa }
        bilgiler[oge.yol] = b
        bilgiKaydet()
    }

    func yildizDegistir(_ oge: KitaplikOgesi) {
        var b = bilgi(oge)
        b.yildiz.toggle()
        bilgiler[oge.yol] = b
        bilgiKaydet()
    }

    func etiketle(_ oge: KitaplikOgesi, _ etiketler: [String]) {
        var b = bilgi(oge)
        b.etiketler = Array(Set(etiketler.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })).sorted()
        bilgiler[oge.yol] = b
        bilgiKaydet()
    }

    private func bilgiKaydet() {
        if let veri = try? JSONEncoder().encode(bilgiler) { try? veri.write(to: bilgiDosyasi, options: .atomic) }
    }

    private func bilgiTasi(_ eski: String, _ yeni: String) {
        for (yol, b) in bilgiler where yol == eski || yol.hasPrefix(eski + "/") {
            bilgiler.removeValue(forKey: yol)
            bilgiler[yeni + yol.dropFirst(eski.count)] = b
        }
        bilgiKaydet()
    }

    // MARK: - Dosya işlemleri

    /// Klasörde çakışmayan bir ad bulur: "Ad.pdf", "Ad 2.pdf", "Ad 3.pdf"…
    func benzersizURL(klasor: URL, ad: String, uzanti: String) -> URL {
        let temiz = TurkceMetin.dosyaAdi(ad)
        let fm = FileManager.default
        var aday = klasor.appendingPathComponent(temiz).appendingPathExtension(uzanti)
        var n = 2
        while fm.fileExists(atPath: aday.path) {
            aday = klasor.appendingPathComponent("\(temiz) \(n)").appendingPathExtension(uzanti)
            n += 1
        }
        return aday
    }

    /// Dışarıdan (Dosyalar, paylaşım, fotoğraflar) gelen dosyaları kitaplığa kopyalar.
    @discardableResult
    func iceAktar(_ urller: [URL], klasor: String = "") async throws -> [KitaplikOgesi] {
        let hedefKlasor = url(klasor)
        try FileManager.default.createDirectory(at: hedefKlasor, withIntermediateDirectories: true)
        var yeniler: [URL] = []
        for kaynak in urller {
            // Zaten kitaplıktaysa kopyalama
            if kaynak.standardizedFileURL.path.hasPrefix(kok.standardizedFileURL.path + "/"),
               !kaynak.path.contains("/Inbox/") {
                yeniler.append(kaynak)
                continue
            }
            let erisim = kaynak.startAccessingSecurityScopedResource()
            defer { if erisim { kaynak.stopAccessingSecurityScopedResource() } }
            let hedef = benzersizURL(klasor: hedefKlasor, ad: kaynak.deletingPathExtension().lastPathComponent,
                                     uzanti: kaynak.pathExtension.isEmpty ? "pdf" : kaynak.pathExtension)
            var hata: NSError?
            var kopyaHatasi: Error?
            NSFileCoordinator().coordinate(readingItemAt: kaynak, options: .withoutChanges, error: &hata) { okunan in
                do { try FileManager.default.copyItem(at: okunan, to: hedef) } catch { kopyaHatasi = error }
            }
            if let h = hata ?? kopyaHatasi { throw KagitHata.genel("\(kaynak.lastPathComponent) alınamadı: \(h.localizedDescription)") }
            if kaynak.path.contains("/Inbox/") { try? FileManager.default.removeItem(at: kaynak) }
            yeniler.append(hedef)
        }
        await tara()
        return yeniler.compactMap { oge(url: $0) }
    }

    /// Bir aracın geçici çıktısını kitaplığa taşır. Klasör verilmezse kaynak belgenin
    /// klasörü, o da yoksa kök kullanılır.
    @discardableResult
    func ciktiKaydet(_ gecici: URL, ad: String, klasor: String? = nil, kaynak: URL? = nil) async throws -> KitaplikOgesi {
        let klasorYolu = klasor ?? kaynak.flatMap { oge(url: $0)?.ustYol } ?? ""
        let hedefKlasor = url(klasorYolu)
        try FileManager.default.createDirectory(at: hedefKlasor, withIntermediateDirectories: true)
        let uzanti = gecici.pathExtension.isEmpty ? "pdf" : gecici.pathExtension
        let hedef = benzersizURL(klasor: hedefKlasor, ad: ad, uzanti: uzanti)
        try FileManager.default.moveItem(at: gecici, to: hedef)
        await tara()
        guard let yeni = oge(url: hedef) else { throw KagitHata.kaydedilemedi(hedef.lastPathComponent) }
        return yeni
    }

    func yeniKlasor(_ ad: String, ust: String = "") async throws -> KitaplikOgesi {
        let hedef = benzersizURL(klasor: url(ust), ad: ad, uzanti: "").deletingPathExtension()
        try FileManager.default.createDirectory(at: hedef, withIntermediateDirectories: true)
        await tara()
        guard let k = oge(url: hedef) else { throw KagitHata.kaydedilemedi(ad) }
        return k
    }

    func yenidenAdlandir(_ oge: KitaplikOgesi, _ yeniAd: String) async throws {
        let temiz = TurkceMetin.dosyaAdi(yeniAd)
        guard temiz != oge.ad else { return }
        let ust = oge.url.deletingLastPathComponent()
        var hedef = ust.appendingPathComponent(temiz)
        if !oge.klasorMu { hedef.appendPathExtension(oge.uzanti) }
        guard !FileManager.default.fileExists(atPath: hedef.path) else {
            throw KagitHata.genel("Bu adda bir öge zaten var.")
        }
        try FileManager.default.moveItem(at: oge.url, to: hedef)
        let yeniYol = (oge.ustYol as NSString).appendingPathComponent(hedef.lastPathComponent)
        bilgiTasi(oge.yol, yeniYol)
        await tara()
    }

    func tasi(_ secilenler: [KitaplikOgesi], klasor: String) async throws {
        let hedefKlasor = url(klasor)
        for o in secilenler {
            if o.klasorMu, klasor == o.yol || klasor.hasPrefix(o.yol + "/") { continue }
            guard o.ustYol != klasor else { continue }
            let hedef = benzersizURL(klasor: hedefKlasor, ad: o.ad, uzanti: o.klasorMu ? "" : o.uzanti)
            let duzgun = o.klasorMu ? hedef.deletingPathExtension() : hedef
            try FileManager.default.moveItem(at: o.url, to: duzgun)
            bilgiTasi(o.yol, (klasor as NSString).appendingPathComponent(duzgun.lastPathComponent))
        }
        await tara()
    }

    func kopyala(_ o: KitaplikOgesi) async throws -> KitaplikOgesi? {
        let hedef = benzersizURL(klasor: o.url.deletingLastPathComponent(), ad: "\(o.ad) kopya", uzanti: o.uzanti)
        try FileManager.default.copyItem(at: o.url, to: hedef)
        await tara()
        return oge(url: hedef)
    }

    /// Çöp kutusuna taşır (Dosyalar'da görünmeyen gizli klasör). 30 gün sonra silinir.
    func copeAt(_ secilenler: [KitaplikOgesi]) async throws {
        try FileManager.default.createDirectory(at: cop, withIntermediateDirectories: true)
        for o in secilenler {
            let hedef = benzersizURL(klasor: cop, ad: o.ad, uzanti: o.klasorMu ? "" : o.uzanti)
            let son = o.klasorMu ? hedef.deletingPathExtension() : hedef
            try FileManager.default.moveItem(at: o.url, to: son)
            // Çöpe atılma anı: 30 gün sayacı dosyanın eski değişiklik tarihine değil buna bakar.
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: son.path)
        }
        await tara()
    }

    func copGeriAl(_ o: KitaplikOgesi) async throws {
        let hedef = benzersizURL(klasor: kok, ad: o.ad, uzanti: o.klasorMu ? "" : o.uzanti)
        try FileManager.default.moveItem(at: o.url, to: o.klasorMu ? hedef.deletingPathExtension() : hedef)
        await tara()
    }

    /// Çöpü boşaltır; `gun` verilirse yalnız o günden eski ögeleri siler.
    func copuBosalt(gun: Int? = nil) async {
        let sinir = gun.map { Date().addingTimeInterval(-Double($0) * 86_400) }
        for o in copOgeleri where sinir == nil || o.degistirilme < sinir! {
            try? FileManager.default.removeItem(at: o.url)
        }
        await tara()
    }

    // MARK: - Paylaşım uzantısından gelenler

    /// Paylaşım uzantısının App Group'a bıraktığı dosyaları kitaplığa alır.
    func paylasimGelenleriniAl() async {
        guard let gelen = OrtakKlasor.gelenler else { return }
        let fm = FileManager.default
        guard !gelenAliniyor else { return }
        gelenAliniyor = true
        defer { gelenAliniyor = false }
        guard let dosyalar = try? fm.contentsOfDirectory(at: gelen, includingPropertiesForKeys: nil), !dosyalar.isEmpty else { return }
        // Her dosya ayrı alınır; yalnız başarıyla alınanlar Gelenler'den silinir.
        for d in dosyalar {
            if (try? await iceAktar([d])) != nil { try? fm.removeItem(at: d) }
        }
    }
}

/// Dosya sıralama ölçütü.
enum Siralama: String, CaseIterable, Identifiable, Codable {
    case tarih, ad, boyut
    var id: String { rawValue }
    var baslik: String {
        switch self {
        case .tarih: "Tarih"
        case .ad: "Ad"
        case .boyut: "Boyut"
        }
    }

    func sirala(_ o: [KitaplikOgesi]) -> [KitaplikOgesi] {
        switch self {
        case .tarih: o.sorted { $0.degistirilme > $1.degistirilme }
        case .ad: o.sorted { $0.ad.localizedStandardCompare($1.ad) == .orderedAscending }
        case .boyut: o.sorted { $0.boyut > $1.boyut }
        }
    }
}
