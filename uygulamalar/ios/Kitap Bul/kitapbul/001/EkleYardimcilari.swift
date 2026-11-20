import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Tekli barkod taraması

/// Tekli barkod taramasında kabul edilen kod: geçerli bir kitap ISBN'i ya da katalogda kayıtlı olan
/// uygulama barkodu (200…). ISBN denetimi saftır; 200… öneki mağaza fiyat etiketlerinde de kullanıldığı
/// için (GS1 200–299) bu kod ancak `kayitliIcKod` onaylarsa kabul edilir. Başka bir kod tarayıcıyı
/// kapatmaz; tarayıcı açık kalır ve kullanıcıya hangi barkodu okutacağı söylenir.
enum TekliBarkodDenetimi {
    static func kabulEdilir(_ kod: String, kayitliIcKod: (String) -> Bool = { _ in false }) -> Bool {
        if BookEditorValidation.normalizedISBN(kod) != nil { return true }
        let normal = ISBNFormatter.normalize(kod)
        return InternalBarcode.isInternal(normal) && kayitliIcKod(normal)
    }
}

// MARK: - Katalogdaki kitap okutulunca

/// Tekli taramada okutulan kitap zaten katalogdaysa adet sormadan artmaz. Kullanıcı "Nüsha ekle (+1)",
/// "Kitabı aç" ya da "Vazgeç" seçer. Seri tarama bu soruyu sormaz (orada her okutma bilinçli bir nüshadır).
struct KatalogdakiKitapOnayi: Identifiable, Equatable {
    let kitapID: UUID
    let isbn: String
    let kitapAdi: String
    /// Tek biçimli konum ("Dolap 3 · Raf 2"); boşsa "Yer atanmamış".
    let konum: String
    let adet: Int
    /// Koleksiyondan düşülmüş kayda nüsha eklenmez; kitap açılabilir ya da yeni kayıt açılır.
    let dusulmus: Bool
    /// Barkodla birlikte çekilen arka kapak; düşülmüş kitap yeni kayıt olarak eklenirse forma geçer.
    let arkaKapak: Data?

    var id: UUID { kitapID }

    init(kitap: CatalogBook, isbn: String, arkaKapak: Data? = nil) {
        kitapID = kitap.id
        self.isbn = isbn
        kitapAdi = kitap.title.trimmingCharacters(in: .whitespacesAndNewlines)
        konum = kitap.konumMetni ?? CatalogBook.yerAtanmamis
        adet = max(1, kitap.quantity ?? 1)
        dusulmus = kitap.isWithdrawn
        self.arkaKapak = arkaKapak
    }

    /// Okutulan ISBN'in katalogdaki kaydı: önce etkin kayıt. Aynı ISBN'li düşülmüş kayıt sıralamada önde
    /// olsa da etkin kayda nüsha eklenebilmeli; yalnız düşülmüş kayıt varsa o döner.
    static func eslesenKayit(isbn: String, in kitaplar: [CatalogBook]) -> CatalogBook? {
        let eslesenler = kitaplar.filter { ISBNFormatter.normalize($0.isbn ?? "") == isbn }
        return eslesenler.first { !$0.isWithdrawn } ?? eslesenler.first
    }

    var baslik: String { "“\(kitapAdi.isEmpty ? isbn : kitapAdi)” zaten katalogda" }

    var mesaj: String {
        dusulmus
            ? "Bu kayıt koleksiyondan düşülmüş; nüsha eklenmez. Kitabı yeniden edindiyseniz yeni kayıt olarak ekleyebilirsiniz."
            : "\(konum)\nKatalogda \(adet) nüsha var."
    }

    var nushaEklenebilir: Bool { !dusulmus }

    /// Yalnız düşülmüş kayıt varken eski davranış korunur: künye aranır, yeni kayıt formu açılır.
    var yeniKayitAcilabilir: Bool { dusulmus }
}

// MARK: - Kayıttan sonraki şerit

/// Ekle'de kayıttan sonra altta görünen şerit: "“X” eklendi · Geri al · Sonrakini okut".
/// Geri alma yalnız bu kayda bağlıdır (`islemKimligi`); başka bir kayıt son işlem olursa, ekleme oturumu
/// değişirse ya da Ekle sayfasından çıkılırsa şerit kalkar.
struct SonEklemeSeridi: Equatable {
    enum Tur: Equatable {
        case yeniKayit
        case nusha(Int)
        case geriAlindi
    }

