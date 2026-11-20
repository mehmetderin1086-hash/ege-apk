import Foundation
import Testing
@testable import Asistan

@Suite("Yaşam servisleri")
struct YasamServisleriTestleri {
    @Test func saglikHavasiMetniAqiVePolenIcerir() throws {
        let d = Data(#"{"current":{"time":"2026-10-20T22:00","european_aqi":52,"pm10":40.1,"pm2_5":35.2,"ozone":35,"uv_index":0,"alder_pollen":0,"birch_pollen":0,"grass_pollen":0.2,"mugwort_pollen":0.1,"olive_pollen":0,"ragweed_pollen":0}}"#.utf8)
        let y = try JSONDecoder().decode(YasamServisleriAraci.HavaSagligi.self, from: d)
        let m = YasamServisleriAraci.saglikMetni(y, ad: "İstanbul")
        #expect(m.contains("52 (orta)")); #expect(m.contains("çimen 0.2")); #expect(m.contains("PM2.5 35.2"))
    }

    @Test func urunYanitiBesinKodlariniCozuyor() throws {
        let d = Data(#"{"status":1,"product":{"product_name":"Örnek","brands":"Marka","nutriscore_grade":"b","allergens":"milk","nutriments":{"energy-kcal_100g":120,"fat_100g":3.2,"sugars_100g":4.5,"proteins_100g":6,"salt_100g":0.2}}}"#.utf8)
        let y = try JSONDecoder().decode(YasamServisleriAraci.UrunYaniti.self, from: d)
        #expect(y.product?.nutriments?.energyKcal == 120); #expect(y.product?.nutriscore_grade == "b")
    }

    @MainActor @Test func aracKayitliVePolitikasiDogru() {
        #expect(AracKaydi.adlar.contains("yasamServisleri")); #expect(KanitTamponu.veriAraclari.contains("yasamServisleri"))
        #expect(!GorevGunlugu.yanEtkiliMi("yasamServisleri", islem: "deprem")); #expect(!GorevGunlugu.yanEtkiliMi("yasamServisleri", islem: "sabahOzeti"))
        #expect(!CanliHizliIstemci.uygun("İstanbul hava kalitesi ve polen")); #expect(!CanliHizliIstemci.uygun("Bu barkodu araştır"))
    }
}

@Suite("Yaşam servisleri canlı", .serialized, .enabled(if: ProcessInfo.processInfo.environment["ASISTAN_CANLI"] == "1"))
struct YasamServisleriCanliTestleri {
    @Test func altiAcikHizmetCalisir() async throws {
        let a = YasamServisleriAraci()
        func girdi(_ islem: String, sorgu: String? = nil, yer: String? = nil, barkod: String? = nil) -> YasamServisleriAraci.Arguments {
            .init(islem: islem, sorgu: sorgu, yer: yer, barkod: barkod, enlem: nil, boylam: nil, yaricapKm: nil)
        }
        #expect(try await a.call(arguments: girdi("saglikHavasi", yer: "İstanbul")).contains("Open-Meteo"))
        #expect(try await a.call(arguments: girdi("deprem", yer: "İstanbul")).contains("USGS"))
        #expect(try await a.call(arguments: girdi("urun", barkod: "3017620422003")).contains("Nutri-Score"))
        #expect(try await a.call(arguments: girdi("bilgi", sorgu: "Hücre")).contains("Kaynak:"))
        #expect(try await a.call(arguments: girdi("doga", sorgu: "Pinus nigra")).contains("GBIF"))
        #expect(try await a.call(arguments: girdi("makale", sorgu: "CRISPR")).contains("OpenAlex"))
    }
}
