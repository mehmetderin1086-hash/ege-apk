import Testing
import Foundation
import SwiftData
@testable import Asistan

@Suite("C-hafiza-tetik düzeltmeleri") @MainActor
struct DuzeltmeCHafizaTetikTestleri {
    nonisolated(unsafe) private static var kaplar: [ModelContainer] = []   // context'ten uzun yaşamalı (yoksa SwiftData çöker)
    private func depo() -> HafizaDeposu {
        let k = HafizaDeposu.kapOlustur(bellekte: true); Self.kaplar.append(k)
        return HafizaDeposu(baglam: k.mainContext)
    }
    private func klasor() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appending(path: "c-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    // MARK: unut (bulgu 9, 39, 100)

    @Test func unutCokEslesmedeHicbiriniSilmez() {
        let d = depo()
        for m in ["Kullanıcının eşinin adı Ayşe", "Ayşe Hanım kullanıcının komşusu", "Kullanıcı çayı şekersiz içer"] { _ = d.hatirla(m) }
        if case .cokEslesme(let l) = d.unutTekil("Ayşe") { #expect(l.count == 2) } else { Issue.record("iki olguya uyan parça hiçbirini silmemeli") }
        if case .cokEslesme(let l) = d.unutTekil("Kullanıcı") { #expect(l.count == 3) } else { Issue.record("'Kullanıcı' bütün hafızayı silmemeli") }
        #expect(d.unutTekil("a") == .yok && d.unut(iceren: "ay") == 0, "kısa parça silmez")
        #expect(d.olgular().count == 3)
        // Tam metin yalnız o olguyu siler (parça olarak başka olgulara da uysa bile).
        #expect(d.unutTekil("kullanıcının eşinin adı ayşe") == .silindi("Kullanıcının eşinin adı Ayşe"))
        #expect(d.olgular().count == 2)
        #expect(d.unut(iceren: "komşusu") == 1 && d.olgular().count == 1)
    }

    @Test func sabitOlguUnutlaSilinmez() throws {
        let d = depo()
        let o = try #require(d.hatirla("Kullanıcının kan grubu A Rh+"))
        d.olguAyarla(o.kimlik, sabit: true)
        #expect(d.unutTekil("kan grubu") == .sabitKorundu)
        #expect(d.unut(iceren: "Kullanıcının kan grubu A Rh+") == 0)
        #expect(d.olgular().count == 1)
    }

    // MARK: yakın kopya ve günlük birleştirme (bulgu 7, 8)

    @Test func farkliOlgularBirbiriniEzmezVeBirlesmez() {
        let d = depo()
        let ciftler = [("Kullanıcı kahveyi şekersiz sever", "Kullanıcı çayı şekersiz sever"),
                       ("Kullanıcı 9-A sınıfına biyoloji dersi veriyor", "Kullanıcı 10-B sınıfına biyoloji dersi veriyor"),
                       ("Kullanıcının eşinin adı Ayşe", "Kullanıcının annesinin adı Ayşe")]
        for (a, b) in ciftler { _ = d.hatirlaZengin(a, kaynak: "cikarim"); _ = d.hatirlaZengin(b, kaynak: "cikarim") }
        #expect(d.olgular().count == 6, "kahve/çay, 9-A/10-B, eşi/annesi ayrı kalır")
        #expect(d.yinelenenleriBirlestir() == 0)
        #expect(d.olgular().count == 6)
        #expect(OlguBicimi.benzerlik("Kullanıcı 9-A sınıfında", "Kullanıcı 10-B sınıfında") == 0)
    }

    @Test func uzunOlgudaSondakiFarkGorulur() {
        let a = "Kullanıcı pazartesi salı çarşamba perşembe cuma günleri okulda sabah erken saatte biyoloji laboratuvarı hazırlıyor"
        let b = "Kullanıcı pazartesi salı çarşamba perşembe cuma günleri okulda sabah erken saatte biyoloji laboratuvarı temizliyor"
        #expect(!OlguBicimi.neredeyseAyni(a, b))
        #expect(!OlguBicimi.kapsar(OlguBicimi.imza(a), OlguBicimi.imza(b)))
    }

    @Test func birebirAyniOlgularBirlesirSabitlenenDokunulmaz() throws {
        let d = depo()
        _ = d.hatirla("Kullanıcı sabah kahve içer.", kaynak: "cikarim")
        _ = d.hatirla("kullanıcı sabah kahve içer", kaynak: "cikarim")
        #expect(d.olgular().count == 2)
        #expect(d.yinelenenleriBirlestir() == 1 && d.olgular().count == 1)
        let s = try #require(d.hatirla("Kullanıcının kedisi Pamuk"))
        d.olguAyarla(s.kimlik, sabit: true)
        _ = d.hatirla("Kullanıcının kedisi Pamuk.")
        #expect(d.yinelenenleriBirlestir() == 0 && d.olgular().count == 3, "sabitlenen birleştirilmez")
    }

    @Test func cikarimKullanicininOlgusunuEzmez() {
        let d = depo()
        _ = d.hatirlaZengin("Kullanıcı Beykoz Cumhuriyet Mahallesi'nde oturuyor", kaynak: "kullanici", kategori: .yer)
        _ = d.hatirlaZengin("Kullanıcı Beykoz Cumhuriyet Mahallesi'nde evde oturuyor", kaynak: "cikarim", kategori: .yer)
        #expect(d.olgular().count == 2)
        #expect(d.olgular().contains { $0.kaynak == "kullanici" && !$0.metin.contains("evde") })
    }

    @Test func farkliKategorideYakinKopyaGuncellenmez() {
        let d = depo()
        _ = d.hatirlaZengin("Kullanıcı Beykoz Cumhuriyet Mahallesi'nde oturuyor", kaynak: "cikarim", kategori: .yer)
        _ = d.hatirlaZengin("Kullanıcı Beykoz Cumhuriyet Mahallesi'nde evde oturuyor", kaynak: "cikarim", kategori: .diger)
        #expect(d.olgular().count == 2)
    }

    // MARK: indeks (bulgu 160)

    @Test func indeksYeniKayitGuncellemedeKopyaBirakmaz() {
        let ix = HafizaIndeksi(bellekte: true)
        ix.ekle(tur: .mesaj, kimlik: "k1", metin: "Matematik sınavı cuma", yeni: true)
        ix.ekle(tur: .mesaj, kimlik: "k1", metin: "Matematik sınavı perşembe")
        #expect(ix.say(tur: .mesaj) == 1, "güncelleme yolu eski kaydı yine siler")
        #expect(ix.ara("persembe").count == 1)
    }

    // MARK: olgu çıkarıcı (bulgu 150)

    @Test func cikariciAsistanYanitiniCerceveler() {
        let g = OlguCikarici.girdi(mevcut: [], kullanici: "Benim adım Mehmet", asistan: String(repeating: "x", count: 2000) + "SONEK")
        #expect(g.contains("<asistan_yaniti") && g.contains("</asistan_yaniti>"))
        #expect(!g.contains("SONEK"), "asistan yanıtı kırpılır")
        #expect(g.contains("Kullanıcı: Benim adım Mehmet") && g.contains("(yok)"))
    }

    // MARK: tetik ve proje depoları (bulgu 90, 91)

    @Test func eksikAlanliTetikVeProjeCozulur() throws {
        let dir = try klasor(); defer { try? FileManager.default.removeItem(at: dir) }
        let t = dir.appending(path: "t.json")
        try Data(#"[{"id":"\#(UUID().uuidString)","ad":"Sabah","tur":"Her gün saatinde","istem":"Özetle"}]"#.utf8).write(to: t)
        let td = TetikDeposu(dosya: t)
        #expect(td.tetikler.count == 1)
        #expect(td.tetikler.first?.saat == 7 && td.tetikler.first?.dakikaOnce == 10 && td.tetikler.first?.etkin == true)
        let p = dir.appending(path: "p.json")
        try Data(#"[{"id":"\#(UUID().uuidString)","ad":"Okul"}]"#.utf8).write(to: p)
        let pd = ProjeDeposu(dosya: p, defaults: try #require(UserDefaults(suiteName: "p-\(UUID())")))
        #expect(pd.projeler.count == 1 && pd.projeler.first?.notlar.isEmpty == true && pd.projeler.first?.baglam.isEmpty == true)
        #expect(Tetik.Tur.saat.rawValue == "Her gün saatinde", "kalıcı anahtar değişmemeli")
    }

    @Test func bozukDepoYedeklenirVeOzgunIcerikKorunur() throws {
        let dir = try klasor(); defer { try? FileManager.default.removeItem(at: dir) }
        let p = dir.appending(path: "projeler.json")
        let bozuk = Data("{bozuk".utf8); try bozuk.write(to: p)
        let pd = ProjeDeposu(dosya: p, defaults: try #require(UserDefaults(suiteName: "p-\(UUID())")))
        #expect(pd.projeler.isEmpty)
        _ = pd.ekle("Yeni")
        let yedekler = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("projeler.bozuk-") }
        #expect(yedekler.count == 1)
        #expect(try Data(contentsOf: try #require(yedekler.first)) == bozuk)
    }

    // MARK: Kestirme/Siri teslimi (bulgu 89, 103)

    @Test func yenidenYayinYalnizEslesecekIsteklerde() {
        #expect(GorevKopru.yinelenebilir("Bugünkü derslerimi özetle"))
        #expect(!GorevKopru.yinelenebilir("/yeni"))
        #expect(!GorevKopru.yinelenebilir(String(repeating: "a", count: 4_001)))
        #expect(!GorevKopru.yinelenebilir("   "))
    }

    @Test func siriSorusuKabulEdilinceKutudanCikar() {
        let k = GorevKopru.ortak
        let s = "siri-test-\(UUID())"
        k.teslimEt(s)
        #expect(k.bekleyenSoru == s)
        k.kabul(s, nesil: 77_777)   // ilk yayından (300 ms) önce kabul: hiç yayın yapılmaz
        #expect(k.bekleyenSoru == nil)
    }

    // MARK: kişisel alan (bulgu 84, 85, 132)

    @Test func birMegabaytiAsanYedekGeriYuklenir() throws {
        let dir = try klasor(); defer { try? FileManager.default.removeItem(at: dir) }
        let kaynak = KisiselAlan(dosya: dir.appending(path: "a.json"))
        let parca = String(repeating: "çğıöşü ", count: 4_000)   // 28.000 karakter, Türkçe harfler 2 bayt
        for i in 0..<25 { #expect(kaynak.yanitKaydet("\(i) " + parca)) }
        let veri = try kaynak.yedekVerisi()
        #expect(veri.count > 1_000_000)
        let hedef = KisiselAlan(dosya: dir.appending(path: "b.json"))
        #expect(hedef.yedegiYukle(veri))
        #expect(hedef.icerik.yanitlar.map(\.metin) == kaynak.icerik.yanitlar.map(\.metin))
    }

    @Test func geriYuklemeOncekiIcerigiSaklarVeGeriAlinir() throws {
        let dir = try klasor(); defer { try? FileManager.default.removeItem(at: dir) }
        let kaynak = KisiselAlan(dosya: dir.appending(path: "k.json"))
        #expect(kaynak.komutKaydet(.init(baslik: "Yedekteki", metin: "Taşınan komut")))
        let veri = try kaynak.yedekVerisi()
        let hedef = KisiselAlan(dosya: dir.appending(path: "h.json"))
        #expect(hedef.yanitKaydet("Silinmemeli"))
        #expect(hedef.yedegiYukle(veri))
        #expect(hedef.icerik.yanitlar.isEmpty)
        let onceki = try JSONDecoder().decode(KisiselAlan.Icerik.self, from: Data(contentsOf: hedef.oncekiDosya))
        #expect(onceki.yanitlar.map(\.metin) == ["Silinmemeli"])
        #expect(hedef.geriYuklemeyiGeriAl())
        #expect(hedef.icerik.yanitlar.map(\.metin) == ["Silinmemeli"] && hedef.oncekiIcerik == nil)
    }

    @Test func kilitHatasiBozukDosyadanAyrilir() throws {
        #expect(KisiselAlan.kilitHatasi(CocoaError(.fileReadNoPermission)))
        #expect(KisiselAlan.kilitHatasi(NSError(domain: NSCocoaErrorDomain, code: 256, userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))])))
        #expect(!KisiselAlan.kilitHatasi(CocoaError(.coderReadCorrupt)))
        #expect(KisiselAlan.yedekBoyutuUygun(2_000_000) && !KisiselAlan.yedekBoyutuUygun(KisiselAlan.azamiYedekBayti + 1))
        // Bozuk dosyada yeniden deneme yazma engelini kaldırmaz.
        let dir = try klasor(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "bozuk.json")
        try Data("not valid json".utf8).write(to: url)
        let alan = KisiselAlan(dosya: url)
        alan.yenidenDene()
        #expect(!alan.yanitKaydet("Yeni") && alan.hata != nil)
    }
}
