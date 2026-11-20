import Foundation
import Testing
@testable import Asistan

/// P1.1: belge/plan işleri (plan, yazılı, tutanak, dilekçe, e-Okul…) araçsız hızlı yarışa girmez.
/// Testler `kayitliAraclar` ve `beceriKokleri`ni açıkça verir; küresel duruma (BeceriDeposu.kok) bağlı değildir.
@Suite("Belge ve plan işleri araçlı yola gider") struct OgretmenYonlendirmeTestleri {
    private func uygun(_ s: String, araclar: Set<String> = [], kokler: [[String]] = []) -> Bool {
        CanliHizliIstemci.uygun(s, kayitliAraclar: araclar, beceriKokleri: kokler)
    }

    @Test(arguments: ["ders planı hazırla", "yazılı sorularını hazırla", "veliye mesaj taslağı", "zümre tutanağı yaz",
                      "e-Okul notlarını gir", "rubrik oluştur", "Derslerimi planla", "dilekçe yaz",
                      "eokul şifremi unuttum", "E okul girişini anlat"])
    func ogretmenlikIsiYarisaGirmez(_ s: String) {
        #expect(!uygun(s), "\(s) araçlı yola gitmeli")
    }

    @Test(arguments: ["Mitoz ile mayoz farkı ne", "yazılım nedir", "Yazılımcı olmak zor mu", "Bir gün kaç saniyedir",
                      "Fotosentezi iki cümleyle açıkla", "Türkçe okulda nasıl öğretilir", "Python nedir"])
    func siradanSoruYaristaKalir(_ s: String) {
        #expect(uygun(s), "\(s) yarışa girebilmeli")
    }

    @Test func aracKokleriYalnizKayitliyken() {
        #expect(uygun("Bunu İngilizceye çevir"), "çeviri aracı kayıtlı değilken yarışta kalır")
        #expect(!uygun("Bunu İngilizceye çevir", araclar: ["ceviri"]))
        #expect(!uygun("Şu metni tercüme et", araclar: ["ceviri"]))
        #expect(uygun("Bana bir hücre çizer misin"))
        #expect(!uygun("Bana bir hücre çizer misin", araclar: ["cizim"]))
        // Başka aracın kaydı çeviri köklerini etkinleştirmez.
        #expect(uygun("Bunu İngilizceye çevir", araclar: ["cizim", "fotograf"]))
        // P2.12: PDF işleri araçlı yola gider; "dondurma" yarışta kalır ("dondur" kök değil).
        #expect(uygun("Bu iki PDF'yi birleştir"), "PDF aracı kayıtlı değilken yarışta kalır")
        #expect(!uygun("Bu iki PDF'yi birleştir", araclar: ["pdfIslem"]))
        #expect(!uygun("Bu formu imzala", araclar: ["pdfIslem"]))
        #expect(!uygun("Bunu biraz küçült", araclar: ["pdfIslem"]))
        #expect(!uygun("PDF'i sıkıştır", araclar: ["pdfIslem"]))
        #expect(uygun("Dondurma nasıl yapılır", araclar: ["pdfIslem"]))
        // P4.4: galeri işleri araçlı yola gider; soru fotoğrafı yarışta kalır.
        #expect(!uygun("galerimdeki geçen haftaki fotoğrafları bul", araclar: ["fotograflar"]))
        #expect(uygun("Bu fotoğraftaki soruyu çöz", araclar: ["fotograflar"]))
    }

    /// Derleme zamanı listesi `AracKaydi.adlar` ile eş kalmalı: yeni araç kaydedilip `varsayilanAraclar`a yazılmazsa kırılır.
    @MainActor @Test func varsayilanAraclarKayitlaEs() {
        let beklenen = Set(CanliHizliIstemci.aracTetikleri.keys).intersection(AracKaydi.adlar)
        #expect(CanliHizliIstemci.varsayilanAraclar == beklenen)
    }

    @Test func eOkulSozcukSinirli() {
        #expect(!uygun("e-okul"))
        #expect(uygun("Türkçe okulda nasıl öğretilir"))
        #expect(uygun("Bu sene okul ne zaman açılıyor"))
    }

    @Test func tetikKokKurali() {
        let b: [Beceri] = [
            Beceri(ad: "ders-programi", aciklama: "", icerik: ""),
            Beceri(ad: "ikra-ile-calis", aciklama: "", icerik: ""),
            Beceri(ad: "sinav-programi", aciklama: "", icerik: ""),
            Beceri(ad: "yoklama", aciklama: "", icerik: ""),
            Beceri(ad: "ve-ile", aciklama: "", icerik: ""),       // kökü kalmaz: listeye girmez
            Beceri(ad: "ders-programi", aciklama: "", icerik: ""), // yinelenen ad tekilleşir
            Beceri(ad: "Mitoz_Karti", aciklama: "", icerik: ""),   // içe aktarılmış ad normalleşir
        ]
        #expect(BeceriDeposu.tetikKokleri(b) == [["ders", "program"], ["ikra", "cali"], ["sina", "program"], ["yoklam"], ["mito", "kart"]])
    }

    @Test func beceriAdiIstekteGecerseYarisaGirmez() {
        let kokler = BeceriDeposu.tetikKokleri([Beceri(ad: "mitoz-karti", aciklama: "Mitoz kartı", icerik: "1. Kart")])
        #expect(!uygun("mitoz kartı hazırla", kokler: kokler))
        #expect(uygun("mitoz kartı hazırla"), "beceri yokken yarışta kalır")
        // Bütün kökler gerekir: yalnız "mitoz" geçen soru yarışta kalır.
        #expect(uygun("Mitoz ile mayoz farkı ne", kokler: kokler))
        // Boş kök listesi her isteği engellememeli.
        #expect(uygun("Merhaba nasılsın", kokler: [[]]))
    }

    @Test func kaldirilanHazirBecerilerKokUretmez() {
        let kokler = BeceriDeposu.tetikKokleri(BeceriDeposu.hazirBeceriler)
        #expect(kokler.isEmpty)
        #expect(uygun("ders programımı göster", kokler: kokler))
        #expect(uygun("İkra ile çalışalım", kokler: kokler))
    }
}

/// Kök dizinine yazan test: önbelleğin `kaydet`/`sil` ile sıfırlandığını ve `kok` değişince yenilendiğini denetler.
@Suite("Beceri tetik önbelleği", .serialized) struct OgretmenYonlendirmeDiskTestleri {
    @Test func kaydetSilOnbellegiYeniler() throws {
        let eski = BeceriDeposu.kok
        let k = FileManager.default.temporaryDirectory.appendingPathComponent("beceri-tetik-\(UUID().uuidString)")
        BeceriDeposu.kok = k
        defer { BeceriDeposu.kok = eski; try? FileManager.default.removeItem(at: k) }
        #expect(!BeceriDeposu.tetikKokleri().contains(["mito", "kart"]))
        try BeceriDeposu.kaydet(ad: "mitoz-karti", aciklama: "Mitoz kartı hazırlar", icerik: "1. Evreleri yaz")
        #expect(BeceriDeposu.tetikKokleri().contains(["mito", "kart"]))
        #expect(!CanliHizliIstemci.uygun("mitoz kartı hazırla", kayitliAraclar: []))
        #expect(BeceriDeposu.sil("mitoz-karti"))
        #expect(!BeceriDeposu.tetikKokleri().contains(["mito", "kart"]))
        // Kaldırılan hazır beceriler (ders-plani…) kök üretmez.
        #expect(!BeceriDeposu.tetikKokleri().contains(["ders", "plan"]))
    }
}
