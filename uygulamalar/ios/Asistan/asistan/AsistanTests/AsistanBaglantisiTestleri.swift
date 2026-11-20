import Foundation
import Testing
@testable import Asistan

@Suite("Asistan dış bağlantıları") @MainActor
struct AsistanBaglantisiTestleri {
    @Test func sistemEkranlariCozulur() {
        #expect(AsistanBaglantisi.coz(URL(string: "asistan://live")!) == .live)
        #expect(AsistanBaglantisi.coz(URL(string: "asistan://atolye")!) == .ekran(.atolye))
        #expect(AsistanBaglantisi.coz(URL(string: "asistan://indirmeler")!) == .ekran(.indirmeler))
        #expect(AsistanBaglantisi.coz(URL(string: "asistan://telefon")!) == .ekran(.telefon))
        #expect(AsistanBaglantisi.coz(URL(string: "asistan://donustur")!) == .ekran(.donustur))
        #expect(AsistanBaglantisi.coz(URL(string: "asistan://arsiv")!) == .ekran(.arsiv))
        #expect(AsistanBaglantisi.coz(URL(string: "asistan://uretkenlik")!) == .ekran(.uretkenlik))
    }

    @Test func taslakSadeceAsistanBaglantisindanAlinir() {
        let metin = "Merhaba dünya & plan"
        var bilesen = URLComponents(string: "asistan://taslak")!
        bilesen.queryItems = [URLQueryItem(name: "metin", value: metin)]
        #expect(AsistanBaglantisi.coz(bilesen.url!) == .taslak(metin))
        #expect(AsistanBaglantisi.coz(URL(string: "https://asistan/taslak?metin=x")!) == nil)
        #expect(AsistanBaglantisi.coz(URL(string: "asistan://taslak")!) == nil)
    }
}
