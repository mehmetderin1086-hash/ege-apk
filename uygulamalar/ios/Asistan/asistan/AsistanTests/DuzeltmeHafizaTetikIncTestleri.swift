import Testing
import Foundation
import SwiftData
@testable import Asistan

/// İkinci inceleme düzeltmeleri (hafıza + tetik): okunamayan tetik dosyası, kalıcı olgunun tarihle geçici olmaması,
/// kullanıcı güncellemesinin sabit olguyla çelişki olarak eklenmesi, asistan kaynaklı terim denetimi, Siri kutusu yedeği,
/// okul günü 7 günlük ufuk ve 56 bildirim sınırı, kilitliyken Siri/bildirim yanıtı. Hepsi geçici klasör/bellek; ağ/izin/model yok.
@Suite("İnceleme 2 hafıza + tetik", .serialized) @MainActor
struct DuzeltmeHafizaTetikIncTestleri {
    nonisolated(unsafe) private static var kaplar: [ModelContainer] = []   // context'ten uzun yaşamalı (yoksa SwiftData çöker)
    private func depo() -> HafizaDeposu {
        let k = HafizaDeposu.kapOlustur(bellekte: true); Self.kaplar.append(k)
        return HafizaDeposu(baglam: k.mainContext)
    }
    private func klasor() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appending(path: "inc2-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    private func yedekler(_ d: URL, onEk: String) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: d, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix(onEk) }
    }

    // MARK: Bulgu 2: tetikleyiciler.json çözülemezse

