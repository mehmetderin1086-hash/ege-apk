import KagitKit
import SwiftUI

/// Taranmış sınıf yığınını öğrenci başına parçalara böler; gözden geçirme ekranıyla.
struct YiginBolEkrani: View {
    let baglam: AracBaglami
    @Environment(Kitaplik.self) private var kitaplik
    @Environment(Yonlendirici.self) private var yon
    @Environment(\.dismiss) private var kapat
    @State private var depo = OgretmenDeposu.paylasilan

    enum Kip: String, CaseIterable, Identifiable {
        case ad, herN, bos
        var id: String { rawValue }
        var ad: String {
            switch self {
            case .ad: "Ad algıla"
            case .herN: "Her N sayfa"
            case .bos: "Boş sayfa ayırıcı"
            }
        }
    }

    @State private var girdi: URL?
    @State private var sinifId: UUID?
    @State private var kip: Kip = .ad
    @State private var n = 2
    @State private var sinavAdi = ""
    @State private var parcalar: [YiginParcasi] = []
    @State private var sayfaSayisi = 0
    @State private var calisiyor: String?
    @State private var oran: Double?
    @State private var ileti: Ileti?

    private var sinif: Sinif? { depo.siniflar.first { $0.id == sinifId } }
    private var ogrenciler: [Ogrenci] { sinif?.ogrenciler ?? [] }

    var body: some View {
        Form {
            TekPDFSecimi(url: $girdi)
            Section("Bölme") {
                Picker("Yöntem", selection: $kip) { ForEach(Kip.allCases) { Text($0.ad).tag($0) } }
                if kip == .herN { Stepper("Her \(n) sayfa bir öğrenci", value: $n, in: 1...40) }
                Picker("Sınıf listesi", selection: $sinifId) {
                    Text("Seçilmedi").tag(UUID?.none)
                    ForEach(depo.siniflar) { Text($0.ad).tag(Optional($0.id)) }
                }
                if kip == .ad && sinif == nil {
                    Text("Ad algılamak için bir sınıf listesi seçin.").font(.caption).foregroundStyle(.orange)
                }
                TextField("Sınav adı (dosya adına eklenir)", text: $sinavAdi)
                Button { analiz() } label: { Label(parcalar.isEmpty ? "Analiz et" : "Yeniden analiz et", systemImage: "wand.and.stars") }
                    .disabled(girdi == nil || (kip == .ad && sinif == nil))
            }
            if !parcalar.isEmpty { gozdenGecirme }
        }
        .navigationTitle("Yığını öğrenciye böl")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { kapat() } } }
        .safeAreaInset(edge: .bottom) {
            if !parcalar.isEmpty {
                Button { kaydet() } label: {
                    Label("\(parcalar.count) dosyaya böl ve kaydet", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent).padding().background(.bar)
            }
        }
        .calisiyorKatmani(calisiyor, oran: oran)
        .iletiGoster($ileti)
        .onAppear { if girdi == nil { girdi = baglam.girdiler.first } }
        .onChange(of: girdi) { _, _ in parcalar = [] }
    }

    @ViewBuilder private var gozdenGecirme: some View {
        Section {
            ForEach(Array(parcalar.enumerated()), id: \.element.id) { i, p in
                HStack(alignment: .top, spacing: 10) {
                    if let girdi { SayfaResmi(url: girdi, sayfa: p.sayfalar.first ?? 0, yukseklik: 84).frame(width: 60) }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sayfa \(SayfaAraligi.metin(p.sayfalar)) · \(p.sayfalar.count) sayfa").font(.subheadline.weight(.medium))
                        if !ogrenciler.isEmpty {
                            Picker("Öğrenci", selection: $parcalar[i].ogrenci) {
                                Text("Atanmamış").tag(Int?.none)
                                ForEach(Array(ogrenciler.enumerated()), id: \.offset) { k, o in Text(o.tamAd).tag(Optional(k)) }
                            }
                            .labelsHidden()
                        }
                        if p.guven > 0 { Text("Algılanan: \(p.algilanan.replacingOccurrences(of: "\n", with: " "))").font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                    }
                    Spacer(minLength: 0)
                    Menu {
                        if i + 1 < parcalar.count {
                            Button { parcalar = YiginBolme.birlestir(parcalar, i) } label: { Label("Sonrakiyle birleştir", systemImage: "arrow.triangle.merge") }
                        }
                        if p.sayfalar.count > 1 {
                            Menu("Böl") {
                                ForEach(1..<p.sayfalar.count, id: \.self) { k in
                                    Button("Sayfa \(p.sayfalar[k] + 1)'den başlat") { parcalar = YiginBolme.bol(parcalar, i, konum: k) }
                                }
                            }
                        }
                        Button(role: .destructive) { parcalar.remove(at: i) } label: { Label("Bu parçayı çıkar", systemImage: "trash") }
                    } label: { Image(systemName: "ellipsis.circle").font(.title3) }
                }
            }
        } header: {
            Text("Gözden geçirme · \(parcalar.count) parça")
        } footer: {
            Text("Atamaları düzeltin; parçaları birleştirin ya da bölün. Çıkarılan parçalar kaydedilmez.")
        }
    }

    private func analiz() {
        guard let u = girdi else { return }
        calisiyor = "Sayfalar inceleniyor…"
        oran = nil
        let ogr = ogrenciler
        let k: YiginKipi = switch kip { case .ad: .adAlgila; case .herN: .herNSayfa(n); case .bos: .bosSayfa }
        let durum = IsDurumu()
        Task {
            defer { calisiyor = nil }
            do {
                let v = try Data(contentsOf: u)
                parcalar = try await YiginBolme.oner(veri: v, kip: k, ogrenciler: ogr, ilerleme: { o in Task { @MainActor in oran = o } })
                _ = durum
                if parcalar.isEmpty { ileti = Ileti(baslik: "Sonuç yok", metin: "Hiç parça bulunamadı.") }
            } catch { ileti = Ileti(error) }
        }
    }

    private func kaydet() {
        guard let u = girdi else { return }
        calisiyor = "Dosyalar yazılıyor…"
        oran = nil
        let p = parcalar, ogr = ogrenciler, ad = sinavAdi.trimmingCharacters(in: .whitespaces)
        let ust = kitaplik.oge(url: u)?.ustYol ?? ""
        Task {
            defer { calisiyor = nil }
            do {
                let v = try Data(contentsOf: u)
                let ciktilar = try await Task.detached { try YiginBolme.ciktilar(veri: v, parcalar: p, ogrenciler: ogr, sinavAdi: ad) }.value
                let klasor = try await kitaplik.yeniKlasor(ad.isEmpty ? "Yığın bölme" : ad, ust: ust)
                for (i, c) in ciktilar.enumerated() {
                    let t = Gecici.dosya("\(c.ad).pdf")
                    try c.veri.write(to: t)
                    try await kitaplik.ciktiKaydet(t, ad: c.ad, klasor: klasor.yol)
                    oran = Double(i + 1) / Double(ciktilar.count)
                }
                parcalar = []
                yon.sekme = .dosyalar
                ileti = Ileti(baslik: "Tamam", metin: "\(ciktilar.count) dosya “\(klasor.ad)” klasörüne kaydedildi.", hata: false)
            } catch { ileti = Ileti(error) }
        }
    }
}
