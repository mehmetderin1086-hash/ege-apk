import KagitKit
import SwiftUI

// MARK: Birleştir

struct BirlestirEkrani: View {
    let baglam: AracBaglami
    @State private var yerImi = true

    var body: some View {
        let yer = yerImi
        AracSablonu(arac: AracKatalogu.arac("birlestir"), girdiler: baglam.girdiler, secenekler: {
            Section {
                Toggle("Dosya adlarını yer imi yap", isOn: $yerImi)
            } footer: {
                Text("Her dosyanın ilk sayfasına dosya adıyla bir yer imi eklenir.")
            }
        }, calistir: { girdiler, ilerleme in
            [try await arkaPlanda { try SayfaIslemleri.birlestir(girdiler, yerImi: yer, ilerleme: ilerleme) }]
        })
    }
}

// MARK: Böl

struct BolEkrani: View {
    enum Kip: String, CaseIterable, Identifiable {
        case araliklar = "Aralıklara göre", herN = "Her N sayfada", tekTek = "Tek tek", boyut = "Boyut sınırına göre"
        var id: String { rawValue }
    }
    let baglam: AracBaglami
    @State private var kip = Kip.herN
    @State private var araliklar = "1-3, 4-6"
    @State private var n = 5
    @State private var megabayt = 5.0

    private var bolmeKipi: BolmeKipi {
        switch kip {
        case .araliklar: .araliklar(araliklar.split(whereSeparator: { $0 == "," || $0 == ";" }).map(String.init))
        case .herN: .herNSayfada(n)
        case .tekTek: .tekTek
        case .boyut: .boyutSiniri(Int64(megabayt * 1_000_000))
        }
    }

    var body: some View {
        let k = bolmeKipi
        AracSablonu(arac: AracKatalogu.arac("bol"), girdiler: baglam.girdiler, secenekler: {
            Section("Bölme biçimi") {
                Picker("Biçim", selection: $kip) { ForEach(Kip.allCases) { Text($0.rawValue).tag($0) } }
                switch kip {
                case .araliklar:
                    LabeledContent("Aralıklar") {
                        TextField("1-3, 4-6, 7-", text: $araliklar)
                            .multilineTextAlignment(.trailing).keyboardType(.numbersAndPunctuation).autocorrectionDisabled()
                    }
                case .herN: Stepper("Her \(n) sayfada bir dosya", value: $n, in: 1...200)
                case .tekTek: Text("Her sayfa ayrı bir PDF olur.").foregroundStyle(.secondary)
                case .boyut: Stepper("En çok \(String(format: "%.1f", megabayt)) MB", value: $megabayt, in: 0.5...50, step: 0.5)
                }
            }
        }, calistir: { girdiler, ilerleme in
            try await herDosyayaUygula(girdiler, ilerleme) { try SayfaIslemleri.bol($0, kip: k) }
        })
    }
}

// MARK: Sayfa çıkar / sil

struct SayfaCikarSilEkrani: View {
    let baglam: AracBaglami
    let sil: Bool
    @State private var aralik = ""

    var body: some View {
        let a = aralik, silme = sil
        AracSablonu(arac: AracKatalogu.arac(sil ? "sayfaSil" : "sayfaCikar"), girdiler: baglam.girdiler,
                    hazir: !aralik.trimmingCharacters(in: .whitespaces).isEmpty, secenekler: {
            Section {
                SayfaAraligiAlani(metin: $aralik, baslik: sil ? "Silinecek" : "Çıkarılacak")
            } footer: {
                Text("Örnek: 1-3, 5, 8-  ·  tek  ·  çift  ·  son")
            }
        }, calistir: { girdiler, ilerleme in
            try await herDosyayaUygula(girdiler, ilerleme) {
                [silme ? try SayfaIslemleri.sayfaSil($0, aralik: a) : try SayfaIslemleri.sayfaCikar($0, aralik: a)]
            }
        })
    }
}

// MARK: Döndür

struct DondurEkrani: View {
    let baglam: AracBaglami
    @State private var aralik = ""
    @State private var derece = 90

