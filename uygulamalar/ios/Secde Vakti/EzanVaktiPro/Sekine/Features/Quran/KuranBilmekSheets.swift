import SwiftUI

enum KBDrawerAction {
    case settings
    case surahs
    case duas
    case tefeul
    case pageJuz
    case topics
    case bookmarks
    case favorites
    case notes
}

// MARK: - 1. Sol Üst Genel Menü Drawer (Screenshot 5)

struct KBGeneralMenuDrawer: View {
    let onSelectAction: (KBDrawerAction) -> Void
    @Environment(\.dismiss) private var dismiss

    private let creamBg = Color(red: 0.99, green: 0.97, blue: 0.90)

    var body: some View {
        NavigationStack {
            List {
                Button {
                    onSelectAction(.settings)
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.white)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(Color(red: 0.35, green: 0.15, blue: 0.15)))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("AYARLAR")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.red)
                            Text("Tema, kelime manası, mealler ve font ayarları...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.right")
                            .foregroundColor(.primary)
                    }
                    .padding(.vertical, 4)
                }

                Section("KUR'AN BİLMEK MENÜSÜ") {
                    drawerRow(icon: "book.closed.fill", title: "Kuran-ı Kerim Sureler (Sıralama & Ayete Git)", action: .surahs)
                    drawerRow(icon: "text.bubble.fill", title: "Dua'lar (Hatim, Rabbenâ & Sekine Duası)", action: .duas)
                    drawerRow(icon: "shuffle", title: "Tefeülle ayet göster", action: .tefeul)
                    drawerRow(icon: "doc.text.fill", title: "Sayfa, Cüz - Hizb Aç (1-604 / 30 Cüz)", action: .pageJuz)
                    drawerRow(icon: "magnifyingglass.circle.fill", title: "Konularda ara (Kur'an Konu Fihristi)", action: .topics)
                    drawerRow(icon: "bookmark.fill", title: "Kaydedilen yer işaretleri", action: .bookmarks)
                    drawerRow(icon: "star.fill", title: "Seçilen Sure / Ayet", action: .favorites)
                    drawerRow(icon: "square.and.pencil", title: "Not kaydet / oku", action: .notes)
                }
            }
            .scrollContentBackground(.hidden)
            .background(creamBg)
            .navigationTitle("Kur'an Bilmek Menüsü")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
    }

    private func drawerRow(icon: String, title: String, action: KBDrawerAction) -> some View {
        Button {
            onSelectAction(action)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 17))
                    .foregroundColor(.gray)
                    .frame(width: 28)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - 2. Ana Sayfa Görünüm Ayarları (Screenshot 3)

struct KBDisplaySettingsSheet: View {
    @ObservedObject var store: KuranBilmekStore
    @Environment(\.dismiss) private var dismiss

    private let mintBg = Color(red: 0.18, green: 0.78, blue: 0.56)

    var body: some View {
        NavigationStack {
            ZStack {
                mintBg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Okuma ve ekran ayarları")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.top, 8)

                        VStack(alignment: .leading, spacing: 12) {
                            Label("İki parmakla yakınlaştır", systemImage: "hand.pinch")
                                .font(.headline)
                            Text("Okuma alanında iki parmağınızı açın veya kapatın. Parmaklarınızı kaldırdığınızda yazı boyutu uygulanır ve kelimeler ekrana yeniden sığar.")
                                .font(.subheadline)
                            HStack {
                                Button("Küçült") { store.fontSizeScale = max(0.8, store.fontSizeScale - 0.1) }
                                Spacer()
                                Text("%\(Int(store.fontSizeScale * 100))").monospacedDigit()
                                Spacer()
                                Button("Büyüt") { store.fontSizeScale = min(1.8, store.fontSizeScale + 0.1) }
                            }.buttonStyle(.bordered)
                            Button("Okuma boyutlarını sıfırla") {
                                store.fontSizeScale = 1
                                store.arabicFontScale = 1.08
                                store.turkishFontScale = 1
                            }
                        }.padding().background(.white, in: RoundedRectangle(cornerRadius: 16))

                        // Reading preferences
                        VStack(alignment: .leading, spacing: 14) {
                            radioToggleRow(
                                isOn: !store.showMushafOnly,
                                title: "Kur'an sayfası kelime görünümü"
                            ) {
                                store.showMushafOnly = false
                            }

                            radioToggleRow(
                                isOn: store.showWordMeaning && !store.showMushafOnly,
                                title: "Kelime altında MANA görünümü"
                            ) {
                                store.showMushafOnly = false
                                store.showWordMeaning.toggle()
                            }

                            radioToggleRow(
                                isOn: store.showWordLatin && !store.showMushafOnly,
                                title: "Kelime Altında LATİN okunuşları"
                            ) {
                                store.showMushafOnly = false
                                store.showWordLatin.toggle()
                            }

                            radioToggleRow(
                                isOn: store.showVerseTranslations && !store.showMushafOnly,
                                title: "Ayetlerin altında meal görünümü"
                            ) {
                                store.showMushafOnly = false
                                store.showVerseTranslations.toggle()
                            }

                            Divider()

                            // Arapça Mushaf Hattı & Renkli Tecvid Bölümü
                            Text("ARAPÇA MUSHAF HATTI VE RENKLİ TECVİD AYARLARI")
                                .font(.caption.weight(.bold))
                                .foregroundColor(Color(red: 0.08, green: 0.50, blue: 0.34))

                            // Canlı Besmele Hat & Tecvid Önizleme Kutusu
                            VStack(spacing: 6) {
                                if store.showColorTajweed {
                                    Text(TajweedColorizer.colorizedArabic("بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ"))
                                        .font(store.arabicFontStyle.font(size: 27 * store.arabicFontScale))
                                        .multilineTextAlignment(.center)
                                } else {
                                    Text("بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ")
                                        .font(store.arabicFontStyle.font(size: 27 * store.arabicFontScale))
                                        .foregroundColor(.black)
                                        .multilineTextAlignment(.center)
                                }
                                Text("Aktif Hat: \(store.arabicFontStyle.title)")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(red: 0.98, green: 0.95, blue: 0.86))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.teal.opacity(0.3), lineWidth: 1))
                            )

                            Picker("Arapça Mushaf Hattı", selection: $store.arabicFontStyle) {
                                ForEach(KBArabicFontStyle.allCases) { style in
                                    Text(style.title).tag(style)
                                }
                            }
                            .pickerStyle(.menu)

                            Toggle("Renkli Tecvid Modu (Gunne, İhfa, Kalkale, Med)", isOn: $store.showColorTajweed)
                                .font(.subheadline.weight(.semibold))
                                .tint(.green)

                            Toggle("Tecvid Renk Rehberi Şeridini Göster", isOn: $store.showTajweedLegend)
                                .font(.caption)
                                .tint(.teal)

                            HStack {
                                Text("Arapça Hat Boyutu:")
                                    .font(.subheadline.weight(.semibold))
                                Slider(value: $store.arabicFontScale, in: 0.80...1.60, step: 0.05)
                                Text("\(Int(store.arabicFontScale * 100))%")
                                    .font(.caption.weight(.bold))
                            }

                            Divider()

                            // Türkçe Meal & Kelime Fontu Bölümü
                            Text("TÜRKÇE MEAL & KELİME FONT AYARLARI")
                                .font(.caption.weight(.bold))
                                .foregroundColor(Color(red: 0.72, green: 0.28, blue: 0.12))

                            Picker("Türkçe Yazı Tipi (Font)", selection: $store.turkishFontStyle) {
                                ForEach(KBTurkishFontStyle.allCases) { tStyle in
                                    Text(tStyle.title).tag(tStyle)
                                }
                            }
                            .pickerStyle(.menu)

                            Text("İnce çizgiler, açık bir gökyüzü: ç, ğ, ı, İ, ö, ş, ü.")
                                .font(store.turkishFontStyle.font(size: 22))
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(12)
                                .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

                            HStack {
                                Text("Türkçe Meal Boyutu:")
                                    .font(.subheadline.weight(.semibold))
                                Slider(value: $store.turkishFontScale, in: 0.80...1.50, step: 0.05)
                                Text("\(Int(store.turkishFontScale * 100))%")
                                    .font(.caption.weight(.bold))
                            }

                            Divider()

                            Text("Diyanet meali ve yazı ölçeği:")
                                .font(.caption.weight(.bold))
                                .foregroundColor(.secondary)

                            Toggle("Diyanet Vakfı Kur’an Meali", isOn: $store.showMealDiyanet)
                                .font(.subheadline)

                            HStack {
                                Text("Genel Ölçek:")
                                    .font(.subheadline.weight(.semibold))
                                Slider(value: $store.fontSizeScale, in: 0.8...1.8, step: 0.05)
                                Text("\(Int(store.fontSizeScale * 100))%")
                                    .font(.caption.weight(.bold))
                            }

                            Divider()

                            // Preset 1: Sadece Kur'an Sayfası olarak göster
                            Button {
                                store.showMushafOnly = true
                                dismiss()
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: "doc.richtext.fill")
                                        .font(.system(size: 24))
                                        .foregroundColor(.pink)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("Sadece Kur'an Sayfası olarak göster")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundColor(.pink)
                                        Text("Bu durumda ana ekranda sadece Arapça Mushaf ayetleri gösterilecektir.")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }

