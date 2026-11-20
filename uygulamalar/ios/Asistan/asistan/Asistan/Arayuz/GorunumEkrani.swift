import SwiftUI
import UniformTypeIdentifiers

struct GorunumEkrani: View {
    @Environment(Ayarlar.self) private var ayarlar
    @Environment(\.colorScheme) private var sema
    @State private var onceki: GorunumTercihleri?
    @State private var belge: GorunumBelgesi?
    @State private var disaAktar = false
    @State private var iceAktar = false
    @State private var mesaj: String?

    /// Ölçeği yüzde metnine çevirir; kayan nokta artığı yuvarlanır (0.8999… → "%90", kesilip "%89" olmaz).
    nonisolated static func yuzde(_ olcek: Double) -> String { "%\(Int((olcek * 100).rounded()))" }

    var body: some View {
        @Bindable var a = ayarlar
        Form {
            Section {
                onizleme
                    .listRowInsets(EdgeInsets())
            } header: { Text("Canlı önizleme") } footer: { Text("Değişiklikler anında uygulanır ve telefonda saklanır. Önizlemedeki hareket örnektir; mikrofonu açmaz.") }
            // Tek hazır görünüm seti sohbet temalarıdır (`SohbetTemasi.hazirlar`, yukarıdaki bölüm).
            SohbetTemaAyarlari()
            Section("Tema ve renk") {
                Picker("Tema", selection: $a.gorunum.tema) { ForEach(GorunumTercihleri.Tema.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(GorunumTercihleri.paletler, id: \.1) { ad, hex in
                            Button { a.gorunum.renk = hex } label: {
                                VStack(spacing: 4) {
                                    Circle().fill(Color(hex: hex)).frame(width: 36,height:36)
                                        .overlay { if a.gorunum.renk == hex { Image(systemName:"checkmark").foregroundStyle(.black).bold() } }
                                    Text(ad).font(.caption2)
                                }.frame(minWidth: 55, minHeight: 60)
                            }.buttonStyle(.plain).accessibilityLabel(ad).accessibilityAddTraits(a.gorunum.renk == hex ? .isSelected : [])
                        }
                    }
                }.scrollIndicators(.hidden)
                ColorPicker("Vurgu rengi (gönder, mikrofon)", selection: Binding(get: { a.gorunum.vurgu }, set: { a.gorunum.renk = $0.rgbHex }), supportsOpacity: false)
            }
            // `duzen`, `balon`, `zemin`, `baslik`, `durum` ve `hizliKomutlar` alanları eski profillerin
            // çözülebilmesi için GorunumTercihleri'nde duruyor; hiçbir ekrana bağlı olmadıkları için burada denetimleri yok.
            Section("Ses görselleştirmesi") {
                Picker("Görünüm", selection: $a.gorunum.gosterge) { ForEach(GorunumTercihleri.Gosterge.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                LabeledContent("Boyut", value: Self.yuzde(a.gorunum.kureOlcegi))
                Slider(value: $a.gorunum.kureOlcegi, in: 0.7...1.2, step: 0.1).accessibilityLabel("Ses görselinin boyutu")
                Toggle("Animasyonları göster", isOn: $a.gorunum.hareket)
                Text("Boyut, Live ekranındaki büyük küreye uygulanır. iPhone'un Hareketi Azalt ayarı da dikkate alınır.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Mesajlar ve okunabilirlik") {
                LabeledContent("Yazı boyutu", value: Self.yuzde(a.gorunum.yaziOlcegi))
                Slider(value: $a.gorunum.yaziOlcegi, in: 0.9...1.4, step: 0.1).accessibilityLabel("Sohbet yazı boyutu")
                Toggle("Sıkı mesaj aralığı", isOn: $a.gorunum.sik)
                Text("Sohbet yazısı iPhone'un metin boyutuna da uyum sağlar.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Görünüm profilini taşı") {
                Button("Profili dosyaya aktar", systemImage: "square.and.arrow.up") {
                    do { belge = GorunumBelgesi(data: try a.gorunum.veri()); disaAktar = true } catch { mesaj = error.localizedDescription }
                }
                Button("Dosyadan profil yükle", systemImage: "square.and.arrow.down") { iceAktar = true }
                Text("Profil yalnız görünüm ayarlarını içerir. Sohbetler, hesaplar ve API anahtarları dahil edilmez.").font(.footnote).foregroundStyle(.secondary)
                Button("Varsayılan görünüme dön (Karma)", systemImage: "arrow.counterclockwise") { onceki = a.gorunum; a.gorunum = .init(); a.gorunum.sohbet = .karma; a.gorunum.renk = "D97757" }
                if let onceki {
                    Button("Son görünüm değişikliğini geri al", systemImage: "arrow.uturn.backward") { a.gorunum = onceki; self.onceki = nil }
                }
            }
        }
        .navigationTitle("Görünüm stüdyosu")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(a.gorunum.renkSemasi)
        .tint(a.gorunum.metinRengi(sema == .dark))
        .fileExporter(isPresented: $disaAktar, document: belge, contentType: .json, defaultFilename: "Mehmet-Asistan-Gorunum") { sonuc in
            if case .failure(let error) = sonuc { mesaj = error.localizedDescription }
        }
        .fileImporter(isPresented: $iceAktar, allowedContentTypes: [.json]) { sonuc in
            do {
                let url = try sonuc.get(); let erisim = url.startAccessingSecurityScopedResource()
                defer { if erisim { url.stopAccessingSecurityScopedResource() } }
                let boyut = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 16001
                guard boyut <= 16000 else { throw GorunumTercihleri.ProfilHatasi.gecersiz }
                let yeni = try GorunumTercihleri.coz(Data(contentsOf: url))
                onceki = a.gorunum; a.gorunum = yeni; mesaj = "Görünüm profili uygulandı."
            } catch { mesaj = "Profil yüklenemedi. Mevcut görünüm korundu. \(error.localizedDescription)" }
        }
        .alert("Görünüm profili", isPresented: Binding(get: { mesaj != nil }, set: { if !$0 { mesaj = nil } })) { Button("Tamam") { mesaj = nil } } message: { Text(mesaj ?? "") }
    }
    private var onizleme: some View {
        VStack(spacing: 12) {
            HStack { Image(systemName: "line.3.horizontal.decrease"); Spacer(); Text(ayarlar.gorunenAd).font(.caption.bold()); Spacer(); Image(systemName: "slider.horizontal.3") }
            SesGostergesi(duzey: 0.35, etkin: true, profil: ayarlar.gorunum).frame(height: 100 * ayarlar.gorunum.kureOlcegi)
            MesajBalonu(rol: .kullanici, metin: "Bugünü birlikte planlayalım.", etkileşim: false)
            MesajBalonu(rol: .asistan, metin: "Hazırım. Önce en önemli işinden başlayalım.", etkileşim: false)
        }.padding(16).background(SohbetZemini())
    }
}
