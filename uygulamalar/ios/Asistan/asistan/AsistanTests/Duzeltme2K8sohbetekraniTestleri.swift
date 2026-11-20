import Testing
import Foundation
@testable import Asistan

@Suite("K8-sohbet-ekrani düzeltmeleri")
@MainActor
struct Duzeltme2K8sohbetekraniTestleri {

    // MARK: 35/96/105 — gönderim penceresinde araya giren tur: girdi geri konur

    @Test("Geri konan metin, bu arada yazılanı ezmez")
    func girdiBirlestirme() {
        #expect(SohbetEkrani.girdiyiBirlestir(eski: "Mitoz nedir?", simdiki: "") == "Mitoz nedir?")
        #expect(SohbetEkrani.girdiyiBirlestir(eski: "", simdiki: "yeni") == "yeni")
        #expect(SohbetEkrani.girdiyiBirlestir(eski: "  ", simdiki: "yeni") == "yeni")
        #expect(SohbetEkrani.girdiyiBirlestir(eski: "eski", simdiki: " \n") == "eski")
        #expect(SohbetEkrani.girdiyiBirlestir(eski: "eski", simdiki: "yeni") == "eski\nyeni")
    }

    @Test("Geri konan ekler önce gelir, sınır aşılmaz")
    func ekBirlestirme() {
        #expect(SohbetEkrani.ekleriBirlestir(eski: [1, 2, 3], simdiki: [9], sinir: 8) == [1, 2, 3, 9])
        #expect(SohbetEkrani.ekleriBirlestir(eski: [1, 2, 3], simdiki: [9], sinir: 3) == [1, 2, 3])
        #expect(SohbetEkrani.ekleriBirlestir(eski: [Int](), simdiki: [4, 5], sinir: 8) == [4, 5])
        #expect(SohbetEkrani.ekleriBirlestir(eski: [1], simdiki: [2], sinir: -2).isEmpty)
    }

    // MARK: 98 — Kestirme istisnası 4000 karakteri aşan görevde de eşleşir

    @Test("Kestirmenin beklediği görev bağlantı biçimiyle (kırp + 4000) karşılaştırılır")
    func kestirmeEslesmesi() {
        let uzun = String(repeating: "a", count: 4_500)
        let baglantidan = String(uzun.prefix(4_000))   // AsistanBaglantisi.coz böyle keser
        #expect(SohbetEkrani.kestirmeyiBekliyor(beklenen: "  \(uzun)\n", metin: baglantidan))
        #expect(SohbetEkrani.kestirmeyiBekliyor(beklenen: " Hava nasıl? ", metin: "Hava nasıl?"))
        #expect(!SohbetEkrani.kestirmeyiBekliyor(beklenen: nil, metin: "Hava nasıl?"))
        #expect(!SohbetEkrani.kestirmeyiBekliyor(beklenen: "Başka görev", metin: "Hava nasıl?"))
    }

    @Test("Kısa görevde bağlantı biçimi metni değiştirmez")
    func kestirmeKisaGorev() {
        let tam = String(repeating: "b", count: 4_000)
        #expect(SohbetEkrani.kestirmeyiBekliyor(beklenen: tam, metin: tam))
        #expect(!SohbetEkrani.kestirmeyiBekliyor(beklenen: tam + "c", metin: tam + "c"))   // bağlantı 4000'de keser
    }

    // MARK: 100/102/106 — arşiv araması önbellekli, Türkçe harf duyarsız

    @Test("Önbellekli arşiv araması başlık ve içerikte eşleşir")
    func arsivOnbellekliArama() {
        let a = UUID(), b = UUID(), c = UUID()
        let basliklar = [(a, "Biyoloji sınavı"), (b, "Alışveriş"), (c, "Notlar")]
        let icerik = [a: GecmisArama.normalize("ilk\nMitoz bölünme"), b: GecmisArama.normalize("süt\nekmek"), c: ""]
        let q = { (s: String) in GecmisArama.normalize(s).trimmingCharacters(in: .whitespaces) }
        #expect(GecmisEkrani.eslesenler(basliklar, icerik: icerik, sorgu: q("SINAV")) == [a])
        #expect(GecmisEkrani.eslesenler(basliklar, icerik: icerik, sorgu: q("mitoz")) == [a])
        #expect(GecmisEkrani.eslesenler(basliklar, icerik: icerik, sorgu: q("EKMEK")) == [b])
        #expect(GecmisEkrani.eslesenler(basliklar, icerik: icerik, sorgu: q("mayoz")).isEmpty)
        #expect(GecmisEkrani.eslesenler(basliklar, icerik: icerik, sorgu: "") == [a, b, c])
    }

    @Test("Önbellekte olmayan sohbet yalnız başlıkla eşleşir")
    func arsivOnbellekEksik() {
        let a = UUID()
        #expect(GecmisEkrani.eslesenler([(a, "Fotosentez")], icerik: [:], sorgu: "fotosentez") == [a])
        #expect(GecmisEkrani.eslesenler([(a, "X")], icerik: [:], sorgu: "fotosentez").isEmpty)
    }

    @Test("Önbellekli arama eski eslesir kuralıyla aynı sonucu verir (Türkçe sorgular)")
    func arsivEskiKuralUyumu() {
        let a = UUID()
        let mesajlar = ["Hücre zarı", "Işık tepkimeleri"]
        let icerik = [a: GecmisArama.normalize(mesajlar.joined(separator: "\n"))]
        for sorgu in ["hücre", "HÜCRE", "tepkime", "zar", "yok"] {   // yerel ayardan bağımsız (I/ı içermeyen) sorgular
            let q = GecmisArama.normalize(sorgu).trimmingCharacters(in: .whitespaces)
            let yeni = GecmisEkrani.eslesenler([(a, "Başlık")], icerik: icerik, sorgu: q).contains(a)
            #expect(yeni == GecmisEkrani.eslesir(baslik: "Başlık", metinler: mesajlar, sorgu: sorgu), "sorgu: \(sorgu)")
        }
    }

    // MARK: 108 — eksik fotoğraf notu yalnız eksik varken yazılır (sınır notu korunur)

    @Test("Eksik yoksa sınır notu aynen kalır; eksik varsa öne eklenir")
    func eksikNotuSinirNotuyla() {
        let sinir = "Bir mesaja en fazla 8 görsel eklenir; fazlası eklenmedi."
        #expect(SohbetEkrani.eksikFotoNotu(0, onceki: nil) == nil)
        #expect(SohbetEkrani.eksikFotoNotu(0, onceki: sinir) == sinir)
        #expect(SohbetEkrani.eksikFotoNotu(2, onceki: sinir)?.hasPrefix("2 fotoğraf eklenemedi") == true)
        #expect(SohbetEkrani.eksikFotoNotu(2, onceki: sinir)?.hasSuffix(sinir) == true)
    }
}
