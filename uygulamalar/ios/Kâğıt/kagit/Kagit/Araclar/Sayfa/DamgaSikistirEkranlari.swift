import KagitKit
import PhotosUI
import SwiftUI

// MARK: Filigran

struct FiligranEkrani: View {
    let baglam: AracBaglami
    @State private var gorselMi = false
    @State private var metin = "TASLAK"
    @State private var punto = 60.0
    @State private var renk = Color.gray
    @State private var opaklik = 0.3
    @State private var aci = 45.0
    @State private var doseme = false
    @State private var onde = true
    @State private var olcek = 0.5
    @State private var aralik = ""
    @State private var secim: PhotosPickerItem?
    @State private var gorselVeri: Data?

    private var ayar: FiligranAyari? {
        var a: FiligranAyari
        if gorselMi {
            guard let gorselVeri else { return nil }
            a = FiligranAyari(tur: .gorsel(gorselVeri))
        } else {
            a = FiligranAyari(tur: .metin(metin))
        }
        a.punto = punto; a.renk = renk.kagitRGBA; a.opaklik = opaklik; a.aci = aci
        a.doseme = doseme; a.onde = onde; a.gorselOlcek = olcek; a.aralik = aralik
        return a
    }

    var body: some View {
        let a = ayar
        AracSablonu(arac: AracKatalogu.arac("filigran"), girdiler: baglam.girdiler,
                    hazir: a != nil && (gorselMi || !metin.trimmingCharacters(in: .whitespaces).isEmpty), secenekler: {
            Section("Filigran") {
                Picker("Tür", selection: $gorselMi) {
                    Text("Metin").tag(false)
                    Text("Görsel").tag(true)
                }
                .pickerStyle(.segmented)
                if gorselMi {
                    PhotosPicker(selection: $secim, matching: .images) {
                        Label(gorselVeri == nil ? "Görsel seç" : "Görseli değiştir", systemImage: "photo")
                    }
                    VStack(alignment: .leading) {
                        Text("Boyut: sayfa genişliğinin %\(Int(olcek * 100))'i")
                        Slider(value: $olcek, in: 0.1...1)
                    }
                } else {
                    TextField("Yazı", text: $metin)
                    VStack(alignment: .leading) {
                        Text("Punto: \(Int(punto))")
                        Slider(value: $punto, in: 12...200, step: 1)
                    }
                    ColorPicker("Renk", selection: $renk, supportsOpacity: false)
                }
            }
            Section("Görünüm") {
                VStack(alignment: .leading) {
                    Text("Opaklık: %\(Int(opaklik * 100))")
                    Slider(value: $opaklik, in: 0.05...1)
                }
                VStack(alignment: .leading) {
                    Text("Açı: \(Int(aci))°")
                    Slider(value: $aci, in: -90...90, step: 5)
                }
                Toggle("Sayfayı döşe", isOn: $doseme)
                Picker("Konum", selection: $onde) {
                    Text("İçeriğin önünde").tag(true)
                    Text("İçeriğin arkasında").tag(false)
                }
                SayfaAraligiAlani(metin: $aralik)
            }
        }, calistir: { girdiler, ilerleme in
            guard let a else { throw KagitHata.genel("Filigran görseli seçin.") }
            return try await herDosyayaUygula(girdiler, ilerleme) { [try DamgaIslemleri.filigran($0, ayar: a)] }
        })
        .onChange(of: secim) { _, yeni in
            guard let yeni else { return }
            Task { gorselVeri = try? await yeni.loadTransferable(type: Data.self) }
        }
    }
}

// MARK: Sayfa numarası

struct SayfaNumarasiEkrani: View {
    let baglam: AracBaglami
    @State private var konum = DamgaKonumu.altOrta
    @State private var bicim = "{n}"
    @State private var baslangic = 1
    @State private var atla = false
    @State private var punto = 11.0
    @State private var aralik = ""

    private var numaraAyari: NumaraAyari {
        var a = NumaraAyari()
        a.konum = konum; a.bicim = bicim; a.baslangic = baslangic; a.ilkSayfayiAtla = atla
        a.punto = punto; a.aralik = aralik
        return a
    }

    var body: some View {
        let ayar = numaraAyari
        AracSablonu(arac: AracKatalogu.arac("sayfaNumarasi"), girdiler: baglam.girdiler, secenekler: {
            Section {
                Picker("Konum", selection: $konum) { ForEach(DamgaKonumu.allCases) { Text($0.ad).tag($0) } }
                Picker("Biçim", selection: $bicim) {
                    Text("1").tag("{n}")
                    Text("1/10").tag("{n}/{N}")
                    Text("Sayfa 1").tag("Sayfa {n}")
                    Text("- 1 -").tag("- {n} -")
                }
                Stepper("Başlangıç no: \(baslangic)", value: $baslangic, in: 0...9999)
                Toggle("İlk sayfayı atla (kapak)", isOn: $atla)
                Stepper("Punto: \(Int(punto))", value: $punto, in: 6...30)
                SayfaAraligiAlani(metin: $aralik)
            }
        }, calistir: { girdiler, ilerleme in
            try await herDosyayaUygula(girdiler, ilerleme) { [try DamgaIslemleri.sayfaNumarasi($0, ayar: ayar)] }
        })
    }
}

