import KagitKit
import SwiftUI

/// PDF metninden yapay zekâ ile soru üretir; düzenlenebilir önizlemeden sınav + cevap anahtarı PDF'i çıkarır.
struct SoruUretEkrani: View {
    let baglam: AracBaglami
    @Environment(Kitaplik.self) private var kitaplik
    @Environment(Yonlendirici.self) private var yon
    @Environment(\.dismiss) private var kapat
    @State private var depo = OgretmenDeposu.paylasilan

    @State private var girdi: URL?
    @State private var aralik = ""
    @State private var adetler: [SoruTuru: Int] = [.coktanSecmeli: 5, .dogruYanlis: 2, .bosluk: 2, .acikUclu: 1, .eslestirme: 0]
    @State private var zorluk: SoruZorlugu = .orta
    @State private var sinif = "9. sınıf"
    @State private var konu = ""
    @State private var sinavAdi = ""
    @State private var aciklamali = true
    @State private var sorular: [UretilenSoru] = []
    @State private var kaynakEtiketi: String?
    @State private var calisiyor: String?
    @State private var oran: Double?
    @State private var ileti: Ileti?
    @State private var uretilen: [KitaplikOgesi] = []
    @State private var gorev: Task<Void, Never>?

    var body: some View {
        Form {
            TekPDFSecimi(url: $girdi)
            Section("Kaynak metin") {
                SayfaAraligiAlani(metin: $aralik)
                TextField("Konu odağı (isteğe bağlı)", text: $konu)
            }
            Section("Sorular") {
                ForEach(SoruTuru.allCases) { t in
                    Stepper("\(t.ad): \(adetler[t] ?? 0)", value: Binding(get: { adetler[t] ?? 0 }, set: { adetler[t] = $0 }), in: 0...20)
                }
                Picker("Zorluk", selection: $zorluk) { ForEach(SoruZorlugu.allCases) { Text($0.ad).tag($0) } }
                Picker("Sınıf düzeyi", selection: $sinif) { ForEach(["9. sınıf", "10. sınıf", "11. sınıf", "12. sınıf"], id: \.self) { Text($0).tag($0) } }
                Button { uret() } label: { Label(sorular.isEmpty ? "Soruları üret" : "Yeniden üret", systemImage: "sparkles") }
                    .disabled(girdi == nil || adetler.values.reduce(0, +) == 0)
                if let kaynakEtiketi { KaynakRozeti(etiket: kaynakEtiketi) }
            }
            if !sorular.isEmpty { onizleme }
            if !uretilen.isEmpty {
                Section("Oluşturulanlar") {
                    ForEach(uretilen) { o in Button { belgeyiAc(yon, o) } label: { Label(o.tamAd, systemImage: "doc.richtext") } }
                }
            }
        }
        .navigationTitle("Soru üret")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { gorev?.cancel(); kapat() } } }
        .safeAreaInset(edge: .bottom) {
            if !sorular.isEmpty {
                Button { pdfOlustur() } label: {
                    Label("Sınav ve cevap anahtarı PDF'i oluştur", systemImage: "doc.badge.plus").frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent).padding().background(.bar)
            }
        }
        .calisiyorKatmani(calisiyor, oran: oran)
        .iletiGoster($ileti)
        .onAppear {
            if girdi == nil { girdi = baglam.girdiler.first }
            if sinavAdi.isEmpty, let g = girdi { sinavAdi = g.deletingPathExtension().lastPathComponent }
        }
    }

    @ViewBuilder private var onizleme: some View {
        Section {
            TextField("Sınav adı", text: $sinavAdi)
            Toggle("Anahtarda çözüm açıklamaları", isOn: $aciklamali)
            ForEach($sorular) { $s in
                NavigationLink { SoruDuzenleme(soru: $s) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.tur.ad).font(.caption).foregroundStyle(.secondary)
                        Text(s.metin).lineLimit(3)
                    }
                }
            }
            .onDelete { sorular.remove(atOffsets: $0) }
        } header: {
            Text("Önizleme · \(sorular.count) soru")
        } footer: {
            Text("Bir soruya dokunarak düzenleyin; kaydırarak silin.")
        }
    }

    private func uret() {
        guard let u = girdi else { return }
        calisiyor = "Metin okunuyor…"
        oran = nil
        let istek = SoruIstegi(adetler: adetler.filter { $0.value > 0 }, zorluk: zorluk, sinif: sinif, konu: konu)
        let yz = YapayAyar.paylasilan.yapayZeka()
        let aralikMetni = aralik
        gorev = Task {
            defer { calisiyor = nil }
            do {
                if let neden = yz.kullanilamazNedeni { throw KagitHata.yapayZeka(neden) }
                let v = try Data(contentsOf: u)
                let n = PDFDocumentSayac.sayfaSayisi(v)
                let idx = try SayfaAraligi.coz(aralikMetni, sayfaSayisi: n)
                let metin = try await BelgeMetni.sayfaMetinleri(veri: v, sayfalar: idx, ocr: true)
                calisiyor = "Yapay zekâ soru üretiyor…"
                sorular = try await SoruUretici.uret(sayfalar: metin, istek: istek, yz: yz, ilerleme: { o in Task { @MainActor in oran = o } })
                kaynakEtiketi = yz.kaynakEtiketi
            } catch { if !Task.isCancelled { ileti = Ileti(error) } }
        }
    }

    private func pdfOlustur() {
        calisiyor = "PDF hazırlanıyor…"
        let s = sorular, b = depo.baslik, ad = sinavAdi.isEmpty ? "Sınav" : sinavAdi, ac = aciklamali
        let ust = girdi.flatMap { kitaplik.oge(url: $0)?.ustYol } ?? ""
        Task {
            defer { calisiyor = nil }
            do {
                let (sinav, anahtar) = await Task.detached {
                    (SinavPDF.sinav(sorular: s, baslik: b, sinavAdi: ad), SinavPDF.anahtar(sorular: s, baslik: b, sinavAdi: ad, aciklamali: ac))
                }.value
                var yeni: [KitaplikOgesi] = []
                for (adi, veri) in [("\(ad) - Sınav", sinav), ("\(ad) - Cevap Anahtarı", anahtar)] {
                    let t = Gecici.dosya("\(adi).pdf")
                    try veri.write(to: t)
                    yeni.append(try await kitaplik.ciktiKaydet(t, ad: adi, klasor: ust))
                }
                uretilen = yeni
            } catch { ileti = Ileti(error) }
        }
    }
}

