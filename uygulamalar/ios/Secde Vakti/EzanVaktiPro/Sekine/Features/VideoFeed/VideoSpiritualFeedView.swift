import SwiftUI
import AVKit
import AVFoundation

/// Gerçek MP4 video dosyasını kesintisiz döngüde oynatan UIKit AVPlayerLayer sarmalayıcısı.
struct LoopingMP4VideoView: UIViewRepresentable {
    let resourceName: String
    let isMuted: Bool

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.configure(resourceName: resourceName, isMuted: isMuted)
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        uiView.configure(resourceName: resourceName, isMuted: isMuted)
    }

    final class PlayerContainerView: UIView {
        private var queuePlayer: AVQueuePlayer?
        private var playerLooper: AVPlayerLooper?
        private var currentResource: String?

        override class var layerClass: AnyClass {
            AVPlayerLayer.self
        }

        var playerLayer: AVPlayerLayer {
            layer as! AVPlayerLayer
        }

        func configure(resourceName: String, isMuted: Bool) {
            playerLayer.videoGravity = .resizeAspectFill
            if currentResource == resourceName, let queuePlayer {
                queuePlayer.isMuted = isMuted
                if queuePlayer.timeControlStatus != .playing {
                    queuePlayer.play()
                }
                return
            }
            currentResource = resourceName
            queuePlayer?.pause()
            playerLooper = nil

            guard let url = Bundle.main.url(forResource: resourceName, withExtension: "mp4") else { return }
            let asset = AVAsset(url: url)
            let item = AVPlayerItem(asset: asset)
            let player = AVQueuePlayer(playerItem: item)
            player.isMuted = isMuted
            let looper = AVPlayerLooper(player: player, templateItem: item)
            self.queuePlayer = player
            self.playerLooper = looper
            self.playerLayer.player = player
            player.play()
        }
    }
}

/// Canlı Ses Dalgası (Waveform) animasyonu.
struct LiveAudioWaveformView: View {
    let isPlaying: Bool
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.08, paused: !isPlaying)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<22, id: \.self) { i in
                    let wave = isPlaying
                        ? abs(sin(t * 5.2 + Double(i) * 0.45)) * 26 + 6
                        : 5
                    Capsule()
                        .fill(color.gradient)
                        .frame(width: 4, height: wave)
                }
            }
            .frame(height: 34)
        }
    }
}

