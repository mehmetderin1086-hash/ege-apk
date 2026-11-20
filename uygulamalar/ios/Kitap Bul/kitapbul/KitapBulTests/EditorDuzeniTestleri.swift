import Testing
import Foundation
@testable import _01

/// Kitap editörünün sadeleştirilmiş düzeni: katlı "Diğer bilgiler" grubunun ne zaman kendiliğinden
/// açıldığı ve "Son konumu kullan" değerinin nerede yazılıp nasıl gösterildiği (görünümsüz, saf yardımcılarla).
@MainActor
@Suite(.serialized)
struct EditorDuzeniTestleri {
    private func konum(_ defaults: UserDefaults) -> [String] {
        let son = SonKonum.yukle(defaults: defaults)
        return [son.yer, son.dolap, son.raf]
    }

    private func sorunlar(_ taslak: BookDraft) -> Set<String> {
        EditorDigerBilgiler.sorunluAlanlar(BookEditorValidation.validate(taslak.dogrulamaGirdisi),
                                           dusukGuvenli: taslak.lowConfidenceFields)
    }

    @Test func bosYeniFormDigerBilgileriAcmaz() {
        // Boş kitap adı her yeni formda doğrulama sorunudur ama alan ilk bölümde açık durur
        #expect(sorunlar(BookDraft()).isEmpty)
        var taslak = BookDraft()
        taslak.isbn = "123"
        taslak.cabinet = "3\n"
        taslak.lowConfidenceFields = ["title", "author", "isbn"]
        #expect(sorunlar(taslak).isEmpty, "Açık alanlardaki sorun ve düşük güven grubu açmaz")
    }

    @Test func gruptakiSorunVeDusukGuvenGrubuAcar() {
        var taslak = BookDraft()
        taslak.title = "Küçük Prens"
        taslak.publicationYear = "abc"
        #expect(sorunlar(taslak) == ["publicationYear"])
        taslak.publicationYear = "1943"
        taslak.pageCount = "0"
        #expect(sorunlar(taslak) == ["pageCount"])
        taslak.pageCount = "96"
        taslak.lowConfidenceFields = ["publisher", "edition", "title"]
        #expect(sorunlar(taslak) == ["publisher", "edition"])
    }

    @Test func geminininKategoriVeDilBelirsizligiGrubuAcar() {
        var taslak = BookDraft()
        GeminiBookRecognizer.merge(GeminiBookFields(title: "Küçük Prens", author: "Saint-Exupéry", language: "Türkçe",
                                                    category: "Roman", uncertain: ["category", "language"]), into: &taslak)
        #expect(sorunlar(taslak) == ["category", "language"])
    }

    @Test func okumaninIsaretledigiHerAlanGorunurKalir() {
        // Gemini her alanı belirsiz döndürse de işaretlenen her anahtar ya açık bölümde ya da grubu
        // açan alanlar arasında olmalı; yoksa uyarı katlı grupta görünmeden kalır.
        var alanlar = GeminiBookFields(title: "A", author: "B", publisher: "C", publicationYear: "2020", edition: "2",
                                       pageCount: "100", language: "Türkçe", category: "Roman", summary: "Özet",
                                       uncertain: BookFieldMetadata.fields)
        alanlar.series = "Seri"; alanlar.tags = ["macera"]; alanlar.readingLevel = "Ortaokul"
        alanlar.contentWarning = "Yok"; alanlar.imageQuality = "blurry"
        var taslak = BookDraft()
        GeminiBookRecognizer.merge(alanlar, into: &taslak)
        let acikBolum: Set<String> = ["title", "author", "isbn"]
        let gruptakiler = taslak.lowConfidenceFields.filter { !$0.hasPrefix("imageQuality:") && !acikBolum.contains($0) }
        #expect(!gruptakiler.isEmpty)
        #expect(gruptakiler.isSubset(of: EditorDigerBilgiler.guvenAlanlari), "Grubu açmayan işaret: \(gruptakiler)")
    }

    @Test func geminiNoktasiYalnizGeminiyeAitDoluVeDegismemisAlandaCikar() {
        var taslak = BookDraft()
        taslak.isbn = "9789750718434" // barkoddan gelmiş gibi: Gemini damgası almaz
        GeminiBookRecognizer.merge(GeminiBookFields(title: "Küçük Prens", author: "Saint-Exupéry", category: "Roman"),
                                   into: &taslak)
        let gemini = EditorGuvenIsareti.geminiAlanlari(taslak.fieldMetadata)
        func nokta(_ alan: String, _ deger: String, ilk: String? = nil) -> Bool {
            EditorGuvenIsareti.geminiOkudu(alan, deger: deger, ilkDeger: ilk ?? deger, taslak: taslak, geminiAlanlari: gemini)
        }
        #expect(nokta("title", taslak.title))
        #expect(nokta("category", taslak.category))
        #expect(!nokta("pageCount", taslak.pageCount), "Gemini'nin boş bıraktığı alanda nokta çıkmaz")
        #expect(!nokta("isbn", taslak.isbn), "Barkoddan gelen ISBN Gemini'ye mal edilmez")
        #expect(!nokta("title", "Küçük Prens 2", ilk: taslak.title), "Editörde değişen alanda nokta çıkmaz")
        taslak.lowConfidenceFields.insert("author")
        #expect(!nokta("author", taslak.author), "Düşük güvenli alanda nokta yerine üçgen çıkar")
        taslak.recognizedByGemini = false
        #expect(!nokta("title", taslak.title))
        #expect(EditorGuvenIsareti.geminiAlanlari(nil).isEmpty)
    }

