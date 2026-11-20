#if DEBUG
import Foundation
import UIKit
import AVFoundation
import SwiftData

/// Yalnız açıkça verilen geliştirme argümanıyla, kişisel hafızaya dokunmadan çalışır.
@MainActor
enum AsistanSinama {
    // MARK: P3.10-kabul — merkezi rapor yazıcı

    /// `araclar/cihaz-kabul.sh` her sınamayı `--sinama-kosu=<uuid>` ile açar; rapor bu kimliği `kosu` alanında taşır.
    /// Betik eski turdan kalan dosyayı kimlik uyuşmazlığından ayırt eder.
    nonisolated static let kosuOneki = "--sinama-kosu="

    /// Açılış argümanlarındaki koşu kimliği; yoksa ya da boşsa nil.
    nonisolated static func kosuKimligi(_ argumanlar: [String] = ProcessInfo.processInfo.arguments) -> String? {
        guard let arguman = argumanlar.last(where: { $0.hasPrefix(kosuOneki) }) else { return nil }
        let kimlik = String(arguman.dropFirst(kosuOneki.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        return kimlik.isEmpty ? nil : kimlik
    }

    /// Bir raporun başarılı sayılması: (`tamamlandi` true ya da `asama` "tamamlandi") ve `hata` boş ve `zamanAsimi` true değil.
    /// `araclar/kabul_karsilastir.py` başarısızlık ölçütüyle uyumludur.
    nonisolated static func kabulBasarili(_ json: [String: Any]) -> Bool {
        let tamam = (json["tamamlandi"] as? Bool) == true || (json["asama"] as? String) == "tamamlandi"
        let hata = ((json["hata"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return tamam && hata.isEmpty && !SinamaKaydi.altHataVar(json)
    }

    /// Sınama raporunu `klasor` (varsayılan Documents) altına `dosyaAdi` ile atomik yazar. Var olan alanlara yalnız
    /// `kosu` (açılışta `--sinama-kosu=` verildiyse), `surum` (SurumBilgisi.uzun) ve `kosuBitti` eklenir.
    /// `bitti` false = ara yazım (tur sürüyor); true = son yazım: başarıdan BAĞIMSIZ bir SinamaKaydi satırı düşer.
    nonisolated static func kaydet(_ dosyaAdi: String, _ sonuc: [String: Any], bitti: Bool = true, klasor: URL? = nil,
                                   kosu: String? = kosuKimligi(), surum: String = SurumBilgisi.simdiki.uzun) {
        var nesne = sonuc
        if let kosu { nesne["kosu"] = kosu }
        nesne["surum"] = surum
        nesne["kosuBitti"] = bitti
        let dizin = klasor ?? URL.documentsDirectory
        guard let url = jsonYaz(nesne, dizin: dizin, dosyaAdi: dosyaAdi), bitti, let ad = SinamaKaydi.raporAdi(dosyaAdi) else { return }
        var ozet = nesne
        ozet["tamamlandi"] = kabulBasarili(nesne)
        SinamaKaydi.ekle(SinamaKaydi.ozetle(ad: ad, json: ozet, zaman: degisimZamani(url)), klasor: dizin)
    }

    /// Üst düzeyi dizi olan eski raporlar (otomatik, web): biçim değişmez, bu yüzden `kosu`/`surum` eklenemez
    /// (cihaz-kabul bunları koşturmaz). Son yazımda satır düşer; ilk dolu `hata` başarısızlık sayılır.
    nonisolated static func kaydet(_ dosyaAdi: String, dizi: [[String: Any]], bitti: Bool = true, klasor: URL? = nil) {
        let dizin = klasor ?? URL.documentsDirectory
        guard let url = jsonYaz(dizi, dizin: dizin, dosyaAdi: dosyaAdi), bitti, let ad = SinamaKaydi.raporAdi(dosyaAdi) else { return }
        let hata = dizi.lazy.compactMap { ($0["hata"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty } ?? ""
        let ozet: [String: Any] = ["tamamlandi": hata.isEmpty, "hata": hata, "sonuclar": dizi]
        SinamaKaydi.ekle(SinamaKaydi.ozetle(ad: ad, json: ozet, zaman: degisimZamani(url)), klasor: dizin)
    }

    /// Geçersiz JSON nesnesi (JSONSerialization'da ObjC istisnası, çökme) yazılmaz; yazılan dosyanın adresini döndürür.
    nonisolated private static func jsonYaz(_ nesne: Any, dizin: URL, dosyaAdi: String) -> URL? {
        guard JSONSerialization.isValidJSONObject(nesne),
              let veri = try? JSONSerialization.data(withJSONObject: nesne, options: [.prettyPrinted, .sortedKeys]) else { return nil }
        let url = dizin.appending(path: dosyaAdi)
        do { try veri.write(to: url, options: .atomic) } catch { return nil }
        return url
    }

    /// Satır zamanı dosyanın değişiklik anı: SinamaKaydi.iceAktar aynı raporu (ad + saniye) ikinci kez eklemez.
    nonisolated private static func degisimZamani(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
    }

    /// Eski UI testinin bıraktığı kayıtlar: açık kimlik + zaman + tam istem
    /// eşleşmesi olmadan hiçbir kayıt silinmez. İstek yalnız geliştirici kurulumunda okunur.
    static func testVerisiniTemizle() {
        let dosya = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appending(path: "asistan-test-temizlik-istegi.json")
        var silinmisSohbet = 0
        func bitir(_ hata: String) { kaydet("asistan-test-verisi-temizlik.json", ["tamamlandi": false, "hata": hata, "silinenSohbet": silinmisSohbet]) }
        guard ProcessInfo.processInfo.environment["ASISTAN_TEST"] != "1",
              HafizaDeposu.depoURL != nil, HafizaDeposu.acilisDurumu == .normal else {
            bitir("Normal kalıcı depo açık değil."); return
        }
        guard let veri = try? Data(contentsOf: dosya),
              let istek = (try? JSONSerialization.jsonObject(with: veri)) as? [String: Any],
              let alt = istek["baslangic"] as? Double, let ust = istek["bitis"] as? Double,
              ust > alt, ust - alt <= 3600,
              let satirlar = istek["sohbetler"] as? [[String: Any]], !satirlar.isEmpty, satirlar.count <= 20,
              let olgu = istek["olgu"] as? [String: Any],
              let olguID = (olgu["kimlik"] as? String).flatMap(UUID.init(uuidString:)),
              let olguMetni = olgu["metin"] as? String else { bitir("Temizlik isteği geçersiz."); return }
        let baglam = HafizaDeposu.paylasilanKap.mainContext
        let depo = HafizaDeposu(baglam: baglam)
        func aralikta(_ tarih: Date) -> Bool { (alt...ust).contains(tarih.timeIntervalSince1970) }
        let hepsi = depo.tumSohbetler()
        var secilen: [Sohbet] = []
        for satir in satirlar {
            guard let id = (satir["kimlik"] as? String).flatMap(UUID.init(uuidString:)),
                  let istemler = satir["istemler"] as? [String], !istemler.isEmpty,
                  let adet = satir["mesajSayisi"] as? Int,
                  let s = hepsi.first(where: { $0.kimlik == id }), aralikta(s.olusturma),
                  s.mesajlar.count == adet, s.mesajlar.allSatisfy({ aralikta($0.zaman) }),
                  s.mesajlar.sorted(by: { $0.zaman < $1.zaman }).filter({ $0.rol == .kullanici }).map(\.metin) == istemler
            else { bitir("Sohbet kimliği, zamanı veya test istemi eşleşmedi."); return }
            secilen.append(s)
        }
        guard Set(secilen.map(\.kimlik)).count == secilen.count,
              let o = depo.olgular().first(where: { $0.kimlik == olguID }),
              o.metin == olguMetni, aralikta(o.olusturma) else { bitir("Olgu eşleşmedi."); return }
        let silinen = depo.sohbetleriSil(secilen)
        silinmisSohbet = silinen
        guard silinen == satirlar.count else { bitir("Test sohbetleri silinemedi."); return }
        guard depo.olguSil(olguID) else { baglam.rollback(); bitir("Test olgusu silinemedi."); return }
        do {
            let kalanSohbetler = try baglam.fetch(FetchDescriptor<Sohbet>())
            let kalanOlgular = try baglam.fetch(FetchDescriptor<Olgu>())
            let kalan = kalanSohbetler.contains { s in satirlar.contains { ($0["kimlik"] as? String)?.lowercased() == s.kimlik.uuidString.lowercased() } }
                || kalanOlgular.contains { $0.kimlik == olguID }
            kaydet("asistan-test-verisi-temizlik.json", ["tamamlandi": !kalan, "silinenSohbet": silinen, "silinenOlgu": 1])
            if !kalan { try? FileManager.default.removeItem(at: dosya) }
        } catch { bitir("Silme sonrası okuma doğrulanamadı; istek korundu.") }
    }

    static func sonIstekSina() async {
        let istek = "Türkiye'nin en kalabalık 5 ilini nüfuslarıyla bul, Excel dosyasında ver"
        Self.kaydet("asistan-son-istek-sinama.json", ["tamamlandi": false, "istek": istek], bitti: false)
        let onceki = Set((try? FileManager.default.contentsOfDirectory(atPath: IndirmeYoneticisi.klasor.path)) ?? [])
        let alan = "asistan.son-istek.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: alan) else { return }
        defer { defaults.removePersistentDomain(forName: alan) }
        let ayarlar = Ayarlar(defaults: defaults)
        ayarlar.otomatikHafiza = false; ayarlar.heyAsistan = false; ayarlar.sesliYanit = false
        ayarlar.webArama = true; ayarlar.sunucuGorevleri = false; ayarlar.calismaKipi = "otomatik"
        await TelefonProxy.ortak.hazirla()
        let kap = HafizaDeposu.kapOlustur(bellekte: true)
        let beyin = Beyin(ayarlar: ayarlar, depo: HafizaDeposu(baglam: kap.mainContext), onay: OnayKapisi())
        beyin.gonder(istek)
        for _ in 0..<480 {
            if beyin.durum == .bosta { break }
            try? await Task.sleep(for: .milliseconds(250))
        }
        let sonra = Set((try? FileManager.default.contentsOfDirectory(atPath: IndirmeYoneticisi.klasor.path)) ?? [])
        let yeni = Array(sonra.subtracting(onceki).filter { $0.lowercased().hasSuffix(".xlsx") }).sorted()
        let sonuc: [String: Any] = [
            "istek": istek,
            "kip": beyin.aktifKip.rawValue,
            "dogrudanArastirma": HizliModelSecimi.dogrudanArastirma(istek),
            "durum": String(describing: beyin.durum),
            "hata": beyin.sonHata ?? "",
            "model": beyin.aktifModel ?? "",
            "yanitlar": beyin.mesajlar.filter { $0.rol == .asistan }.map(\.metin),
            "araclar": beyin.gorevler.adimlar.map { ["ad": $0.ad, "durum": $0.durum] },
            "xlsx": yeni,
            "tamamlandi": true
        ]
        Self.kaydet("asistan-son-istek-sinama.json", sonuc)
    }

    static func ofisSina() {
        let json = #"{"title":"Asistan Ofis Sınaması","paragraphs":["Bu belge doğrudan iPhone üzerinde oluşturuldu.","Özgün dosyalar düzenlemede korunur; yeni kopya üretilir."],"table":{"columns":["Tür","Durum"],"rows":[["DOCX","Hazır"],["XLSX","Hazır"],["PPTX","Hazır"],["PDF","Hazır"]]},"slides":[{"title":"Asistan","body":["iPhone üzerinde üretim","DOCX, XLSX, PPTX ve PDF"]},{"title":"Düzenleme","body":["Dosyayı ekle","İstediğin değişikliği yaz","Yeni kopyayı paylaş"]}]}"#
        var sonuc: [String: Any] = ["tamamlandi": false]
        do {
            let i = try OfisOlusturucu.icerik(json)
            guard let tablo = i.tablo else { throw IndirmeHatasi.metin("Sınama tablosu hazırlanamadı.") }
            let dosyalar: [(String, Data)] = [
                ("Mehmet-Asistan-Ofis.docx", OfisOlusturucu.docx(i)),
                ("Mehmet-Asistan-Ofis.xlsx", ExcelOlusturucu.xlsx(tablo)),
                ("Mehmet-Asistan-Ofis.pptx", OfisOlusturucu.pptx(i)),
                ("Mehmet-Asistan-Ofis.pdf", OfisOlusturucu.pdf(i))
            ]
            var yazilan: [[String: Any]] = []
            for (ad, data) in dosyalar {
                let url = IndirmeYoneticisi.klasor.appending(path: "kabul-" + ad)
                try data.write(to: url, options: .atomic)
                IndirmeYoneticisi.ortak.yerelDosyaEkle(url: url, gorunenAd: ad)
                let okunan = try? BelgeOkuyucu.oku(url)
                yazilan.append(["ad": ad, "bayt": data.count, "okundu": okunan?.metin.isEmpty == false])
            }
            sonuc = ["tamamlandi": true, "dosyalar": yazilan]
        } catch { sonuc["hata"] = error.localizedDescription }
        Self.kaydet("asistan-ofis-sinama.json", sonuc)
    }

    static func donusturmeSina() {
        var sonuc: [String: Any] = ["tamamlandi": false]
        do {
            let kaynakIcerik = OfisOlusturucu.Icerik(
                baslik: "Dönüşüm Kaynağı",
                paragraflar: ["Birinci Word paragrafı", "İkinci Word paragrafı", "Üçüncü Word paragrafı"],
                tablo: nil,
                slaytlar: []
            )
            let kaynakURL = IndirmeYoneticisi.klasor.appending(path: "kabul-Donusum-Kaynagi.docx")
            try OfisOlusturucu.docx(kaynakIcerik).write(to: kaynakURL, options: .atomic)
            let word = try BelgeOkuyucu.oku(kaynakURL)
            var dosyalar: [[String: Any]] = []
            for hedef in ["xlsx", "pdf", "pptx", "csv"] {
                let url = try OfisDonusturucu.donustur(word, hedef: hedef)
                let tekrar = try BelgeOkuyucu.oku(url)
                dosyalar.append(["yon": "docx->\(hedef)", "ad": url.lastPathComponent, "okundu": !tekrar.metin.isEmpty])
            }
            let tablo = ExcelOlusturucu.Tablo(sutunlar: ["Kalem", "Tutar"], satirlar: [["Kira", "95"], ["Market", "88"]])
            let excelURL = IndirmeYoneticisi.klasor.appending(path: "kabul-Donusum-Kaynagi.xlsx")
            try ExcelOlusturucu.xlsx(tablo).write(to: excelURL, options: .atomic)
            let excel = try BelgeOkuyucu.oku(excelURL)
            let wordURL = try OfisDonusturucu.donustur(excel, hedef: "docx")
            dosyalar.append(["yon": "xlsx->docx", "ad": wordURL.lastPathComponent, "okundu": try !BelgeOkuyucu.oku(wordURL).metin.isEmpty])
            sonuc = ["tamamlandi": true, "dosyalar": dosyalar]
        } catch { sonuc["hata"] = error.localizedDescription }
        Self.kaydet("asistan-donusturme-sinama.json", sonuc)
    }

    static func arsivSina() {
        var sonuc: [String: Any] = ["tamamlandi": false]
        let gecici = FileManager.default.temporaryDirectory.appending(path: "arsiv-kabul-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: gecici) }
        do {
            try FileManager.default.createDirectory(at: gecici, withIntermediateDirectories: true)
            let metin = gecici.appending(path: "Telefon.txt")
            let tablo = gecici.appending(path: "Liste.csv")
            try "Asistan ZIP kabulü".write(to: metin, atomically: true, encoding: .utf8)
            try "Ad,Durum\nZIP,Hazır\nRAR,Açılır".write(to: tablo, atomically: true, encoding: .utf8)
            let zip = try ArsivIslemleri.zipOlustur([metin, tablo], ad: "iPhone-Arsiv-Kabul")
            IndirmeYoneticisi.ortak.yerelDosyaEkle(url: zip, gorunenAd: "iPhone-Arsiv-Kabul.zip")
            let zipAcildi = try ArsivIslemleri.ac(zip, parola: nil)
            let zipMetni = try String(contentsOf: zipAcildi.1.first { $0.pathExtension == "txt" }!, encoding: .utf8)

            let rarBaytlari: [UInt8] = [
                0x52,0x61,0x72,0x21,0x1a,0x07,0x01,0x00,0x33,0x92,0xb5,0xe5,0x0a,0x01,0x05,0x06,0x00,0x05,0x01,0x01,0x80,0x80,0x00,0xf7,
                0x12,0xa7,0xe5,0x1f,0x02,0x02,0xa8,0x00,0x06,0xa8,0x00,0xa4,0x83,0x02,0x16,0x3b,0xf1,0x5f,0x57,0xb5,0x06,0x7a,0x80,0x00,
                0x01,0x09,0x52,0x45,0x41,0x44,0x4d,0x45,0x2e,0x6d,0x64,0x23,0x20,0x55,0x6e,0x72,0x61,0x72,0x0a,0x0a,0x41,0x20,0x64,0x65,
                0x73,0x63,0x72,0x69,0x70,0x74,0x69,0x6f,0x6e,0x20,0x6f,0x66,0x20,0x74,0x68,0x69,0x73,0x20,0x70,0x61,0x63,0x6b,0x61,0x67,
                0x65,0x2e,0x0a,0x1d,0x77,0x56,0x51,0x03,0x05,0x04,0x00
            ]
            let rar = gecici.appending(path: "gercek-rar5.rar")
            try Data(rarBaytlari).write(to: rar, options: .atomic)
            let rarAcildi = try ArsivIslemleri.ac(rar, parola: nil)
            sonuc = [
                "tamamlandi": true,
                "zipDosya": zip.lastPathComponent,
                "zipDosyaSayisi": zipAcildi.1.count,
                "zipIcerikDogru": zipMetni == "Asistan ZIP kabulü",
                "rarDosyaSayisi": rarAcildi.1.count,
                "rarDosya": rarAcildi.1.first?.lastPathComponent ?? "",
                "rarBayt": try Data(contentsOf: rarAcildi.1[0]).count
            ]
        } catch { sonuc["hata"] = error.localizedDescription }
        Self.kaydet("asistan-arsiv-sinama.json", sonuc)
    }

    static func grokYetenekleriSina() async {
        var sonuc: [String: Any] = ["tamamlandi": false]
        let alan = "asistan.grok-kabul.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: alan) else { return }
        defer { defaults.removePersistentDomain(forName: alan) }
        do {
            let takim = UzmanTakimi(defaults: defaults)
            let uzman = try takim.uzmanlar.first { $0.ad == "Araştırmacı" }.unwrapped("Araştırmacı bulunamadı")
            takim.sec(uzman.id)
            let baglam = try takim.baglam(istek: "Kaynakları incele").unwrapped("Uzman bağlamı oluşmadı")
            let rutinAdi = "iPhone kabul \(UUID().uuidString.prefix(6))"
            let sunucu = SunucuGorevleri.ortak
            try await sunucu.rutinEkle(ad: rutinAdi, metin: "Tek cümlelik durum özeti hazırla", tur: "text", dakika: 10080)
            let rutin = try sunucu.rutinler.first { $0.name == rutinAdi }.unwrapped("Rutin sunucuda bulunamadı")
            try await sunucu.rutinEtkin(rutin, etkin: false)
            let durduruldu = sunucu.rutinler.first { $0.id == rutin.id }?.etkin == false
            if let silinecek = sunucu.rutinler.first(where: { $0.id == rutin.id }) { try await sunucu.rutinSil(silinecek) }
            sonuc = [
                "tamamlandi": true,
                "sablonUzmanSayisi": takim.uzmanlar.count,
                "uzmanBaglami": baglam.contains("Kaynak araştırması"),
                "beceriSayisi": BeceriKitapligi(defaults: defaults).beceriler.count,
                "rutinOlustu": true,
                "rutinDurdu": durduruldu,
                "rutinSilindi": !sunucu.rutinler.contains { $0.id == rutin.id }
            ]
        } catch { sonuc["hata"] = error.localizedDescription }
        Self.kaydet("asistan-grok-yetenekleri-sinama.json", sonuc)
    }

    static func kazimaSina() async {
        let html = """
        <!doctype html><html lang="tr"><head><title>Telefon Kazıma Sınaması</title>
        <meta name="description" content="Yerel deneme sayfası">
        <script type="application/ld+json">{"name":"Deneme Ürünü","price":42}</script></head>
        <body><h1>İstanbul verisi</h1><p>Telefon üzerinde çıkarıldı.</p>
        <a href="https://example.com/rapor.pdf">Rapor PDF</a>
        <img src="https://example.com/kapak.jpg" alt="Kapak">
        <audio src="https://example.com/ses.mp3"></audio>
        <video src="https://example.com/video.mp4"></video>
        <table><tr><th>Ad</th><th>Değer</th></tr><tr><td>Sıcaklık</td><td>21</td></tr></table></body></html>
        """
        let kaziyici = WebKaziyici()
        kaziyici.web.loadHTMLString(html, baseURL: URL(string: "https://example.com/test")!)
        try? await Task.sleep(for: .seconds(1))
        await kaziyici.tara()
        var sonuc: [String: Any] = ["durum": kaziyici.durum]
        if let rapor = kaziyici.rapor {
            sonuc["baslik"] = rapor.baslik
            sonuc["adet"] = rapor.ogeler.count
            sonuc["turler"] = Array(Set(rapor.ogeler.map(\.tur))).sorted()
            sonuc["pdf"] = rapor.ogeler.contains { $0.url == "https://example.com/rapor.pdf" && $0.tur == "dosya" }
            sonuc["csvBayt"] = (try? KazimaDisaAktarici.veri(rapor, csv: true).count) ?? 0
            sonuc["jsonBayt"] = (try? KazimaDisaAktarici.veri(rapor, csv: false).count) ?? 0
        }
        if let canliURL = URL(string: "https://example.com") {
            let canli = WebKaziyici()
            canli.ac(canliURL)
            for _ in 0..<20 {
                if canli.durum.hasPrefix("Sayfa hazır") { break }
                try? await Task.sleep(for: .milliseconds(250))
            }
            await canli.tara()
            sonuc["canliBaslik"] = canli.rapor?.baslik ?? ""
            sonuc["canliKaynak"] = canli.rapor?.kaynak ?? ""
            sonuc["canliOge"] = canli.rapor?.ogeler.count ?? 0
            sonuc["canliDurum"] = canli.durum
        }
        Self.kaydet("asistan-kazima-sinama.json", sonuc)
    }

    static func indirmeSina() async {
        var r: [String: Any] = ["kepceKurulu": KepceBaglantisi.kurulu]
        let k = IndirmeYoneticisi.ortak
        do {
            let id = try await k.ekle("https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf", tur: "file")
            for _ in 0..<60 {
                try await Task.sleep(for: .seconds(1))
                if let kayit = k.kayitlar.first(where: { $0.id == id }), !kayit.etkin {
                    r["dosyaDurum"] = kayit.durum; r["dosyaHata"] = kayit.hata
                    if let u = k.dosyaURL(kayit) {
                        let data = try Data(contentsOf: u); r["pdfDogrulandi"] = data.starts(with: Data("%PDF".utf8)); r["bayt"] = data.count
                    }
                    k.sil(kayit); break
                }
            }
            if KepceBaglantisi.kurulu {
                try await k.kepceyeAktar("https://download.samplelib.com/mp4/sample-5s.mp4", tur: "video")
                r["kepceAktarildi"] = true
            }
        } catch { r["hata"] = error.localizedDescription }
        Self.kaydet("asistan-indirme-sinama.json", r)
    }

    /// Yalnız bu oturumda kurulduğu dışarıdan doğrulanmış köprü için geliştirme kabul sınaması.
    static func dosyaKopruSina() async {
        let root = FileManager.default.temporaryDirectory.appending(path: "kopru-sinama-\(UUID())")
        var sonuc: [String: Any] = ["uygulamaSayisi": UygulamaKatalogu.ortak.uygulamalar.count, "kopruEtkin": UygulamaKatalogu.ortak.kopruEklendi]
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            let belgeler = root.appending(path: "Belgeler")
            try FileManager.default.createDirectory(at: belgeler, withIntermediateDirectories: true)
            try "İSTANBUL: hücre ve kalıtım örneği.".write(to: belgeler.appending(path: "Ornek.txt"), atomically: true, encoding: .utf8)
            let k = DosyaKitapligi(kayitURL: root.appending(path: "bag.json"))
            try k.bagla(belgeler)
            let r = try await k.ara("istanbul", icerikte: true)
            sonuc["dosyaEslesmesi"] = r.sonuclar.count
            if let x = r.sonuclar.first { sonuc["icerikOkundu"] = try await k.oku(x.id.uuidString).contains("kalıtım") }
            let arac = UygulamaAcAraci(onay: OnayKapisi())
            sonuc["pusulaAcmaIstegi"] = try await arac.call(arguments: .init(hedef: "Pusula"))
        } catch { sonuc["hata"] = error.localizedDescription }
        Self.kaydet("asistan-dosya-kopru-sinama.json", sonuc)
    }

    static func hizKabulSina() async {
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = false }
        await TelefonProxy.ortak.sina()
        let alan = "asistan.hiz-kabul.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: alan)!; defer { d.removePersistentDomain(forName: alan) }
        let a = Ayarlar(defaults: d)
        a.otomatikHafiza = false; a.heyAsistan = false; a.sesliYanit = false; a.sunucuGorevleri = false
        let kap = HafizaDeposu.kapOlustur(bellekte: true)
        let b = Beyin(ayarlar: a, depo: HafizaDeposu(baglam: kap.mainContext), onay: OnayKapisi(), modelVitesi: ModelVitesi(defaults: d))
        var turlar: [[String: Any]] = []
        // sakla(false) tur sürerken ara yazımdır (kosuBitti false); yalnız sondaki sakla(true) koşuyu bitirir.
        // Son yazımda tamamlandi, hiçbir turun bitmemiş olmamasına bağlıdır (kabul tur başarısızlığını sessiz geçmesin).
        func sakla(_ son: Bool) {
            let tamam = son && turlar.allSatisfy { ($0["bitti"] as? Bool) == true }
            Self.kaydet("asistan-hiz-kabul.json", ["tamamlandi": tamam, "turlar": turlar], bitti: son)
        }
        func tur(_ soru: String, ad: String) async {
            // Cihaz üzerinde kesilen/süresi uzayan model isteğinde hangi turun
            // takıldığını dosyadan doğrudan görebilmek için başlangıcı hemen yaz.
            turlar.append(["ad": ad, "durum": "başladı"])
            sakla(false)
            let index = turlar.index(before: turlar.endIndex)
            let bas = Date(); var ilk: Double?
            b.gonder(soru)
            while b.durum != .bosta, Date().timeIntervalSince(bas) < 55 {
                if ilk == nil, !b.akanMetin.isEmpty { ilk = Date().timeIntervalSince(bas) }
                try? await Task.sleep(for: .milliseconds(50))
            }
            let bitti = b.durum == .bosta; let toplam = Date().timeIntervalSince(bas)
            turlar[index] = ["ad": ad, "model": b.aktifModel ?? "", "caba": b.secilenCaba?.rawValue ?? "", "ilkSn": ilk ?? toplam,
                             "toplamSn": toplam, "bitti": bitti, "hata": b.sonHata ?? "", "yanit": b.mesajlar.last?.metin ?? ""]
            if !bitti { b.iptal() }; sakla(false)
        }
        sakla(false)
        await tur("Merhaba", ad: "otomatik-selam")
        await tur("Saat kaç?", ad: "otomatik-arac")
        await tur("Mavi rengini seçtim. Bana bu renkle ilgili iki cümlelik bir hikaye yaz.", ad: "sonnet-yazi")
        await tur("Bunu kısalt", ad: "haiku-baglam")
        await tur("The sky is blue cümlesini Türkçeye çevir.", ad: "gemini-ceviri")
        await tur("n=3 için n tekse karesi de tektir, kanıtla. İki cümle kullan.", ad: "gpt-zor")
        let soru = "Apple resmi kaynaklarında iPhone pil sağlığına hangi Ayarlar menüsünden bakıldığını web aramasıyla araştır. İki kısa cümle ve kaynak bağlantısı ver."
        b.yeniSohbet(); a.otomatikModel = true; a.calismaKipi = "arastirma"; a.caba = "auto"
        await tur(soru, ad: "web-dogrudan")
        a.calismaKipi = "sohbet"; a.webArama = false
        await tur("Az önceki araştırmandaki menü yolunu tek cümleyle tekrar söyle.", ad: "web-sonrasi-baglam")
        sakla(true)
    }

    /// Tek bir ilk-metni, fiziksel cihazda sağlayıcı takılmasına karşı korumanın
    /// gerçekten yedeğe düşüp düşmediğini kısa sürede görmek için ölçer.
    static func ilkMetinSina() async {
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = false }
        await TelefonProxy.ortak.sina()
        let alan = "asistan.ilk-metin.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: alan)!; defer { d.removePersistentDomain(forName: alan) }
        let a = Ayarlar(defaults: d)
        a.otomatikHafiza = false; a.heyAsistan = false; a.sesliYanit = false; a.sunucuGorevleri = false
        let kap = HafizaDeposu.kapOlustur(bellekte: true)
        let b = Beyin(ayarlar: a, depo: HafizaDeposu(baglam: kap.mainContext), onay: OnayKapisi(), modelVitesi: ModelVitesi(defaults: d))
        let baslangic = Date(); b.gonder("Merhaba")
        var ilkMetin: Double?
        while b.durum != .bosta, Date().timeIntervalSince(baslangic) < 45 {
            if ilkMetin == nil, !b.akanMetin.isEmpty { ilkMetin = Date().timeIntervalSince(baslangic) }
            try? await Task.sleep(for: .milliseconds(50))
        }
        let bitti = b.durum == .bosta
        if !bitti { b.iptal() }
        let sonuc: [String: Any] = [
            "tamamlandi": bitti,
            "ilkSn": ilkMetin ?? Date().timeIntervalSince(baslangic),
            "toplamSn": Date().timeIntervalSince(baslangic),
            "model": b.aktifModel ?? "",
            "hata": b.sonHata ?? "",
            "yanit": b.mesajlar.last?.metin ?? ""
        ]
        Self.kaydet("asistan-ilk-metin-sinama.json", sonuc)
    }

    static func hizSina() async {
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = false }
        await TelefonProxy.ortak.sina()
        var sonuclar: [[String: Any]] = []
        func sakla(_ tamam: Bool) {
            let veri: [String: Any] = ["tamamlandi": tamam, "modeller": TelefonProxy.ortak.modeller.map(\.id), "sonuclar": sonuclar]
            Self.kaydet("asistan-hiz-sinama.json", veri, bitti: tamam)
        }
        sakla(false)
        for model in ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-4-5", "gpt-6.1-sol", "gemini-3.8-flash"] {
            let alan = "asistan.hiz.\(UUID().uuidString)"
            let d = UserDefaults(suiteName: alan)!
            let a = Ayarlar(defaults: d)
            a.otomatikModel = false; a.modelKimligi = model; a.webArama = false; a.sesliYanit = false; a.otomatikHafiza = false; a.heyAsistan = false
            a.caba = "low"; a.calismaKipi = "sohbet"
            let kap = HafizaDeposu.kapOlustur(bellekte: true)
            let b = Beyin(ayarlar: a, depo: HafizaDeposu(baglam: kap.mainContext), onay: OnayKapisi())
            for soru in ["Merhaba, kısaca hazır olduğunu söyle.", "suankiSaat aracını kullanarak gerçek saati öğren, yalnız saati söyle."] {
                b.yeniSohbet()
                let bas = Date(); var ilk: Double?
                b.gonder(soru)
                while b.durum != .bosta, Date().timeIntervalSince(bas) < 45 {
                    if ilk == nil, !b.akanMetin.isEmpty { ilk = Date().timeIntervalSince(bas) }
                    try? await Task.sleep(for: .milliseconds(50))
                }
                let bitti = b.durum == .bosta
                let toplam = Date().timeIntervalSince(bas)
                sonuclar.append(["model": model, "soru": soru, "ilkSn": ilk ?? toplam, "toplamSn": toplam,
                                 "bitti": bitti, "hata": b.sonHata ?? "", "yanit": b.mesajlar.last?.metin ?? ""])
                if !bitti { b.iptal() }
                sakla(false)
            }
            d.removePersistentDomain(forName: alan)
        }
        sakla(true)
    }

    static func cabaSina() async {
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = false }
        let alan = "asistan.caba-test.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: alan)!
        defer { d.removePersistentDomain(forName: alan) }
        let a = Ayarlar(defaults: d)
        a.otomatikHafiza = false; a.heyAsistan = false; a.webArama = false
        a.sunucuGorevleri = false; a.calismaKipi = "sohbet"
        let kap = HafizaDeposu.kapOlustur(bellekte: true)
        let b = Beyin(ayarlar: a, depo: HafizaDeposu(baglam: kap.mainContext), onay: OnayKapisi())
        var turlar: [[String: Any]] = []
        for metin in ["Merhaba", "n=3 seçtim. n tekse n² tektir, kanıtla. En fazla iki cümle kullan.", "Python ile iki sayıyı toplayan tek satırlık fonksiyon yaz.", "2 + 2 kaç? Önceki mesajımda seçtiğim n değerini de söyle."] {
            let bas = Date()
            b.gonder(metin)
            while b.durum != .bosta, Date().timeIntervalSince(bas) < 90 {
                try? await Task.sleep(for: .milliseconds(100))
            }
            let bitti = b.durum == .bosta
            turlar.append(["istek": metin, "caba": b.secilenCaba?.rawValue ?? "yok", "model": a.modelKimligi,
                           "yol": b.aktifYol?.ad ?? "yok", "yanit": b.mesajlar.last?.metin ?? "", "hata": b.sonHata ?? "",
                           "bitti": bitti, "sn": Date().timeIntervalSince(bas)])
            Self.kaydet("asistan-caba-sinama.json", ["ayar": Ayarlar().caba, "turlar": turlar], bitti: false)
            if !bitti { b.iptal(); break }
        }
        Self.kaydet("asistan-caba-sinama.json", ["ayar": Ayarlar().caba, "turlar": turlar])
    }

    /// Gerçek mikrofon/Opus/TTS/dinlemeye dönüş sınaması. STT girdisi sabit test metnidir;
    /// gerçek kullanıcının uyandırma ve dikte başarısını kanıtlamaz. Kişisel sohbet arşivine yazmaz.
    static func liveSina() async {
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = false }
        let alan = "asistan.live-test.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: alan)!
        defer { d.removePersistentDomain(forName: alan) }
        let a = Ayarlar(defaults: d)
        a.heyAsistan = false; a.otomatikHafiza = false; a.sesliYanit = true
        a.sttMotoru = "apple"; a.calismaKipi = "sohbet"; a.webArama = false
        a.sesKimligi = Ayarlar().sesKimligi; a.canliMotor = "claude"
        let kap = HafizaDeposu.kapOlustur(bellekte: true)
        let b = Beyin(ayarlar: a, depo: HafizaDeposu(baglam: kap.mainContext), onay: OnayKapisi())
        let ses = SesOturumu(beyin: b, ayarlar: a)
        let calismaKimligi = UUID().uuidString
        let baslangicZamani = Date().timeIntervalSince1970
        var sonuc: [String: Any] = ["calismaKimligi": calismaKimligi, "baslangicUnix": baslangicZamani,
                                    "bitti": false, "elleModelAyari": a.modelKimligi,
                                    "otomatikModel": a.otomatikModel, "ses": a.sesKimligi,
                                    "girdi": "sabit metin; gerçek STT testi değil"]
        var turlar: [[String: Any]] = []
        func kaydet() {
            sonuc["turlar"] = turlar
            // Koşu yalnız `asama` "tamamlandi" olunca biter; öncekiler ara yazımdır.
            AsistanSinama.kaydet("asistan-live-sinama.json", sonuc, bitti: (sonuc["asama"] as? String) == "tamamlandi")
        }
        // Cihaz kilitliyken eski sonuç dosyasının yanlışlıkla yeni ölçüm gibi
        // okunmasını önlemek için, daha Live bağlantısı denenmeden oturum damgası yazılır.
        kaydet()
        await ses.canliModuAc()
        try? await Task.sleep(for: .seconds(2))
        sonuc["gercekZamanliEtkin"] = ses.gercekZamanliEtkin
        sonuc["gercekZamanliHata"] = ses.gercekLive.sonBaglantiHatasi ?? ""
        sonuc["canliDurum"] = ses.canliDurum
        sonuc["baslangicMikrofon"] = String(describing: ses.dinleyici.durum)
        sonuc["girisDb"] = ses.dinleyici.girisDb
        sonuc["canliMod"] = ses.canliMod
        sonuc["asama"] = "live_hazir"
        kaydet()
        for metin in ["Bu konuşma için seçtiğim renk mercan. Yalnız 'Mercan, aklımda.' de.", "Az önce seçtiğim renk neydi? Yalnız rengin adını söyle.", "Seçtiğim rengi bir kez daha söyle."] {
            guard ses.canliMod, ses.dinleyici.durum == .dinliyor else {
                sonuc["asama"] = "tur_baslatilamadi"
                sonuc["turBaslatmaDurumu"] = String(describing: ses.dinleyici.durum)
                sonuc["turBaslatmaCanli"] = ses.canliMod
                kaydet()
                break
            }
            let bas = Date()
            let eskiAdet = b.mesajlar.count
            sonuc["asama"] = "girdi_teslim_ediliyor"
            kaydet()
            var testOynatici: AVAudioPlayer?
            if ProcessInfo.processInfo.arguments.contains("--asistan-live-ses-sinama") {
                sonuc["girdi"] = "Azure test sesi hoparlörden fiziksel mikrofona; gerçek kullanıcı değil"
                do {
                    let data = try await AsistanSesleri.ses(metin, kimlik: a.sesKimligi)
                    let player = try AVAudioPlayer(data: data)
                    testOynatici = player
                    guard player.play() else { throw SunucuGorevleri.Hata.http(502) }
                } catch { sonuc["girdiHatasi"] = error.localizedDescription; kaydet(); break }
            } else {
                ses.dinleyici.kesinlesti?(metin, [], 16000)
            }
            sonuc["asama"] = "girdi_teslim_edildi"
            kaydet()
            var cikisTepe: Float = -100
            var ilkSes: Double?
            var dondu = false
            var sonAraKayit = Date.distantPast
            while Date().timeIntervalSince(bas) < 65 {
                try? await Task.sleep(for: .milliseconds(50))
                cikisTepe = max(cikisTepe, ses.konusmaci.cikisDb)
                if ilkSes == nil, ses.konusmaci.cikisDb > -80 { ilkSes = Date().timeIntervalSince(bas) }
                if Date().timeIntervalSince(sonAraKayit) >= 1 {
                    sonAraKayit = Date()
                    sonuc["asama"] = "yanit_bekleniyor"
                    sonuc["beklemeSn"] = Date().timeIntervalSince(bas)
                    sonuc["beyinDurumu"] = String(describing: b.durum)
                    sonuc["aktifModel"] = b.aktifModel ?? ""
                    sonuc["mesajSayisi"] = b.mesajlar.count
                    sonuc["sonHata"] = b.sonHata ?? ""
                    sonuc["mikrofonDurumu"] = String(describing: ses.dinleyici.durum)
                    sonuc["mikrofonHatasi"] = ses.uyandirmaHatasi ?? ""
                    kaydet()
                }
                if b.mesajlar.count > eskiAdet + 1, b.durum == .bosta, !ses.konusmaci.konusuyor, ses.dinleyici.durum == .dinliyor { dondu = true; break }
                if b.sonHata != nil || ses.konusmaci.sesHatasi != nil { break }
                if case .hata = ses.dinleyici.durum { break }
            }
            testOynatici?.stop()
            sonuc["asama"] = "tur_kaydediliyor"
            turlar.append(["mikrofonDurumu": String(describing: ses.dinleyici.durum), "mikrofonHatasi": ses.uyandirmaHatasi ?? "", "mikrofonYolu": ses.dinleyici.girisYolu, "model": b.aktifModel ?? "", "taninan": b.mesajlar.last(where: { $0.rol == .kullanici })?.metin ?? "", "istek": metin, "yanit": b.mesajlar.last(where: { $0.rol == .asistan })?.metin ?? "", "hata": b.sonHata ?? ses.konusmaci.sesHatasi ?? "", "bitti": dondu && ilkSes != nil, "dinlemeyeDondu": dondu, "canliMod": ses.canliMod, "sureSn": Date().timeIntervalSince(bas), "ilkSesSn": ilkSes ?? -1, "cikisDb": cikisTepe])
            kaydet()
            if !dondu { break }
        }
        sonuc["asama"] = "kapatiliyor"
        kaydet()
        await ses.sesliKipiKapat(); b.iptal()
        sonuc["durdu"] = !ses.canliMod && ses.dinleyici.durum == .kapali
        if ProcessInfo.processInfo.arguments.contains("--asistan-uyandirma-ses-sinama") {
            a.heyAsistan = true
            await ses.uyandirmayiEtkinlestir()
            do {
                let data = try await AsistanSesleri.ses("Hey Asistan", kimlik: a.sesKimligi)
                let player = try AVAudioPlayer(data: data)
                sonuc["uyandirmaSesCaldi"] = player.play()
                let bas = Date()
                while Date().timeIntervalSince(bas) < 10, !ses.sesliKip { try? await Task.sleep(for: .milliseconds(100)) }
                sonuc["testSesiyleUyandi"] = ses.sesliKip && !ses.uyandirmaBekliyor
                sonuc["uyandirmaMikrofon"] = String(describing: ses.dinleyici.durum)
                player.stop()
            } catch { sonuc["uyandirmaHata"] = error.localizedDescription }
            await ses.sesliKipiKapat()
        }
        let gecti = turlar.count == 3 && turlar.allSatisfy {
            ($0["bitti"] as? Bool) == true && ($0["hata"] as? String) == ""
                && ($0["yanit"] as? String)?.localizedCaseInsensitiveContains("mercan") == true
        } && (sonuc["durdu"] as? Bool) == true
        sonuc["bitti"] = gecti
        sonuc["tamamlandi"] = gecti
        sonuc["beklenenTur"] = 3
        if !gecti { sonuc["hata"] = "Üç turun yanıt, ses çıkışı, bağlam veya dinlemeye dönüş doğrulaması başarısız." }
        sonuc["asama"] = "tamamlandi"
        kaydet()
    }
    static func sesAkisiSina() async {
        let a = Ayarlar()
        let ses = Konusmaci(); ses.ayarlar = a
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        let bas = Date()
        ses.akisBasladi()
        ses.soyle("Merhaba Mehmet. Sesli konuşmamızda cümleler arasındaki beklemeyi azaltıyorum.")
        ses.soyle("Bir sonraki cümle, önceki cümle okunurken hazırlanıyor.")
        ses.akisBitti("")
        var ilkSes: Double?
        while Date().timeIntervalSince(bas) < 40, ses.konusuyor {
            if ilkSes == nil, ses.cikisDb > -80 { ilkSes = Date().timeIntervalSince(bas) }
            try? await Task.sleep(for: .milliseconds(50))
        }
        let sonuc: [String: Any] = ["ses": a.sesKimligi, "ilkSesSn": ilkSes ?? -1, "parca": ses.oynatilanParcaSayisi, "hazirGecis": ses.oncedenHazirGecisSayisi, "sonUretimMs": ses.sonUretimMs ?? -1, "tamamlandi": !ses.konusuyor && ilkSes != nil && ses.oynatilanParcaSayisi >= 2, "bitti": !ses.konusuyor, "hata": ses.sesHatasi ?? ""]
        ses.sustur()
        Self.kaydet("asistan-ses-akis-sinama.json", sonuc)
    }

    static func sesSina() async {
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = false }
        let a = Ayarlar()
        var kayit: [String: Any] = ["tamamlandi": false]
        do {
            await AsistanSesleri.ortak.yenile()
            kayit["sesSayisi"] = AsistanSesleri.ortak.sesler.count
            let bas = Date()
            let data = try await AsistanSesleri.ses("Merhaba Mehmet. Ben senin asistanınım. Bugün sana nasıl yardımcı olabilirim?", kimlik: a.sesKimligi)
            let player = try AVAudioPlayer(data: data)
            kayit["uretimMs"] = Int(Date().timeIntervalSince(bas) * 1000)
            kayit["sure"] = player.duration
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
            kayit["oynatmaBasladi"] = player.play()
            try await Task.sleep(for: .seconds(player.duration + 0.5))
            kayit["oynatmaBitti"] = !player.isPlaying
            kayit["ses"] = a.sesKimligi
            kayit["tamamlandi"] = (kayit["oynatmaBasladi"] as? Bool) == true && !player.isPlaying
        } catch { kayit["hata"] = error.localizedDescription }
        Self.kaydet("asistan-ses-sinama.json", kayit)
    }
    static func sunucuSina() async {
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = false }
        var kayit: [String: Any] = [:]
        do {
            let g = try await SunucuGorevleri.ortak.ekle("Türkçe tek cümleyle Mehmet'e merhaba de.", tur: "text")
            kayit = ["id": g.id, "durum": g.status]
            Self.kaydet("asistan-sunucu-sinama.json", kayit, bitti: false)
            for _ in 0..<50 {
                try await Task.sleep(for: .seconds(5)); await SunucuGorevleri.ortak.yenile()
                if let son = SunucuGorevleri.ortak.gorevler.first(where: { $0.id == g.id }) {
                    kayit = ["id": son.id, "durum": son.status, "yanit": son.result, "hata": son.error]
                    Self.kaydet("asistan-sunucu-sinama.json", kayit, bitti: false)
                    if !son.etkin { break }
                }
            }
        } catch { kayit["hata"] = error.localizedDescription }
        Self.kaydet("asistan-sunucu-sinama.json", kayit)
    }
    static func otomatikSina() async {
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = false }
        let alan = "asistan.otomatik-sinama.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: alan)!
        defer { d.removePersistentDomain(forName: alan) }
        let a = Ayarlar(defaults: d); a.modelKimligi = "gpt-6.1-sol"; a.otomatikHafiza = false; a.sesliYanit = false; a.webArama = false
        let kap = HafizaDeposu.kapOlustur(bellekte: true)
        let beyin = Beyin(ayarlar: a, depo: HafizaDeposu(baglam: kap.mainContext), onay: OnayKapisi())
        let vakalar: [(String, String, CalismaKipi, CalismaKipi)] = [
            ("Python ile CSV dosyasını okuyup toplam hesaplayan fonksiyon yaz", "", .sohbet, .kod),
            ("Buna birim testlerini de ekle", "Python ile CSV toplayan fonksiyon yaz", .kod, .kod),
            ("Bana kısa bir doğum günü mesajı hazırla", "", .sohbet, .yazi),
            ("Bunu daha samimi yap", "Doğum günü mesajı hazırla", .yazi, .yazi),
            ("Apple'ın güncel iPhone mikrofon desteğini resmi kaynaklardan araştır", "", .sohbet, .arastirma),
            ("Uzayda bir kütüphanenin suluboya resmini çiz", "", .sohbet, .gorsel),
            ("Resim üretme, bunun için bir açıklama metni yaz", "", .gorsel, .yazi),
            ("Şimdi YouTube'u aç", "Python kodu yaz", .kod, .sohbet),
            ("Sohbet arşivini aç", "", .sohbet, .arsiv)
        ]
        var sonuclar: [[String: Any]] = []
        for (istek, onceki, kip, beklenen) in vakalar {
            let baslangic = Date()
            let sonuc = await beyin.kipSec(istek, ekVar: false, oncekiIstek: onceki, oncekiKip: kip)
            sonuclar.append(["istek": istek, "beklenen": beklenen.rawValue, "secilen": sonuc.rawValue, "basarili": sonuc == beklenen, "sureMs": Date().timeIntervalSince(baslangic) * 1000])
            Self.kaydet("asistan-otomatik-sinama.json", dizi: sonuclar, bitti: false)
        }
        beyin.gonder("Üç cümlelik bir teşekkür mesajı yaz.")
        let bas = Date()
        while beyin.durum != .bosta, Date().timeIntervalSince(bas) < 60 { try? await Task.sleep(for: .milliseconds(200)) }
        sonuclar.append(["istek": "tam akis: tesekkur mesaji", "secilen": beyin.aktifKip.rawValue, "sesliOkunur": beyin.seslendirilebilir, "sureMs": Date().timeIntervalSince(bas) * 1000, "tamamlandi": beyin.durum == .bosta,
                         "hata": beyin.sonHata ?? "", "yanit": beyin.mesajlar.last(where: { $0.rol == .asistan })?.metin ?? ""])
        if beyin.durum != .bosta { beyin.iptal() }
        do {
            let hava = try await HavaAraci().call(arguments: .init(yer: "İstanbul"))
            let saatSayisi = EkDefteri.ortak.bekleyen.compactMap { e -> HavaOzeti? in if case .hava(let h) = e.tur { h } else { nil } }.last?.saatler.count ?? 0
            EkDefteri.ortak.temizle()   // sınama turu sonraki isteğe kart bırakmasın
            sonuclar.append(["istek": "canli hava karti", "yanit": hava, "saatSayisi": saatSayisi])
        } catch { sonuclar.append(["istek": "canli hava karti", "hata": error.localizedDescription]) }
        a.calismaKipi = "sohbet"
        beyin.gonder("Saat kaç? Önce saat aracını kullan.")
        let aracBas = Date()
        while beyin.durum != .bosta, Date().timeIntervalSince(aracBas) < 70 { try? await Task.sleep(for: .milliseconds(200)) }
        sonuclar.append(["istek": "canli arac gunlugu", "sureMs": Date().timeIntervalSince(aracBas) * 1000, "tamamlandi": beyin.durum == .bosta, "adimlar": beyin.gorevler.adimlar.map { ["ad": $0.ad, "durum": $0.durum] }, "hata": beyin.sonHata ?? "", "yanit": beyin.mesajlar.last(where: { $0.rol == .asistan })?.metin ?? ""])
        if beyin.durum != .bosta { beyin.iptal() }
        Self.kaydet("asistan-otomatik-sinama.json", dizi: sonuclar)
    }
    static func webYeniSina() async {
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = false }
        var sonuc: [String: Any] = [:]
        let baslangic = Date()
        do { sonuc["webYanit"] = try await WebArastirici.ara("Apple iPhone Mirroring açıkken iPhone mikrofonu kullanılabilir mi? Resmi destek sayfasını bul.") }
        catch { sonuc["hata"] = error.localizedDescription }
        sonuc["sureSn"] = Date().timeIntervalSince(baslangic)
        Self.kaydet("asistan-web-yeni.json", sonuc)
    }
    static func webHamSina() async {
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = false }
        let p = TelefonProxy.ortak
        await p.hazirla()
        var sonuclar: [[String: Any]] = []
        let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appending(path: "asistan-web-sinama.json")
        Self.kaydet("asistan-web-sinama.json", dizi: [], bitti: false)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 45; config.timeoutIntervalForResource = 45
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        for surum in ["web_search_20260209", "web_search_20250305"] {
            var r = URLRequest(url: p.taban.appending(path: "v1/messages"))
            r.httpMethod = "POST"; r.timeoutInterval = 120
            r.setValue("Bearer \(p.yerelAnahtar)", forHTTPHeaderField: "Authorization")
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: Any] = ["model": "claude-opus-5-5", "max_tokens": 2000, "stream": false,
                "messages": [["role": "user", "content": "Search Apple support for iPhone Mirroring microphone support. Give a short answer with the source URL."]],
                "tools": [["type": surum, "name": "web_search", "max_uses": 2]]]
            do {
                r.httpBody = try JSONSerialization.data(withJSONObject: body)
                let (d, response) = try await session.data(for: r)
                let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
                let content = obj?["content"] as? [[String: Any]] ?? []
                sonuclar.append(["surum": surum, "http": (response as? HTTPURLResponse)?.statusCode ?? 0,
                    "tip": (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? "", "bayt": d.count,
                    "bloklar": content.compactMap { $0["type"] as? String }, "bitis": obj?["stop_reason"] ?? "",
                    "metin": content.compactMap { $0["text"] as? String }.joined(), "hata": obj?["error"] ?? ""])
            } catch { sonuclar.append(["surum": surum, "hata": error.localizedDescription]) }
            Self.kaydet("asistan-web-sinama.json", dizi: sonuclar, bitti: false)
        }
        do {
            let img = try await GorselUretici.uret(model: "gemini-3-pro-image", istem: "A plain blue circle on a white background, no text.")
            sonuclar.append(["gorselModel": "gemini-3-pro-image", "genislik": Int(img.size.width * img.scale), "yukseklik": Int(img.size.height * img.scale)])
            try img.pngData()?.write(to: file.deletingLastPathComponent().appending(path: "asistan-gorsel-sinama.png"), options: .atomic)
        } catch { sonuclar.append(["gorselModel": "gemini-3-pro-image", "hata": error.localizedDescription]) }
        Self.kaydet("asistan-web-sinama.json", dizi: sonuclar)
    }
    static func atolyeyiSina() async {
        let eski = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = eski }
        let proxy = TelefonProxy.ortak
        await proxy.sina()
        let dizin = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var sonuc: [String: Any] = ["tamamlandi": false]
        func sakla(_ bitti: Bool = false) {
            Self.kaydet("asistan-atolye-sinama.json", sonuc, bitti: bitti, klasor: dizin)
        }
        sakla()
        let alan = "asistan.atolye-sinama.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: alan)!
        defer { d.removePersistentDomain(forName: alan) }
        let a = Ayarlar(defaults: d)
        a.modelKimligi = "claude-opus-5-5"; a.webArama = true; a.sesliYanit = false; a.otomatikHafiza = false; a.calismaKipi = "arastirma"
        let kap = HafizaDeposu.kapOlustur(bellekte: true)
        let onay = OnayKapisi(); onay.otomatikKarar = false
        let beyin = Beyin(ayarlar: a, depo: HafizaDeposu(baglam: kap.mainContext), onay: onay)
        beyin.gonder("Apple'ın resmi kaynaklarında iPhone Mirroring kullanılırken iPhone mikrofonunun çalışıp çalışmadığını web aramasıyla kontrol et. İki cümle ve kaynak bağlantısını ver.")
        let bas = Date()
        while beyin.durum != .bosta, Date().timeIntervalSince(bas) < 120 { try? await Task.sleep(for: .milliseconds(250)) }
        if beyin.durum != .bosta { beyin.iptal() }
        sonuc["webAramaSayisi"] = beyin.sinamaWebAramaSayisi
        sonuc["webYanit"] = beyin.mesajlar.last(where: { $0.rol == .asistan })?.metin ?? ""
        sonuc["webHata"] = beyin.sonHata ?? ""
        sakla()
        if let model = proxy.modeller.first(where: { $0.id == "gemini-3-pro-image" }) ?? proxy.modeller.first(where: \.gorselUretir) {
            sonuc["gorselModel"] = model.id
            sakla()
            do {
                let img = try await GorselUretici.uret(model: model.id, istem: "A simple flat blue circle on a plain white background, no text.")
                sonuc["gorselGenislik"] = Int(img.size.width * img.scale)
                sonuc["gorselYukseklik"] = Int(img.size.height * img.scale)
                if let png = img.pngData() { try png.write(to: dizin.appending(path: "asistan-gorsel-sinama.png"), options: .atomic) }
            } catch { sonuc["gorselHata"] = error.localizedDescription }
        }
        sonuc["tamamlandi"] = true
        sakla(true)
    }

    static func modelleriSina() async {
        let eski = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = eski }
        let proxy = TelefonProxy.ortak
        await proxy.sina()
        var sonuclar: [[String: Any]] = []
        func sakla(_ tamam: Bool) {
            let nesne: [String: Any] = ["tamamlandi": tamam, "modeller": proxy.modeller.map(\.id), "sonuclar": sonuclar]
            Self.kaydet("asistan-modeller-sinama.json", nesne, bitti: tamam)
        }
        sakla(false)
        let tercihler = ["claude-opus-5-5", "gpt-6.1-sol", "gemini-3.8-flash", "gemini-3.5-flash"]
        for aile in ["Claude", "ChatGPT / Codex", "Gemini", "Grok"] {
            let adaylar = proxy.modeller.filter { $0.aile == aile && $0.sohbet }
            guard let model = tercihler.compactMap({ id in adaylar.first { $0.id == id } }).first ?? adaylar.first else {
                sonuclar.append(["aile": aile, "durum": "bagli_model_yok"]); sakla(false); continue
            }
            let alan = "asistan.model-sinama.\(UUID().uuidString)"
            let d = UserDefaults(suiteName: alan)!
            let a = Ayarlar(defaults: d)
            a.otomatikModel = false; a.modelKimligi = model.id; a.webArama = false; a.sesliYanit = false; a.otomatikHafiza = false
            let kap = HafizaDeposu.kapOlustur(bellekte: true)
            let depo = HafizaDeposu(baglam: kap.mainContext)
            let onay = OnayKapisi(); onay.otomatikKarar = false
            let beyin = Beyin(ayarlar: a, depo: depo, onay: onay)
            let bas = Date()
            beyin.gonder("İşlev sınaması: suankiSaat aracını kullanarak gerçek saati öğren ve yalnız 'Saat HH:mm, hazırım.' diye cevap ver.")
            while beyin.durum != .bosta, Date().timeIntervalSince(bas) < 90 { try? await Task.sleep(for: .milliseconds(200)) }
            let asim = beyin.durum != .bosta
            if asim { beyin.iptal() }
            let yanit = beyin.mesajlar.last(where: { $0.rol == .asistan })?.metin ?? ""
            let kayitlar = await proxy.motor.log.records.filter { $0.model == model.id }
            sonuclar.append(["aile": aile, "model": model.id, "basarili": !asim && beyin.sonHata == nil && !yanit.isEmpty,
                             "yanit": yanit, "hata": beyin.sonHata ?? "", "saniye": Int(Date().timeIntervalSince(bas)),
                             "yollar": kayitlar.map(\.route)])
            d.removePersistentDomain(forName: alan)
            sakla(false)
        }
        sakla(true)
    }

    static func gelenKutusuSina() {
        let dosya = FileManager.default.temporaryDirectory.appending(path: "gelen-kutusu-sinama-\(UUID().uuidString).json")
        let kutu = GelenKutusu(dosya: dosya)
        let mail = kutu.ekle(kaynak: "E-posta", gonderen: "Ayşe", metin: "Toplantı yarın saat 10.00'da.")
        let whatsapp = kutu.ekle(kaynak: "whatsapp bildirimi", gonderen: "Mehmet", metin: "On dakika sonra geliyorum.")
        if let id = kutu.iletiler.last?.id { kutu.okundu(id) }
        let yeniden = GelenKutusu(dosya: dosya)
        let sonuc: [String: Any] = [
            "tamamlandi": mail && whatsapp && yeniden.iletiler.count == 2,
            "kaynaklar": yeniden.iletiler.map(\.kaynak),
            "gonderenler": yeniden.iletiler.map(\.gonderen),
            "okunmamis": yeniden.okunmamis,
            "kalici": yeniden.iletiler.count == 2
        ]
        Self.kaydet("asistan-gelen-kutusu-sinama.json", sonuc)
        try? FileManager.default.removeItem(at: dosya)
    }

    /// iPhone Keychain'indeki mevcut bağlantıyla Live token yolunu dener.
    /// Sunucu adresi, kişisel token veya geçici Live token hiçbir zaman diske yazılmaz.
    static func liveBaglantiSina() async {
        var sonuc: [String: Any] = ["tamamlandi": false, "durum": "baslatiliyor"]
        defer { Self.kaydet("asistan-live-baglanti-sinama.json", sonuc) }
        guard let taban = Gizli.vekilTaban, let token = Gizli.vekilToken else {
            sonuc["durum"] = "baglanti_yok"
            return
        }
        do {
            var istek = URLRequest(url: SunucuGorevleri.asistanAdresi(taban, "live-token"))
            istek.httpMethod = "POST"
            istek.httpBody = Data("{}".utf8)
            istek.timeoutInterval = 15
            istek.setValue("application/json", forHTTPHeaderField: "Content-Type")
            istek.setValue(token, forHTTPHeaderField: "X-Personal-Token")
            let (veri, yanit) = try await URLSession.shared.data(for: istek)
            let kod = (yanit as? HTTPURLResponse)?.statusCode ?? 0
            sonuc["httpDurumu"] = kod
            if kod == 200,
               let nesne = try? JSONSerialization.jsonObject(with: veri) as? [String: Any],
               let model = nesne["model"] as? String {
                sonuc["tamamlandi"] = true
                sonuc["durum"] = "gercek_zamanli_hazir"
                sonuc["model"] = model
            } else {
                sonuc["durum"] = "sirali_live_geri_donus"
            }
        } catch {
            sonuc["durum"] = "sirali_live_geri_donus"
            sonuc["agHatasi"] = true
        }
    }

    static func calistir() async {
        let onceki = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = onceki }
        var sonuc: [String: Any] = ["zaman": ISO8601DateFormatter().string(from: .now), "asama": "baglanti"]
        // Ara yazımlar (asama "tamamlandi" olmadan) koşuyu bitirmez; bağlantı hatası ve son yazım sakla(true) ile biter.
        func sakla(_ bitti: Bool = false) {
            Self.kaydet("asistan-sinama.json", sonuc, bitti: bitti)
        }
        let proxy = TelefonProxy.ortak
        await proxy.sina()
        sonuc["telefonProxyHazir"] = proxy.hazir
        sonuc["hesapSayisi"] = proxy.hesapSayisi
        sonuc["modelSinamasi"] = proxy.sonSinama ?? "yok"
        sonuc["turkceSesVar"] = Konusmaci.turkceSes != nil
        sonuc["asama"] = "gercek_model_ve_araclar"
        sakla()
        guard proxy.hazir else { sonuc["asama"] = "baglanti_hatasi"; sakla(true); return }
        let alan = "asistan.sinama.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: alan)!
        defer { defaults.removePersistentDomain(forName: alan) }
        let ayar = Ayarlar(defaults: defaults)
        ayar.sesliYanit = false; ayar.webArama = false; ayar.otomatikHafiza = false
        let kap = HafizaDeposu.kapOlustur(bellekte: true)
        let depo = HafizaDeposu(baglam: kap.mainContext)
        let onay = OnayKapisi(); onay.otomatikKarar = false
        let beyin = Beyin(ayarlar: ayar, depo: depo, onay: onay)
        beyin.gonder("Bu bir işlev sınamasıdır. suankiSaat aracını ve cihaz aracının pil işlemini kullan. Hafıza aracına 'Sınama rengi turkuaz' bilgisini kaydet. Gerçek saat ve pil yüzdesini tek cümlede söyle.")
        let baslangic = Date()
        while beyin.durum != .bosta, Date().timeIntervalSince(baslangic) < 150 {
            try? await Task.sleep(for: .milliseconds(200))
        }
        let zamanAsimi = beyin.durum != .bosta
        if zamanAsimi { beyin.iptal() }
        sonuc["sureSaniye"] = Int(Date().timeIntervalSince(baslangic))
        sonuc["zamanAsimi"] = zamanAsimi
        sonuc["model"] = ayar.modelKimligi
        sonuc["yol"] = beyin.aktifYol?.ad ?? "yok"
        sonuc["hata"] = beyin.sonHata ?? ""
        sonuc["yanit"] = beyin.mesajlar.last(where: { $0.rol == .asistan })?.metin ?? ""
        sonuc["hafizaAraciCalisti"] = depo.olgular().contains { $0.metin.localizedCaseInsensitiveContains("turkuaz") }
        sonuc["istekYollari"] = await proxy.motor.log.records.map(\.route)
        sonuc["asama"] = "tamamlandi"
        sakla(true)
    }
}

private extension Optional {
    func unwrapped(_ mesaj: String) throws -> Wrapped {
        guard let self else { throw NSError(domain: "AsistanSinama", code: 1, userInfo: [NSLocalizedDescriptionKey: mesaj]) }
        return self
    }
}
#endif
