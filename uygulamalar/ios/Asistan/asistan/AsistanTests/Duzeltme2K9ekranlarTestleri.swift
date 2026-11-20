import Testing
import Foundation
@testable import Asistan

@MainActor @Suite("K9-ekranlar düzeltmeleri")
struct Duzeltme2K9ekranlarTestleri {
    private var uzun: String { String(repeating: "a", count: CalismaAlani.enFazlaKarakter + 1) }

    // Bulgu 109/115/121: sınırı aşan kaydedilmemiş düzenleme varken geri oku kilitlenir (sessiz kayıp yok).
    @Test func calismaAlaniCikisiYalnizKirliVeSinirAsilincaKilitli() {
        let kayitli: [CalismaAlani.Dosya: String] = [.soul: "Sıcak konuş", .user: "Öğretmenim", .agents: ""]
        #expect(!CalismaAlaniEkrani.cikisKilitliMi(kayitli, kayitli: kayitli))
        #expect(!CalismaAlaniEkrani.cikisKilitliMi([.soul: "Sıcak konuş", .user: "Biyoloji öğretmeniyim", .agents: ""], kayitli: kayitli))
        #expect(CalismaAlaniEkrani.cikisKilitliMi([.soul: "Sıcak konuş", .user: uzun, .agents: ""], kayitli: kayitli))
        // Diskte zaten (dışarıdan) sınırı aşan ama değiştirilmemiş içerik çıkışı kilitlemez: kaybolacak düzenleme yok.
        let diskteUzun: [CalismaAlani.Dosya: String] = [.soul: uzun, .user: "", .agents: ""]
        #expect(!CalismaAlaniEkrani.cikisKilitliMi(diskteUzun, kayitli: diskteUzun))
    }

    // Bulgu 38/115/121: Nabız listesi için aynı kilit; yalnız baş/son boşluk farkı kirli sayılmaz.
    @Test func nabizCikisiYalnizKirliVeSinirAsilincaKilitli() {
        #expect(!NabizEkrani.cikisKilitliMi("- takvim", kayitli: "- takvim\n"))
        #expect(!NabizEkrani.cikisKilitliMi("- takvim\n- hava", kayitli: "- takvim"))
        #expect(NabizEkrani.cikisKilitliMi(uzun, kayitli: "- takvim"))
        #expect(!NabizEkrani.cikisKilitliMi(uzun, kayitli: uzun))
        let sinirda = String(repeating: "b", count: CalismaAlani.enFazlaKarakter)
        #expect(!NabizEkrani.cikisKilitliMi(sinirda, kayitli: ""))
    }

    // Bulgu 125: silme onayı tanı günlüğünün de gideceğini söyler.
    @Test func izlemeSilmeOnayiTaniGunlugunuSoyler() {
        let m = IzlemeEkrani.silmeAciklamasi
        #expect(m.contains("tanı günlüğü"))
        #expect(m.contains("tani.log"))
        #expect(m.contains("Geri alınamaz"))
    }

    // Bulgu 110: UUID öneki eklenince ad 255 baytı aşmasın (çok baytlı adlarda ENAMETOOLONG yüzünden dosya düşüyordu).
    @Test func arsivAdiBaytaSigar() {
        #expect(ArsivIslemleri.baytaSigdir("Ödev.pdf") == "Ödev.pdf")
        let cjk = String(repeating: "漢", count: 100) + ".pdf"          // 304 bayt
        let s = ArsivIslemleri.baytaSigdir(cjk)
        #expect(s.utf8.count <= 218)
        #expect(s.hasSuffix(".pdf"))
        #expect((UUID().uuidString + "-" + s).utf8.count <= 255)
        let kiril = String(repeating: "Ж", count: 139) + ".docx"
        #expect(ArsivIslemleri.baytaSigdir(kiril).utf8.count <= 218)
        #expect(ArsivIslemleri.baytaSigdir(kiril).hasSuffix(".docx"))
    }

