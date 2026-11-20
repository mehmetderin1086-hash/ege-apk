import Testing
import Foundation
import SwiftData
@testable import Asistan

/// P3.8 (A-G): olgu durumu (onay/çelişki), geçerlilik sonu, yalnız kullanıcı cümlesi denetimi, talimat tekrarının düşülmesi,
/// RRF ve bge-m3 yanıt çözücü, V1 → V2 şema geçişi. Hepsi bellek içi ya da geçici klasör; ağ/izin/model yok.
@Suite("P3.8 hafıza kalitesi", .serialized) @MainActor
struct Gelistirme_P3_8_HafizaKalitesiTestleri {
    let temizlik = TestTemizligi()
    nonisolated(unsafe) private static var kaplar: [ModelContainer] = []   // context'ten uzun yaşamalı (yoksa SwiftData çöker)
    private func depo() -> HafizaDeposu {
        let k = HafizaDeposu.kapOlustur(bellekte: true); Self.kaplar.append(k)
        return HafizaDeposu(baglam: k.mainContext)
    }
    private func klasor() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appending(path: "p38-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return temizlik.gecici(d)
    }

    // MARK: B) biçim

    @Test func ucAlanliBicimTarihiCozer() throws {
        let c = OlguBicimi.coz("[tarih:3:2026-11-01] Kullanıcı bu dönem nöbetçi öğretmen")
        #expect(c.kategori == .tarih && c.onem == 3 && c.metin == "Kullanıcı bu dönem nöbetçi öğretmen")
        let bitis = try #require(c.bitis)
        var dc = DateComponents(); dc.year = 2026; dc.month = 11; dc.day = 2
        #expect(bitis == Calendar.current.date(from: dc), "bitiş, verilen günün sonu (ertesi gün 00:00)")
        #expect(OlguBicimi.coz("[tercih:4] Kullanıcı çayı şekersiz içer").bitis == nil, "iki alanlı biçim kalıcıdır")
        let hatali = OlguBicimi.coz("[tarih:3:2026-13-45] Kullanıcı yarın sınavda")
        #expect(hatali.bitis == nil && hatali.kategori == .tarih && hatali.onem == 3, "geçersiz tarih yok sayılır, öbür alanlar kalır")
        #expect(OlguBicimi.coz("[tarih:3:2026-02-30] x").bitis == nil)
        #expect(OlguBicimi.coz("[tarih:3:yarin] x").bitis == nil)
    }

    // MARK: C) yalnız kullanıcı cümlesi

    @Test func kullanicininSoylemedigiOlguReddedilir() {
        #expect(!OlguCikarici.kullanicidanMi("[yer:3] Kullanıcı Ankara'da yaşıyor", kullanici: "Bugün hava nasıl olacak, dışarı çıkacağım"))
        #expect(OlguCikarici.kullanicidanMi("[yer:3] Kullanıcı Ankara'da yaşıyor", kullanici: "Ben Ankara'ya geçen yıl taşındım"))
        #expect(OlguCikarici.kullanicidanMi("Kullanıcının kedisinin adı Pamuk", kullanici: "kedimin adı pamuk, mamasını unuttum"))
        #expect(!OlguCikarici.kullanicidanMi("Kullanıcı", kullanici: "kullanıcı benim"), "terimsiz olgu reddedilir")
    }

    // MARK: D) onay ve çelişki

    @Test func cikarimSaglikOlgusuOnayBekler() throws {
        let d = depo()
        let o = d.hatirlaZengin("[saglik:4] Kullanıcının fıstık alerjisi var", kaynak: "cikarim")
        #expect(o?.durum == OlguDurumu.bekliyor)
        #expect(d.talimatOlgulari().isEmpty, "onay bekleyen olgu talimata girmez")
        #expect(d.etkinOlgular().isEmpty && d.bekleyenOlgular().count == 1)
        // Kullanıcı kaynaklı ve sıradan çıkarım onay istemez.
        #expect(d.hatirlaZengin("[saglik:4] Kullanıcının tansiyonu düşük", kaynak: "kullanici")?.durum == nil)
        #expect(d.hatirlaZengin("[tercih:3] Kullanıcı sabah çayını demli içer", kaynak: "cikarim")?.durum == nil)
        #expect(d.hatirlaZengin("[proje:5] Kullanıcı biyoloji kitabı yazıyor", kaynak: "cikarim")?.durum == OlguDurumu.bekliyor, "önem 5 onay ister")
        let ilk = try #require(o)
        #expect(d.olguOnayla(ilk.kimlik))
        #expect(d.talimatOlgulari().contains { $0.contains("fıstık") }, "onaylanan olgu talimata girer")
        let red = try #require(d.bekleyenOlgular().first)
        #expect(d.olguReddet(red.kimlik) && !d.olgular().contains { $0.kimlik == red.kimlik })
        #expect(Gelistirme_P3_8_HafizaKalitesiTestleri.onayKurali())
    }

