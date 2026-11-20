import SwiftUI

// Modül C: güvenlik ve tarama araçları.
extension AracKatalogu {
    static var guvenlikAraclari: [Arac] {
        [ParolaKoyEkrani.arac, ParolaKaldirEkrani.arac, KarartmaEkrani.arac, UstVeriEkrani.arac]
    }
    static var taramaAraclari: [Arac] {
        [TaraBaslatici.arac, OCREkrani.arac, MetinCikarEkrani.arac]
    }
}
