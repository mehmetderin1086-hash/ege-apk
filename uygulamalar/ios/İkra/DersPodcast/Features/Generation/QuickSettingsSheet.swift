import SwiftUI

/// #40: türev bölümler (özet, eksik konu, video, "Farkı ne?") için kısa ayar sayfası.
/// Çağıranın koyduğu bölüme özgü bağlam (seri, yönergeler, türev) korunur; profil yalnız görünen ayarları değiştirir.
struct QuickSettingsSheet: View {
    let initial: PodcastSettings
    let title: String
    let onConfirm: (PodcastSettings) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var settings: PodcastSettings
    @State private var profileName = ""

    init(initial: PodcastSettings, title: String, onConfirm: @escaping (PodcastSettings) -> Void) {
        self.initial = initial
        self.title = title
        self.onConfirm = onConfirm
        _settings = State(initialValue: initial)
    }

    @AppStorage(AppVoice.primaryKey) private var appVoiceRaw = ""
    @AppStorage(AppVoice.secondaryKey) private var appVoiceRaw2 = ""

    /// Kayıtlı son ayarlardan başlangıç (bölüme özgü bağlam temizlenmiş), Ayarlar'daki sesle.
    static func defaultInitial() -> PodcastSettings {
        let data = UserDefaults.standard.data(forKey: "lastSettings") ?? Data()
        return ((try? JSONDecoder().decode(PodcastSettings.self, from: data)) ?? PodcastSettings()).reusable.withAppVoice
    }

    /// Profil uygulanır, bağlam alanları başlangıçtan korunur (saf; test edilir).
    nonisolated static func applying(_ profile: PodcastSettings, keepingContextOf base: PodcastSettings) -> PodcastSettings {
        var s = profile.reusable
        s.series = base.series
        s.directives = base.directives
        s.recallFirst = base.recallFirst
        s.derivation = base.derivation
        s.focus = base.focus
        return s
    }

    var body: some View {
        NavigationStack {
            Form {
                let profiles = PodcastProfiles.all
                if !profiles.isEmpty {
                    Section("Profil") {
                        ForEach(profiles) { profile in
                            Button {
                                settings = Self.applying(profile.settings, keepingContextOf: initial).withAppVoice
                            } label: {
                                Label(profile.name, systemImage: "person.crop.rectangle.stack")
                            }
                        }
                    }
                }
                Section("Süre") {
                    Picker("Süre", selection: $settings.durationMin) {
                        ForEach(PodcastSettings.durations, id: \.self) { Text($0 == 60 ? "1 saat" : "\($0) dk").tag($0) }
                    }
                }
                Section("Anlatım") {
                    Picker("Biçim", selection: $settings.format) {
                        ForEach(PodcastFormat.allCases.filter { settings.engine.supportsTwoHosts || !$0.usesTwoHosts }) { Text($0.title).tag($0) }
                    }
                    Picker("Derinlik", selection: $settings.depth) {
                        ForEach(PodcastDepth.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Tempo", selection: $settings.pace) {
                        ForEach(PodcastPace.allCases) { Text($0.title).tag($0) }
                    }
                }
                // Tek ses ayarı (Ayarlar › Ses ile aynı); değişince podcast ayarları sesten yeniden kurulur.
                Section("Ses") {
                    AppVoiceSettingRow(title: "Anlatıcı sesi", slot: .primary)
                    if settings.format.usesTwoHosts { AppVoiceSettingRow(title: "İkinci ses", slot: .secondary) }
                }
                .onChange(of: appVoiceRaw) { _, _ in settings.applyAppVoice() }
                .onChange(of: appVoiceRaw2) { _, _ in settings.applyAppVoice() }
                Section {
                    TextField("Profil adı (isteğe bağlı)", text: $profileName)
                    Button("Bu ayarları profil olarak kaydet", systemImage: "square.and.arrow.down") {
                        PodcastProfiles.save(profileName, settings: settings)
                        profileName = ""
                    }
                    .disabled(profileName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Oluştur") {
                        onConfirm(settings)
                        dismiss()
                    }
                }
            }
        }
    }
}