// MARK: Üst / alt bilgi

struct UstAltBilgiEkrani: View {
    let baglam: AracBaglami
    @State private var alanlar: [DamgaKonumu: String] = [.ustSol: "{dosya}", .ustSag: "{tarih}", .altOrta: "{n} / {N}"]
    @State private var atla = false
    @State private var baslangic = 1
    @State private var punto = 10.0
    @State private var aralik = ""

    private var bilgiAyari: BilgiAyari {
        var b = BilgiAyari()
        b.alanlar = alanlar; b.ilkSayfayiAtla = atla; b.baslangic = baslangic; b.punto = punto; b.aralik = aralik
        return b
    }

    var body: some View {
        let ayar = bilgiAyari
        AracSablonu(arac: AracKatalogu.arac("ustAltBilgi"), girdiler: baglam.girdiler,
                    hazir: alanlar.values.contains { !$0.isEmpty }, secenekler: {
            Section {
                ForEach(DamgaKonumu.allCases) { k in
                    LabeledContent(k.ad) {
                        TextField("boş", text: Binding(get: { alanlar[k] ?? "" }, set: { alanlar[k] = $0 }))
                            .multilineTextAlignment(.trailing).autocorrectionDisabled()
                    }
                }
            } header: {
                Text("Alanlar")
            } footer: {
                Text("Yer tutucular: {n} sayfa no · {N} son numara · {tarih} · {dosya}")
            }
            Section {
                Toggle("İlk sayfayı atla", isOn: $atla)
                Stepper("Başlangıç no: \(baslangic)", value: $baslangic, in: 0...9999)
                Stepper("Punto: \(Int(punto))", value: $punto, in: 6...24)
                SayfaAraligiAlani(metin: $aralik)
            }
        }, calistir: { girdiler, ilerleme in
            try await herDosyayaUygula(girdiler, ilerleme) { [try DamgaIslemleri.ustAltBilgi($0, ayar: ayar)] }
        })
    }
}

// MARK: Sıkıştır

struct SikistirEkrani: View {
    let baglam: AracBaglami
    @State private var onAyar = SikistirmaOnAyari.orta
    @State private var ozel = false
    @State private var yol = SikistirmaAyari.Yol.vektor
    @State private var dpi = 150.0
    @State private var kalite = 0.7

    var body: some View {
        let ayar: SikistirmaAyari = ozel
            ? SikistirmaAyari(yol: yol, dpi: Int(dpi), jpegKalite: kalite)
            : .onAyar(onAyar)
        AracSablonu(arac: AracKatalogu.arac("sikistir"), girdiler: baglam.girdiler, secenekler: {
            Section {
                Toggle("Özel ayar", isOn: $ozel)
                if ozel {
                    Picker("Yöntem", selection: $yol) {
                        Text("Metni koru (vektör)").tag(SikistirmaAyari.Yol.vektor)
                        Text("Sayfayı görüntüye çevir").tag(SikistirmaAyari.Yol.rasterlestir)
                    }
                    if yol == .rasterlestir {
                        VStack(alignment: .leading) {
                            Text("Çözünürlük: \(Int(dpi)) dpi")
                            Slider(value: $dpi, in: 50...300, step: 10)
                        }
                        VStack(alignment: .leading) {
                            Text("JPEG kalitesi: %\(Int(kalite * 100))")
                            Slider(value: $kalite, in: 0.2...0.95)
                        }
                    }
                } else {
                    Picker("Ön ayar", selection: $onAyar) {
                        ForEach(SikistirmaOnAyari.allCases) { Text($0.ad).tag($0) }
                    }
                    .pickerStyle(.inline)
                }
            } footer: {
                Text(ozel && yol == .rasterlestir || (!ozel && onAyar == .yuksek)
                     ? "Sayfalar görüntüye çevrilir: taranmış belgelerde en küçük boyut, ama metin seçilemez olur."
                     : "Metin ve çizimler vektör kalır; görseller küçültülür. Çıktı büyükse özgün dosya korunur.")
            }
        }, calistir: { girdiler, ilerleme in
            let sonuclar = try await arkaPlanda { () throws -> [SikistirmaSonucu] in
                var s: [SikistirmaSonucu] = []
                for (i, u) in girdiler.enumerated() {
                    try iptalDenetle()
                    s.append(try Sikistirma.sikistir(u, ayar: ayar))
                    ilerleme(Double(i + 1) / Double(girdiler.count))
                }
                return s
            }
            let kuculenler = sonuclar.filter(\.kuculdu).map(\.cikti)
            guard !kuculenler.isEmpty else { throw KagitHata.genel(sonuclar.first?.ileti ?? "Sıkıştırılamadı.") }
            return kuculenler
        })
    }
}
