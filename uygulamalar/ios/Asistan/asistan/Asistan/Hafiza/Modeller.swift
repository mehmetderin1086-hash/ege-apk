import Foundation
import SwiftData

@Model
final class Sohbet {
    @Attribute(.unique) var kimlik: UUID
    var baslik: String
    var olusturma: Date
    /// Çekmecede en üstte sabitlenir (hafif geçiş: varsayılan false).
    var sabit: Bool = false
    @Relationship(deleteRule: .cascade, inverse: \Mesaj.sohbet) var mesajlar: [Mesaj]

    init(baslik: String = "Yeni sohbet") {
        kimlik = UUID(); self.baslik = baslik; olusturma = .now; mesajlar = []
    }
}

@Model
final class Mesaj {
    enum Rol: String, Codable { case kullanici, asistan, arac }
    @Attribute(.unique) var kimlik: UUID
    var rolHam: String
    var metin: String
    var zaman: Date
    var sohbet: Sohbet?
    /// Yanıtla gösterilen kartlar (dosya, tablo, medya, kaynak, indirme) — JSON; eski sohbetler açılınca yeniden görünür.
    var ekVerisi: Data?
    /// V3 (P3.5): denetim/sayısal sağlama/kaynak notu (`Beyin.Goruntu.kontrol`); eski mesajlarda nil (hafif geçiş).
    var kontrol: String?

    init(rol: Rol, metin: String, sohbet: Sohbet?) {
        kimlik = UUID(); rolHam = rol.rawValue; self.metin = metin; zaman = .now; self.sohbet = sohbet
    }
    var rol: Rol { Rol(rawValue: rolHam) ?? .asistan }
}

/// Kalıcı hafıza: kullanıcı hakkında hatırlanacak tek cümlelik olgular.
@Model
final class Olgu {
    @Attribute(.unique) var kimlik: UUID
    var metin: String
    var olusturma: Date
    var kaynak: String
    /// Anlamsal arama için gömleme (Float32 dizisi); yoksa yalnız yakınlık/sıra ile bulunur.
    var vektor: Data?
    // Zenginleştirme (hepsi isteğe bağlı: eski kayıtlar için hafif SwiftData geçişi).
    /// "kisi", "tercih", "yer", "is", "saglik", "tarih", "proje", "diger".
    var kategori: String?
    /// 1-5; 5 = çok önemli (her oturum talimatına girer). Sabitlenen olgu 5 sayılır.
    var onem: Int?
    var sonKullanim: Date?
    var kullanimSayisi: Int?
    /// Kullanıcının elle sabitlediği olgu: silinmez, birleştirilmez, talimatta hep yer alır.
    var sabit: Bool?
    // V2 (SemaSurumleri: AsistanSemaV2, hafif geçiş).
    /// nil ya da "onayli": onaylı (talimata ve geri çağırmaya girer); "bekliyor": çıkarımla gelen hassas olgu, kullanıcı onayı
    /// bekliyor; "celiski": kullanıcının verdiği/sabitlediği bilgiyle çelişen yeni değer, kullanıcı hangisinin doğru olduğunu seçer.
    var durum: String?
    /// Geçici olgunun bitiş günü ("bu dönem", "yarına kadar"); geçince etkin sayılmaz, günlük bakımda silinir.
    var gecerlilikSonu: Date?

    init(metin: String, kaynak: String = "kullanici", vektor: Data? = nil) {
        kimlik = UUID(); self.metin = metin; olusturma = .now; self.kaynak = kaynak; self.vektor = vektor
    }
}