                            Divider()

                            // Preset 2: Tüm seçenekleri aktif ederek göster
                            Button {
                                store.showMushafOnly = false
                                store.showWordMeaning = true
                                store.showWordLatin = true
                                store.showVerseTranslations = true
                                store.showMealDiyanet = true
                                dismiss()
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: "list.bullet.rectangle.fill")
                                        .font(.system(size: 24))
                                        .foregroundColor(.pink)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("Tüm seçenekleri aktif ederek göster")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundColor(.pink)
                                        Text("Bu durumda ana ekranda:\n- Kur'an Ayetleri,\n- Kelime Manası,\n- Arapça Kelime Latin Okunuşu,\n- Diyanet meali gösterilecektir.")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .multilineTextAlignment(.leading)
                                    }
                                }
                            }
                        }
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))

                        HStack(spacing: 16) {
                            Button {
                                dismiss()
                            } label: {
                                Text("VAZGEÇ")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.black)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Capsule().fill(Color.white))
                            }

                            Button {
                                dismiss()
                            } label: {
                                Text("TAMAM")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.black)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Capsule().fill(Color.white))
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    private func radioToggleRow(isOn: Bool, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isOn ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(Color(red: 0.08, green: 0.62, blue: 0.68))
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Color(red: 0.08, green: 0.56, blue: 0.64))
                Spacer()
            }
        }
    }
}

// MARK: - 3. Sûre Sıralama (Alfabetik / Kur'an Sırası / Nüzul Sırası) & Hızlı Ayete Git (Screenshot 6)

struct KBSurahNavigatorSheet: View {
    @ObservedObject var store: KuranBilmekStore
    let onSelectSurahAyah: (Int, Int) -> Void
    @Environment(\.dismiss) private var dismiss

    enum SortOrder: String, CaseIterable {
        case alphabetical = "Alfabetik sıra"
        case mushaf = "Kuran sırası"
        case revelation = "Nuzul sırası"
    }

    @State private var sortOrder: SortOrder = .mushaf
    @State private var searchText: String = ""
    @State private var selectedChapterForAyahJump: KBChapter? = nil

    private var sortedChapters: [KBChapter] {
        let filtered = store.chapters.filter { ch in
            guard !searchText.isEmpty else { return true }
            return ch.turkishName.localizedCaseInsensitiveContains(searchText) ||
                   "\(ch.id)".contains(searchText) ||
                   ch.name_arabic.contains(searchText)
        }
        switch sortOrder {
        case .alphabetical:
            return filtered.sorted { $0.turkishName.localizedCompare($1.turkishName) == .orderedAscending }
        case .mushaf:
            return filtered.sorted { $0.id < $1.id }
        case .revelation:
            return filtered.sorted { $0.revelation_order < $1.revelation_order }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 0) {
                    // 3-Way Sort Picker matching Screenshot 6
                    Picker("Sıralama", selection: $sortOrder) {
                        ForEach(SortOrder.allCases, id: \.self) { order in
                            Text(order.rawValue).tag(order)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(10)
                    .background(Color(red: 0.80, green: 0.95, blue: 0.88))

                    // Search Field
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Sure ara (Örn: Yâsîn, Mülk, 36)...", text: $searchText)
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray6)))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)

                    List(sortedChapters) { ch in
                        HStack {
                            Button {
                                onSelectSurahAyah(ch.id, 1)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(ch.id)) \(ch.turkishName)")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.primary)
                                    Text("(\(ch.verses_count) ayet, Sayfa: \(ch.startPage), Nüzul: \(ch.revelation_order). sıra - \(ch.revelationPlaceTurkish))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Spacer()

                            Text(ch.name_arabic)
                                .font(.system(size: 20, design: .serif))
                                .foregroundColor(Color(red: 0.14, green: 0.50, blue: 0.34))

                            Button {
                                selectedChapterForAyahJump = ch
                            } label: {
                                Text("Ayete Git")
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Capsule().fill(Color(red: 0.18, green: 0.72, blue: 0.48)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listStyle(.plain)
                }

                // Popup Ayah Selector ("1. ayete git", "2. ayete git"...) matching Screenshot 6
                if let ch = selectedChapterForAyahJump {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture { selectedChapterForAyahJump = nil }

                    VStack(spacing: 0) {
                        HStack {
                            Text("\(ch.turkishName) - \(ch.id) (\(ch.verses_count) ayet)")
                                .font(.system(size: 15, weight: .bold))
                            Spacer()
                            Button {
                                selectedChapterForAyahJump = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.white, .red)
                            }
                        }
                        .padding(12)
                        .background(Color(.systemGray6))

                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(1...max(1, ch.verses_count), id: \.self) { anum in
                                    Button {
                                        selectedChapterForAyahJump = nil
                                        onSelectSurahAyah(ch.id, anum)
                                        dismiss()
                                    } label: {
                                        HStack {
                                            Text("\(anum). ayete git")
                                                .font(.system(size: 15, weight: .medium))
                                                .foregroundColor(.primary)
                                            Spacer()
                                            Image(systemName: "arrow.right.circle")
                                                .foregroundColor(.secondary)
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 11)
                                    }
                                    Divider()
                                }
                            }
                        }
                    }
                    .frame(width: 270, height: 420)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground)))
                    .shadow(radius: 16)
                }
            }
            .navigationTitle("Kur'an-ı Kerim Sûreleri")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
    }
}

