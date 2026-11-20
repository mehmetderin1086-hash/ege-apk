import Foundation
import SwiftData

/// Hafıza deposunun sürümlü şeması. V1: `Sohbet.sabit`, `Mesaj.ekVerisi`, `Olgu.kategori/onem/sonKullanim/kullanimSayisi/sabit`
/// alanlarıyla 20 Eki 2026'ya kadarki modeller (aşağıda dondurulmuş kopyalar); sürümsüz `Schema([...])` ile açılmış eski depo
/// V1 sayılır (model özetleri aynıdır). V2: `Olgu.durum`, `Olgu.gecerlilikSonu` (dondurulmuş kopyalar). V3: bugünkü üst düzey modeller (`Mesaj.kontrol`).
///
/// V2 eklemenin reçetesi (modele alan eklemek, alan adı/türü değiştirmek, model eklemek):
/// 1. Bugünkü `Sohbet`, `Mesaj`, `Olgu` tanımlarını olduğu gibi `AsistanSemaV1` içine iç tür olarak kopyala
///    (`@Model final class Sohbet { ... }`); V1 artık bu dondurulmuş kopyaları listeler, eski tanım bir daha değişmez.
/// 2. `Modeller.swift`'te değişikliği yap ve `nonisolated enum AsistanSemaV2: VersionedSchema` ekle
///    (`Schema.Version(2, 0, 0)`, modeller üst düzey türler).
/// 3. `AsistanGocPlani.schemas`'a `AsistanSemaV2.self` ekle; `stages`'e
///    `.lightweight(fromVersion: AsistanSemaV1.self, toVersion: AsistanSemaV2.self)` ya da veri dönüştürmesi
///    gerekiyorsa `.custom(fromVersion:toVersion:willMigrate:didMigrate:)` ekle.
/// 4. `HafizaDeposu.kapAc` içindeki `AsistanSemaV1` başvurusunu en yeni sürümle değiştir.
/// 5. Eski sürüm deposundan (V1 yedeği) açılışı sınayan birim testi yaz (`HafizaKurtarmaTestleri` deseni).
/// Geçiş başarısız olursa `HafizaKurtarma.tani` sağlam dosyayı `.semaUyumsuz` sayar: veri TAŞINMAZ, kopyalanır;
/// kap bellekte açılır ve bir sonraki sürüm düzeltmesiyle aynı depo yeniden açılabilir.
nonisolated enum AsistanSemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [Sohbet.self, Mesaj.self, Olgu.self] }

    // Dondurulmuş V1 kopyaları (P3.8, 20 Eki 2026): saklanan alanlar V1 deposundaki model özetiyle birebir aynı kalmalı.
    // BİR DAHA DEĞİŞTİRME; yeni alan bugünkü üst düzey modellere ve yeni sürüme eklenir.
    @Model
    final class Sohbet {
        @Attribute(.unique) var kimlik: UUID
        var baslik: String
        var olusturma: Date
        var sabit: Bool = false
        @Relationship(deleteRule: .cascade, inverse: \Mesaj.sohbet) var mesajlar: [Mesaj]

        init(baslik: String = "Yeni sohbet") {
            kimlik = UUID(); self.baslik = baslik; olusturma = .now; mesajlar = []
        }
    }

    @Model
    final class Mesaj {
        @Attribute(.unique) var kimlik: UUID
        var rolHam: String
        var metin: String
        var zaman: Date
        var sohbet: Sohbet?
        var ekVerisi: Data?

        init(rolHam: String, metin: String, sohbet: Sohbet?) {
            kimlik = UUID(); self.rolHam = rolHam; self.metin = metin; zaman = .now; self.sohbet = sohbet
        }
    }

    @Model
    final class Olgu {
        @Attribute(.unique) var kimlik: UUID
        var metin: String
        var olusturma: Date
        var kaynak: String
        var vektor: Data?
        var kategori: String?
        var onem: Int?
        var sonKullanim: Date?
        var kullanimSayisi: Int?
        var sabit: Bool?

        init(metin: String, kaynak: String = "kullanici", vektor: Data? = nil) {
            kimlik = UUID(); self.metin = metin; olusturma = .now; self.kaynak = kaynak; self.vektor = vektor
        }
    }
}

/// V2 (P3.8): `Olgu.durum` (nil/"onayli" onaylı, "bekliyor", "celiski") ve `Olgu.gecerlilikSonu`. İkisi de isteğe bağlı:
/// V1 → V2 hafif geçiştir, eski olgular onaylı ve süresiz açılır.
nonisolated enum AsistanSemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
    static var models: [any PersistentModel.Type] { [Sohbet.self, Mesaj.self, Olgu.self] }

    // Dondurulmuş V2 kopyaları (P3.5, 20 Eki 2026): saklanan alanlar V2 deposundaki model özetiyle birebir aynı kalmalı.
    // BİR DAHA DEĞİŞTİRME; yeni alan bugünkü üst düzey modellere ve yeni sürüme eklenir.
    @Model
    final class Sohbet {
        @Attribute(.unique) var kimlik: UUID
        var baslik: String
        var olusturma: Date
        var sabit: Bool = false
        @Relationship(deleteRule: .cascade, inverse: \Mesaj.sohbet) var mesajlar: [Mesaj]

        init(baslik: String = "Yeni sohbet") {
            kimlik = UUID(); self.baslik = baslik; olusturma = .now; mesajlar = []
        }
    }

    @Model
    final class Mesaj {
        @Attribute(.unique) var kimlik: UUID
        var rolHam: String
        var metin: String
        var zaman: Date
        var sohbet: Sohbet?
        var ekVerisi: Data?

        init(rolHam: String, metin: String, sohbet: Sohbet?) {
            kimlik = UUID(); self.rolHam = rolHam; self.metin = metin; zaman = .now; self.sohbet = sohbet
        }
    }

    @Model
    final class Olgu {
        @Attribute(.unique) var kimlik: UUID
        var metin: String
        var olusturma: Date
        var kaynak: String
        var vektor: Data?
        var kategori: String?
        var onem: Int?
        var sonKullanim: Date?
        var kullanimSayisi: Int?
        var sabit: Bool?
        var durum: String?
        var gecerlilikSonu: Date?

        init(metin: String, kaynak: String = "kullanici", vektor: Data? = nil) {
            kimlik = UUID(); self.metin = metin; olusturma = .now; self.kaynak = kaynak; self.vektor = vektor
        }
    }
}

/// V3 (P3.5): `Mesaj.kontrol` (denetim notu, isteğe bağlı). V2 → V3 hafif geçiştir, eski mesajlar notsuz açılır.
nonisolated enum AsistanSemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }
    static var models: [any PersistentModel.Type] { [Sohbet.self, Mesaj.self, Olgu.self] }
}

/// Hafıza geçiş planı. Yeni sürüm eklenince `schemas` sırayla büyür, `stages` her ardışık çift için bir aşama alır.
nonisolated enum AsistanGocPlani: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [AsistanSemaV1.self, AsistanSemaV2.self, AsistanSemaV3.self] }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: AsistanSemaV1.self, toVersion: AsistanSemaV2.self),
         .lightweight(fromVersion: AsistanSemaV2.self, toVersion: AsistanSemaV3.self)]
    }
}
