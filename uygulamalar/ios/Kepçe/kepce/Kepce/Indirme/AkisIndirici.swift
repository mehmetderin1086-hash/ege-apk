import CommonCrypto
import Foundation

nonisolated enum IndirmeHatasi: LocalizedError, Equatable {
    case http(Int)
    case suresiDoldu
    case eksik(Int64, Int64)
    case mpegTS
    case bosYanit
    case yerYok(Int64)
    case desteklenmiyor(String)
    case dosyaDegisti

    var errorDescription: String? {
        switch self {
        case .http(let kod): "Sunucu hatası (HTTP \(kod))."
        case .suresiDoldu: "İndirme adresinin süresi doldu ya da erişim reddedildi; yeniden dene."
        case .dosyaDegisti: "Sunucudaki dosya değişti; indirme baştan başlayacak."
        case .eksik(let alinan, let beklenen): "Dosya eksik indi (\(alinan)/\(beklenen) bayt)."
        case .mpegTS: "Bu akış MPEG-TS biçiminde; iPhone'da birleştirilemez. \"Özgün dosya\" seçeneğiyle indir."
        case .bosYanit: "Sunucu boş yanıt verdi."
        case .yerYok(let gereken): "Telefonda yeterli boş yer yok (\(BicimSecici.boyutMetni(gereken)) gerekiyor)."
        case .desteklenmiyor(let neden): "Desteklenmeyen akış: \(neden)"
        }
    }

    /// Adres yenilenerek (yeniden çözülerek) düzelebilecek hatalar.
    var yenilenebilir: Bool {
        switch self {
        case .suresiDoldu, .dosyaDegisti: true
        case .http(let kod): [403, 404, 410].contains(kod)
        default: false
        }
    }
}

/// İş parçacıkları arasında paylaşılan bayt sayacı; arayüz bunu yarım saniyede bir okur.
nonisolated final class IlerlemeSayaci: @unchecked Sendable {
    private let kilit = NSLock()
    private var _alinan: Int64 = 0
    private var _toplam: Int64?

    var alinan: Int64 { kilit.withLock { _alinan } }
    var toplam: Int64? {
        get { kilit.withLock { _toplam } }
        set { kilit.withLock { _toplam = newValue } }
    }
    func ekle(_ n: Int64) { kilit.withLock { _alinan += n } }
    func ayarla(_ n: Int64) { kilit.withLock { _alinan = n } }
}

