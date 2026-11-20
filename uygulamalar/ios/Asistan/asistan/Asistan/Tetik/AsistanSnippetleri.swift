import AppIntents
import SwiftUI

/// P4.4: Siri / Kestirmeler yanıt kartı. `AsistanaSorIntent` yerel ya da yarış yanıtını sesli okurken bu kartı da gösterir:
/// yanıtın ilk 600 karakteri + "Uygulamada aç" (kaydedilen sohbet, `SonucuAcIntent`) ve "Yeni soru" (`AsistanaSorIntent`).
struct YanitKartiIntent: SnippetIntent {
    static let title: LocalizedStringResource = "Asistan yanıtı"
    static let isDiscoverable = false

    @Parameter(title: "Yanıt") var metin: String
    @Parameter(title: "Sohbet") var sohbetKimligi: String?

    init() {}
    init(metin: String, sohbetKimligi: String?) {
        self.metin = metin
        self.sohbetKimligi = sohbetKimligi
    }

    @MainActor func perform() async throws -> some IntentResult & ShowsSnippetView {
        .result(view: YanitKarti(metin: metin, sohbetKimligi: sohbetKimligi))
    }
}

/// Snippet görünümü: sistem çizer (uygulama penceresi yok), bu yüzden ortam nesnesi kullanılmaz; renk vurgusu sabit.
struct YanitKarti: View {
    let metin: String
    let sohbetKimligi: String?

    /// Saf: kartta gösterilen metin (Markdown işaretleri temizlenmiş, en çok 600 karakter).
    static func kartMetni(_ metin: String) -> String {
        let duz = Konusmaci.okunabilir(metin).trimmingCharacters(in: .whitespacesAndNewlines)
        return duz.count > 600 ? String(duz.prefix(599)) + "…" : duz
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Asistan", systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(Color(red: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255))
            Text(Self.kartMetni(metin))
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                if let sohbetKimligi, UUID(uuidString: sohbetKimligi) != nil {
                    Button(intent: SonucuAcIntent(sohbetID: sohbetKimligi)) {
                        Label("Uygulamada aç", systemImage: "arrow.up.forward.app")
                    }
                }
                Button(intent: AsistanaSorIntent()) {
                    Label("Yeni soru", systemImage: "questionmark.bubble")
                }
            }
            .buttonStyle(.bordered)
            .font(.callout)
        }
        .padding()
    }
}
