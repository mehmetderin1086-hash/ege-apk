import CoreSpotlight
import Foundation
import Photos
import SwiftData
import Testing
@testable import Asistan

/// P4.4: sistem genelinde görünürlük (Spotlight varlıkları, Siri yanıt kartı, fotoğraf araması ve OCR indeksi).
/// Ağ, izin ve gerçek model gerektirmez; Spotlight sonuç görünümü, Siri kartının çizimi ve BGProcessing telefonda elle denenir.
@Suite("P4.4-Sistem görünürlüğü") @MainActor
struct Gelistirme_P4_4_SistemGorunurlukTestleri {

    // MARK: (a) Spotlight öznitelikleri

    @Test func ozelliklerVarsayilanYalnizBaslik() {
        let a = AsistanSpotlight.ozellikler(baslik: "Mitoz sunumu", icerik: "Gizli ilk mesaj", icerikDahil: false)
        #expect(a.title == "Mitoz sunumu")
        #expect(a.displayName == "Mitoz sunumu")
        #expect(a.contentDescription == nil)
    }

    @Test func ozelliklerIcerikAcikken200Karakter() {
        let uzun = String(repeating: "a", count: 500)
        let a = AsistanSpotlight.ozellikler(baslik: "B", icerik: uzun, icerikDahil: true)
        #expect(a.contentDescription?.count == AsistanSpotlight.ozetSiniri)
        // Boş içerik özet üretmez.
        #expect(AsistanSpotlight.ozellikler(baslik: "B", icerik: "   ", icerikDahil: true).contentDescription == nil)
    }

    @Test func spotlightTestteKapali() {
        #expect(AsistanSpotlight.kapali)   // birim testleri sistem indeksini kirletmez
    }

    @Test func kimlikAyiklaBicimlerdenUUID() {
        let u = UUID()
        #expect(AsistanSpotlight.kimlikAyikla(u.uuidString) == u)
        #expect(AsistanSpotlight.kimlikAyikla("SohbetVarligi/\(u.uuidString)") == u)
        #expect(AsistanSpotlight.kimlikAyikla("bozuk") == nil)
        #expect(AsistanSpotlight.kimlikAyikla(nil) == nil)
    }

    // MARK: (b) Fotoğraf metni indeksi

    @Test func fotoIndeksiAksansizArarVeIsaretler() {
        let i = FotoIndeksi(bellekte: true)
        #expect(i.hazir)
        let t = Date(timeIntervalSince1970: 1_790_000_000)
        i.ekle(kimlik: "A/L0/001", tarih: t, metin: "Biyoloji Sınavı 12 Kasım, 3. ders saati")
        i.ekle(kimlik: "B/L0/001", tarih: t, metin: "Market listesi: süt, ekmek")
        let b = i.ara("sinav")
        #expect(b.map(\.kimlik) == ["A/L0/001"])
        #expect(b.first?.tarih == t)
        #expect(b.first?.alinti.contains("Sınavı") == true)   // alıntı özgün metinden
        #expect(i.ara("SÜT").map(\.kimlik) == ["B/L0/001"])
        #expect(i.sayi() == 2)
        // İşlendi: aynı ya da eski değişim tarihi işlenmiş, daha yeni değişim yeniden okunur.
        #expect(i.islendi(kimlik: "A/L0/001", degisim: t))
        #expect(i.islendi(kimlik: "A/L0/001", degisim: t.addingTimeInterval(-60)))
        #expect(!i.islendi(kimlik: "A/L0/001", degisim: t.addingTimeInterval(60)))
        #expect(!i.islendi(kimlik: "C/L0/001", degisim: t))
    }

    @Test func fotoIndeksiKisaMetinYalnizIsaretlenir() {
        let i = FotoIndeksi(bellekte: true)
        let t = Date.now
        i.ekle(kimlik: "K/1", tarih: t, metin: "ok")
        #expect(i.sayi() == 0)
        #expect(i.islenenSayisi() == 1)
        #expect(i.islendi(kimlik: "K/1", degisim: t))
    }

    @Test func fotoIndeksiYenidenEkleDegistirirTemizleSifirlar() {
        let i = FotoIndeksi(bellekte: true)
        let t = Date.now
        i.ekle(kimlik: "A/1", tarih: t, metin: "Eski yazı burada duruyor")
        i.ekle(kimlik: "A/1", tarih: t, metin: "Yeni yazı fotosentez", degisim: t.addingTimeInterval(10))
        #expect(i.sayi() == 1)
        #expect(i.ara("eski").isEmpty)
        #expect(i.ara("fotosentez").count == 1)
        #expect(i.islendi(kimlik: "A/1", degisim: t.addingTimeInterval(10)))
        i.temizle()
        #expect(i.sayi() == 0)
        #expect(i.islenenSayisi() == 0)
        #expect(!i.islendi(kimlik: "A/1", degisim: t))
        #expect(i.ara("").isEmpty)
    }

