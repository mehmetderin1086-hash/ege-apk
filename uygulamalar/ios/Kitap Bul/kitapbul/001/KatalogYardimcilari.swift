import Foundation
import SwiftUI
import SwiftData
import CoreImage
import UIKit

// MARK: - Okuma düzeyi

nonisolated enum OkumaDuzeyi {
    static let liste = ["Okul öncesi", "1-2. sınıf", "3-4. sınıf", "Ortaokul", "Lise", "Yetişkin"]
}

// MARK: - Konum

/// Konumun tek biçimi: "Oda · Dolap 3 · Raf 2". Kitaplar, Ana Sayfa araması, ayrıntı, raflar,
/// barkod masası, nüsha ve sayım ekranları bu metni kullanır; boş konumun adı `yerAtanmamis`.
extension CatalogBook {
    static let yerAtanmamis = "Yer atanmamış"

    /// Boş ya da yalnız boşluk olan parçalar atlanır; hiçbiri yoksa `nil`.
    static func konumMetni(yer: String?, dolap: String?, raf: String?) -> String? {
        func dolu(_ metin: String?) -> String? {
            let temiz = metin?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return temiz.isEmpty ? nil : temiz
        }
        let parcalar = [dolu(yer), dolu(dolap).map { "Dolap " + $0 }, dolu(raf).map { "Raf " + $0 }].compactMap { $0 }
        return parcalar.isEmpty ? nil : parcalar.joined(separator: " · ")
    }

    /// Kitabın yeri (oda/genel konum · dolap · raf); kayıtlı değilse `nil`.
    var konumMetni: String? { Self.konumMetni(yer: location, dolap: cabinet, raf: shelf) }

    /// Nüshanın kendi dolap/rafı varsa o, yoksa kitabınki.
    func konumMetni(nusha: BookCopy?) -> String? {
        guard let nusha else { return konumMetni }
        return Self.konumMetni(yer: location, dolap: nusha.effectiveCabinet(for: self), raf: nusha.effectiveShelf(for: self))
    }
}

extension CatalogBook {
    static let kategorisiz = "Kategorisiz"

    /// Kategorinin tek adı: boşluk kırpılır, boş ya da yalnız boşluksa "Kategorisiz".
    var kategoriAdi: String { Self.kategoriAdi(category) }

    nonisolated static func kategoriAdi(_ ham: String?) -> String {
        let temiz = ham?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return temiz.isEmpty ? "Kategorisiz" : temiz
    }
}

// MARK: - Demirbaşla bulma