    let kitapAdi: String
    var tur: Tur
    let islemKimligi: UUID?
    /// Kaydın yazıldığı ekleme oturumu: geri alma o oturumun günlüğünü düzeltir, başka oturumunkini değil.
    var oturumKimligi: UUID? = nil
    /// Yeni kaydın eklendiği andaki hâli: sonradan düzenlendiyse geri alma (kalıcı silme) önce onay ister.
    var kayitAni: Book? = nil

    /// Geri alma bu işlemin makbuzu hâlâ duruyorsa yapılır. Aynı ekleme Son Eklemeler'deki
    /// "Eklemeleri Geri Al" ile geri alındıysa makbuz silinmiştir; adet ikinci kez düşmez.
    func makbuzDuruyor(hedef: UUID, context: ModelContext) -> Bool {
        guard let islemKimligi,
              let makbuz = try? CatalogSaveEngine.receipt(for: islemKimligi, context: context) else { return false }
        return makbuz.bookID == hedef
    }

    /// Yeni kayıt eklendikten sonra değiştiyse (kapak, raf, not…) `true`: geri alma kaydı kalıcı siler.
    func sonradanDegisti(_ guncel: Book?) -> Bool {
        guard tur == .yeniKayit, let kayitAni, let guncel else { return false }
        return guncel != kayitAni
    }

    var metin: String {
        let ad = kitapAdi.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Kitap" : kitapAdi
        switch tur {
        case .yeniKayit: return "“\(ad)” eklendi"
        case .nusha(let adet): return adet == 1 ? "“\(ad)” için nüsha eklendi (+1)" : "“\(ad)” için \(adet) nüsha eklendi"
        case .geriAlindi: return "“\(ad)” eklemesi geri alındı"
        }
    }

    var geriAlinabilir: Bool { tur != .geriAlindi }
}

// MARK: - Son Eklemeler ve onay kuyruğu

enum EkleOzeti {
    /// Oturum özeti; sıfır olan parçalar yazılmaz, hepsi sıfırsa `nil`.
    nonisolated static func oturum(bekleyen: Int, yeni: Int, nusha: Int) -> String? {
        let parcalar = [
            bekleyen > 0 ? "\(bekleyen) kayıt kontrol bekliyor" : nil,
            yeni > 0 ? "\(yeni) yeni kayıt" : nil,
            nusha > 0 ? "\(nusha) nüsha eklendi" : nil
        ].compactMap { $0 }
        return parcalar.isEmpty ? nil : parcalar.joined(separator: " · ")
    }

    /// Onay kuyruğunda "Kontrol gerekli" bölümüne düşen taslak: adı yok ya da şüpheli alanı var.
    static func kontrolGerekli(_ taslak: BookDraft) -> Bool {
        taslak.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !taslak.lowConfidenceFields.isEmpty
    }

    /// "Adı Olanları Kaydet" düğmesindeki sayı; kayıt mantığıyla aynı kural (adı boş olan kuyrukta kalır).
    static func kaydedilebilirSayisi(_ taslaklar: [BookDraft]) -> Int {
        taslaklar.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }
}

extension ScanSession {
    nonisolated var ozetMetni: String? {
        EkleOzeti.oturum(bekleyen: pendingBooks.count, yeni: insertedIDs.count, nusha: mergedCopies.values.reduce(0, +))
    }
}

// MARK: - Seri tarama: art arda gelen aynı barkod

/// Kadrajda titreyen ya da elde bir an daha tutulan barkodun iki kez sayılmasını önler. Pencere içinde
/// yinelenen kod yutulur (`true`); pencere dolunca aynı kod yeni bir nüsha olarak geçer. Pencere,
/// yutulan okutmalarla uzamaz: ölçü son KABUL edilen okutmadır.
nonisolated struct TekrarBastirici {
    var pencere: TimeInterval = 1.5
    private var sonKabul: [String: Date] = [:]

    init(pencere: TimeInterval = 1.5) { self.pencere = pencere }

    /// `true`: bu okutma yinelemedir, yutulmalı.
    mutating func yutulsunMu(_ kod: String, simdi: Date = Date()) -> Bool {
        if let son = sonKabul[kod], simdi.timeIntervalSince(son) >= 0, simdi.timeIntervalSince(son) < pencere {
            return true
        }
        sonKabul[kod] = simdi
        if sonKabul.count > 256 {
            sonKabul = sonKabul.filter { simdi.timeIntervalSince($0.value) < pencere }
        }
        return false
    }
}

// MARK: - Dosya içe aktarma özeti

