import SwiftUI

/// P4.7: Sürüş kipi ayarları (Ayarlar kökündeki "Sürüş kipi" satırı). Bölüm `SurusKipiAyarBolumu` olarak da
/// Ses ve Live sayfasına gömülebilir.
struct SurusKipiAyarlari: View {
    var body: some View {
        Form { SurusKipiAyarBolumu() }
            .navigationTitle("Sürüş kipi")
    }
}

/// Otomatik (CarPlay) ve elle açma anahtarları, etkin kipin durumu, "Bu sürüşte kapat" ve ertelenen istekler.
struct SurusKipiAyarBolumu: View {
    @Environment(Ayarlar.self) private var ayarlar
    @State private var kip = SurusKipi.ortak

    var body: some View {
        @Bindable var a = ayarlar
        Section {
            Toggle("Arabaya bağlanınca sürüş kipi", isOn: $a.surusKipiOtomatik)
                .accessibilityIdentifier("surus-kipi-anahtari")
            Toggle("Sürüş kipini şimdi aç", isOn: $a.surusKipiElle)
                .accessibilityIdentifier("surus-kipi-elle")
            if kip.aktif {
                Label("Şu an sürüş kipinde", systemImage: "car.fill")
                    .foregroundStyle(.tint)
                    .accessibilityIdentifier("surus-kipi-durum")
                Button("Bu sürüşte kapat") { kip.buSurusteKapat() }
                    .accessibilityIdentifier("surus-kipi-kapat")
            }
        } header: {
            Text("Sürüş kipi")
        } footer: {
            Text("CarPlay'e bağlanınca yanıtlar en çok iki kısa cümle olur, onay sesle sorulur, belge ve tablo üretimi ertelenir; araba bağlantısı kesilince ertelenen istek bildirimle hatırlatılır. CarPlay'siz araç kitinde 'Sürüş kipini şimdi aç' anahtarını kullan.")
        }
        if !kip.ertelenenler.isEmpty {
            Section("Sürüşte ertelenenler") {
                ForEach(kip.ertelenenler, id: \.self) { istek in
                    HStack {
                        Text(istek).lineLimit(2)
                        Spacer(minLength: 8)
                        Button("Gönder") {
                            kip.cikar([istek])
                            GorevKopru.ortak.teslimEt(istek)
                        }
                        .buttonStyle(.borderless)
                        .disabled(kip.aktif)
                    }
                }
                Button("Listeyi temizle", role: .destructive) { kip.cikar(kip.ertelenenler) }
                    .accessibilityIdentifier("surus-ertelenen-temizle")
            }
        }
    }
}
