import Foundation
import PDFKit

/// Düzenleyicinin kayıt hattı: `KagitDamgasi` açıklamalarını içeriğe işler, ardından
/// (şifresiz belgelerde) form alanları için `/AcroForm` yamasını uygular.
public enum KayitIsleme {
    public static func veri(_ belge: PDFDocument, secenekler: KayitSecenekleri = .init()) throws -> Data {
        let veri = try DamgaIsleme.veri(belge, secenekler: secenekler)
        let sifreli = secenekler.kullaniciParolasi != nil || secenekler.sahipParolasi != nil || belge.isEncrypted
        return sifreli ? veri : AcroFormYamasi.uygula(veri)
    }
}