    // MARK: (c) Fotoğraf süzgeci

    @Test func tarihAraligiYalnizGunTamGun() throws {
        let r = try #require(FotoSuzgeci.tarihAraligi(baslangic: "2026-10-15", bitis: nil))
        let k = Calendar.current
        let bas = try #require(r.bas), bit = try #require(r.bit)
        let b = k.dateComponents([.year, .month, .day, .hour, .minute, .second], from: bas)
        let s = k.dateComponents([.year, .month, .day, .hour, .minute, .second], from: bit)
        #expect(b.day == 15 && b.hour == 0 && b.minute == 0 && b.second == 0)
        #expect(s.day == 15 && s.hour == 23 && s.minute == 59 && s.second == 59)
    }

    @Test func tarihAraligiBitisGunSonuVeTersAralik() throws {
        let r = try #require(FotoSuzgeci.tarihAraligi(baslangic: "2026-10-01", bitis: "2026-10-03"))
        let s = Calendar.current.dateComponents([.day, .hour, .minute], from: try #require(r.bit))
        #expect(s.day == 3 && s.hour == 23 && s.minute == 59)
        #expect(FotoSuzgeci.tarihAraligi(baslangic: "2026-10-20", bitis: "2026-10-10") == nil)
        // Saatli başlangıç olduğu gibi kalır, bitiş açık.
        let saatli = try #require(FotoSuzgeci.tarihAraligi(baslangic: "2026-10-15T08:30", bitis: nil))
        #expect(saatli.bit == nil)
        #expect(Calendar.current.component(.hour, from: try #require(saatli.bas)) == 8)
        // Boş ve çözülemeyen tarih yok sayılır.
        let bos = try #require(FotoSuzgeci.tarihAraligi(baslangic: "", bitis: "dün"))
        #expect(bos.bas == nil && bos.bit == nil)
    }

    @Test func turOzellikleri() {
        let e = FotoSuzgeci.ozellikler(tur: "ekranGoruntusu")
        #expect(e.medya == .image && e.alt == .photoScreenshot && e.album == .smartAlbumScreenshots)
        let s = FotoSuzgeci.ozellikler(tur: "selfie")
        #expect(s.alt == nil && s.album == .smartAlbumSelfPortraits)
        #expect(FotoSuzgeci.ozellikler(tur: "canli").alt == .photoLive)
        #expect(FotoSuzgeci.ozellikler(tur: "video").medya == .video)
        let h = FotoSuzgeci.ozellikler(tur: "hepsi")
        #expect(h.medya == nil && h.alt == nil && h.album == nil)
        #expect(FotoSuzgeci.ozellikler(tur: nil).medya == nil)
    }

    @Test func predicateAnahtarlari() throws {
        let r = try #require(FotoSuzgeci.tarihAraligi(baslangic: "2026-10-15", bitis: nil))
        let p = try #require(FotoSuzgeci.predicate(medya: .image, bas: r.bas, bit: r.bit))
        #expect(p.predicateFormat.contains("mediaType"))
        #expect(p.predicateFormat.contains("creationDate >="))
        #expect(p.predicateFormat.contains("creationDate <="))
        #expect(FotoSuzgeci.predicate(medya: nil, bas: nil, bit: nil) == nil)
    }

    // MARK: (d) Sohbet varlığı

    @Test func sohbetVarligiGorunumuBasligiTasir() {
        let v = SohbetVarligi(id: UUID(), baslik: "Hücre bölünmesi", tarih: .now)
        #expect(String(localized: v.displayRepresentation.title) == "Hücre bölünmesi")
        #expect(v.ozet == nil)
        #expect(v.baslik == "Hücre bölünmesi")
    }

    // MARK: (e) Sohbet sorgusu (bellek içi kap)

    @Test func sohbetSorgusuKimligeGoreBulur() throws {
        let kap = HafizaDeposu.kapOlustur(bellekte: true)
        let depo = HafizaDeposu(baglam: kap.mainContext)
        let s = depo.sohbetOlustur()
        depo.ekle(.kullanici, "Mayoz bölünme özeti", sohbet: s)
        let bos = depo.sohbetOlustur()
        let bulunan = SohbetSorgusu.bul([s.kimlik, UUID()], baglam: kap.mainContext)
        #expect(bulunan.map(\.id) == [s.kimlik])
        #expect(bulunan.first?.baslik == "Mayoz bölünme özeti")
        #expect(SohbetSorgusu.ara("mayoz", baglam: kap.mainContext).map(\.id) == [s.kimlik])
        #expect(Set(SohbetSorgusu.sonlar(baglam: kap.mainContext).map(\.id)) == [s.kimlik, bos.kimlik])
        // Boş "Yeni sohbet" Spotlight'a yazılmaz; adı konmuş sohbet yazılır.
        #expect(!AsistanSpotlight.yazilir(bos))
        #expect(AsistanSpotlight.yazilir(s))
        // İçerik özeti yalnız istenince ve ilk kullanıcı mesajından.
        #expect(AsistanSpotlight.varlik(s, icerikDahil: false).ozet == nil)
        #expect(AsistanSpotlight.varlik(s, icerikDahil: true).ozet == "Mayoz bölünme özeti")
    }

    @Test func olguSorgusuTumTerimleriArar() {
        let l = [OlguVarligi(id: UUID(), metin: "Kızımın okulu Kadıköy'de", kategori: "kisi"),
                 OlguVarligi(id: UUID(), metin: "Çay şekersiz içerim", kategori: "tercih")]
        #expect(OlguSorgusu.ara("kadikoy okulu", olgular: l).map(\.kategori) == ["kisi"])
        #expect(OlguSorgusu.ara("SEKERSIZ", olgular: l).map(\.kategori) == ["tercih"])
        #expect(OlguSorgusu.ara("ve", olgular: l).isEmpty)
    }

    // MARK: (f) Araç şeması

    @Test func fotografAraciSemasiDuz() throws {
        let a = FotografAraci(onay: OnayKapisi())
        #expect(a.name == "fotograflar")
        let s = String(decoding: try JSONEncoder().encode(a.parameters), as: UTF8.self)
        #expect(!s.contains("$ref") && !s.contains("$defs"), "\(s.prefix(200))")
        for alan in ["islem", "baslangic", "bitis", "yer", "album", "tur", "metin", "adet", "kimlikler"] {
            #expect(s.contains("\"\(alan)\""), "\(alan) şemada yok")
        }
    }

    // MARK: (g) Siri yanıtlayıcı ve kart

    @Test func siriSonucKarsilastirmalariDerlenir() {
        #expect(SiriYanitlayici.yarisSonucu(Beyin.yarisAramaIsareti) == .uygulamada)
        #expect(SiriYanitlayici.yarisSonucu("Merhaba") != .uygulamada)
    }

    @Test func yanitKartiMetni600Karakter() {
        let k = YanitKartiIntent(metin: "Yanıt", sohbetKimligi: nil)
        #expect(k.metin == "Yanıt")
        #expect(k.sohbetKimligi == nil)
        let uzun = String(repeating: "kelime ", count: 200)
        let m = YanitKarti.kartMetni(uzun)
        #expect(m.count == 600)
        #expect(m.hasSuffix("…"))
        #expect(YanitKarti.kartMetni("Kısa yanıt") == "Kısa yanıt")
    }

    // MARK: (h) Kısa kimlik tablosu

    @Test func kisaKimlikTablosuBilinmeyeniReddeder() {
        let tablo = FotoSuzgeci.kisaKimlikler(["A/L0/001", "B/L0/001"])
        #expect(tablo == ["F1": "A/L0/001", "F2": "B/L0/001"])
        let c = FotoSuzgeci.kimlikCoz("F1, f2 F9 xyz F1", tablo: tablo)
        #expect(c.tam == ["A/L0/001", "B/L0/001"])
        #expect(c.bilinmeyen == ["F9", "xyz"])
        // Tam kimlik tablo olmadan da geçer; en çok 8.
        let tam = (1...12).map { "K\($0)/L0/001" }.joined(separator: ",")
        #expect(FotoSuzgeci.kimlikCoz(tam, tablo: [:]).tam.count == FotoSuzgeci.enFazlaGoster)
        // Boş tabloda kısa kimlik bilinmeyendir.
        #expect(FotoSuzgeci.kimlikCoz("F1", tablo: [:]).tam.isEmpty)
        #expect(FotoSuzgeci.siraliKisalar(FotoSuzgeci.kisaKimlikler((1...11).map { "x/\($0)" })).prefix(3) == ["F1", "F2", "F3"])
    }

    @Test func sonucSatiriBicimi() {
        let o = FotoGaleri.Oge(kimlik: "A/1", tarih: nil, medya: .video, alt: [], sure: 75, favori: true, konumlu: true, mesafeKm: 1.25)
        let s = FotoSuzgeci.satir(kisa: "F2", oge: o)
        #expect(s.hasPrefix("F2 · tarihsiz · video 1:15 · favori"))
        #expect(s.contains("km"))
        let e = FotoGaleri.Oge(kimlik: "B/1", tarih: nil, medya: .image, alt: .photoScreenshot, sure: 0, favori: false, konumlu: false, mesafeKm: nil)
        #expect(FotoSuzgeci.satir(kisa: "F1", oge: e) == "F1 · tarihsiz · ekran görüntüsü")
    }
}
