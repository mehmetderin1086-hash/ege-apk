import Foundation
import Testing
@testable import Asistan

/// Arayüz inceleme düzeltmeleri: taslak geçişi, eylem kartı zamanlayıcısı, ayar dizini konumları.
@Suite("Arayüz düzeltmeleri") @MainActor
struct Duzeltme_ArayuzTurTestleri {

    @Test func eskiKayitAcilincaYeniSohbetTaslagiTasinmaz() {
        let eski = UUID()
        let r = SohbetEkrani.taslakGecisi([:], eski: nil, yeni: eski, metin: "yeni sohbette yazılan", yeniKayitTaze: false)
        #expect(r.metin == "", "eski sohbete yeni sohbetin taslağı taşınmamalı")
        #expect(r.taslaklar[nil] == "yeni sohbette yazılan")
    }

    @Test func tazeKayitDonusuMetniKorur() {
        let y = UUID()
        let r = SohbetEkrani.taslakGecisi([:], eski: nil, yeni: y, metin: "yazılan", yeniKayitTaze: true)
        #expect(r.metin == "yazılan")
    }

    @Test func eylemKartiZamanCizelgesi() {
        let simdi = Date(timeIntervalSince1970: 1_000_000)
        var k = EylemKaydi(tur: .alarm, baslik: "b", ozet: "", kimlikler: ["x"])
        k.zaman = simdi.addingTimeInterval(-700)
        #expect(EylemKarti.zamanCizelgesi(k, simdi: simdi).isEmpty, "süresi geçmiş kart zamanlayıcı taşımaz")
        k.zaman = simdi.addingTimeInterval(-590)
        let c = EylemKarti.zamanCizelgesi(k, simdi: simdi)
        #expect(c.first == simdi)
        #expect(c.last == simdi.addingTimeInterval(10), "son çizim bitiş anında")
        k.zaman = simdi
        let t = EylemKarti.zamanCizelgesi(k, simdi: simdi)
        #expect(t.count == 41 && t.last == simdi.addingTimeInterval(600))
    }

    @Test func kokDizinOgeleriAyarlarEtiketiTasir() {
        for id in ["kalite", "sistem-aramasi", "surus-kipi", "hakkinda"] {
            let o = AyarDizini.hepsi.first { $0.id == id }
            #expect(o?.etiket == "Ayarlar", "kök öğe: \(id)")
        }
        #expect(AyarDizini.ara("carplay").contains { $0.hedef == .surusKipi })
        #expect(AyarDizini.ara("sürüm").contains { $0.hedef == .hakkinda })
    }
}