/// Gelen veriyi doğrudan dosyadaki yerine (`pwrite`) yazan URLSession temsilcisi.
/// Bellekte büyük tampon tutmaz; paralel aralık istekleri aynı dosyanın farklı bölgelerine yazar.
nonisolated final class AkisOturumu: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    static let shared = AkisOturumu()

    private final class Kayit {
        let fd: Int32
        var konum: Int64
        let baslangic: Int64
        let aralikli: Bool
        let beklenenToplam: Int64?
        let sayaclar: [IlerlemeSayaci]
        let devam: CheckedContinuation<(HTTPURLResponse, Int64), Error>
        var yanit: HTTPURLResponse?
        var hata: Error?
        init(fd: Int32, konum: Int64, aralikli: Bool, beklenenToplam: Int64?, sayaclar: [IlerlemeSayaci], devam: CheckedContinuation<(HTTPURLResponse, Int64), Error>) {
            self.fd = fd; self.konum = konum; self.baslangic = konum; self.aralikli = aralikli; self.beklenenToplam = beklenenToplam
            self.sayaclar = sayaclar; self.devam = devam
        }
    }

    private let kilit = NSLock()
    private var kayitlar: [Int: Kayit] = [:]

    private var oturumDeposu: URLSession?

    var oturum: URLSession {
        kilit.withLock {
            if let oturumDeposu { return oturumDeposu }
            let ayar = URLSessionConfiguration.default
            ayar.httpMaximumConnectionsPerHost = 16
            ayar.timeoutIntervalForRequest = 30
            ayar.requestCachePolicy = .reloadIgnoringLocalCacheData
            ayar.urlCache = nil
            ayar.waitsForConnectivity = false
            let kuyruk = OperationQueue()
            kuyruk.maxConcurrentOperationCount = 1
            kuyruk.qualityOfService = .userInitiated
            let yeni = URLSession(configuration: ayar, delegate: self, delegateQueue: kuyruk)
            oturumDeposu = yeni
            return yeni
        }
    }

    /// İsteği çalıştırır, gövdeyi `fd`'nin `konum` baytından başlayarak yazar; yanıtı ve yazılan bayt sayısını döndürür.
    /// `aralikli` istekte sunucu 206 yerine 200 dönerse ve konum 0 değilse hata verir (yanlış yere yazmamak için).
    func getir(_ istek: URLRequest, fd: Int32, konum: Int64, aralikli: Bool, beklenenToplam: Int64? = nil,
               sayaclar: [IlerlemeSayaci]) async throws -> (HTTPURLResponse, Int64) {
        try Task.checkCancellation()
        let gorev = oturum.dataTask(with: istek)
        let kimlik = gorev.taskIdentifier
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { devam in
                kilit.withLock {
                    kayitlar[kimlik] = Kayit(fd: fd, konum: konum, aralikli: aralikli, beklenenToplam: beklenenToplam, sayaclar: sayaclar, devam: devam)
                }
                // İptal kayıttan önce geldiyse tamamlanma bildirimi kaybolmuş olabilir: burada sürdür.
                // `removeValue` tek kez başarılı olduğu için devam en fazla bir kez sürdürülür.
                if Task.isCancelled {
                    gorev.cancel()
                    if let kayit = kilit.withLock({ kayitlar.removeValue(forKey: kimlik) }) { kayit.devam.resume(throwing: CancellationError()) }
                    return
                }
                gorev.resume()
            }
        } onCancel: {
            gorev.cancel()
        }
    }

    /// Yönlendirmede ana makine değişirse çerezi gönderme.
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(AkisIndirici.cerezSuz(request, onceki: task.originalRequest?.url))
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        guard let kayit = kilit.withLock({ kayitlar[dataTask.taskIdentifier] }) else { return completionHandler(.cancel) }
        guard let http = response as? HTTPURLResponse else {
            kayit.hata = IndirmeHatasi.bosYanit
            return completionHandler(.cancel)
        }
        if !(200..<300).contains(http.statusCode) {
            kayit.hata = IndirmeHatasi.http(http.statusCode)
            return completionHandler(.cancel)
        }
        if kayit.aralikli && http.statusCode == 200 && kayit.baslangic != 0 {
            kayit.hata = IndirmeHatasi.desteklenmiyor("sunucu aralıklı indirmeyi desteklemiyor")
            return completionHandler(.cancel)
        }
        if kayit.aralikli, http.statusCode == 206, let aralik = AralikBasligi(http.value(forHTTPHeaderField: "Content-Range")),
           aralik.baslangic != kayit.baslangic {
            kayit.hata = IndirmeHatasi.desteklenmiyor("sunucu yanlış aralık döndürdü")
            return completionHandler(.cancel)
        }
        if kayit.aralikli, http.statusCode == 206, let beklenen = kayit.beklenenToplam,
           let toplam = AralikBasligi(http.value(forHTTPHeaderField: "Content-Range"))?.toplam, toplam != beklenen {
            kayit.hata = IndirmeHatasi.dosyaDegisti
            return completionHandler(.cancel)
        }
        kayit.yanit = http
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let kayit = kilit.withLock({ kayitlar[dataTask.taskIdentifier] }), kayit.hata == nil else { return }
        let yazilan: Int = data.withUnsafeBytes { tampon -> Int in
            guard let taban = tampon.baseAddress else { return 0 }
            var toplam = 0
            while toplam < tampon.count {
                let n = pwrite(kayit.fd, taban + toplam, tampon.count - toplam, off_t(kayit.konum) + off_t(toplam))
                if n <= 0 { return -1 }
                toplam += n
            }
            return toplam
        }
        if yazilan < 0 {
            kayit.hata = IndirmeHatasi.yerYok(Int64(data.count))
            dataTask.cancel()
            return
        }
        kayit.konum += Int64(yazilan)
        for sayac in kayit.sayaclar { sayac.ekle(Int64(yazilan)) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let kayit = kilit.withLock({ kayitlar.removeValue(forKey: task.taskIdentifier) }) else { return }
        if let hata = kayit.hata {
            kayit.devam.resume(throwing: hata)
        } else if let error {
            if (error as? URLError)?.code == .cancelled { kayit.devam.resume(throwing: CancellationError()) }
            else { kayit.devam.resume(throwing: error) }
        } else if let yanit = kayit.yanit {
            kayit.devam.resume(returning: (yanit, kayit.konum - kayit.baslangic))
        } else {
            kayit.devam.resume(throwing: IndirmeHatasi.bosYanit)
        }
    }
}

