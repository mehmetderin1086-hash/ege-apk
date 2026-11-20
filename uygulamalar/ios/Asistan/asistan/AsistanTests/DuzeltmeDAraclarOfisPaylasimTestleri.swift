import Foundation
import Testing
import EventKit
import PDFKit
import AlarmKit
import ZIPFoundation
@testable import Asistan

@Suite("D-araclar-ofis-paylasim düzeltmeleri") @MainActor struct DuzeltmeDAraclarOfisPaylasimTestleri {
    // MARK: 42 — saatsiz gün

    @Test func yalnizGunAyirt() {
        #expect(AracYardim.yalnizGun("2026-10-21"))
        #expect(AracYardim.yalnizGun(" 2026-10-21 "))
        #expect(!AracYardim.yalnizGun("2026-10-21T09:00"))
        #expect(!AracYardim.yalnizGun(nil))
        #expect(!AracYardim.yalnizGun("yarın"))
    }

    @Test func saatsizHatirlatmaDokuzaKurulur() throws {
        let z = try #require(AracYardim.hatirlatmaZamani("2026-10-21"))
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: z)
        #expect(c.year == 2026 && c.month == 10 && c.day == 21)
        #expect(c.hour == 9 && c.minute == 0)
        let saatli = try #require(AracYardim.hatirlatmaZamani("2026-10-21T18:30"))
        #expect(Calendar.current.component(.hour, from: saatli) == 18)
        #expect(AracYardim.hatirlatmaZamani("anlamsız") == nil)
    }

    @Test func tumGunEtkinligiKurulur() {
        let depo = EKEventStore()
        let gun = AracYardim.tarih("2026-10-29")!
        let e = TakvimAraci.etkinlikKur(depo, baslik: "Cumhuriyet Bayramı", bas: gun, bit: gun, tumGun: true)
        #expect(e.isAllDay)
        #expect(e.alarms?.first?.relativeOffset == TakvimAraci.tumGunUyariOfseti(15))
        #expect(TakvimAraci.tumGunUyariOfseti(15) == 9 * 3600 - 15 * 60)
        // Varsayılan (saatli) yol değişmedi.
        let saatli = TakvimAraci.etkinlikKur(depo, baslik: "x", bas: gun, bit: gun)
        #expect(!saatli.isAllDay)
        #expect(saatli.endDate > saatli.startDate)
        #expect(saatli.alarms?.first?.relativeOffset == -900)
    }

    // MARK: 41 — toplu eklemede atlanan / kesilen raporu

    @Test func topluOzetAtlananVeKesileniSoyler() {
        #expect(AracYardim.topluOzet(atlanan: [], kesilen: 0, sinir: 60).isEmpty)
        let s = AracYardim.topluOzet(atlanan: ["3. Kimya | yarın", "7. Fizik"], kesilen: 5, sinir: 60)
        #expect(s.contains("Eklenemeyen 2 satır"))
        #expect(s.contains("3. Kimya | yarın"))
        #expect(s.contains("7. Fizik"))
        #expect(s.contains("Sınır 60: 5 madde işlenmedi"))
        #expect(!AracYardim.topluOzet(atlanan: [], kesilen: 2, sinir: 40).contains("Eklenemeyen"))
    }

    // MARK: 48 — 'tamamla' hedef seçimi

    @Test func tamamlaHedefiBelirsizlikteSecilmez() {
        let b = ["9B Biyoloji dersi", "10A Biyoloji dersi"]
        #expect(HatirlaticiAraci.hedefSec(b, parca: "biyoloji") == .belirsiz([0, 1]))
        #expect(HatirlaticiAraci.hedefSec(b, parca: "10a biyoloji dersi") == .tek(1))
        #expect(HatirlaticiAraci.hedefSec(b, parca: "9B") == .tek(0))
        #expect(HatirlaticiAraci.hedefSec(b, parca: "kimya") == .yok)
        #expect(HatirlaticiAraci.hedefSec(b, parca: "  ") == .yok)
        // Tam eşleşme, alt dize eşleşmesine üstün gelir.
        #expect(HatirlaticiAraci.hedefSec(["Fotokopi al ve dağıt", "Fotokopi al"], parca: "fotokopi al") == .tek(1))
        // Aksan duyarsız tam eşleşme.
        #expect(HatirlaticiAraci.hedefSec(["Süt al", "Süt al ve ekmek"], parca: "sut al") == .tek(0))
    }

    // MARK: 47 — zamanlayıcı iptali ve Türkçe durum

    @Test func alarmDurumuTurkce() {
        #expect(ZamanlayiciAraci.durumAdi(.scheduled) == "bekliyor")
        #expect(ZamanlayiciAraci.durumAdi(.countdown) == "geri sayıyor")
        #expect(ZamanlayiciAraci.durumAdi(.paused) == "duraklatıldı")
        #expect(ZamanlayiciAraci.durumAdi(.alerting) == "çalıyor")
    }

    @Test func iptalYalnizEslesenKaydiSecer() {
        let cay = UUID(), uyanma = UUID()
        let ogeler: [(id: UUID, baslik: String)] = [(cay, "Çay"), (uyanma, "Uyanma")]
        #expect(ZamanlayiciAraci.iptalSecimi(ogeler, baslik: "çay") == .iptal([cay]))
        #expect(ZamanlayiciAraci.iptalSecimi(ogeler, baslik: "toplantı") == .eslesmeYok)
        #expect(ZamanlayiciAraci.iptalSecimi(ogeler, baslik: nil) == .belirsiz)
        #expect(ZamanlayiciAraci.iptalSecimi(ogeler, baslik: "") == .belirsiz)
        #expect(ZamanlayiciAraci.iptalSecimi(ogeler, baslik: "Hepsi") == .iptal([cay, uyanma]))
        #expect(ZamanlayiciAraci.iptalSecimi([(cay, "Çay")], baslik: nil) == .iptal([cay]))
        #expect(ZamanlayiciAraci.iptalSecimi([], baslik: "hepsi") == .bos)
    }

    // MARK: 43 — PDF'te uzun paragraf ve slaytlar

    @Test func uzunParagrafSonrakiSayfayaTasar() throws {
        let uzun = String(repeating: "Hücre zarı seçici geçirgendir ve madde alışverişini düzenler. ", count: 150) + "SONKELIME"
        let govde: [String: Any] = ["title": "Uzun", "paragraphs": [uzun]]
        let json = String(decoding: try JSONSerialization.data(withJSONObject: govde), as: UTF8.self)
        let pdf = OfisOlusturucu.pdf(try OfisOlusturucu.icerik(json))
        let belge = try #require(PDFDocument(data: pdf))
        #expect(belge.pageCount >= 2)
        #expect(belge.string?.contains("SONKELIME") == true)
    }

    @Test func yalnizSlaytliPdfBosKalmaz() throws {
        let i = try OfisOlusturucu.icerik(#"{"slides":[{"title":"Mitoz","body":["Profaz evresi","Metafaz evresi"]}]}"#)
        let belge = try #require(PDFDocument(data: OfisOlusturucu.pdf(i)))
        let metin = belge.string ?? ""
        #expect(metin.contains("Profaz"))
        #expect(metin.contains("Metafaz"))
    }

    // MARK: 45 — PPTX şema öğeleri

    @Test func pptxZorunluOgeleriIcerir() throws {
        let i = try OfisOlusturucu.icerik(#"{"title":"Sunum","slides":[{"title":"Bir","body":["Madde"]}]}"#)
        let kok = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: kok, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: kok) }
        let p = kok.appending(path: "sunum.pptx")
        try OfisOlusturucu.pptx(i).write(to: p)
        let arsiv = try Archive(url: p, accessMode: .read)
        func oku(_ yol: String) throws -> String {
            let girdi = try #require(arsiv[yol])
            var veri = Data()
            _ = try arsiv.extract(girdi) { veri.append($0) }
            return String(decoding: veri, as: UTF8.self)
        }
        let sunum = try oku("ppt/presentation.xml")
        let ana = try oku("ppt/slideMasters/slideMaster1.xml")
        let tema = try oku("ppt/theme/theme1.xml")
        #expect(sunum.contains("<p:notesSz"))
        #expect(ana.contains("<p:clrMap"))
        #expect(ana.contains("id=\"2147483649\""))
        #expect(!ana.contains("<p:sldLayoutId id=\"1\""))
        for renk in ["<a:dk2>", "<a:lt2>", "<a:accent2>", "<a:accent6>", "<a:hlink>", "<a:folHlink>"] { #expect(tema.contains(renk), "\(renk) eksik") }
        for liste in ["fillStyleLst", "lnStyleLst", "effectStyleLst", "bgFillStyleLst", "<a:ea ", "<a:cs "] { #expect(tema.contains(liste), "\(liste) eksik") }
    }

    // MARK: 65 — dönüştürmede işaret süzgeci ve kesinti notu

    @Test func donusturmeYalnizOkuyucuIsaretleriniAtar() {
        #expect(OfisDonusturucu.okuyucuIsaretiMi("[Sayfa 3]"))
        #expect(OfisDonusturucu.okuyucuIsaretiMi("[word/document.xml]"))
        #expect(OfisDonusturucu.okuyucuIsaretiMi("[ppt/slides/slide2.xml]"))
        #expect(!OfisDonusturucu.okuyucuIsaretiMi("[Not]"))
        #expect(!OfisDonusturucu.okuyucuIsaretiMi("[1, 2, 3]"))
        let belge = OkunanBelge(ad: "Rapor.pdf", metin: "[Sayfa 1]\nGiriş\n[Not]\n[1, 2, 3]\n[word/document.xml]\nSon", not: "")
        #expect(OfisDonusturucu.icerik(belge).paragraflar == ["Giriş", "[Not]", "[1, 2, 3]", "Son"])
        #expect(OfisDonusturucu.kesintiNotu(belge).isEmpty)
    }

    @Test func satirSiniriAsilincaNotUretilir() {
        let n = OfisDonusturucu.satirSiniri + 100
        let belge = OkunanBelge(ad: "Uzun.docx", metin: (1...n).map { "Satır \($0)" }.joined(separator: "\n"), not: "")
        #expect(OfisDonusturucu.icerik(belge).paragraflar.count == OfisDonusturucu.satirSiniri)
        let not = OfisDonusturucu.kesintiNotu(belge)
        #expect(not.contains("\(n) satırın ilk \(OfisDonusturucu.satirSiniri) satırı"))
    }

    // MARK: 62 — arşiv hata yollarında artık bırakmaz, çıkarılanlar İndirmeler'e taşınır

    private func indirmelerdeki(_ parca: String) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: IndirmeYoneticisi.klasorYolu)) ?? []).filter { $0.contains(parca) }
    }

    @Test func bozukArsivYarimKlasorBirakmaz() throws {
        try FileManager.default.createDirectory(atPath: IndirmeYoneticisi.klasorYolu, withIntermediateDirectories: true)
        let isaret = "Bozuk\(UUID().uuidString.prefix(8))"
        let zip = FileManager.default.temporaryDirectory.appending(path: isaret + ".zip")
        try Data("bu bir zip değil".utf8).write(to: zip)
        defer { try? FileManager.default.removeItem(at: zip) }
        #expect(throws: (any Error).self) { try ArsivIslemleri.ac(zip, parola: nil) }
        #expect(indirmelerdeki(isaret).isEmpty)
        let metin = FileManager.default.temporaryDirectory.appending(path: isaret + ".txt")
        try Data("x".utf8).write(to: metin)
        defer { try? FileManager.default.removeItem(at: metin) }
        #expect(throws: ArsivIslemleri.Hata.self) { try ArsivIslemleri.ac(metin, parola: nil) }
        #expect(indirmelerdeki(isaret).isEmpty)
    }

    @Test func bosZipYarimDosyaBirakmaz() throws {
        try FileManager.default.createDirectory(atPath: IndirmeYoneticisi.klasorYolu, withIntermediateDirectories: true)
        let klasor = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: klasor, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: klasor) }
        let isaret = "BosZip\(UUID().uuidString.prefix(8))"
        // Yalnız klasör seçildi: düzenli dosya yok → .bos; yarım .zip kalmamalı.
        #expect(throws: ArsivIslemleri.Hata.self) { try ArsivIslemleri.zipOlustur([klasor], ad: isaret) }
        #expect(indirmelerdeki(isaret).isEmpty)
    }

    @Test func acilanDosyalarIndirmelereTasinir() throws {
        let kok = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: kok, withIntermediateDirectories: true)
        let a = kok.appending(path: "Bir.txt"), b = kok.appending(path: "İki.csv")
        try "Merhaba".write(to: a, atomically: true, encoding: .utf8)
        try "A,B".write(to: b, atomically: true, encoding: .utf8)
        let zip = try ArsivIslemleri.zipOlustur([a, b], ad: "Tasima")
        let acilan = try ArsivIslemleri.ac(zip, parola: nil)
        let tasinan = ArsivIslemleri.indirmelereTasi(acilan)
        defer {
            try? FileManager.default.removeItem(at: kok); try? FileManager.default.removeItem(at: zip)
            for t in tasinan { try? FileManager.default.removeItem(at: t.url) }
        }
        #expect(tasinan.count == 2)
        #expect(Set(tasinan.map(\.ad)) == ["Bir.txt", "İki.csv"])
        #expect(!FileManager.default.fileExists(atPath: acilan.0.path))
        let indirmeler = URL(fileURLWithPath: IndirmeYoneticisi.klasorYolu, isDirectory: true).standardizedFileURL
        for t in tasinan {
            #expect(t.url.deletingLastPathComponent().standardizedFileURL == indirmeler)
            #expect(FileManager.default.fileExists(atPath: t.url.path))
        }
        let bir = try #require(tasinan.first { $0.ad == "Bir.txt" })
        #expect(try String(contentsOf: bir.url, encoding: .utf8) == "Merhaba")
    }
}