/// Namaz Vakitlerinde Sesli Video Ayet & Hadis Merkezi (Reels / Sinematik Vakit Modu).
struct VideoSpiritualFeedView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: PrayerTimeStore
    @EnvironmentObject private var adhan: AdhanPlayer

    @State private var selectedPrayer: Prayer = .maghrib
    @State private var showFullScreenAlarm = false
    @State private var notificationToast: String?
    @State private var isVideoSoundMuted = true

    private var activePacket: VakitSpiritualPacket {
        VakitSpiritualDatabase.packet(for: selectedPrayer)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        prayerSelectorBar
                        videoHeroPlayerCard
                        audioControlPanel
                        verseDetailCard
                        hadithDetailCard
                        duaDetailCard
                        testAndNotificationActionsCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }

                if let toast = notificationToast {
                    VStack {
                        Spacer()
                        HStack(spacing: 10) {
                            Image(systemName: "bell.badge.fill")
                                .foregroundStyle(.yellow)
                            Text(toast)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial)
                        .background(Color.black.opacity(0.75))
                        .clipShape(Capsule())
                        .padding(.bottom, 24)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle("Sesli Video Ayet & Hadis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showFullScreenAlarm = true
                    } label: {
                        Label("Tam Ekran", systemImage: "play.rectangle.fill")
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
            .fullScreenCover(isPresented: $showFullScreenAlarm) {
                FullScreenAdhanAlarmView(prayer: selectedPrayer)
            }
            .onAppear {
                if let current = store.schedule?.currentTime(at: Date())?.prayer {
                    selectedPrayer = current
                } else if let next = store.schedule?.nextTime(after: Date())?.prayer {
                    selectedPrayer = next
                }
            }
        }
    }

    // MARK: - Vakit Seçici Bar
    private var prayerSelectorBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Prayer.ordered) { prayer in
                    let isSelected = prayer == selectedPrayer
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            selectedPrayer = prayer
                        }
                        if adhan.isPlaying {
                            adhan.playFullVakitPacket(VakitSpiritualDatabase.packet(for: prayer))
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: prayer.systemImage)
                            Text(prayer.displayName)
                                .fontWeight(.semibold)
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(isSelected ? Palette.accent : Palette.card)
                        .foregroundStyle(isSelected ? Color.white : Palette.textPrimary)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(isSelected ? Color.clear : Palette.separator, lineWidth: 1)
                        )
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    // MARK: - Sinematik MP4 Video Hero Kartı
    private var videoHeroPlayerCard: some View {
        ZStack(alignment: .bottom) {
            LoopingMP4VideoView(resourceName: activePacket.videoFileName, isMuted: isVideoSoundMuted)
                .frame(height: 430)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Palette.gold.opacity(0.6), lineWidth: 1.5)
                )

            // Üst rozet ve Tam Ekran / Ses kontrolü
            VStack {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles.tv.fill")
                            .foregroundStyle(.yellow)
                        Text(activePacket.badgeTitle)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.55))
                    .clipShape(Capsule())

                    Spacer()

                    Button {
                        showFullScreenAlarm = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                            Text("Tam Ekran")
                        }
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.55))
                        .clipShape(Capsule())
                    }
                }
                .padding(14)

                Spacer()

                // Alt Canlı Ses Dalgası & Durum Çubuğu
                VStack(spacing: 8) {
                    LiveAudioWaveformView(isPlaying: adhan.isPlaying, color: .yellow)

                    if adhan.isPlaying {
                        VStack(spacing: 2) {
                            Text(adhan.activeTitle)
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(.white)
                            Text(adhan.activeSubtitle)
                                .font(.caption2)
                                .foregroundStyle(.yellow)
                        }
                    } else {
                        Text("Sesli Ayet, Meal, Hadis veya Tam Ezan dinlemek için aşağıdan başlatın")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .background(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.82)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .frame(height: 430)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    // MARK: - Sesli Okuma Kontrol Paneli
    private var audioControlPanel: some View {
        VStack(spacing: 10) {
            Button {
                if adhan.isPlaying && adhan.mode == .fullVakitCombo {
                    adhan.stop()
                } else {
                    adhan.playFullVakitPacket(activePacket)
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: (adhan.isPlaying && adhan.mode == .fullVakitCombo) ? "stop.circle.fill" : "play.circle.fill")
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text((adhan.isPlaying && adhan.mode == .fullVakitCombo)
                             ? "Sesli Vakit Paketini Durdur"
                             : "Tam Vakit Paketini Sesli Dinle")
                            .font(.headline.weight(.bold))
                        Text("Arapça Tilavet + Türkçe Sesli Meal + Hadis-i Şerif + Dua")
                            .font(.caption)
                            .opacity(0.9)
                    }
                    Spacer()
                    Image(systemName: "waveform")
                        .font(.title3)
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(Palette.accent.gradient)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            HStack(spacing: 10) {
                Button {
                    adhan.playAyahRecitation(globalAyahNumber: activePacket.globalAyahNumber, title: activePacket.verseSource)
                } label: {
                    Label("Arapça Tilavet", systemImage: "speaker.wave.3.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Palette.card)
                        .foregroundStyle(Palette.textPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.separator, lineWidth: 1))
                }

                Button {
                    let trText = "\(activePacket.verseSource). \(activePacket.turkishVerse). Vaktin Hadisi Şerifi: \(activePacket.hadithTurkish)"
                    adhan.speakTurkish(text: trText, title: "\(selectedPrayer.displayName) · Meal & Hadis")
                } label: {
                    Label("Türkçe Meal & Hadis", systemImage: "person.wave.2.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Palette.card)
                        .foregroundStyle(Palette.textPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.separator, lineWidth: 1))
                }
            }

            HStack(spacing: 10) {
                Button {
                    if adhan.isPlaying && adhan.mode == .adhanMekke {
                        adhan.stop()
                    } else {
                        adhan.play(resource: "ezan-full")
                    }
                } label: {
                    Label((adhan.isPlaying && adhan.mode == .adhanMekke) ? "Durdur" : "Mekke Ezanı",
                          systemImage: "moon.stars.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Palette.card)
                        .foregroundStyle(Palette.gold)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.gold.opacity(0.4), lineWidth: 1))
                }

                Button {
                    if adhan.isPlaying && adhan.mode == .adhanMedine {
                        adhan.stop()
                    } else {
                        adhan.play(resource: "ezan-medine")
                    }
                } label: {
                    Label((adhan.isPlaying && adhan.mode == .adhanMedine) ? "Durdur" : "Medine Ezanı",
                          systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Palette.card)
                        .foregroundStyle(Palette.gold)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.gold.opacity(0.4), lineWidth: 1))
                }
            }
        }
    }

    // MARK: - Vaktin Ayeti Kartı
    private var verseDetailCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("VAKTİN AYET-İ KERİMESİ", systemImage: "book.closed.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Palette.accent)
                Spacer()
                Button {
                    adhan.playAyahRecitation(globalAyahNumber: activePacket.globalAyahNumber, title: activePacket.verseSource)
                } label: {
                    Label("Tilavet", systemImage: "play.fill")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Palette.accent.opacity(0.15))
                        .foregroundStyle(Palette.accent)
                        .clipShape(Capsule())
                }
            }

            Text(activePacket.arabicVerse)
                .font(.custom("AmiriQuran-Regular", size: 36, relativeTo: .title))
                .fontWeight(.regular)
                .lineSpacing(12)
                .fixedSize(horizontal: false, vertical: true)
                .environment(\.layoutDirection, .rightToLeft)
                .foregroundStyle(Palette.textPrimary)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.vertical, 4)

            Text(activePacket.verseTransliteration)
                .font(.system(size: 17, weight: .regular))
                .lineSpacing(5)
                .foregroundStyle(Palette.textSecondary)

            Divider().background(Palette.separator)

            Text("“\(activePacket.turkishVerse)”")
                .font(.system(size: 23, weight: .regular))
                .lineSpacing(7)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(Palette.textPrimary)

            HStack {
                Text("— \(activePacket.verseSource)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.gold)
                Spacer()
                Button {
                    adhan.speakTurkish(text: "\(activePacket.verseSource). \(activePacket.turkishVerse)", title: activePacket.verseSource)
                } label: {
                    Label("Sesli Meal", systemImage: "speaker.wave.2.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.accent)
                }
            }
        }
        .padding(16)
        .sekineCard(active: true)
    }

    // MARK: - Vaktin Hadisi Kartı
    private var hadithDetailCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("VAKTİN HADİS-İ ŞERİFİ", systemImage: "quote.opening")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Palette.gold)
                Spacer()
                Button {
                    adhan.speakTurkish(
                        text: "Peygamber Efendimiz Sallallahu Aleyhi ve Sellem buyurdu ki: \(activePacket.hadithTurkish). Kaynak: \(activePacket.hadithSource)",
                        title: "Vaktin Hadis-i Şerifi"
                    )
                } label: {
                    Label("Sesli Dinle", systemImage: "speaker.wave.2.fill")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Palette.gold.opacity(0.18))
                        .foregroundStyle(Palette.gold)
                        .clipShape(Capsule())
                }
            }

            Text(activePacket.hadithArabic)
                .font(.custom("Amiri-Regular", size: 34, relativeTo: .title))
                .fontWeight(.regular)
                .lineSpacing(10)
                .fixedSize(horizontal: false, vertical: true)
                .environment(\.layoutDirection, .rightToLeft)
                .foregroundStyle(Palette.textPrimary)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)

            Text("“\(activePacket.hadithTurkish)”")
                .font(.system(size: 23, weight: .regular))
                .lineSpacing(7)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(Palette.textPrimary)

            Text("— \(activePacket.hadithSource)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.textSecondary)
        }
        .padding(16)
        .sekineCard()
    }

    // MARK: - Vaktin Duası Kartı
    private var duaDetailCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("VAKTİN DUASI & TEFEKKÜRÜ", systemImage: "hands.sparkles.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Palette.accent)
                Spacer()
                Button {
                    adhan.speakTurkish(text: activePacket.duaTurkish, title: "Vaktin Duası")
                } label: {
                    Label("Sesli Dua", systemImage: "speaker.wave.2.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.accent)
                }
            }
            Text("“\(activePacket.duaTurkish)”")
                .font(.system(size: 23, weight: .regular))
                .lineSpacing(7)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(Palette.textPrimary)
        }
        .padding(16)
        .sekineCard()
    }

    // MARK: - Canlı Bildirim & Alarm Test Aksiyonları
    private var testAndNotificationActionsCard: some View {
        VStack(spacing: 12) {
            Button {
                Task {
                    let ok = await adhan.scheduleInstantRichVideoNotification(for: selectedPrayer)
                    withAnimation {
                        notificationToast = ok
                            ? "3 saniye içinde Videolu & Sesli Ezan Bildirimi geliyor! (Ekranı kilitleyebilir veya bekleyebilirsiniz)"
                            : "Bildirim izni kapalı! Lütfen Ayarlar'dan bildirim iznini açın."
                    }
                    try? await Task.sleep(for: .seconds(5))
                    withAnimation { notificationToast = nil }
                }
            } label: {
                HStack {
                    Image(systemName: "bell.and.waves.left.and.right.fill")
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Videolu & Sesli Vakit Bildirimini Şimdi Test Et")
                            .font(.subheadline.weight(.bold))
                        Text("3 sn sonra iPhone'unuza MP4 videolu + ezan sesli ayet/hadis bildirimi gönderir")
                            .font(.caption2)
                            .opacity(0.85)
                    }
                    Spacer()
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(Color.orange.gradient)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            Button {
                showFullScreenAlarm = true
            } label: {
                HStack {
                    Image(systemName: "alarm.waves.left.and.right.fill")
                        .font(.title3)
                    Text("Tam Ekran Canlı Vakit & Ezan Alarmını Başlat")
                        .font(.subheadline.weight(.bold))
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(Palette.card)
                .foregroundStyle(Palette.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.accent, lineWidth: 1.5))
            }
        }
    }
}

