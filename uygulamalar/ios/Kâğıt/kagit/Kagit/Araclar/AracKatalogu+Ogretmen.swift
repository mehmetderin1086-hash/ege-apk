import KagitKit
import PDFKit
import SwiftUI

// Modül D: öğretmen ve yapay zekâ araçları.
extension AracKatalogu {
    static var ogretmenAraclari: [Arac] {
        [
            Arac(id: "yiginiBol", ad: "Yığını öğrenciye böl", aciklama: "Taranmış sınıf yığınını öğrenci başına ayrı PDF'lere böler",
                 simge: "rectangle.stack.badge.person.crop", kategori: .ogretmen, girdi: .tekPDF) { YiginBolEkrani(baglam: $0) },
            Arac(id: "kitapcikOlustur", ad: "A/B kitapçık oluştur", aciklama: "Sınav sorularını karıştırıp iki kitapçık ve cevap anahtarı üretir",
                 simge: "books.vertical", kategori: .ogretmen, girdi: .tekPDF) { KitapcikEkrani(baglam: $0) },
            Arac(id: "soruUret", ad: "Soru üret", aciklama: "PDF'ten yapay zekâ ile sınav sorusu ve cevap anahtarı hazırlar",
                 simge: "sparkles.rectangle.stack", kategori: .ogretmen, girdi: .tekPDF) { SoruUretEkrani(baglam: $0) },
            Arac(id: "puanTablosu", ad: "Puan tablosu", aciklama: "Notlandırılmış PDF'lerdeki puanları Excel/CSV tablosuna toplar",
                 simge: "tablecells", kategori: .ogretmen, girdi: .birVeyaCokPDF) { PuanTablosuEkrani(baglam: $0) },
            Arac(id: "basligiEkle", ad: "Başlık ekle", aciklama: "Okul başlık şablonunu sayfaların üstüne ekler",
                 simge: "text.badge.plus", kategori: .ogretmen, girdi: .birVeyaCokPDF, topluUygun: true) { BaslikEkleEkrani(baglam: $0) },
        ]
    }

    static var yapayAraclari: [Arac] {
        [
            Arac(id: "ozetle", ad: "Özetle", aciklama: "Belgeyi yapay zekâ ile özetleyip PDF olarak kaydeder",
                 simge: "text.append", kategori: .yapay, girdi: .tekPDF) { OzetleEkrani(baglam: $0) },
            Arac(id: "cevir", ad: "Belgeyi çevir", aciklama: "Belgeyi Türkçe ↔ İngilizce çevirip yeni PDF yapar",
                 simge: "character.bubble", kategori: .yapay, girdi: .tekPDF) { CevirEkrani(baglam: $0) },
            Arac(id: "belgeyleSohbet", ad: "Belgeyle sohbet", aciklama: "Belgeye soru sorun; yanıt kaynak sayfalarıyla gelir",
                 simge: "bubble.left.and.text.bubble.right", kategori: .yapay, girdi: .tekPDF) { BelgeyleSohbetAraci(baglam: $0) },
        ]
    }
}

// MARK: - Puan tablosu

struct PuanTablosuEkrani: View {
    let baglam: AracBaglami
    @State private var sayfaSutunlari = false
    @State private var sinavAdi = "Puanlar"

    var body: some View {
        AracSablonu(arac: AracKatalogu.bul("puanTablosu")!, girdiler: baglam.girdiler, secenekler: {
            Section("Tablo") {
                TextField("Sayfa adı", text: $sinavAdi)
                Toggle("Sayfa başına puan sütunları", isOn: $sayfaSutunlari)
            }
            Section { Text("Dosya adları “123 Ayşe Yılmaz - Sınav.pdf” biçimindeyse numara ve ad otomatik ayrılır. Toplam, belgedeki puan işaretlerinden okunur.").font(.footnote).foregroundStyle(.secondary) }
        }, calistir: { girdiler, ilerleme in
            let sutun = sayfaSutunlari, ad = sinavAdi
            return try await Task.detached {
                var g: [(String, Data)] = []
                for (i, u) in girdiler.enumerated() {
                    try iptalDenetle()
                    g.append((u.lastPathComponent, try Data(contentsOf: u)))
                    ilerleme(Double(i + 1) / Double(girdiler.count) * 0.7)
                }
                let satirlar = PuanTablosu.olustur(girdiler: g)
                guard !satirlar.isEmpty else { throw KagitHata.bosGirdi }
                let x = Gecici.dosya("Puan tablosu.xlsx")
                try PuanTablosu.xlsx(satirlar, sayfaSutunlari: sutun, baslik: ad.isEmpty ? "Puanlar" : ad).write(to: x)
                let c = Gecici.dosya("Puan tablosu.csv")
                try PuanTablosu.csv(satirlar, sayfaSutunlari: sutun).write(to: c)
                ilerleme(1)
                return [x, c]
            }.value
        })
    }
}

