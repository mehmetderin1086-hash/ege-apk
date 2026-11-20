import Foundation
import Testing
@testable import Asistan

#if DEBUG
/// P3.3: değerlendirme setini gerçek `Beyin.gonder` ile koşar (gerçek model, ücretli). Yalnız ASISTAN_CANLI=1 ve Debug derlemede.
/// Kuru çalışma kipinde (`AjanDefteri.kuruCalisma`) yan etkili araçlar `IzlenenArac` içinde çalıştırılmaz, başarılı sayılır.
/// Araç sarmalayıcısından geçmeyen kısa yollar (müzik, iett, kitapyurdu, yan etkili yerel komut, sunucu kod görevi) gerçekten iş yapacağı için
/// burada çalıştırılmaz; onlar `DegerlendirmeTestleri` içinde yalnız `YolTahmini` ile ağsız denetlenir.
@Suite("Değerlendirme seti canlı", .serialized, .enabled(if: ProcessInfo.processInfo.environment["ASISTAN_CANLI"] == "1"))
@MainActor
struct DegerlendirmeCanliTestleri {
    /// Gerçek gonder ile çalıştırılmayan yollar.
    static let atlananYollar: Set<String> = ["muzik", "iett", "kitapyurdu", "sunucu"]

    static func calistirilacakMi(_ o: DegerlendirmeOrnegi) -> Bool {
        if atlananYollar.contains(o.beklenenYol) { return false }
        // Fener/zamanlayıcı/alarm yerel komutu araçları doğrudan çağırır (kuru çalışmadan geçmez).
        if let k = YerelKomut.coz(o.istek), YerelKomut.yanEtkili(k) { return false }
        return true
    }

    private func beyin() -> Beyin {
        let ud = UserDefaults(suiteName: "degerlendirme.\(UUID().uuidString)")!
        let ayarlar = Ayarlar(defaults: ud)
        ayarlar.otomatikModel = true; ayarlar.caba = "auto"; ayarlar.webArama = true
        let k = OnayKapisi(); k.otomatikKarar = true
        return Beyin(ayarlar: ayarlar, depo: HafizaDeposu(baglam: HafizaTestleri.kap.mainContext), onay: k)
    }

    @Test(.timeLimit(.minutes(60)))
    func setGercekGonderIleBeklenenYoldanGider() async throws {
        AjanDefteri.kuruCalisma = true
        defer { AjanDefteri.kuruCalisma = false }
        let set = try DegerlendirmeTestleri.seti().filter(Self.calistirilacakMi)
        var ozet: [String] = []
        for o in set {
            let b = beyin()
            try #require(b.hazir, "Secrets.xcconfig dolu olmalı")
            let bas = Date()
            b.gonder(o.istek)
            // Örnek başına 90 sn sınır; aşılırsa durdurulur ve sonraki örneğe geçilir.
            while b.durum != .bosta, Date().timeIntervalSince(bas) < 90 { try await Task.sleep(for: .milliseconds(200)) }
            if b.durum != .bosta { b.iptal() }
            let sn = Date().timeIntervalSince(bas)
            let yanit = b.mesajlar.last(where: { $0.rol == .asistan })
            #expect(sn < 90, "süre aşımı: '\(o.istek)'")
            // Yarış [ARAMA] işaretiyle ya da "yaptım" iddiasıyla zincire devredebilir: yarış beklenen örnekte zincir de kabul.
            let yol = yanit?.iz?.yol ?? b.sonYonlendirme
            let kabul = yol == o.beklenenYol || (o.beklenenYol == "yaris" && yol == "zincir")
            #expect(kabul, "yol: '\(o.istek)' → \(yol), beklenen \(o.beklenenYol)")
            let adimlar = Set(AjanDefteri.ortak.gorevler.first?.adimlar.map(\.arac) ?? [])
            for a in o.beklenenAraclar {
                #expect(adimlar.contains(a), "araç: '\(o.istek)' → \(a) çalışmadı; adımlar: \(adimlar.sorted())")
            }
            ozet.append("\(String(format: "%5.1f", sn)) sn \(yol) [\(adimlar.sorted().joined(separator: ","))] \(o.istek.prefix(50))")
        }
        print("DEĞERLENDİRME CANLI (\(set.count) örnek):\n" + ozet.joined(separator: "\n"))
    }

    @Test func atlananlarKisaYollardir() throws {
        let set = try DegerlendirmeTestleri.seti()
        #expect(set.contains { !Self.calistirilacakMi($0) })
        #expect(!set.filter(Self.calistirilacakMi).contains { Self.atlananYollar.contains($0.beklenenYol) })
    }
}
#endif
