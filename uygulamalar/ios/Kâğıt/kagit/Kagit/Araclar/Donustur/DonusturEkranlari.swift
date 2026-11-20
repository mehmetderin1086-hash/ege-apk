import KagitKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: Görselden PDF

struct GorseldenPDFEkrani: View {
    let baglam: AracBaglami
    @State private var boyut = GorselPDFAyari.SayfaBoyutu.a4
    @State private var yon = GorselPDFAyari.Yon.otomatik
    @State private var kenar = 0.0
    @State private var sigdir = true
    @State private var kalite = 0.85

    var body: some View {
        let a = ayar
        AracSablonu(arac: AracKatalogu.arac("gorseldenPDF"), girdiler: baglam.girdiler, secenekler: {
            Section {
                Picker("Sayfa boyutu", selection: $boyut) { ForEach(GorselPDFAyari.SayfaBoyutu.allCases) { Text($0.ad).tag($0) } }
                if boyut != .gorselBoyutu {
                    Picker("Yön", selection: $yon) { ForEach(GorselPDFAyari.Yon.allCases) { Text($0.ad).tag($0) } }
                    Picker("Yerleşim", selection: $sigdir) {
                        Text("Sığdır").tag(true)
                        Text("Doldur (kırp)").tag(false)
                    }
                }
                Stepper("Kenar boşluğu: \(Int(kenar)) pt", value: $kenar, in: 0...100, step: 4)
                VStack(alignment: .leading) {
                    Text("JPEG kalitesi: %\(Int(kalite * 100))")
                    Slider(value: $kalite, in: 0.3...1)
                }
            } footer: {
                Text("Fotoğraflar, ekran görüntüleri ve HEIC dosyaları desteklenir. Her görsel bir sayfa olur.")
            }
        }, calistir: { girdiler, ilerleme in
            [try await arkaPlanda { try GorselPDF.gorseldenPDF(girdiler, ayar: a, ilerleme: ilerleme) }]
        })
    }

    private var ayar: GorselPDFAyari {
        var a = GorselPDFAyari()
        a.sayfaBoyutu = boyut; a.yon = yon; a.kenarBosluk = kenar; a.sigdir = sigdir; a.jpegKalite = kalite
        return a
    }
}

// MARK: Belgeden PDF (TXT, RTF, HTML, Markdown; Office → sunucu)

struct BelgedenPDFEkrani: View {
    let baglam: AracBaglami

    var body: some View {
        AracSablonu(arac: AracKatalogu.arac("belgedenPDF"), girdiler: baglam.girdiler, secenekler: {
            Section {
                Text("TXT, RTF, HTML ve Markdown cihazda dönüştürülür. DOCX, XLSX, PPTX ve ODT dosyaları sunucuda (LibreOffice) dönüştürülür.")
                    .font(.footnote).foregroundStyle(.secondary)
                SunucuNotu()
            }
        }, calistir: { girdiler, ilerleme in
            let istemci = pdfStudioIstemcisi()
            let sunucuAcik = Ayarlar.paylasilan.sunucuEtkin
            var sonuc: [URL] = []
            for (i, u) in girdiler.enumerated() {
                try Task.checkCancellation()
                if MetindenPDF.yerelMi(u) {
                    sonuc.append(try await MetindenPDF.cevir(u))
                } else if MetindenPDF.sunucuUzantilari.contains(u.pathExtension.lowercased()) {
                    guard sunucuAcik else { throw sunucuKapaliHatasi("“.\(u.pathExtension.lowercased())” dosyasını PDF'e çevirmek") }
                    sonuc.append(try await istemci.officedenPDF(u))
                } else {
                    throw KagitHata.desteklenmiyor("“\(u.lastPathComponent)” türü PDF'e çevrilemez.")
                }
                ilerleme(Double(i + 1) / Double(girdiler.count))
            }
            return sonuc
        })
    }
}

// MARK: Boş PDF

struct BosPDFEkrani: View {
    let baglam: AracBaglami
    @State private var boyut = PDFCizim.Boyut.a4
    @State private var yatay = false
    @State private var sayfa = 1
    @State private var desen = BosPDFDeseni.cizgili

