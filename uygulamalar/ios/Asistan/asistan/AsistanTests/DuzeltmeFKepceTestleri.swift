import Foundation
import Testing
@testable import Asistan

@Suite("F-kepce düzeltmeleri") struct DuzeltmeFKepceTestleri {
    // MARK: Hata iletileri (bulgu 138, 152, 139)

    @Test func yasIletisiBotDalinaDusmez() {
        let ileti = PythonMotoru.anlasilir("İndirilebilir biçim bulunamadı. Sign in to confirm your age. This video may be inappropriate for some users.")
        #expect(ileti.hasPrefix("Yaş doğrulaması"))
        #expect(!ileti.contains("robot"))
    }

    @Test func botIletisiRobotAciklamasiAlir() {
        #expect(PythonMotoru.anlasilir("Sign in to confirm you’re not a bot. Use --cookies").hasPrefix("YouTube bu ağdan gelen isteği robot sanıyor"))
        #expect(PythonMotoru.anlasilir("ERROR: Sign in to confirm you're not a bot").contains("robot"))
    }

    @Test func istenenBicimYokIletisiKaldirilmisDenmez() {
        let ileti = PythonMotoru.anlasilir("Requested format is not available. Use --list-formats")
        #expect(!ileti.contains("kullanılamıyor"))
        #expect(ileti.hasPrefix("Uygun biçim seçilemedi"))
        #expect(PythonMotoru.anlasilir("Video unavailable. This video is not available").hasPrefix("Video kullanılamıyor"))
    }

    @Test func gevsekAgeImzasiYok() {
        // "page"/"message" içinde "age", "confirm" ile birlikte geçse bile yaş açıklaması verilmez.
        #expect(!PythonMotoru.anlasilir("Please confirm the message on this page").contains("Yaş"))
    }

    @Test func anlasilirIkiKezUygulanincaYinelenmez() {
        for ham in ["ERROR: Sign in to confirm you're not a bot", "Sign in to confirm your age", "Private video. Sign in", "Requested format is not available"] {
            let bir = PythonMotoru.anlasilir(ham)
            #expect(PythonMotoru.anlasilir(bir) == bir)
        }
        #expect(PythonMotoru.anlasilir("tanınmayan ileti") == "tanınmayan ileti")
    }

    @Test func iletilerGercekAyarYolunuGosterir() {
        #expect(PythonMotoru.anlasilir("Sign in to confirm your age").contains("Ayarlar > İndirme motoru"))
    }

    // MARK: Çerez dosyası (bulgu 76)

    @Test func cerezDosyasiBicimiDenetlenir() {
        #expect(PythonMotoru.cerezMetniGecerli("# Netscape HTTP Cookie File\n.youtube.com\tTRUE\t/\tTRUE\t0\tPREF\tf1=1\n"))
        #expect(PythonMotoru.cerezMetniGecerli(".youtube.com\tTRUE\t/\tTRUE\t1893456000\tSID\t\n"))   // boş değer: sondaki sekme sayılır
        #expect(PythonMotoru.cerezMetniGecerli("#HttpOnly_.youtube.com\tTRUE\t/\tTRUE\t0\tLOGIN_INFO\tx\n"))
        #expect(!PythonMotoru.cerezMetniGecerli(""))
        #expect(!PythonMotoru.cerezMetniGecerli("{\"cookies\": []}"))
        #expect(!PythonMotoru.cerezMetniGecerli("merhaba dünya\nikinci satır"))
    }

    // MARK: Yazma hataları ve iletiler (bulgu 141, 140)

    @Test func yazmaHatasiYalnizYerYoksaYerYokDer() {
        #expect((AkisIndirici.yazmaHatasi(ENOSPC) as? AkisHatasi) == .yerYok(0))
        #expect((AkisIndirici.yazmaHatasi(EDQUOT) as? AkisHatasi) == .yerYok(0))
        #expect((AkisIndirici.yazmaHatasi(EIO) as? POSIXError)?.code == .EIO)
        #expect((AkisIndirici.yazmaHatasi(EIO) as? AkisHatasi) == nil)
    }