enum PDFDocumentSayac {
    static func sayfaSayisi(_ v: Data) -> Int { PDFDocumentSarmal.sayfaSayisi(v) }
}

extension PDFDocumentSarmal {
    static func sayfaSayisi(_ veri: Data) -> Int { PDFDocument(data: veri)?.pageCount ?? 0 }
}

import PDFKit

/// Tek bir sorunun düzenlenmesi.
struct SoruDuzenleme: View {
    @Binding var soru: UretilenSoru

    var body: some View {
        Form {
            Section("Soru") { TextField("Soru metni", text: $soru.metin, axis: .vertical).lineLimit(2...10) }
            switch soru.tur {
            case .coktanSecmeli:
                Section("Şıklar") {
                    ForEach(0..<soru.secenekler.count, id: \.self) { i in
                        HStack {
                            Text(String(UnicodeScalar(UInt8(65 + i)))).bold()
                            TextField("Şık", text: $soru.secenekler[i], axis: .vertical)
                        }
                    }
                }
                Section("Doğru cevap") {
                    Picker("Doğru şık", selection: $soru.dogru) { ForEach(["A", "B", "C", "D", "E"], id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented)
                }
            case .dogruYanlis:
                Section("Doğru cevap") {
                    Picker("Cevap", selection: $soru.dogru) { Text("Doğru").tag("Doğru"); Text("Yanlış").tag("Yanlış") }.pickerStyle(.segmented)
                }
            case .bosluk, .acikUclu:
                Section(soru.tur == .bosluk ? "Beklenen sözcük" : "Örnek yanıt") { TextField("Cevap", text: $soru.dogru, axis: .vertical) }
            case .eslestirme:
                Section("Çiftler") {
                    ForEach(0..<soru.ciftler.count, id: \.self) { i in
                        HStack {
                            TextField("Sol", text: $soru.ciftler[i].sol)
                            Image(systemName: "arrow.left.arrow.right").foregroundStyle(.secondary)
                            TextField("Sağ", text: $soru.ciftler[i].sag)
                        }
                    }
                }
            }
            Section("Çözüm açıklaması") { TextField("Açıklama", text: $soru.aciklama, axis: .vertical).lineLimit(1...6) }
        }
        .navigationTitle(soru.tur.ad)
        .navigationBarTitleDisplayMode(.inline)
    }
}
