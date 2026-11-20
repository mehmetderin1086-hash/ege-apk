import KagitKit
import PhotosUI
import SwiftUI

/// Tam ekran tarayıcı: kamera (ya da Fotoğraflar) → düzenleme → kaydet.
struct TaramaEkrani: View {
    @Environment(\.dismiss) private var kapat
    @State private var model = TaramaModeli()
    @State private var kameraAcik = false
    /// Yeniden taranacak sayfa (nil: sona ekle).
    @State private var yenidenTaranan: UUID?
    @State private var fotoSec = false
    @State private var fotoSecimi: [PhotosPickerItem] = []
    @State private var vazgecSor = false
    @State private var ilkAcilis = true
    @State private var ileti: Ileti?
    @State private var yukleniyor = false

    var body: some View {
        NavigationStack {
            Group {
                if model.sayfalar.isEmpty {
                    baslangic
                } else {
                    TaramaDuzenleyici(model: model, kameraAc: kameraAc, fotoSec: { fotoSec = true }, bitti: { kapat() })
                }
            }
            .navigationTitle("Tara")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { if model.sayfalar.isEmpty { kapat() } else { vazgecSor = true } }
                }
            }
            .confirmationDialog("Taranan sayfalar silinsin mi?", isPresented: $vazgecSor, titleVisibility: .visible) {
                Button("Sayfaları sil ve kapat", role: .destructive) { kapat() }
                Button("Düzenlemeye dön", role: .cancel) {}
            }
        }
        .interactiveDismissDisabled(!model.sayfalar.isEmpty)
        .fullScreenCover(isPresented: $kameraAcik) {
            BelgeKamerasi { goruntuler in
                kameraAcik = false
                guard let goruntuler, !goruntuler.isEmpty else { return }
                if let id = yenidenTaranan {
                    model.degistir(id, goruntu: goruntuler[0])
                    if goruntuler.count > 1 { model.ekle(Array(goruntuler.dropFirst())) }
                } else {
                    model.ekle(goruntuler)
                }
                yenidenTaranan = nil
            }
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $fotoSec, selection: $fotoSecimi, matching: .images)
        .onChange(of: fotoSecimi) { _, yeni in
            guard !yeni.isEmpty else { return }
            let secim = yeni
            fotoSecimi = []
            Task { await fotograflariEkle(secim) }
        }
        .iletiGoster($ileti)
        .overlay { if yukleniyor { CalisiyorKatmani(metin: "Fotoğraflar hazırlanıyor…") } }
        .task {
            guard ilkAcilis else { return }
            ilkAcilis = false
            if BelgeKamerasi.desteklenir { kameraAcik = true }
        }
    }

    private func kameraAc(yenidenTara id: UUID? = nil) {
        yenidenTaranan = id
        kameraAcik = true
    }

    /// Fotoğraflardan seçilen görselleri aynı düzenleme ekranına alır (simülatörde kamera yok).
    private func fotograflariEkle(_ secim: [PhotosPickerItem]) async {
        yukleniyor = true
        defer { yukleniyor = false }
        var goruntuler: [CGImage] = []
        for oge in secim {
            guard let veri = try? await oge.loadTransferable(type: Data.self) else { continue }
            let g = await Task.detached { PDFCizim.goruntuYukle(veri, enBuyukKenar: 3200) }.value
            if let g { goruntuler.append(g) }
        }
        guard !goruntuler.isEmpty else {
            ileti = Ileti(metin: "Seçilen fotoğraflar açılamadı.")
            return
        }
        model.ekle(goruntuler, otomatikKose: true, filtre: .otomatikRenk)
    }

    private var baslangic: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "doc.viewfinder").font(.system(size: 64)).foregroundStyle(Tema.vurgu)
            Text("Belge tara").font(.title2.bold())
            Text(BelgeKamerasi.desteklenir
                 ? "Kamerayla sayfaları tara, düzenle ve aranabilir PDF olarak kaydet."
                 : "Bu cihazda belge kamerası yok. Fotoğraflardan bir görsel seçerek aynı düzenleme ekranını kullanabilirsin.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal, 32)
            VStack(spacing: 12) {
                if BelgeKamerasi.desteklenir {
                    Button { kameraAc() } label: { Label("Kamerayı aç", systemImage: "camera").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent)
                }
                Button { fotoSec = true } label: { Label("Fotoğraflardan seç", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered)
            }
            .controlSize(.large)
            .padding(.horizontal, 40)
            Spacer()
        }
    }
}