    @Test func dogrulamaGirdisiTaslakAlanlariniTasir() {
        var taslak = BookDraft()
        taslak.title = "Ad"; taslak.isbn = "9789750718434"; taslak.publicationYear = "2020"; taslak.pageCount = "120"
        taslak.quantity = 3; taslak.location = "Kütüphane"; taslak.cabinet = "3"; taslak.shelf = "2"
        let girdi = taslak.dogrulamaGirdisi
        #expect(girdi.title == "Ad" && girdi.isbn == "9789750718434" && girdi.publicationYear == "2020")
        #expect(girdi.pageCount == "120" && girdi.quantity == 3)
        #expect(girdi.location == "Kütüphane" && girdi.cabinet == "3" && girdi.shelf == "2")
    }

    @Test func sonKonumYalnizEkleAkisindakiYeniKayittaYazilir() {
        #expect(SonKonum.yazilmali(hatirla: true, existingBookID: nil))
        #expect(!SonKonum.yazilmali(hatirla: true, existingBookID: UUID()), "Mevcut kitabın düzenlenmesi yazmaz")
        #expect(!SonKonum.yazilmali(hatirla: false, existingBookID: nil), "Onay kuyruğu düzenlemesi yazmaz")
        #expect(!SonKonum.yazilmali(hatirla: false, existingBookID: UUID()))
    }

    @Test func sonKonumKirpilarakYazilirBosKonumOncekiniKorur() throws {
        let suite = UUID().uuidString, defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(konum(defaults) == ["", "", ""])
        SonKonum.kaydet(yer: " Kütüphane ", dolap: "3", raf: " 2", defaults: defaults)
        #expect(konum(defaults) == ["Kütüphane", "3", "2"])
        SonKonum.kaydet(yer: "  ", dolap: "", raf: "\n", defaults: defaults)
        #expect(konum(defaults) == ["Kütüphane", "3", "2"], "Konumsuz kayıt son konumu silmez")
        // Üç alan birlikte yazılır: yeni konumda boş kalan alan eskisinden miras kalmaz
        SonKonum.kaydet(yer: "", dolap: "5", raf: "", defaults: defaults)
        #expect(konum(defaults) == ["", "5", ""])
    }

    @Test func sonKonumDugmesiTekKonumBiciminiKullanir() {
        #expect(SonKonum.dugmeBasligi(yer: "", dolap: "3", raf: "2") == "Son konumu kullan (Dolap 3 · Raf 2)")
        #expect(SonKonum.dugmeBasligi(yer: "Kütüphane", dolap: "3", raf: "") == "Son konumu kullan (Kütüphane · Dolap 3)")
        #expect(SonKonum.dugmeBasligi(yer: " ", dolap: "", raf: "") == nil)
    }

    @Test func sonKonumArsivleBirlikteTasinir() {
        // Başka arşive geçişte ve geri yüklemede arşiv ayarları silinip yeniden yazılır; son konum
        // da bunlardan biri olmalı, yoksa önceki kataloğun dolabı yeni kataloğa taşınır.
        #expect(SonKonum.anahtarlar == ["sonKonum.yer", "sonKonum.dolap", "sonKonum.raf"])
        #expect(SonKonum.anahtarlar.isSubset(of: ArchiveSettings.allowedKeys))
    }

    @Test func rafAtamaDolapNotuEtkisiniSoyler() {
        #expect(ShelfAssignSetupSheet.dolapNotu(dolap: " ", sonKonumdan: false)
                == "Dolap boş kalırsa kitapların kayıtlı dolabı korunur; yalnız raf değişir.")
        let not = ShelfAssignSetupSheet.dolapNotu(dolap: " 3 ", sonKonumdan: true)
        #expect(not.hasPrefix("Dolap, son eklenen kitabın konumundan alındı."))
        #expect(not.contains("dolabı “3” olarak değişir"))
        #expect(!ShelfAssignSetupSheet.dolapNotu(dolap: "A", sonKonumdan: false).contains("son eklenen"))
    }
}