    @Test func bilinmeyenTurluOgeAtlanirSaglamlarKalir() throws {
        let d = try klasor(); defer { try? FileManager.default.removeItem(at: d) }
        let f = d.appending(path: "tetikleyiciler.json")
        let iyi = UUID().uuidString
        try Data(#"[{"id":"\#(iyi)","ad":"Sabah","tur":"Her gün saatinde","istem":"Özetle"},{"id":"\#(UUID().uuidString)","ad":"Gelecek","tur":"Yeni tür","istem":"x"}]"#.utf8).write(to: f)
        let td = TetikDeposu(dosya: f)
        #expect(td.tetikler.count == 1 && td.tetikler.first?.ad == "Sabah")
        #expect(!td.okunamadi, "tek öğe atlandı, dosya bütünüyle okunamaz sayılmaz")
        #expect(try yedekler(d, onEk: "tetikleyiciler.bozuk-").count == 1, "özgün dosya yedeklenir")
    }

    @Test func okunamayanDosyaEzilmezVePlanBildirimSilmez() async throws {
        let d = try klasor(); defer { try? FileManager.default.removeItem(at: d) }
        let f = d.appending(path: "tetikleyiciler.json")
        let bozuk = Data("{bozuk".utf8); try bozuk.write(to: f)
        let td = TetikDeposu(dosya: f)
        #expect(td.okunamadi && td.tetikler.isEmpty)
        td.kaydet(Tetik(ad: "Yeni", tur: .saat, istem: "x"))
        await td.planlaSirayla().value
        #expect(try Data(contentsOf: f) == bozuk, "okunamayan dosya yazımla ezilmez")
        #expect(try yedekler(d, onEk: "tetikleyiciler.bozuk-").count == 1)
    }

    // MARK: Bulgu 3: kalıcı olgu tarihle geçici olmaz

    @Test func cikarimTarihiKaliciOlguyuGeciciYapmaz() throws {
        let d = depo()
        let eski = try #require(d.hatirlaZengin("Kullanıcının adresi Kadıköy", kaynak: "cikarim", kategori: .yer))
        #expect(eski.gecerlilikSonu == nil)
        let guncel = try #require(d.hatirlaZengin("[yer:3:2099-12-01] Kullanıcının adresi Üsküdar", kaynak: "cikarim"))
        #expect(guncel.kimlik == eski.kimlik && guncel.metin.contains("Üsküdar"), "yakın kopya yerinde güncellenir")
        #expect(guncel.gecerlilikSonu == nil, "çıkarım tarihi kalıcı olguyu geçici yapmaz (bakımda silinirdi)")
        #expect(d.suresiDolanlariTemizle(simdi: Date(timeIntervalSince1970: 4_200_000_000)) == 0)
    }

    @Test func gecicOlguYeniTarihAlirVeKullaniciTarihVerebilir() throws {
        let d = depo()
        let gecici = try #require(d.hatirlaZengin("[yer:3:2099-01-01] Kullanıcının adresi Kadıköy", kaynak: "cikarim"))
        let once = try #require(gecici.gecerlilikSonu)
        let yeni = try #require(d.hatirlaZengin("[yer:3:2099-06-01] Kullanıcının adresi Üsküdar", kaynak: "cikarim"))
        #expect(yeni.kimlik == gecici.kimlik && (yeni.gecerlilikSonu ?? .distantPast) > once, "zaten geçici olan yeni tarihi alır")

        let d2 = depo()
        let kalici = try #require(d2.hatirlaZengin("Kullanıcının adresi Kadıköy", kaynak: "cikarim", kategori: .yer))
        let k = try #require(d2.hatirlaZengin("[yer:3:2099-12-01] Kullanıcının adresi Üsküdar", kaynak: "kullanici"))
        #expect(k.kimlik == kalici.kimlik && k.gecerlilikSonu != nil, "kullanıcı kendi verdiği geçici bilgiye tarih koyabilir")
    }

    // MARK: Bulgu 5: kullanıcı güncellemesi sabit eski bilgiyle yan yana yaşamaz

    @Test func kullaniciYeniDegeriSabitEskiylCeliskiOlur() throws {
        let d = depo()
        let eski = try #require(d.hatirlaZengin("Kullanıcının adresi Kadıköy", kaynak: "kullanici", kategori: .yer))
        d.olguAyarla(eski.kimlik, sabit: true)
        let yeni = try #require(d.hatirlaZengin("Kullanıcının adresi Üsküdar", kaynak: "kullanici", kategori: .yer))
        #expect(yeni.kimlik != eski.kimlik && yeni.durum == OlguDurumu.celiski)
        #expect(eski.metin.contains("Kadıköy") && eski.sabit == true)
        #expect(!d.talimatOlgulari().contains { $0.contains("Üsküdar") }, "çözülene dek yeni değer talimata girmez")
        #expect(d.celiskiAdayi(yeni)?.kimlik == eski.kimlik)
        #expect(d.celiskiCoz(yeni: yeni.kimlik, eski: eski.kimlik, yeniDogru: true))
        let kalan = try #require(d.olgular().first)
        #expect(d.olgular().count == 1 && kalan.metin.contains("Üsküdar") && kalan.sabit == true && kalan.durum == nil, "sabitleme yeniye geçer")
    }

    @Test func sabitOlmayanKullaniciOlgusuHalaYerindeGuncellenir() throws {
        let d = depo()
        let eski = try #require(d.hatirlaZengin("Kullanıcının adresi Kadıköy", kaynak: "kullanici", kategori: .yer))
        let yeni = try #require(d.hatirlaZengin("Kullanıcının adresi Üsküdar", kaynak: "kullanici", kategori: .yer))
        #expect(yeni.kimlik == eski.kimlik && yeni.durum == nil && yeni.metin.contains("Üsküdar"))
    }

    // MARK: Bulgu 6: asistan kaynaklı terim

    @Test func asistanaOzguTerimTasiyanOlguDuser() {
        let kullanici = "Ben Ankara'da oturuyorum"
        let asistan = "Ankara'da Kızılay çevresi çok kalabalık olur."
        #expect(OlguCikarici.kullanicidanMi("Kullanıcı Ankara'da oturuyor", kullanici: kullanici, asistan: asistan))
        #expect(!OlguCikarici.kullanicidanMi("Kullanıcı Ankara'da Kızılay'da oturuyor", kullanici: kullanici, asistan: asistan),
                "Kızılay yalnız asistan yanıtında geçiyor")
        #expect(OlguCikarici.kullanicidanMi("Kullanıcı Ankara'da Kızılay'da oturuyor", kullanici: kullanici), "asistan metni verilmezse eski davranış")
    }

    // MARK: Bulgu 7: bozuk Siri kutusu yedeklenir

