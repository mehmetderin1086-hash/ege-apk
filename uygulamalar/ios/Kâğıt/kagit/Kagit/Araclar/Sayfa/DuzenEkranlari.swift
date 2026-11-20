import KagitKit
import SwiftUI

// MARK: Kenar kırp

struct KenarKirpEkrani: View {
    let baglam: AracBaglami
    @State private var otomatik = true
    @State private var pay = 8.0
    @State private var ust = 10.0
    @State private var alt = 10.0
    @State private var sol = 10.0
    @State private var sag = 10.0   // mm
    @State private var aralik = ""

    var body: some View {
        let kip: KirpmaKipi = otomatik
            ? .otomatik(pay: pay)
            : .elle(ust: ust * 72 / 25.4, alt: alt * 72 / 25.4, sol: sol * 72 / 25.4, sag: sag * 72 / 25.4)
        let a = aralik
        AracSablonu(arac: AracKatalogu.arac("kenarKirp"), girdiler: baglam.girdiler, secenekler: {
            Section {
                Picker("Kırpma", selection: $otomatik) {
                    Text("Otomatik").tag(true)
                    Text("Elle").tag(false)
                }
                .pickerStyle(.segmented)
                if otomatik {
                    VStack(alignment: .leading) {
                        Text("İçerik çevresinde boşluk: \(Int(pay)) pt")
                        Slider(value: $pay, in: 0...40, step: 1)
                    }
                } else {
                    Stepper("Üst: \(Int(ust)) mm", value: $ust, in: 0...100)
                    Stepper("Alt: \(Int(alt)) mm", value: $alt, in: 0...100)
                    Stepper("Sol: \(Int(sol)) mm", value: $sol, in: 0...100)
                    Stepper("Sağ: \(Int(sag)) mm", value: $sag, in: 0...100)
                }
                SayfaAraligiAlani(metin: $aralik)
            } footer: {
                Text(otomatik ? "Beyaz kenarlar her sayfada ayrı bulunup kırpılır." : "Her kenardan verilen kadar içeri kırpılır.")
            }
        }, calistir: { girdiler, ilerleme in
            try await herDosyayaUygula(girdiler, ilerleme) { [try SayfaYerlesimi.kenarKirp($0, kip: kip, aralik: a)] }
        })
    }
}

// MARK: Kâğıt başına N sayfa

struct NUpEkrani: View {
    let baglam: AracBaglami
    @State private var adet = 4
    @State private var cizgi = true

    var body: some View {
        let n = adet, c = cizgi
        AracSablonu(arac: AracKatalogu.arac("nUp"), girdiler: baglam.girdiler, secenekler: {
            Section {
                Picker("Kâğıt başına", selection: $adet) {
                    ForEach([2, 4, 6, 9], id: \.self) { Text("\($0) sayfa").tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Sayfa kenar çizgisi", isOn: $cizgi)
            } footer: {
                Text("A4 kâğıda sığdırılır. 2 ve 6 sayfa yatay, 4 ve 9 sayfa dikey kâğıt kullanır.")
            }
        }, calistir: { girdiler, ilerleme in
            try await herDosyayaUygula(girdiler, ilerleme) { [try SayfaYerlesimi.nUp($0, sayfaBasina: n, kenarCizgisi: c)] }
        })
    }
}

// MARK: Kitapçık baskı

struct KitapcikBaskiEkrani: View {
    let baglam: AracBaglami
    @State private var katlamali = true

    var body: some View {
        let k: SayfaYerlesimi.KitapcikKipi = katlamali ? .katlamali : .ikiYukari
        AracSablonu(arac: AracKatalogu.arac("kitapcikBaski"), girdiler: baglam.girdiler, secenekler: {
            Section {
                Picker("Düzen", selection: $katlamali) {
                    Text("A4 katlamalı kitapçık").tag(true)
                    Text("A5 iki yukarı").tag(false)
                }
                .pickerStyle(.inline)
            } footer: {
                Text(katlamali
                     ? "Çift taraflı yazdırın (kısa kenardan çevir), ortadan katlayıp zımbalayın. Sayfa sayısı 4'ün katına boş sayfalarla tamamlanır."
                     : "Ardışık iki sayfa yan yana, A4 yatay kâğıda yerleştirilir.")
            }
        }, calistir: { girdiler, ilerleme in
            try await herDosyayaUygula(girdiler, ilerleme) { [try SayfaYerlesimi.kitapcikBaski($0, kip: k)] }
        })
    }
}

// MARK: Boyutlandır

struct BoyutlandirEkrani: View {
    let baglam: AracBaglami
    @State private var boyut = PDFCizim.Boyut.a4
    @State private var aralik = ""

    var body: some View {
        let b = boyut, a = aralik
        AracSablonu(arac: AracKatalogu.arac("boyutlandir"), girdiler: baglam.girdiler, secenekler: {
            Section {
                Picker("Kâğıt", selection: $boyut) {
                    ForEach([PDFCizim.Boyut.a4, .a5, .letter]) { Text($0.ad).tag($0) }
                }
                .pickerStyle(.segmented)
                SayfaAraligiAlani(metin: $aralik)
            } footer: {
                Text("İçerik oranı korunarak ortalanır; yatay sayfa yatay kalır. Bağlantılar ve form alanları korunmaz.")
            }
        }, calistir: { girdiler, ilerleme in
            try await herDosyayaUygula(girdiler, ilerleme) { [try SayfaIslemleri.boyutlandir($0, hedef: b, aralik: a)] }
        })
    }
}
