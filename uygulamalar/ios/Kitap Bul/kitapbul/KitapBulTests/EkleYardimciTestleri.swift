import Testing
import Foundation
import SwiftData
@testable import _01

/// Ekle sekmesi: tekli barkod denetimi, katalogdaki kitap onayı, kayıt şeridi, Son Eklemeler özeti
/// ve onay kuyruğu bölümleri (kamera olmadan, saf yardımcılarla).
@MainActor
@Suite(.serialized)
struct EkleYardimciTestleri {
    @Test func tekliTaramaYalnizKitapBarkodunuKabulEder() {
        #expect(TekliBarkodDenetimi.kabulEdilir("9789750718434"))
        #expect(TekliBarkodDenetimi.kabulEdilir("978-975-07-1843-4"), "Tireli ISBN de kabul edilir")
        #expect(TekliBarkodDenetimi.kabulEdilir("0306406152"), "ISBN-10")
        // Uygulamanın kendi barkodu (200…) yalnız katalogda kayıtlıysa: aynı önek mağaza fiyat etiketinde de var
        let icKod = InternalBarcode.generate(existingCodes: [])
        #expect(TekliBarkodDenetimi.kabulEdilir(icKod, kayitliIcKod: { $0 == icKod }), "Katalogdaki uygulama barkodu")
        #expect(!TekliBarkodDenetimi.kabulEdilir(icKod), "Kayıtsız 200… kodu (fiyat etiketi) tarayıcıyı kapatmaz")
        #expect(!TekliBarkodDenetimi.kabulEdilir(icKod, kayitliIcKod: { _ in false }))
        // Fiyat etiketi, ürün barkodu ya da kontrol basamağı hatalı kod tarayıcıyı kapatmamalı
        #expect(!TekliBarkodDenetimi.kabulEdilir("8690504000016"))
        #expect(!TekliBarkodDenetimi.kabulEdilir("9789750718435"))
        #expect(!TekliBarkodDenetimi.kabulEdilir("OGR-7A-12"))
        #expect(!TekliBarkodDenetimi.kabulEdilir(""))
    }

    @Test func katalogdakiKitapOnayiKonumVeNushayiSoyler() {
        let kitap = CatalogBook(book: Book(title: "Şeker Portakalı", author: "Vasconcelos", isbn: "9789750718434",
                                           quantity: 3, shelf: "2", cabinet: "3"))
        let onay = KatalogdakiKitapOnayi(kitap: kitap, isbn: "9789750718434")
        #expect(onay.baslik == "“Şeker Portakalı” zaten katalogda")
        #expect(onay.mesaj.contains("Dolap 3 · Raf 2"))
        #expect(onay.mesaj.contains("3 nüsha"))
        #expect(onay.nushaEklenebilir)
        #expect(onay.id == kitap.id)
    }

    @Test func katalogdakiKitapOnayiBosKonumuVeDusulmusKaydiAyirir() {
        let yersiz = KatalogdakiKitapOnayi(kitap: CatalogBook(book: Book(title: "", author: "", isbn: "9789750718434")),
                                           isbn: "9789750718434")
        #expect(yersiz.baslik == "“9789750718434” zaten katalogda", "Adı yoksa ISBN söylenir")
        #expect(yersiz.mesaj.contains(CatalogBook.yerAtanmamis))
        #expect(yersiz.mesaj.contains("1 nüsha"))

        let dusulmus = KatalogdakiKitapOnayi(kitap: CatalogBook(book: Book(title: "Eski", author: "Yazar", isbn: "9789750718434",
                                                                          isWithdrawn: true)), isbn: "9789750718434")
        #expect(!dusulmus.nushaEklenebilir, "Düşülmüş kayda nüsha eklenmez")
        #expect(dusulmus.yeniKayitAcilabilir, "Yeniden edinilen kitap yeni kayıt olarak eklenebilmeli")
        #expect(dusulmus.mesaj.contains("düşülmüş"))
        #expect(!yersiz.yeniKayitAcilabilir, "Etkin kayıtta yeni kayıt değil nüsha önerilir")
    }