    // Bulgu 110/117/124: taşınamayan dosya sayılır (sessizce düşmez); RAR'daki yinelenen yol hata sayılmaz.
    @Test func tasinamayanDosyaSayilirYinelenenSayilmaz() throws {
        let kok = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + "-Açıldı", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: kok, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: ArsivIslemleri.indirmeler, withIntermediateDirectories: true)
        let var1 = kok.appending(path: "Var.txt"), yok = kok.appending(path: "Yok.txt")
        try "Merhaba".write(to: var1, atomically: true, encoding: .utf8)
        let r = ArsivIslemleri.indirmelereTasiSayarak((kok, [var1, var1, yok]))
        defer {
            try? FileManager.default.removeItem(at: kok)
            for t in r.tasinan { try? FileManager.default.removeItem(at: t.url) }
        }
        #expect(r.tasinan.count == 1)
        #expect(r.tasinan.first?.ad == "Var.txt")
        #expect(r.kalan == 1)
        #expect(ArsivIslemleri.kalanUyarisi(r.kalan)?.contains("1 dosya") == true)
        #expect(ArsivIslemleri.kalanUyarisi(0) == nil)
        #expect(ArsivIslemleri.Hata.tasinamadi.errorDescription?.contains("taşınamadı") == true)
    }

    // Bulgu 119/122: çerez dosyası yedekten dışlanır.
    @Test func dosyaYedektenDislanir() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + "-cerez.txt")
        try Data("# Netscape HTTP Cookie File\n".utf8).write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(AyarlarEkrani.yedektenDisla(url))
        let d = try URL(fileURLWithPath: url.path).resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(d.isExcludedFromBackup == true)
    }

    // Bulgu 113/116 (+O13): kesinti notu satır sayısından üretilir; PDF dahil bütün biçimler arka plan üreticisinden çıkar.
    @Test func donusturmeArkaPlanVerisiVeKesintiNotu() throws {
        #expect(OfisDonusturucu.kesintiNotu(satirSayisi: OfisDonusturucu.satirSiniri).isEmpty)
        #expect(OfisDonusturucu.kesintiNotu(satirSayisi: OfisDonusturucu.satirSiniri + 5).contains("\(OfisDonusturucu.satirSiniri + 5) satırın"))
        let belge = OkunanBelge(ad: "Not.docx", metin: "Giriş\nHücre\nSon", not: "")
        let tum = OfisDonusturucu.tumSatirlar(belge)
        let i = OfisDonusturucu.icerik(belge, satirlar: tum)
        #expect(i.paragraflar == OfisDonusturucu.icerik(belge).paragraflar)
        for hedef in ["docx", "xlsx", "pptx", "csv", "md", "txt", "json"] {
            #expect(try !OfisDonusturucu.arkaPlanVerisi(i, hedef: hedef).isEmpty)
        }
        #expect(try !OfisDonusturucu.arkaPlanVerisi(i, hedef: "pdf").isEmpty)
    }

    // Bulgu 114/123: geri yükleme özeti geri almanın süresini söyler; okuma hatası varsa başa uyarı konur.
    @Test func yedekOzetiGeriAlmaSuresiniVeUyariyiSoyler() {
        let duz = KisiselAlanEkrani.yedekOzetiMetni(mevcutKomut: 3, mevcutYanit: 1, yedekKomut: 5, yedekYanit: 2, uyari: nil)
        #expect(duz.contains("Mevcut 3 komut ve 1 kayıtlı yanıt"))
        #expect(duz.contains("Bir sonraki geri yüklemeye kadar"))
        #expect(!duz.hasPrefix("Uyarı"))
        let uyarili = KisiselAlanEkrani.yedekOzetiMetni(mevcutKomut: 0, mevcutYanit: 0, yedekKomut: 5, yedekYanit: 2, uyari: "Kişisel alan okunamadı.")
        #expect(uyarili.hasPrefix("Uyarı: Kişisel alan okunamadı."))
    }
}
