import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: PrayerTimeStore
    @EnvironmentObject private var adhan: AdhanPlayer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("home.displayStyle") private var displayStyle = 0
    @AppStorage("home.layout.v2") private var homeLayout = 0
    @AppStorage("home.shortcuts.v2") private var shortcutIDs = "quran,elifba,tesbih"
    @AppStorage("home.showLearning.v2") private var showLearning = true
    @AppStorage("home.showSpiritual.v2") private var showSpiritual = true
    @AppStorage("home.showDiscovery.v2") private var showDiscovery = true
    @State private var showCustomize = false
    @State private var showDetailedTimes = false
    @State private var learningProgress = EBProgress()
    @State private var showLocationSearch = false
    @State private var showSettings = false
    @State private var showProMenu = false
    @State private var selectedDayOffset = 0
    @State private var activeAlarmPrayer: Prayer?
    @State private var shareImage: UIImage?
    @State private var expandedVerse = false
    @State private var notificationStatus: String?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    header
                    if let schedule = store.schedule, store.today != nil {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            if homeLayout == 1 { hero(schedule: schedule, now: context.date) }
                            else { compactHero(schedule: schedule, now: context.date) }
                        }
                        if schedule.day(containing: Date())?.hicriMonth == 9 { RamadanCard(schedule: schedule) }
                        shortcuts
                        if adhan.isPlaying { audioBar }
                        todayOverview(schedule)
                        DisclosureGroup("Gün seçimi ve bildirimler", isExpanded: $showDetailedTimes) {
                            scheduleSection(schedule).padding(.top, 12)
                        }.font(.subheadline).tint(Palette.accent)
                        if showLearning { learningSection }
                        if showDiscovery { discoverySection }
                        DisclosureGroup("Ses ve hatırlatmalar") {
                            VStack(spacing: 14) {
                                Button { if adhan.isPlaying { adhan.stop() } else { adhan.play(resource: "ezan-full") } } label: {
                                    Label(adhan.isPlaying ? "Sesi durdur" : "Ezanı dinle", systemImage: "speaker.wave.2").frame(maxWidth: .infinity, minHeight: 44)
                                }
                                Button {
                                    Task {
                                        let prayer = schedule.currentTime(at: Date())?.prayer ?? .fajr
                                        let ok = await adhan.scheduleInstantRichVideoNotification(for: prayer)
                                        notificationStatus = ok ? "Deneme bildirimi zamanlandı." : "Bildirim iznini Ayarlar’dan açın."
                                    }
                                } label: { Label("Bildirim denemesi", systemImage: "bell.badge").frame(maxWidth: .infinity, minHeight: 44) }
                                if let notificationStatus { Text(notificationStatus).font(.caption) }
                            }.padding(.top, 12)
                        }.font(.subheadline.weight(.medium)).tint(Palette.accent).padding(18).sekineCard()
                        if showSpiritual { spiritualSection(schedule) }
                        HStack {
                            if let shareImage {
                                ShareLink(item: Image(uiImage: shareImage), message: Text("Bugünün namaz vakitleri · Secde Vakti"), preview: SharePreview("Namaz vakitleri", image: Image(uiImage: shareImage))) {
                                    Label("Vakitleri paylaş", systemImage: "square.and.arrow.up")
                                }
                            }
                            Spacer()
                            Button { showSettings = true } label: { Label("Ayarlar", systemImage: "slider.horizontal.3") }
                        }
                        .font(.footnote.weight(.semibold)).foregroundStyle(Palette.accent).padding(.horizontal, 4)
                    } else if store.isLoading {
                        ProgressView("Vakitler yükleniyor…").frame(maxWidth: .infinity, minHeight: 220)
                    } else {
                        ContentUnavailableView {
                            Label("Vakitleri keşfedin", systemImage: "sun.horizon")
                        } description: { Text("Şehrinizi seçerek günlük namaz vakitlerine ulaşın.") }
                        actions: { Button("Şehir seç") { showLocationSearch = true }.buttonStyle(.borderedProminent) }
                    }
                    if let error = store.errorMessage {
                        Label(error, systemImage: "info.circle").font(.caption).foregroundStyle(Palette.textSecondary)
                            .padding(16).frame(maxWidth: .infinity, alignment: .leading).sekineCard()
                    }
                    Text("SECDE VAKTİ").font(.system(size: 9, weight: .medium)).tracking(3).foregroundStyle(Palette.textSecondary.opacity(0.7))
                        .padding(.top, 6)
                }
                .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 100)
            }
            .background(Palette.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { if let location = settings.location { await store.refresh(location: location, settings: settings) } }
            .sheet(isPresented: $showLocationSearch) {
                LocationSearchSheet { place in
                    settings.location = place
                    settings.addSavedLocation(place)
                    Task { await store.refresh(location: place, settings: settings) }
                }
            }
            .sheet(isPresented: $showCustomize) {
                HomeCustomizationSheet(layout: $homeLayout, shortcutIDs: $shortcutIDs, showLearning: $showLearning, showSpiritual: $showSpiritual, showDiscovery: $showDiscovery)
            }
            .onAppear {
                learningProgress = UserDefaults.standard.data(forKey: "elifba.progress.v1").flatMap { try? JSONDecoder().decode(EBProgress.self, from: $0) } ?? EBProgress()
            }
            .sheet(isPresented: $showSettings) { SettingsView().presentationDragIndicator(.visible) }
            .sheet(isPresented: $showProMenu) { EzanVaktiProMenuSheet().presentationDragIndicator(.visible) }
            .fullScreenCover(item: $activeAlarmPrayer) { FullScreenAdhanAlarmView(prayer: $0) }
            .task(id: store.today?.dayStart) { renderShareImage() }
            .onChange(of: store.schedule?.fetchedAt) { _, _ in renderShareImage() }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text("HUZURLU BİR VAKİT").font(.system(size: 10, weight: .bold)).tracking(2.4).foregroundStyle(Palette.accent)
                Button { showLocationSearch = true } label: {
                    HStack(spacing: 7) {
                        Text(settings.location?.name ?? "Şehir seçin")
                            .font(.system(.title2, design: .serif).weight(.semibold)).lineLimit(1)
                        Image(systemName: "chevron.down").font(.caption.weight(.bold))
                    }.foregroundStyle(Palette.textPrimary)
                }
                .accessibilityHint("Namaz vakitlerinin gösterileceği şehri değiştirir")
            }
            Spacer(minLength: 10)
            Button { showCustomize = true } label: {
                Image(systemName: "square.grid.2x2").font(.title3).frame(width: 42, height: 44)
                    .foregroundStyle(Palette.accent)
            }.accessibilityLabel("Ana ekranı düzenle").accessibilityIdentifier("customizeHome")
            Button { showSettings = true } label: {
                Image(systemName: "slider.horizontal.3").font(.title3).frame(width: 46, height: 46)
                    .background(Palette.card, in: Circle()).foregroundStyle(Palette.accent)
            }.accessibilityLabel("Ayarlar ve bildirimler")
        }.buttonStyle(.plain)
    }

    private func hero(schedule: PrayerSchedule, now: Date) -> some View {
        let next = schedule.nextTime(after: now)
        let current = schedule.currentTime(at: now)
        let duration = max(1, (next?.date ?? now).timeIntervalSince(current?.date ?? now))
        let progress = min(1, max(0, now.timeIntervalSince(current?.date ?? now) / duration))
        return VStack(alignment: .leading, spacing: 22) {
            HStack {
                Label(schedule.sourceTitle, systemImage: schedule.source == "diyanet" ? "checkmark.seal" : "wifi.slash")
                    .font(.caption2.weight(.medium)).foregroundStyle(.white.opacity(0.8))
                Spacer()
                Menu {
                    Picker("Vakit görünümü", selection: $displayStyle) {
                        Text("Klasik").tag(0)
                        Text("Dairesel").tag(1)
                        Text("Sade").tag(2)
                    }
                } label: {
                    Image(systemName: "square.grid.2x2").font(.subheadline).frame(width: 36, height: 36)
                        .background(.white.opacity(0.12), in: Circle())
                }.accessibilityLabel("Vakit kartı görünümünü seç")
            }
            if let next {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SIRADAKİ VAKİT").font(.system(size: 9, weight: .bold)).tracking(2.4).foregroundStyle(EzanDesign.gold)
                        Text(next.prayer.displayName).font(.system(size: displayStyle == 2 ? 32 : 40, weight: .medium, design: .serif))
                        Text("Saat \(format(next.date, pattern: "HH:mm"))")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.7))
                    }
                    Spacer(minLength: 0)
                    if displayStyle == 1 {
                        ZStack {
                            Circle().stroke(.white.opacity(0.12), lineWidth: 5)
                            Circle().trim(from: 0, to: progress).stroke(EzanDesign.gold, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
                            Image(systemName: next.prayer.systemImage).font(.system(size: 32, weight: .light)).foregroundStyle(EzanDesign.gold)
                        }.frame(width: 84, height: 84).accessibilityHidden(true)
                    } else if displayStyle == 0 {
                        Image(systemName: next.prayer.systemImage).font(.system(size: 58, weight: .ultraLight))
                            .foregroundStyle(EzanDesign.gold).padding(.trailing, 4).accessibilityHidden(true)
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text(Self.countdown(now, next.date))
                        .font(.system(size: displayStyle == 2 ? 38 : 48, weight: .light, design: .rounded).monospacedDigit())
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .accessibilityLabel("\(next.prayer.displayName) vaktine \(CountdownFormatter.string(from: now, to: next.date)) kaldı")
                    if displayStyle != 2 {
                        GeometryReader { geometry in
                            Capsule().fill(.white.opacity(0.15))
                                .overlay(alignment: .leading) { Capsule().fill(EzanDesign.gold).frame(width: geometry.size.width * progress) }
                        }.frame(height: 3).accessibilityHidden(true)
                    }
                }
            }
            HStack(alignment: .top) {
                Text(format(now, pattern: "d MMMM · EEEE"))
                Spacer()
                if let hijri = schedule.day(containing: now)?.hicriDate { Text(hijri).multilineTextAlignment(.trailing) }
            }.font(.system(size: 14)).foregroundStyle(.white.opacity(0.85))
        }
        .foregroundStyle(.white).padding(24)
        .background { EzanDesign.heroGradient.overlay { EzanPattern() } }
        .clipShape(RoundedRectangle(cornerRadius: 30))
        .shadow(color: EzanDesign.forest.opacity(0.16), radius: 18, x: 0, y: 8)
    }

    private var shortcuts: some View {
        HStack(spacing: 10) {
            ForEach(HomeQuickAction.selected(shortcutIDs)) { action in
                NavigationLink { action.destination } label: { shortcut(action.title, action.icon) }
                    .accessibilityIdentifier("homeShortcut-" + action.rawValue)
            }
            Button { showProMenu = true } label: { shortcut("Tümü", "square.grid.2x2") }
        }.buttonStyle(.plain)
    }

    private func compactHero(schedule: PrayerSchedule, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(schedule.sourceTitle, systemImage: schedule.source == "diyanet" ? "checkmark.seal" : "wifi.slash").font(.caption)
                Spacer()
                Text(format(now, pattern: "d MMMM")).font(.caption)
            }.foregroundStyle(.white.opacity(0.85))
            if let next = schedule.nextTime(after: now) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SIRADAKİ VAKİT").font(.caption2).tracking(2).foregroundStyle(EzanDesign.gold)
                        Text(next.prayer.displayName).font(.system(.largeTitle, design: .serif).weight(.regular))
                        Text(format(next.date, pattern: "HH:mm")).font(.title3.monospacedDigit())
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 8) {
                        Image(systemName: next.prayer.systemImage).font(.system(size: 30, weight: .light)).foregroundStyle(EzanDesign.gold)
                        Text(Self.countdown(now, next.date)).font(.system(size: 28, weight: .light, design: .rounded).monospacedDigit())
                            .lineLimit(1).minimumScaleFactor(0.65)
                            .accessibilityLabel(next.prayer.displayName + " vaktine " + CountdownFormatter.string(from: now, to: next.date) + " kaldı")
                        Text("vaktine kaldı").font(.caption).foregroundStyle(.white.opacity(0.8))
                    }
                }
            }
            if let hijri = schedule.day(containing: now)?.hicriDate {
                Text(hijri).font(.caption).foregroundStyle(.white.opacity(0.85))
            }
        }.foregroundStyle(.white).padding(22)
            .background { EzanDesign.heroGradient.overlay { EzanPattern() } }
            .clipShape(RoundedRectangle(cornerRadius: 26))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("compactPrayerHero")
    }

    private func todayOverview(_ schedule: PrayerSchedule) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Bugünün vakitleri").font(.system(.title3, design: .serif))
                Spacer()
                Button { showDetailedTimes.toggle() } label: { Image(systemName: "calendar") }
                    .accessibilityLabel("Gün seçimi ve bildirimleri göster")
            }.foregroundStyle(Palette.textPrimary)
            TimelineView(.periodic(from: .now, by: 30)) { context in
                if let day = schedule.day(containing: context.date) {
                    if homeLayout == 2 {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                            ForEach(day.times) { time in miniPrayer(time, next: schedule.nextTime(after: context.date)?.date == time.date) }
                        }
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(day.times) { time in
                                    miniPrayer(time, next: schedule.nextTime(after: context.date)?.date == time.date).frame(minWidth: 80)
                                }
                            }
                        }
                    }
                }
            }
        }.accessibilityIdentifier("homeTodayOverview")
    }
    private func miniPrayer(_ time: PrayerTime, next: Bool) -> some View {
        VStack(spacing: 7) {
            Image(systemName: time.prayer.systemImage).font(.body).foregroundStyle(Palette.accent)
            Text(time.prayer.displayName).font(.caption)
            Text(format(time.date, pattern: "HH:mm")).font(.body.monospacedDigit())
            if next { Text("Sıradaki").font(.system(size: 9)).foregroundStyle(Palette.accent) }
        }.foregroundStyle(Palette.textPrimary).frame(maxWidth: .infinity, minHeight: 82).padding(10)
            .background(next ? Palette.cardActive : Palette.card, in: RoundedRectangle(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).stroke(next ? Palette.accent.opacity(0.5) : Color.clear, lineWidth: 1) }
            .accessibilityElement(children: .combine)
    }
    private var learningSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Öğrenmeye devam et").font(.system(.title3, design: .serif))
            NavigationLink { ElifBaView() } label: {
                HStack(spacing: 16) {
                    Text("ب").font(.custom("AmiriQuran", size: 50)).frame(width: 66, height: 72)
                        .background(Palette.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Kur’an Öğreniyorum").font(.headline)
                        Text("Elif Bâ · \(learningProgress.completedLessons.count)/12 ders tamamlandı").font(.caption).foregroundStyle(Palette.textSecondary)
                        ProgressView(value: Double(learningProgress.completedLessons.count), total: 12).tint(Palette.accent)
                        Text(learningProgress.completedLessons.count == 12 ? "Alıştırmalarla pekiştir" : "Harfler, harekeler ve okuma çalışmaları").font(.caption).foregroundStyle(Palette.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                }.foregroundStyle(Palette.textPrimary).padding(16).sekineCard()
            }.buttonStyle(.plain).accessibilityIdentifier("homeLearningCard")
            NavigationLink { KuranBilmekView() } label: {
                HStack {
                    Image(systemName: "book.pages").font(.title2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Kur’an ile bir mola").font(.headline)
                        Text("Ayet ara · meali oku · tilaveti takip et").font(.caption).foregroundStyle(Palette.textSecondary)
                    }
                    Spacer(); Image(systemName: "chevron.right")
                }.foregroundStyle(Palette.accent).padding(18).sekineCard()
            }.buttonStyle(.plain)
        }
    }
    private var discoverySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Gününe eşlik etsin").font(.system(.title3, design: .serif))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                NavigationLink { DuaView() } label: { discoveryCard("Dua defteri", "Günlük dualar", "hands.sparkles", .orange) }
                NavigationLink { TesbihView() } label: { discoveryCard("Zikir molası", "Sayacını aç", "circle.dotted", .teal) }
                NavigationLink { EsmaulHusnaView() } label: { discoveryCard("Esmâü’l Hüsnâ", "İsimleri keşfet", "sparkles", .purple) }
                NavigationLink { NearbyMosquesView() } label: { discoveryCard("Yakındaki camiler", "Haritada incele", "building.columns", .blue) }
            }.buttonStyle(.plain)
        }
    }
    private func discoveryCard(_ title: String, _ subtitle: String, _ icon: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: icon).font(.title2).foregroundStyle(color)
            Text(title).font(.headline).foregroundStyle(Palette.textPrimary)
            Text(subtitle).font(.caption).foregroundStyle(Palette.textSecondary)
        }.frame(maxWidth: .infinity, minHeight: 102, alignment: .leading).padding(16)
            .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 22))
    }

    private func shortcut(_ title: String, _ icon: String) -> some View {
        VStack(spacing: 9) {
            Image(systemName: icon).font(.system(size: 21, weight: .regular)).foregroundStyle(Palette.accent)
                .frame(width: 50, height: 50).background(Palette.card, in: RoundedRectangle(cornerRadius: 18))
            Text(title).font(.subheadline.weight(.medium)).foregroundStyle(Palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.75)
        }.frame(maxWidth: .infinity).frame(minHeight: 74)
    }

    private func scheduleSection(_ schedule: PrayerSchedule) -> some View {
        let date = Calendar.current.date(byAdding: .day, value: selectedDayOffset, to: Date()) ?? Date()
        let day = schedule.day(containing: date)
        return VStack(spacing: 15) {
            HStack {
                EzanSectionTitle(title: "Günün vakitleri")
                Button { selectedDayOffset = 0 } label: {
                    Text(selectedDayOffset == 0 ? "Bugün" : "Bugüne dön").font(.caption.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 7).background(Palette.cardActive, in: Capsule())
                }.foregroundStyle(Palette.accent)
            }
            HStack {
                Button { selectedDayOffset -= 1 } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.disabled(selectedDayOffset <= -1)
                Spacer()
                Text(format(date, pattern: "d MMMM yyyy, EEEE")).font(.caption.weight(.medium)).multilineTextAlignment(.center)
                Spacer()
                Button { selectedDayOffset += 1 } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.disabled(selectedDayOffset >= 6)
            }.foregroundStyle(Palette.textSecondary).background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
                .accessibilityElement(children: .contain)
            if let day {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    VStack(spacing: 0) {
                        ForEach(Prayer.ordered) { prayer in
                            if let time = day.time(for: prayer) {
                                prayerRow(prayer, time: time, next: schedule.nextTime(after: context.date)?.date == time)
                                if prayer != .isha { Divider().overlay(Palette.separator.opacity(0.5)).padding(.leading, 60) }
                            }
                        }
                    }.sekineCard()
                }
            } else {
                Text("Bu tarih için kayıtlı vakit bulunmuyor. Vakitleri yenilemek için ekranı aşağı çekin.")
                    .font(.subheadline).foregroundStyle(Palette.textSecondary).padding(20).sekineCard()
            }
            HStack(spacing: 5) {
                Image(systemName: "location.circle")
                Text("\(schedule.placeName) yerel saati · \(schedule.sourceTitle)")
            }.font(.system(size: 10)).foregroundStyle(Palette.textSecondary).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func prayerRow(_ prayer: Prayer, time: Date, next: Bool) -> some View {
        let enabled = settings.isNotificationEnabled(for: prayer)
        return HStack(spacing: 13) {
            Image(systemName: prayer.systemImage).font(.system(size: 18, weight: .light))
                .foregroundStyle(next ? Palette.accent : Palette.textSecondary).frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(prayer.displayName).font(.body.weight(next ? .semibold : .regular))
                if next { Text("Sıradaki vakit").font(.system(size: 10)).foregroundStyle(Palette.accent) }
            }
            Spacer()
            Text(format(time, pattern: "HH:mm")).font(.system(.title3, design: .rounded).weight(next ? .bold : .medium).monospacedDigit())
            if prayer.isNotifiable {
                Button {
                    settings.setNotification(!enabled, for: prayer)
                    Task { await store.rescheduleNotifications(settings: settings) }
                } label: {
                    Image(systemName: enabled ? "bell.fill" : "bell.slash").font(.system(size: 14))
                        .foregroundStyle(enabled ? Palette.accent : Palette.textSecondary.opacity(0.6)).frame(width: 44, height: 44)
                }.accessibilityLabel("\(prayer.displayName) bildirimi").accessibilityValue(enabled ? "Açık" : "Kapalı")
            } else { Color.clear.frame(width: 44, height: 44).accessibilityHidden(true) }
        }
        .foregroundStyle(Palette.textPrimary).padding(.leading, 18).padding(.trailing, 6).padding(.vertical, 7)
        .background(next ? Palette.cardActive : Color.clear)
    }

    private func spiritualSection(_ schedule: PrayerSchedule) -> some View {
        let prayer = schedule.currentTime(at: Date())?.prayer ?? .fajr
        let packet = VakitSpiritualDatabase.packet(for: prayer)
        return VStack(alignment: .leading, spacing: 15) {
            EzanSectionTitle(title: "Kalbe iyi gelen", detail: prayer.displayName + " vakti")
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Label("VAKTİN AYETİ", systemImage: "sparkle").font(.system(size: 10, weight: .bold)).tracking(1.5).foregroundStyle(Palette.accent)
                    Spacer()
                    Button { activeAlarmPrayer = prayer } label: { Image(systemName: "play.circle").font(.title2) }.accessibilityLabel("Ayet videosunu aç")
                }
                Text(packet.arabicVerse).font(.custom("AmiriQuran-Regular", size: 28)).lineSpacing(12)
                    .foregroundStyle(Palette.textPrimary).frame(maxWidth: .infinity, alignment: .trailing)
                Text(packet.turkishVerse).font(.system(.body, design: .serif)).lineSpacing(6)
                    .foregroundStyle(Palette.textPrimary).lineLimit(expandedVerse ? nil : 3)
                HStack {
                    Text(packet.verseSource).font(.caption).foregroundStyle(Palette.textSecondary)
                    Spacer()
                    Button(expandedVerse ? "Daralt" : "Devamını oku") { expandedVerse.toggle() }.font(.caption.weight(.semibold))
                }
                Divider()
                HStack {
                    Button { adhan.speakTurkish(text: packet.turkishVerse, title: "Vaktin ayeti") } label: { Label("Meali dinle", systemImage: "speaker.wave.2") }
                    Spacer()
                    ShareLink(item: "\(packet.turkishVerse) — \(packet.verseSource)") { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("Ayeti paylaş")
                }.font(.subheadline.weight(.medium)).frame(minHeight: 30)
            }.foregroundStyle(Palette.accent).padding(22).sekineCard()
            VStack(alignment: .leading, spacing: 10) {
                Label("HADİS-İ ŞERİF", systemImage: "quote.opening").font(.system(size: 10, weight: .bold)).tracking(1.5).foregroundStyle(Palette.gold)
                Text(packet.hadithTurkish).font(.system(.subheadline, design: .serif)).lineSpacing(5).foregroundStyle(Palette.textPrimary)
                Text(packet.hadithSource).font(.caption2).foregroundStyle(Palette.textSecondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(22).sekineCard()
        }
    }

    private var audioBar: some View {
        HStack {
            Image(systemName: "waveform").foregroundStyle(Palette.accent)
            Text("Sesli içerik oynatılıyor").font(.subheadline)
            Spacer()
            Button { adhan.stop() } label: { Image(systemName: "stop.circle.fill").font(.title2) }.accessibilityLabel("Sesi durdur")
        }.padding(16).foregroundStyle(Palette.accent).sekineCard(active: true)
    }

    private func format(_ date: Date, pattern: String) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "tr_TR")
        f.timeZone = store.schedule?.timeZone ?? .current; f.dateFormat = pattern
        return f.string(from: date)
    }
    private static func countdown(_ now: Date, _ target: Date) -> String {
        let seconds = max(0, Int(target.timeIntervalSince(now)))
        return String(format: "%02d : %02d : %02d", seconds / 3600, seconds % 3600 / 60, seconds % 60)
    }
    private func renderShareImage() {
        guard let schedule = store.schedule, let day = store.today else { shareImage = nil; return }
        shareImage = ShareCardRenderer.image(placeName: schedule.placeName, day: day, timeZone: schedule.timeZone, sourceTitle: schedule.sourceTitle)
    }
}

