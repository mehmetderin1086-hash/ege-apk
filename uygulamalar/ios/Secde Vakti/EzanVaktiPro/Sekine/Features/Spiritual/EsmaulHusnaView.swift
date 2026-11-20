import SwiftUI

/// Ezan Vakti Pro Esmaü'l Hüsna (s6.png) — 99 İsim, Arapça Hat, Türkçe Anlam ve Sesli Dinleme.
struct EsmaulHusnaView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var adhan: AdhanPlayer
    @State private var query = ""
    @State private var showGalleryCards = true

    private var items: [EsmaName] {
        guard !query.isEmpty else { return SpiritualContent.esmaulHusna }
        let q = query.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        return SpiritualContent.esmaulHusna.filter {
            ($0.name + " " + $0.meaning)
                .folding(options: .diacriticInsensitive, locale: .current)
                .lowercased().contains(q)
        }
    }

    var body: some View {
        Group {
            if showGalleryCards {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            VStack(spacing: 10) {
                                HStack {
                                    Text("#\(index + 1)")
                                        .font(.caption.weight(.bold))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(.white.opacity(0.25))
                                        .clipShape(Capsule())
                                    Spacer()
                                    Button {
                                        adhan.speakTurkish(
                                            text: "\(item.name) Celle Celâlühû. Anlamı: \(item.meaning)",
                                            title: item.name
                                        )
                                    } label: {
                                        Label("Sesli Dinle", systemImage: "play.circle.fill")
                                            .font(.caption.weight(.bold))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(.white.opacity(0.3))
                                            .clipShape(Capsule())
                                    }
                                }
                                .foregroundStyle(Color(red: 0.10, green: 0.24, blue: 0.28))

                                Text(Self.arabicCalligraphy(for: index))
                                    .font(.system(size: 54, weight: .bold))
                                    .foregroundStyle(Color(red: 0.08, green: 0.28, blue: 0.32))
                                    .padding(.vertical, 4)

                                Text("\(item.name) c.c.")
                                    .font(.title2.weight(.bold))
                                    .foregroundStyle(Color(red: 0.08, green: 0.18, blue: 0.22))

                                Text(item.meaning)
                                    .font(.subheadline)
                                    .foregroundStyle(Color(red: 0.15, green: 0.25, blue: 0.28))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 12)
                            }
                            .padding(20)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .fill(
                                        index % 2 == 0
                                            ? Color(red: 0.76, green: 0.91, blue: 0.96)
                                            : Color(red: 0.78, green: 0.94, blue: 0.82)
                                    )
                            )
                        }
                    }
                    .padding(16)
                }
                .background(Palette.background.ignoresSafeArea())
            } else {
                List {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(Palette.textSecondary)
                                .frame(width: 26, alignment: .trailing)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.name)
                                    .font(SekineFont.row(settings.fontScale))
                                    .foregroundStyle(Palette.accent)
                                Text(item.meaning)
                                    .font(SekineFont.caption(settings.fontScale))
                                    .foregroundStyle(Palette.textPrimary)
                            }
                            Spacer()
                            Button {
                                adhan.speakTurkish(text: "\(item.name). \(item.meaning)", title: item.name)
                            } label: {
                                Image(systemName: "speaker.wave.2.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(Palette.accent)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "İsim veya anlam ara")
        .navigationTitle("Esmaü'l Hüsna (99)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showGalleryCards.toggle()
                } label: {
                    Image(systemName: showGalleryCards ? "list.bullet" : "rectangle.grid.1x2.fill")
                }
            }
        }
    }

    private static let arabicNames: [String] = [
        "اللَّهُ", "الرَّحْمَنُ", "الرَّحِيمُ", "الْمَلِكُ", "الْقُدُّوسُ", "السَّلَامُ", "الْمُؤْمِنُ", "الْمُهَيْمِنُ", "الْعَزِيزُ", "الْجَبَّارُ",
        "الْمُتَكَبِّرُ", "الْخَالِقُ", "الْبَارِئُ", "الْمُصَوِّرُ", "الْغَفَّارُ", "الْقَهَّارُ", "الْوَهَّابُ", "الرَّزَّاقُ", "الْفَتَّاحُ", "الْعَلِيمُ"
    ]

    private static func arabicCalligraphy(for index: Int) -> String {
        if index < arabicNames.count { return arabicNames[index] }
        return "اللَّهُ جَلَّ جَلَالُهُ"
    }
}
