import KagitKit
import SwiftUI

/// Kaydetme seçenekleri: ad, OCR, kalite, klasör.
struct TaramaKayitFormu: View {
    let model: TaramaModeli
    /// Kayıttan sonra tarayıcıyı kapatır.
    let bitti: () -> Void

    @Environment(Kitaplik.self) private var kitaplik
    @Environment(Yonlendirici.self) private var yon
    @Environment(\.dismiss) private var kapat

    @State private var ad = ""
    @State private var adDegisti = false
    @State private var onerilen = ""
    @State private var ocr = true
    @State private var kalite: TaramaKalitesi = .orta
    @State private var klasor = ""
    @State private var belgeyiAc = true
    @State private var tahmin = "…"
    @State private var calisiyor = false
    @State private var durum = IsDurumu()
    @State private var ileti: Ileti?

    var body: some View {
        NavigationStack {
            Form {
                Section("Ad") {
                    TextField("Belge adı", text: $ad)
                        .onChange(of: ad) { _, yeni in if yeni != onerilen { adDegisti = true } }
                }
                Section {
                    Toggle("Aranabilir PDF (OCR)", isOn: $ocr)
                } footer: {
                    Text("Her sayfaya görünmez bir metin katmanı eklenir; belgede arama yapabilir, metni kopyalayabilirsin. Süre sayfa sayısına göre uzar.")
                }
                Section {
                    Picker("Kalite", selection: $kalite) {
                        ForEach(TaramaKalitesi.allCases) { Text($0.ad).tag($0) }
                    }
                    LabeledContent("Tahmini boyut", value: tahmin)
                }
                Section("Konum") {
                    Picker("Klasör", selection: $klasor) {
                        Text("Kitaplık (ana klasör)").tag("")
                        ForEach(kitaplik.klasorler.sorted { $0.yol.localizedStandardCompare($1.yol) == .orderedAscending }) { k in
                            Text(k.yol).tag(k.yol)
                        }
                    }
                    Toggle("Kaydedince belgeyi aç", isOn: $belgeyiAc)
                }
            }
            .navigationTitle("\(model.sayfalar.count) sayfa")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { kapat() }.disabled(calisiyor) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { kaydet() }.disabled(calisiyor || ad.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .overlay { if calisiyor { CalisiyorKatmani(metin: ocr ? "Metin tanınıyor ve PDF hazırlanıyor…" : "PDF hazırlanıyor…", oran: durum.oran) } }
            .iletiGoster($ileti)
            .interactiveDismissDisabled(calisiyor)
        }
        .task { await adiOner() }
        .task(id: kalite) { await boyutuTahminEt() }
    }

    /// İlk sayfanın ilk anlamlı satırı + tarih.
    private func adiOner() async {
        let bos = "Tarama \(Date().formatted(.iso8601.year().month().day()))"
        if ad.isEmpty { onerilen = bos; ad = bos }
        guard let g = model.sayfalar.first?.onizleme ?? model.sayfalar.first?.kucuk else { return }
        let satirlar = (try? await MetinTanima.tani(g, hizli: true)) ?? []
        if !adDegisti {
            let oneri = TaramaIslemleri.adOner(satirlar: satirlar)
            onerilen = oneri
            ad = oneri
        }
    }

    /// İlk sayfayı seçili kalitede kodlayıp sayfa sayısıyla çarpar.
    private func boyutuTahminEt() async {
        guard let s = model.sayfalar.first else { return }
        tahmin = "…"
        let k = kalite, sayi = model.sayfalar.count
        let bayt = await Task.detached(priority: .utility) {
            let g = TaramaModeli.isle(s.ozgun, dondurme: s.dondurme, dortgen: s.dortgen, filtre: s.filtre,
                                      golgeTemizle: s.golgeTemizle, enBuyukKenar: k.enBuyukKenar)
            return PDFCizim.kodla(g, tur: .jpeg, kalite: k.jpeg)?.count ?? 0
        }.value
        guard !Task.isCancelled else { return }
        tahmin = "≈ " + BicimYardimci.boyut(Int64(bayt * sayi))
    }

    private func kaydet() {
        calisiyor = true
        durum.oran = nil
        let temizAd = TurkceMetin.dosyaAdi(ad, varsayilan: "Tarama")
        Task {
            defer { calisiyor = false }
            do {
                let goruntuler = await model.sonGoruntuler(kalite: kalite)
                var sec = AranabilirSecenekleri()
                sec.ocr = ocr
                sec.jpegKalitesi = kalite.jpeg
                let veri = try await AranabilirPDF.gorsellerdenPDF(goruntuler, baslik: temizAd, secenekler: sec,
                                                                   ilerleme: durum.bildirim)
                let gecici = Gecici.dosya("\(temizAd).pdf")
                try Belge.yaz(veri, gecici, beklenenSayfa: goruntuler.count)
                let oge = try await kitaplik.ciktiKaydet(gecici, ad: temizAd, klasor: klasor)
                let ac = belgeyiAc
                kapat()
                bitti()
                if ac {
                    try? await Task.sleep(for: .milliseconds(600))
                    yon.ac(oge)
                } else {
                    yon.ileti = Ileti(baslik: "Kaydedildi", metin: "“\(oge.tamAd)” kitaplığa eklendi.", hata: false)
                }
            } catch {
                ileti = Ileti(error)
            }
        }
    }
}