    private static func onayKurali() -> Bool {
        HafizaDeposu.onayGerekir(kaynak: "cikarim", kategori: .kisi, onem: 3)
            && !HafizaDeposu.onayGerekir(kaynak: "asistan", kategori: .saglik, onem: 5)
            && !HafizaDeposu.onayGerekir(kaynak: "cikarim", kategori: .yer, onem: 4)
    }

    @Test func kullaniciAdresiyleCelisenCikarimCeliskiOlur() throws {
        let d = depo()
        let eski = try #require(d.hatirlaZengin("Kullanıcının adresi Kadıköy", kaynak: "kullanici", kategori: .yer))
        let yeni = try #require(d.hatirlaZengin("Kullanıcının adresi Üsküdar", kaynak: "cikarim", kategori: .yer))
        #expect(yeni.kimlik != eski.kimlik && yeni.durum == OlguDurumu.celiski, "eski yerinde kalır, yeni çelişki olarak eklenir")
        #expect(eski.durum == nil && eski.metin.contains("Kadıköy"))
        #expect(d.celiskiAdayi(yeni)?.kimlik == eski.kimlik)
        #expect(!d.talimatOlgulari().contains { $0.contains("Üsküdar") })
        #expect(OlguOnayCipi.metin(yeni, eski: eski).contains("Önceki bilgiyle çelişiyor") && OlguOnayCipi.metin(yeni, eski: eski).contains("Kadıköy"))
        #expect(d.celiskiCoz(yeni: yeni.kimlik, eski: eski.kimlik, yeniDogru: true))
        #expect(d.olgular().map(\.metin) == ["Kullanıcının adresi Üsküdar"] && d.olgular().first?.durum == nil)

        let d2 = depo()
        let e2 = try #require(d2.hatirlaZengin("Kullanıcının adresi Kadıköy", kaynak: "kullanici", kategori: .yer))
        let y2 = try #require(d2.hatirlaZengin("Kullanıcının adresi Üsküdar", kaynak: "cikarim", kategori: .yer))
        #expect(d2.celiskiCoz(yeni: y2.kimlik, eski: e2.kimlik, yeniDogru: false))
        #expect(d2.olgular().map(\.metin) == ["Kullanıcının adresi Kadıköy"])
    }

    @Test func sabitlemekOnaydir() throws {
        let d = depo()
        let o = try #require(d.hatirlaZengin("[kisi:4] Kullanıcının kızı Elif", kaynak: "cikarim"))
        #expect(o.durum == OlguDurumu.bekliyor)
        d.olguAyarla(o.kimlik, sabit: true)
        #expect(o.durum == nil && d.talimatOlgulari().contains { $0.contains("Elif") })
    }

    @Test func onayCipiMetni() {
        #expect(OlguOnayCipi.metin(yeni: "Kullanıcının kızı Elif", celiski: false, eski: nil) == "Hatırlayayım mı: Kullanıcının kızı Elif")
        #expect(OlguOnayCipi.metin(yeni: "B", celiski: true, eski: "A") == "Önceki bilgiyle çelişiyor: B (önceki: A)")
        #expect(OlguOnayCipi.metin(yeni: "B", celiski: true, eski: nil) == "Önceki bilgiyle çelişiyor: B")
    }

    // MARK: A) geçerlilik sonu

    @Test func suresiDolanEtkinDegilVeTemizlenir() {
        let d = depo()
        let gecmis = d.hatirlaZengin("[tarih:3:2020-01-01] Kullanıcı bu hafta nöbetçi", kaynak: "kullanici")
        #expect(gecmis?.gecerlilikSonu != nil)
        let gelecek = d.hatirlaZengin("[tarih:3:2099-12-31] Kullanıcı bu dönem 9-A'nın danışmanı", kaynak: "kullanici")
        #expect(d.etkinOlgular().map(\.kimlik) == [gelecek?.kimlik].compactMap { $0 }, "süresi dolan etkin sayılmaz")
        #expect(!d.talimatOlgulari().contains { $0.contains("nöbetçi") })
        #expect(d.suresiDolanlariTemizle() == 1)
        #expect(d.olgular().count == 1 && d.olgular().first?.kimlik == gelecek?.kimlik)
        #expect(HafizaDeposu.etkinMi(durum: nil, gecerlilikSonu: nil, simdi: .now))
        #expect(HafizaDeposu.etkinMi(durum: OlguDurumu.onayli, gecerlilikSonu: .distantFuture, simdi: .now))
        #expect(!HafizaDeposu.etkinMi(durum: OlguDurumu.celiski, gecerlilikSonu: nil, simdi: .now))
    }