/// "Dosyalar"dan seçilen PDF ve görsellerin sonucu: hangi dosya okundu, hangisi neden okunamadı.
/// Başarısızlık ilerleme çubuğunda kaybolmaz; kullanıcıya dosya adıyla söylenir.
nonisolated struct DosyaIceAktarmaOzeti: Equatable {
    struct Hata: Equatable {
        var ad: String
        var neden: String
    }

    private(set) var okunan = 0
    private(set) var hatalar: [Hata] = []

    var okunamayan: Int { hatalar.count }
    var toplam: Int { okunan + okunamayan }

    mutating func okundu() { okunan += 1 }
    mutating func hata(ad: String, neden: String) { hatalar.append(Hata(ad: ad, neden: neden)) }

    /// Mesajda en çok bu kadar dosya adı sayılır; kalanı "ve N dosya daha" olur.
    static let gosterilenAd = 5

    var mesaj: String? {
        guard toplam > 0 else { return nil }
        if hatalar.isEmpty { return nil }
        let liste = hatalar.prefix(Self.gosterilenAd).map { "\($0.ad) (\($0.neden))" }.joined(separator: ", ")
        let fazla = hatalar.count > Self.gosterilenAd ? " ve \(hatalar.count - Self.gosterilenAd) dosya daha" : ""
        return "\(okunan) dosya okundu, \(okunamayan) okunamadı: \(liste)\(fazla)"
    }
}

/// Tek bir dosyanın neden okunamadığı; `neden` kullanıcıya dosya adının yanında gösterilir.
nonisolated struct DosyaOkumaHatasi: LocalizedError, Equatable {
    var neden: String
    var errorDescription: String? { neden }
}

extension DosyaIceAktarmaOzeti {
    /// Hatayı mesajdaki kısa nedene çevirir ("bozuk PDF", "iCloud'dan indirilemedi"…).
    static func neden(_ error: Error) -> String {
        if let hata = error as? DosyaOkumaHatasi { return hata.neden }
        if error is CancellationError { return "iptal edildi" }
        return "okunamadı"
    }
}

/// "Dosyalar"dan seçilen dosyaları sırayla işler ve sonucu özetler. Dosya başına hata toplanır;
/// biri okunamasa da diğerleri sürer ve sessizce yutulmaz.
enum DosyaIceAktarma {
    static func calistir(urls: [URL], ilerleme: (Int) -> Void = { _ in },
                         isle: (URL) async throws -> Void) async -> DosyaIceAktarmaOzeti {
        var ozet = DosyaIceAktarmaOzeti()
        for (sira, url) in urls.enumerated() {
            do {
                try await isle(url)
                ozet.okundu()
            } catch is CancellationError {
                ozet.hata(ad: url.lastPathComponent, neden: "iptal edildi")
                break
            } catch {
                ozet.hata(ad: url.lastPathComponent, neden: DosyaIceAktarmaOzeti.neden(error))
            }
            ilerleme(sira + 1)
        }
        return ozet
    }
}

/// Dosyayı `NSFileCoordinator` ile okur: iCloud'da henüz inmemiş dosya önce indirilir, sonra okunur.
/// `Data(contentsOf:)` indirilmemiş yer tutucuyu okuyamadığı için "içe aktarma çalışmıyor" izlenimi veriyordu.
nonisolated enum KoordineliDosyaOkuma {
    static func oku(_ url: URL) async throws -> Data {
        try await withCheckedThrowingContinuation { devam in
            DispatchQueue.global(qos: .userInitiated).async {
                devam.resume(with: Result { try okuEszamanli(url) })
            }
        }
    }

    static func okuEszamanli(_ url: URL) throws -> Data {
        let anahtarlar: Set<URLResourceKey> = [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
        let degerler = try? url.resourceValues(forKeys: anahtarlar)
        let bulutta = degerler?.isUbiquitousItem == true
        if bulutta, degerler?.ubiquitousItemDownloadingStatus != .current {
            // Başlatılamazsa koordineli okuma yine de indirmeyi dener.
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        }
        var koordinasyonHatasi: NSError?
        var sonuc: Result<Data, Error> = .failure(DosyaOkumaHatasi(neden: "okunamadı"))
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &koordinasyonHatasi) { okunacak in
            sonuc = Result { try Data(contentsOf: okunacak) }
        }
        if koordinasyonHatasi != nil, case .failure = sonuc {
            throw DosyaOkumaHatasi(neden: bulutta ? "iCloud'dan indirilemedi" : "okunamadı")
        }
        do { return try sonuc.get() }
        catch { throw DosyaOkumaHatasi(neden: bulutta ? "iCloud'dan indirilemedi" : "okunamadı") }
    }
}

