import Foundation
import Testing
@testable import Asistan

/// P3.11: widget anlığının saf mantığı (sıradaki ders, bugün, zaman noktaları, kısaltma, JSON, hızlı sor bağlantısı).
/// Ağ, izin ve gerçek model gerektirmez; widget görünümleri simülatör galerisinde, EKEventStoreChanged ile yenileme telefonda elle denenir.
@Suite("P3.11-Widget ders günü") @MainActor
struct Gelistirme_P3_11_DersGunuTestleri {
    private typealias O = WidgetAnlik.Olay

    private static let takvim: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        c.locale = Locale(identifier: "tr_TR")
        return c
    }()

    private func an(_ gun: Int, _ saat: Int, _ dakika: Int = 0) -> Date {
        Self.takvim.date(from: DateComponents(year: 2026, month: 10, day: gun, hour: saat, minute: dakika))!
    }

    private func olay(_ b: String, _ bas: Date, _ bit: Date, yer: String? = nil) -> O {
        O(baslik: b, baslangic: bas, bitis: bit, yer: yer)
    }

    // MARK: (a) siradaki

    @Test func surenDersSiradakindenOnceGelir() throws {
        let simdi = an(20, 10, 20)
        let o = [olay("Sonraki", an(20, 11), an(20, 11, 40)), olay("Süren", an(20, 10), an(20, 10, 50))]
        let s = try #require(DersGunu.siradaki(o, simdi: simdi))
        #expect(s.olay.baslik == "Süren")
        #expect(s.suruyor)
    }

    @Test func gecmisOlayAtlanir() throws {
        let simdi = an(20, 12)
        let o = [olay("Geçmiş", an(20, 10), an(20, 10, 40)), olay("Gelecek", an(20, 13), an(20, 13, 40))]
        let s = try #require(DersGunu.siradaki(o, simdi: simdi))
        #expect(s.olay.baslik == "Gelecek")
        #expect(!s.suruyor)
        // Bitiş anı geçmiş sayılır (bitis > simdi değil).
        #expect(DersGunu.siradaki([olay("Bitti", an(20, 11), an(20, 12))], simdi: simdi) == nil)
    }

    @Test func geceYarisiniGecenEtkinlik() throws {
        let o = [olay("Gece nöbeti", an(20, 23, 30), an(21, 0, 30))]
        let s = try #require(DersGunu.siradaki(o, simdi: an(21, 0, 10)))
        #expect(s.suruyor)
        let once = try #require(DersGunu.siradaki(o, simdi: an(20, 22)))
        #expect(!once.suruyor)
        // Bugün listesinde de iki günde görünür (kesişme), bittikten sonra görünmez.
        #expect(DersGunu.bugun(o, simdi: an(21, 0, 10), takvim: Self.takvim).count == 1)
        #expect(DersGunu.bugun(o, simdi: an(21, 1), takvim: Self.takvim).isEmpty)
    }

    @Test func bosListeNil() {
        #expect(DersGunu.siradaki([], simdi: an(20, 9)) == nil)
        #expect(DersGunu.siradakiMetni([], simdi: an(20, 9)) == nil)
    }

    // MARK: (b) bugun

    @Test func bugunYalnizBugunuDoner() {
        let simdi = an(20, 10, 20)
        let o = [
            olay("Dün", an(19, 10), an(19, 11)),
            olay("Bitmiş bugün", an(20, 8), an(20, 8, 40)),
            olay("Süren", an(20, 10), an(20, 10, 50)),
            olay("Akşam", an(20, 19), an(20, 20)),
            olay("Yarın", an(21, 8, 30), an(21, 9, 10)),
        ]
        let b = DersGunu.bugun(o.reversed(), simdi: simdi, takvim: Self.takvim)
        #expect(b.map(\.baslik) == ["Süren", "Akşam"])
    }

    // MARK: (c) zamanNoktalari

    @Test func zamanNoktalariSiraliBenzersizSinirli() {
        let simdi = an(20, 10, 20)
        var o = [olay("A", an(20, 10), an(20, 10, 50)), olay("B", an(20, 10, 50), an(20, 11, 30)),
                 olay("Çok ileri", an(22, 9), an(22, 10))]
        let n = DersGunu.zamanNoktalari(o, simdi: simdi, takvim: Self.takvim)
        #expect(n.first == simdi)
        #expect(n == n.sorted())
        #expect(Set(n).count == n.count)
        #expect(n.allSatisfy { $0 >= simdi && $0 <= simdi.addingTimeInterval(36 * 3_600) })
        #expect(n.contains(an(20, 10, 50)) && n.contains(an(20, 11, 30)))
        #expect(n.contains(an(21, 0)))            // gece yarısı: bugün listesi yenilenir
        #expect(!n.contains(an(20, 10)))          // geçmiş başlangıç alınmaz
        #expect(!n.contains(an(22, 9)))           // 36 saatin dışı
        // Çok olayda en çok 30 nokta.
        o = (0..<40).map { i in olay("D\(i)", simdi.addingTimeInterval(Double(i + 1) * 600), simdi.addingTimeInterval(Double(i + 1) * 600 + 300)) }
        let cok = DersGunu.zamanNoktalari(o, simdi: simdi, takvim: Self.takvim)
        #expect(cok.count == 30)
        #expect(cok == cok.sorted())
        #expect(DersGunu.zamanNoktalari([], simdi: simdi, enFazla: 0, takvim: Self.takvim) == [simdi])
    }

    // MARK: (d) kisalt

    @Test func kisaltMarkdownTemizlerVeSinira() {
        let md = "## Başlık\n\n**Kalın** ve `kod` ile [bağlantı](https://ornek.com) var.\n- madde bir\n- madde iki"
        let k = DersGunu.kisalt(md)
        #expect(k == "Başlık Kalın ve kod ile bağlantı var. madde bir madde iki")
        let uzun = String(repeating: "mitokondri hücrenin enerji santralidir ", count: 20)
        let u = DersGunu.kisalt(uzun)
        #expect(u.count <= 160)
        #expect(u.hasSuffix("…"))
        #expect(!u.contains("  "))
        #expect(DersGunu.kisalt(String(repeating: "a", count: 300)).count == 160)   // tek dev kelime sert kesilir
        #expect(DersGunu.kisalt("  \n ") == "")
    }

    // MARK: (e) JSON gidiş-dönüş

    @Test func anlikJsonGidisDonus() throws {
        let a = WidgetAnlik(olaylar: [olay("Biyoloji 10-A", an(20, 10), an(20, 10, 40), yer: "B-12"), olay("Toplantı", an(20, 15), an(20, 16))],
                            takvimIzni: true, sonYanit: "Kısa yanıt", sonSohbetID: UUID().uuidString,
                            sonYanitZamani: Date(timeIntervalSinceReferenceDate: 812_345_678.25), guncelleme: an(20, 7, 45))
        let veri = try JSONEncoder().encode(a)
        #expect(try JSONDecoder().decode(WidgetAnlik.self, from: veri) == a)
        // Dosya yolu (App Group yerine geçici dizin) ile yaz/oku.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("p311-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Widget/anlik.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent().deletingLastPathComponent()) }
        try DersGunu.yaz(a, url)
        #expect(DersGunu.oku(url) == a)
        #expect(DersGunu.oku(url.deletingLastPathComponent().appendingPathComponent("yok.json")) == nil)
    }

    // MARK: (f) hizliIstem

    @Test func hizliIstemSiniri() {
        #expect(DersGunu.hizliIstem(0) == nil)
        #expect(DersGunu.hizliIstem(9) == nil)
        for no in 1...4 { #expect(!(DersGunu.hizliIstem(no) ?? "").isEmpty) }
        #expect(DersGunu.hizliIstemler.map(\.no) == [1, 2, 3, 4])
        #expect(DersGunu.hizliAdres(2)?.absoluteString == "asistan://hizli?no=2")
    }

    // MARK: (g) AsistanBaglantisi

    @Test func hizliBaglantisiCozulur() {
        #expect(AsistanBaglantisi.coz(URL(string: "asistan://hizli?no=2")!) == .hizli(2))
        #expect(AsistanBaglantisi.coz(URL(string: "asistan://hizli?no=9")!) == nil)
        #expect(AsistanBaglantisi.coz(URL(string: "asistan://hizli?no=abc")!) == nil)
        #expect(AsistanBaglantisi.coz(URL(string: "asistan://hizli")!) == nil)
        // Widget'ın ürettiği bağlantı aynı sözleşmeyle çözülür.
        for i in DersGunu.hizliIstemler { #expect(AsistanBaglantisi.coz(DersGunu.hizliAdres(i.no)!) == .hizli(i.no)) }
    }

    // MARK: Kilit ekranı metinleri

    @Test func siradakiMetniVeYonelmeEki() {
        let o = [olay("Biyoloji 10-A", an(20, 10), an(20, 10, 50)), olay("Biyoloji 11-C", an(20, 11), an(20, 11, 40))]
        #expect(DersGunu.siradakiMetni(o, simdi: an(20, 10, 20), takvim: Self.takvim) == "Şimdi: Biyoloji 10-A · 10:50'ye kadar")
        #expect(DersGunu.siradakiMetni(o, simdi: an(20, 10, 55), takvim: Self.takvim) == "Sıradaki: Biyoloji 11-C · 11:00")
        let yarin = [olay("Kimya", an(21, 8, 30), an(21, 9, 10))]
        #expect(DersGunu.siradakiMetni(yarin, simdi: an(20, 18), takvim: Self.takvim) == "Sıradaki: Kimya · yarın 08:30")
        #expect(DersGunu.yonelmeEki(saat: 11, dakika: 0) == "e")    // on bire
        #expect(DersGunu.yonelmeEki(saat: 10, dakika: 0) == "a")    // ona
        #expect(DersGunu.yonelmeEki(saat: 10, dakika: 30) == "a")   // otuza
        #expect(DersGunu.yonelmeEki(saat: 9, dakika: 40) == "a")    // kırka
        #expect(DersGunu.yonelmeEki(saat: 12, dakika: 0) == "ye")   // on ikiye
        #expect(DersGunu.yonelmeEki(saat: 13, dakika: 26) == "ya")  // yirmi altıya
        #expect(DersGunu.yonelmeEki(saat: 14, dakika: 9) == "a")    // dokuza
        #expect(DersGunu.yonelmeEki(saat: 0, dakika: 0) == "a")     // sıfıra
        #expect(DersGunu.yonelmeEki(saat: 20, dakika: 0) == "ye")   // yirmiye
        #expect(DersGunu.saat(an(20, 9, 5), takvim: Self.takvim) == "09:05")
    }
}