    @Test func bozukSiriKutusuYedeklenir() throws {
        let d = try klasor(); defer { try? FileManager.default.removeItem(at: d) }
        let f = d.appending(path: "siri-soru-kutusu.json")
        let bozuk = Data("[{bozuk".utf8); try bozuk.write(to: f)
        #expect(SiriSoruKutusu.oku(f).isEmpty)
        let y = try yedekler(d, onEk: "siri-soru-kutusu.bozuk-")
        let yedek = try #require(y.first)
        let yedekVerisi = try Data(contentsOf: yedek)
        #expect(y.count == 1 && yedekVerisi == bozuk)
        #expect(SiriSoruKutusu.oku(d.appending(path: "yok.json")).isEmpty, "dosya yoksa yedek de yok")
        #expect(try yedekler(d, onEk: "yok.bozuk-").isEmpty)
    }

    // MARK: Bulgu 8-9: okul günü ufku ve bildirim sınırı

    private var takvim: Calendar { var t = Calendar(identifier: .gregorian); t.timeZone = .current; return t }
    private func an(_ y: Int, _ a: Int, _ g: Int, _ s: Int, _ d: Int = 0) -> Date {
        takvim.date(from: DateComponents(year: y, month: a, day: g, hour: s, minute: d))!
    }

    @Test func okulGunuSaatTetigiYediGunluk() {
        let t = Tetik(ad: "Sabah", tur: .saat, istem: "x", saat: 7, dakika: 30, yalnizOkulGunu: true)
        // Pazartesi akşamı (2026-10-19), hafta içi okul günü: yedi ardışık günden hafta içi olanlar (Sal-Cum + sonraki Pzt-Sal).
        let simdi = an(2026, 10, 19, 20)
        let cal = takvim
        let hafta: (Date) -> Bool? = { (2...6).contains(cal.component(.weekday, from: $0)) }
        let o = TetikDeposu.planOgeleri(tetikler: [t], etkinlikler: [], simdi: simdi, okulGunu: hafta, takvim: cal)
        let z = o.compactMap(\.zaman)
        #expect(o.count == 5 && o.allSatisfy { !$0.tekrarli })
        #expect(z == [an(2026, 10, 20, 7, 30), an(2026, 10, 21, 7, 30), an(2026, 10, 22, 7, 30), an(2026, 10, 23, 7, 30), an(2026, 10, 26, 7, 30)])
        // Her gün okul günü: en çok 7 öğe, tetik başına.
        let her = TetikDeposu.planOgeleri(tetikler: [t], etkinlikler: [], simdi: simdi, okulGunu: { _ in true }, takvim: takvim)
        #expect(her.count == 7 && her.last?.zaman == an(2026, 10, 26, 7, 30))
    }

    @Test func varsayilanBildirimSiniriElliAlti() {
        let simdi = an(2026, 10, 20, 6)
        let e = (0..<20).map { i -> TetikEtkinligi in
            let b = simdi.addingTimeInterval(Double(i + 1) * 3600)
            return TetikEtkinligi(ad: "Etkinlik \(i)", baslangic: b, bitis: b.addingTimeInterval(2400), takvim: "İş")
        }
        let dort = (0..<4).map { Tetik(ad: "T\($0)", tur: .takvim, istem: "x", dakikaOnce: 10) }
        let o = TetikDeposu.planOgeleri(tetikler: dort, etkinlikler: e, simdi: simdi, okulGunu: { _ in nil }, takvim: takvim)
        #expect(o.count == 56 && Set(o.map(\.kimlik)).count == 56)
        let konum = Tetik(ad: "Okul", tur: .konum, istem: "x", enlem: 41, boylam: 29)
        #expect(TetikDeposu.planOgeleri(tetikler: dort + [konum], etkinlikler: e, simdi: simdi, okulGunu: { _ in nil }, takvim: takvim).count == 55)
    }

    // MARK: Bulgu 4: kilitliyken depoya dokunulmaz

    @Test func korumaliVeriKilitliyseUygulamayaDevredilir() async {
        let ud = UserDefaults(suiteName: "inc2-\(UUID())")!
        // Yerel yanıtlar depo/ağ gerektirmez; kilitliyken de verilir.
        #expect(await SiriYanitlayici.yanitla("saat kaç", ayarlar: Ayarlar(defaults: ud), korumaliVeriAcik: { false }) != .uygulamada)
        // Model gerektiren istek kilitliyken (ya da çevrimdışıyken) uygulamaya devredilir; paylaşılan kap açılmaz.
        #expect(await SiriYanitlayici.yanitla("Fotosentezi iki cümleyle açıkla", ayarlar: Ayarlar(defaults: ud), korumaliVeriAcik: { false }) == .uygulamada)
    }
}
