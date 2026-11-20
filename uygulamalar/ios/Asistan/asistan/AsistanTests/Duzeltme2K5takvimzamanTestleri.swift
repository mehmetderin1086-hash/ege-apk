import Foundation
import Testing
@testable import Asistan

@Suite("K5-takvim-zaman düzeltmeleri") struct Duzeltme2K5takvimzamanTestleri {
    private func gun(_ s: String) -> Date { AracYardim.tarih(s)! }

    // MARK: 20 — aynı başlıklı hatırlatıcılarda en yakın vadeli kapanır

    @Test func ayniBaslikliKayittaEnYakinVadeSecilir() {
        let b = ["9B Biyoloji dersi", "9B Biyoloji dersi"]
        let d20 = gun("2026-10-20T08:30"), d27 = gun("2026-10-27T08:30")
        #expect(HatirlaticiAraci.hedefSec(b, tarihler: [d27, d20], parca: "9b biyoloji dersi") == .tek(1))
        #expect(HatirlaticiAraci.hedefSec(b, tarihler: [d20, d27], parca: "9B Biyoloji dersi") == .tek(0))
        // Tarihsiz olan sona kalır.
        #expect(HatirlaticiAraci.hedefSec(b, tarihler: [nil, d27], parca: "9b biyoloji dersi") == .tek(1))
        // Tarih bilinmiyorsa eski davranış: ilk kayıt.
        #expect(HatirlaticiAraci.hedefSec(b, parca: "9b biyoloji dersi") == .tek(0))
        // Alt dize belirsizliği korunur.
        #expect(HatirlaticiAraci.hedefSec(b, tarihler: [d20, d27], parca: "biyoloji") == .belirsiz([0, 1]))
    }

    // MARK: 22 — tek çağrıda birden çok 'tamamla'

    @Test func topluTamamlaAyniKaydiIkiKezSecmez() {
        let b = ["Süt al", "Fotokopi al", "Süt al", "Kimya sınavı"]
        let s = HatirlaticiAraci.topluHedefSec(b, tarihler: [gun("2026-10-22"), nil, gun("2026-10-21"), nil],
                                              parcalar: ["süt al", "fotokopi", "Süt al", "fizik"])
        #expect(s == [.tek(2), .tek(1), .tek(0), .yok])
        // Belirsiz parça kapatılmaz, öbürleri etkilenmez.
        #expect(HatirlaticiAraci.topluHedefSec(["9B Biyoloji", "10A Biyoloji", "Süt al"], parcalar: ["biyoloji", "süt"]) == [.belirsiz([0, 1]), .tek(2)])
    }

    // MARK: 21/80 — tek 'ekle'de çözülemeyen zaman

    @Test func tekEkleZamanCozumu() {
        #expect(HatirlaticiAraci.zamanCoz(nil) == .yok)
        #expect(HatirlaticiAraci.zamanCoz("  ") == .yok)
        #expect(HatirlaticiAraci.zamanCoz("yarın 08:30") == .anlasilmadi("yarın 08:30"))
        #expect(HatirlaticiAraci.zamanCoz(" 21.10.2026 08:30 ") == .anlasilmadi("21.10.2026 08:30"))
        #expect(HatirlaticiAraci.zamanCoz("2026-10-21T08:30") == .tamam(gun("2026-10-21T08:30")))
        // Saatsiz gün 09:00'a kurulur.
        #expect(HatirlaticiAraci.zamanCoz("2026-10-21") == .tamam(gun("2026-10-21T09:00")))
    }

    // MARK: 76/77 — iptal: hepsi sözleri ve tür sözcüğü

    @Test func iptalHepsiSozleriTaninir() {
        let cay = UUID(), uyanma = UUID()
        let ogeler: [(id: UUID, baslik: String)] = [(cay, "Çay"), (uyanma, "Uyanma")]
        for s in ["bütün", "tüm", "HEPSI", "HEPSİ", "Tümünü", "tamamını", "tüm alarmları", "bütün alarmlar", "all"] {
            #expect(ZamanlayiciAraci.iptalSecimi(ogeler, baslik: s) == .iptal([cay, uyanma]), Comment(rawValue: s))
        }
        #expect(ZamanlayiciAraci.iptalSecimi(ogeler, baslik: "toplantı") == .eslesmeYok)
        // "Tüm" ile başlayan ama tür sözcüğü olmayan ifade etiket aramasına düşer.
        #expect(ZamanlayiciAraci.iptalSecimi([(cay, "Tüm gün ders"), (uyanma, "Uyanma")], baslik: "tüm gün") == .iptal([cay]))
    }

