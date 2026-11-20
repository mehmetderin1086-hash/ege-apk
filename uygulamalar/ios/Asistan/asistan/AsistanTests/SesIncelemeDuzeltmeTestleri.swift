import Foundation
import Testing
import UIKit
@testable import Asistan

/// Ses alanı inceleme düzeltmeleri (saf mantık; ağ, izin ve model yok).
@MainActor
@Suite("Ses inceleme düzeltmeleri")
struct SesIncelemeDuzeltmeTestleri {

    @Test func kayitSurerkenOturumBirakilmaz() {
        #expect(!SesOturumu.oturumBirakilir(dinleyiciCalisiyor: false, konusuyor: false, sozKesmeCalisiyor: false,
                                            gercekZamanli: false, beyinBosta: true, uyandirmaBekliyor: false,
                                            kayitSuruyor: true))
        #expect(SesOturumu.oturumBirakilir(dinleyiciCalisiyor: false, konusuyor: false, sozKesmeCalisiyor: false,
                                           gercekZamanli: false, beyinBosta: true, uyandirmaBekliyor: false,
                                           kayitSuruyor: false))
    }

    @Test func herSeferindeSorAraciLivedaCalistirilmaz() {
        #expect(CanliAracKoprusu.onayEngeli(.sor) == CanliAracKoprusu.onayGerekenArac)
        #expect(CanliAracKoprusu.onayEngeli(.otomatik) == nil)
        #expect(CanliAracKoprusu.onayEngeli(.kapali) == nil)
    }

    @Test func sahneAdlari() {
        #expect(SesOturumu.sahneAdi(.active) == "active")
        #expect(SesOturumu.sahneAdi(.inactive) == "inactive")
        #expect(SesOturumu.sahneAdi(.background) == "background")
    }
}