    // MARK: E) talimattakiler yinelenmez

    @Test func talimattakiOlguGeriCagirmadaDusulur() throws {
        let d = depo()
        // HafizaDeposu/geriCagir ortak (disk) indeksi kullanır; indeks açılamıyorsa test sessizce geçmesin, açıksa iz bırakmasın.
        try #require(HafizaIndeksi.ortak.hazir, "ortak hafıza indeksi açılamadı")
        var eklenenler: [UUID] = []
        defer { for k in eklenenler { HafizaIndeksi.ortak.sil(kimlik: k.uuidString) } }
        let mama = try #require(d.hatirla("Kullanıcı Pamuk için yaş mama alır"))
        eklenenler.append(mama.kimlik)
        d.olguAyarla(mama.kimlik, onem: 1)
        mama.olusturma = Date(timeIntervalSinceNow: -100_000)   // en eski ve önemsiz: talimata girmez
        let kedi = try #require(d.hatirlaZengin("[kisi:5] Kullanıcının kedisi Pamuk", kaynak: "kullanici"))
        eklenenler.append(kedi.kimlik)
        for i in 0..<61 {
            let o = try #require(d.hatirla("Kullanıcı dolgu olgusu \(String(UnicodeScalar(UInt8(65 + i % 26))))\(i)"))
            eklenenler.append(o.kimlik)
            d.olguAyarla(o.kimlik, onem: 1)
        }
        try d.baglam.save()
        let talimat = Set(d.talimatSecimi().map(\.kimlik))
        #expect(talimat.count == 60 && talimat.contains(kedi.kimlik) && !talimat.contains(mama.kimlik))
        let dusulmus = d.geriCagir("Pamuk mama", olguAdet: 6, gecmisAdet: 0, isaretle: false).olgular.map(\.kimlik)
        #expect(!dusulmus.contains(kedi.kimlik), "talimattaki olgu yinelenmez")
        #expect(dusulmus.contains(mama.kimlik))
        let hepsi = d.geriCagir("Pamuk mama", olguAdet: 6, gecmisAdet: 0, isaretle: false, talimattakileriDus: false).olgular.map(\.kimlik)
        #expect(hepsi.contains(kedi.kimlik) && hepsi.contains(mama.kimlik))
    }

    @Test func ilgiliYalnizEtkinOlgulardan() {
        let d = depo()
        _ = d.hatirla("Olgu bir")
        _ = d.hatirlaZengin("[saglik:3] Kullanıcının astımı var", kaynak: "cikarim")
        #expect(d.ilgili("herhangi", k: 5).map(\.metin) == ["Olgu bir"])
    }

    // MARK: G) RRF, bge-m3 çözücü, boyut denetimi

    @Test func rrfSirasiVeFormulu() {
        let p = HafizaDeposu.rrf([["a", "b"], ["a", "c"]])
        #expect(abs((p["a"] ?? 0) - 2.0 / 61.0) < 1e-12)
        #expect(abs((p["b"] ?? 0) - 1.0 / 62.0) < 1e-12 && abs((p["c"] ?? 0) - 1.0 / 62.0) < 1e-12)
        let q = HafizaDeposu.rrf([["x", "y"], ["y", "z"]])
        #expect((q["y"] ?? 0) > (q["x"] ?? 0), "iki listede de üstte olan, tek listede birinci olanı geçer")
        #expect(abs((HafizaDeposu.rrf([["a"]], k: 10)["a"] ?? 0) - 1.0 / 11.0) < 1e-12)
        #expect(HafizaDeposu.rrf([["a", "a"]])["a"] == 1.0 / 61.0, "aynı listede yinelenen kimlik bir kez sayılır")
    }

    private func vektorJSON(_ v: [Float]) -> String { "[" + v.map { String($0) }.joined(separator: ",") + "]" }