/// Geri sayım metni: "2 sa 14 dk 30 sn" — yaşlı kullanıcı için açık.
enum CountdownFormatter {
    static func string(from now: Date, to target: Date) -> String {
        let total = max(0, Int(target.timeIntervalSince(now)))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d sa %02d dk", h, m) }
        if m > 0 { return String(format: "%d dk %02d sn", m, s) }
        return String(format: "%d sn", s)
    }
}

// MARK: - Secde Vakti 12'li Hızlı Menü (s10.png Birebir)
struct EzanVaktiProMenuSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    menuLink(title: "Kur'an-ı Kerim", icon: "book.fill", color: .cyan) {
                        QuranAndLibraryView()
                    }
                    menuLink(title: "Video Ayet & Hadis", icon: "play.tv.fill", color: .orange) {
                        VideoSpiritualFeedView()
                    }
                    menuLink(title: "3D Zikirmatik", icon: "circle.grid.cross.fill", color: .teal) {
                        TesbihView()
                    }
                    menuLink(title: "Yakındaki Camiler", icon: "building.columns.fill", color: .blue) {
                        NearbyMosquesView()
                    }
                    menuLink(title: "Kıble Pusulası", icon: "location.north.line.fill", color: .green) {
                        QiblaView()
                    }
                    menuLink(title: "Esmaü'l Hüsna", icon: "sparkles", color: .purple) {
                        EsmaulHusnaView()
                    }
                    menuLink(title: "Hısnü'l Müslim", icon: "hands.sparkles.fill", color: .indigo) {
                        DuaView()
                    }
                    menuLink(title: "Kaza Takibi", icon: "checkmark.seal.fill", color: .mint) {
                        KazaView()
                    }
                    menuLink(title: "Aylık İmsakiye", icon: "calendar", color: .brown) {
                        MonthlyView()
                    }
                }
                .padding(16)
            }
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle("Tüm Özellikler Menüsü")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
            }
        }
    }

    private func menuLink<Dest: View>(title: String, icon: String, color: Color, @ViewBuilder destination: @escaping () -> Dest) -> some View {
        NavigationLink(destination: destination) {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(color.opacity(0.14))
                        .frame(width: 72, height: 72)
                    Image(systemName: icon)
                        .font(.system(size: 28))
                        .foregroundStyle(color)
                }
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Palette.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(Palette.card)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}