// MARK: - 4. Tek Ayet Detay Ekranı (Screenshot 7)

struct KBSingleVerseDetailModal: View {
    @ObservedObject var store: KuranBilmekStore
    let initialVerse: KBVerse
    let onOpenNote: (KBVerse) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var currentIndex: Int = 0
    @State private var hideWordMeanings: Bool = false
    @State private var showReciterPicker: Bool = false

    private var activeVerse: KBVerse {
        guard !store.verses.isEmpty, currentIndex >= 0, currentIndex < store.verses.count else {
            return initialVerse
        }
        return store.verses[currentIndex]
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header matching Screenshot 7
                let ch = store.currentChapter
                let v = activeVerse
                VStack(spacing: 3) {
                    HStack {
                        Spacer()
                        Text("\(ch?.turkishName ?? "Sûre") Suresi ")
                            .font(.system(size: 16, weight: .bold)) +
                        Text("Ayet: \(v.verse_number)")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.red) +
                        Text(" / T. \(ch?.verses_count ?? store.verses.count) ayet")
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(.white, .red)
                        }
                    }
                    Text("Sayfa: \(v.page_number ?? 1) (Kuran: \(v.surahId), Vahiy: \(ch?.revelation_order ?? 1). sıra) Cüz: \(v.juz_number ?? 1), Hizb: \(v.hizb_number ?? 1)")
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                }
                .padding(10)
                .background(Color(red: 0.95, green: 0.98, blue: 0.96))

                ScrollView {
                    VStack(spacing: 14) {
                        // Word-by-Word Grid with MANA GİZLE toggle
                        let columns = [GridItem(.adaptive(minimum: 80, maximum: 130), spacing: 8)]
                        LazyVGrid(columns: columns, alignment: .center, spacing: 10) {
                            ForEach(v.actualWords) { w in
                                VStack(spacing: 4) {
                                    Text(w.arabicDisplay)
                                        .font(.system(size: 26, design: .serif))
                                    if !hideWordMeanings {
                                        Text(w.turkishMeaning)
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(Color(red: 0.16, green: 0.44, blue: 0.29))
                                            .multilineTextAlignment(.center)
                                    }
                                }
                                .padding(6)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.6)))
                                .onTapGesture {
                                    store.playWordAudio(w)
                                }
                            }
                        }

                        HStack {
                            Button {
                                hideWordMeanings.toggle()
                            } label: {
                                Label(hideWordMeanings ? "MANA GÖSTER" : "MANA GİZLE", systemImage: hideWordMeanings ? "eye.slash" : "eye")
                                    .font(.caption.weight(.bold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Capsule().fill(Color.white))
                            }

                            Spacer()

                            Button {
                                store.toggleBookmark(verse: v)
                            } label: {
                                Image(systemName: store.isBookmarked(v) ? "bookmark.fill" : "bookmark")
                                    .foregroundColor(.red)
                                    .padding(8)
                                    .background(Circle().fill(Color.white))
                            }

                            Button {
                                store.toggleFavorite(verse: v)
                            } label: {
                                Image(systemName: store.isFavorite(v) ? "star.fill" : "star")
                                    .foregroundColor(.orange)
                                    .padding(8)
                                    .background(Circle().fill(Color.white))
                            }
                        }

                        // Comparative Translations
                        VStack(alignment: .leading, spacing: 10) {
                            if let t1 = v.translationText(for: 77) {
                                mealCard(title: "DİYANET VAKFI KURAN MEALİ [ \(ch?.turkishName ?? "") / \(v.verse_number) ]", bodyText: "\(v.verse_number). \(t1)")
                            }
                        }
                    }
                    .padding(14)
                }
                .background(Color(red: 0.98, green: 0.95, blue: 0.85))

                // Bottom Bar: Okuyucu seç + SESLİ OKU + ÖNCEKİ AYET / SONRAKİ AYET + NOTLAR (Screenshot 7)
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        Menu {
                            ForEach(store.reciters, id: \.id) { rec in
                                Button {
                                    store.selectedReciter = rec.id
                                } label: {
                                    HStack {
                                        Text(rec.name)
                                        if store.selectedReciter == rec.id {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text("Okuyucu seç")
                                    .font(.caption.weight(.semibold))
                                Image(systemName: "ellipsis.circle.fill")
                                    .foregroundColor(.red)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.white))
                        }

                        Button {
                            store.playSingleAyahAudio(surahId: v.surahId, ayahNumber: v.verse_number)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(.white, .red)
                                Text("SESLİ OKU")
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(.red)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.white))
                        }
                    }

                    HStack {
                        Button {
                            onOpenNote(v)
                        } label: {
                            VStack(spacing: 2) {
                                Image(systemName: "square.and.pencil")
                                    .foregroundColor(.green)
                                Text("NOTLAR")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white))
                        }

                        Spacer()

                        Button {
                            if currentIndex > 0 { currentIndex -= 1 }
                        } label: {
                            HStack(spacing: 4) {
                                Text("ÖNCEKİ AYET")
                                    .font(.system(size: 11, weight: .bold))
                                Image(systemName: "chevron.up.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(Color(red: 0.12, green: 0.52, blue: 0.44))
                            }
                        }
                        .disabled(currentIndex <= 0)

                        Button {
                            if currentIndex + 1 < store.verses.count { currentIndex += 1 }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.down.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(Color(red: 0.12, green: 0.52, blue: 0.44))
                                Text("SONRAKİ AYET")
                                    .font(.system(size: 11, weight: .bold))
                            }
                        }
                        .disabled(currentIndex + 1 >= store.verses.count)

                        Spacer()

                        ShareLink(item: "\(v.fullArabicText)\n\n\(v.translationText(for: 77) ?? "")") {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 18, weight: .bold))
                                .padding(8)
                                .background(Circle().fill(Color.white))
                        }
                    }
                }
                .padding(10)
                .background(Color(red: 0.92, green: 0.96, blue: 0.94))
            }
            .onAppear {
                if let idx = store.verses.firstIndex(where: { $0.id == initialVerse.id }) {
                    currentIndex = idx
                }
            }
        }
    }

    private func mealCard(title: String, bodyText: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
            Text(bodyText)
                .font(.system(size: 14))
                .foregroundColor(.primary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(red: 0.89, green: 0.96, blue: 0.96)))
        }
    }
}

