import Foundation
import Testing
import EventKit
import Contacts
import AVFoundation
import Speech
import CoreLocation
import Photos
import UserNotifications
import AlarmKit
@testable import Asistan

/// P1.10: izin reddinde sohbet kartı (`MesajEki.Tur.izin`) ve Ayarlar > İzinler. Yalnız saf eşlemeler; sistem sorusu açılmaz.
@Suite("P1.10 izin kartı") @MainActor
struct Gelistirme_P1_10_IzinKartiTestleri {

    @Test func eventKitEslemesi() {
        #expect(IzinDurumu.ek(.denied) == .reddedildi)
        #expect(IzinDurumu.ek(.restricted) == .reddedildi)
        #expect(IzinDurumu.ek(.notDetermined) == .sorulmadi)
        #expect(IzinDurumu.ek(.writeOnly) == .kisitli)
        #expect(IzinDurumu.ek(.fullAccess) == .verildi)
    }

    @Test func kisilerEslemesi() {
        #expect(IzinDurumu.cn(.limited) == .kisitli)
        #expect(IzinDurumu.cn(.authorized) == .verildi)
        #expect(IzinDurumu.cn(.denied) == .reddedildi)
        #expect(IzinDurumu.cn(.notDetermined) == .sorulmadi)
    }

    @Test func digerEslemeler() {
        #expect(IzinDurumu.kayit(.granted) == .verildi)
        #expect(IzinDurumu.kayit(.denied) == .reddedildi)
        #expect(IzinDurumu.kayit(.undetermined) == .sorulmadi)
        #expect(IzinDurumu.konusma(.restricted) == .reddedildi)
        #expect(IzinDurumu.konusma(.authorized) == .verildi)
        #expect(IzinDurumu.konum(.authorizedWhenInUse) == .verildi)
        #expect(IzinDurumu.konum(.notDetermined) == .sorulmadi)
        #expect(IzinDurumu.kamera(.denied) == .reddedildi)
        #expect(IzinDurumu.foto(.limited) == .kisitli)
        #expect(IzinDurumu.alarm(.authorized) == .verildi)
        #expect(IzinDurumu.alarm(.notDetermined) == .sorulmadi)
        #expect(IzinDurumu.bildirim(.provisional) == .verildi)
        #expect(IzinDurumu.bildirim(.denied) == .reddedildi)
    }

    @Test func dugmeMetinleri() {
        #expect(IzinDurumu.dugme(.sorulmadi) == "İzin ver")
        #expect(IzinDurumu.dugme(.reddedildi) == "Ayarlar'ı aç")
        #expect(IzinDurumu.dugme(.kisitli) == "Ayarlar'ı aç")
        #expect(IzinDurumu.dugme(.verildi) == nil)
    }

    @Test func turAdlariBosDegilVeTekil() {
        #expect(IzinTuru.allCases.count == 10)
        #expect(IzinTuru.allCases.allSatisfy { !$0.ad.isEmpty && !$0.simge.isEmpty })
        #expect(Set(IzinTuru.allCases.map(\.ad)).count == IzinTuru.allCases.count)
    }

    @Test func kaliciGidisDonus() throws {
        let veri = EkKalici.kodla([MesajEki(tur: .izin(.kisiler))])
        let ham = String(decoding: try #require(veri), as: UTF8.self)
        #expect(ham.contains("\"t\":\"izin\""))
        let geri = EkKalici.coz(veri)
        guard geri.count == 1, case .izin(let t) = geri[0].tur else { Issue.record("izin kartı çözülmedi"); return }
        #expect(t == .kisiler)
    }

    @Test func bilinmeyenIzinAtlanir() {
        let veri = Data(#"[{"t":"izin","ad":"uydu"},{"t":"izin"},{"t":"izin","ad":"takvim"},{"t":"kaynak","adresler":["https://example.com"]}]"#.utf8)
        let ekler = EkKalici.coz(veri)
        #expect(ekler.count == 2)
        if case .izin(let t) = ekler.first?.tur { #expect(t == .takvim) } else { Issue.record("takvim izin kartı") }
    }

    @Test func ekDefteriAyniIzniBirKezEkler() {
        let d = EkDefteri()
        d.ekle(MesajEki(tur: .izin(.takvim)))
        d.ekle(MesajEki(tur: .izin(.takvim)))
        d.ekle(MesajEki(tur: .izin(.kisiler)))
        let ekler = d.al()
        #expect(ekler.count == 2)
        #expect(ekler.map(\.tur) == [.izin(.takvim), .izin(.kisiler)])
        // Defter boşaldıktan sonra (yeni tur) yeniden eklenebilir.
        d.ekle(MesajEki(tur: .izin(.takvim)))
        #expect(d.bekleyen.count == 1)
    }
}