/// Vakit Girdiğinde veya Bildirime Dokunulduğunda Açılan Tam Ekran Ezan + Video Ayet & Hadis Alarmı.
struct FullScreenAdhanAlarmView: View {
    let prayer: Prayer
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var adhan: AdhanPlayer
    @EnvironmentObject private var store: PrayerTimeStore

    private var packet: VakitSpiritualPacket {
        VakitSpiritualDatabase.packet(for: prayer)
    }

    var body: some View {
        ZStack {
            LoopingMP4VideoView(resourceName: packet.videoFileName, isMuted: true)
                .ignoresSafeArea()

            LinearGradient(
                colors: [.black.opacity(0.65), .black.opacity(0.35), .black.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                HStack {
                    Label("CANLI VAKİT & EZAN ALARMI", systemImage: "bell.badge.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.yellow)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.15))
                        .clipShape(Capsule())
                    Spacer()
                    Button {
                        adhan.stop()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                VStack(spacing: 6) {
                    Text(packet.badgeTitle)
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Text(packet.subtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.yellow)
                }

                LiveAudioWaveformView(isPlaying: adhan.isPlaying, color: .yellow)

                ScrollView {
                    VStack(spacing: 16) {
                        // Ayet kutusu
                        VStack(spacing: 10) {
                            Text("📖 VAKTİN AYET-İ KERİMESİ")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.yellow)
                            Text(packet.arabicVerse)
                                .font(.custom("AmiriQuran-Regular", size: 36, relativeTo: .title))
                .fontWeight(.regular)
                .lineSpacing(12)
                .fixedSize(horizontal: false, vertical: true)
                .environment(\.layoutDirection, .rightToLeft)
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                            Text("“\(packet.turkishVerse)”")
                                .font(.system(size: 23, weight: .regular))
                                .lineSpacing(7)
                                .fixedSize(horizontal: false, vertical: true)
                                .foregroundStyle(.white.opacity(0.95))
                                .multilineTextAlignment(.center)
                            Text("— \(packet.verseSource)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.yellow)
                        }
                        .padding(16)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                        // Hadis kutusu
                        VStack(spacing: 10) {
                            Text("✨ VAKTİN HADİS-İ ŞERİFİ")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.yellow)
                            Text("“\(packet.hadithTurkish)”")
                                .font(.system(size: 23, weight: .regular))
                                .lineSpacing(7)
                                .fixedSize(horizontal: false, vertical: true)
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                            Text("— \(packet.hadithSource)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.yellow)
                        }
                        .padding(16)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .padding(.horizontal, 20)
                }

                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        Button {
                            adhan.play(resource: "ezan-full")
                        } label: {
                            Label("Tam Ezan Oku", systemImage: "moon.stars.fill")
                                .font(.subheadline.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(Color.yellow)
                                .foregroundStyle(.black)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }

                        Button {
                            adhan.playFullVakitPacket(packet)
                        } label: {
                            Label("Sesli Ayet & Hadis", systemImage: "speaker.wave.3.fill")
                                .font(.subheadline.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(Color.green.gradient)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }

                    Button {
                        adhan.stop()
                        dismiss()
                    } label: {
                        Text("Alarmı Kapat & Ezan Duasını Oku")
                            .font(.headline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(.white.opacity(0.2))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
        .onAppear {
            adhan.playFullVakitPacket(packet)
        }
    }
}