// MARK: - 5. "OKU ▶" Modal: İkra Seslendirme Sanatçıları, Çevrimdışı Sûre İndir, Diyanet Radyo & Aşr-ı Şerif (Screenshot 9 + Ultra Upgrade)

struct KBOkuAudioSheet: View {
    @ObservedObject var store: KuranBilmekStore
    @ObservedObject private var ikra = IkraAudioAndRadioCenter.shared
    @ObservedObject private var player = AdhanPlayer.shared
    let onJumpToSurahAyah: (Int, Int) -> Void
    @Environment(\.dismiss) private var dismiss

    enum OkuTab: String, CaseIterable {
        case ikraArtists = "İkra & Ünlü Sesler"
        case surahDownload = "Sûre Dinle & İndir"
        case liveRadio = "Diyanet & Vav"
        case asriSerif = "Aşr-ı Şerif Oku"
        case ayahRange = "Ayetler Oku"
    }

    @State private var selectedTab: OkuTab = .ikraArtists
    @State private var customStartAyah: Int = 1
    @State private var customEndAyah: Int = 7

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Top Scrollable Pill Tabs
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(OkuTab.allCases, id: \.self) { tab in
                            Button {
                                selectedTab = tab
                            } label: {
                                Text(tab.rawValue)
                                    .font(.system(size: 12.5, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 13)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule().fill(
                                            selectedTab == tab
                                                ? Color(red: 0.94, green: 0.36, blue: 0.28)
                                                : Color(red: 0.14, green: 0.68, blue: 0.44)
                                        )
                                    )
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .background(Color(red: 0.94, green: 0.98, blue: 0.95))

                Divider()

                switch selectedTab {
                case .ikraArtists:
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            // 1. Playback Mode Selector
                            VStack(alignment: .leading, spacing: 8) {
                                Text("1. OKUMA VE SESLENDİRME MODU SEÇİN")
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(Color(red: 0.08, green: 0.48, blue: 0.32))

                                ForEach(IkraPlaybackMode.allCases) { mode in
                                    Button {
                                        ikra.playbackMode = mode
                                    } label: {
                                        HStack {
                                            Image(systemName: ikra.playbackMode == mode ? "largecircle.fill.circle" : "circle")
                                                .foregroundColor(Color(red: 0.12, green: 0.62, blue: 0.42))
                                            Text(mode.title)
                                                .font(.system(size: 13.5, weight: .semibold))
                                                .foregroundColor(.primary)
                                            Spacer()
                                        }
                                        .padding(10)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10)
                                                .fill(ikra.playbackMode == mode ? Color.green.opacity(0.12) : Color(.secondarySystemBackground))
                                        )
                                    }
                                }
                            }
                            .padding(.horizontal, 14)

                            // 2. Famous Turkish Voice Artists (İkra Sesleri)
                            VStack(alignment: .leading, spacing: 8) {
                                Text("2. ÜNLÜ TÜRKÇE MEAL & İKRA SANATÇILARI (7 SANATÇI)")
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(Color(red: 0.78, green: 0.24, blue: 0.16))

                                ForEach(ikra.turkishVoiceArtists) { artist in
                                    let isSelected = ikra.selectedTurkishArtistId == artist.id
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Button {
                                                ikra.selectedTurkishArtistId = artist.id
                                            } label: {
                                                HStack(spacing: 8) {
                                                    Image(systemName: isSelected ? "checkmark.seal.fill" : "person.wave.2.fill")
                                                        .font(.title3)
                                                        .foregroundColor(isSelected ? .green : .orange)
                                                    VStack(alignment: .leading, spacing: 2) {
                                                        Text(artist.name)
                                                            .font(.system(size: 14.5, weight: .bold))
                                                            .foregroundColor(.primary)
                                                        Text(artist.roleBadge)
                                                            .font(.caption2.weight(.bold))
                                                            .foregroundColor(.white)
                                                            .padding(.horizontal, 7)
                                                            .padding(.vertical, 2)
                                                            .background(Capsule().fill(Color(red: 0.82, green: 0.32, blue: 0.18)))
                                                    }
                                                }
                                            }

                                            Spacer()

                                            Button {
                                                ikra.selectedTurkishArtistId = artist.id
                                                let sName = store.currentChapter?.turkishName ?? "Fâtiha"
                                                ikra.playSurah(surahId: store.currentSurahId, surahName: sName)
                                            } label: {
                                                Label("Dinle", systemImage: "play.fill")
                                                    .font(.caption.weight(.bold))
                                            }
                                            .buttonStyle(.borderedProminent)
                                            .tint(Color(red: 0.12, green: 0.56, blue: 0.38))
                                        }

                                        Text(artist.description)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(isSelected ? Color.yellow.opacity(0.18) : Color(.secondarySystemBackground))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(isSelected ? Color.orange : Color.clear, lineWidth: 1.5)
                                            )
                                    )
                                }
                            }
                            .padding(.horizontal, 14)

                            // 3. 14 Famous World & Turkish Quran Reciters
                            VStack(alignment: .leading, spacing: 8) {
                                Text("3. TÜRK VE DÜNYA HAFIZLARI")
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(Color(red: 0.10, green: 0.36, blue: 0.68))

                                ForEach(ikra.famousArabicReciters) { reciter in
                                    let isRecSelected = ikra.selectedArabicReciterId == reciter.id
                                    HStack {
                                        Button {
                                            ikra.selectedArabicReciterId = reciter.id
                                            store.selectedReciter = reciter.id
                                        } label: {
                                            HStack(spacing: 10) {
                                                Image(systemName: isRecSelected ? "checkmark.circle.fill" : "mic.circle.fill")
                                                    .font(.title3)
                                                    .foregroundColor(isRecSelected ? .blue : .teal)
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(reciter.name)
                                                        .font(.system(size: 14, weight: .bold))
                                                        .foregroundColor(.primary)
                                                    Text("\(reciter.countryAndTitle) · \(reciter.styleBadge)")
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                        }
                                        Spacer()
                                        Button {
                                            ikra.selectedArabicReciterId = reciter.id
                                            store.selectedReciter = reciter.id
                                            ikra.playArabicAyah(surahId: store.currentSurahId, ayah: 1, title: store.surahName(for: store.currentSurahId))
                                        } label: {
                                            Image(systemName: "play.circle.fill")
                                                .font(.title2)
                                                .foregroundColor(.blue)
                                        }
                                    }
                                    .padding(10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(isRecSelected ? Color.blue.opacity(0.10) : Color(.secondarySystemBackground))
                                    )
                                }
                            }
                            .padding(.horizontal, 14)
                        }
                        .padding(.vertical, 12)
                    }

                case .surahDownload:
                    VStack(spacing: 0) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Aktif Sanatçı: \(ikra.currentTurkishArtist.name)")
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(.primary)
                                Text("Çevrimdışı Arşiv: \(ikra.totalOfflineStorageString)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button {
                                Task {
                                    for sid in [1, 36, 67, 112, 113, 114] {
                                        await ikra.downloadSurahForOffline(surahId: sid, surahName: store.surahName(for: sid))
                                    }
                                }
                            } label: {
                                Label("Namaz Sûrelerini İndir", systemImage: "arrow.down.to.line.circle.fill")
                                    .font(.caption2.weight(.bold))
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                        }
                        .padding(12)
                        .background(Color(.secondarySystemBackground))

                        List(store.chapters) { ch in
                            let isReady = ikra.isSurahAvailableOffline(surahId: ch.id)
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text("\(ch.id). \(ch.turkishName) Sûresi")
                                            .font(.subheadline.weight(.bold))
                                        if isReady {
                                            Text("✓ Çevrimdışı")
                                                .font(.system(size: 9.5, weight: .bold))
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Capsule().fill(Color.green))
                                        }
                                    }
                                    Text("\(ch.verses_count) Ayet · \(ch.revelationPlaceTurkish) · \(ikra.playbackMode.shortLabel)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Button {
                                    ikra.playSurah(surahId: ch.id, surahName: ch.turkishName)
                                } label: {
                                    Label("Dinle", systemImage: "play.fill")
                                        .font(.caption.weight(.bold))
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(Color(red: 0.14, green: 0.64, blue: 0.42))

                                Button {
                                    Task {
                                        await ikra.downloadSurahForOffline(surahId: ch.id, surahName: ch.turkishName)
                                    }
                                } label: {
                                    Image(systemName: isReady ? "checkmark.icloud.fill" : "arrow.down.circle.fill")
                                        .font(.title3)
                                        .foregroundColor(isReady ? .green : .orange)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .listStyle(.plain)
                    }

                case .liveRadio:
                    List {
                        Section("Diyanet ve Vav · Canlı Radyo") {
                            ForEach(ikra.liveRadioStations) { station in
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.red.opacity(0.14))
                                            .frame(width: 42, height: 42)
                                        Image(systemName: station.icon)
                                            .font(.headline)
                                            .foregroundColor(.red)
                                    }

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(station.title)
                                            .font(.subheadline.weight(.bold))
                                        Text(station.subtitle)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    Button {
                                        ikra.playLiveRadio(station)
                                    } label: {
                                        Label("Canlı Aç", systemImage: "play.fill")
                                            .font(.caption.weight(.bold))
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.red)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)

                case .asriSerif:
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Gün ve gündeme göre okunabilecek seçme Aşr-ı Şerifler (İkra Ar+Tr)")
                                .font(.caption.weight(.bold))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 14)

                            ForEach(store.asriSerifList) { item in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("\(item.number)) \(item.title)")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color(red: 0.24, green: 0.80, blue: 0.62))

                                    HStack {
                                        Button {
                                            store.playSingleAyahAudio(surahId: item.surahId, ayahNumber: item.startAyah)
                                        } label: {
                                            Image(systemName: "play.circle.fill")
                                                .font(.system(size: 28))
                                                .foregroundStyle(.white, Color(red: 0.98, green: 0.44, blue: 0.36))
                                        }

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("\(item.surahName)/\(item.surahId)  [ Toplam ayet: \(item.totalAyahs) ]")
                                                .font(.system(size: 15, weight: .bold))
                                                .foregroundColor(Color(red: 0.14, green: 0.60, blue: 0.44))
                                            Text("Okunacak ilk/son ayet(ler): \(item.startAyah) / \(item.endAyah)")
                                                .font(.caption.weight(.semibold))
                                                .foregroundColor(Color(red: 0.14, green: 0.60, blue: 0.44))
                                        }

                                        Spacer()

                                        Button("Ayetlere Git") {
                                            onJumpToSurahAyah(item.surahId, item.startAyah)
                                            dismiss()
                                        }
                                        .font(.caption.weight(.bold))
                                        .buttonStyle(.borderedProminent)
                                        .tint(Color(red: 0.18, green: 0.72, blue: 0.50))
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.bottom, 8)
                                }
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemBackground)))
                                .padding(.horizontal, 12)
                            }
                        }
                        .padding(.vertical, 10)
                    }

                case .ayahRange:
                    VStack(spacing: 16) {
                        let ch = store.currentChapter
                        Text("Aktif Sûre: \(ch?.turkishName ?? "Fâtiha") (\(ch?.verses_count ?? 7) Ayet)")
                            .font(.headline)

                        Stepper("Başlangıç Ayeti: \(customStartAyah)", value: $customStartAyah, in: 1...max(1, ch?.verses_count ?? 7))
                        Stepper("Bitiş Ayeti: \(customEndAyah)", value: $customEndAyah, in: customStartAyah...max(1, ch?.verses_count ?? 7))

                        Picker("Okuma Hızı", selection: $ikra.playbackSpeed) {
                            Text("0.75x Yavaş").tag(Float(0.75))
                            Text("1.0x Normal").tag(Float(1.0))
                            Text("1.25x Hızlı").tag(Float(1.25))
                            Text("1.50x Çok Hızlı").tag(Float(1.5))
                        }
                        .pickerStyle(.segmented)

                        Button {
                            store.playSingleAyahAudio(surahId: store.currentSurahId, ayahNumber: customStartAyah)
                        } label: {
                            Label("İkra Modunda Sesli Oku (Arapça + Türkçe Meal)", systemImage: "play.circle.fill")
                                .font(.subheadline.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 0.96, green: 0.44, blue: 0.36))

                        Button {
                            store.playSingleAyahTurkishMealStudio(surahId: store.currentSurahId, ayahNumber: customStartAyah)
                        } label: {
                            Label("Sadece Stüdyo Türkçe Mealini Dinle", systemImage: "person.wave.2.fill")
                                .font(.subheadline.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 0.14, green: 0.58, blue: 0.40))

                        Spacer()
                    }
                    .padding(20)
                }
            }
            .navigationTitle("İkra Ses, Sanatçı, İndir & Radyo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if player.isPlaying {
                        Button("Durdur", role: .destructive) {
                            player.stop()
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
    }
}

