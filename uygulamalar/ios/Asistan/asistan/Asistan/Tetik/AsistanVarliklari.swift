import AppIntents
import CoreSpotlight
import Foundation
import SwiftData
import UniformTypeIdentifiers

// P4.4: sistem genelinde görünürlük. Sohbetler ve indirilen dosyalar Spotlight'ta aranabilir (`IndexedEntity`);
// olgular (kişisel hafıza) Spotlight'a GİRMEZ, yalnız Kestirmeler'de sorgulanır (`OlguVarligi`, `HafizadaBulIntent`).
// Bütün varlık ve sorgu türleri `nonisolated struct`: AppEntity/EntityQuery Sendable ve yalıtımsız gereksinimler taşır,
// MainActor varsayılan yalıtımlı modülde düz struct "main actor-isolated conformance" hatası verir. Depoya erişen sorgu
// yöntemleri `@MainActor … async`: async gereksinim yalıtımlı tanıkla karşılanır.

// MARK: Sohbet

nonisolated struct SohbetVarligi: IndexedEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Sohbet" }
    static var defaultQuery: SohbetSorgusu { SohbetSorgusu() }

    // Düz `let`: `nonisolated struct` içinde `@Property` sarmalayıcısı "'nonisolated' cannot be applied to mutable stored
    // properties" hatası verir (swiftc ile sınandı). Spotlight başlık/alt başlığı `displayRepresentation`'dan okur.
    let id: UUID
    let baslik: String
    let tarih: Date
    /// Yalnız `Ayarlar.spotlightIcerik` açıkken dolu: ilk kullanıcı mesajının ilk 200 karakteri. Varsayılan yalnız başlık.
    let ozet: String?

    init(id: UUID, baslik: String, tarih: Date, ozet: String? = nil) {
        self.id = id
        self.baslik = baslik
        self.tarih = tarih
        self.ozet = ozet
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(baslik)", subtitle: "\(tarih.formatted(date: .abbreviated, time: .omitted))")
    }

    var attributeSet: CSSearchableItemAttributeSet {
        AsistanSpotlight.ozellikler(baslik: baslik, icerik: ozet, icerikDahil: ozet != nil, temel: defaultAttributeSet)
    }
}

nonisolated struct SohbetSorgusu: EntityStringQuery {
    init() {}

    @MainActor func entities(for identifiers: [SohbetVarligi.ID]) async throws -> [SohbetVarligi] {
        Self.bul(identifiers, baglam: HafizaDeposu.paylasilanKap.mainContext)
    }

    @MainActor func entities(matching string: String) async throws -> [SohbetVarligi] {
        Self.ara(string, baglam: HafizaDeposu.paylasilanKap.mainContext)
    }

    @MainActor func suggestedEntities() async throws -> [SohbetVarligi] {
        Self.sonlar(baglam: HafizaDeposu.paylasilanKap.mainContext)
    }

    /// Kimliklerle sohbet bulur (sıra korunur; bulunamayan atlanır). Testler bellek içi kapla çağırır.
    @MainActor static func bul(_ kimlikler: [UUID], baglam: ModelContext) -> [SohbetVarligi] {
        let icerik = AsistanSpotlight.icerikDahil
        return kimlikler.compactMap { k in
            var d = FetchDescriptor<Sohbet>(predicate: #Predicate { $0.kimlik == k })
            d.fetchLimit = 1
            return (try? baglam.fetch(d))?.first.map { AsistanSpotlight.varlik($0, icerikDahil: icerik) }
        }
    }

    /// Başlıkta geçen metne göre (büyük/küçük harf ve aksan duyarsız), yeniden eskiye en çok 20 sohbet.
    @MainActor static func ara(_ metin: String, baglam: ModelContext) -> [SohbetVarligi] {
        let t = metin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return sonlar(baglam: baglam) }
        var d = FetchDescriptor<Sohbet>(predicate: #Predicate { $0.baslik.localizedStandardContains(t) },
                                        sortBy: [SortDescriptor(\.olusturma, order: .reverse)])
        d.fetchLimit = 20
        let icerik = AsistanSpotlight.icerikDahil
        return ((try? baglam.fetch(d)) ?? []).map { AsistanSpotlight.varlik($0, icerikDahil: icerik) }
    }

    /// Son 10 sohbet (Kestirmeler öneri listesi).
    @MainActor static func sonlar(baglam: ModelContext, adet: Int = 10) -> [SohbetVarligi] {
        var d = FetchDescriptor<Sohbet>(sortBy: [SortDescriptor(\.olusturma, order: .reverse)])
        d.fetchLimit = adet
        let icerik = AsistanSpotlight.icerikDahil
        return ((try? baglam.fetch(d)) ?? []).map { AsistanSpotlight.varlik($0, icerikDahil: icerik) }
    }
}

