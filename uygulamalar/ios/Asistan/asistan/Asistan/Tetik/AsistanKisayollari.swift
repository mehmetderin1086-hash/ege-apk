import AppIntents

struct AsistanKisayollari: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AsistaniBaslatIntent(),
            phrases: [
                "\(.applicationName) başlat",
                "\(.applicationName) ile konuş",
                "\(.applicationName) dinle",
                "\(.applicationName) aç",
            ],
            shortTitle: "Asistan'ı başlat",
            systemImageName: "waveform.circle.fill"
        )
        AppShortcut(
            intent: GelenKutusunuAcIntent(),
            phrases: ["\(.applicationName) gelen kutumu aç", "\(.applicationName) iletilerimi göster"],
            shortTitle: "Gelen kutusunu aç",
            systemImageName: "tray.full.fill"
        )
        AppShortcut(intent: AsistanCanliBaslatIntent(), phrases: ["\(.applicationName) canlı konuş", "\(.applicationName) canlı mod"], shortTitle: "Canlı konuş", systemImageName: "waveform.badge.mic")
        AppShortcut(intent: AsistanAtolyeAcIntent(), phrases: ["\(.applicationName) atölyeyi aç", "\(.applicationName) araştırma yap"], shortTitle: "Atölyeyi aç", systemImageName: "sparkles")
        AppShortcut(intent: AsistanIndirmeleriniAcIntent(), phrases: ["\(.applicationName) indirmeleri aç"], shortTitle: "İndirmeleri aç", systemImageName: "arrow.down.circle.fill")
        AppShortcut(intent: AsistanTelefonIslemleriniAcIntent(), phrases: ["\(.applicationName) telefon işlemlerini aç"], shortTitle: "Telefon işlemleri", systemImageName: "square.grid.2x2")
        AppShortcut(intent: AsistanDosyaDonusturIntent(), phrases: ["\(.applicationName) dosya dönüştür"], shortTitle: "Dosya dönüştür", systemImageName: "arrow.triangle.2.circlepath.doc.on.clipboard")
        // 10 kısa yol sınırı: "Arşivi aç" Kestirmeler'de niyet olarak durur; yerine uygulamayı açmadan soru.
        AppShortcut(intent: AsistanaSorIntent(), phrases: ["\(.applicationName)'a sor", "\(.applicationName) ile soru sor", "\(.applicationName) bir şey soracağım"], shortTitle: "Asistan'a sor", systemImageName: "questionmark.bubble.fill")
        AppShortcut(intent: AsistanUretkenligiAcIntent(), phrases: ["\(.applicationName) üretkenliği aç", "\(.applicationName) çalışma alanını aç"], shortTitle: "Üretkenlik", systemImageName: "briefcase.fill")
        // P4.2: uygulamayı açmadan tek sesli komut (AudioRecordingIntent). 10/10 dolu: yeni kısa yol için biri çıkarılmalı.
        // "dinle" cümlesi AsistaniBaslatIntent'te kaldığı için buradaki cümleler ondan farklıdır.
        AppShortcut(intent: AsistanBasKonusIntent(), phrases: ["\(.applicationName) bas konuş", "\(.applicationName) dinle beni"], shortTitle: "Bas konuş", systemImageName: "mic.circle.fill")
    }
}