/// Arama terimi bir demirbaş koduna uyuyorsa kitabı bulur: nüsha demirbaşı ya da kitabın kendi
/// demirbaşı. Kural barkod masasıyla aynıdır (`OkutCozumleyici.demirbasNushalari`: büyük/küçük harf
/// ve ayraç farkı sayılmaz); arama koşulu değişmez.
enum DemirbasArama {
    /// Koda uyan ayrı kitaplar, ada göre. Aynı kod birden çok kitapta kayıtlıysa hepsi döner.
    static func kitaplar(_ terim: String, context: ModelContext) -> [CatalogBook] {
        let kod = terim.trimmingCharacters(in: .whitespacesAndNewlines)
        let anahtar = CatalogMatcher.normalize(kod)
        guard !anahtar.isEmpty else { return [] }
        let nushalar: [BookCopy]
        let kitapKodlular: [CatalogBook]
        if let r = OkutCozumleyici.demirbasRakamlari(anahtar) {
            nushalar = (try? OkutCozumleyici.demirbasNushalari(kod, context: context)) ?? []
            let (a, b, c, d) = (r[0], r[1], r[2], r[3])
            let istek = FetchDescriptor<CatalogBook>(predicate: #Predicate {
                ($0.accessionCode?.contains(a) ?? false) && ($0.accessionCode?.contains(b) ?? false)
                    && ($0.accessionCode?.contains(c) ?? false) && ($0.accessionCode?.contains(d) ?? false)
            })
            kitapKodlular = ((try? context.fetch(istek)) ?? []).filter { CatalogMatcher.normalize($0.accessionCode ?? "") == anahtar }
        } else {
            // Rakamsız terim çoğunlukla sözcük aramasıdır ("orwell"): her aramada nüsha tablosu
            // baştan sona okunmasın diye yalnız birebir, büyük ve küçük harfli yazım aranır.
            let buyuk = kod.uppercased(), kucuk = kod.lowercased()
            nushalar = (try? context.fetch(FetchDescriptor<BookCopy>(predicate: #Predicate {
                $0.accessionCode == kod || $0.accessionCode == buyuk || $0.accessionCode == kucuk
            }))) ?? []
            let s1: String? = kod, s2: String? = buyuk, s3: String? = kucuk
            kitapKodlular = (try? context.fetch(FetchDescriptor<CatalogBook>(predicate: #Predicate {
                $0.accessionCode == s1 || $0.accessionCode == s2 || $0.accessionCode == s3
            }))) ?? []
        }
        let nushaKitaplari = Array(Set(nushalar.map(\.bookID)))
        let kitaplar = nushaKitaplari.isEmpty ? [] : ((try? context.fetch(FetchDescriptor<CatalogBook>(
            predicate: #Predicate { nushaKitaplari.contains($0.id) }))) ?? [])
        var gorulen = Set<UUID>()
        return (kitaplar + kitapKodlular)
            .filter { gorulen.insert($0.id).inserted }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// Yalnız tek kitaba uyuyorsa o kitap; uyan yoksa ya da kod birden çok kitapta kayıtlıysa `nil`
    /// (ayrıntı kendiliğinden açılmaz, seçim kullanıcıya kalır).
    static func kitap(_ terim: String, context: ModelContext) -> CatalogBook? {
        let bulunan = kitaplar(terim, context: context)
        return bulunan.count == 1 ? bulunan.first : nil
    }
}

// MARK: - Mükerrer denetimi

/// Düzenleyicide "bu kitap zaten var" uyarısı: aynı ISBN ya da aynı (aksansız) ad.
enum MukerrerDenetimi {
    struct Eslesme: Identifiable, Equatable {
        let id: UUID
        let title: String
        let detail: String
    }

    static func eslesmeler(title: String, isbn: String, haric: UUID?, context: ModelContext, limit: Int = 3) -> [Eslesme] {
        var bulunan: [CatalogBook] = []
        let isbnAnahtar = ISBNFormatter.normalize(isbn)
        if !isbnAnahtar.isEmpty {
            // Katalogda tireli/boşluklu yazılmış olabilir ve tire yerleri yayınevine göre değişir.
            // Son iki rakam (kontrol basamağı ve öncesi) aralarında tire/boşluk olsa da olmasa da
            // bitişik yazılır: onunla SQL'de daralt, sonra rakamları tam karşılaştır.
            let son = Array(isbnAnahtar.suffix(2)).map(String.init)
            let bitisik = son.joined()
            let tireli = son.joined(separator: "-")
            let bosluklu = son.joined(separator: " ")
            // Önce tam eşleşme (en sık durum: tiresiz kayıtlı ISBN) — tek satır getirir
            var tam = FetchDescriptor<CatalogBook>(predicate: #Predicate { $0.isbn == isbnAnahtar })
            tam.fetchLimit = 5
            var aday = (try? context.fetch(tam)) ?? []
            if aday.isEmpty {
                var genis = FetchDescriptor<CatalogBook>(
                    predicate: #Predicate {
                        ($0.isbn?.contains(bitisik) ?? false) || ($0.isbn?.contains(tireli) ?? false)
                            || ($0.isbn?.contains(bosluklu) ?? false)
                    })
                genis.fetchLimit = 2_000
                aday = (try? context.fetch(genis)) ?? []
            }
            bulunan += aday.filter { ISBNFormatter.normalize($0.isbn ?? "") == isbnAnahtar }
        }
        let adAnahtar = CatalogMatcher.normalize(title)
        if adAnahtar.count >= 3 {
            var descriptor = FetchDescriptor<CatalogBook>(predicate: #Predicate { $0.searchKey?.contains(adAnahtar) ?? false })
            descriptor.fetchLimit = 50
            let aday = (try? context.fetch(descriptor)) ?? []
            bulunan += aday.filter { CatalogMatcher.normalize($0.title) == adAnahtar }
        }
        var gorulen = Set<UUID>()
        return bulunan
            .filter { $0.id != haric && gorulen.insert($0.id).inserted }
            .prefix(limit)
            .map { kitap in
                var parcalar: [String] = []
                if !kitap.author.isEmpty { parcalar.append(kitap.author) }
                if let dolap = kitap.cabinet, !dolap.isEmpty { parcalar.append("Dolap \(dolap)") }
                return Eslesme(id: kitap.id, title: kitap.title,
                               detail: parcalar.isEmpty ? "" : " (" + parcalar.joined(separator: ", ") + ")")
            }
    }
}

// MARK: - Seri analizi

enum SeriAnalizi {
    /// 1'den en büyük cilde kadar eksik cilt numaraları.
    static func eksikCiltler(_ ciltler: [Int]) -> [Int] {
        let mevcut = Set(ciltler.filter { $0 > 0 })
        guard let enBuyuk = mevcut.max(), enBuyuk <= 500 else { return [] }
        return (1...enBuyuk).filter { !mevcut.contains($0) }
    }

    static func seriKitaplari(_ seri: String, context: ModelContext) -> [CatalogBook] {
        let ad = seri
        let kitaplar = (try? context.fetch(FetchDescriptor<CatalogBook>(predicate: #Predicate { $0.series == ad }))) ?? []
        return kitaplar.sorted { ($0.volume ?? 0, $0.title) < ($1.volume ?? 0, $1.title) }
    }

    /// Katalogdaki tüm seriler: ad → (kitap sayısı, eksik ciltler)
    static func ozet(_ kitaplar: [CatalogBook]) -> [(seri: String, sayi: Int, eksik: [Int])] {
        var gruplar: [String: [Int]] = [:]
        for kitap in kitaplar {
            guard let seri = kitap.series, !seri.isEmpty else { continue }
            gruplar[seri, default: []].append(kitap.volume ?? 0)
        }
        return gruplar
            .map { (seri: $0.key, sayi: $0.value.count, eksik: eksikCiltler($0.value)) }
            .sorted { $0.seri.localizedStandardCompare($1.seri) == .orderedAscending }
    }
}

// MARK: - Benzer kitaplar

enum BenzerKitaplar {
    /// Aynı seri > aynı yazar > ortak etiket > aynı kategori/düzey.
    static func skor(_ a: CatalogBook, _ b: CatalogBook) -> Int {
        guard a.id != b.id else { return 0 }
        var puan = 0
        if let seri = a.series, !seri.isEmpty, seri == b.series { puan += 6 }
        let yazarA = CatalogMatcher.normalize(a.author)
        if !yazarA.isEmpty, yazarA == CatalogMatcher.normalize(b.author) { puan += 4 }
        let etiketlerA: Set<String> = Set(a.tagList.map { CatalogMatcher.normalize($0) })
        let etiketlerB: Set<String> = Set(b.tagList.map { CatalogMatcher.normalize($0) })
        let ortak: Int = etiketlerA.intersection(etiketlerB).count
        puan += min(3, ortak) * 2
        if let kategori = a.category, !kategori.isEmpty, kategori == b.category { puan += 2 }
        if let duzey = a.readingLevel, !duzey.isEmpty, duzey == b.readingLevel { puan += 1 }
        return puan
    }

    static func bul(_ kitap: CatalogBook, adaylar: [CatalogBook], limit: Int = 8) -> [CatalogBook] {
        typealias Aday = (kitap: CatalogBook, puan: Int)
        let puanli: [Aday] = adaylar
            .filter { !$0.isWithdrawn }
            .map { (kitap: $0, puan: skor(kitap, $0)) }
            .filter { $0.puan >= 2 }
        let sirali = puanli.sorted { (x: Aday, y: Aday) -> Bool in
            if x.puan != y.puan { return x.puan > y.puan }
            return x.kitap.title < y.kitap.title
        }
        return Array(sirali.prefix(limit).map { $0.kitap })
    }

    /// Adaylar yalnız ilgili alanlarla daraltılarak getirilir (50 bin kaydı belleğe almamak için).
    static func adaylar(for kitap: CatalogBook, context: ModelContext) -> [CatalogBook] {
        var sonuc: [CatalogBook] = []
        let yazar = kitap.author
        let kategori = kitap.category
        let seri = kitap.series
        func getir(_ predicate: Predicate<CatalogBook>) {
            var descriptor = FetchDescriptor<CatalogBook>(predicate: predicate)
            descriptor.fetchLimit = 60
            sonuc += (try? context.fetch(descriptor)) ?? []
        }
        if !yazar.isEmpty { getir(#Predicate { $0.author == yazar }) }
        if let seri, !seri.isEmpty { getir(#Predicate { $0.series == seri }) }
        if let kategori, !kategori.isEmpty { getir(#Predicate { $0.category == kategori }) }
        for etiket in kitap.tagList.prefix(3) {
            getir(#Predicate { $0.tags?.localizedStandardContains(etiket) ?? false })
        }
        var gorulen = Set<UUID>()
        return sonuc.filter { gorulen.insert($0.id).inserted }
    }
}

// MARK: - Kapak baskın rengi

/// Kapak fotoğrafının ortalama rengi (ayrıntı sayfası başlığı için). Bellekte önbelleklenir.
enum KapakRengi {
    private static let onbellek = NSCache<NSUUID, UIColor>()
    private nonisolated static let ciContext = CIContext(options: [.workingColorSpace: NSNull()])

    static func baskin(id: UUID, data: Data?) -> Color? {
        guard let data else { return nil }
        if let hazir = onbellek.object(forKey: id as NSUUID) { return Color(uiColor: hazir) }
        guard let renk = hesapla(data) else { return nil }
        onbellek.setObject(renk, forKey: id as NSUUID)
        return Color(uiColor: renk)
    }

    /// Önbellekte yoksa renk hesabı (CoreImage) ana iş parçacığını tutmasın diye arka planda yapılır.
    static func baskinArkaPlanda(id: UUID, data: Data?) async -> Color? {
        guard let data else { return nil }
        if let hazir = onbellek.object(forKey: id as NSUUID) { return Color(uiColor: hazir) }
        let renk = await Task.detached(priority: .utility) { hesapla(data) }.value
        guard let renk else { return nil }
        onbellek.setObject(renk, forKey: id as NSUUID)
        return Color(uiColor: renk)
    }

    nonisolated static func hesapla(_ data: Data) -> UIColor? {
        guard let girdi = CIImage(data: data),
              let filtre = CIFilter(name: "CIAreaAverage",
                                    parameters: [kCIInputImageKey: girdi, kCIInputExtentKey: CIVector(cgRect: girdi.extent)]),
              let cikti = filtre.outputImage
        else { return nil }
        var piksel = [UInt8](repeating: 0, count: 4)
        ciContext.render(cikti, toBitmap: &piksel, rowBytes: 4,
                         bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        return UIColor(red: CGFloat(piksel[0]) / 255, green: CGFloat(piksel[1]) / 255,
                       blue: CGFloat(piksel[2]) / 255, alpha: 1)
    }
}

// MARK: - Kayıtlı filtreler ve arama geçmişi

struct KayitliFiltre: Codable, Identifiable, Equatable {
    var id = UUID()
    var ad: String
    var filtre: KitapFiltresi
    var siralama: String
}

enum KayitliFiltreStore {
    private static let anahtar = "kitaplarKayitliFiltreler"

    static func hepsi() -> [KayitliFiltre] {
        guard let data = UserDefaults.standard.data(forKey: anahtar) else { return [] }
        return (try? JSONDecoder().decode([KayitliFiltre].self, from: data)) ?? []
    }

    static func kaydet(_ liste: [KayitliFiltre]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(liste), forKey: anahtar)
    }

    static func ekle(_ filtre: KayitliFiltre) {
        var liste = hepsi().filter { $0.ad != filtre.ad }
        liste.append(filtre)
        kaydet(liste)
    }

    static func sil(_ id: UUID) {
        guard YetkiDurumu.shared.yonetici else { AppLog.write("Yönetici gerektiren toplu işlem engellendi"); return }
        kaydet(hepsi().filter { $0.id != id })
    }
}

enum AramaGecmisi {
    private static let anahtar = "kitaplarAramaGecmisi"
    static let enFazla = 10

    static func hepsi() -> [String] {
        UserDefaults.standard.stringArray(forKey: anahtar) ?? []
    }

    static func ekle(_ terim: String) {
        let temiz = terim.trimmingCharacters(in: .whitespacesAndNewlines)
        guard temiz.count >= 2 else { return }
        var liste = hepsi().filter { $0.caseInsensitiveCompare(temiz) != .orderedSame }
        liste.insert(temiz, at: 0)
        UserDefaults.standard.set(Array(liste.prefix(enFazla)), forKey: anahtar)
    }

    static func temizle() {
        UserDefaults.standard.removeObject(forKey: anahtar)
    }
}

// MARK: - A–Z bölümleri

enum AlfabeBolumleri {
    /// Türkçe alfabeye göre baş harf (Ç, Ğ, İ, Ö, Ş, Ü ayrı bölüm; rakam ve simgeler "#").
    static func basHarf(_ metin: String) -> String {
        guard let ilk = metin.trimmingCharacters(in: .whitespacesAndNewlines).first else { return "#" }
        let harf = String(ilk).uppercased(with: Locale(identifier: "tr_TR"))
        return harf.first?.isLetter == true ? harf : "#"
    }

    static func grupla(_ kitaplar: [CatalogBook], anahtar: (CatalogBook) -> String) -> [(harf: String, kitaplar: [CatalogBook])] {
        var sira: [String] = []
        var gruplar: [String: [CatalogBook]] = [:]
        for kitap in kitaplar {
            let harf = basHarf(anahtar(kitap))
            if gruplar[harf] == nil { sira.append(harf) }
            gruplar[harf, default: []].append(kitap)
        }
        return sira.map { (harf: $0, kitaplar: gruplar[$0] ?? []) }
    }
}

// MARK: - Toplu işlemler

enum TopluKitapIslemi {
    static func kategori(_ ad: String, _ kitaplar: [CatalogBook]) {
        guard YetkiDurumu.shared.yonetici else { AppLog.write("Yönetici gerektiren toplu işlem engellendi"); return }
        kitaplar.forEach { book in
            let before = book.book; book.category = ad; stampManual(book, before: before); book.refreshSearchKey()
        }
    }

    nonisolated enum YerAlani: Hashable { case dolap, raf }

    /// Dolu alanı yazar, boş bırakılan alanı korur; `temizle` içindeki alan boşaltılır.
    /// Dönüş: sonucu anlatan kısa özet ("Dolap C, raf değişmedi").
    @discardableResult
    static func yer(dolap: String, raf: String, temizle: Set<YerAlani> = [], _ kitaplar: [CatalogBook]) -> String {
        guard YetkiDurumu.shared.yonetici else { AppLog.write("Yönetici gerektiren toplu işlem engellendi"); return "" }
        for kitap in kitaplar {
            let before = kitap.book
            if temizle.contains(.dolap) { kitap.cabinet = nil } else if !dolap.isEmpty { kitap.cabinet = dolap }
            if temizle.contains(.raf) { kitap.shelf = nil } else if !raf.isEmpty { kitap.shelf = raf }
            stampManual(kitap, before: before)
        }
        return yerOzeti(dolap: dolap, raf: raf, temizle: temizle)
    }

    nonisolated static func yerOzeti(dolap: String, raf: String, temizle: Set<YerAlani>) -> String {
        let dolapMetni = temizle.contains(.dolap) ? "dolap temizlendi" : (dolap.isEmpty ? "dolap değişmedi" : "Dolap \(dolap)")
        let rafMetni = temizle.contains(.raf) ? "raf temizlendi" : (raf.isEmpty ? "raf değişmedi" : "Raf \(raf)")
        let ozet = dolapMetni + ", " + rafMetni
        return ozet.prefix(1).uppercased(with: Locale(identifier: "tr_TR")) + ozet.dropFirst()
    }

    static func okuma(_ durum: String, _ kitaplar: [CatalogBook]) {
        guard YetkiDurumu.shared.yonetici else { AppLog.write("Yönetici gerektiren toplu işlem engellendi"); return }
        kitaplar.forEach { $0.readingStatus = durum }
    }

    static func duzey(_ duzey: String, _ kitaplar: [CatalogBook]) {
        guard YetkiDurumu.shared.yonetici else { AppLog.write("Yönetici gerektiren toplu işlem engellendi"); return }
        kitaplar.forEach { book in
            let before = book.book; book.readingLevel = duzey.isEmpty ? nil : duzey; stampManual(book, before: before)
        }
    }

    /// Etiket ekler (var olanları korur, aynısını iki kez eklemez).
    static func etiketEkle(_ etiket: String, _ kitaplar: [CatalogBook]) {
        guard YetkiDurumu.shared.yonetici else { AppLog.write("Yönetici gerektiren toplu işlem engellendi"); return }
        let yeni = etiket.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !yeni.isEmpty else { return }
        for kitap in kitaplar {
            let before = kitap.book
            var liste = kitap.tagList
            for etiket in yeni where !liste.contains(where: { $0.caseInsensitiveCompare(etiket) == .orderedSame }) {
                liste.append(etiket)
            }
            kitap.tags = liste.joined(separator: ", ")
            stampManual(kitap, before: before)
            kitap.refreshSearchKey()
        }
    }

    static func dus(_ kitaplar: [CatalogBook], neden: String) {
        guard YetkiDurumu.shared.yonetici else { AppLog.write("Yönetici gerektiren toplu işlem engellendi"); return }
        for kitap in kitaplar {
            kitap.isWithdrawn = true
            kitap.withdrawnReason = neden
            kitap.withdrawnDate = .now
        }
    }

    struct DusSonucu: Equatable {
        var dusulen = 0
        /// Ödünçte olduğu için düşülmeyen kitaplar.
        var atlananOdunc = 0
        /// Düşülen kitaplar arasında bekleyen (kapanmamış) rezervasyonu olanlar.
        var acikRezervasyon = 0

        func mesaj(neden: String) -> String {
            var parcalar = ["\(dusulen) kitap düşüldü (\(neden))."]
            if atlananOdunc > 0 { parcalar.append("\(atlananOdunc) ödünçlü kitap atlandı; iade alınınca düşülebilir.") }
            if acikRezervasyon > 0 { parcalar.append("\(acikRezervasyon) düşülen kitapta bekleyen rezervasyon var.") }
            return parcalar.joined(separator: " ")
        }
    }

    /// Ödünçte olan kitaplar düşülmez (iade edilmemiş nüsha envanterden çıkmasın); kalanlar düşülür.
    static func dus(_ kitaplar: [CatalogBook], neden: String, context: ModelContext) -> DusSonucu {
        guard YetkiDurumu.shared.yonetici else { AppLog.write("Yönetici gerektiren toplu işlem engellendi"); return DusSonucu() }
        let kimlikler = Set(kitaplar.map(\.id))
        let oduncte = Set(((try? context.fetch(FetchDescriptor<ActiveLoan>())) ?? []).map(\.bookID).filter { kimlikler.contains($0) })
        let rezervasyonlu = Set(((try? context.fetch(FetchDescriptor<Reservation>())) ?? [])
            .filter { !$0.isClosed && kimlikler.contains($0.bookID) }.map(\.bookID))
        var sonuc = DusSonucu()
        var dusulecek: [CatalogBook] = []
        for kitap in kitaplar {
            let eskiOdunc = !(kitap.loanedTo ?? "").isEmpty
            if oduncte.contains(kitap.id) || eskiOdunc { sonuc.atlananOdunc += 1; continue }
            dusulecek.append(kitap)
            if rezervasyonlu.contains(kitap.id) { sonuc.acikRezervasyon += 1 }
        }
        for kitap in dusulecek {
            let before = kitap.book
            kitap.isWithdrawn = true
            kitap.withdrawnReason = neden
            kitap.withdrawnDate = .now
            stampManual(kitap, before: before)
        }
        sonuc.dusulen = dusulecek.count
        return sonuc
    }

    /// Düşülmüş kitabı koleksiyona döndürür; neden ve tarih temizlenir, değişiklik damgalanır.
    static func koleksiyonaGeriAl(_ kitap: CatalogBook) {
        guard YetkiDurumu.shared.yonetici, kitap.isWithdrawn else { return }
        let before = kitap.book
        kitap.isWithdrawn = false
        kitap.withdrawnReason = nil
        kitap.withdrawnDate = nil
        stampManual(kitap, before: before)
    }

    static func sil(_ kitaplar: [CatalogBook], context: ModelContext) {
        do { try silVerified(kitaplar, context: context) } catch { AppLog.write("Toplu silme başarısız; katalog korundu") }
    }

    static func silVerified(_ kitaplar: [CatalogBook], context: ModelContext) throws {
        try TrashStore.moveVerified(kitaplar, context: context, reason: "Toplu silme (Kitaplar)")
    }

    private static func stampManual(_ book: CatalogBook, before: Book) {
        book.fieldMetadata = BookFieldMetadata.stampChanges(before: before, after: book.book, source: "manual").fieldMetadata
    }
}

// MARK: - Toplu geri alma

extension Book {
    /// Kapak ve görsel verisiz kopya: toplu geri alma kaydı ve karşılaştırması hafif kalsın.
    nonisolated var hafif: Book {
        var kopya = self
        kopya.coverData = nil
        kopya.backCoverData = nil
        kopya.imprintData = nil
        return kopya
    }
}

/// Son toplu işlemin geri alınabilir kaydı. Kapak verisi taşımaz; kalıcıdır (uygulama kapanınca kaybolmaz).
nonisolated struct CatalogBulkUndoRecord: Codable, Equatable, Sendable {
    var id = UUID()
    var createdAt = Date()
    var ozet = ""
    var degisimler: [TopluGeriAlma.Degisim] = []
}

nonisolated enum CatalogBulkUndoStore {
    static var varsayilanURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("SonTopluIslem.json")
    }

    static func oku(from url: URL? = varsayilanURL) -> CatalogBulkUndoRecord? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CatalogBulkUndoRecord.self, from: data)
    }

    @discardableResult
    static func kaydet(_ kayit: CatalogBulkUndoRecord, to url: URL? = varsayilanURL) -> Bool {
        guard let url else { return false }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(kayit) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    static func temizle(at url: URL? = varsayilanURL) {
        if let url { try? FileManager.default.removeItem(at: url) }
    }
}

/// Toplu geri almanın saf kararı: hangi değişiklik geri uygulanır, hangisi bayat ya da kayıp.
nonisolated enum TopluGeriAlma {
    struct Degisim: Codable, Equatable, Sendable {
        var before: Book
        var after: Book
    }

    struct Plan: Equatable {
        /// Geri yazılacak kitaplar (mevcut kapak verileri korunmuş).
        var uygulanan: [Book] = []
        /// İşlemden sonra elle değiştirildiği için dokunulmayanlar.
        var bayat: [UUID] = []
        /// Artık katalogda olmayanlar.
        var kayip: [UUID] = []
        var atlanan: Int { bayat.count + kayip.count }
    }

    /// Kayıtlar hafif biçimle karşılaştırılır; `guncel` tam kitabı verir (kapaklar oradan taşınır).
    static func plan(_ degisimler: [Degisim], guncel: [UUID: Book]) -> Plan {
        var plan = Plan()
        for degisim in degisimler {
            guard let simdi = guncel[degisim.after.id] else { plan.kayip.append(degisim.after.id); continue }
            guard simdi.hafif == degisim.after.hafif else { plan.bayat.append(degisim.after.id); continue }
            var geri = degisim.before
            geri.coverData = simdi.coverData
            geri.backCoverData = simdi.backCoverData
            geri.imprintData = simdi.imprintData
            plan.uygulanan.append(geri)
        }
        return plan
    }

    /// İşlem öncesi ve sonrası karşılaştırılır; yalnız gerçekten değişen kitaplar kayda girer.
    static func degisimler(before: [UUID: Book], after: [Book]) -> [Degisim] {
        after.compactMap { yeni in
            guard let eski = before[yeni.id], eski.hafif != yeni.hafif else { return nil }
            return Degisim(before: eski.hafif, after: yeni.hafif)
        }
    }
}

// MARK: - Liste hesabı (önbellek + arka plan sıralama)

/// Sıralama için gereken en az alan: modeller arka plana taşınmaz, yalnız bu değerler gider.
nonisolated struct SiralamaOgesi: Sendable {
    let id: UUID
    let title: String
    let author: String
    let eklenme: Date
    let yil: String
    let yer: String?
    let cilt: Int

    init(id: UUID, title: String, author: String, eklenme: Date = .distantPast, yil: String = "", yer: String? = nil, cilt: Int = 0) {
        self.id = id; self.title = title; self.author = author
        self.eklenme = eklenme; self.yil = yil; self.yer = yer; self.cilt = cilt
    }

}

extension SiralamaOgesi {
    @MainActor
    init(_ kitap: CatalogBook) {
        let dolap = kitap.cabinet ?? "", raf = kitap.shelf ?? ""
        self.init(id: kitap.id, title: kitap.title, author: kitap.author, eklenme: kitap.addedAt,
                  yil: kitap.publicationYear ?? "", yer: dolap.isEmpty && raf.isEmpty ? nil : dolap + "/" + raf,
                  cilt: kitap.volume ?? 0)
    }
}

nonisolated enum KitapSiralayici {
    /// Tek sıralama kaynağı: `KitapFiltresi.uygula` ve arka plan hesabı bunu kullanır.
    static func sirala(_ ogeler: [SiralamaOgesi], siralama: KitapSiralama, seriSecili: Bool) -> [UUID] {
        let sirali: [SiralamaOgesi]
        if seriSecili {
            sirali = ogeler.sorted { ($0.cilt, $0.title) < ($1.cilt, $1.title) }
        } else {
            switch siralama {
            case .ad:
                sirali = ogeler.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            case .yazar:
                sirali = ogeler.sorted { $0.author.localizedStandardCompare($1.author) == .orderedAscending }
            case .yeni:
                sirali = ogeler.sorted { $0.eklenme > $1.eklenme }
            case .yil:
                sirali = ogeler.sorted { $0.yil > $1.yil }
            case .yer:
                sirali = ogeler.sorted {
                    switch ($0.yer, $1.yer) {
                    case let (a?, b?) where a != b: return a.localizedStandardCompare(b) == .orderedAscending
                    case (.some, nil): return true
                    case (nil, .some): return false
                    default: return $0.title.localizedStandardCompare($1.title) == .orderedAscending
                    }
                }
            }
        }
        return sirali.map(\.id)
    }
}

/// Listenin hesaplanmış hali. Girdi anahtarı değişmedikçe yeniden hesaplanmaz.
struct ListeHesabi {
    var anahtar: HesapAnahtari
    var kitaplar: [CatalogBook]
    var stoklar: [UUID: LibraryStock]
    var gecikmis: Set<UUID>

    /// Aynı anahtarla zaten hesaplanmışsa `false`.
    static func yenidenGerekli(mevcut: ListeHesabi?, anahtar: HesapAnahtari) -> Bool {
        mevcut?.anahtar != anahtar
    }
}

/// Liste hesabını tetikleyen girdiler. Sayılar hızlı değişim göstergesi, parmak izi ise ad/kategori/ödünç
/// gibi sayıyı değiştirmeyen düzenlemeleri yakalar.
struct HesapAnahtari: Equatable {
    var filtre: KitapFiltresi
    var siralama: String
    var kitapSayisi: Int
    var loanSayisi: Int
    var copySayisi: Int
    var reservationSayisi: Int
    var parmakIzi: Int

    static func kur(filtre: KitapFiltresi, siralama: String, kitaplar: [CatalogBook], loans: [ActiveLoan],
                    copies: [BookCopy], reservations: [Reservation]) -> HesapAnahtari {
        var hasher = Hasher()
        for kitap in kitaplar {
            hasher.combine(kitap.id); hasher.combine(kitap.title); hasher.combine(kitap.author)
            hasher.combine(kitap.category); hasher.combine(kitap.cabinet); hasher.combine(kitap.shelf)
            hasher.combine(kitap.readingStatus); hasher.combine(kitap.isWithdrawn); hasher.combine(kitap.quantity)
            hasher.combine(kitap.loanedTo); hasher.combine(kitap.tags); hasher.combine(kitap.readingLevel)
            hasher.combine(kitap.series); hasher.combine(kitap.volume); hasher.combine(kitap.publicationYear)
        }
        for loan in loans { hasher.combine(loan.id); hasher.combine(loan.bookID); hasher.combine(loan.dueDate) }
        for copy in copies { hasher.combine(copy.id); hasher.combine(copy.bookID); hasher.combine(copy.status) }
        for rezervasyon in reservations {
            hasher.combine(rezervasyon.id); hasher.combine(rezervasyon.bookID)
            hasher.combine(rezervasyon.isClosed); hasher.combine(rezervasyon.notifiedAt)
        }
        return HesapAnahtari(filtre: filtre, siralama: siralama, kitapSayisi: kitaplar.count, loanSayisi: loans.count,
                             copySayisi: copies.count, reservationSayisi: reservations.count, parmakIzi: hasher.finalize())
    }
}

// MARK: - Öneri çipleri

/// Düzenleyicide Kategori / Yayınevi / Seri alanları için katalogda en sık geçen değerler.
enum KategoriOnerileri {
    enum Alan { case kategori, yayinevi, seri }

    static func enSik(_ alan: Alan = .kategori, context: ModelContext, limit: Int = 8) -> [String] {
        let kitaplar = (try? context.fetch(FetchDescriptor<CatalogBook>())) ?? []
        return enSik(kitaplar.filter { !$0.isDeleted }.map { kitap -> String? in
            switch alan {
            case .kategori: kitap.category
            case .yayinevi: kitap.publisher
            case .seri: kitap.series
            }
        }, limit: limit)
    }

    /// Üç alanın önerileri tek katalog okumasıyla.
    static func hepsi(context: ModelContext, limit: Int = 8) -> EditorOnerileri {
        let kitaplar = ((try? context.fetch(FetchDescriptor<CatalogBook>())) ?? []).filter { !$0.isDeleted }
        return EditorOnerileri(kategori: enSik(kitaplar.map(\.category), limit: limit),
                               yayinevi: enSik(kitaplar.map(\.publisher), limit: limit),
                               seri: enSik(kitaplar.map(\.series), limit: limit))
    }

    /// Saf sayım: boşlar atılır, büyük/küçük harf farkı tek sayılır, sayı eşitse alfabetik.
    nonisolated static func enSik(_ degerler: [String?], limit: Int = 8) -> [String] {
        var sayim: [String: (ad: String, adet: Int)] = [:]
        for ham in degerler {
            let temiz = ham?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !temiz.isEmpty else { continue }
            let anahtar = temiz.lowercased(with: Locale(identifier: "tr_TR"))
            let onceki = sayim[anahtar]
            sayim[anahtar] = (ad: onceki?.ad ?? temiz, adet: (onceki?.adet ?? 0) + 1)
        }
        return sayim.values
            .sorted { $0.adet != $1.adet ? $0.adet > $1.adet : $0.ad.localizedStandardCompare($1.ad) == .orderedAscending }
            .prefix(limit).map(\.ad)
    }
}

// MARK: - Kategori dağılımı

enum KategoriDagilimi {
    struct Satir: Equatable {
        let ad: String
        let baslik: Int
        let nusha: Int
    }

    /// Düşülenler hariç kategori → başlık ve nüsha sayısı; boş kategori "Kategorisiz" altında toplanır.
    static func hesapla(_ kitaplar: [CatalogBook]) -> [Satir] {
        var sayilar: [String: (baslik: Int, nusha: Int)] = [:]
        for kitap in kitaplar where !kitap.isWithdrawn {
            let onceki = sayilar[kitap.kategoriAdi] ?? (0, 0)
            sayilar[kitap.kategoriAdi] = (onceki.baslik + 1, onceki.nusha + max(1, kitap.quantity ?? 1))
        }
        return sayilar.map { Satir(ad: $0.key, baslik: $0.value.baslik, nusha: $0.value.nusha) }
            .sorted { $0.nusha != $1.nusha ? $0.nusha > $1.nusha : $0.ad < $1.ad }
    }
}

// MARK: - Süzgeç rotası

/// Eksik Alan Panosu gibi ekranlardan Kitaplar sekmesine hazır süzgeç taşır; sekme açılınca tek sefer tüketilir.
@Observable
final class KitapFiltreRotasi {
    static let shared = KitapFiltreRotasi()
    var bekleyen: KitapFiltresi?
}