/// Spotlight'ta ya da Kestirmeler'de seçilen sohbeti uygulamada açar (`asistan://sohbet?kimlik=`; yan etkisiz).
struct SohbetiAcIntent: OpenIntent {
    static let title: LocalizedStringResource = "Sohbeti aç"
    static let description = IntentDescription("Asistan'daki bir sohbeti açar.")

    @Parameter(title: "Sohbet") var target: SohbetVarligi

    init() {}
    init(target: SohbetVarligi) { self.target = target }

    @MainActor func perform() async throws -> some IntentResult & OpensIntent {
        let url = IsAktivitesiGorunum.sohbetAdresi(target.id.uuidString) ?? URL(string: "asistan://arsiv")!
        return .result(opensIntent: OpenURLIntent(url))
    }
}

// MARK: İndirilen dosya

nonisolated struct DosyaVarligi: IndexedEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Dosya" }
    static var defaultQuery: DosyaSorgusu { DosyaSorgusu() }

    let id: UUID
    let ad: String
    let tur: String

    init(id: UUID, ad: String, tur: String) {
        self.id = id
        self.ad = ad
        self.tur = tur
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(ad)", subtitle: "Asistan · İndirmeler")
    }

    var attributeSet: CSSearchableItemAttributeSet {
        AsistanSpotlight.ozellikler(baslik: ad, icerik: nil, icerikDahil: false, temel: defaultAttributeSet)
    }

    /// Spotlight'a yalnız bitmiş ve dosyası olan kayıtlar girer.
    @MainActor static func listesi(_ kayitlar: [IndirmeKaydi]) -> [DosyaVarligi] {
        kayitlar.filter { $0.durum == "done" && $0.dosya != nil }.map { DosyaVarligi(id: $0.id, ad: $0.ad, tur: $0.tur) }
    }
}

nonisolated struct DosyaSorgusu: EntityStringQuery {
    init() {}

    @MainActor func entities(for identifiers: [DosyaVarligi.ID]) async throws -> [DosyaVarligi] {
        let hepsi = DosyaVarligi.listesi(IndirmeYoneticisi.ortak.kayitlar)
        return identifiers.compactMap { k in hepsi.first { $0.id == k } }
    }

    @MainActor func entities(matching string: String) async throws -> [DosyaVarligi] {
        let t = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let hepsi = DosyaVarligi.listesi(IndirmeYoneticisi.ortak.kayitlar)
        guard !t.isEmpty else { return Array(hepsi.suffix(10).reversed()) }
        return Array(hepsi.filter { $0.ad.localizedStandardContains(t) }.suffix(20).reversed())
    }

    @MainActor func suggestedEntities() async throws -> [DosyaVarligi] {
        Array(DosyaVarligi.listesi(IndirmeYoneticisi.ortak.kayitlar).suffix(10).reversed())
    }
}

/// Spotlight'ta seçilen dosya için İndirmeler ekranını açar.
struct DosyayiAcIntent: OpenIntent {
    static let title: LocalizedStringResource = "Dosyayı aç"
    static let description = IntentDescription("Asistan'ın İndirmeler ekranını açar.")

    @Parameter(title: "Dosya") var target: DosyaVarligi

    init() {}
    init(target: DosyaVarligi) { self.target = target }

    @MainActor func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "asistan://indirmeler")!))
    }
}

// MARK: Olgu (yalnız Kestirmeler; Spotlight'a girmez)

nonisolated struct OlguVarligi: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Hafıza bilgisi" }
    static var defaultQuery: OlguSorgusu { OlguSorgusu() }

    let id: UUID
    let metin: String
    let kategori: String

    init(id: UUID, metin: String, kategori: String) {
        self.id = id
        self.metin = metin
        self.kategori = kategori
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(metin)", subtitle: "\(kategori)")
    }
}

nonisolated struct OlguSorgusu: EntityStringQuery {
    init() {}

    @MainActor func entities(for identifiers: [OlguVarligi.ID]) async throws -> [OlguVarligi] {
        let hepsi = Self.etkinler(HafizaDeposu(baglam: HafizaDeposu.paylasilanKap.mainContext))
        return identifiers.compactMap { k in hepsi.first { $0.id == k } }
    }

    @MainActor func entities(matching string: String) async throws -> [OlguVarligi] {
        Self.ara(string, olgular: Self.etkinler(HafizaDeposu(baglam: HafizaDeposu.paylasilanKap.mainContext)))
    }

    @MainActor func suggestedEntities() async throws -> [OlguVarligi] {
        Array(Self.etkinler(HafizaDeposu(baglam: HafizaDeposu.paylasilanKap.mainContext)).suffix(10).reversed())
    }

    /// Yalnız etkin (onaylı, süresi dolmamış) olgular; onay bekleyen ya da çelişkili olgu dışarı verilmez.
    @MainActor static func etkinler(_ depo: HafizaDeposu) -> [OlguVarligi] {
        let simdi = Date.now
        return depo.olgular().filter { HafizaDeposu.etkinMi($0, simdi: simdi) }
            .map { OlguVarligi(id: $0.kimlik, metin: $0.metin, kategori: $0.kategori ?? "diger") }
    }

    /// Saf: bütün terimleri (HafizaIndeksi kuralıyla normalleştirilmiş) içeren olgular, en çok 20.
    static func ara(_ sorgu: String, olgular: [OlguVarligi]) -> [OlguVarligi] {
        let terimler = HafizaIndeksi.terimler(sorgu)
        guard !terimler.isEmpty else { return [] }
        return Array(olgular.filter { o in
            let n = HafizaIndeksi.normalize(o.metin)
            return terimler.allSatisfy { n.contains($0.count > 6 ? String($0.prefix(max(5, $0.count - 3))) : $0) }
        }.prefix(20))
    }
}

