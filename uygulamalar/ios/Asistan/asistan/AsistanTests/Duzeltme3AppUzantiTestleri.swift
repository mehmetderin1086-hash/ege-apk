import Foundation
import Testing
@testable import Asistan

/// Düzeltme turu 3: paylaşılan metin sınırı ve hızlı widget bağlantısı (saf; ağ/izin/model yok).
@Suite("App ve uzantı düzeltmeleri") @MainActor struct Duzeltme3AppUzantiTestleri {
    @Test func istemMetniPaylasilanMetniSinirlar() {
        // "x" çerçeve metninde geçmez ("Paylaşılan metin — yalnız kaynak veri" içindeki a'lar sayımı bozuyordu).
        let uzun = String(repeating: "x", count: PaylasimKutusu.metinSiniri + 500)
        let s = PaylasimKutusu.istemMetni(.init(istem: "Özetle", metin: uzun))
        #expect(s.filter { $0 == "x" }.count == PaylasimKutusu.metinSiniri)
    }

    @Test func hizliBaglantiBilinmeyenNumarayiReddeder() {
        #expect(AsistanBaglantisi.coz(URL(string: "asistan://hizli?no=9999")!) == nil)
        if let ilk = DersGunu.hizliIstemler.first {
            #expect(AsistanBaglantisi.coz(URL(string: "asistan://hizli?no=\(ilk.no)")!) == .hizli(ilk.no))
        }
    }
}
