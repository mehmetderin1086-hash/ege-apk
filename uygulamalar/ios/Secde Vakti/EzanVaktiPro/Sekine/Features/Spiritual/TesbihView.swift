import SwiftUI
import StoreKit

/// Ezan Vakti Pro 3D Dikey Boncuklu Zikirmatik (s7.png) + Klasik Halka Sayaç + Sesli Zikir.
struct TesbihView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var adhan: AdhanPlayer
    @Environment(\.requestReview) private var requestReview

    @AppStorage("tesbih.count") private var count = 0
    @AppStorage("tesbih.target") private var target = 33
    @AppStorage("tesbih.zikirIndex") private var zikirIndex = 0
    @AppStorage("tesbih.rounds") private var rounds = 0
    @AppStorage("tesbih.beadMode") private var useBeadMode = true
    @AppStorage("tesbih.voiceEnabled") private var voiceEnabled = false

    struct ZikirOption {
        let title: String
        let arabic: String
        let meaning: String
    }

    private static let zikirler: [ZikirOption] = [
        .init(title: "Sübhânallah", arabic: "سُبْحَانَ اللَّهِ", meaning: "Allah'ı tüm eksikliklerden tenzih ederim"),
        .init(title: "Elhamdülillah", arabic: "الْحَمْدُ لِلَّهِ", meaning: "Hamd yalnız Allah'a mahsustur"),
        .init(title: "Allâhu Ekber", arabic: "اللَّهُ أَكْبَرُ", meaning: "Allah en büyüktür"),
        .init(title: "Lâ Havle Velâ Kuvvete İllâ Billâh", arabic: "لَا حَوْلَ وَلَا قُوَّةَ إِلَّا بِاللَّهِ", meaning: "Güç ve kuvvet yalnız Allah'tandır"),
        .init(title: "Estağfirullah el-Azîm", arabic: "أَسْتَغْفِرُ اللَّهَ الْعَظِيمَ", meaning: "Yüce Allah'tan mağfiret dilerim"),
        .init(title: "Allâhümme Salli Alâ Muhammed", arabic: "اللَّهُمَّ صَلِّ عَلَى مُحَمَّدٍ", meaning: "Allah'ım! Efendimiz Muhammed'e salât eyle"),
        .init(title: "Lâ İlâhe İllallâh", arabic: "لَا إِلٰهَ إِلَّا اللَّهُ", meaning: "Allah'tan başka ilâh yoktur")
    ]

    private var currentZikir: ZikirOption {
        Self.zikirler[zikirIndex % Self.zikirler.count]
    }

    var body: some View {
        VStack(spacing: 18) {
            // Üst Zikir Seçici ve Mod Değiştirici
            HStack {
                Menu {
                    ForEach(Array(Self.zikirler.enumerated()), id: \.offset) { idx, z in
                        Button {
                            zikirIndex = idx
                        } label: {
                            Text("\(z.title) — \(z.meaning)")
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(currentZikir.title.uppercased())
                            .font(.headline.weight(.bold))
                        Image(systemName: "chevron.down.circle.fill")
                    }
                    .foregroundStyle(Palette.accent)
                }

                Spacer()

                Button {
                    voiceEnabled.toggle()
                } label: {
                    Image(systemName: voiceEnabled ? "speaker.wave.2.circle.fill" : "speaker.slash.circle")
                        .font(.title2)
                        .foregroundStyle(voiceEnabled ? Palette.gold : Palette.textSecondary)
                }

                Button {
                    withAnimation(.spring(response: 0.35)) {
                        useBeadMode.toggle()
                    }
                } label: {
                    Label(useBeadMode ? "3D Boncuk" : "Kadran", systemImage: useBeadMode ? "circle.grid.cross.fill" : "circle.dotted")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Palette.card)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 8)

            VStack(spacing: 4) {
                Text(currentZikir.arabic)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Palette.gold)
                Text(currentZikir.meaning)
                    .font(.caption)
                    .foregroundStyle(Palette.textSecondary)
            }

            if useBeadMode {
                ezanVaktiProBeadCounter
            } else {
                classicCircleCounter
            }

            controls
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle("3D Zikirmatik")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Ezan Vakti Pro s7.png Birebir 3D Dikey Kehribar Boncuklu Tasarım
    private var ezanVaktiProBeadCounter: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(count)")
                    .font(.system(size: 86 * settings.fontScale.multiplier, weight: .bold, design: .rounded)
                        .monospacedDigit())
                    .foregroundStyle(Palette.textPrimary)
                    .contentTransition(.numericText())

                HStack(spacing: 6) {
                    Image(systemName: "arrow.2.squarepath")
                    Text("Tur: \(rounds) · Hedef: \(target)")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.textSecondary)

                Text("Boncuklara veya ekrana dokunarak çekin")
                    .font(.caption)
                    .foregroundStyle(Palette.textSecondary.opacity(0.8))
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Sağda Dikey 3D Kehribar/İnci Tesbih İpi ve Boncukları (s7.png)
            ZStack {
                // Tesbih İpi
                VStack(spacing: 8) {
                    ForEach(0..<18, id: \.self) { _ in
                        Capsule()
                            .fill(Palette.textSecondary.opacity(0.35))
                            .frame(width: 3, height: 8)
                    }
                }

                VStack(spacing: 14) {
                    ForEach(0..<6, id: \.self) { idx in
                        let sizes: [CGFloat] = [22, 34, 48, 66, 54, 40]
                        let isPulled = idx >= 3
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: isPulled
                                        ? [Color(red: 0.98, green: 0.85, blue: 0.68), Color(red: 0.76, green: 0.46, blue: 0.22), Color(red: 0.52, green: 0.28, blue: 0.10)]
                                        : [Color.white, Color(white: 0.82), Color(white: 0.68)],
                                    center: .init(x: 0.35, y: 0.32),
                                    startRadius: 2,
                                    endRadius: sizes[idx] * 0.6
                                )
                            )
                            .frame(width: sizes[idx], height: sizes[idx])
                            .shadow(color: .black.opacity(0.22), radius: 5, x: 0, y: 4)
                            .offset(y: CGFloat(count % 2 == 0 ? 0 : 4))
                            .animation(.spring(response: 0.22, dampingFraction: 0.6), value: count)
                    }
                }
            }
            .frame(width: 96, height: 340)
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: 360)
        .contentShape(Rectangle())
        .onTapGesture { increment() }
    }

    private var classicCircleCounter: some View {
        ZStack {
            Circle()
                .stroke(Palette.separator, lineWidth: 14)
            Circle()
                .trim(from: 0, to: min(1, Double(count) / Double(max(1, target))))
                .stroke(Palette.accent, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.2), value: count)
            VStack(spacing: 2) {
                Text("\(count)")
                    .font(.system(size: 72 * settings.fontScale.multiplier, weight: .bold, design: .rounded)
                        .monospacedDigit())
                    .foregroundStyle(Palette.textPrimary)
                Text("/ \(target)")
                    .font(SekineFont.caption(settings.fontScale))
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .frame(width: 250, height: 250)
        .contentShape(Circle())
        .onTapGesture { increment() }
    }

    private var controls: some View {
        HStack(spacing: 14) {
            Picker("Hedef", selection: $target) {
                Text("33").tag(33)
                Text("99").tag(99)
                Text("500").tag(500)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 200)

            Button {
                reset()
            } label: {
                Label("Sıfırla", systemImage: "arrow.counterclockwise")
                    .font(SekineFont.caption(settings.fontScale))
            }
            .buttonStyle(.bordered)
            .tint(Palette.accent)
        }
    }

    private func increment() {
        count += 1
        if voiceEnabled && (count == 1 || count % 11 == 0) {
            adhan.speakTurkish(text: currentZikir.title, title: currentZikir.title)
        }
        if count >= target {
            count = 0
            rounds += 1
            zikirIndex += 1
            haptic(.heavy)
            askForReviewAfterRound()
        } else {
            haptic(.light)
        }
    }

    private func askForReviewAfterRound() {
        let prompt = ReviewPrompt()
        let version = ReviewPrompt.currentVersion
        guard prompt.shouldAsk(version: version, positiveMoment: true) else { return }
        prompt.markAsked(version: version)
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            requestReview()
        }
    }

    private func reset() {
        count = 0
        haptic(.medium)
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}