/// Kestirmeler: "Asistan hafızasında bul". Uygulamayı açmaz; yalnız etkin olguları döndürür (salt okunur).
struct HafizadaBulIntent: AppIntent {
    static let title: LocalizedStringResource = "Asistan hafızasında bul"
    static let description = IntentDescription("Asistan'ın hatırladığı bilgilerde arama yapar ve bulunanları döndürür.")
    static let openAppWhenRun = false

    @Parameter(title: "Aranacak", requestValueDialog: IntentDialog("Hafızada ne arayayım?"))
    var metin: String

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<[OlguVarligi]> & ProvidesDialog {
        let bulunan = OlguSorgusu.ara(metin, olgular: OlguSorgusu.etkinler(HafizaDeposu(baglam: HafizaDeposu.paylasilanKap.mainContext)))
        let dialog = bulunan.isEmpty ? "Hafızada bununla ilgili bir bilgi yok." : bulunan.prefix(3).map(\.metin).joined(separator: " · ")
        return .result(value: bulunan, dialog: IntentDialog(stringLiteral: String(dialog.prefix(600))))
    }
}

// MARK: Spotlight indeksi

/// Sohbet ve dosya varlıklarını adlı Spotlight indeksine yazar. Bütün işler tek sırada (FIFO) yürür: hızlı ard arda gelen
/// ad değiştirme + silme yer değiştirmesin. Test sürecinde (XCTest / ASISTAN_TEST) hiçbir şey yazılmaz.
@MainActor
enum AsistanSpotlight {
    nonisolated static let indeksAdi = "asistan"
    /// Tam yeniden kurulum sürüm anahtarı: biçim değişince `surum` artırılır, ilk açılışta bir kez bütün sohbetler yazılır.
    nonisolated static let surumAnahtari = "spotlight.surumV1"
    nonisolated static let surum = 1
    /// `Ayarlar.spotlightIcerik` ile aynı anahtar (Ayarlar'a erişimi olmayan yollar buradan okur).
    nonisolated static let icerikAnahtari = "ayar.spotlightIcerikV1"
    nonisolated static let ozetSiniri = 200
    /// Tam kurulumda yazılan en çok sohbet sayısı.
    nonisolated static let enFazlaSohbet = 300

    nonisolated static var kapali: Bool { OnayKapisi.testte }
    nonisolated static var icerikDahil: Bool { UserDefaults.standard.bool(forKey: icerikAnahtari) }

    private static var sonIs: Task<Void, Never>?

    /// Saf: Spotlight öğesinin öznitelikleri. Varsayılan yalnız başlık; `icerikDahil` açıksa içerik ilk 200 karakterle
    /// `contentDescription` olur. `temel` verilirse (varlığın `defaultAttributeSet`'i) onun üstüne yazılır.
    nonisolated static func ozellikler(baslik: String, icerik: String?, icerikDahil: Bool,
                                       temel: CSSearchableItemAttributeSet? = nil) -> CSSearchableItemAttributeSet {
        let a = temel ?? CSSearchableItemAttributeSet(contentType: .text)
        a.title = baslik
        a.displayName = baslik
        if icerikDahil, let i = icerik?.trimmingCharacters(in: .whitespacesAndNewlines), !i.isEmpty {
            a.contentDescription = String(i.prefix(ozetSiniri))
        } else if temel == nil {
            a.contentDescription = nil
        }
        return a
    }

