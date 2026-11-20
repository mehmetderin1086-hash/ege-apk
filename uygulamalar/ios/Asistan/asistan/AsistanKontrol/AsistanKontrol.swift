import WidgetKit
import SwiftUI
import AppIntents

/// Kontrol Merkezi, kilit ekranı ve Action Button'a atanabilen tek düğme.
struct AsistanKontrol: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.mehmetderin.asistan.kontrol") {
            ControlWidgetButton(action: AsistaniBaslatIntent()) {
                Label("Asistan", systemImage: "waveform.circle.fill")
            }
        }
        .displayName("Asistan'ı başlat")
        .description("Asistan'ı açar ve dinlemeye başlar.")
    }
}

/// Denetim Merkezi'ne ayrıca eklenebilen, doğrudan Live mod düğmesi.
struct AsistanCanliKontrol: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.mehmetderin.asistan.canli-kontrol") {
            ControlWidgetButton(action: AsistanCanliBaslatIntent()) {
                Label("Canlı konuş", systemImage: "waveform.badge.mic")
            }
        }
        .displayName("Canlı konuşma")
        .description("Asistan'ı canlı sesli konuşmada açar.")
    }
}

/// P4.2: uygulamayı açmadan tek sesli komut (AsistanBasKonusIntent, AudioRecordingIntent). Kilit ekranı ve Action Button için.
struct AsistanBasKonusKontrol: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.mehmetderin.asistan.bas-konus-kontrol") {
            ControlWidgetButton(action: AsistanBasKonusIntent()) {
                Label("Bas konuş", systemImage: "mic.circle.fill")
            }
        }
        .displayName("Bas konuş")
        .description("Uygulamayı açmadan tek sesli komut alır ve yanıtı sesli söyler.")
    }
}

/// P4.2: kullanıcının eklerken seçtiği kipte (dinle, canlı + kamera, son sohbet, sabah özeti) Asistan'ı açar.
struct AsistanKipliKontrol: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "com.mehmetderin.asistan.kipli-kontrol", intent: AsistanKipliYapilandirma.self) { y in
            ControlWidgetButton(action: AsistanKipliBaslatIntent(kip: y.kip)) {
                Label(y.kip.baslik, systemImage: y.kip.simge)
            }
        }
        .displayName("Asistan kipi")
        .description("Seçtiğin kipte açar: dinle, canlı + kamera, son sohbete devam ya da sabah özeti.")
        .promptsForUserConfiguration()
    }
}

/// P4.2: Hey Asistan ayarını Kontrol Merkezi'nden açıp kapatır (App Group; uygulama öne gelince uyar).
struct AsistanHeyKontrol: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: OrtakAyarlar.heyKontrolTuru, provider: HeyDegeri()) { acik in
            ControlWidgetToggle("Hey Asistan", isOn: acik, action: HeyAsistanAyarlaIntent()) { acik in
                Label(acik ? "Açık" : "Kapalı", systemImage: acik ? "ear.badge.waveform" : "ear")
            }
        }
        .displayName("Hey Asistan")
        .description("Uygulama açıkken Hey Asistan dinlemesini açar ya da kapatır.")
    }
}

/// Hey Asistan kontrolünün değeri: App Group'tan okunur, hiç yazılmamışsa uygulamanın varsayılanı (açık).
nonisolated struct HeyDegeri: ControlValueProvider {
    var previewValue: Bool { true }
    func currentValue() async throws -> Bool { OrtakAyarlar.heyAsistan ?? true }
}

@main
struct AsistanKontrolBundle: WidgetBundle {
    var body: some Widget {
        AsistanKontrol()
        AsistanCanliKontrol()
        // P4.2: bas-konuş, kipli başlatma ve Hey Asistan anahtarı (var olan iki kontrolün türleri değişmez).
        AsistanBasKonusKontrol()
        AsistanKipliKontrol()
        AsistanHeyKontrol()
        AsistanAlarmAktivitesi()
        AsistanIsAktivitesi()
        // P3.11: ana ekran ve kilit ekranı widget'ları (AsistanWidgetlari.swift).
        KonusWidget()
        BugunWidget()
        HizliSorWidget()
    }
}