// MARK: - Başlık ekle

struct BaslikEkleEkrani: View {
    let baglam: AracBaglami
    @State private var depo = OgretmenDeposu.paylasilan
    @State private var hepsi = false
    @State private var yerAc = true
    @State private var kutular = true
    @State private var sinavAdi = ""

    var body: some View {
        AracSablonu(arac: AracKatalogu.bul("basligiEkle")!, girdiler: baglam.girdiler, secenekler: {
            Section("Başlık") {
                TextField("Sınav adı", text: $sinavAdi)
                Picker("Sayfalar", selection: $hepsi) { Text("Yalnız ilk sayfa").tag(false); Text("Her sayfa").tag(true) }
                Toggle("İçeriği küçültüp yer aç", isOn: $yerAc)
                Toggle("Ad Soyad / No / Sınıf / Puan kutuları", isOn: $kutular)
            }
            Section("Önizleme") {
                BaslikOnizleme(baslik: depo.baslik, sinavAdi: sinavAdi).frame(height: 110)
                if depo.baslik.bosMu { Text("Okul bilgileri boş. Ayarlar › Öğretmen › Okul başlığı bölümünden doldurun.").font(.caption).foregroundStyle(.orange) }
            }
        }, calistir: { girdiler, ilerleme in
            let b = depo.baslik, h = hepsi, y = yerAc, k = kutular, ad = sinavAdi
            return try await Task.detached {
                var cikti: [URL] = []
                for (i, u) in girdiler.enumerated() {
                    try iptalDenetle()
                    let v = try Data(contentsOf: u)
                    let n = PDFDocument(data: v)?.pageCount ?? 0
                    let s = BaslikEkleyici.Secenek(sayfalar: h ? Array(0..<n) : [0], yerAc: y, ogrenciKutulari: k, sinavAdi: ad)
                    let sonuc = try BaslikEkleyici.ekle(veri: v, baslik: b, secenek: s)
                    let t = Gecici.dosya("\(u.deletingPathExtension().lastPathComponent) - başlıklı.pdf")
                    try sonuc.write(to: t)
                    cikti.append(t)
                    ilerleme(Double(i + 1) / Double(girdiler.count))
                }
                return cikti
            }.value
        })
    }
}

// MARK: - Özetle / çevir

/// PDF'ten (sayfa aralığıyla) metin alır.
private func metinAl(_ u: URL, _ aralik: String) async throws -> [Int: String] {
    let v = try Data(contentsOf: u)
    let n = PDFDocumentSarmal.sayfaSayisi(v)
    let idx = try SayfaAraligi.coz(aralik, sayfaSayisi: n)
    let m = try await BelgeMetni.sayfaMetinleri(veri: v, sayfalar: idx, ocr: true)
    guard !m.isEmpty else { throw KagitHata.yapayZeka("Belgede metin bulunamadı.") }
    return m
}

struct OzetleEkrani: View {
    let baglam: AracBaglami
    @State private var stil: OzetStili = .ayrintili
    @State private var aralik = ""
    @State private var etiket: String?

