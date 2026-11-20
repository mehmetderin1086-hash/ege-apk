import SwiftUI

/// Ezan Vakti Pro Hısnü'l Müslim & Dualar (s5.png) — Okunuş, Anlam ve Sesli Dinleme.
struct DuaView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var adhan: AdhanPlayer

    var body: some View {
        List {
            ForEach(SpiritualContent.duas) { dua in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(dua.title)
                            .font(SekineFont.row(settings.fontScale).weight(.bold))
                            .foregroundStyle(Palette.accent)
                        Spacer()
                        Button {
                            adhan.speakTurkish(
                                text: "\(dua.title). Okunuşu: \(dua.reading). Anlamı: \(dua.meaning)",
                                title: dua.title
                            )
                        } label: {
                            Label("Sesli Dinle", systemImage: "speaker.wave.2.fill")
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Palette.accent.opacity(0.15))
                                .foregroundStyle(Palette.accent)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    Text(dua.reading)
                        .font(SekineFont.caption(settings.fontScale).italic())
                        .foregroundStyle(Palette.textPrimary)
                    Text("“\(dua.meaning)”")
                        .font(SekineFont.caption(settings.fontScale))
                        .foregroundStyle(Palette.textSecondary)
                    Text("— \(dua.source)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.gold)
                }
                .padding(.vertical, 6)
            }
        }
        .navigationTitle("Hısnü'l Müslim & Dualar")
        .navigationBarTitleDisplayMode(.inline)
    }
}