// MARK: - 6. Muhteşem Arama Ekranı (Arapça Klavye + Kök + Konu + Kelime Arama) (Screenshot 10)

struct KBSearchSheet: View {
    @ObservedObject var store: KuranBilmekStore
    let onJumpToVerse: (Int, Int) -> Void
    @Environment(\.dismiss) private var dismiss

    init(store: KuranBilmekStore, onJumpToVerse: @escaping (Int, Int) -> Void) {
        self.store = store
        self.onJumpToVerse = onJumpToVerse
        _query = State(initialValue: store.lastSearchQuery)
    }

    @State private var selectedSurah = 0
    @State private var query: String
    @State private var selectedFullAyah: KBFullAyah?
    @State private var showArabicKeyboard: Bool = false

    private let arabicLetters: [String] = [
        "ض", "ص", "ث", "ق", "ف", "غ", "ع", "ه", "خ", "ح", "ج",
        "ش", "س", "ي", "ب", "ل", "ا", "ت", "ن", "م", "ك", "ط",
        "ذ", "ء", "ؤ", "ر", "ى", "ة", "و", "ز", "ظ", "د"
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Mint Search Header matching Screenshot 10
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                        TextField("Meal, Arapça veya Bakara 255", text: $query)
                            .accessibilityIdentifier("ayahSearchField")
                            .foregroundStyle(.black)
                            .onSubmit {
                                store.rememberSearch(query)
                                Task { await store.performSearch(query: query, surahID: selectedSurah == 0 ? nil : selectedSurah) }
                            }
                        if !query.isEmpty {
                            Button {
                                query = ""
                            } label: {
                                Text("X")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.teal)
                            }
                        }
                        Button("Ara") {
                            store.rememberSearch(query)
                                Task { await store.performSearch(query: query, surahID: selectedSurah == 0 ? nil : selectedSurah) }
                        }
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.teal)
                    }
                    .padding(10)
                    .background(Capsule().fill(Color.white))

                    HStack(spacing: 14) {
                        Picker("Aranacak sure", selection: $selectedSurah) {
                            Text("Tüm sureler").tag(0)
                            ForEach(store.chapters) { chapter in
                                Text("\(chapter.id). \(chapter.turkishName)").tag(chapter.id)
                            }
                        }
                        .pickerStyle(.menu).tint(.black)
                        .accessibilityIdentifier("searchSurahFilter")
                        Toggle("Arapça Klavye", isOn: $showArabicKeyboard)
                            .toggleStyle(.button)
                            .font(.caption.weight(.bold))
                            .tint(.white)
                    }
                }
                .padding(12)
                .background(Color(red: 0.18, green: 0.78, blue: 0.56))

                // Results Count Bar
                HStack {
                    Text("Bulunan toplam ayet : \(store.searchTotalCount) adet")
                        .foregroundStyle(.black)
                        .font(.caption.weight(.bold))
                    Spacer()
                    if !store.searchResults.isEmpty {
                        ShareLink(item: "Kur'an Bilmek Arama Sonucu (\(query)): \(store.searchTotalCount) ayet bulundu.") {
                            Label("PAYLAŞ - Dışarı aktar", systemImage: "square.and.arrow.up")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color(red: 0.05, green: 0.30, blue: 0.22))
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(red: 0.84, green: 0.96, blue: 0.90))

                Text(store.searchStatus)
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 12).padding(.vertical, 6)

                if query.isEmpty && !store.recentSearches.isEmpty {
                    HStack {
                        Text("Son aramalar").font(.caption)
                        Spacer()
                        Button("Geçmişi temizle") { store.clearSearchHistory() }.font(.caption)
                    }.padding(.horizontal, 12)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(store.recentSearches, id: \.self) { recent in
                                Button(recent) { query = recent }
                                    .buttonStyle(.bordered)
                            }
                        }.padding(.horizontal, 12)
                    }
                }

                // Quick Suggestion Pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(["Fatiha 1", "2:255", "Ayetel Kürsi", "Yasin", "sabır", "rahmet", "الرَّحْمَٰنِ", "namaz", "dua"], id: \.self) { sample in
                            if sample != "अल्लाह" {
                                Button(sample) {
                                    query = sample
                                    store.rememberSearch(sample)

                                }
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color(.systemGray6)))
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }

                if store.isSearching && store.searchResults.isEmpty {
                    Spacer()
                    ProgressView("Kur'an-ı Kerim içinde aranıyor...")
                    Spacer()
                } else if store.searchResults.isEmpty {
                    ContentUnavailableView(query.isEmpty ? "Ayet ara" : "Sonuç bulunamadı", systemImage: "magnifyingglass", description: Text("Örnek: Fatiha 1, 2:255, sabır veya Arapça bir ifade."))
                } else {
                    List(Array(store.searchResults.enumerated()), id: \.element.id) { idx, item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("\(idx + 1)) \(item.surahName)/\(item.surahId) ")
                                    .font(.caption.weight(.bold)) +
                                Text("Ayet: \(item.ayahNumber) ")
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(.red) +
                                Text(item.pageNumber > 0 ? "Sayfa: \(item.pageNumber)" : "")
                                    .font(.caption.weight(.bold))
                                Spacer()
                                Button {
                                    store.rememberSearch(query)
                                    if let ayah = store.fullAyah(for: item.id) {
                                        selectedFullAyah = ayah
                                    } else {
                                        onJumpToVerse(item.surahId, item.ayahNumber)
                                        dismiss()
                                    }
                                } label: {
                                    HStack(spacing: 3) {
                                        Text("DETAY GÖSTER")
                                            .font(.system(size: 10, weight: .bold))
                                        Image(systemName: "chevron.right.circle.fill")
                                    }
                                    .foregroundColor(.teal)
                                }
                            }

                            Text(item.arabicText)
                                .font(.custom("AmiriQuran", size: 30))
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .trailing)

                            if let hw = item.highlightedWord, let hm = item.highlightedMeaning {
                                HStack {
                                    Text("Eşleşen Kelime:")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Text(hw)
                                        .font(.callout.weight(.bold))
                                        .foregroundColor(.red)
                                    Text("→ \(hm)")
                                        .font(.caption.weight(.semibold))
                                }
                            }

                            Text(item.turkishText)
                                .font(.body)
                                .foregroundColor(.primary)
                        }
                        .padding(.vertical, 4)
                    }
                    .listStyle(.plain)
                }

                // Built-in On-Screen Arabic Keyboard matching Screenshot 10
                if showArabicKeyboard {
                    VStack(spacing: 6) {
                        let cols = Array(repeating: GridItem(.flexible(), spacing: 4), count: 11)
                        LazyVGrid(columns: cols, spacing: 5) {
                            ForEach(arabicLetters, id: \.self) { letter in
                                Button {
                                    query.append(letter)

                                } label: {
                                    Text(letter)
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundColor(.black)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 34)
                                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.white))
                                        .shadow(color: .black.opacity(0.15), radius: 0.5, y: 1)
                                }
                            }

                            Button {
                                if !query.isEmpty {
                                    query.removeLast()
                                }
                            } label: {
                                Image(systemName: "delete.left.fill")
                                    .font(.system(size: 15))
                                    .foregroundColor(.red)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 34)
                                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.white))
                            }
                        }
                    }
                    .padding(8)
                    .background(Color(.systemGray4))
                }
            }
            .sheet(item: $selectedFullAyah) { ayah in
                KBFullAyahDetail(store: store, initialAyah: ayah) { sid, number in
                    selectedFullAyah = nil
                    onJumpToVerse(sid, number)
                    dismiss()
                }
            }
            .task(id: query + "|" + String(store.fullSearchCount) + "|" + String(selectedSurah)) {
                do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
                await store.performSearch(query: query, surahID: selectedSurah == 0 ? nil : selectedSurah)
            }
            .navigationTitle("Ayet Arama")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
    }
}