    @Test func uzakGomlemciIkiBicimiCozer() throws {
        let v = [Float](repeating: 0, count: 1023) + [2]
        let a = try UzakGomlemci.coz(Data("{\"embeddings\": [\(vektorJSON(v)), \(vektorJSON(v.reversed()))]}".utf8))
        #expect(a.count == 2 && a[0].count == 1024 && a[0][1023] == 1 && a[1][0] == 1, "birim uzunluğa getirilir")
        let b = try UzakGomlemci.coz(Data("{\"data\": [{\"index\": 1, \"embedding\": \(vektorJSON(v.reversed()))}, {\"index\": 0, \"embedding\": \(vektorJSON(v))}]}".utf8))
        #expect(b.count == 2 && b[0][1023] == 1 && b[1][0] == 1, "OpenAI biçimi index'e göre sıralanır")
        #expect(throws: UzakGomlemci.Hata.boyut(512)) { try UzakGomlemci.coz(Data("{\"embeddings\": [\(vektorJSON([Float](repeating: 1, count: 512)))]}".utf8)) }
        #expect(throws: UzakGomlemci.Hata.bicim) { try UzakGomlemci.coz(Data("{\"sonuc\": []}".utf8)) }
    }

    @Test func eskiBoyutluVektorYokSayilir() throws {
        let eski = [Float](repeating: 0.1, count: 512), yeni = [Float](repeating: 0.1, count: 1024)
        #expect(UzakGomlemci.gecerli(Gomlemci.veri(eski)) == nil)
        #expect(UzakGomlemci.gecerli(Gomlemci.veri(yeni))?.count == 1024)
        #expect(UzakGomlemci.gecerli(nil) == nil)
        let dosya = try klasor().appending(path: "mv.plist")
        let mv = MesajVektorleri(dosya: dosya)
        let a = UUID(), b = UUID()
        mv.ekle(a, eski); mv.ekle(b, yeni)
        #expect(!mv.gecerliVar(a) && mv.gecerliVektor(a) == nil, "512 boyutlu NL gömmesi yeniden doldurulacak sayılır")
        #expect(mv.gecerliVar(b) && mv.gecerliVektor(b)?.count == 1024)
        // Ayar UserDefaults.standard'tan okunur (enjeksiyon yok): önceki değer geri konur.
        let ayarOnceki = UserDefaults.standard.object(forKey: UzakGomlemci.ayarAnahtari)
        defer {
            if let ayarOnceki { UserDefaults.standard.set(ayarOnceki, forKey: UzakGomlemci.ayarAnahtari) }
            else { UserDefaults.standard.removeObject(forKey: UzakGomlemci.ayarAnahtari) }
        }
        UserDefaults.standard.set(false, forKey: UzakGomlemci.ayarAnahtari)
        #expect(!UzakGomlemci.etkin, "ayar kapalıyken etkin değil")
        UserDefaults.standard.set(true, forKey: UzakGomlemci.ayarAnahtari)
        #expect(UzakGomlemci.etkin == (Gizli.vekilTaban != nil && Gizli.vekilToken != nil), "ayar açıkken etkinlik vekil kimliğine bağlı")
    }

    // MARK: şema V1 → V2

    @Test func v1DeposuV2IleAcilir() throws {
        let d = try klasor(), store = d.appending(path: "Asistan.store")
        do {
            let v1 = Schema(versionedSchema: AsistanSemaV1.self)
            let kap = try ModelContainer(for: v1, configurations: [ModelConfiguration("Asistan", schema: v1, url: store)])
            Self.kaplar.append(kap)
            let b = kap.mainContext
            let s = AsistanSemaV1.Sohbet(baslik: "Eski sohbet"); b.insert(s)
            b.insert(AsistanSemaV1.Mesaj(rolHam: "kullanici", metin: "Eski mesaj", sohbet: s))
            let o = AsistanSemaV1.Olgu(metin: "Eski olgu"); o.onem = 4; o.sabit = true; b.insert(o)
            try b.save()
        }
        let s = HafizaDeposu.kapAc(ayar: HafizaDeposu.diskAyari(klasor: d))
        Self.kaplar.append(s.kap)
        #expect(s.durum == .normal, "V1 deposu hafif geçişle açılmalı (veri bellekte kalmamalı)")
        let b = ModelContext(s.kap)
        let olgular = try b.fetch(FetchDescriptor<Olgu>())
        #expect(olgular.count == 1 && olgular.first?.metin == "Eski olgu" && olgular.first?.onem == 4 && olgular.first?.sabit == true)
        #expect(olgular.first?.durum == nil && olgular.first?.gecerlilikSonu == nil, "eski olgu onaylı ve süresiz")
        #expect(try b.fetch(FetchDescriptor<Mesaj>()).first?.sohbet?.baslik == "Eski sohbet")
    }
}
