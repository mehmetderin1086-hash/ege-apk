import Testing
import Foundation
import SwiftData
import SQLite3
@testable import Asistan

/// P2.1: hafıza açılmazsa çökmesin — kurtarma, günlük yedek, sürümlü şema. Hepsi geçici klasörlerde; ağ/izin/model yok.
@Suite("P2.1 hafıza kurtarma") @MainActor
struct HafizaKurtarmaTestleri {
    nonisolated(unsafe) private static var kaplar: [ModelContainer] = []   // context'ten uzun yaşamalı (yoksa SwiftData çöker)
    private struct KurucuHatasi: Error {}

    private func klasor() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appending(path: "p21-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    private func depoYolu(_ d: URL) -> URL { d.appending(path: "Asistan.store") }

    private func ac(_ d: URL, kurucu: HafizaDeposu.Kurucu? = nil,
                    tani: ((URL, any Error) -> HafizaKurtarma.Tani)? = nil) -> (kap: ModelContainer, durum: HafizaDeposu.AcilisDurumu) {
        let s = HafizaDeposu.kapAc(ayar: HafizaDeposu.diskAyari(klasor: d), kurucu: kurucu, tani: tani)
        Self.kaplar.append(s.kap)
        return s
    }
    private let basarisiz: HafizaDeposu.Kurucu = { _, _ in throw KurucuHatasi() }

    /// Diskte içinde verilen olgular olan bir depo kurar; kabı döndürür (yaşamı `kaplar`'da).
    private func olguluDepo(_ d: URL, _ metinler: [String]) throws -> ModelContainer {
        let (kap, durum) = ac(d)
        #expect(durum == .normal)
        let b = kap.mainContext
        for m in metinler { b.insert(Olgu(metin: m)) }
        try b.save()
        return kap
    }

    private func olguMetinleri(_ kap: ModelContainer) throws -> [String] {
        try ModelContext(kap).fetch(FetchDescriptor<Olgu>()).map(\.metin).sorted()
    }

    private func mevcut(_ u: URL) -> Bool { FileManager.default.fileExists(atPath: u.path) }

    // MARK: (1) bozuk depo

    @Test func bozukDepoKurtarilir() throws {
        let d = try klasor(), store = depoYolu(d)
        for u in HafizaKurtarma.dosyalar(store) {
            try Data((0..<9000).map { _ in UInt8.random(in: .min ... .max) }).write(to: u)
        }
        #expect(HafizaKurtarma.tani(store: store) == .bozuk)
        let (kap, durum) = ac(d)
        guard case .kurtarildi(let ad) = durum else { Issue.record("bozuk depo kurtarılmalıydı: \(durum)"); return }
        let kurtarma = HafizaKurtarma.kurtarmaKlasoru(store).appending(path: ad)
        for u in HafizaKurtarma.dosyalar(store) { #expect(mevcut(kurtarma.appending(path: u.lastPathComponent)), "\(u.lastPathComponent) taşınmalı") }
        #expect(HafizaKurtarma.kurtarmaKopyalari(store: store).first?.neden == "bozuk")
        let b = kap.mainContext
        b.insert(Sohbet(baslik: "Kurtarma sonrası"))
        try b.save()
        #expect(try ModelContext(kap).fetch(FetchDescriptor<Sohbet>()).map(\.baslik) == ["Kurtarma sonrası"])
    }

    // MARK: (2) sürümsüz / eski sürümlü depo → bugünkü şema

    /// Eski depo bugünkü (V3) üst düzey modellerle DEĞİL, dondurulmuş V1 kopyalarıyla yazılır; böylece V1 → V3 geçişi gerçekten sınanır.
    @Test func semasizV1DepoBugunkuSemayaGecer() throws {
        let d = try klasor(), store = depoYolu(d)
        let ekVerisi = EkKalici.kodla([], gorselAdlari: ["ornek-gorsel.jpg"])
        #expect(ekVerisi != nil)
        do {
            // Sürümsüz Schema: eski uygulamanın yazdığı biçim (VersionedSchema/migrationPlan yok).
            let eski = Schema([AsistanSemaV1.Sohbet.self, AsistanSemaV1.Mesaj.self, AsistanSemaV1.Olgu.self])
            let kap = try ModelContainer(for: eski, configurations: [ModelConfiguration("Asistan", schema: eski, url: store)])
            Self.kaplar.append(kap)
            let b = kap.mainContext
            let s = AsistanSemaV1.Sohbet(baslik: "Sabit sohbet"); s.sabit = true; b.insert(s)
            let m = AsistanSemaV1.Mesaj(rolHam: "kullanici", metin: "Görselli mesaj", sohbet: s); m.ekVerisi = ekVerisi; b.insert(m)
            let o = AsistanSemaV1.Olgu(metin: "Önemli olgu"); o.onem = 5; o.sabit = true; o.kategori = "kisi"; o.kullanimSayisi = 3; b.insert(o)
            try b.save()
        }
        _ = try eskiDepoyuDogrula(d, ekVerisi: ekVerisi)
    }

    /// V2 sürüm kimlikli depo da V3'e hafif geçişle açılır; V2'ye özgü alanlar (durum, gecerlilikSonu) korunur.
    @Test func v2DepoBugunkuSemayaGecer() throws {
        let d = try klasor(), store = depoYolu(d)
        let ekVerisi = EkKalici.kodla([], gorselAdlari: ["ornek-gorsel.jpg"])
        let bitis = Date(timeIntervalSince1970: 1_900_000_000)
        do {
            let v2 = Schema(versionedSchema: AsistanSemaV2.self)
            let kap = try ModelContainer(for: v2, configurations: [ModelConfiguration("Asistan", schema: v2, url: store)])
            Self.kaplar.append(kap)
            let b = kap.mainContext
            let s = AsistanSemaV2.Sohbet(baslik: "Sabit sohbet"); s.sabit = true; b.insert(s)
            let m = AsistanSemaV2.Mesaj(rolHam: "kullanici", metin: "Görselli mesaj", sohbet: s); m.ekVerisi = ekVerisi; b.insert(m)
            let o = AsistanSemaV2.Olgu(metin: "Önemli olgu"); o.onem = 5; o.sabit = true; o.kategori = "kisi"; o.kullanimSayisi = 3
            o.durum = "bekliyor"; o.gecerlilikSonu = bitis; b.insert(o)
            try b.save()
        }
        let kap = try eskiDepoyuDogrula(d, ekVerisi: ekVerisi)
        let olgu = try #require(try ModelContext(kap).fetch(FetchDescriptor<Olgu>()).first)
        #expect(olgu.durum == "bekliyor" && olgu.gecerlilikSonu == bitis)
    }

    /// Eski sürümlü depoyu bugünkü kapla açar: durum normal (kurtarma/bellek yok), alanlar okunur, yeni alan nil, yeni yazım sürer.
    private func eskiDepoyuDogrula(_ d: URL, ekVerisi: Data?) throws -> ModelContainer {
        let store = depoYolu(d)
        let (kap, durum) = ac(d)
        #expect(durum == .normal)
        #expect(!mevcut(HafizaKurtarma.kurtarmaKlasoru(store)), "sağlam eski depo kurtarmaya taşınmamalı")
        let b = ModelContext(kap)
        let sohbetler = try b.fetch(FetchDescriptor<Sohbet>())
        #expect(sohbetler.count == 1 && sohbetler.first?.sabit == true && sohbetler.first?.baslik == "Sabit sohbet")
        let mesajlar = try b.fetch(FetchDescriptor<Mesaj>())
        #expect(mesajlar.count == 1 && mesajlar.first?.ekVerisi == ekVerisi && mesajlar.first?.sohbet?.baslik == "Sabit sohbet")
        #expect(mesajlar.first?.kontrol == nil, "V3'te gelen alan eski mesajda nil açılır")
        let olgular = try b.fetch(FetchDescriptor<Olgu>())
        #expect(olgular.count == 1)
        #expect(olgular.first?.onem == 5 && olgular.first?.sabit == true && olgular.first?.kategori == "kisi" && olgular.first?.kullanimSayisi == 3)
        // Geçişten sonra yeni alanlarla yazım çalışır.
        let yeni = Mesaj(rol: .asistan, metin: "Geçiş sonrası", sohbet: sohbetler.first); yeni.kontrol = "Denetim: tamam"
        b.insert(yeni)
        try b.save()
        #expect(try ModelContext(kap).fetch(FetchDescriptor<Mesaj>()).count == 2)
        return kap
    }

    // MARK: (3) günlük yedek

    @Test func gunlukYedekGundeBirVeYedisiniTutar() throws {
        let d = try klasor(), store = depoYolu(d)
        let (kap, _) = ac(d)
        let b = kap.mainContext
        let s = Sohbet(); b.insert(s)
        b.insert(Mesaj(rol: .kullanici, metin: "yedeklenecek mesaj", sohbet: s))
        try b.save()
        let yk = HafizaKurtarma.yedekKlasoru(store)
        var takvim = Calendar(identifier: .gregorian); takvim.timeZone = .current
        let bas = takvim.date(from: DateComponents(year: 2026, month: 3, day: 1, hour: 12))!
        let gunler = (0..<9).map { takvim.date(byAdding: .day, value: $0, to: bas)! }
        var son: URL?
        for t in gunler {
            son = HafizaKurtarma.gunlukYedek(store: store, klasor: yk, simdi: t)
            #expect(son != nil)
        }
        let liste = HafizaKurtarma.yedekler(klasor: yk)
        #expect(liste.count == 7)
        #expect(!liste.contains { $0.id == "Asistan-\(HafizaKurtarma.gun(gunler[0])).store" }, "en eski silinmeli")
        #expect(liste.first?.id == "Asistan-\(HafizaKurtarma.gun(gunler[8])).store", "en yenisi önce")
        #expect(HafizaKurtarma.gunlukYedek(store: store, klasor: yk, simdi: gunler[8]) == nil, "aynı gün ikinci yedek yok")
        let yedek = try #require(son)
        #expect((try yedek.resourceValues(forKeys: [.isExcludedFromBackupKey])).isExcludedFromBackup == true)
        // Yedek düz SQLite olarak açılır; WAL'deki mesaj da tutarlı kopyaya girmiş olmalı.
        #expect(satirSayisi(yedek, "ZMESAJ") == 1)
        // "Şimdi yedekle": bugünün yedeğini değiştirir.
        b.insert(Mesaj(rol: .asistan, metin: "ikinci", sohbet: s)); try b.save()
        let zorla = try #require(HafizaKurtarma.gunlukYedek(store: store, klasor: yk, simdi: gunler[8], zorla: true))
        #expect(satirSayisi(zorla, "ZMESAJ") == 2)
        #expect(HafizaKurtarma.yedekler(klasor: yk).count == 7)
    }

    @Test func depoYokkenYedekAlinmaz() throws {
        let d = try klasor(), store = depoYolu(d)
        #expect(HafizaKurtarma.gunlukYedek(store: store, klasor: HafizaKurtarma.yedekKlasoru(store)) == nil)
        #expect(!mevcut(HafizaKurtarma.yedekKlasoru(store)))
    }

    // MARK: (4) geri yükleme

    @Test func geriYuklemeBirSonrakiAcilistaUygulanir() throws {
        let d = try klasor(), store = depoYolu(d)
        let kap = try olguluDepo(d, ["Eski olgu"])
        let yedek = try #require(HafizaKurtarma.gunlukYedek(store: store, klasor: HafizaKurtarma.yedekKlasoru(store)))
        kap.mainContext.insert(Olgu(metin: "Yeni olgu")); try kap.mainContext.save()
        try HafizaKurtarma.geriYuklemeIste(yedek, store: store)
        #expect(HafizaKurtarma.bekleyenIstek(store: store)?.kaynak.hasPrefix("Yedekler/") == true)
        let (yeni, durum) = ac(d)
        #expect(durum == .geriYuklendi)
        #expect(try olguMetinleri(yeni) == ["Eski olgu"])
        #expect(HafizaKurtarma.bekleyenIstek(store: store) == nil, "işaret silinmeli")
        let kopya = try #require(HafizaKurtarma.kurtarmaKopyalari(store: store).first)
        #expect(kopya.neden == "geri-yukleme-oncesi" && kopya.depoVar)
        // Bir sonraki açılış normal; geri yükleme ikinci kez uygulanmaz.
        #expect(ac(d).durum == .normal)
    }

    @Test func disaridakiKaynakGeriYuklenmez() throws {
        let d = try klasor(), store = depoYolu(d)
        let dis = try klasor().appending(path: "baska.store")
        try Data("x".utf8).write(to: dis)
        #expect(throws: HafizaKurtarma.GeriYuklemeHatasi.kaynakDisarida) { try HafizaKurtarma.geriYuklemeIste(dis, store: store) }
        #expect(throws: HafizaKurtarma.GeriYuklemeHatasi.kaynakYok) {
            try HafizaKurtarma.geriYuklemeIste(HafizaKurtarma.yedekKlasoru(store).appending(path: "Asistan-yok.store"), store: store)
        }
        #expect(HafizaKurtarma.bekleyenIstek(store: store) == nil)
    }

    @Test func kaynagiKaybolanIstekBirakilir() throws {
        let d = try klasor(), store = depoYolu(d)
        _ = try olguluDepo(d, ["Kalan olgu"])
        let yedek = try #require(HafizaKurtarma.gunlukYedek(store: store, klasor: HafizaKurtarma.yedekKlasoru(store)))
        try HafizaKurtarma.geriYuklemeIste(yedek, store: store)
        try FileManager.default.removeItem(at: yedek)
        #expect(!HafizaKurtarma.bekleyenGeriYuklemeyiUygula(store: store))
        #expect(HafizaKurtarma.bekleyenIstek(store: store) == nil)
        #expect(mevcut(store), "asıl depo yerinde kalmalı")
        #expect(HafizaKurtarma.kurtarmaKopyalari(store: store).isEmpty)
    }

    // MARK: (5) bellek içi geri dönüş

    @Test func ikiKezBasarisizKurucuBellekteAcar() throws {
        let d = try klasor()
        let (kap, durum) = ac(d, kurucu: basarisiz, tani: { _, _ in .bozuk })
        guard case .bellekte = durum else { Issue.record("bellek içi kap beklenirdi: \(durum)"); return }
        let b = kap.mainContext
        b.insert(Olgu(metin: "Bellekteki olgu")); try b.save()
        #expect(try olguMetinleri(kap) == ["Bellekteki olgu"])
    }

    // MARK: (6) erişilemeyen depo taşınmaz

    @Test func erisilemezDepoTasinmaz() throws {
        let d = try klasor(), store = depoYolu(d)
        _ = try olguluDepo(d, ["Korunacak olgu"])
        let (_, durum) = ac(d, kurucu: basarisiz, tani: { _, _ in .erisilemez })
        #expect(durum == .bellekte(hata: "Telefon kilidi açılınca yeniden aç"))
        #expect(mevcut(store))
        #expect(!mevcut(HafizaKurtarma.kurtarmaKlasoru(store)), "Kurtarma klasörü oluşmamalı")
        #expect(try olguMetinleri(ac(d).kap) == ["Korunacak olgu"])
    }

    @Test func izinHatasiErisilemezSayilir() {
        let alt = NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))
        let ust = NSError(domain: "SwiftData", code: 1, userInfo: [NSUnderlyingErrorKey: alt])
        #expect(HafizaKurtarma.izinHatasi(ust))
        #expect(HafizaKurtarma.izinHatasi(NSError(domain: NSCocoaErrorDomain, code: 513)))
        #expect(!HafizaKurtarma.izinHatasi(NSError(domain: NSCocoaErrorDomain, code: 134110)))
        #expect(HafizaKurtarma.sinifla(SQLITE_NOTADB) == .bozuk && HafizaKurtarma.sinifla(SQLITE_CORRUPT) == .bozuk)
        #expect(HafizaKurtarma.sinifla(SQLITE_CANTOPEN) == .erisilemez && HafizaKurtarma.sinifla(SQLITE_IOERR | (13 << 8)) == .erisilemez)
        #expect(HafizaKurtarma.sinifla(SQLITE_ERROR) == nil)
    }

    // MARK: (7) şema uyumsuz depo kopyalanır

    @Test func semaUyumsuzKopyalanir() throws {
        let d = try klasor(), store = depoYolu(d)
        _ = try olguluDepo(d, ["Şema olgusu"])
        #expect(HafizaKurtarma.tani(store: store) == .semaUyumsuz, "sağlam dosya")
        let (_, durum) = ac(d, kurucu: basarisiz)
        #expect(durum == .bellekte(hata: "Hafıza şeması açılamadı; veriler korunuyor"))
        #expect(mevcut(store), "asıl dosya yerinde kalmalı")
        let kopyalar = HafizaKurtarma.kurtarmaKopyalari(store: store)
        #expect(kopyalar.count == 1 && kopyalar.first?.neden == "sema-uyumsuz" && kopyalar.first?.depoVar == true)
        // Aynı dosyayla ikinci açılış yeni kopya çıkarmaz.
        _ = ac(d, kurucu: basarisiz)
        #expect(HafizaKurtarma.kurtarmaKopyalari(store: store).count == 1)
    }

    // MARK: (8) kurtarma kopyasından geri yükleme

    @Test func kurtarmaKopyasindanGeriYuklenir() throws {
        let d = try klasor(), store = depoYolu(d)
        let kap = try olguluDepo(d, ["Kopyadaki olgu"])
        _ = ac(d, kurucu: basarisiz)   // şema uyumsuz: kopya alınır
        let kopya = try #require(HafizaKurtarma.kurtarmaKopyalari(store: store).first)
        kap.mainContext.insert(Olgu(metin: "Sonradan eklenen")); try kap.mainContext.save()
        try HafizaKurtarma.geriYuklemeIste(kopya.url.appending(path: store.lastPathComponent), store: store)
        #expect(HafizaKurtarma.bekleyenIstek(store: store)?.kaynak.hasPrefix("Kurtarma/") == true)
        let (yeni, durum) = ac(d)
        #expect(durum == .geriYuklendi)
        #expect(try olguMetinleri(yeni) == ["Kopyadaki olgu"])
        #expect(mevcut(kopya.url.appending(path: store.lastPathComponent)), "kaynak kopya yerinde kalmalı")
    }

    @Test func kurtarmaKlasoruYalnizKendiAltindanSilinir() throws {
        let d = try klasor(), store = depoYolu(d)
        _ = try olguluDepo(d, ["x olgu"])
        let k = try HafizaKurtarma.kopyala(store, neden: "bilinmeyen")
        #expect(throws: HafizaKurtarma.GeriYuklemeHatasi.kaynakDisarida) { try HafizaKurtarma.kurtarmaSil(d, store: store) }
        try HafizaKurtarma.kurtarmaSil(k, store: store)
        #expect(!mevcut(k) && mevcut(store))
    }

    // MARK: Yardımcı

    private func satirSayisi(_ dosya: URL, _ tablo: String) -> Int {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(dosya.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return -1 }
        var st: OpaquePointer?
        defer { sqlite3_finalize(st) }
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM \(tablo)", -1, &st, nil) == SQLITE_OK, sqlite3_step(st) == SQLITE_ROW else { return -1 }
        return Int(sqlite3_column_int64(st, 0))
    }
}
