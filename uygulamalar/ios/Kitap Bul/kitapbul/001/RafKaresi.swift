import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@preconcurrency import Vision

// MARK: - Raf karesi: tek fotoğrafta birçok kitap

/// Yan yana dizilmiş kitapların tek fotoğrafından bulunan bir kitap (ön ya da arka yüz).
nonisolated struct AlgilananKitap: Codable, Sendable, Equatable {
    var isbn: String?
    var title: String?
    var author: String?
    var publisher: String?
    /// "front" (kapak görünüyor) | "back" (arka yüz: barkod/ISBN görünüyor)
    var side: String?
    /// Modelin bu kayda güveni (0–1).
    var confidence: Double?
    /// Kitabın karedeki yeri: [ymin, xmin, ymax, xmax], 0–1000 ölçeğinde (Gemini box_2d).
    var box: [Double]?
    /// Aynı karede bulunan nüsha sayısı (aynı kitap iki kez çekilmişse 2). Birleştirmede dolar.
    var copies: Int?
    /// ISBN barkoddan mı geldi? (Barkod yanılmaz; metinden okunan rakam komşu kitabın olabilir.)
    var barkodlu = false
    /// Birden çok kare seçildiğinde hangi fotoğraftan geldiği (kapak kesiti için).
    var photoIndex: Int?

    enum CodingKeys: String, CodingKey {
        case isbn, title, author, publisher, side, confidence, copies, barkodlu, photoIndex
        case box = "box_2d"
    }

    init(
        isbn: String? = nil, title: String? = nil, author: String? = nil,
        publisher: String? = nil, side: String? = nil, confidence: Double? = nil,
        box: [Double]? = nil, copies: Int? = nil, barkodlu: Bool = false, photoIndex: Int? = nil
    ) {
        self.isbn = isbn
        self.title = title
        self.author = author
        self.publisher = publisher
        self.side = side
        self.confidence = confidence
        self.box = box
        self.copies = copies
        self.barkodlu = barkodlu
        self.photoIndex = photoIndex
    }

    /// Gemini bazen ISBN'i sayı, güveni metin döndürür; tek alan yüzünden tüm kare kaybolmasın.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isbn = GevsekDeger.metin(c, .isbn)
        title = GevsekDeger.metin(c, .title)
        author = GevsekDeger.metin(c, .author)
        publisher = GevsekDeger.metin(c, .publisher)
        side = GevsekDeger.metin(c, .side)
        confidence = GevsekDeger.ondalik(c, .confidence)
        box = GevsekDeger.ondalikListe(c, .box)
        copies = GevsekDeger.tamsayi(c, .copies)
        // Uygulama içi alanlar: model çıktısından ASLA okunmaz (barkod doğrulaması taklit edilemez)
        barkodlu = false
        photoIndex = nil
    }

    var temizISBN: String { ISBNFormatter.repair(isbn ?? "") }
    var temizAd: String { (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
    var temizYazar: String { (author ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
    var onYuz: Bool { (side ?? "").lowercased().hasPrefix("f") }
    /// 1–99 arasına kırpılır: modelin saçma büyük değeri toplamda taşma yapmasın.
    var nusha: Int { min(max(1, copies ?? 1), AlgilananKitap.enFazlaNusha) }
    static let enFazlaNusha = 99

    /// Kutunun 0–1 ölçeğinde, sol üst kökenli dikdörtgeni (geçersiz kutu nil).
    var kutu: CGRect? {
        guard let box, box.count == 4, box.allSatisfy(\.isFinite) else { return nil }
        let ymin = min(max(box[0] / 1000, 0), 1), xmin = min(max(box[1] / 1000, 0), 1)
        let ymax = min(max(box[2] / 1000, 0), 1), xmax = min(max(box[3] / 1000, 0), 1)
        guard xmax > xmin, ymax > ymin else { return nil }
        return CGRect(x: xmin, y: ymin, width: xmax - xmin, height: ymax - ymin)
    }
}

/// Vision'ın karede bulduğu tek barkod: ISBN ve 0–1 ölçeğinde (sol üst kökenli) merkezi.
/// Konumu bilinmeyen (eski API) barkodlarda merkez (-1, -1) verilir.
nonisolated struct BarkodBulgusu: Sendable, Equatable {
    var isbn: String
    var merkez: CGPoint

    var konumlu: Bool { merkez.x >= 0 && merkez.y >= 0 }
}

/// Tek karenin algılama sonucu: kitaplar ve (varsa) Gemini hatası — kullanıcıya
/// "yalnız barkodlar okundu" denebilsin.
nonisolated struct AlgilamaSonucu: Sendable {
    var kitaplar: [AlgilananKitap]
    var geminiHatasi: String?
}

/// "Raf Karesi" akışı: masaya/rafa dizilmiş 5–15 kitabın tek fotoğrafından her kitabı ayrı bulur.
///
/// İki kaynak birlikte çalışır:
/// - Vision, karedeki TÜM EAN-13 barkodlarını ve yerlerini okur (çevrimdışı ve kesin).
/// - Gemini, karedeki her kitabı ayrı kayıt olarak çıkarır: arka yüzde ISBN metni, ön yüzde
///   ad/yazar/yayınevi ve kitabın kutusu (box_2d).
/// Barkodlar kutu içine düştükleri Gemini kaydına bağlanır (yanlış kitaba ISBN gitmez);
/// eşleşmeyen barkodlar ISBN'li kayıt olur. Barkoddan gelen ISBN her zaman baskındır.
enum CokluKitapAlgilayici {
    nonisolated struct Yanit: Codable, Sendable {
        var books: [AlgilananKitap]
    }

    /// Kutu içine düşmeyen barkodun kutu KENARINA en fazla uzaklığı (0–1 ölçeği). Gemini kutuları
    /// birkaç yüzde kayabilir; barkod kitabın köşesindedir, kutu merkezine uzaklık ölçüt olmaz.
    nonisolated static let kenarPayi = 0.06
    /// Aynı barkodun iki kez algılanması ile iki ayrı nüshayı ayıran en küçük merkez uzaklığı.
    nonisolated static let ayniBarkodUzakligi = 0.02
    /// Barkodsuz (metinden okunan) ISBN'in onaysız kaydedilebilmesi için gereken Gemini güveni.
    nonisolated static let guvenEsigi = 0.7

    static let sistemIstemi = """
    Sen bir okul kütüphanesi kataloglama asistanısın. Sana yan yana dizilmiş BİRDEN ÇOK kitabın tek \
    fotoğrafı verilecek. Kitaplar ön yüzleri (kapak) ya da arka yüzleri (barkod, ISBN, tanıtım metni) \
    görünecek şekilde durabilir; fotoğraf yan ya da ters çevrilmiş olabilir. Görüntüdeki HER kitap için \
    ayrı bir kayıt çıkar ve YALNIZCA JSON döndür:
    {"books": [{"isbn": "", "title": "", "author": "", "publisher": "", "side": "back", \
    "confidence": 0.9, "box_2d": [ymin, xmin, ymax, xmax]}]}
    Kurallar:
    - Her fiziksel kitap tam olarak bir kayıt; aynı kitaptan iki nüsha varsa iki kayıt. Soldan sağa, \
    üstten alta sırala. Kitap yoksa {"books": []}.
    - box_2d: kitabın fotoğraftaki sınır kutusu, 0–1000 ölçeğinde [ymin, xmin, ymax, xmax]. Her kayıtta \
    zorunlu; kutu kitabın tamamını (barkod dahil) kapsasın.
    - isbn: barkodun altındaki ya da "ISBN" ibaresinin yanındaki 13 rakam (978/979 ile başlar). \
    Rakamları tek tek dikkatle oku; tire ve boşlukları at. Okunamıyorsa boş bırak. TAHMİN ETME, \
    başka bir kitabın numarasını kopyalama. Metin olarak (tırnak içinde) yaz.
    - title/author/publisher: ön yüzde kapaktan oku. Arka yüzde tanıtım metninden anlaşılıyorsa \
    (yazar biyografisi, "X - Bütün Eserleri" gibi seri ibaresi, yayınevi logosu/adresi) doldur; \
    emin değilsen boş bırak. Yazar alanına çevirmen/editör yazma. Cilt numarasını ada ekle ("Sefiller 2. Cilt").
    - side: kapak görünüyorsa "front", arka yüz (barkod/tanıtım metni) görünüyorsa "back".
    - confidence: kaydın doğruluğuna güvenin (0–1); ISBN rakamlarından emin değilsen 0.5'in altında ver.
    - Türkçe karakterleri (ş, ğ, ı, İ, ö, ü, ç) doğru yaz; tümü büyük harfli adları Başlık Biçimine çevir.
    """

    /// Geçerli ISBN-13 ve kitap ön eki (978/979): dergi/ürün barkodları kitap sayılmaz.
    nonisolated static func kitapISBN(_ value: String) -> String? {
        let isbn = ISBNFormatter.repair(value)
        guard ISBNFormatter.isValidISBN13(isbn), isbn.hasPrefix("978") || isbn.hasPrefix("979") else { return nil }
        return isbn
    }

    // MARK: Vision

    /// Vision ile karedeki tüm EAN-13 barkodları (geçerli ISBN-13'ler) ve merkezleri.
    /// Barkodlar küçük olduğu için görüntü 4200 px'te çözülür. Yan çekilmiş karede hiç barkod
    /// çıkmazsa 90° döndürülmüş yönle yeniden denenir ve merkezler orijinal kareye çevrilir.
    /// Çağıranın görev ağacında, ana aktörün dışında koşar; iptal edilirse boş döner.
    @concurrent static func barkodlar(_ data: Data) async -> [BarkodBulgusu] {
        guard !Task.isCancelled, let image = decodeImage(from: data, maxPixel: 4200) else { return [] }
        let duz = tara(image, orientation: .up).map {
            BarkodBulgusu(isbn: $0.isbn, merkez: merkezOrijinale($0.kutu, dondurulmus: false))
        }
        if !duz.isEmpty { return tekil(duz) }
        guard !Task.isCancelled else { return [] }
        let donuk = tara(image, orientation: .right).map {
            BarkodBulgusu(isbn: $0.isbn, merkez: merkezOrijinale($0.kutu, dondurulmus: true))
        }
        return tekil(donuk)
    }

    nonisolated private static func tara(_ image: CGImage, orientation: CGImagePropertyOrientation) -> [(isbn: String, kutu: CGRect)] {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.ean13]
        let handler = VNImageRequestHandler(cgImage: image, orientation: orientation)
        try? handler.perform([request])
        return (request.results ?? []).compactMap { gozlem in
            guard let isbn = kitapISBN(gozlem.payloadStringValue ?? "") else { return nil }
            return (isbn, gozlem.boundingBox)
        }
    }

    /// Vision kutusu (sol ALT kökenli, 0–1) → orijinal karede sol ÜST kökenli merkez.
    /// `dondurulmus`: görüntü `.right` yönüyle (90° saat yönünde) analiz edilmişse geri çevirir.
    nonisolated static func merkezOrijinale(_ kutu: CGRect, dondurulmus: Bool) -> CGPoint {
        let vx = kutu.midX, vy = kutu.midY
        if dondurulmus {
            return CGPoint(x: 1 - vy, y: 1 - vx)
        }
        return CGPoint(x: vx, y: 1 - vy)
    }

    /// Aynı barkodun çift algılanması atılır; aynı ISBN farklı yerde duruyorsa (iki nüsha) kalır.
    nonisolated static func tekil(_ bulgular: [BarkodBulgusu]) -> [BarkodBulgusu] {
        var sonuc: [BarkodBulgusu] = []
        for bulgu in bulgular {
            let ayni = sonuc.contains { mevcut in
                mevcut.isbn == bulgu.isbn && uzaklik(mevcut.merkez, bulgu.merkez) < ayniBarkodUzakligi
            }
            if !ayni { sonuc.append(bulgu) }
        }
        return sonuc
    }

    nonisolated private static func uzaklik(_ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = a.x - b.x, dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Noktanın dikdörtgen kenarına uzaklığı (içindeyse 0).
    nonisolated static func kenaraUzaklik(_ nokta: CGPoint, _ kutu: CGRect) -> Double {
        let dx = max(kutu.minX - nokta.x, 0, nokta.x - kutu.maxX)
        let dy = max(kutu.minY - nokta.y, 0, nokta.y - kutu.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }

    // MARK: Gemini

    @concurrent private static func geminiIcinHazirla(_ data: Data) async -> Data? {
        GeminiImagePreparer.jpegData(from: data, maxPixel: 2048, quality: 0.8)
    }

    /// Gemini ile karedeki her kitap. Küçük ISBN yazıları okunabilsin diye görüntü 2048 px gider.
    static func geminiKitaplar(_ data: Data) async throws -> [AlgilananKitap] {
        let hazir = await geminiIcinHazirla(data)
        try Task.checkCancellation()
        guard let hazir else { throw GeminiError.decoding("Görüntü işlenemedi") }
        let yanit = try await GeminiClient.shared.generateJSON(
            Yanit.self,
            prompt: "Bu fotoğraftaki tüm kitapları listele.",
            system: sistemIstemi,
            images: [hazir],
            temperature: 0.1,
            maxOutputTokens: 8192,
            timeout: 90,
            maxAttempts: 2
        )
        return yanit.books
    }

    /// Barkod okuma ile Gemini aynı anda çalışır; Gemini kapalı ya da hatalıysa yalnız barkodlar kalır
    /// ve hata sonuçta bildirilir (kullanıcı ön yüzlerin okunmadığını bilsin).
    static func algila(_ data: Data) async -> AlgilamaSonucu {
        let barkodTask = Task { await barkodlar(data) }
        var gemini: [AlgilananKitap] = []
        var hata: String?
        if GeminiSettings.isOCREnabled {
            do {
                gemini = try await geminiKitaplar(data)
            } catch {
                hata = (error as? GeminiError)?.errorDescription ?? error.localizedDescription
#if DEBUG
                print("🤖 Raf karesi Gemini atlandı: \(hata ?? "")")
#endif
            }
        }
        return AlgilamaSonucu(kitaplar: birlestir(barkodlar: await barkodTask.value, gemini: gemini), geminiHatasi: hata)
    }

    // MARK: Birleştirme

    /// Konumsuz kısa yol (yalnız ISBN listesi): barkodlar kutuya bağlanmaz, nüsha eklemez.
    nonisolated static func birlestir(barkodlar: [String], gemini: [AlgilananKitap]) -> [AlgilananKitap] {
        birlestir(barkodlar: barkodlar.map { BarkodBulgusu(isbn: $0, merkez: CGPoint(x: -1, y: -1)) }, gemini: gemini)
    }

    /// Saf birleştirme (test edilebilir):
    /// 1. Her konumlu barkod, en uygun Gemini kaydına bağlanır (`enUygunKayit`) ve o kaydın ISBN'i
    ///    barkodla DEĞİŞTİRİLİR (metinden okunan rakam yanılabilir, barkod yanılmaz). Bir kayda en
    ///    fazla bir barkod bağlanır; barkodlar kutuya yakınlık sırasıyla dağıtılır.
    /// 2. Gemini kayıtlarının ISBN'i onarılıp doğrulanır; geçersizse ISBN'siz sayılır. Aynı ISBN'li
    ///    ikinci kayıt ayrı nüshadır: `nushalariTopla` açıkken adet toplanır, kapalıyken (farklı
    ///    karelerin birleştirilmesi) en yükseği alınır.
    /// 3. Bağlanamayan barkodlar ISBN'li (arka yüz) kayıt olur. ISBN zaten listedeyse nüsha sayısı,
    ///    o ISBN'in karede görülen barkod sayısının altına düşmez ama ÜSTÜNE de çıkmaz (kutusu kaymış
    ///    bir kitabın kendi barkodu hayalet nüsha üretmesin).
    /// 4. ISBN'siz kayıtlar yalnız adı okunmuşsa eklenir; benzer adlı kayıt varsa ona nüsha olarak katılır.
    nonisolated static func birlestir(
        barkodlar: [BarkodBulgusu], gemini: [AlgilananKitap], nushalariTopla: Bool = true
    ) -> [AlgilananKitap] {
        var gemini = gemini
        var bagliKayitlar = Set<Int>()
        var bagliBarkodlar = Set<Int>()

        // 1) Barkod → kayıt eşlemesi: en kesin (kutu içindeki arka yüz) çiftler önce bağlanır
        let adaylar = barkodlar.enumerated()
            .filter { $0.element.konumlu }
            .flatMap { bIndex, barkod in
                gemini.indices.compactMap { kIndex -> (bIndex: Int, kIndex: Int, puan: Double)? in
                    guard let puan = eslesmePuani(barkod.merkez, kayit: gemini[kIndex]) else { return nil }
                    return (bIndex, kIndex, puan)
                }
            }
            .sorted { $0.puan < $1.puan }
        for aday in adaylar where !bagliBarkodlar.contains(aday.bIndex) && !bagliKayitlar.contains(aday.kIndex) {
            gemini[aday.kIndex].isbn = barkodlar[aday.bIndex].isbn
            gemini[aday.kIndex].barkodlu = true
            bagliKayitlar.insert(aday.kIndex)
            bagliBarkodlar.insert(aday.bIndex)
        }

        func nushaBirlestir(_ mevcut: Int, _ eklenen: Int, into sonuc: inout [AlgilananKitap]) {
            let onceki = sonuc[mevcut].nusha
            sonuc[mevcut].copies = min(AlgilananKitap.enFazlaNusha, nushalariTopla ? onceki + eklenen : max(onceki, eklenen))
        }

        // Karede görülen konumlu barkod sayısı ve bunlardan kayda bağlananlar (ISBN başına)
        let konumluBarkodSayisi = Dictionary(
            barkodlar.filter(\.konumlu).compactMap { kitapISBN($0.isbn) }.map { ($0, 1) },
            uniquingKeysWith: +
        )
        let bagliSayisi = Dictionary(
            gemini.filter(\.barkodlu).map { ($0.temizISBN, 1) },
            uniquingKeysWith: +
        )

        var sonuc: [AlgilananKitap] = []
        // 2. adımda ISBN'i güvenilmez bulunup ada düşürülen kayıtların sıraları (4. adımda işlenir)
        var dusurulenler = Set<Int>()

        // 2) ISBN'li Gemini kayıtları
        for (kIndex, var kayit) in gemini.enumerated() {
            let isbn = kayit.temizISBN
            guard !isbn.isEmpty else { continue }
            // Komşu kitabın barkod numarası metinden kopyalanmış olabilir: o ISBN'in karedeki tüm
            // barkodları zaten başka kayıtlara bağlıysa bu metin-ISBN güvenilmez, kayıt ada düşer
            if !kayit.barkodlu, let barkodAdedi = konumluBarkodSayisi[isbn],
               bagliSayisi[isbn, default: 0] >= barkodAdedi {
                dusurulenler.insert(kIndex)
                continue
            }
            kayit.isbn = isbn
            kayit.copies = kayit.nusha
            if let index = sonuc.firstIndex(where: { $0.temizISBN == isbn }) {
                nushaBirlestir(index, kayit.nusha, into: &sonuc)
                sonuc[index].barkodlu = sonuc[index].barkodlu || kayit.barkodlu
                // Adı okunmuş kayıt, adı boş olana tercih edilir
                if sonuc[index].temizAd.isEmpty, !kayit.temizAd.isEmpty {
                    let nusha = sonuc[index].copies
                    let barkodlu = sonuc[index].barkodlu
                    sonuc[index] = kayit
                    sonuc[index].copies = nusha
                    sonuc[index].barkodlu = barkodlu
                }
            } else {
                sonuc.append(kayit)
            }
        }

        // 3) Bağlanamayan barkodlar
        for (bIndex, barkod) in barkodlar.enumerated() where !bagliBarkodlar.contains(bIndex) {
            guard let isbn = kitapISBN(barkod.isbn) else { continue }
            if let index = sonuc.firstIndex(where: { $0.temizISBN == isbn }) {
                sonuc[index].barkodlu = true
                if nushalariTopla, barkod.konumlu {
                    sonuc[index].copies = max(sonuc[index].nusha, konumluBarkodSayisi[isbn] ?? 1)
                }
            } else {
                // Kutusu yok: barkodun çevresinde küçük bir sanal kutu, aynı karedeki başka bir kayıtla
                // ayrı fiziksel kitap olduğu anlaşılabilsin (ContentView.mergeShelfDrafts)
                let kutu: [Double]? = barkod.konumlu
                    ? [barkod.merkez.y * 1000 - 20, barkod.merkez.x * 1000 - 20, barkod.merkez.y * 1000 + 20, barkod.merkez.x * 1000 + 20]
                    : nil
                sonuc.append(AlgilananKitap(isbn: isbn, side: "back", confidence: 1, box: kutu, copies: 1, barkodlu: true))
            }
        }

        // 4) ISBN'siz kayıtlar (2. adımda ISBN'i güvenilmez bulunup düşürülenler dahil)
        for (kIndex, var kayit) in gemini.enumerated() where kayit.temizISBN.isEmpty || dusurulenler.contains(kIndex) {
            let ad = kayit.temizAd
            guard !ad.isEmpty else { continue }
            kayit.isbn = nil
            kayit.copies = kayit.nusha
            let benzer = sonuc.firstIndex { mevcut in
                let mevcutAd = mevcut.temizAd
                return !mevcutAd.isEmpty && CatalogMatcher.isSimilarTitle(mevcutAd, ad)
                    && (kayit.temizYazar.isEmpty || mevcut.temizYazar.isEmpty
                        || CatalogMatcher.isSimilar(mevcut.temizYazar, kayit.temizYazar))
            }
            if let benzer {
                nushaBirlestir(benzer, kayit.nusha, into: &sonuc)
            } else {
                sonuc.append(kayit)
            }
        }

        return sonuc
    }

    /// Barkod–kayıt eşleşme puanı (küçük = iyi); eşleşemezse nil.
    /// Sıra: kutu içindeki arka yüz (0+) < kenara yakın arka yüz (1+) < kutu içindeki ön yüz (2+)
    /// < kenara yakın ön yüz (3+). Ön yüzde barkod görünmez; Gemini yüzü yanlış etiketlemişse diye
    /// tümden dışlanmaz, yalnız geriye alınır. Kesirli kısım eşitlik bozucudur: kutu merkezine
    /// yakınlık ve küçük kutu (iç içe kutularda kitabın kendi kutusu, arkadaki büyük kutu değil).
    nonisolated static func eslesmePuani(_ nokta: CGPoint, kayit: AlgilananKitap) -> Double? {
        guard let kutu = kayit.kutu else { return nil }
        let kenar = kenaraUzaklik(nokta, kutu)
        let iceride = kutu.contains(nokta) || kenar == 0
        guard iceride || kenar <= kenarPayi else { return nil }
        // Ön yüzde barkod görünmez: kutu dışındaki barkod ön yüz kaydına bağlanmaz
        guard iceride || !kayit.onYuz else { return nil }
        let merkezeUzaklik = min(1, uzaklik(nokta, CGPoint(x: kutu.midX, y: kutu.midY)))
        let alan = min(1, kutu.width * kutu.height)
        let taban: Double = (iceride ? 0 : 1) + (kayit.onYuz ? 2 : 0)
        return taban + min(0.99, 0.5 * merkezeUzaklik + 0.49 * alan)
    }

    /// Geriye dönük: noktaya en uygun kayıt (eşleşme yoksa nil).
    nonisolated static func enYakinKayit(_ nokta: CGPoint, gemini: [AlgilananKitap], haric: Set<Int>) -> Int? {
        gemini.indices
            .filter { !haric.contains($0) }
            .compactMap { index in eslesmePuani(nokta, kayit: gemini[index]).map { (index, $0) } }
            .min { $0.1 < $1.1 }?.0
    }

    /// Birden çok karenin sonuçlarını tekilleştirir: aynı kitap iki karede de çekilmiş olabilir,
    /// bu yüzden nüshalar toplanmaz (en yüksek alınır).
    nonisolated static func tekillestir(_ kayitlar: [AlgilananKitap]) -> [AlgilananKitap] {
        birlestir(barkodlar: [BarkodBulgusu](), gemini: kayitlar, nushalariTopla: false)
    }

    // MARK: Kapak kesiti

    /// Fotoğraftan kitabın kendi kutusunu keser (Amazon kapak bulamayınca kapak/arka kapak olur).
    /// Kutu %3 dışa genişletilir ki kenarlar kırpılmasın. Sanal barkod kutuları (çok küçük) kesilmez.
    nonisolated static func kapakKesiti(_ data: Data, kutu: CGRect, maxPixel: Int = 1200) -> Data? {
        guard kutu.width >= 0.08, kutu.height >= 0.08,
              let image = decodeImage(from: data, maxPixel: 3000) else { return nil }
        let pay = 0.03
        let x = max(0, kutu.minX - pay) * Double(image.width)
        let y = max(0, kutu.minY - pay) * Double(image.height)
        let genislik = (min(1, kutu.maxX + pay) * Double(image.width)) - x
        let yukseklik = (min(1, kutu.maxY + pay) * Double(image.height)) - y
        guard genislik >= 40, yukseklik >= 40,
              let kesit = image.cropping(to: CGRect(x: x, y: y, width: genislik, height: yukseklik)) else { return nil }
        return jpeg(kesit, maxPixel: maxPixel, quality: 0.85)
    }

    // MARK: Görüntü yardımcıları

    nonisolated private static func decodeImage(from data: Data, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: false
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    nonisolated private static func jpeg(_ image: CGImage, maxPixel: Int, quality: Double) -> Data? {
        var cikti = image
        let uzunKenar = max(image.width, image.height)
        if uzunKenar > maxPixel {
            let oran = Double(maxPixel) / Double(uzunKenar)
            let boyut = CGSize(width: Double(image.width) * oran, height: Double(image.height) * oran)
            if let context = CGContext(
                data: nil, width: Int(boyut.width), height: Int(boyut.height),
                bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) {
                context.interpolationQuality = .high
                context.draw(image, in: CGRect(origin: .zero, size: boyut))
                if let kucuk = context.makeImage() { cikti = kucuk }
            }
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, cikti, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

// MARK: - Esnek JSON okuma

/// Gemini yapılandırılmış çıktıda bazen sayıyı tırnak içinde ("2"), metni sayı olarak
/// (9786053607021) döndürür. Bu yardımcılar tür farkını sessizce çözer; eksik/null → nil.
/// Sonsuz/NaN ya da Int'e sığmayan değerler nil olur (Int(Double) çökmesi yaşanmaz).
nonisolated enum GevsekDeger {
    private static func guvenliTamsayi(_ d: Double) -> Int? {
        guard d.isFinite, abs(d) < 1e15 else { return nil }
        return Int(d)
    }

    static func metin<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> String? {
        if let s = try? c.decodeIfPresent(String.self, forKey: key) { return s }
        if let i = try? c.decodeIfPresent(Int.self, forKey: key) { return String(i) }
        if let d = try? c.decodeIfPresent(Double.self, forKey: key), d.isFinite {
            if d == d.rounded(), let tam = guvenliTamsayi(d) { return String(tam) }
            return String(d)
        }
        return nil
    }

    static func ondalik<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> Double? {
        if let d = try? c.decodeIfPresent(Double.self, forKey: key) { return d.isFinite ? d : nil }
        if let s = try? c.decodeIfPresent(String.self, forKey: key) {
            let d = Double(s.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
            return d.flatMap { $0.isFinite ? $0 : nil }
        }
        return nil
    }

    static func tamsayi<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> Int? {
        if let i = try? c.decodeIfPresent(Int.self, forKey: key) { return i }
        if let d = try? c.decodeIfPresent(Double.self, forKey: key) { return guvenliTamsayi(d) }
        if let s = try? c.decodeIfPresent(String.self, forKey: key) {
            let temiz = s.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
            return Int(temiz) ?? Double(temiz).flatMap(guvenliTamsayi)
        }
        return nil
    }

    /// Metin listesi; tek metin gelirse tek öğeli liste, sayı öğeleri metne çevrilir.
    static func metinListe<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> [String]? {
        if let list = try? c.decodeIfPresent([String].self, forKey: key) { return list }
        if let tek = try? c.decodeIfPresent(String.self, forKey: key) { return tek.isEmpty ? [] : [tek] }
        if let sayilar = try? c.decodeIfPresent([Double].self, forKey: key) {
            return sayilar.map { $0 == $0.rounded() && abs($0) < 1e15 ? String(Int($0)) : String($0) }
        }
        return nil
    }

    /// Mantıksal değer; "true"/"false"/"evet"/"hayır" metinleri ve 0/1 sayıları da kabul edilir.
    static func mantik<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> Bool? {
        if let b = try? c.decodeIfPresent(Bool.self, forKey: key) { return b }
        if let s = try? c.decodeIfPresent(String.self, forKey: key) {
            switch s.trimmingCharacters(in: .whitespaces).lowercased() {
            case "true", "evet", "yes", "1": return true
            case "false", "hayır", "hayir", "no", "0": return false
            default: return nil
            }
        }
        if let i = try? c.decodeIfPresent(Int.self, forKey: key) { return i != 0 }
        return nil
    }

    static func ondalikListe<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> [Double]? {
        if let list = try? c.decodeIfPresent([Double].self, forKey: key) { return list.allSatisfy(\.isFinite) ? list : nil }
        if let list = try? c.decodeIfPresent([String].self, forKey: key) {
            let sayilar = list.compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }.filter(\.isFinite)
            return sayilar.count == list.count ? sayilar : nil
        }
        return nil
    }
}