/// `Content-Range: bytes 0-1023/4096` başlığı.
nonisolated struct AralikBasligi: Equatable {
    var baslangic: Int64
    var bitis: Int64
    var toplam: Int64?

    init?(_ metin: String?) {
        guard let metin, let bosluk = metin.firstIndex(of: " ") else { return nil }
        let govde = metin[metin.index(after: bosluk)...]
        let parcalar = govde.split(separator: "/", maxSplits: 1)
        guard parcalar.count == 2 else { return nil }
        let uclar = parcalar[0].split(separator: "-", maxSplits: 1)
        guard uclar.count == 2, let a = Int64(uclar[0]), let b = Int64(uclar[1]) else { return nil }
        baslangic = a; bitis = b; toplam = Int64(parcalar[1])
    }
}

/// Aralıklı indirmede hangi parçaların bittiğini saklayan yan dosya (devam ettirme için).
nonisolated struct ParcaDurumu: Codable, Equatable {
    var kimlik: String = ""
    var toplam: Int64
    var parca: Int64
    var tamam: Set<Int>

    var sayi: Int { parca > 0 && toplam > 0 ? Int((toplam - 1) / parca + 1) : 0 }
    func aralik(_ i: Int) -> ClosedRange<Int64> { Int64(i) * parca ... min(toplam, Int64(i + 1) * parca) - 1 }
    var kalan: [Int] { (0..<sayi).filter { !tamam.contains($0) } }
    var alinan: Int64 { tamam.reduce(0) { $0 + Int64(aralik($1).count) } }
}

