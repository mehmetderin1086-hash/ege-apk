import Foundation
import Testing
@testable import Asistan

/// P1.8: hava kartı sohbete bağlandı (`MesajEki.Tur.hava(HavaOzeti)`); ağa gidilmez, Open-Meteo yanıtı literaldir.
@Suite("P1.8 hava kartı") @MainActor
struct Gelistirme_P1_8_HavaKartiTestleri {
    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private let simdiVeGunluk = """
        "current": {"temperature_2m": 17.6, "apparent_temperature": 16.4, "relative_humidity_2m": 70, "weather_code": 2, "wind_speed_10m": 11.2},
        "daily": {"time": ["2026-10-20", "2026-10-21", "2026-10-22"], "temperature_2m_max": [21.4, 19.0, 18.2], "temperature_2m_min": [12.6, 11.0, 10.4],
                  "weather_code": [2, 61, 3], "precipitation_probability_max": [10, 80, null]}
        """

    private func saatlik(_ n: Int, eksik: Int = 0) -> String {
        let saatler = (0..<n).map { "\"2026-10-20T\(String(format: "%02d", $0 % 24)):00\"" }
        let m = max(0, n - eksik)
        let sicak = (0..<m).map { String(Double($0) + 10.4) }
        let yagis = (0..<m).map { $0 == 1 ? "null" : String($0 * 5) }
        let kod = (0..<m).map { _ in "61" }
        let ruzgar = (0..<m).map { String(Double($0) + 3.6) }
        return """
            "hourly": {"time": [\(saatler.joined(separator: ","))], "temperature_2m": [\(sicak.joined(separator: ","))],
                       "precipitation_probability": [\(yagis.joined(separator: ","))], "weather_code": [\(kod.joined(separator: ","))],
                       "wind_speed_10m": [\(ruzgar.joined(separator: ","))]}
            """
    }

    private func yanit(_ ek: String?) throws -> HavaAraci.Yanit {
        let govde = ek.map { simdiVeGunluk + ",\n" + $0 } ?? simdiVeGunluk
        return try JSONDecoder().decode(HavaAraci.Yanit.self, from: Data("{\(govde)}".utf8))
    }

    @Test func yanittanOzetEnFazla12Saat() throws {
        let o = HavaOzeti(try yanit(saatlik(14)), ad: "İstanbul", zaman: t0)
        #expect(o.ad == "İstanbul")
        #expect(o.sicaklikMetni == "18°", "17,6 → 18")
        #expect(Int(o.hissedilen.rounded()) == 16)
        #expect(o.kod == 2)
        #expect(o.yuksek == 21.4 && o.dusuk == 12.6)
        #expect(o.saatler.count == HavaOzeti.enFazlaSaat)
        #expect(o.saatler.count == 12)
        #expect(o.saatler.first?.saat == "00:00")
        #expect(o.saatler[2].deger("Sıcaklık") == "12°", "12,4 → 12")
        #expect(o.saatler[2].deger("Yağış") == "%10")
        #expect(o.saatler[1].deger("Yağış") == "—", "null olasılık")
        #expect(o.saatler[0].deger("Rüzgâr") == "4 km/sa", "3,6 → 4")
        #expect(o.zaman == t0)
    }

    @Test func saatlikYoksaBos() throws {
        let o = HavaOzeti(try yanit(nil), ad: "Ankara", zaman: t0)
        #expect(o.saatler.isEmpty)
        #expect(o.sicaklikMetni == "18°")
    }

    @Test func kisaDizilerCokmedenNilAlanla() throws {
        // 5 saat var ama değer dizileri 2 öğe: kalan saatlerin alanları nil.
        let o = HavaOzeti(try yanit(saatlik(5, eksik: 3)), ad: "İzmir", zaman: t0)
        #expect(o.saatler.count == 5)
        #expect(o.saatler[0].sicaklik == 10.4)
        #expect(o.saatler[4].sicaklik == nil && o.saatler[4].yagis == nil && o.saatler[4].kod == nil && o.saatler[4].ruzgar == nil)
        #expect(o.saatler[4].deger("Sıcaklık") == "—")
        #expect(o.saatler[4].saat == "04:00")
    }

    @Test func kaliciGidisDonus() throws {
        let o = HavaOzeti(try yanit(saatlik(3)), ad: "Bursa", zaman: t0)
        let veri = EkKalici.kodla([MesajEki(tur: .hava(o))])
        let geri = EkKalici.coz(veri)
        guard geri.count == 1, case .hava(let g) = geri[0].tur else { Issue.record("hava kartı çözülmedi"); return }
        #expect(g == o)
        let ham = String(decoding: try #require(veri), as: UTF8.self)
        #expect(ham.contains("\"t\":\"hava\""))
    }

    @Test func eskiKayitHavaAlaniOlmadanCozulur() {
        // P1.8 öncesi biçim: "hava" alanı hiç yok.
        let eski = Data(#"[{"t":"kaynak","adresler":["https://example.com"]},{"t":"dosya","ad":"a.pdf","yol":"I:a.pdf"}]"#.utf8)
        let ekler = EkKalici.coz(eski)
        #expect(ekler.count == 2)
        if case .kaynaklar(let k) = ekler.first?.tur { #expect(k == ["https://example.com"]) } else { Issue.record("kaynak kartı") }
        // Alanı eksik hava kaydı sessizce atlanır, öbürleri çözülür.
        let bozuk = Data(#"[{"t":"hava"},{"t":"kaynak","adresler":["https://example.com"]}]"#.utf8)
        #expect(EkKalici.coz(bozuk).count == 1)
    }

    @Test func ekDefterineHavaKartiEklenir() {
        let d = EkDefteri()
        let o = HavaOzeti(ad: "İstanbul", sicaklik: 18, hissedilen: 17, kod: 2, yuksek: nil, dusuk: nil, saatler: [], zaman: t0)
        d.ekle(MesajEki(tur: .hava(o)))
        d.ekle(MesajEki(tur: .hava(o)))
        let al = d.al()
        #expect(al.count == 2, "aynı turda iki şehir = iki kart")
        #expect(d.bekleyen.isEmpty)
    }
}
