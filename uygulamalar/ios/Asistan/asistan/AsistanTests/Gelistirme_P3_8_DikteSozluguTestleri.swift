import Testing
import Foundation
@testable import Asistan

/// P3.8 (H): dikte düzeltme defteri (fark, öğrenme, uygulama, ipucu, kalıcılık) ve dikte dil modelinin saf yardımcıları.
/// Her test kendi geçici dosyasını kullanır; `ortak` deftere ve ağa dokunulmaz.
@Suite("P3.8 dikte sözlüğü") @MainActor
struct Gelistirme_P3_8_DikteSozluguTestleri {
    let temizlik = TestTemizligi()
    private func defter() -> (DikteDuzeltmeDefteri, URL) {
        let u = temizlik.gecici(FileManager.default.temporaryDirectory.appending(path: "p38-dikte-\(UUID().uuidString).json"))
        return (DikteDuzeltmeDefteri(dosya: u), u)
    }
    private func ciftler(_ ham: String, _ duz: String) -> [String] {
        DikteDuzeltmeDefteri.fark(ham: ham, duzeltilmis: duz).map { "\($0.0)>\($0.1)" }
    }

    @Test func farkYalnizKucukDegisimleriAlir() {
        #expect(ciftler("mitos bölünmesi", "mitoz bölünmesi") == ["mitos>mitoz"])
        #expect(ciftler("Hücrede ribosom ve lizosom var", "Hücrede ribozom ve lizozom var") == ["ribosom>ribozom", "lizosom>lizozom"])
        #expect(ciftler("bunu bana hemen yap", "şu dosyayı yarın gönder lütfen").isEmpty, "cümlenin yeniden yazılması alınmaz")
        #expect(ciftler("on beş cüz indir", "15 cüz indir").isEmpty, "sayı içeren değişim alınmaz")
        #expect(ciftler("Vav radyo çöz indir", "Vav radyo cüz indir").isEmpty, "kısa sözcükte büyük değişim (oran > 0,6) alınmaz")
        #expect(ciftler("kalem ver", "masa ver").isEmpty, "bambaşka sözcük alınmaz")
        #expect(ciftler("aynı metin", "Aynı metin.").isEmpty, "harf büyüklüğü/noktalama düzeltme sayılmaz")
        #expect(ciftler("mitoz ile mayoz farkı", "mitoz ve mayoz farkı").isEmpty, "durak sözcüğü alınmaz")
    }

    @Test func uygulaSayacVeSozcukSiniri() {
        let (d, _) = defter()
        d.ogren(ham: "mitos bölünmesi", duzeltilmis: "mitoz bölünmesi", kaynak: .suzgec)
        #expect(d.uygula("mitos evresi") == "mitos evresi", "tek kez görülen süzgeç düzeltmesi uygulanmaz")
        d.ogren(ham: "mitos nedir", duzeltilmis: "mitoz nedir", kaynak: .suzgec)
        #expect(d.liste().first?.sayac == 2)
        #expect(d.uygula("mitos evresi") == "mitoz evresi")
        #expect(d.uygula("Mitos nedir") == "Mitoz nedir", "harf büyüklüğü korunur")
        #expect(d.uygula("mitoskondri ve mitos") == "mitoskondri ve mitoz", "sözcük içi eşleşme yapılmaz")
        #expect(d.ekle(yanlis: "ribosom", dogru: "ribozom"))
        #expect(d.uygula("ribosom nerede") == "ribozom nerede", "kullanıcı kaydı hemen uygulanır")
        #expect(!d.ekle(yanlis: "kalem", dogru: "Kalem") && !d.ekle(yanlis: " ", dogru: "x"))
    }

    @Test func kullaniciKaydiniSuzgecDegistiremez() {
        let (d, _) = defter()
        #expect(d.ekle(yanlis: "Mendel", dogru: "Mendel'in"))
        d.ogren(ham: "Mendel yasaları", duzeltilmis: "Mandel yasaları", kaynak: .suzgec)
        #expect(d.liste().first { $0.yanlis == "Mendel" }?.dogru == "Mendel'in")
    }