    /// Saf: Spotlight dokunuşundaki öğe kimliğinden (ne biçimde gelirse gelsin) ilk UUID.
    nonisolated static func kimlikAyikla(_ s: String?) -> UUID? {
        guard let s else { return nil }
        if let u = UUID(uuidString: s) { return u }
        guard let r = s.range(of: #"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"#, options: .regularExpression) else { return nil }
        return UUID(uuidString: String(s[r]))
    }

    /// Sohbetin ilk kullanıcı mesajı (içerik özeti için).
    static func ilkKullaniciMesaji(_ s: Sohbet) -> String? {
        s.mesajlar.filter { $0.rol == .kullanici }.min { $0.zaman < $1.zaman }?.metin
    }

    static func varlik(_ s: Sohbet, icerikDahil: Bool, ilkMesaj: String? = nil) -> SohbetVarligi {
        let ozet = icerikDahil ? (ilkMesaj ?? ilkKullaniciMesaji(s)).map { String($0.prefix(ozetSiniri)) } : nil
        return SohbetVarligi(id: s.kimlik, baslik: s.baslik, tarih: HafizaDeposu.sonZaman(s), ozet: ozet)
    }

    /// Henüz adı konmamış boş sohbet ("Yeni sohbet") Spotlight'a yazılmaz.
    static func yazilir(_ s: Sohbet) -> Bool { !(s.baslik == "Yeni sohbet" && s.mesajlar.isEmpty) }

    /// Sırayı korur: her iş bir öncekinin bitmesini bekler; ağır iş ana iş parçacığı dışında yürür.
    private static func sirala(_ is_: @escaping @Sendable () async -> Void) {
        let onceki = sonIs
        sonIs = Task.detached(priority: .utility) {
            await onceki?.value
            await is_()
        }
    }

    static func sohbetDegisti(_ s: Sohbet, ilkMesaj: String? = nil) {
        guard !kapali, yazilir(s) else { return }
        let v = varlik(s, icerikDahil: icerikDahil, ilkMesaj: ilkMesaj)
        sirala { await indeksle(sohbetler: [v]) }
    }

    static func sohbetSilindi(_ kimlik: UUID) {
        guard !kapali else { return }
        sirala {
            let i = CSSearchableIndex(name: indeksAdi)
            try? await i.deleteAppEntities(identifiedBy: [kimlik], ofType: SohbetVarligi.self)
        }
    }

    static func sohbetlerSilindi(_ kimlikler: [UUID]) {
        guard !kapali, !kimlikler.isEmpty else { return }
        sirala {
            let i = CSSearchableIndex(name: indeksAdi)
            try? await i.deleteAppEntities(identifiedBy: kimlikler, ofType: SohbetVarligi.self)
        }
    }

    /// İndirilen dosyaların listesini baştan yazar (sahne arka plana geçince).
    static func dosyalariYenile(_ kayitlar: [IndirmeKaydi]) {
        guard !kapali else { return }
        let v = DosyaVarligi.listesi(kayitlar)
        sirala {
            let i = CSSearchableIndex(name: indeksAdi)
            try? await i.deleteAppEntities(ofType: DosyaVarligi.self)
            if !v.isEmpty { try? await i.indexAppEntities(v) }
        }
    }

    /// Bütün sohbetleri yeniden yazar. Sürüm anahtarı güncelse bir şey yapmaz; `zorla` (içerik ayarı değişti, elle yeniden
    /// kurulum) anahtarı yok sayar.
    static func tamYenile(depo: HafizaDeposu, zorla: Bool = false) {
        guard !kapali else { return }
        guard zorla || UserDefaults.standard.integer(forKey: surumAnahtari) != surum else { return }
        let icerik = icerikDahil
        let v = depo.sonSohbetler(enFazlaSohbet).filter(yazilir).map { varlik($0, icerikDahil: icerik) }
        sirala {
            let i = CSSearchableIndex(name: indeksAdi)
            try? await i.deleteAppEntities(ofType: SohbetVarligi.self)
            await indeksle(sohbetler: v)
            UserDefaults.standard.set(surum, forKey: surumAnahtari)
        }
    }

    /// Asistan'ın bütün Spotlight öğelerini siler. Sürüm anahtarı güncel kalır (bir sonraki açılış her şeyi geri yazmaz);
    /// yeni ve değişen sohbetler yine eklenir, hepsini geri eklemek için `tamYenile(zorla: true)`.
    static func hepsiniSil() {
        guard !kapali else { return }
        sirala {
            try? await CSSearchableIndex(name: indeksAdi).deleteAllSearchableItems()
            UserDefaults.standard.set(surum, forKey: surumAnahtari)
        }
    }

    nonisolated private static func indeksle(sohbetler v: [SohbetVarligi]) async {
        guard !v.isEmpty else { return }
        let i = CSSearchableIndex(name: indeksAdi)
        // Büyük listeyi 100'lük parçalarla yaz (tek çağrıda yüzlerce öğe sistem sınırına takılabilir).
        var bas = 0
        while bas < v.count {
            if Task.isCancelled { return }
            let parca = Array(v[bas..<min(bas + 100, v.count)])
            try? await i.indexAppEntities(parca)
            bas += 100
        }
    }
}
