import SwiftUI

/// P3.12: Ayarlar > Ses ve Live > 'Kulaklık ve okuma' bölümü (SesVeLiveAyarlari'nın Form'unda).
/// Arama dizini kayıtları `AyarDizini.hepsi`'nde: kulaklik-mikrofonu, kulaklik-dugmesi, akilli-konusma-sonu, ilk-ses-hizli, okuma-hizi.
struct SesHattiAyarBolumu: View {
    @Environment(Ayarlar.self) private var ayarlar
    @Environment(SesOturumu.self) private var ses

    var body: some View {
        @Bindable var a = ayarlar
        Section("Kulaklık ve okuma") {
            Toggle("Kulaklık mikrofonu", isOn: $a.kulaklikMikrofonu)
                .accessibilityIdentifier("ayar-kulaklik-mikrofonu")
            Text("Açıkken AirPods mikrofonu kullanılır; sesli kipte kulaklık sesi telefon kalitesine düşer. Kutudaki kulaklıkta 5 dk dahili mikrofona dönülür.")
                .font(.footnote).foregroundStyle(.secondary)
            Toggle("Kulaklık düğmesi", isOn: $a.kumanda)
                .accessibilityIdentifier("ayar-kulaklik-dugmesi")
                .onChange(of: ayarlar.kumanda) { _, acik in if !acik { ses.kumanda.coz() } }
            Text("Açıkken sesli kipte müzik kısılmaz, durur; AirPods'a bir kez bas: duraklat/gönder, iki kez: sözü al.")
                .font(.footnote).foregroundStyle(.secondary)
            Toggle("Akıllı konuşma sonu", isOn: $a.akilliKonusmaSonu)
                .accessibilityIdentifier("ayar-akilli-konusma-sonu")
            Text("Kısa komutlar çabuk gönderilir; virgülde ya da 've, ama, çünkü' gibi bağlaçta durursan biraz daha beklenir.")
                .font(.footnote).foregroundStyle(.secondary)
            Toggle("İlk sesi hızlı başlat", isOn: $a.ilkSesHizli)
                .accessibilityIdentifier("ayar-ilk-ses-hizli")
            Text("Uzun ilk cümlede okuma ilk virgülde başlar, cümlenin bitmesi beklenmez.")
                .font(.footnote).foregroundStyle(.secondary)
            Picker("Okuma hızı", selection: Binding(get: { Float(ayarlar.okumaHizi) }, set: { ses.konusmaci.hiziDegistir($0) })) {
                ForEach(OkumaCubugu.hizlar, id: \.self) { Text(OkumaCubugu.hizEtiketi($0)).tag($0) }
            }
            .accessibilityIdentifier("ayar-okuma-hizi")
        }
    }
}
