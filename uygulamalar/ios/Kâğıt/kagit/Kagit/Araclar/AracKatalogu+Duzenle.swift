import KagitKit
import SwiftUI

// Modül B: düzenleme araçları — imzala, düzleştir, açıklamaları kaldır, metni düzenle.
extension AracKatalogu {
    static var duzenleAraclari: [Arac] {
        [
            Arac(id: "imzala", ad: "PDF İmzala", aciklama: "Formu doldur, imzanı, tarihini ve işaretleri ekle",
                 simge: "signature", kategori: .duzenle, girdi: .tekPDF) { baglam in
                BelgeAcici(baslik: "PDF İmzala", simge: "signature", kip: .imzala, girdiler: baglam.girdiler,
                           aciklama: "Seçtiğin PDF Doldur & İmzala kipinde açılır.")
            },
            Arac(id: "metniDuzenle", ad: "Metni Düzenle", aciklama: "PDF içindeki metni değiştir, yeni metin ekle",
                 simge: "character.cursor.ibeam", kategori: .duzenle, girdi: .tekPDF) { baglam in
                BelgeAcici(baslik: "Metni Düzenle", simge: "character.cursor.ibeam", kip: .duzenle, girdiler: baglam.girdiler,
                           aciklama: "Seçtiğin PDF Düzenle kipinde açılır; bir metin satırına dokunarak değiştirebilirsin.")
            },
            Arac(id: "duzlestir", ad: "Düzleştir", aciklama: "Açıklama ve form alanlarını sayfa içeriğine işle",
                 simge: "square.3.layers.3d.down.right", kategori: .duzenle, girdi: .birVeyaCokPDF, topluUygun: true) { baglam in
                if let arac = AracKatalogu.bul("duzlestir") {
                    AracSablonu(arac: arac, girdiler: baglam.girdiler, secenekler: {
                        Section {
                            Text("İşaretler, çizimler, notlar ve doldurulmuş form alanları sayfanın kalıcı parçası olur; artık düzenlenemez. Her yerde aynı görünür.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }, calistir: { girdiler, ilerleme in
                        try await Self.dosyalariIsle(girdiler, ek: "düzleştirilmiş", ilerleme: ilerleme) { url in
                            try DuzenlemeAraclari.duzlestir(url: url)
                        }
                    })
                }
            },
            Arac(id: "aciklamalariKaldir", ad: "Açıklamaları Kaldır", aciklama: "Vurgu, çizim, not ve damgaları sil",
                 simge: "eraser.line.dashed", kategori: .duzenle, girdi: .birVeyaCokPDF, topluUygun: true) { baglam in
                AciklamaKaldirEkrani(girdiler: baglam.girdiler)
            },
        ]
    }

    /// Her girdi için `islem`in verisini "<ad> (<ek>).pdf" geçici dosyasına yazar.
    nonisolated static func dosyalariIsle(_ girdiler: [URL], ek: String, ilerleme: @escaping Ilerleme,
                                          islem: @escaping @Sendable (URL) throws -> Data) async throws -> [URL] {
        try await Task.detached {
            var ciktilar: [URL] = []
            for (i, u) in girdiler.enumerated() {
                try iptalDenetle()
                ilerleme(Double(i) / Double(max(girdiler.count, 1)))
                let veri = try islem(u)
                let hedef = Gecici.dosya("\(u.deletingPathExtension().lastPathComponent) (\(ek)).pdf")
                try Belge.yaz(veri, hedef)
                ciktilar.append(hedef)
            }
            ilerleme(1)
            return ciktilar
        }.value
    }
}

/// Açıklamaları kaldır aracı: bağlantı/form koruma seçenekleriyle.
private struct AciklamaKaldirEkrani: View {
    let girdiler: [URL]
    @State private var baglantilariKoru = true
    @State private var formlariKoru = true

    var body: some View {
        if let arac = AracKatalogu.bul("aciklamalariKaldir") {
            let baglanti = baglantilariKoru, form = formlariKoru
            AracSablonu(arac: arac, girdiler: girdiler, secenekler: {
                Section {
                    Toggle("Bağlantıları koru", isOn: $baglantilariKoru)
                    Toggle("Form alanlarını koru", isOn: $formlariKoru)
                } footer: {
                    Text("Vurgu, alt çizgi, çizim, şekil, metin kutusu, not ve damgalar kaldırılır.")
                }
            }, calistir: { girdiler, ilerleme in
                try await AracKatalogu.dosyalariIsle(girdiler, ek: "açıklamasız", ilerleme: ilerleme) { url in
                    try DuzenlemeAraclari.aciklamalariKaldir(url: url, baglantilariKoru: baglanti, formlariKoru: form).veri
                }
            })
        }
    }
}

/// "PDF İmzala" / "Metni Düzenle": dosyayı seç, belgeyi ilgili kipte aç.
struct BelgeAcici: View {
    let baslik: String
    let simge: String
    let kip: BelgeKipi
    let girdiler: [URL]
    let aciklama: String

    @Environment(Kitaplik.self) private var kitaplik
    @Environment(Yonlendirici.self) private var yon
    @Environment(\.dismiss) private var kapat
    @State private var secimAcik = false
    @State private var acildi = false

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: simge).font(.system(size: 54)).foregroundStyle(Tema.renk(.duzenle))
            Text(aciklama).multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal, 30)
            Button { secimAcik = true } label: {
                Label("PDF seç", systemImage: "doc.badge.plus").frame(maxWidth: 260).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(baslik)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { kapat() } } }
        .kaynakSecici(isPresented: $secimAcik, girdi: .tekPDF) { urller in
            if let u = urller.first { ac(u) }
        }
        .task {
            if !acildi, let u = girdiler.first { acildi = true; ac(u) }
        }
    }

    private func ac(_ url: URL) {
        Task {
            do {
                let oge: KitaplikOgesi
                if let var_ = kitaplik.oge(url: url) {
                    oge = var_
                } else {
                    guard let ilk = try await kitaplik.iceAktar([url]).first else { return }
                    oge = ilk
                }
                kapat()
                try? await Task.sleep(for: .milliseconds(400))
                yon.ac(oge, kip: kip)
            } catch {
                yon.ileti = Ileti(error)
            }
        }
    }
}