// MARK: - Depo modunda kayıtlı kitap okutulunca

/// Depo taramasında katalogda zaten olan bir kitap okutulduğunda ne yapılacağı. Seçim `SonKonum` gibi
/// hatırlanır; varsayılan eski davranıştır (nüsha eklenir, kitabın yeri korunur).
enum DepoEslesmeKarari: String, CaseIterable, Identifiable {
    case nusha, konumTasi, sor

    static let anahtar = "depoEslesmeKarari"
    var id: String { rawValue }

    var baslik: String {
        switch self {
        case .nusha: "Nüsha ekle"
        case .konumTasi: "Konumunu buraya taşı"
        case .sor: "Her seferinde sor"
        }
    }

    var aciklama: String {
        switch self {
        case .nusha: "Okutulan kitabın adedi 1 artar; kitabın kayıtlı yeri değişmez."
        case .konumTasi: "Kitabın dolap ve rafı okutulduğu yere taşınır; adet artmaz. “Geri Al” eski yere döndürür."
        case .sor: "Kayıtlı kitap okutulunca nüsha mı eklensin, konum mu taşınsın diye sorulur."
        }
    }

    static var mevcut: DepoEslesmeKarari {
        get { DepoEslesmeKarari(rawValue: UserDefaults.standard.string(forKey: anahtar) ?? "") ?? .nusha }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: anahtar) }
    }
}

/// Depo taramasının hızlı mükerrer dizini: düşülmüş kayıtlar dışlanır, aynı ISBN'li birden çok etkin kayıtta
/// ilk etkin kayıt kazanır (düşülmüş kayıt sıralamada önde olsa da nüsha ona eklenmez).
enum DepoIndeksi {
    static func kur(_ kitaplar: [CatalogBook]) -> [String: CatalogBook] {
        var indeks: [String: CatalogBook] = [:]
        for kitap in kitaplar where !kitap.isWithdrawn && !kitap.isDeleted {
            let isbn = ISBNFormatter.normalize(kitap.isbn ?? "")
            if !isbn.isEmpty, indeks[isbn] == nil { indeks[isbn] = kitap }
        }
        return indeks
    }
}

/// "Konum farklı: A-3 → B-1" etiketi: kayıtlı kitap başka yerde okutulduğunda onay kuyruğu satırında görünür.
nonisolated enum KonumFarki {
    static func metin(eskiDolap: String?, eskiRaf: String?, yeniDolap: String?, yeniRaf: String?) -> String? {
        func parca(_ dolap: String?, _ raf: String?) -> String {
            [dolap, raf].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: "-")
        }
        let eski = parca(eskiDolap, eskiRaf), yeni = parca(yeniDolap, yeniRaf)
        guard !eski.isEmpty, !yeni.isEmpty, eski != yeni else { return nil }
        return "Konum farklı: \(eski) → \(yeni)"
    }
}

/// Depo kipinde "Her seferinde sor" seçiliyken tarayıcı kapağında gösterilen soru.
struct DepoSorusu: Identifiable, Equatable {
    let kitapID: UUID
    let isbn: String
    let kitapAdi: String
    let eskiKonum: String
    let yeniKonum: String
    var id: UUID { kitapID }
}

// MARK: - Arşiv dışa/içe aktarma yardımcıları

/// Diskteki hazır arşivi `fileExporter`a verir; içerik belleğe okunmaz, sistem hedefe dosyadan kopyalar.
struct ArchiveFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.zip] }

    let url: URL?

    init(url: URL?) { self.url = url }

    init(configuration: ReadConfiguration) throws { url = nil }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let url else { return FileWrapper(regularFileWithContents: Data()) }
        return try FileWrapper(url: url, options: [])
    }
}

/// Eski JSON yedeğinin arşiv önizlemesi: onaylanırsa işlem öncesi tam yedek alınır, sonra geri yüklenir.
struct JSONYedekGeriYuklemeOnizlemesi: ViewModifier {
    @Binding var onizleme: ArchiveImportCoordinator.Preparation?
    let veri: Data
    let context: ModelContext

    func body(content: Content) -> some View {
        content.sheet(item: $onizleme) { hazirlik in
            ArchiveImportReviewView(preparation: hazirlik, onSettingsChange: { secili in
                try await ArchiveImportCoordinator.prepareAsync(jsonBackup: veri, context: context, restoreSettings: secili)
            }, onApply: { try await ArchiveImportCoordinator.applyAsync($0, context: context) })
        }
    }
}