nonisolated enum AkisIndirici {
    static let varsayilanParca: Int64 = 8 * 1024 * 1024
    static let enBuyukDosya: Int64 = 1 << 42   // 4 TB: bunun üstü bozuk başlık sayılır

    /// Devam ettirme dosyalarının hangi akışa ait olduğunu belirler (biçim değişirse baştan indirilir).
    static func kimlik(_ b: Bicim) -> String { "\(b.formatID)|\(b.filesize ?? -1)" }

    /// `cerezKaynagi`: çerezin ait olduğu adres; başka ana makineye giden isteklerde Cookie başlığı atılır.
    static func istek(_ adres: URL, basliklar: [String: String]?, aralik: ClosedRange<Int64>? = nil, cerezKaynagi: URL? = nil) -> URLRequest {
        var istek = URLRequest(url: adres)
        let ayniMakine = cerezKaynagi == nil || cerezKaynagi?.host()?.lowercased() == adres.host()?.lowercased()
        for (ad, deger) in basliklar ?? [:] where ayniMakine || ad.lowercased() != "cookie" { istek.setValue(deger, forHTTPHeaderField: ad) }
        if let aralik { istek.setValue("bytes=\(aralik.lowerBound)-\(aralik.upperBound)", forHTTPHeaderField: "Range") }
        istek.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        return istek
    }

    static func cerezSuz(_ istek: URLRequest, onceki: URL?) -> URLRequest {
        guard let onceki, istek.url?.host()?.lowercased() != onceki.host()?.lowercased() else { return istek }
        var yeni = istek
        yeni.setValue(nil, forHTTPHeaderField: "Cookie")
        return yeni
    }

    /// Biçimi `hedef` dosyasına indirir; aynı hedefe yeniden çağrılırsa kaldığı yerden sürer.
    /// Tamamlanan akış bir işaret dosyası bırakır; aynı biçimle yeniden çağrılınca indirilmez.
    @concurrent static func indir(_ bicim: Bicim, hedef: URL, baglanti: Int, sayac: IlerlemeSayaci, sure: Double?, mpegTSKabul: Bool = false) async throws {
        let isaret = hedef.appendingPathExtension("tamam")
        if let eski = try? String(contentsOf: isaret, encoding: .utf8), eski == kimlik(bicim),
           let boyut = try? hedef.resourceValues(forKeys: [.fileSizeKey]).fileSize, boyut > 0 {
            sayac.toplam = Int64(boyut)
            sayac.ayarla(Int64(boyut))
            return
        }
        try? FileManager.default.removeItem(at: isaret)
        if bicim.parcali {
            try await parcalar(bicim, hedef: hedef, baglanti: baglanti, sayac: sayac, sure: sure)
        } else if bicim.hls {
            try await hls(bicim, hedef: hedef, baglanti: baglanti, sayac: sayac, sure: sure, mpegTSKabul: mpegTSKabul)
        } else {
            try await dogrudan(bicim, hedef: hedef, baglanti: baglanti, sayac: sayac)
        }
        try? kimlik(bicim).write(to: isaret, atomically: true, encoding: .utf8)
    }

    // MARK: Doğrudan (HTTP aralıklı, paralel)

    static func dogrudan(_ bicim: Bicim, hedef: URL, baglanti: Int, sayac: IlerlemeSayaci) async throws {
        guard let adresMetni = bicim.url, let adres = URL(string: adresMetni) else { throw IndirmeHatasi.bosYanit }
        let durumDosyasi = hedef.appendingPathExtension("durum")
        let parca = max(256 * 1024, min(bicim.chunkSize ?? varsayilanParca, varsayilanParca))
        let akisKimligi = kimlik(bicim)

        var durum = (try? Data(contentsOf: durumDosyasi)).flatMap { try? JSONDecoder().decode(ParcaDurumu.self, from: $0) }
        // Başka biçime ait, parça boyu farklı ya da dosyası silinmiş (iOS önbelleği temizlemiş) durum geçersizdir.
        if let d = durum, d.parca != parca || d.kimlik != akisKimligi || !FileManager.default.fileExists(atPath: hedef.path) {
            durum = nil
        }
        if durum == nil { try? FileManager.default.removeItem(at: hedef) }

        let fd = open(hedef.path, O_RDWR | O_CREAT, 0o644)
        guard fd >= 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { close(fd) }

        do {
            if durum == nil {
                // İlk parça: toplam boyutu ve aralık desteğini öğren.
                sayac.ayarla(0)
                let ilk = 0...(parca - 1)
                let (yanit, yazilan) = try await yinele {
                    sayac.ayarla(0)
                    return try await AkisOturumu.shared.getir(istek(adres, basliklar: bicim.httpHeaders, aralik: ilk), fd: fd, konum: 0, aralikli: true, sayaclar: [sayac])
                }
                if yanit.statusCode == 200 {
                    // Sunucu aralığı yok saydı: bütün dosya geldi.
                    ftruncate(fd, off_t(yazilan))
                    sayac.toplam = yazilan
                    try? FileManager.default.removeItem(at: durumDosyasi)
                    return
                }
                guard let toplam = AralikBasligi(yanit.value(forHTTPHeaderField: "Content-Range"))?.toplam ?? bicim.filesize else {
                    throw IndirmeHatasi.desteklenmiyor("dosya boyutu bilinmiyor")
                }
                guard toplam > 0, toplam < enBuyukDosya else { throw IndirmeHatasi.desteklenmiyor("geçersiz dosya boyutu") }
                durum = ParcaDurumu(kimlik: akisKimligi, toplam: toplam, parca: parca, tamam: yazilan >= min(parca, toplam) ? [0] : [])
                try kaydet(durum!, durumDosyasi)
            }
            guard var durum else { return }
            sayac.toplam = durum.toplam
            sayac.ayarla(durum.alinan)
            try yerVarMi(durum.toplam - durum.alinan, hedef: hedef)

            let kalan = durum.kalan
            let toplam = durum.toplam
            do {
                try await withThrowingTaskGroup(of: Int.self) { grup in
                    var sira = kalan.makeIterator()
                    func baslat() {
                        guard let i = sira.next() else { return }
                        let aralik = durum.aralik(i)
                        grup.addTask {
                            // Parçanın baytları gelirken toplam sayaca da eklenir; deneme başarısız olursa geri alınır.
                            let parcaSayaci = IlerlemeSayaci()
                            do {
                                let (_, yazilan) = try await yinele {
                                    sayac.ekle(-parcaSayaci.alinan)
                                    parcaSayaci.ayarla(0)
                                    return try await AkisOturumu.shared.getir(istek(adres, basliklar: bicim.httpHeaders, aralik: aralik), fd: fd,
                                                                              konum: aralik.lowerBound, aralikli: true, beklenenToplam: toplam,
                                                                              sayaclar: [parcaSayaci, sayac])
                                }
                                if yazilan != Int64(aralik.count) { throw IndirmeHatasi.eksik(yazilan, Int64(aralik.count)) }
                            } catch {
                                sayac.ekle(-parcaSayaci.alinan)
                                throw error
                            }
                            return i
                        }
                    }
                    for _ in 0..<max(1, baglanti) { baslat() }
                    var sonKayit = Date()
                    while let biten = try await grup.next() {
                        durum.tamam.insert(biten)
                        if Date().timeIntervalSince(sonKayit) > 1 { try? kaydet(durum, durumDosyasi); sonKayit = Date() }
                        baslat()
                    }
                }
            } catch {
                try? kaydet(durum, durumDosyasi)   // biten parçalar kaybolmasın
                throw error
            }
            ftruncate(fd, off_t(toplam))
            try? FileManager.default.removeItem(at: durumDosyasi)
        } catch IndirmeHatasi.dosyaDegisti {
            // Sunucudaki dosya değişti: eldeki parçalar işe yaramaz.
            try? FileManager.default.removeItem(at: durumDosyasi)
            ftruncate(fd, 0)
            throw IndirmeHatasi.dosyaDegisti
        }
    }

    private static func kaydet(_ durum: ParcaDurumu, _ dosya: URL) throws {
        try JSONEncoder().encode(durum).write(to: dosya, options: .atomic)
    }

    static func yerVarMi(_ gereken: Int64, hedef: URL) throws {
        let degerler = try? hedef.deletingLastPathComponent().resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let bos = degerler?.volumeAvailableCapacityForImportantUsage, gereken > 0, bos < min(gereken, enBuyukDosya) + 200_000_000 {
            throw IndirmeHatasi.yerYok(gereken)
        }
    }

    /// Geçici ağ hatalarında üç kez yeniden dener; adres süresi dolduysa hemen bırakır.
    static func yinele<T: Sendable>(_ deneme: @Sendable () async throws -> T) async throws -> T {
        var son: Error?
        for tur in 0..<4 {
            do { return try await deneme() } catch {
                if error is CancellationError { throw error }
                if let hata = error as? IndirmeHatasi {
                    if hata == .dosyaDegisti { throw hata }
                    if hata.yenilenebilir { throw IndirmeHatasi.suresiDoldu }
                    if case .http(let kod) = hata, kod < 500, kod != 429 { throw hata }
                    if case .yerYok = hata { throw hata }
                    if case .desteklenmiyor = hata { throw hata }
                }
                son = error
                try await Task.sleep(for: .seconds(Double(tur + 1) * 1.5))
            }
        }
        throw son ?? IndirmeHatasi.bosYanit
    }

    // MARK: Parçalı akış (DASH parçaları, HLS bölütleri)

    nonisolated struct Bolut: Sendable {
        var adres: URL
        var aralik: ClosedRange<Int64>?
        var anahtar: URL?
        var iv: Data?
    }

    static func parcalar(_ bicim: Bicim, hedef: URL, baglanti: Int, sayac: IlerlemeSayaci, sure: Double?) async throws {
        let taban = bicim.fragmentBaseURL.flatMap(URL.init(string:))
        let bolutler: [Bolut] = (bicim.fragments ?? []).compactMap { parca in
            if let url = parca.url, let adres = URL(string: url) { return Bolut(adres: adres) }
            if let yol = parca.path, let adres = taban.flatMap({ URL(string: yol, relativeTo: $0)?.absoluteURL }) { return Bolut(adres: adres) }
            return nil
        }
        guard !bolutler.isEmpty, bolutler.count == bicim.fragments?.count else { throw IndirmeHatasi.desteklenmiyor("parça adresleri eksik") }
        sayac.toplam = bicim.boyut(sure: sure)
        try await sirali(bolutler, basliklar: bicim.httpHeaders, cerezKaynagi: bicim.url.flatMap(URL.init(string:)) ?? taban, kimlik: kimlik(bicim),
                         hedef: hedef, baglanti: baglanti, sayac: sayac, ilkKontrol: nil)
    }

    static func hls(_ bicim: Bicim, hedef: URL, baglanti: Int, sayac: IlerlemeSayaci, sure: Double?, mpegTSKabul: Bool) async throws {
        guard let adresMetni = bicim.url, var adres = URL(string: adresMetni) else { throw IndirmeHatasi.bosYanit }
        let kaynak = adres
        var liste = HLSListesi(metin: try await yinele { try await metin(kaynak, bicim.httpHeaders, cerezKaynagi: kaynak) }, taban: adres)
        if let varyant = liste.enIyiVaryant {   // ana liste geldiyse en yüksek bant genişlikli varyant
            adres = varyant
            liste = HLSListesi(metin: try await yinele { try await metin(varyant, bicim.httpHeaders, cerezKaynagi: kaynak) }, taban: varyant)
        }
        guard !liste.bolutler.isEmpty else { throw IndirmeHatasi.bosYanit }
        if liste.sifreleme == .desteklenmeyen { throw IndirmeHatasi.desteklenmiyor("şifreli (DRM) HLS") }
        sayac.toplam = bicim.boyut(sure: sure)
        let tum = (liste.baslangic.map { [$0] } ?? []) + liste.bolutler
        var kontrol: (@Sendable (Data) throws -> Void)?
        if liste.baslangic == nil && !mpegTSKabul {
            kontrol = { veri in if veri.first == 0x47 { throw IndirmeHatasi.mpegTS } }
        }
        try await sirali(tum, basliklar: bicim.httpHeaders, cerezKaynagi: kaynak, kimlik: kimlik(bicim), hedef: hedef, baglanti: baglanti,
                         sayac: sayac, ilkKontrol: kontrol)
    }

    static func metin(_ adres: URL, _ basliklar: [String: String]?, cerezKaynagi: URL?) async throws -> String {
        let (veri, yanit) = try await URLSession.shared.data(for: istek(adres, basliklar: basliklar, cerezKaynagi: cerezKaynagi), delegate: CerezsizYonlendirme.shared)
        if let http = yanit as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw IndirmeHatasi.http(http.statusCode) }
        return String(decoding: veri, as: UTF8.self)
    }

    /// Bölütleri paralel indirir, dosyaya sırayla ekler. Yan dosya kaçıncı bölüte kadar yazıldığını tutar.
    static func sirali(_ bolutler: [Bolut], basliklar: [String: String]?, cerezKaynagi: URL?, kimlik: String, hedef: URL, baglanti: Int,
                       sayac: IlerlemeSayaci, ilkKontrol: (@Sendable (Data) throws -> Void)?) async throws {
        struct Durum: Codable { var kimlik: String?; var sayi: Int?; var yazilan: Int; var konum: Int64 }
        let durumDosyasi = hedef.appendingPathExtension("durum")
        let yeni = Durum(kimlik: kimlik, sayi: bolutler.count, yazilan: 0, konum: 0)
        var durum = (try? Data(contentsOf: durumDosyasi)).flatMap { try? JSONDecoder().decode(Durum.self, from: $0) } ?? yeni
        // Başka akışa ait, bölüt sayısı değişmiş ya da dosyası kaybolmuş/kısalmış durum geçersizdir.
        let boyut = (try? hedef.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? -1
        if durum.kimlik != kimlik || durum.sayi != bolutler.count || boyut < durum.konum || durum.yazilan > bolutler.count { durum = yeni }
        if !FileManager.default.fileExists(atPath: hedef.path) { FileManager.default.createFile(atPath: hedef.path, contents: nil) }
        let tutamac = try FileHandle(forWritingTo: hedef)
        defer { try? tutamac.close() }
        try tutamac.truncate(atOffset: UInt64(durum.konum))
        try tutamac.seekToEnd()
        sayac.ayarla(durum.konum)

        var anahtarlar: [URL: Data] = [:]
        for bolut in bolutler {
            if let a = bolut.anahtar, anahtarlar[a] == nil { anahtarlar[a] = try await yinele { try await veri(a, basliklar, cerezKaynagi: cerezKaynagi) } }
        }
        let anahtarTablosu = anahtarlar

        let baslangic = durum.yazilan
        let pencere = max(1, baglanti) * 4   // yazılmayı bekleyen bölüt sayısı sınırı (bellek)
        try await withThrowingTaskGroup(of: (Int, Data).self) { grup in
            var sonraki = baslangic, siradaki = baslangic, ucusta = 0
            var bekleyen: [Int: Data] = [:]
            func doldur() {
                while ucusta < max(1, baglanti), sonraki < bolutler.count, sonraki - siradaki < pencere {
                    let i = sonraki, bolut = bolutler[i]
                    sonraki += 1
                    ucusta += 1
                    grup.addTask {
                        var icerik = try await yinele { try await veri(bolut.adres, basliklar, aralik: bolut.aralik, cerezKaynagi: cerezKaynagi) }
                        if let a = bolut.anahtar, let anahtar = anahtarTablosu[a] {
                            icerik = try aesCoz(icerik, anahtar: anahtar, iv: bolut.iv ?? sira(i))
                        }
                        return (i, icerik)
                    }
                }
            }
            doldur()
            while let (i, icerik) = try await grup.next() {
                ucusta -= 1
                bekleyen[i] = icerik
                while let parca = bekleyen.removeValue(forKey: siradaki) {
                    if siradaki == 0 { try ilkKontrol?(parca) }
                    try tutamac.write(contentsOf: parca)
                    durum.konum += Int64(parca.count)
                    durum.yazilan = siradaki + 1
                    sayac.ekle(Int64(parca.count))
                    siradaki += 1
                    if siradaki % 10 == 0 { try? JSONEncoder().encode(durum).write(to: durumDosyasi, options: .atomic) }
                }
                doldur()
            }
        }
        sayac.toplam = durum.konum
        try? FileManager.default.removeItem(at: durumDosyasi)
    }

    static func veri(_ adres: URL, _ basliklar: [String: String]?, aralik: ClosedRange<Int64>? = nil, cerezKaynagi: URL?) async throws -> Data {
        let (veri, yanit) = try await URLSession.shared.data(for: istek(adres, basliklar: basliklar, aralik: aralik, cerezKaynagi: cerezKaynagi),
                                                             delegate: CerezsizYonlendirme.shared)
        if let http = yanit as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw IndirmeHatasi.http(http.statusCode) }
        return veri
    }

    /// HLS'de IV verilmezse bölüt sıra numarası 16 baytlık büyük-sonlu IV olur.
    static func sira(_ i: Int) -> Data {
        var iv = Data(count: 16)
        var n = UInt64(i).bigEndian
        withUnsafeBytes(of: &n) { iv.replaceSubrange(8..<16, with: $0) }
        return iv
    }

    static func aesCoz(_ veri: Data, anahtar: Data, iv: Data) throws -> Data {
        var cikis = Data(count: veri.count + kCCBlockSizeAES128)
        var uzunluk = 0
        let durum = cikis.withUnsafeMutableBytes { c in
            veri.withUnsafeBytes { v in
                anahtar.withUnsafeBytes { a in
                    iv.withUnsafeBytes { i in
                        CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                                a.baseAddress, anahtar.count, i.baseAddress, v.baseAddress, veri.count, c.baseAddress, c.count, &uzunluk)
                    }
                }
            }
        }
        guard durum == kCCSuccess else { throw IndirmeHatasi.desteklenmiyor("AES çözülemedi") }
        return cikis.prefix(uzunluk)
    }
}

