import Foundation
import Testing
@testable import Asistan

/// O3: yerel Whisper güvenli yükleme — `.indirildi` durumu, çökme işareti, sesli kip açılışında hazırlama kararı.
/// Ağ, izin ya da gerçek model gerektirmez; diskte olmayan uydurma model adları kullanılır.
@MainActor
@Suite("O3 yerel Whisper yükleme")
struct YerelWhisperYuklemeTestleri {

    private func ayriDefaults() -> (UserDefaults, String) {
        let ad = "o3-whisper-\(UUID().uuidString)"
        return (UserDefaults(suiteName: ad)!, ad)
    }

    // MARK: (1) sesliAcilistaYuklenir karar tablosu

    @Test func yerelSeciliDegilseYuklenmez() {
        #expect(!YerelWhisper.sesliAcilistaYuklenir(kullan: false, durum: .indirildi, indirilmis: true, cokmus: false))
    }

    @Test func indirilmemisModelKendiligindenIndirilmez() {
        #expect(!YerelWhisper.sesliAcilistaYuklenir(kullan: true, durum: .indirilmedi, indirilmis: false, cokmus: false))
    }

    @Test func cokmeIsaretiVarsaYuklenmez() {
        #expect(!YerelWhisper.sesliAcilistaYuklenir(kullan: true, durum: .indirildi, indirilmis: true, cokmus: true))
    }

    @Test func surenVeyaHazirDurumdaYenidenYuklenmez() {
        let durumlar: [YerelWhisper.Durum] = [.yukleniyor, .hazir, .indiriliyor(0.4), .hata("x")]
        for d in durumlar {
            #expect(!YerelWhisper.sesliAcilistaYuklenir(kullan: true, durum: d, indirilmis: true, cokmus: false), "\(d)")
        }
    }

    @Test func indirilmisVeCokmesizModelYuklenir() {
        #expect(YerelWhisper.sesliAcilistaYuklenir(kullan: true, durum: .indirildi, indirilmis: true, cokmus: false))
        // Açılış durumu henüz tazelenmemişse (.indirilmedi) ama model diskteyse de yüklenir.
        #expect(YerelWhisper.sesliAcilistaYuklenir(kullan: true, durum: .indirilmedi, indirilmis: true, cokmus: false))
    }

    // MARK: (2) çökme anahtarı

    @Test func cokmeAnahtariBicimi() {
        #expect(YerelWhisper.cokmeAnahtari("openai_whisper-small") == "whisper.yukleniyor.openai_whisper-small")
    }

    // MARK: (3) oncekiYuklemeCokmus

    @Test func oncekiYuklemeCokmusIsaretiOkur() {
        let (d, ad) = ayriDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: ad) }
        let model = "o3-yok-model"
        #expect(!YerelWhisper.oncekiYuklemeCokmus(model, defaults: d))
        d.set(true, forKey: YerelWhisper.cokmeAnahtari(model))
        #expect(YerelWhisper.oncekiYuklemeCokmus(model, defaults: d))
        #expect(!YerelWhisper.oncekiYuklemeCokmus("o3-baska-model", defaults: d))
        d.removeObject(forKey: YerelWhisper.cokmeAnahtari(model))
        #expect(!YerelWhisper.oncekiYuklemeCokmus(model, defaults: d))
    }

    @Test func cokmeIsaretiZamanDamgasiTasirVeNormalKapanistaSilinir() {
        let (d, ad) = ayriDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: ad) }
        YerelWhisper.cokmeIsaretiYaz("o3-a", defaults: d)
        YerelWhisper.cokmeIsaretiYaz("o3-b", defaults: d)
        d.set("baska", forKey: "baska.anahtar")
        let damga = d.double(forKey: YerelWhisper.cokmeAnahtari("o3-a"))
        #expect(abs(damga - Date().timeIntervalSince1970) < 5, "değer yükleme başlangıcının zaman damgası")
        #expect(YerelWhisper.oncekiYuklemeCokmus("o3-a", defaults: d) && YerelWhisper.oncekiYuklemeCokmus("o3-b", defaults: d))
        YerelWhisper.cokmeIsaretleriniTemizle(defaults: d)
        #expect(!YerelWhisper.oncekiYuklemeCokmus("o3-a", defaults: d) && !YerelWhisper.oncekiYuklemeCokmus("o3-b", defaults: d))
        #expect(d.string(forKey: "baska.anahtar") == "baska", "yalnız çökme işaretleri silinir")
    }

    // MARK: (4) durumuTazele

    @Test func isaretliModelHataGosterirIsaretSilinceGeriDoner() {
        let (d, ad) = ayriDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: ad) }
        let model = "o3-yok-model-\(UUID().uuidString)"
        let w = YerelWhisper()
        d.set(true, forKey: YerelWhisper.cokmeAnahtari(model))
        w.durumuTazele(model: model, defaults: d)
        #expect(w.durum == .hata(YerelWhisper.cokmeHataMetni))
        d.removeObject(forKey: YerelWhisper.cokmeAnahtari(model))
        w.durumuTazele(model: model, defaults: d)
        // Model diskte yok: hata durumundan .indirilmedi'ye döner (hata kalıcı kilit değil).
        #expect(w.durum == .indirilmedi)
    }

    @Test func isaretsizIndirilmemisModelIndirilmediGorunur() {
        let (d, ad) = ayriDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: ad) }
        let w = YerelWhisper()
        w.durumuTazele(model: "o3-yok-model-\(UUID().uuidString)", defaults: d)
        #expect(w.durum == .indirilmedi)
    }

    /// Otomatik hazırlama çökme işaretine saygı duyar: indirme/yükleme başlamaz, durum hata olur.
    @Test func otomatikHazirlamaCokmeIsaretindeBaslamaz() {
        let model = "o3-yok-model-\(UUID().uuidString)"
        let anahtar = YerelWhisper.cokmeAnahtari(model)
        UserDefaults.standard.set(true, forKey: anahtar)
        defer { UserDefaults.standard.removeObject(forKey: anahtar) }
        let w = YerelWhisper()
        w.hazirla(model: model)
        #expect(w.durum == .hata(YerelWhisper.cokmeHataMetni))
        #expect(!w.hazir)
        #expect(w.yukluModel == nil)
        // İşaret yerinde kalır; yalnız elle deneme siler.
        #expect(YerelWhisper.oncekiYuklemeCokmus(model))
    }

    @Test func bosaltIndirilmemisModeldeIndirilmediBirakir() {
        let w = YerelWhisper()
        w.bosalt()
        #expect(w.durum == .indirilmedi)
        #expect(!w.hazir)
    }
}