    var body: some View {
        let b = boyut, y = yatay, s = sayfa, d = desen
        AracSablonu(arac: AracKatalogu.arac("bosPDF"), girdiler: [], secenekler: {
            Section {
                Picker("Boyut", selection: $boyut) { ForEach(PDFCizim.Boyut.allCases) { Text($0.ad).tag($0) } }
                Picker("Yön", selection: $yatay) {
                    Text("Dikey").tag(false)
                    Text("Yatay").tag(true)
                }
                .pickerStyle(.segmented)
                Stepper("\(sayfa) sayfa", value: $sayfa, in: 1...200)
                Picker("Desen", selection: $desen) { ForEach(BosPDFDeseni.allCases) { Text($0.ad).tag($0) } }
            }
        }, calistir: { _, _ in
            [try await arkaPlanda { try GorselPDF.bosPDF(boyut: b, yatay: y, sayfaSayisi: s, desen: d, ad: "\(d.ad) PDF") }]
        })
    }
}

// MARK: PDF'ten görsele

struct PDFtenGorseleEkrani: View {
    let baglam: AracBaglami
    @State private var bicim = GorselBicimi.png
    @State private var dpi = 150.0
    @State private var aralik = ""
    @State private var kalite = 0.85
    @State private var zip = false
    @State private var fotograflar = false

    var body: some View {
        let b = bicim, d = Int(dpi), a = aralik, k = kalite, z = zip, foto = fotograflar
        AracSablonu(arac: AracKatalogu.arac("pdftenGorsele"), girdiler: baglam.girdiler, kitapligaKaydet: zip, secenekler: {
            Section {
                Picker("Biçim", selection: $bicim) { ForEach(GorselBicimi.allCases) { Text($0.ad).tag($0) } }.pickerStyle(.segmented)
                VStack(alignment: .leading) {
                    Text("Çözünürlük: \(Int(dpi)) dpi")
                    Slider(value: $dpi, in: 72...300, step: 6)
                }
                if bicim == .jpeg {
                    VStack(alignment: .leading) {
                        Text("Kalite: %\(Int(kalite * 100))")
                        Slider(value: $kalite, in: 0.3...1)
                    }
                }
                SayfaAraligiAlani(metin: $aralik)
                Toggle("Tek ZIP dosyası olarak", isOn: $zip)
                Toggle("Fotoğraflar'a kaydet", isOn: $fotograflar)
            }
        }, calistir: { girdiler, ilerleme in
            let sonuc = try await herDosyayaUygula(girdiler, ilerleme) {
                try PDFGorsel.pdftenGorsele($0, bicim: b, dpi: d, aralik: a, kalite: k, zip: z)
            }
            if foto {
                let resimler = z ? [] : sonuc
                if !resimler.isEmpty { try await FotoKaydet.kaydet(resimler) }
            }
            return sonuc
        })
    }
}

// MARK: Gömülü görselleri çıkar

struct PDFtenGorselleriCikarEkrani: View {
    let baglam: AracBaglami
    @State private var bicim = GorselBicimi.png
    @State private var aralik = ""
    @State private var zip = true

    var body: some View {
        let b = bicim, a = aralik, z = zip
        AracSablonu(arac: AracKatalogu.arac("pdftenGorselleriCikar"), girdiler: baglam.girdiler, kitapligaKaydet: zip, secenekler: {
            Section {
                Picker("Biçim", selection: $bicim) { ForEach(GorselBicimi.allCases) { Text($0.ad).tag($0) } }.pickerStyle(.segmented)
                SayfaAraligiAlani(metin: $aralik)
                Toggle("Tek ZIP dosyası olarak", isOn: $zip)
            } footer: {
                Text("PDF'in içine gömülü fotoğraf ve resimler özgün çözünürlüğünde çıkarılır.")
            }
        }, calistir: { girdiler, ilerleme in
            try await herDosyayaUygula(girdiler, ilerleme) { try PDFGorsel.pdftenGorselleriCikar($0, aralik: a, bicim: b, zip: z) }
        })
    }
}

// MARK: Word / Excel (yerel ya da sunucu)

struct PDFtenOfficeEkrani: View {
    nonisolated enum Tur: Sendable { case word, excel }
    let baglam: AracBaglami
    let tur: Tur
    @State private var sunucuda = false
    @State private var aralik = ""

    private var sunucuAcik: Bool { Ayarlar.paylasilan.sunucuEtkin }