    @Test func ipucuSiniriVeKalicilik() {
        let (d, u) = defter()
        for i in 0..<40 { _ = d.ekle(yanlis: "yanlisterim\(i)", dogru: "dogruterim\(i)") }
        let ipucu = d.ipucu(enFazla: 30)
        #expect(ipucu.components(separatedBy: ", ").count == 30)
        let yeniden = DikteDuzeltmeDefteri(dosya: u)
        func ozet(_ l: [DikteDuzeltmeDefteri.Kayit]) -> Set<String> { Set(l.map { "\($0.yanlis)>\($0.dogru)>\($0.sayac)>\($0.kaynak.rawValue)" }) }
        #expect(yeniden.liste().count == 40 && ozet(yeniden.liste()) == ozet(d.liste()), "diske yazılıp aynen okunur")
        yeniden.sil("yanlisterim0")
        #expect(DikteDuzeltmeDefteri(dosya: u).liste().count == 39)
    }

    @Test func enFazla300Kayit() {
        let (d, _) = defter()
        for i in 0..<305 { _ = d.ekle(yanlis: "y\(i)abc", dogru: "d\(i)abc") }
        #expect(d.liste().count == DikteDuzeltmeDefteri.enFazlaKayit)
    }

    @Test func yalnizSesliIstekteOgrenir() {
        #expect(DikteDuzeltmeDefteri.sesliIstekMi(ham: "Mitos bölünmesi nedir", sonDikte: "mitos bölünmesi nedir"))
        #expect(!DikteDuzeltmeDefteri.sesliIstekMi(ham: "mitos bölünmesi nedir", sonDikte: nil), "yazılı istek")
        #expect(!DikteDuzeltmeDefteri.sesliIstekMi(ham: "mitos bölünmesi nedir", sonDikte: "hava nasıl"))
        let (d, _) = defter()
        d.suzgectenOgren(ham: "mitos bölünmesi", duzeltilmis: "mitoz bölünmesi")
        #expect(d.liste().isEmpty, "son dikte yoksa öğrenilmez")
        d.sonDikte = "mitos bölünmesi"
        d.suzgectenOgren(ham: "mitos bölünmesi", duzeltilmis: "mitoz bölünmesi")
        #expect(d.liste().count == 1 && d.sonDikte == nil)
    }

    @Test func whisperIstemiVeYanki() {
        let uzun = (0..<200).map { "terim\($0)" }.joined(separator: ", ")
        let istem = WhisperIstemcisi.istem(ipucu: "Türkçe sesli asistan komutu.", defter: uzun)
        #expect(istem.count <= 600 && istem.hasPrefix("Türkçe sesli asistan komutu.") && !istem.hasSuffix(","))
        #expect(WhisperIstemcisi.istem(ipucu: nil, defter: "") == "")
        #expect(WhisperIstemcisi.sozlukYankisi("mitoz, ribozom", defter: "mitoz, ribozom, lizozom"))
        #expect(!WhisperIstemcisi.sozlukYankisi("mitoz bölünmesi nedir", defter: "mitoz, ribozom"))
    }

    @Test func dilModeliGirdileri() {
        let a = DikteDilModeli.girdiOzeti(["mitoz", "Ayşe Yılmaz", "ribozom"])
        #expect(a == DikteDilModeli.girdiOzeti(["ribozom", "mitoz", "Ayşe Yılmaz"]), "sıra bağımsız")
        #expect(a == DikteDilModeli.girdiOzeti(["mitoz", "Ayşe Yılmaz", "ribozom"]), "kararlı")
        #expect(a.count == 12 && a.allSatisfy(\.isHexDigit))
        #expect(a != DikteDilModeli.girdiOzeti(["mitoz"]))
        let tr = Locale(identifier: "tr_TR")
        let ifadeler = DikteDilModeli.ifadeler(kisiler: ["Ayşe Yılmaz", "ayşe yılmaz", " "], defter: ["mitoz", "Mitoz", "Fotosentez"])
        #expect(ifadeler.first == "Ayşe Yılmaz" && ifadeler.filter { $0.lowercased(with: tr) == "ayşe yılmaz" }.count == 1)
        #expect(ifadeler.filter { $0.lowercased(with: tr) == "mitoz" }.count == 1, "defter yinelenmez")
        #expect(ifadeler.count == 3, "yalnız kişiler + defter (sabit terim listesi yok)")
    }
}