    @Test func iptalTurSozcuguYedekSuzgec() {
        let cay = UUID(), sabah = UUID(), yumurta = UUID()
        let ogeler: [(id: UUID, baslik: String)] = [(cay, "Çay"), (sabah, "Sabah")]
        let z: Set<UUID> = [cay]
        #expect(ZamanlayiciAraci.iptalSecimi(ogeler, baslik: "zamanlayıcıyı", zamanlayicilar: z) == .iptal([cay]))
        #expect(ZamanlayiciAraci.iptalSecimi(ogeler, baslik: "Alarmı", zamanlayicilar: z) == .iptal([sabah]))
        #expect(ZamanlayiciAraci.iptalSecimi(ogeler, baslik: "sayacı", zamanlayicilar: z) == .iptal([cay]))
        // Tür bilgisi verilmezse eski davranış.
        #expect(ZamanlayiciAraci.iptalSecimi(ogeler, baslik: "zamanlayıcı") == .eslesmeYok)
        // Aynı türden iki aday: silinmez, sorulur.
        let iki: [(id: UUID, baslik: String)] = [(cay, "Çay"), (yumurta, "Yumurta"), (sabah, "Sabah")]
        #expect(ZamanlayiciAraci.iptalSecimi(iki, baslik: "zamanlayıcı", zamanlayicilar: [cay, yumurta]) == .belirsiz)
        // "tüm zamanlayıcıları" yalnız zamanlayıcıları kapatır, saatli alarma dokunmaz.
        #expect(ZamanlayiciAraci.iptalSecimi(iki, baslik: "tüm zamanlayıcıları", zamanlayicilar: [cay, yumurta]) == .iptal([cay, yumurta]))
        #expect(ZamanlayiciAraci.iptalSecimi(ogeler, baslik: "bütün alarmları", zamanlayicilar: [cay, sabah]) == .eslesmeYok)
        // Etiket eşleşmesi tür sözcüğünden önce gelir (varsayılan etiket "Zamanlayıcı").
        let etiketli: [(id: UUID, baslik: String)] = [(cay, "Zamanlayıcı"), (sabah, "Sabah")]
        #expect(ZamanlayiciAraci.iptalSecimi(etiketli, baslik: "zamanlayıcı", zamanlayicilar: []) == .iptal([cay]))
    }

    // MARK: 70/74/78 — etiket kayıtları kilitli güncellenir

    @Test func paralelKayitGuncellemesiKayipsiz() async {
        let anahtar = ZamanlayiciAraci.kayitAnahtari
        let eski = UserDefaults.standard.data(forKey: anahtar)
        defer { if let eski { UserDefaults.standard.set(eski, forKey: anahtar) } else { UserDefaults.standard.removeObject(forKey: anahtar) } }
        UserDefaults.standard.removeObject(forKey: anahtar)
        let idler = (0..<64).map { _ in UUID().uuidString }
        await withTaskGroup(of: Void.self) { grup in
            for id in idler {
                grup.addTask { ZamanlayiciAraci.kayitlariGuncelle { $0[id] = ZamanlayiciAraci.AlarmKaydi(baslik: id, hedef: .distantFuture) } }
            }
        }
        let k = ZamanlayiciAraci.kayitlar()
        #expect(k.count == idler.count)
        // Yalnız fark silinir: yarısını kaldırınca öbür yarı kalır.
        ZamanlayiciAraci.kayitlariGuncelle { (k: inout [String: ZamanlayiciAraci.AlarmKaydi]) -> Void in for s in idler.prefix(32) { k[s] = nil } }
        #expect(Set(ZamanlayiciAraci.kayitlar().keys) == Set(idler.dropFirst(32)))
    }

    // MARK: 79 — 'listele' saatsiz bitiş

    @Test func listeBitisiSaatsizGunuKapsar() {
        let bas = gun("2026-10-21")
        #expect(TakvimAraci.listeBitisi("2026-10-23", bas: bas) == gun("2026-10-24"))
        #expect(TakvimAraci.listeBitisi("2026-10-21", bas: bas) == gun("2026-10-22"))
        #expect(TakvimAraci.listeBitisi("2026-10-23T18:00", bas: bas) == gun("2026-10-23T18:00"))
        #expect(TakvimAraci.listeBitisi(nil, bas: bas) == bas.addingTimeInterval(86_400))
        // Başlangıçtan önce kalan bitiş boş aralık üretmez.
        #expect(TakvimAraci.listeBitisi("2026-10-20T10:00", bas: bas) == bas.addingTimeInterval(86_400))
    }

    // MARK: 72/81 — toplu eklemede uyarı metni

    @Test func topluUyariNotuTumGunuAyirt() {
        #expect(TakvimAraci.topluUyariNotu(dk: 15, eklenen: 3, tumGun: 0) == " Uyarı: 15 dk önce.")
        #expect(TakvimAraci.topluUyariNotu(dk: 15, eklenen: 2, tumGun: 2).contains("09:00'dan 15 dk önce"))
        let karisik = TakvimAraci.topluUyariNotu(dk: 10, eklenen: 5, tumGun: 2)
        #expect(karisik.contains("Uyarı: 10 dk önce") && karisik.contains("2 tanesi tüm gün"))
        #expect(TakvimAraci.topluUyariNotu(dk: -1, eklenen: 3, tumGun: 1) == " Uyarı kurulmadı.")
    }
}