enum HomeQuickAction: String, CaseIterable, Identifiable {
    case quran, elifba, tesbih, calendar, dua, qibla
    var id: String { rawValue }
    var title: String { switch self { case .quran: return "Kur’an"; case .elifba: return "Elif Bâ"; case .tesbih: return "Zikirmatik"; case .calendar: return "Takvim"; case .dua: return "Dualar"; case .qibla: return "Kıble" } }
    var icon: String { switch self { case .quran: return "book.closed"; case .elifba: return "textformat.abc"; case .tesbih: return "circle.dotted"; case .calendar: return "calendar"; case .dua: return "hands.sparkles"; case .qibla: return "location.north" } }
    static func selected(_ raw: String) -> [Self] {
        var result: [Self] = []
        for key in raw.split(separator: ",") {
            if let action = Self(rawValue: String(key)), !result.contains(action) { result.append(action) }
        }
        for fallback in [Self.quran, .elifba, .tesbih] where !result.contains(fallback) { result.append(fallback) }
        return Array(result.prefix(3))
    }
    @ViewBuilder var destination: some View {
        switch self {
        case .quran: QuranAndLibraryView()
        case .elifba: ElifBaView()
        case .tesbih: TesbihView()
        case .calendar: MonthlyView()
        case .dua: DuaView()
        case .qibla: QiblaView()
        }
    }
}
struct HomeCustomizationSheet: View {
    @Binding var layout: Int
    @Binding var shortcutIDs: String
    @Binding var showLearning: Bool
    @Binding var showSpiritual: Bool
    @Binding var showDiscovery: Bool
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Ana ekran düzeni") {
                    ForEach(0..<3) { index in
                        Button { layout = index } label: {
                            HStack(spacing: 14) {
                                Image(systemName: ["rectangle.topthird.inset.filled", "timer", "square.grid.2x2"][index]).font(.title2).frame(width: 34)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(["Dengeli", "Odak", "Kartlar"][index]).font(.headline)
                                    Text(["Kısa vakit kartı ve yatay günlük akış", "Büyük geri sayım ve vakit simgesi", "Günün altı vakti ayrı kutularda"][index]).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if layout == index { Image(systemName: "checkmark.circle.fill") }
                            }.foregroundStyle(Palette.accent).padding(.vertical, 8)
                        }.accessibilityIdentifier("homeLayout-\(index)")
                            .accessibilityValue(layout == index ? "Seçili" : "")
                    }
                }
                Section("Hızlı erişim · üç kısayol") {
                    ForEach(0..<3) { slot in
                        Picker("\(slot + 1). kısayol", selection: Binding(get: { HomeQuickAction.selected(shortcutIDs)[slot] }, set: { chosen in
                            var actions = HomeQuickAction.selected(shortcutIDs)
                            if let other = actions.firstIndex(of: chosen) { actions.swapAt(slot, other) }
                            else { actions[slot] = chosen }
                            shortcutIDs = actions.map(\.rawValue).joined(separator: ",")
                        })) {
                            ForEach(HomeQuickAction.allCases) { action in Text(action.title).tag(action) }
                        }.accessibilityIdentifier("homeShortcutPicker-\(slot)")
                    }
                }
                Section("Gösterilecek bölümler") {
                    Toggle("Öğrenmeye devam et", isOn: $showLearning)
                    Toggle("Gününe eşlik etsin", isOn: $showDiscovery)
                    Toggle("Ayet ve hadis", isOn: $showSpiritual)
                }
                Section {
                    Button("Varsayılan düzene dön") {
                        layout = 0; shortcutIDs = "quran,elifba,tesbih"
                        showLearning = true; showSpiritual = true; showDiscovery = true
                    }
                } footer: { Text("Seçimlerin bu cihazda saklanır. Vakitler ve bildirim ayarları değişmez.") }
            }.navigationTitle("Ana ekranı düzenle").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Bitti") { dismiss() } } }
        }
    }
}
