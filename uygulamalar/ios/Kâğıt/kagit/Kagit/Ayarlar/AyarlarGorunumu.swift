import KagitKit
import SwiftUI

/// Ayarlar sekmesi. Bölümler modüllerin kendi dosyalarındadır.
struct AyarlarGorunumu: View {
    @Environment(Ayarlar.self) private var ayarlar
    @Environment(Kitaplik.self) private var kitaplik

    var body: some View {
        @Bindable var a = ayarlar
        NavigationStack {
            Form {
                Section("Genel") {
                    Toggle("Kapatırken otomatik kaydet", isOn: $a.otomatikKaydet)
                    TextField("Adın (imza ve damgalarda)", text: $a.yazarAdi)
                }
                GuvenlikAyarlari()
                ImzaDamgaAyarlari()
                OgretmenAyarlari()
                YapayZekaAyarlari()
                BulutAyarlari()
                Section("Depolama") {
                    LabeledContent("Belge sayısı", value: "\(kitaplik.belgeler.count)")
                    LabeledContent("Toplam boyut", value: BicimYardimci.boyut(kitaplik.belgeler.reduce(0) { $0 + $1.boyut }))
                    Button("Geçici dosyaları temizle") { Gecici.temizle() }
                }
                Section("Hakkında") {
                    LabeledContent("Sürüm", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                    Text("Belgeler telefonunda kalır. Yalnız Office dönüşümü ve bulut yapay zekâ, açıksa, kendi sunucuna gider. PDF motoru: PDFKit + PDFium (BSD). Yazı tipleri: Noto (OFL).")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Ayarlar")
        }
    }
}