// MARK: - 7. Yardımcı Modallar (Kelime Listesi, Kök Concordance, Sayfa/Cüz, Konular, Notlar, Tefe'ül, Dualar)

struct KBVerseWordsTableSheet: View {
    @ObservedObject var store: KuranBilmekStore
    let verse: KBVerse
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("\(store.surahName(for: verse.surahId)) Sûresi, \(verse.verse_number). Ayet Kelimeleri") {
                    ForEach(verse.actualWords) { w in
                        HStack {
                            Button {
                                store.playWordAudio(w)
                            } label: {
                                Image(systemName: "play.circle.fill")
                                    .font(.title3)
                                    .foregroundColor(.orange)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(w.turkishMeaning)
                                    .font(.subheadline.weight(.bold))
                                Text("Okunuş: \(w.turkishTransliteration) · Kök: \(w.arabicRootLetters)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(w.arabicDisplay)
                                .font(.system(size: 24, design: .serif))
                        }
                    }
                }
            }
            .navigationTitle("Ayetin Kelime Meali")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    let shareBody = verse.actualWords.map { "\($0.arabicDisplay) (\($0.turkishTransliteration)): \($0.turkishMeaning)" }.joined(separator: "\n")
                    ShareLink(item: shareBody) {
                        Label("Paylaş", systemImage: "square.and.arrow.up")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
    }
}

struct KBWordConcordanceSheet: View {
    @ObservedObject var store: KuranBilmekStore
    let word: KBWord
    let onSelectVerse: (Int, Int) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let matches = store.findLocalOccurrences(of: word)
        NavigationStack {
            List {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Aranan Kelime: \(word.turkishMeaning)")
                                .font(.headline)
                            Text("Sülâsi Kök: \(word.arabicRootLetters)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(word.arabicDisplay)
                            .font(.system(size: 30, design: .serif))
                    }
                }

                Section("Kur'an'da Geçtiği Ayetler (\(matches.count) kayıt)") {
                    ForEach(Array(matches.enumerated()), id: \.offset) { _, m in
                        Button {
                            onSelectVerse(m.verse.surahId, m.verse.verse_number)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(m.surahName) Sûresi, \(m.verse.verse_number). Ayet (Sayfa \(m.verse.page_number ?? 1))")
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(.teal)
                                Text(m.verse.fullArabicText)
                                    .font(.system(size: 20, design: .serif))
                                    .foregroundColor(.primary)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                Text(m.verse.translationText(for: 77) ?? "")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Kelime & Kök Rehberi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
    }
}

struct KBPageJuzPickerSheet: View {
    @ObservedObject var store: KuranBilmekStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPage: Int = 1
    @State private var selectedJuz: Int = 1

    var body: some View {
        NavigationStack {
            Form {
                Section("Mushaf Sayfasına Git (1 - 604)") {
                    Stepper("Sayfa: \(selectedPage)", value: $selectedPage, in: 1...604)
                    Button("Sayfa \(selectedPage) Aç") {
                        Task {
                            await store.loadByPage(selectedPage)
                            dismiss()
                        }
                    }
                    .font(.headline)
                }

                Section("Cüz'e Git (1 - 30)") {
                    Picker("Cüz Seçin", selection: $selectedJuz) {
                        ForEach(1...30, id: \.self) { j in
                            Text("\(j). Cüz").tag(j)
                        }
                    }
                    Button("\(selectedJuz). Cüz'ü Aç") {
                        Task {
                            await store.loadByJuz(selectedJuz)
                            dismiss()
                        }
                    }
                    .font(.headline)
                }
            }
            .navigationTitle("Sayfa, Cüz - Hizb Aç")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
    }
}

struct KBTopicsSheet: View {
    @ObservedObject var store: KuranBilmekStore
    let onSelectTopicQuery: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(store.topics) { topic in
                Button {
                    onSelectTopicQuery(topic.query)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: topic.icon)
                            .font(.title3)
                            .foregroundColor(.teal)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(topic.title)
                                .font(.headline)
                                .foregroundColor(.primary)
                            Text(topic.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Kur'an Konu Fihristi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
    }
}

struct KBSavedListSheet: View {
    let title: String
    let items: [KBBookmark]
    let onSelect: (KBBookmark) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    ContentUnavailableView("Henüz Kayıt Yok", systemImage: "bookmark.slash", description: Text("Ayetlerin yanındaki Hızlı Ulaşım menüsünden veya kelime kartından kayıt ekleyebilirsiniz."))
                } else {
                    List(items) { item in
                        Button {
                            onSelect(item)
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("\(item.surahName) Sûresi, \(item.ayahNumber). Ayet")
                                        .font(.headline)
                                    Text("Sayfa: \(item.pageNumber)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.right.circle.fill")
                                    .foregroundColor(.teal)
                            }
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
    }
}

struct KBNotesListSheet: View {
    @ObservedObject var store: KuranBilmekStore
    let onJumpToNote: (KBVerseNote) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if store.notes.isEmpty {
                    ContentUnavailableView("Kayıtlı Not Yok", systemImage: "note.text", description: Text("Herhangi bir ayetin Hızlı Ulaşım menüsünden ayete özel not alabilirsiniz."))
                } else {
                    List(store.notes) { note in
                        Button {
                            onJumpToNote(note)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(note.surahName) Sûresi, \(note.ayahNumber). Ayet")
                                    .font(.headline)
                                Text(note.noteText)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Kayıtlı Ayet Notlarım")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
    }
}

struct KBNoteEditorSheet: View {
    @ObservedObject var store: KuranBilmekStore
    let verse: KBVerse
    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("\(store.surahName(for: verse.surahId)) Sûresi, \(verse.verse_number). Ayet Notu") {
                    TextEditor(text: $text)
                        .frame(minHeight: 150)
                }
            }
            .navigationTitle("Not Kaydet / Düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Kaydet") {
                        store.saveNote(surahId: verse.surahId, ayahNumber: verse.verse_number, text: text)
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
            .onAppear {
                text = store.noteText(for: verse.surahId, ayahNumber: verse.verse_number)
            }
        }
    }
}

struct KBSurahInfoSheet: View {
    let chapter: KBChapter?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let ch = chapter {
                        Text("\(ch.id). \(ch.turkishName) Sûresi (\(ch.name_arabic))")
                            .font(.title2.weight(.bold))
                        Text("• İndiği Yer: \(ch.revelationPlaceTurkish) (\(ch.revelation_place.capitalized))\n• Nüzul (Vahiy) Sırası: \(ch.revelation_order)\n• Toplam Ayet Sayısı: \(ch.verses_count)\n• Mushaf Sayfa Aralığı: \(ch.pages.first ?? 1) - \(ch.pages.last ?? 1)")
                            .font(.subheadline)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))

                        Text("Sûre Hakkında Bilgi")
                            .font(.headline)
                        Text("\(ch.turkishName) Sûresi, Kur'an-ı Kerim'in \(ch.id). sûresidir ve \(ch.revelationPlaceTurkish) döneminde nazil olmuştur. Toplam \(ch.verses_count) ayetten oluşur. Kelime meali görünümünde her kelimenin üzerine dokunarak o kelimenin Türkçe anlamını, Latin okunuşunu, varsa sözlük kökünü ve sesli telaffuzunu dinleyebilirsiniz.")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(16)
            }
            .navigationTitle("Sûre Hakkında Kısa Bilgi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
    }
}

struct KBTefeulSheet: View {
    @ObservedObject var store: KuranBilmekStore
    let verse: KBVerse
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text("Tefe'ül Ayet-i Kerimesi")
                        .font(.headline)
                        .foregroundColor(.teal)
                    Text("\(store.surahName(for: verse.surahId)) Sûresi, \(verse.verse_number). Ayet")
                        .font(.title3.weight(.bold))

                    Text(verse.fullArabicText)
                        .font(.system(size: 28, design: .serif))
                        .multilineTextAlignment(.center)
                        .padding()

                    Text(verse.translationText(for: 77) ?? "")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Button {
                        store.playSingleAyahAudio(surahId: verse.surahId, ayahNumber: verse.verse_number)
                    } label: {
                        Label("Ayeti Sesli Dinle", systemImage: "play.circle.fill")
                            .font(.headline)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.teal)
                }
                .padding(20)
            }
            .navigationTitle("Tefe'ül")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
    }
}

struct KBDuaSpecialSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Hatim Duası") {
                    Text("Elhamdülillâhi Rabbi'l-âlemîn. Vessalâtü vesselâmü alâ Rasûlinâ Muhammedin ve alâ âlihî ve sahbihî ecmaîn. Allah'ım! Okunan Kur'an-ı Kerim'i, yapılan hatm-i şerifi dergâh-ı izzetinde kabul eyle. Hasıl olan sevabı başta Peygamber Efendimiz Hz. Muhammed Mustafa (s.a.v.) olmak üzere tüm peygamberlerin, sahabe-i kiramın ve geçmişlerimizin ruhlarına hediye eyledik, vasıl eyle Ya Rabbi!")
                        .font(.subheadline)
                }
                Section("Kur'an'dan Rabbenâ Dua Ayetleri") {
                    Text("• Rabbenâ âtinâ fi'd-dünyâ haseneten ve fi'l-âhirati haseneten ve kınâ azâbe'n-nâr. (Bakara, 201)\n• Rabbenâ lâ tüziğ kulûbenâ ba'de iz hedeytenâ ve heb lenâ min ledünke rahmeh. (Âl-i İmrân, 8)\n• Rabbenâğfirlî ve li-vâlideyye ve li'l-mü'minîne yevme yekûmu'l-hisâb. (İbrâhîm, 41)")
                        .font(.subheadline)
                }
                Section("Sekine Duası") {
                    Text("Allâhümme innî es'elüke bi-esmâike'l-hüsnâ ve sıfâtike'l-ulyâ en tünzile's-sekînete fî kulûbinâ. Ferdün, Hayyün, Kayyûmun, Hakemün, Adlün, Kuddûsün...")
                        .font(.subheadline)
                }
            }
            .navigationTitle("Hatim, Kur'an & Sekine Duaları")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
    }
}


