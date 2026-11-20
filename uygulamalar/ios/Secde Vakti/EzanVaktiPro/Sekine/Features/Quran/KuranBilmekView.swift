import SwiftUI

enum KBActiveModal: Identifiable {
    case generalMenu
    case surahList
    case displaySettings
    case search
    case pageJuzPicker
    case topics
    case bookmarks
    case favorites
    case notesList
    case okuBottom
    case surahInfo
    case duaSubmenu
    case singleVerse(KBVerse)
    case wordList(KBVerse)
    case concordance(KBWord)
    case noteEditor(KBVerse)
    case tefeul(KBVerse)

    var id: String {
        switch self {
        case .generalMenu: return "generalMenu"
        case .surahList: return "surahList"
        case .displaySettings: return "displaySettings"
        case .search: return "search"
        case .pageJuzPicker: return "pageJuzPicker"
        case .topics: return "topics"
        case .bookmarks: return "bookmarks"
        case .favorites: return "favorites"
        case .notesList: return "notesList"
        case .okuBottom: return "okuBottom"
        case .surahInfo: return "surahInfo"
        case .duaSubmenu: return "duaSubmenu"
        case .singleVerse(let v): return "singleVerse_\(v.id)"
        case .wordList(let v): return "wordList_\(v.id)"
        case .concordance(let w): return "concordance_\(w.id)"
        case .noteEditor(let v): return "noteEditor_\(v.id)"
        case .tefeul(let v): return "tefeul_\(v.id)"
        }
    }
}

struct KuranBilmekView: View {
    @EnvironmentObject private var appearance: AppSettings
    @ObservedObject private var store = KuranBilmekStore.shared
    @ObservedObject private var sync = QFSyncPlayer.shared
    @ObservedObject private var player = AdhanPlayer.shared
    @ObservedObject private var ikra = IkraAudioAndRadioCenter.shared

    @State private var selectedWordContext: (word: KBWord, verse: KBVerse)? = nil
    @State private var activeModal: KBActiveModal? = nil

    @State private var scrollTargetAyah: Int? = nil
    @State private var showReadingTools = false
    @State private var isFullscreenMushaf: Bool = false
    @State private var copiedWordToast: String? = nil
    @GestureState private var pinchScale: CGFloat = 1

    // Signature Kuran Bilmek Colors
    private let mintHeaderColor = Color(red: 0.20, green: 0.53, blue: 0.43) // #2EC78F
    private var creamPageBg: Color { Palette.background }
    private var surahBannerBg: Color { Palette.cardActive }
    private let yellowPopupBg = Color(red: 1.00, green: 0.96, blue: 0.52)   // #FFF585

    var body: some View {
        GeometryReader { geometry in
            readerContent(width: geometry.size.width)
        }
    }