/// En basit HLS ayrıştırıcısı: varyantlar, EXT-X-MAP, bayt aralıkları ve AES-128.
nonisolated struct HLSListesi {
    enum Sifreleme { case yok, aes128, desteklenmeyen }
    var bolutler: [AkisIndirici.Bolut] = []
    var baslangic: AkisIndirici.Bolut?
    var enIyiVaryant: URL?
    var sifreleme = Sifreleme.yok

    init(metin: String, taban: URL) {
        var anahtar: URL?, iv: Data?
        var sonrakiAralik: ClosedRange<Int64>?
        var sonAralikSonu: Int64 = 0
        var medyaSirasi = 0
        var enIyiBant = -1
        var varyantBekliyor: Int?
        for satir in metin.split(whereSeparator: \.isNewline).map({ $0.trimmingCharacters(in: .whitespaces) }) where !satir.isEmpty {
            if satir.hasPrefix("#EXT-X-STREAM-INF:") {
                varyantBekliyor = Int(Self.ozellik(satir, "BANDWIDTH") ?? "") ?? 0
            } else if satir.hasPrefix("#EXT-X-MEDIA-SEQUENCE:") {
                medyaSirasi = Int(satir.dropFirst("#EXT-X-MEDIA-SEQUENCE:".count)) ?? 0
            } else if satir.hasPrefix("#EXT-X-KEY:") {
                let yontem = Self.ozellik(satir, "METHOD") ?? "NONE"
                switch yontem {
                case "NONE": anahtar = nil; iv = nil
                case "AES-128":
                    if sifreleme != .desteklenmeyen { sifreleme = .aes128 }
                    anahtar = Self.ozellik(satir, "URI").flatMap { URL(string: $0, relativeTo: taban)?.absoluteURL }
                    iv = Self.ozellik(satir, "IV").flatMap(Self.onaltilik)
                default: sifreleme = .desteklenmeyen
                }
                if yontem != "NONE" && yontem != "AES-128" { sifreleme = .desteklenmeyen }
            } else if satir.hasPrefix("#EXT-X-MAP:") {
                if let uri = Self.ozellik(satir, "URI"), let adres = URL(string: uri, relativeTo: taban)?.absoluteURL {
                    baslangic = AkisIndirici.Bolut(adres: adres, aralik: Self.ozellik(satir, "BYTERANGE").flatMap { Self.aralik($0, onceki: 0) })
                }
            } else if satir.hasPrefix("#EXT-X-BYTERANGE:") {
                sonrakiAralik = Self.aralik(String(satir.dropFirst("#EXT-X-BYTERANGE:".count)), onceki: sonAralikSonu)
            } else if satir.hasPrefix("#") {
                continue
            } else if let bant = varyantBekliyor {
                if bant > enIyiBant, let adres = URL(string: satir, relativeTo: taban)?.absoluteURL { enIyiBant = bant; enIyiVaryant = adres }
                varyantBekliyor = nil
            } else if let adres = URL(string: satir, relativeTo: taban)?.absoluteURL {
                let sira = medyaSirasi + bolutler.count
                bolutler.append(AkisIndirici.Bolut(adres: adres, aralik: sonrakiAralik, anahtar: anahtar, iv: iv ?? (anahtar != nil ? AkisIndirici.sira(sira) : nil)))
                if let sonrakiAralik { sonAralikSonu = sonrakiAralik.upperBound + 1 }
                sonrakiAralik = nil
            }
        }
        if !bolutler.isEmpty { enIyiVaryant = nil }
    }

    static func ozellik(_ satir: String, _ ad: String) -> String? {
        // "BANDWIDTH" ararken "AVERAGE-BANDWIDTH"i yakalamamak için öncesinde ':' ya da ',' olmalı.
        guard let aralik = satir.range(of: "[:,]\(ad)=", options: .regularExpression) else { return nil }
        var kalan = satir[aralik.upperBound...]
        if kalan.first == "\"" {
            kalan = kalan.dropFirst()
            return kalan.firstIndex(of: "\"").map { String(kalan[..<$0]) }
        }
        return String(kalan.prefix { $0 != "," })
    }

    /// "uzunluk@başlangıç" (başlangıç yoksa öncekinin sonu).
    static func aralik(_ metin: String, onceki: Int64) -> ClosedRange<Int64>? {
        let parcalar = metin.split(separator: "@")
        guard let ilk = parcalar.first, let uzunluk = Int64(ilk), uzunluk > 0, uzunluk < AkisIndirici.enBuyukDosya else { return nil }
        let bas = parcalar.count > 1 ? Int64(parcalar[1]) ?? onceki : onceki
        guard bas >= 0, bas < AkisIndirici.enBuyukDosya else { return nil }
        return bas...(bas + uzunluk - 1)
    }

    static func onaltilik(_ metin: String) -> Data? {
        var hex = metin.lowercased()
        if hex.hasPrefix("0x") { hex.removeFirst(2) }
        guard hex.count == 32 else { return nil }
        var veri = Data()
        var i = hex.startIndex
        while i < hex.endIndex {
            let j = hex.index(i, offsetBy: 2)
            guard let bayt = UInt8(hex[i..<j], radix: 16) else { return nil }
            veri.append(bayt)
            i = j
        }
        return veri
    }
}

/// URLSession'ın kendi yönlendirmelerinde çerezin başka ana makineye gitmesini önler.
nonisolated final class CerezsizYonlendirme: NSObject, URLSessionTaskDelegate, Sendable {
    static let shared = CerezsizYonlendirme()
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(AkisIndirici.cerezSuz(request, onceki: task.originalRequest?.url))
    }
}