    /// Aynı ISBN'li düşülmüş ve etkin kayıt varsa onay etkin kaydı gösterir (nüsha eklenebilir);
    /// yalnız düşülmüş kayıt varsa o döner.
    @Test func katalogEslesmesiOnceEtkinKaydiSecer() {
        let isbn = "9789750718434"
        let dusulmus = CatalogBook(book: Book(title: "Yıpranan", author: "Yazar", isbn: isbn, isWithdrawn: true))
        let etkin = CatalogBook(book: Book(title: "Yeni Nüsha", author: "Yazar", isbn: "978-975-07-1843-4"))
        let baska = CatalogBook(book: Book(title: "Başka", author: "Yazar", isbn: "0306406152"))
        #expect(KatalogdakiKitapOnayi.eslesenKayit(isbn: isbn, in: [dusulmus, baska, etkin])?.id == etkin.id)
        #expect(KatalogdakiKitapOnayi.eslesenKayit(isbn: isbn, in: [dusulmus, baska])?.id == dusulmus.id)
        #expect(KatalogdakiKitapOnayi.eslesenKayit(isbn: isbn, in: [baska]) == nil)
    }

    @Test func kayitSeridiMetinleri() {
        var serit = SonEklemeSeridi(kitapAdi: "Küçük Prens", tur: .yeniKayit, islemKimligi: UUID())
        #expect(serit.metin == "“Küçük Prens” eklendi")
        #expect(serit.geriAlinabilir)
        serit.tur = .nusha(1)
        #expect(serit.metin == "“Küçük Prens” için nüsha eklendi (+1)")
        serit.tur = .nusha(3)
        #expect(serit.metin == "“Küçük Prens” için 3 nüsha eklendi")
        serit.tur = .geriAlindi
        #expect(serit.metin == "“Küçük Prens” eklemesi geri alındı")
        #expect(!serit.geriAlinabilir, "Geri alınan kayıt ikinci kez geri alınmaz")
        #expect(SonEklemeSeridi(kitapAdi: "  ", tur: .yeniKayit, islemKimligi: nil).metin == "“Kitap” eklendi")
    }

    @Test func sonEklemelerOzetindeSifirYazilmaz() {
        #expect(EkleOzeti.oturum(bekleyen: 0, yeni: 0, nusha: 0) == nil)
        #expect(EkleOzeti.oturum(bekleyen: 2, yeni: 0, nusha: 0) == "2 kayıt kontrol bekliyor")
        #expect(EkleOzeti.oturum(bekleyen: 0, yeni: 3, nusha: 1) == "3 yeni kayıt · 1 nüsha eklendi")
        var oturum = ScanSession(kind: .photo, title: "Kitap ekleme")
        #expect(oturum.ozetMetni == nil)
        oturum.insertedIDs = [UUID()]
        oturum.mergedCopies = [UUID(): 0]
        #expect(oturum.ozetMetni == "1 yeni kayıt")
    }

    @Test func onayKuyrugundaKontrolVeKayitSayisiAyniKuralla() {
        var adsiz = BookDraft(); adsiz.title = "   "
        var supheli = BookDraft(); supheli.title = "Şüpheli Ad"; supheli.lowConfidenceFields = ["author"]
        var hazir = BookDraft(); hazir.title = "Hazır Kitap"
        #expect(EkleOzeti.kontrolGerekli(adsiz))
        #expect(EkleOzeti.kontrolGerekli(supheli))
        #expect(!EkleOzeti.kontrolGerekli(hazir))
        // "Adı Olanları Kaydet" sayısı kayıt mantığıyla aynı: adı boş olan kuyrukta kalır
        #expect(EkleOzeti.kaydedilebilirSayisi([adsiz, supheli, hazir]) == 2)
    }

    @Test func bilgiNotuKaydaVeKayittanTaslagaGecmez() {
        var taslak = BookDraft()
        taslak.title = "Bulunamayan"
        taslak.isbn = "9789750718434"
        taslak.bilgiNotu = "Bu ISBN çevrimiçi kaynaklarda bulunamadı."
        let geri = BookDraft(book: taslak.snapshot)
        #expect(geri.bilgiNotu == nil)
        #expect(geri.title == "Bulunamayan")
    }