    private func readerContent(width: CGFloat) -> some View {
        ZStack {
            creamPageBg.ignoresSafeArea()

            VStack(spacing: 0) {
                if !isFullscreenMushaf {
                    topMintHeaderBar
                    subPageJuzBar
                    if showReadingTools { ikraQuickStudioStrip }
                }

                QFSyncControls(verses: store.verses)

                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: true) {
                        LazyVStack(spacing: 12) {
                            surahCalligraphicBanner

                            if store.showColorTajweed && store.showTajweedLegend {
                                tajweedColorLegendBar
                            }

                            if let dlBanner = ikra.lastDownloadStatusBanner {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.down.circle.fill")
                                        .foregroundColor(.teal)
                                    Text(dlBanner)
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(.black.opacity(0.8))
                                    Spacer()
                                    Button {
                                        ikra.lastDownloadStatusBanner = nil
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.gray)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.9)))
                            }

                            if store.isLoading {
                                VStack(spacing: 12) {
                                    ProgressView()
                                        .tint(mintHeaderColor)
                                    Text("Arapça metin ve Diyanet meali yükleniyor…")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 36)
                            } else {
                                ForEach(store.verses) { verse in
                                    verseBlockView(verse)
                                        .id(verse.verse_key)
                                }
                            }
                        }
                        .frame(width: max(0, width - 20))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                    }
                    .accessibilityIdentifier("quranReaderScroll")
                    .highPriorityGesture(MagnificationGesture()
                        .updating($pinchScale) { value, state, _ in state = value }
                        .onEnded { value in
                            store.fontSizeScale = min(1.8, max(0.8, store.fontSizeScale * value))
                        })
                    .overlay(alignment: .top) {
                        if abs(pinchScale - 1) > 0.02 {
                            Text("Yazı boyutu %\(Int(min(1.8, max(0.8, store.fontSizeScale * pinchScale)) * 100))")
                                .font(.subheadline.bold()).padding(12)
                                .background(.regularMaterial, in: Capsule())
                                .allowsHitTesting(false)
                        }
                    }
                    .onChange(of: sync.focusedWordID) { _, target in
                        if sync.autoScroll, let target {
                            withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(target, anchor: .center) }
                        }
                    }
                    .onChange(of: sync.verseKey) { _, key in
                        if sync.autoScroll, let key { withAnimation { proxy.scrollTo(key, anchor: .top) } }
                    }
                    .onChange(of: scrollTargetAyah) { _, target in
                        if let target {
                            withAnimation(.easeInOut(duration: 0.35)) {
                                proxy.scrollTo(store.verses.first(where: { $0.verse_number == target })?.verse_key, anchor: .top)
                            }
                        }
                    }
                }

                if player.isPlaying {
                    activeIkraNowPlayingBar
                }

                bottomOkuControlBar
            }

            // Signature Yellow Word Popup (Screenshot 4)
            if let ctx = selectedWordContext {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            selectedWordContext = nil
                        }
                    }

                yellowWordDetailPopup(word: ctx.word, verse: ctx.verse)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                    .zIndex(20)
            }

            if let toast = copiedWordToast {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(.caption.weight(.bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.black.opacity(0.82)))
                        .padding(.bottom, 76)
                }
                .transition(.opacity)
                .zIndex(30)
            }
        }
        .frame(width: width)
        .sheet(item: $activeModal) { modal in
            modalContentView(for: modal)
        }
        .onDisappear { sync.stop() }
        .onChange(of: store.verses.map(\.verse_key)) { _, _ in sync.stop() }
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("--evp-oku-modal") {
                activeModal = .okuBottom
            } else if ProcessInfo.processInfo.arguments.contains("--evp-settings-modal") {
                activeModal = .displaySettings
            } else if ProcessInfo.processInfo.arguments.contains("--evp-word-popup"),
               let firstVerse = store.verses.first,
               let firstWord = firstVerse.actualWords.first {
                selectedWordContext = (firstWord, firstVerse)
            }
        }
        .onChange(of: store.verses.first?.id) { _, _ in
            if ProcessInfo.processInfo.arguments.contains("--evp-word-popup"),
               selectedWordContext == nil,
               let firstVerse = store.verses.first,
               let firstWord = firstVerse.actualWords.first {
                selectedWordContext = (firstWord, firstVerse)
            }
        }
    }

    @ViewBuilder
    private func modalContentView(for modal: KBActiveModal) -> some View {
        switch modal {
        case .generalMenu:
            KBGeneralMenuDrawer { action in
                activeModal = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    handleDrawerAction(action)
                }
            }
        case .surahList:
            KBSurahNavigatorSheet(store: store) { surahId, ayahNum in
                Task {
                    await store.selectSurah(surahId)
                    scrollTargetAyah = ayahNum
                }
            }
        case .displaySettings:
            KBDisplaySettingsSheet(store: store)
        case .search:
            KBSearchSheet(store: store) { surahId, ayahNum in
                Task {
                    await store.selectSurah(surahId)
                    scrollTargetAyah = ayahNum
                }
            }
        case .pageJuzPicker:
            KBPageJuzPickerSheet(store: store)
        case .topics:
            KBTopicsSheet(store: store) { q in
                activeModal = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    Task { await store.performSearch(query: q) }
                    activeModal = .search
                }
            }
        case .bookmarks:
            KBSavedListSheet(title: "Kaydedilen Yer İşaretleri", items: store.bookmarks) { item in
                activeModal = nil
                Task {
                    await store.selectSurah(item.surahId)
                    scrollTargetAyah = item.ayahNumber
                }
            }
        case .favorites:
            KBSavedListSheet(title: "Seçilen Sûre ve Ayetler", items: store.favoriteVerses) { item in
                activeModal = nil
                Task {
                    await store.selectSurah(item.surahId)
                    scrollTargetAyah = item.ayahNumber
                }
            }
        case .notesList:
            KBNotesListSheet(store: store) { note in
                activeModal = nil
                Task {
                    await store.selectSurah(note.surahId)
                    scrollTargetAyah = note.ayahNumber
                }
            }
        case .okuBottom:
            KBOkuAudioSheet(store: store) { sid, anum in
                Task {
                    await store.selectSurah(sid)
                    scrollTargetAyah = anum
                }
            }
        case .surahInfo:
            KBSurahInfoSheet(chapter: store.currentChapter)
        case .duaSubmenu:
            KBDuaSpecialSheet()
        case .singleVerse(let verse):
            KBSingleVerseDetailModal(store: store, initialVerse: verse) { v in
                activeModal = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    activeModal = .noteEditor(v)
                }
            }
        case .wordList(let verse):
            KBVerseWordsTableSheet(store: store, verse: verse)
        case .concordance(let word):
            KBWordConcordanceSheet(store: store, word: word) { sid, anum in
                activeModal = nil
                Task {
                    await store.selectSurah(sid)
                    scrollTargetAyah = anum
                }
            }
        case .noteEditor(let verse):
            KBNoteEditorSheet(store: store, verse: verse)
        case .tefeul(let verse):
            KBTefeulSheet(store: store, verse: verse)
        }
    }

    // MARK: - Top Mint Header Bar (Screenshots 1, 2, 5, 10)

    private var topMintHeaderBar: some View {
        HStack(spacing: 10) {
            Button { activeModal = .generalMenu } label: {
                Image(systemName: "line.3.horizontal").frame(width: 44, height: 44)
            }.accessibilityLabel("Okuma menüsü")
            Spacer()
            Button { activeModal = .surahList } label: {
                VStack(spacing: 4) {
                    Text(store.currentChapter?.turkishName ?? "Kur’an-ı Kerim").font(.system(.headline, design: .serif))
                    Text("KELİME · DİYANET MEALİ").font(.system(size: 8, weight: .medium)).tracking(1.6)
                }
            }.accessibilityLabel("Sûre seç")
            Spacer()
            Button { activeModal = .search } label: {
                Image(systemName: "magnifyingglass").frame(width: 44, height: 44)
            }.accessibilityLabel("Kur’an’da ara")
        }.foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 6).background(EzanDesign.forest)
    }

    // MARK: - Sub Header (Sayfa / Cüz / Sûre Badge)

    private var subPageJuzBar: some View {
        let firstVerse = store.verses.first
        let pageNum = firstVerse?.page_number ?? store.currentChapter?.startPage ?? 1
        let juzNum = firstVerse?.juz_number ?? 1
        let chName = store.currentChapter?.turkishName ?? "Fâtiha"

        return HStack {
            Button {
                activeModal = .pageJuzPicker
            } label: {
                Text("Sayfa: \(pageNum)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Palette.textSecondary)
            }

            Spacer()

            Button {
                activeModal = .pageJuzPicker
            } label: {
                Text("Cüz: \(juzNum)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Palette.onAccent)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Palette.accent))
            }

            Spacer()

            Button {
                activeModal = .surahList
            } label: {
                HStack(spacing: 3) {
                    Text("\(chName)/\(store.currentSurahId)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Palette.textPrimary)
                    Circle()
                        .fill(Color.red)
                        .frame(width: 6, height: 6)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(creamPageBg)
        .overlay(Divider(), alignment: .bottom)
    }

    // MARK: - İkra Ses, Hat, Tecvid, Sanatçı & Canlı Radyo Hızlı Kontrol Şeridi

    private var ikraQuickStudioStrip: some View {
        let sName = store.currentChapter?.turkishName ?? "Fâtiha"
        let isOffline = ikra.isSurahAvailableOffline(surahId: store.currentSurahId)

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // 1. İkra Sûreyi Sesli Dinle (Sanatçı + Hafız)
                Button {
                    ikra.playSurah(surahId: store.currentSurahId, surahName: sName)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "waveform.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.yellow)
                        Text("İkra Dinle: \(ikra.currentTurkishArtist.name.components(separatedBy: " ").prefix(2).joined(separator: " "))")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color(red: 0.10, green: 0.48, blue: 0.36)))
                }

                // 2. Arapça Mushaf Hattı Seçici Menüsü
                Menu {
                    Section("Arapça Mushaf Hattı Seçin") {
                        ForEach(KBArabicFontStyle.allCases) { style in
                            Button {
                                store.arabicFontStyle = style
                            } label: {
                                HStack {
                                    Text(style.title)
                                    if store.arabicFontStyle == style {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                    Section("Türkçe Meal & Kelime Fontu Seçin") {
                        ForEach(KBTurkishFontStyle.allCases) { tStyle in
                            Button {
                                store.turkishFontStyle = tStyle
                            } label: {
                                HStack {
                                    Text(tStyle.title)
                                    if store.turkishFontStyle == tStyle {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "textformat.alt")
                            .font(.system(size: 11, weight: .bold))
                        Text("Hat: \(store.arabicFontStyle.shortBadge) · Tr: \(store.turkishFontStyle.shortBadge)")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(Color(red: 0.22, green: 0.14, blue: 0.08))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color.white)
                            .overlay(Capsule().stroke(Color.brown.opacity(0.35), lineWidth: 1))
                    )
                }

                // 3. Renkli Tecvid Modu Aç / Kapat
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        store.showColorTajweed.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(store.showColorTajweed ? Color.green : Color.gray)
                            .frame(width: 7, height: 7)
                        Text(store.showColorTajweed ? "Renkli Tecvid: Açık" : "Renkli Tecvid: Kapalı")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(store.showColorTajweed ? Color(red: 0.06, green: 0.45, blue: 0.22) : .gray)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color.white)
                            .overlay(Capsule().stroke(Color.green.opacity(0.45), lineWidth: 1))
                    )
                }

                // 4. Çevrimdışı Sûre İndir / Hazır
                Button {
                    Task {
                        await ikra.downloadSurahForOffline(surahId: store.currentSurahId, surahName: sName)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isOffline ? "checkmark.icloud.fill" : "arrow.down.circle.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text(isOffline ? "Çevrimdışı Hazır" : "Sûreyi İndir (MP3)")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundColor(isOffline ? Color(red: 0.08, green: 0.50, blue: 0.28) : Color(red: 0.78, green: 0.22, blue: 0.16))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color.white)
                            .overlay(Capsule().stroke(Color.orange.opacity(0.45), lineWidth: 1))
                    )
                }

                // 5. Canlı Diyanet Kur'an & Meal Radyoları
                Menu {
                    ForEach(ikra.liveRadioStations) { station in
                        Button {
                            ikra.playLiveRadio(station)
                        } label: {
                            Label(station.title, systemImage: station.icon)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 11, weight: .bold))
                        Text("Diyanet & Vav Radyo")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color(red: 0.78, green: 0.22, blue: 0.18)))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(Color(red: 0.90, green: 0.96, blue: 0.92))
        .overlay(Divider(), alignment: .bottom)
    }

    // MARK: - Interactive Color-Coded Tajweed Legend Bar

    private var tajweedColorLegendBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "paintbrush.pointed.fill")
                .font(.system(size: 11))
                .foregroundColor(Color(red: 0.14, green: 0.52, blue: 0.34))

            Text("Tecvid:")
                .font(.system(size: 10.5, weight: .bold))
                .foregroundColor(.black.opacity(0.75))

            ForEach(TajweedRuleInfo.allCases) { rule in
                HStack(spacing: 3) {
                    Circle()
                        .fill(rule.color)
                        .frame(width: 7, height: 7)
                    Text(rule.rawValue)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(rule.color)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.82))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.teal.opacity(0.22), lineWidth: 0.8)
                )
        )
    }

    // MARK: - Active İkra / Radio Floating Now Playing Bar

    private var activeIkraNowPlayingBar: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.yellow.opacity(0.25))
                    .frame(width: 32, height: 32)
                Image(systemName: "waveform")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.yellow)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(player.activeTitle.isEmpty ? "İkra Sesli Okuma" : player.activeTitle)
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(player.activeSubtitle.isEmpty ? ikra.currentTurkishArtist.name : player.activeSubtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
            }

            Spacer()

            Menu {
                ForEach([Float(0.75), Float(1.0), Float(1.25), Float(1.5)], id: \.self) { spd in
                    Button(String(format: "%.2gx Hız", spd)) {
                        ikra.playbackSpeed = spd
                    }
                }
            } label: {
                Text(String(format: "%.2gx", ikra.playbackSpeed))
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.yellow))
            }

            Button {
                player.stop()
            } label: {
                Image(systemName: "stop.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white, .red)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(red: 0.08, green: 0.34, blue: 0.26))
    }

    // MARK: - Light-Teal Surah Calligraphic Banner (Screenshot 1 & 2)

    private var surahCalligraphicBanner: some View {
        let ch = store.currentChapter
        let chTitleTr = ch?.turkishName ?? "Fâtiha"
        let totalAyahs = ch?.verses_count ?? store.verses.count
        let arName = ch?.name_arabic ?? "الفاتحة"
        let arSub = ch?.arabicBannerSubtitle ?? "مَكِّيَّةٌ وَهِيَ ٧ آيَةٌ - الترتيب الوحى ٥"

        return VStack(spacing: 8) {
            HStack {
                Button {
                    activeModal = .surahInfo
                } label: {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.cyan, Color.white)
                        .shadow(color: .black.opacity(0.15), radius: 2)
                }

                Spacer()

                Text("Toplam ayet: \(totalAyahs)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.gray)
            }

            Text("سُورَةُ \(arName)")
                .font(store.arabicFontStyle.font(size: 33))
                .foregroundColor(Color(red: 0.12, green: 0.28, blue: 0.24))

            Text(arSub)
                .font(store.arabicFontStyle.font(size: 16))
                .foregroundColor(Color(red: 0.15, green: 0.34, blue: 0.28))

            HStack {
                Button {
                    if let first = store.verses.first {
                        store.toggleFavorite(verse: first)
                    }
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.red)
                        Text("Seçilenler\nlistesine ekle")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.black.opacity(0.75))
                            .multilineTextAlignment(.center)
                    }
                }

                Spacer()

                Button {
                    activeModal = .surahList
                } label: {
                    Text("\(chTitleTr)/\(store.currentSurahId)")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color(red: 0.22, green: 0.76, blue: 0.48)))
                }

                Spacer()

                ShareLink(
                    item: "\(chTitleTr) Sûresi (\(totalAyahs) Ayet) — Kur'an Bilmek Kelime Mana Meal"
                ) {
                    VStack(spacing: 2) {
                        Image(systemName: "shareplay")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.red)
                        Text("Bu sureyi\npaylaş")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.black.opacity(0.75))
                            .multilineTextAlignment(.center)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(surahBannerBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.teal.opacity(0.25), lineWidth: 1)
                )
        )
    }

    // MARK: - Verse Block: RTL Word-by-Word Rows + Ornate Medallion + Comparative Meals

    @ViewBuilder
    private func verseBlockView(_ verse: KBVerse) -> some View {
        VStack(alignment: .trailing, spacing: 10) {
            if store.showMushafOnly && !sync.isActive {
                // Pure Mushaf Mode (Screenshot 2) with Arabic Mushaf Font + Color Tajweed
                HStack(alignment: .center, spacing: 8) {
                    verseMedallionAndQuickMenu(verse: verse)
                    Spacer()
                    if store.showColorTajweed {
                        Text(TajweedColorizer.colorizedArabic(verse.fullArabicText, defaultColor: Palette.textPrimary))
                            .font(store.arabicFontStyle.font(size: 34 * store.arabicFontScale * store.fontSizeScale))
                            .multilineTextAlignment(.trailing)
                            .lineSpacing(12)
                    } else {
                        Text(verse.fullArabicText)
                            .font(store.arabicFontStyle.font(size: 34 * store.arabicFontScale * store.fontSizeScale))
                            .foregroundColor(.black.opacity(0.88))
                            .multilineTextAlignment(.trailing)
                            .lineSpacing(12)
                    }
                }
                .padding(.vertical, 6)
            } else {
                VStack(alignment: .trailing, spacing: 8) {
                    verseMedallionAndQuickMenu(verse: verse)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: store.fontSizeScale > 1.25 ? 200 : 130), spacing: 8)], spacing: 10) {
                        ForEach(verse.actualWords) { word in
                            wordCellView(word: word, verse: verse)
                        }
                    }
                    .environment(\.layoutDirection, .rightToLeft)
                }
            }

            // Comparative Turkish Translations Under Each Verse (Screenshots 1 & 7)
            if store.showVerseTranslations && !store.showMushafOnly {
                VStack(alignment: .leading, spacing: 6) {
                    if store.showMealDiyanet, let text = verse.translationText(for: 77) {
                        comparativeMealBox(
                            authorTitle: "DİYANET VAKFI KURAN MEALİ",
                            surahId: verse.surahId,
                            surahName: store.currentChapter?.turkishName ?? "Sûre",
                            ayahNum: verse.verse_number,
                            text: text
                        )
                    }
                    let savedNote = store.noteText(for: verse.surahId, ayahNumber: verse.verse_number)
                    if !savedNote.isEmpty {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "note.text")
                                .foregroundColor(.orange)
                            Text("Notunuz: \(savedNote)")
                                .font(store.turkishFontStyle.font(size: 12, weight: .medium))
                                .foregroundColor(.black.opacity(0.8))
                            Spacer()
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.yellow.opacity(0.3)))
                    }
                }
            }

            // Diamond Divider between verses (Screenshot 1)
            HStack {
                Spacer()
                Image(systemName: "diamond.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.gray.opacity(0.45))
                Spacer()
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
    }

    private func chunkedWords(_ words: [KBWord], size: Int) -> [[KBWord]] {
        guard size > 0, !words.isEmpty else { return [] }
        var result: [[KBWord]] = []
        var idx = 0
        while idx < words.count {
            let end = min(idx + size, words.count)
            result.append(Array(words[idx..<end]))
            idx = end
        }
        return result
    }

    // MARK: - Single Word Cell (Arabic Mushaf Font + Color Tajweed + Turkish Meaning + Latin Reading)

    private func wordCellView(word: KBWord, verse: KBVerse) -> some View {
        let isSelected = selectedWordContext?.word.id == word.id
        let isFollowing = sync.verseKey == verse.verse_key && sync.positions.contains(word.position)
        return VStack(spacing: 3) {
            if sync.isActive {
                Image(systemName: "arrow.down")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Palette.accent)
                    .opacity(isFollowing ? 1 : 0)
                    .accessibilityHidden(!isFollowing)
                    .accessibilityLabel("Şimdi okunuyor")
            }
            if store.showColorTajweed {
                Text(TajweedColorizer.colorizedArabic(word.arabicDisplay, defaultColor: Palette.textPrimary))
                    .font(store.arabicFontStyle.font(size: 34 * store.arabicFontScale * store.fontSizeScale))
                    .environment(\.layoutDirection, .rightToLeft)
                    .padding(.vertical, 8)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
            } else {
                Text(word.arabicDisplay)
                    .font(store.arabicFontStyle.font(size: 34 * store.arabicFontScale * store.fontSizeScale))
                    .environment(\.layoutDirection, .rightToLeft)
                    .padding(.vertical, 8)
                    .foregroundColor(.black.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
            }

            Divider()
                .background(Color.gray.opacity(0.35))

            if store.showWordMeaning {
                Text(word.turkishMeaning)
                    .font(store.turkishFontStyle.font(size: 16 * store.turkishFontScale * store.fontSizeScale, weight: .semibold))
                    .foregroundColor(Palette.accent)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if store.showWordLatin {
                Text(word.turkishTransliteration)
                    .font(store.turkishFontStyle.font(size: 14 * store.turkishFontScale * store.fontSizeScale, weight: .regular))
                    .foregroundColor(Palette.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .frame(minWidth: 76, maxWidth: .infinity)
        .environment(\.layoutDirection, .leftToRight)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isFollowing ? Palette.accent.opacity(0.18) : (isSelected ? yellowPopupBg : Palette.card))
        )
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isFollowing ? Palette.accent : .clear, lineWidth: 2))
        .id(QFSyncPlayer.wordID(verseKey: verse.verse_key, position: word.position))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("quran-word-\(verse.verse_key)-\(word.position)")
        .accessibilityValue(isFollowing ? "Şimdi okunuyor" : "")
        .onTapGesture {
            if sync.isActive { sync.seek(verse: verse.verse_key, position: word.position) }
            else {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) { selectedWordContext = (word, verse) }
            }
        }
        .onLongPressGesture(minimumDuration: 0.45) {
            activeModal = .concordance(word)
        }
    }

    // MARK: - Ornate Verse Medallion & "HIZLI ULAŞIM" Context Menu (Screenshot 8)

    private func verseMedallionAndQuickMenu(verse: KBVerse) -> some View {
        HStack(spacing: 4) {
            Button {
                activeModal = .singleVerse(verse)
            } label: {
                ZStack {
                    Image(systemName: "seal")
                        .font(.system(size: 28, weight: .regular))
                        .foregroundColor(Color(red: 0.18, green: 0.56, blue: 0.36))
                    Text(arabicIndicNumber(verse.verse_number))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(red: 0.18, green: 0.56, blue: 0.36))
                }
            }

            Menu {
                Button {
                    store.playSingleAyahAudio(surahId: verse.surahId, ayahNumber: verse.verse_number)
                } label: {
                    Label("İkra Dinle (Arapça Hafız + Stüdyo Türkçe Meal)", systemImage: "waveform.circle.fill")
                }

                Button {
                    store.playSingleAyahTurkishMealStudio(surahId: verse.surahId, ayahNumber: verse.verse_number)
                } label: {
                    Label("Sadece Türkçe Sesli Meal Dinle (Sanatçı)", systemImage: "person.wave.2.fill")
                }

                Divider()

                Button {
                    store.toggleBookmark(verse: verse)
                } label: {
                    Label(
                        store.isBookmarked(verse) ? "Yer İşaretini Kaldır" : "Yeri İşaretle",
                        systemImage: "bookmark.fill"
                    )
                }

                Button {
                    activeModal = .bookmarks
                } label: {
                    Label("Yer İşareti Listesini Göster", systemImage: "eye")
                }

                Button {
                    store.toggleFavorite(verse: verse)
                } label: {
                    Label(
                        store.isFavorite(verse) ? "Seçilenlerden Çıkar" : "Bu Ayeti Seçilenler Listesine Kaydet",
                        systemImage: "star.fill"
                    )
                }

                Button {
                    activeModal = .favorites
                } label: {
                    Label("Seçilenler Listesini Göster", systemImage: "list.star")
                }

                Button {
                    activeModal = .singleVerse(verse)
                } label: {
                    Label("Meal Detay Ekranını Aç", systemImage: "text.justify")
                }

                Button {
                    activeModal = .wordList(verse)
                } label: {
                    Label("Ayetin Kelime Meali Göster/Paylaş", systemImage: "arrow.2.squarepath")
                }

                Button {
                    activeModal = .noteEditor(verse)
                } label: {
                    Label("Bu Ayete Not Ekle / Düzenle", systemImage: "square.and.pencil")
                }

                Button {
                    activeModal = .displaySettings
                } label: {
                    Label("Hat, Font, Tecvid ve Meal Ayarları", systemImage: "book.closed")
                }
            } label: {
                VStack(spacing: 1) {
                    Image(systemName: "arrowtriangle.down.fill")
                        .font(.system(size: 7))
                        .foregroundColor(.gray)
                    Text("HIZLI\nULAŞIM")
                        .font(.system(size: 6.5, weight: .bold))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 3)
                .padding(.vertical, 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.gray.opacity(0.4), lineWidth: 0.8)
                )
            }
        }
        .padding(.top, 8)
    }

    private func comparativeMealBox(authorTitle: String, surahId: Int, surahName: String, ayahNum: Int, text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(authorTitle)
                    .font(store.turkishFontStyle.font(size: 11, weight: .bold))
                    .foregroundColor(Palette.textSecondary)
                Text("[ \(surahName) / \(ayahNum) ]")
                    .font(.system(size: 10.5, weight: .regular))
                    .foregroundColor(.gray)

            }
            HStack(spacing: 12) {
                Button {
                    store.playSingleAyahAudio(surahId: surahId, ayahNumber: ayahNum)
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "play.circle.fill")
                        Text("İkra")
                    }
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundColor(Color(red: 0.08, green: 0.50, blue: 0.34))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.green.opacity(0.14)))
                }

                Button {
                    store.playSingleAyahTurkishMealStudio(surahId: surahId, ayahNumber: ayahNum)
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "speaker.wave.2.fill")
                        Text("Sesli Meal")
                    }
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundColor(Color(red: 0.72, green: 0.28, blue: 0.12))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.orange.opacity(0.16)))
                }
            }

            Text("\(ayahNum). \(text)")
                .font(store.turkishFontStyle.font(size: 20 * store.turkishFontScale * store.fontSizeScale, weight: .regular))
                .lineSpacing(7)
                .foregroundColor(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Palette.cardActive)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.orange.opacity(0.22), lineWidth: 0.8)
                        )
                )
        }
    }

    // MARK: - Signature Yellow Word Detail Popup (Screenshot 4)

    private func yellowWordDetailPopup(word: KBWord, verse: KBVerse) -> some View {
        ScrollView {
            VStack(spacing: 22) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("KELİMEYİ KEŞFET").font(.system(size: 10, weight: .bold)).tracking(2).foregroundStyle(Palette.accent)
                        Text("\(store.surahName(for: verse.surahId)) · \(verse.verse_number). ayet").font(.caption).foregroundStyle(Palette.textSecondary)
                    }
                    Spacer()
                    Button { selectedWordContext = nil } label: {
                        Image(systemName: "xmark").font(.subheadline.weight(.semibold)).frame(width: 44, height: 44)
                            .background(Palette.cardActive, in: Circle())
                    }.accessibilityLabel("Kelime detayını kapat")
                }
                Button {
                    UIPasteboard.general.string = word.arabicDisplay
                    copiedWordToast = "Arapça kelime kopyalandı"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { copiedWordToast = nil }
                } label: {
                    Text(word.arabicDisplay).font(.custom("AmiriQuran-Regular", size: 44))
                        .environment(\.layoutDirection, .rightToLeft)
                        .padding(.vertical, 16).frame(maxWidth: .infinity)
                        .foregroundStyle(Palette.textPrimary).background(Palette.cardActive, in: RoundedRectangle(cornerRadius: 20))
                }.accessibilityHint("Arapça kelimeyi kopyalar")
                VStack(spacing: 8) {
                    Text(word.turkishMeaning).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
                    if !word.turkishTransliteration.isEmpty {
                        Text(word.turkishTransliteration).font(.subheadline).foregroundStyle(Palette.textSecondary)
                        Text("Latin harfli yaklaşık okunuş").font(.caption2).foregroundStyle(Palette.textSecondary)
                    }
                }
                HStack(spacing: 12) {
                    Button { store.playWordAudio(word) } label: { Label("Arapça dinle", systemImage: "play.fill").frame(maxWidth: .infinity, minHeight: 44) }
                        .buttonStyle(.borderedProminent)
                    Button { AdhanPlayer.shared.speakText(word.turkishMeaning, language: "tr-TR") } label: { Image(systemName: "speaker.wave.2").frame(minWidth: 40, minHeight: 44) }
                        .buttonStyle(.bordered).disabled(!word.hasTurkishMeaning).accessibilityLabel("Türkçe anlamı dinle")
                }
                Divider()
                if !word.arabicRootLetters.isEmpty {
                    HStack {
                        Text("Sözlük kökü").font(.subheadline).foregroundStyle(Palette.textSecondary)
                        Spacer()
                        Text(word.arabicRootLetters).font(.custom("Amiri-Regular", size: 28)).environment(\.layoutDirection, .rightToLeft)
                    }
                }
                Button {
                    selectedWordContext = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { activeModal = .concordance(word) }
                } label: { Label("Kayıtlı ayetlerde ara", systemImage: "text.magnifyingglass").frame(maxWidth: .infinity, minHeight: 44) }
                Text("Kelime anlamı ayet bağlamıyla birlikte okunmalıdır. Latin okunuş, Arapça seslerin tamamını karşılamaz.")
                    .font(.caption).foregroundStyle(Palette.textSecondary).multilineTextAlignment(.center)
                Button {
                    store.toggleBookmark(verse: verse)
                    selectedWordContext = nil
                } label: { Label("Yer işaretini değiştir", systemImage: "bookmark").font(.subheadline).frame(minHeight: 44) }
            }.padding(22)
        }
        .frame(maxWidth: 360, maxHeight: 620)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 28))
        .padding(20).foregroundStyle(Palette.textPrimary).tint(Palette.accent)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityAddTraits(.isModal)
    }

    // MARK: - Bottom Control Bar ("OKU ▶", Auto-scroll, Settings Gear, Fullscreen)

    private var bottomOkuControlBar: some View {
        HStack(spacing: 12) {
            Button { showReadingTools.toggle() } label: {
                Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44)
            }.accessibilityLabel("Ses ve yazı araçları")
            Button { activeModal = .bookmarks } label: {
                Image(systemName: "bookmark").frame(width: 44, height: 44)
            }.accessibilityLabel("Yer işaretleri")
            Spacer(minLength: 0)
            Button { activeModal = .okuBottom } label: {
                Label("Dinle", systemImage: "play.fill").font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 18).frame(height: 44).foregroundStyle(.white)
                    .background(EzanDesign.forest, in: Capsule())
            }
            Spacer(minLength: 0)
            Button { activeModal = .displaySettings } label: {
                Image(systemName: "textformat.size").frame(width: 44, height: 44)
            }.accessibilityLabel("Okuma görünümü ayarları")
            Button { isFullscreenMushaf.toggle() } label: {
                Image(systemName: isFullscreenMushaf ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right").frame(width: 44, height: 44)
            }.accessibilityLabel(isFullscreenMushaf ? "Tam ekrandan çık" : "Tam ekran oku")
        }.font(.subheadline).foregroundStyle(Palette.accent).padding(.horizontal, 12).padding(.vertical, 6)
            .background(Palette.card).overlay(alignment: .top) { Divider() }
    }

    private func arabicIndicNumber(_ num: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "ar")
        return formatter.string(from: NSNumber(value: num)) ?? "\(num)"
    }

    private func handleDrawerAction(_ action: KBDrawerAction) {
        switch action {
        case .settings:
            activeModal = .displaySettings
        case .surahs:
            activeModal = .surahList
        case .duas:
            activeModal = .duaSubmenu
        case .tefeul:
            if let randomVerse = store.verses.randomElement() {
                activeModal = .tefeul(randomVerse)
            }
        case .pageJuz:
            activeModal = .pageJuzPicker
        case .topics:
            activeModal = .topics
        case .bookmarks:
            activeModal = .bookmarks
        case .favorites:
            activeModal = .favorites
        case .notes:
            activeModal = .notesList
        }
    }
}