struct KBFullAyahDetail: View {
    @ObservedObject var store: KuranBilmekStore
    @State private var ayah: KBFullAyah
    let onOpenWordReader: (Int, Int) -> Void
    @Environment(\.dismiss) private var dismiss
    init(store: KuranBilmekStore, initialAyah: KBFullAyah, onOpenWordReader: @escaping (Int, Int) -> Void) {
        self.store = store
        _ayah = State(initialValue: initialAyah)
        self.onOpenWordReader = onOpenWordReader
    }
    private var shareText: String {
        "\(store.surahName(for: ayah.surah)) \(ayah.id)\n\(ayah.arabic_text)\n\(ayah.translation)\n\(ayah.footnotes)\n\(store.fullSearchSource)"
    }
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        Text("\(store.surahName(for: ayah.surah)) · \(ayah.id)")
                            .font(.title2).id("top").accessibilityIdentifier("fullAyahReference")
                        Text(ayah.arabic_text).font(.custom("AmiriQuran", size: 34))
                            .lineSpacing(14).frame(maxWidth: .infinity, alignment: .trailing)
                            .textSelection(.enabled)
                        Text(ayah.translation).font(.title3).lineSpacing(8).textSelection(.enabled)
                        if !ayah.footnotes.isEmpty {
                            Divider()
                            Text("Mealin dipnotları").font(.headline)
                            Text(ayah.footnotes).font(.body).lineSpacing(5).textSelection(.enabled)
                        }
                        Text(store.fullSearchSource).font(.caption).foregroundStyle(.secondary)
                        Link("Kaynağında aç", destination: URL(string: "https://quranenc.com/tr/browse/turkish_rwwad/\(ayah.surah)/\(ayah.number)")!)
                        if store.hasWordVerse(ayah) {
                            Button("Kelime okuyucusunda aç") { onOpenWordReader(ayah.surah, ayah.number) }
                                .buttonStyle(.bordered)
                            Text("Kelime okuyucusu mevcut Diyanet mealini gösterir.").font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(22)
                }
                .onChange(of: ayah.id) { _ in proxy.scrollTo("top", anchor: .top) }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button { move(-1) } label: { Label("Önceki ayet", systemImage: "chevron.left") }
                        .disabled(store.adjacentFullAyah(ayah, offset: -1) == nil)
                    Spacer()
                    Button { move(1) } label: { Label("Sonraki ayet", systemImage: "chevron.right") }
                        .disabled(store.adjacentFullAyah(ayah, offset: 1) == nil)
                }.padding().background(.regularMaterial)
            }
            .navigationTitle("Ayet Ayrıntısı").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { ShareLink(item: shareText) }
                ToolbarItem(placement: .topBarTrailing) { Button("Kapat") { dismiss() } }
            }
        }
    }
    private func move(_ offset: Int) {
        if let next = store.adjacentFullAyah(ayah, offset: offset) { ayah = next }
    }
}