    /// Şeritteki "Geri al" ve onaydaki "Nüsha ekle (+1)" aynı tek işleme bağlıdır: işlem kimliği
    /// gelen taslağın kimliğidir, geri alma yalnız o nüshayı düşer ve makbuzu siler.
    @Test func tekliNushaEklemeTekIslemleGeriAlinir() throws {
        let schema = KitapVeritabani.schema
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        context.autosaveEnabled = false
        let mevcut = CatalogBook(book: Book(title: "Küçük Prens", author: "Saint-Exupéry", isbn: "9789750718434", quantity: 2))
        context.insert(mevcut)
        try context.save()

        let gelen = Book(title: mevcut.title, author: mevcut.author, isbn: "9789750718434", quantity: 1)
        let sonuc = try CatalogSaveEngine.save(gelen, context: context, catalog: [mevcut], source: "barcode")
        guard case .merged(let id, let eklenen) = sonuc else { Issue.record("Katalogdaki kitaba nüsha eklenmeli"); return }
        #expect(id == mevcut.id && eklenen == 1)
        #expect(mevcut.quantity == 3)
        #expect(try CatalogSaveEngine.receipt(for: gelen.id, context: context) != nil)

        try CatalogSaveEngine.undo(insertedIDs: [], mergedCopies: [id: eklenen], catalog: [mevcut], context: context,
                                   operationIDs: [gelen.id])
        #expect(mevcut.quantity == 2)
        #expect(try CatalogSaveEngine.receipt(for: gelen.id, context: context) == nil)
    }

    /// Şeritteki "Geri al" makbuza bağlıdır: aynı nüsha Son Eklemeler'deki "Eklemeleri Geri Al" ile
    /// geri alındıysa makbuz silinmiştir ve şerit adedi ikinci kez düşürmez.
    @Test func seritMakbuzSilinincGeriAlmaz() throws {
        let schema = KitapVeritabani.schema
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        context.autosaveEnabled = false
        let mevcut = CatalogBook(book: Book(title: "Küçük Prens", author: "Saint-Exupéry", isbn: "9789750718434", quantity: 3))
        context.insert(mevcut)
        try context.save()

        let gelen = Book(title: mevcut.title, author: mevcut.author, isbn: "9789750718434", quantity: 1)
        let sonuc = try CatalogSaveEngine.save(gelen, context: context, catalog: [mevcut], source: "barcode")
        guard case .merged(let id, let eklenen) = sonuc else { Issue.record("Katalogdaki kitaba nüsha eklenmeli"); return }
        let serit = SonEklemeSeridi(kitapAdi: mevcut.title, tur: .nusha(eklenen), islemKimligi: gelen.id, oturumKimligi: UUID())
        #expect(serit.makbuzDuruyor(hedef: id, context: context))
        #expect(!serit.makbuzDuruyor(hedef: UUID(), context: context), "Başka kitabın makbuzu sayılmaz")
        #expect(!SonEklemeSeridi(kitapAdi: "X", tur: .yeniKayit, islemKimligi: nil).makbuzDuruyor(hedef: id, context: context),
                "İşlem kimliği olmayan şerit geri almaz")

        // Oturum geri alması (Son Eklemeler) aynı nüshayı düşer; şerit artık geri almamalı
        try CatalogSaveEngine.undo(insertedIDs: [], mergedCopies: [id: eklenen], catalog: [mevcut], context: context,
                                   operationIDs: [gelen.id])
        #expect(mevcut.quantity == 3)
        #expect(!serit.makbuzDuruyor(hedef: id, context: context), "Makbuz silindi: adet ikinci kez düşmemeli")
    }

    /// Yeni kayıt eklendikten sonra düzenlendiyse şeridin "Geri al"ı (kalıcı silme) önce onay ister.
    @Test func seritSonradanDegisenKaydiAyirir() {
        var kitap = Book(title: "Küçük Prens", author: "Saint-Exupéry", isbn: "9789750718434")
        let serit = SonEklemeSeridi(kitapAdi: kitap.title, tur: .yeniKayit, islemKimligi: kitap.id, kayitAni: kitap)
        #expect(!serit.sonradanDegisti(kitap), "Değişmeyen kayıt sormadan geri alınır")
        kitap.shelf = "4"
        kitap.notes = "Kütüphaneci notu"
        #expect(serit.sonradanDegisti(kitap))
        #expect(!serit.sonradanDegisti(nil), "Kayıt bulunamazsa karar motorundadır")
        var nusha = serit
        nusha.tur = .nusha(1)
        #expect(!nusha.sonradanDegisti(kitap), "Nüsha geri alması kaydı silmez; motor raf değişikliğini zaten denetler")
    }
}