    @Test func miktarsizYerYokIletisiParcaBoyutuVermez() {
        #expect(AkisHatasi.yerYok(0).errorDescription == "Telefonda yeterli boş yer yok.")
        #expect(AkisHatasi.yerYok(2_000_000_000).errorDescription?.contains("gerekiyor") == true)
    }

    @Test func dosyaDegistiKendiligindenBaslamaVaadiVermez() {
        #expect(AkisHatasi.dosyaDegisti.yenilenebilir)   // motor döngüsü bir kez yeniden çözer
        #expect(AkisHatasi.dosyaDegisti.errorDescription?.contains("baştan başlayacak") == false)
    }

    // MARK: Adres koruması (bulgu 142)

    @Test func ozelAdreslerMotorAkisindaReddedilir() {
        for s in ["http://192.168.1.1/a.mp4", "https://10.0.0.5/x", "https://127.0.0.1:18317/v1/models", "https://[fe80::1]/",
                  "https://localhost/a.mp4", "https://172.20.1.1/seg.ts", "http://rr1.googlevideo.com/videoplayback"] {
            #expect(!AkisIndirici.adresGuvenli(URL(string: s)!), "\(s) reddedilmeliydi")
        }
        // Sayısal genel adres DNS'e gitmeden kabul edilir.
        #expect(AkisIndirici.adresGuvenli(URL(string: "https://142.250.180.14/videoplayback?id=1")!))
    }

    // MARK: Çalışma klasörü (bulgu 78)

    @Test func calismaKlasoruKayitKimligiyleAdlanir() {
        let id = UUID()
        #expect(MotorluIndirici.calismaKlasoru(id).lastPathComponent == id.uuidString)
        #expect(MotorluIndirici.calismaKlasoru(id).deletingLastPathComponent().lastPathComponent == "MotorIsleri")
    }

    @Test func sahipsizKlasorKarari() {
        let simdi = Date()
        let etkin = UUID(), bekleyen = UUID(), sahipsiz = UUID()
        let eski = simdi.addingTimeInterval(-(MotorluIndirici.bekletmeSuresi + 60))
        #expect(!MotorluIndirici.silinmeli(etkin, etkin: [etkin], bekleyen: [], tarih: eski, simdi: simdi))
        #expect(!MotorluIndirici.silinmeli(bekleyen, etkin: [], bekleyen: [bekleyen], tarih: simdi, simdi: simdi))
        #expect(MotorluIndirici.silinmeli(bekleyen, etkin: [], bekleyen: [bekleyen], tarih: eski, simdi: simdi))
        #expect(MotorluIndirici.silinmeli(sahipsiz, etkin: [etkin], bekleyen: [bekleyen], tarih: simdi, simdi: simdi))
        #expect(MotorluIndirici.silinmeli(nil, etkin: [], bekleyen: [], tarih: simdi, simdi: simdi))
    }

    @Test func klasorYalnizIptaldeSilinir() {
        #expect(MotorluIndirici.klasorSilinmeli(CancellationError()))
        #expect(!MotorluIndirici.klasorSilinmeli(AkisHatasi.http(500)))
        #expect(!MotorluIndirici.klasorSilinmeli(AkisHatasi.yerYok(0)))
        #expect(!MotorluIndirici.klasorSilinmeli(PythonMotoru.Hata.cozum("x")))
    }

    // MARK: Birleştirme payı (bulgu 141)

    @Test func birlestirmePayiYalnizMp3SesteYok() {
        let mp3 = IndirmePlani(video: nil, ses: nil, tur: .ses, uzanti: "mp3", etiket: "", tahminiBoyut: nil)
        let m4a = IndirmePlani(video: nil, ses: nil, tur: .ses, uzanti: "m4a", etiket: "", tahminiBoyut: nil)
        let mp4 = IndirmePlani(video: nil, ses: nil, tur: .video, uzanti: "mp4", etiket: "", tahminiBoyut: nil)
        #expect(!MotorluIndirici.birlesecek(mp3))
        #expect(MotorluIndirici.birlesecek(m4a))
        #expect(MotorluIndirici.birlesecek(mp4))
    }
}