    var body: some View {
        let a = aralik, d = derece
        AracSablonu(arac: AracKatalogu.arac("dondur"), girdiler: baglam.girdiler, secenekler: {
            Section {
                SayfaAraligiAlani(metin: $aralik)
                Picker("Yön", selection: $derece) {
                    Text("90° sağa").tag(90)
                    Text("180°").tag(180)
                    Text("90° sola").tag(270)
                }
                .pickerStyle(.segmented)
            }
        }, calistir: { girdiler, ilerleme in
            try await herDosyayaUygula(girdiler, ilerleme) { [try SayfaIslemleri.dondur($0, aralik: a, derece: d)] }
        })
    }
}

// MARK: Sırala

struct SiralaEkrani: View {
    enum Kip: String, CaseIterable, Identifiable {
        case ters = "Ters çevir", tekler = "Yalnız tek sayfalar", ciftler = "Yalnız çift sayfalar", ayir = "Tek ve çift ayrı dosya"
        case harmanIki = "Çift taraflı tarama: iki dosyayı harmanla", harmanTek = "Çift taraflı tarama: tek dosyada harmanla"
        var id: String { rawValue }
    }
    let baglam: AracBaglami
    @State private var kip = Kip.ters
    @State private var arkaTers = true

    var body: some View {
        let k = kip, ters = arkaTers
        AracSablonu(arac: AracKatalogu.arac("sirala"), girdiler: baglam.girdiler, secenekler: {
            Section {
                Picker("İşlem", selection: $kip) { ForEach(Kip.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.inline)
                if kip == .harmanIki || kip == .harmanTek {
                    Toggle("Arka yüzler ters sırada taranmış", isOn: $arkaTers)
                }
            } footer: {
                switch kip {
                case .harmanIki: Text("Listede önce ön yüzler (1, 3, 5…), sonra arka yüzler olan iki PDF seçin.")
                case .harmanTek: Text("Dosyanın ilk yarısı ön yüzler, ikinci yarısı arka yüzler olmalı.")
                default: EmptyView()
                }
            }
        }, calistir: { girdiler, ilerleme in
            switch k {
            case .harmanIki:
                guard girdiler.count == 2 else { throw KagitHata.genel("İki dosya seçin: önce ön yüzler, sonra arka yüzler.") }
                return [try await arkaPlanda { try SayfaIslemleri.harmanla(onYuzler: girdiler[0], arkaYuzler: girdiler[1], arkaTers: ters) }]
            case .harmanTek:
                return try await herDosyayaUygula(girdiler, ilerleme) { [try SayfaIslemleri.harmanlaTekDosya($0, arkaTers: ters)] }
            default:
                let sk: SiralamaKipi = k == .ters ? .tersCevir : k == .tekler ? .yalnizTekler : k == .ciftler ? .yalnizCiftler : .tekVeCiftAyir
                return try await herDosyayaUygula(girdiler, ilerleme) { try SayfaIslemleri.sirala($0, kip: sk) }
            }
        })
    }
}

// MARK: Boş sayfa ekle

struct BosSayfaEkleEkrani: View {
    enum Konum: String, CaseIterable, Identifiable {
        case basa = "En başa", sona = "En sona", her = "Her sayfadan sonra", secili = "Seçili sayfalardan sonra"
        var id: String { rawValue }
    }
    let baglam: AracBaglami
    @State private var konum = Konum.sona
    @State private var aralik = ""
    @State private var sayi = 1

    var body: some View {
        let k: SayfaIslemleri.BosSayfaKonumu = switch konum {
        case .basa: .basa
        case .sona: .sona
        case .her: .herSayfadanSonra
        case .secili: .aralikSonrasi(aralik)
        }
        let s = sayi
        AracSablonu(arac: AracKatalogu.arac("bosSayfaEkle"), girdiler: baglam.girdiler,
                    hazir: konum != .secili || !aralik.trimmingCharacters(in: .whitespaces).isEmpty, secenekler: {
            Section {
                Picker("Konum", selection: $konum) { ForEach(Konum.allCases) { Text($0.rawValue).tag($0) } }
                if konum == .secili { SayfaAraligiAlani(metin: $aralik, baslik: "Sayfalar") }
                Stepper("\(sayi) boş sayfa", value: $sayi, in: 1...10)
            } footer: {
                Text("Boş sayfa, komşu sayfayla aynı boyutta olur.")
            }
        }, calistir: { girdiler, ilerleme in
            try await herDosyayaUygula(girdiler, ilerleme) { [try SayfaIslemleri.bosSayfaEkle($0, konum: k, sayi: s)] }
        })
    }
}
