import Foundation

/// Ayarlardan gelen yapay zekâ yapılandırması.
public struct YapayYapilandirma: Sendable, Equatable {
    public var tercih: KaynakTercihi
    public var model: String
    /// `Ayarlar.bulutYapayZeka`
    public var bulutAcik: Bool
    public var kok: String
    public var anahtar: String?

    public init(tercih: KaynakTercihi = .otomatik, model: String = YapayModeller.varsayilan,
                bulutAcik: Bool = true, kok: String, anahtar: String?) {
        self.tercih = tercih
        self.model = model
        self.bulutAcik = bulutAcik
        self.kok = kok
        self.anahtar = anahtar
    }
}

/// Kaynak seçimi + geri düşme. Özellikler bu yapıyı kullanır, kaynağı doğrudan bilmez.
public struct YapayZeka: Sendable {
    public let yapilandirma: YapayYapilandirma
    let oturum: URLSession
    let cihazVar: Bool
    /// Test için doğrudan kaynak.
    let zorunluKaynak: (any YapayKaynak)?

    public init(_ y: YapayYapilandirma, oturum: URLSession = .shared, cihazKullanilabilir: Bool? = nil) {
        yapilandirma = y
        self.oturum = oturum
        cihazVar = cihazKullanilabilir ?? CihazModeli.kullanilabilir
        zorunluKaynak = nil
    }

    /// Sabit bir kaynakla (testler).
    public init(kaynak: any YapayKaynak) {
        yapilandirma = YapayYapilandirma(kok: "", anahtar: nil)
        oturum = .shared
        cihazVar = false
        zorunluKaynak = kaynak
    }

    func bulut() throws -> VekilIstemci {
        guard yapilandirma.bulutAcik else {
            throw KagitHata.yapayZeka("Bulut yapay zekâ Ayarlar'da kapalı. Bu cihaz Apple Intelligence'ı desteklemiyorsa Ayarlar › Yapay Zekâ'dan bulutu açın.")
        }
        guard let k = yapilandirma.anahtar, !k.isEmpty else {
            throw KagitHata.yapayZeka("Vekil anahtarı girilmemiş. Ayarlar › Yapay Zekâ bölümünden girin.")
        }
        return VekilIstemci(kok: yapilandirma.kok, anahtar: k, model: yapilandirma.model, oturum: oturum)
    }

    /// Tercihe göre birincil kaynak.
    public func birincil() throws -> any YapayKaynak {
        if let zorunluKaynak { return zorunluKaynak }
        switch yapilandirma.tercih {
        case .yalnizCihaz:
            guard cihazVar else {
                throw KagitHata.yapayZeka("Bu cihazda Apple Intelligence kullanılamıyor. Ayarlar'dan kaynağı Otomatik ya da Yalnız bulut yapın.")
            }
            return CihazModeli()
        case .yalnizBulut:
            return try bulut()
        case .otomatik:
            if cihazVar { return CihazModeli() }
            return try bulut()
        }
    }

    /// Ekranda göstermek için seçilecek kaynağın etiketi (kullanılamıyorsa nil).
    public var kaynakEtiketi: String? { try? birincil().etiket }

    /// Kaynak kullanılamıyorsa açıklayıcı ileti (kullanılabiliyorsa nil).
    public var kullanilamazNedeni: String? {
        do { _ = try birincil(); return nil } catch { return (error as? LocalizedError)?.errorDescription ?? "Yapay zekâ kullanılamıyor." }
    }

    public var baglamSiniri: Int { (try? birincil().baglamSiniri) ?? 4_500 }

    /// Yanıt üretir. Otomatik kipte cihaz başarısız olursa buluta düşer.
    public func yanit(_ istek: YapayIstek, akis: YapayAkisi? = nil) async throws -> YapayYaniti {
        let ilk = try birincil()
        do {
            return try await ilk.yanit(istek, akis: akis)
        } catch {
            if zorunluKaynak == nil, yapilandirma.tercih == .otomatik, ilk is CihazModeli,
               !(error is CancellationError), (error as? KagitHata) != .iptal,
               let b = try? bulut() {
                return try await b.yanit(istek, akis: akis)
            }
            throw error
        }
    }

    /// Bağlantıyı sınar: kısa bir istek gönderir.
    public func sina() async throws -> YapayYaniti {
        try await yanit(YapayIstek(sistem: "Çok kısa yanıt ver.", kullanici: "Yalnızca “tamam” yaz.", azamiToken: 600))
    }
}
