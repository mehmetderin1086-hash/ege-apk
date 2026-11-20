import Foundation
import PDFKit

/// Parola koruması: parola koyma ve kaldırma.
public enum Koruma {

    /// Parola durumu (açmadan önce).
    public struct Durum: Sendable, Equatable {
        public var sifreli: Bool
        public var kilitli: Bool
    }

    public static func durum(veri: Data) -> Durum? {
        guard let b = PDFDocument(data: veri) else { return nil }
        return Durum(sifreli: b.isEncrypted, kilitli: b.isLocked)
    }

    /// PDF'e parola koyar.
    /// - `kullaniciParolasi`: belgeyi açmak için sorulur (boşsa açılış serbest).
    /// - `sahipParolasi`: izinleri değiştirmek için; `izinler` kısıtlıysa zorunludur.
    /// - `izinler`: verilen izinler (yazdırma, kopyalama, değiştirme…); sahip parolasını bilen hepsini yapabilir.
    public static func parolaKoy(veri: Data, kaynakParola: String? = nil,
                                 kullaniciParolasi: String?, sahipParolasi: String?,
                                 izinler: Izinler = .hepsi) throws -> Data {
        let kullanici = (kullaniciParolasi?.isEmpty ?? true) ? nil : kullaniciParolasi
        let sahip = (sahipParolasi?.isEmpty ?? true) ? nil : sahipParolasi
        guard kullanici != nil || sahip != nil else {
            throw KagitHata.genel("En az bir parola girin (açılış ya da sahip parolası).")
        }
        if izinler != .hepsi && sahip == nil {
            throw KagitHata.genel("İzinleri kısıtlamak için bir sahip parolası belirleyin.")
        }
        let belge = try Belge.ac(veri: veri, parola: kaynakParola)
        guard belge.pageCount > 0 else { throw KagitHata.bosGirdi }
        // PDFKit sahip parolası olmadan kullanıcı parolasını yok sayabiliyor: boşsa kullanıcı parolasını kullan.
        let secenekler = KayitSecenekleri(kullaniciParolasi: kullanici, sahipParolasi: sahip ?? kullanici,
                                          izinler: izinler)
        let cikti = try Belge.veri(belge, secenekler: secenekler)
        // Doğrula: şifreli ve parola açıyor.
        guard let kontrol = PDFDocument(data: cikti), kontrol.isEncrypted else {
            throw KagitHata.dogrulamaBasarisiz("çıktı parola korumalı değil")
        }
        if let kullanici {
            guard kontrol.isLocked, kontrol.unlock(withPassword: kullanici) else {
                throw KagitHata.dogrulamaBasarisiz("parola ile açılamıyor")
            }
        }
        guard kontrol.pageCount == belge.pageCount else {
            throw KagitHata.dogrulamaBasarisiz("sayfa sayısı değişti")
        }
        return cikti
    }

    /// Parolayı sorup çözülmüş (şifresiz) kopya üretir. Yalnız sahip parolası olan dosyalarda da çalışır.
    public static func parolaKaldir(veri: Data, parola: String?) throws -> Data {
        guard let belge = PDFDocument(data: veri) else { throw KagitHata.acilamadi("belge") }
        guard belge.isEncrypted else { throw KagitHata.genel("Bu PDF zaten parolasız.") }
        if belge.isLocked {
            guard let parola, !parola.isEmpty else { throw KagitHata.parolaGerekli }
            guard belge.unlock(withPassword: parola) else { throw KagitHata.parolaYanlis }
        } else if let parola, !parola.isEmpty {
            _ = belge.unlock(withPassword: parola)   // yalnız sahip parolası varsa izinleri açar
        }
        // PDFKit, kilidi açılmış belgeyi aynı parolayla yeniden şifreler; boş kullanıcı parolası şifrelemeyi kaldırır.
        Belge.anonimlestir(belge)
        Belge.ios27KayitDuzeltmesi(belge)
        guard let cikti = belge.dataRepresentation(options: [PDFDocumentWriteOption.userPasswordOption: ""]) else {
            throw KagitHata.kaydedilemedi("PDF verisi üretilemedi")
        }
        guard let kontrol = PDFDocument(data: cikti), !kontrol.isEncrypted, !kontrol.isLocked,
              kontrol.pageCount == belge.pageCount else {
            throw KagitHata.dogrulamaBasarisiz("çözülmüş kopya hâlâ korumalı ya da eksik")
        }
        return cikti
    }
}