    var body: some View {
        AracSablonu(arac: AracKatalogu.bul("ozetle")!, girdiler: baglam.girdiler, secenekler: {
            Section("Özet") {
                Picker("Biçim", selection: $stil) { ForEach(OzetStili.allCases) { Text($0.ad).tag($0) } }
                SayfaAraligiAlani(metin: $aralik)
                if let e = YapayAyar.paylasilan.yapayZeka().kaynakEtiketi { KaynakRozeti(etiket: e) }
                else if let n = YapayAyar.paylasilan.yapayZeka().kullanilamazNedeni { Text(n).font(.caption).foregroundStyle(.orange) }
            }
        }, calistir: { girdiler, ilerleme in
            let yz = YapayAyar.paylasilan.yapayZeka()
            if let n = yz.kullanilamazNedeni { throw KagitHata.yapayZeka(n) }
            guard let u = girdiler.first else { throw KagitHata.bosGirdi }
            let m = try await metinAl(u, aralik)
            let o = try await Ozetleyici.ozetle(sayfalar: m, stil: stil, yz: yz, ilerleme: ilerleme)
            let ad = u.deletingPathExtension().lastPathComponent
            let pdf = MetinPDF.uret(baslik: "\(ad) — Özet", altBaslik: "Kaynak: \(o.kaynakEtiketi) · \(stil.ad)", govde: o.metin)
            let t = Gecici.dosya("\(ad) - Özet.pdf")
            try pdf.write(to: t)
            return [t]
        })
    }
}

struct CevirEkrani: View {
    let baglam: AracBaglami
    @State private var hedef: Cevirmen.Hedef = .ingilizce
    @State private var aralik = ""

    var body: some View {
        AracSablonu(arac: AracKatalogu.bul("cevir")!, girdiler: baglam.girdiler, secenekler: {
            Section("Çeviri") {
                Picker("Hedef dil", selection: $hedef) { ForEach(Cevirmen.Hedef.allCases) { Text($0.ad).tag($0) } }.pickerStyle(.segmented)
                SayfaAraligiAlani(metin: $aralik)
                Text("Çeviri bulutta yapılır (Claude). Sonuç, özgün sayfa düzenini değil metni taşıyan yeni bir PDF'tir.").font(.footnote).foregroundStyle(.secondary)
            }
        }, calistir: { girdiler, ilerleme in
            let yz = YapayAyar.paylasilan.yapayZeka()
            if let n = yz.kullanilamazNedeni { throw KagitHata.yapayZeka(n) }
            guard let u = girdiler.first else { throw KagitHata.bosGirdi }
            let m = try await metinAl(u, aralik)
            let r = try await Cevirmen.cevir(sayfalar: m, hedef: hedef, yz: yz, ilerleme: ilerleme)
            let govde = r.sayfalar.keys.sorted().map { "# Sayfa \($0)\n\(r.sayfalar[$0] ?? "")" }.joined(separator: "\n")
            let ad = u.deletingPathExtension().lastPathComponent
            let pdf = MetinPDF.uret(baslik: "\(ad) — \(hedef.ad)", altBaslik: "Kaynak: \(r.kaynakEtiketi)", govde: govde)
            let t = Gecici.dosya("\(ad) - \(hedef.ad) çeviri.pdf")
            try pdf.write(to: t)
            return [t]
        })
    }
}

struct BelgeyleSohbetAraci: View {
    let baglam: AracBaglami
    @Environment(Kitaplik.self) private var kitaplik
    @Environment(Yonlendirici.self) private var yon
    @State private var girdi: URL?
    @State private var ileti: Ileti?

    var body: some View {
        Form {
            TekPDFSecimi(url: $girdi)
            Section {
                Button {
                    guard let u = girdi else { return }
                    Task {
                        if let o = kitaplik.oge(url: u) { belgeyiAc(yon, o, kip: .yapay) }
                        else if let o = try? await kitaplik.iceAktar([u]).first { belgeyiAc(yon, o, kip: .yapay) }
                        else { ileti = Ileti(KagitHata.acilamadi(u.lastPathComponent)) }
                    }
                } label: { Label("Belgeyi Yapay Zekâ kipinde aç", systemImage: "bubble.left.and.text.bubble.right") }
                    .disabled(girdi == nil)
            } footer: { Text("Açılan belgede alttaki “Sohbet” sekmesinden soru sorabilirsiniz.") }
        }
        .navigationTitle("Belgeyle sohbet")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if girdi == nil { girdi = baglam.girdiler.first } }
        .iletiGoster($ileti)
    }
}
