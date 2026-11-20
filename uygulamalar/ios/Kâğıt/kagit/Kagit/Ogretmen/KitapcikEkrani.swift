import KagitKit
import SwiftUI

/// A/B kitapçık oluşturma: soru algılama → gözden geçirme → karıştırma ve üretim.
struct KitapcikEkrani: View {
    let baglam: AracBaglami
    @Environment(Kitaplik.self) private var kitaplik
    @Environment(Yonlendirici.self) private var yon
    @Environment(\.dismiss) private var kapat
    @State private var depo = OgretmenDeposu.paylasilan

    @State private var girdi: URL?
    @State private var sinavAdi = ""
    @State private var sutun = 2
    @State private var tohum = Int.random(in: 1...9999)
    @State private var anahtarMetni = ""
    @State private var yenidenNumarala = true
    @State private var bolgeler: [SoruBolgesi] = []
    @State private var calisiyor: String?
    @State private var oran: Double?
    @State private var ileti: Ileti?
    @State private var uretilen: [KitaplikOgesi] = []

    private var anahtarHarfleri: [String] {
        anahtarMetni.uppercased().filter { "ABCDE".contains($0) }.map { String($0) }
    }

    var body: some View {
        Form {
            TekPDFSecimi(url: $girdi)
            Section("Kitapçık") {
                TextField("Sınav adı", text: $sinavAdi)
                Picker("Sütun", selection: $sutun) { Text("Tek sütun").tag(1); Text("İki sütun").tag(2) }.pickerStyle(.segmented)
                Stepper("Karıştırma tohumu: \(tohum)", value: $tohum, in: 1...99999)
                Toggle("Soruları yeniden numarala", isOn: $yenidenNumarala)
                TextField("Cevap anahtarı (ör. ABCDEABCDE)", text: $anahtarMetni).textInputAutocapitalization(.characters).autocorrectionDisabled()
                if !anahtarMetni.isEmpty && !bolgeler.isEmpty && anahtarHarfleri.count != bolgeler.count {
                    Text("Anahtarda \(anahtarHarfleri.count) cevap var, \(bolgeler.count) soru algılandı.").font(.caption).foregroundStyle(.orange)
                }
                Button { algila() } label: { Label(bolgeler.isEmpty ? "Soruları algıla" : "Yeniden algıla", systemImage: "text.viewfinder") }
                    .disabled(girdi == nil)
            }
            if !bolgeler.isEmpty { gozdenGecirme }
            if !uretilen.isEmpty {
                Section("Oluşturulanlar") {
                    ForEach(uretilen) { o in
                        Button { belgeyiAc(yon, o) } label: { Label(o.tamAd, systemImage: "doc.richtext") }
                    }
                }
            }
        }
        .navigationTitle("Kitapçık oluştur")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { kapat() } } }
        .safeAreaInset(edge: .bottom) {
            if !bolgeler.isEmpty {
                Button { uret() } label: {
                    Label("A ve B kitapçıklarını oluştur", systemImage: "books.vertical").frame(maxWidth: .infinity).padding(.vertical, 6)
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
        .onChange(of: girdi) { _, _ in bolgeler = [] }
    }

    @ViewBuilder private var gozdenGecirme: some View {
        Section {
            ForEach(Array(bolgeler.enumerated()), id: \.element.id) { i, b in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Soru \(b.numara)").font(.subheadline.bold())
                        Text(b.parcalar.map { "s.\($0.sayfa + 1)" }.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Menu {
                            if i + 1 < bolgeler.count {
                                Button { bolgeler = SoruAlgilama.birlestir(bolgeler, i) } label: { Label("Sonrakiyle birleştir", systemImage: "arrow.triangle.merge") }
                            }
                            Button(role: .destructive) { bolgeler.remove(at: i) } label: { Label("Soruyu çıkar", systemImage: "trash") }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                    if let girdi {
                        ForEach(Array(b.parcalar.enumerated()), id: \.offset) { _, p in
                            SayfaResmi(url: girdi, sayfa: p.sayfa, bolge: p.kutu, dpi: 80, yukseklik: 150)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    HStack(spacing: 14) {
                        kenarDugmesi("Üst", i) { SoruAlgilama.kenarAyarla(&bolgeler[i], ust: $0) }
                        kenarDugmesi("Alt", i) { SoruAlgilama.kenarAyarla(&bolgeler[i], alt: $0) }
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Gözden geçirme · \(bolgeler.count) soru")
        } footer: {
            Text("Üst/Alt düğmeleri ilk dilimin sınırını 12 punto genişletir ya da daraltır. Şekil içeren soruların altını genişletmeniz gerekebilir.")
        }
    }

    private func kenarDugmesi(_ ad: String, _ i: Int, _ uygula: @escaping (CGFloat) -> Void) -> some View {
        HStack(spacing: 4) {
            Text("\(ad) kenar").font(.caption)
            Button { uygula(12) } label: { Image(systemName: "plus.circle") }.buttonStyle(.borderless)
            Button { uygula(-12) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
        }
    }

    private func algila() {
        guard let u = girdi else { return }
        calisiyor = "Sorular algılanıyor…"
        oran = nil
        Task {
            defer { calisiyor = nil }
            do {
                let v = try Data(contentsOf: u)
                bolgeler = try await SoruAlgilama.algila(veri: v, ocr: true, ilerleme: { o in Task { @MainActor in oran = o } })
            } catch { ileti = Ileti(error) }
        }
    }

    private func uret() {
        guard let u = girdi else { return }
        calisiyor = "Kitapçıklar hazırlanıyor…"
        oran = nil
        var ayar = KitapcikAyari()
        ayar.sutun = sutun
        ayar.tohum = UInt64(tohum)
        ayar.sinavAdi = sinavAdi
        ayar.baslik = depo.baslik
        ayar.yenidenNumarala = yenidenNumarala
        let harfler = anahtarHarfleri
        if harfler.count == bolgeler.count {
            for (i, b) in bolgeler.enumerated() { ayar.anahtar[b.numara] = harfler[i] }
        }
        let b = bolgeler, adi = sinavAdi.isEmpty ? u.deletingPathExtension().lastPathComponent : sinavAdi
        let sonAyar = ayar
        Task {
            defer { calisiyor = nil }
            do {
                let v = try Data(contentsOf: u)
                let s = try await Task.detached { try Kitapcik.uret(kaynak: v, bolgeler: b, ayar: sonAyar) }.value
                var yeni: [KitaplikOgesi] = []
                var dosyalar: [(String, Data)] = [("\(adi) - A Kitapçığı", s.a), ("\(adi) - B Kitapçığı", s.b)]
                if let k = s.anahtarPDF { dosyalar.append(("\(adi) - Cevap Anahtarı", k)) }
                for (ad, veri) in dosyalar {
                    let t = Gecici.dosya("\(ad).pdf")
                    try veri.write(to: t)
                    yeni.append(try await kitaplik.ciktiKaydet(t, ad: ad, kaynak: u))
                }
                uretilen = yeni
            } catch { ileti = Ileti(error) }
        }
    }
}