/// Seri taramanın kalıcı ayarları.
enum SeriTaramaAyari {
    /// Açıkken okutma anında ISBN + konum kaydedilir, künye arka planda dolar; kapalıyken (varsayılan)
    /// künye önce alınır ve taslak onay kuyruğuna düşer.
    static let cevrimdisiOnce = "seriCevrimdisiOnce"
}

// MARK: - Künye kaynağı hata metinleri

/// Künye kaynaklarından gelen hataları kullanıcıya anlaşılır cümleye çevirir ("kitap yok" ile "ulaşılamadı" ayrı söylenir).
nonisolated enum KunyeHataMetni {
    static func metin(_ error: Error, kaynak: String) -> String {
        if let hata = error as? KitapyurduHata, case .sunucu(let kod) = hata {
            switch kod {
            case 429: return "\(kaynak) çok sık istek aldığını bildirdi. Biraz bekleyip yeniden deneyin."
            case 502, 503, 504: return "\(kaynak) şu an yanıt vermiyor (sunucu \(kod)). Biraz sonra yeniden deneyin."
            default: return "\(kaynak) isteği reddetti (sunucu \(kod))."
            }
        }
        if let url = error as? URLError {
            switch url.code {
            case .resourceUnavailable: return "\(kaynak) bot doğrulaması istiyor; uygulamadan erişilemiyor. Bilgileri elle girin."
            case .notConnectedToInternet, .networkConnectionLost: return "İnternet bağlantısı yok. Bağlantıyı denetleyip yeniden deneyin."
            case .timedOut: return "\(kaynak) zamanında yanıt vermedi. Yeniden deneyin."
            default: break
            }
        }
        if error is CancellationError { return "Arama iptal edildi." }
        return "\(kaynak) kaynağına erişilemedi: \(error.localizedDescription)"
    }
}

// MARK: - Şüpheli alanları ISBN'den onarma

/// Onay kuyruğunda "Şüphelileri yeniden ara": ISBN'i olan ve şüpheli alanı bulunan taslaklar kaynaklardan yeniden sorgulanır.
/// Şüpheli işaretli alanlar kaynaktaki değerle değiştirilir, boş alanlar doldurulur; kullanıcının onayladığı
/// (şüpheli işaretsiz) dolu alanlara dokunulmaz.
enum SupheliAlanOnarimi {
    static func aranabilir(_ taslaklar: [BookDraft]) -> [BookDraft] {
        taslaklar.filter { EkleOzeti.kontrolGerekli($0) && !ISBNFormatter.normalize($0.isbn).isEmpty }
    }

    /// Kaynak bilgisini taslağa işler; en az bir alan düzeldiyse `true`.
    @discardableResult
    static func uygula(_ meta: AmazonBookMetadata, to taslak: inout BookDraft) -> Bool {
        let once = taslak
        let supheliler = taslak.lowConfidenceFields
        var onarilan = Set<String>()
        func degistir(_ alan: String, _ yeni: String, _ hedef: inout String) {
            guard supheliler.contains(alan), !yeni.isEmpty else { return }
            hedef = yeni
            onarilan.insert(alan)
        }
        degistir("title", meta.title, &taslak.title)
        degistir("author", meta.author, &taslak.author)
        degistir("publisher", meta.publisher, &taslak.publisher)
        degistir("publicationYear", meta.publicationYear, &taslak.publicationYear)
        degistir("edition", meta.edition, &taslak.edition)
        degistir("pageCount", meta.pageCount, &taslak.pageCount)
        // Boş alanlar doldurulur; dolu alanlar korunur
        AmazonBookScraper.apply(metadata: meta, to: &taslak, overwrite: false)
        // `apply` dolu her alanın şüphesini kaldırır; kaynağın düzeltmediği şüpheli alanlar işaretli kalır.
        let dolduruldu: [(String, String, String)] = [
            ("title", once.title, taslak.title), ("author", once.author, taslak.author),
            ("publisher", once.publisher, taslak.publisher), ("publicationYear", once.publicationYear, taslak.publicationYear),
            ("edition", once.edition, taslak.edition), ("pageCount", once.pageCount, taslak.pageCount)
        ]
        for (alan, eski, yeni) in dolduruldu where eski.isEmpty && !yeni.isEmpty { onarilan.insert(alan) }
        taslak.lowConfidenceFields = supheliler.subtracting(onarilan)
        return taslak.title != once.title || taslak.author != once.author || taslak.publisher != once.publisher
            || taslak.lowConfidenceFields != once.lowConfidenceFields || taslak.coverData != once.coverData
    }
}