    var body: some View {
        let s = sunucuda && sunucuAcik, a = aralik, t = tur
        AracSablonu(arac: AracKatalogu.arac(tur == .word ? "pdftenWord" : "pdftenExcel"), girdiler: baglam.girdiler, secenekler: {
            Section {
                Toggle("Sunucuda (daha iyi düzen)", isOn: $sunucuda).disabled(!sunucuAcik)
                if !sunucuda || !sunucuAcik { SayfaAraligiAlani(metin: $aralik) }
                if sunucuda { SunucuNotu() }
                else if !sunucuAcik { Text("Sunucu kapalı; cihazda dönüştürülür.").font(.footnote).foregroundStyle(.secondary) }
            } footer: {
                Text(tur == .word
                     ? "Cihazda: başlıklar, paragraflar, maddeler ve görseller aktarılır; karmaşık düzen basitleşir. Taranmış sayfalar görüntü olarak eklenir."
                     : "Cihazda: metin satırları sütunlara ayrılıp her sayfa ayrı sayfa olarak aktarılır. Taranmış PDF'lerde metin bulunmaz.")
            }
        }, calistir: { girdiler, ilerleme in
            if s {
                let istemci = pdfStudioIstemcisi()
                var sonuc: [URL] = []
                for (i, u) in girdiler.enumerated() {
                    try Task.checkCancellation()
                    sonuc.append(t == .word ? try await istemci.pdftenWord(u) : try await istemci.pdftenExcel(u))
                    ilerleme(Double(i + 1) / Double(girdiler.count))
                }
                return sonuc
            }
            return try await herDosyayaUygula(girdiler, ilerleme) {
                [t == .word ? try PDFOffice.pdftenWord($0, aralik: a) : try PDFOffice.pdftenExcel($0, aralik: a)]
            }
        })
    }
}

// MARK: PowerPoint

struct PDFtenPowerPointEkrani: View {
    let baglam: AracBaglami
    @State private var aralik = ""
    @State private var dpi = 130.0

    var body: some View {
        let a = aralik, d = Int(dpi)
        AracSablonu(arac: AracKatalogu.arac("pdftenPowerPoint"), girdiler: baglam.girdiler, secenekler: {
            Section {
                SayfaAraligiAlani(metin: $aralik)
                VStack(alignment: .leading) {
                    Text("Slayt görüntü kalitesi: \(Int(dpi)) dpi")
                    Slider(value: $dpi, in: 72...220, step: 6)
                }
            } footer: {
                Text("Her sayfa bir slayt olur (görüntü olarak).")
            }
        }, calistir: { girdiler, ilerleme in
            try await herDosyayaUygula(girdiler, ilerleme) { [try PDFOffice.pdftenPowerPoint($0, aralik: a, dpi: d)] }
        })
    }
}

// MARK: Karşılaştır

struct KarsilastirEkrani: View {
    let baglam: AracBaglami
    @State private var ozet: String?

    var body: some View {
        AracSablonu(arac: AracKatalogu.arac("karsilastir"), girdiler: baglam.girdiler, secenekler: {
            Section {
                Text("Listedeki ilk dosya eski (A), ikinci dosya yeni (B) sürümdür.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let ozet {
                Section("Özet") { Text(ozet) }
            }
        }, calistir: { girdiler, ilerleme in
            guard girdiler.count >= 2 else { throw KagitHata.genel("Karşılaştırmak için iki PDF seçin.") }
            let a = girdiler[0], b = girdiler[1]
            let s = try await arkaPlanda { try PDFKarsilastirma.karsilastir(a, b, ilerleme: ilerleme) }
            ozet = s.ozdesMi
                ? "Fark bulunmadı (\(s.sayfaA) sayfa)."
                : "\(s.farkliSayfalar.count) sayfada fark · +\(s.toplamEklenen) / −\(s.toplamSilinen) satır · ortalama görsel fark %\(String(format: "%.1f", s.ortalamaGorselFark * 100))"
            return s.rapor.map { [$0] } ?? []
        })
    }
}

// MARK: Onar

struct OnarEkrani: View {
    let baglam: AracBaglami
    @State private var ozet: String?

    var body: some View {
        AracSablonu(arac: AracKatalogu.arac("onar"), girdiler: baglam.girdiler, secenekler: {
            Section {
                Text("Açılmayan ya da hata veren PDF'i yeniden yazar. Özgün dosyaya dokunulmaz.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let ozet { Section("Sonuç") { Text(ozet) } }
        }, calistir: { girdiler, ilerleme in
            let sonuclar = try await arkaPlanda { () throws -> [PDFOnar.Sonuc] in
                var s: [PDFOnar.Sonuc] = []
                for (i, u) in girdiler.enumerated() {
                    try iptalDenetle()
                    s.append(try PDFOnar.onar(u))
                    ilerleme(Double(i + 1) / Double(girdiler.count))
                }
                return s
            }
            ozet = sonuclar.map { "\($0.sayfaSayisi) sayfa · \($0.yontem)" }.joined(separator: "\n")
            return sonuclar.map(\.cikti)
        })
    }
}
