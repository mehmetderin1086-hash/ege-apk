import SwiftUI

struct SurahMeta: Identifiable, Hashable {
    let number: Int
    let nameTr: String
    let nameAr: String
    let ayahCount: Int
    let revelationPlace: String
    var id: Int { number }
}

struct AyahItem: Identifiable, Hashable {
    let numberInSurah: Int
    let globalNumber: Int
    let arabicText: String
    let turkishText: String
    var id: Int { globalNumber }
}

/// Ezan Vakti Pro Kütüphane, 114 Sure Kur'an-ı Kerim (Sesli Tilavet + Diyanet Meal) ve Hatim Paylaşımı Modülü.
struct QuranAndLibraryView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var adhan: AdhanPlayer

    @State private var selectedSection: Int = 1
    @State private var searchText: String = ""
    @AppStorage("hatim.completedJuzs") private var completedJuzsRaw: String = ""

    private var completedJuzSet: Set<Int> {
        Set(completedJuzsRaw.split(separator: ",").compactMap { Int($0) })
    }

    private func toggleJuz(_ juz: Int) {
        var current = completedJuzSet
        if current.contains(juz) { current.remove(juz) } else { current.insert(juz) }
        completedJuzsRaw = current.sorted().map(String.init).joined(separator: ",")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.background.ignoresSafeArea()

                VStack(spacing: 8) {
                    if selectedSection != 0 {
                    EzanPageHeader(eyebrow: "Oku · Dinle · Anla", title: "Kur’an-ı Kerim", subtitle: "Arapça metin ve Diyanet meali bir arada.")
                        .padding(.horizontal, 20).padding(.top, 16)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach([(0, "Kelime"), (6, "Elif Bâ"), (1, "Kütüphane"), (2, "Sûreler"), (5, "Tilavet"), (4, "Mealler"), (3, "Hatim")], id: \.0) { item in
                                Button { selectedSection = item.0 } label: {
                                    Text(item.1).font(.body.weight(.medium)).padding(.horizontal, 17).frame(minHeight: 44)
                                        .background(selectedSection == item.0 ? Palette.accent : Palette.card, in: Capsule())
                                        .foregroundStyle(selectedSection == item.0 ? Palette.onAccent : Palette.textSecondary)
                                }
                            }
                        }.padding(.horizontal, 16)
                    }.padding(.vertical, 8)

                    if selectedSection == 0 {
                        KuranBilmekView()
                    } else if selectedSection == 6 {
                        ElifBaView()
                    } else if selectedSection == 1 {
                        libraryShelfView
                    } else if selectedSection == 2 {
                        surahListView
                    } else if selectedSection == 5 {
                        QuranRecitersView()
                    } else if selectedSection == 4 {
                        OfficialMealsView()
                    } else {
                        khatmSharingView
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationTitle("Kur'an & Kütüphane")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - 1. Kütüphane Rafı (Ezan Vakti Pro s4.png Birebir)
    private var libraryShelfView: some View {
        ScrollView {
            VStack(spacing: 18) {
                NavigationLink { ElifBaView() } label: {
                    HStack(spacing: 16) {
                        Text("ا ب").font(.custom("Amiri-Regular", size: 44)).foregroundStyle(Palette.gold)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Kur’an Öğreniyorum · Elif Bâ").font(.headline)
                            Text("28 harf · 12 ders · sesli alıştırmalar").font(.subheadline).foregroundStyle(Palette.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                    }.padding(20).sekineCard(active: true)
                }.buttonStyle(.plain)

                // 7/24 Kur'an Radyosu & Diyanet Radyo + Ünlü Türkçe Meal Sanatçıları Merkezi
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Diyanet ve Vav · Canlı Radyo", systemImage: "antenna.radiowaves.left.and.right")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.yellow)
                        Spacer()
                        if adhan.isPlaying {
                            Button("Durdur") {
                                adhan.stop()
                            }
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.red)
                        }
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(IkraAudioAndRadioCenter.shared.liveRadioStations) { st in
                                Button {
                                    IkraAudioAndRadioCenter.shared.playLiveRadio(st)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Image(systemName: st.icon)
                                                .foregroundStyle(.yellow)
                                            Text(st.category)
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.white.opacity(0.8))
                                        }
                                        Text(st.title)
                                            .font(.headline)
                                            .foregroundStyle(.white)
                                            .lineLimit(2)
                                        Text(st.subtitle)
                                            .font(.subheadline)
                                            .foregroundStyle(.white.opacity(0.75))
                                            .lineLimit(2)
                                    }
                                    .padding(10)
                                    .frame(width: 255, alignment: .leading)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.12)))
                                }
                            }
                        }
                    }
                }
                .padding(16)
                .background(
                    LinearGradient(
                        colors: [Color(red: 0.06, green: 0.28, blue: 0.24), Color(red: 0.04, green: 0.16, blue: 0.14)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                // Ana Mushaf Kartı (Ezan Vakti Pro s4.png üst bölüm)
                HStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 0.29, green: 0.25, blue: 0.14), Color(red: 0.16, green: 0.14, blue: 0.08)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 115, height: 155)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(Palette.gold, lineWidth: 2)
                            )
                        VStack(spacing: 8) {
                            Text("القرآن الكريم")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(Palette.gold)
                            Image(systemName: "book.closed.circle.fill")
                                .font(.system(size: 38))
                                .foregroundStyle(Palette.gold)
                            Text("Kur'an-ı Kerim")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Okumaya başlayın")
                            .font(.caption)
                            .foregroundStyle(Palette.textSecondary)
                        Text("Fâtiha Sûresi · 1. Cüz")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(Palette.textPrimary)

                        NavigationLink {
                            SurahReaderView(surah: Self.popularSurahs[0])
                        } label: {
                            Label("Fâtiha’yı oku", systemImage: "book.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Palette.accent)
                        }

                        Button {
                            selectedSection = 2
                        } label: {
                            Label("Tüm Sureler (114)", systemImage: "list.bullet.rectangle")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Palette.textPrimary)
                        }

                        Button {
                            selectedSection = 3
                        } label: {
                            Label("Cüzler & Hatim (\(completedJuzSet.count)/30)", systemImage: "bookmark.fill")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Palette.gold)
                        }
                    }
                    Spacer()
                }
                .padding(16)
                .sekineCard()

                // Popüler Sureler & E-Kitaplar 3'lü Grid (Ezan Vakti Pro s4.png alt bölüm)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Popüler Sureler & İslami Eserler")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Palette.textPrimary)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        ForEach(Self.featuredBooks) { book in
                            NavigationLink {
                                if let surah = book.linkedSurah {
                                    SurahReaderView(surah: surah)
                                } else {
                                    SpecialBookReaderView(book: book)
                                }
                            } label: {
                                VStack(spacing: 8) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(
                                                LinearGradient(
                                                    colors: book.colors,
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .frame(height: 125)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 14)
                                                    .strokeBorder(Color.white.opacity(0.28), lineWidth: 1.5)
                                            )

                                        VStack(spacing: 6) {
                                            Text(book.arabicBadge)
                                                .font(.system(size: 18, weight: .bold))
                                                .foregroundStyle(.yellow)
                                            Image(systemName: book.icon)
                                                .font(.system(size: 28))
                                                .foregroundStyle(.white)
                                        }
                                    }
                                    Text(book.title)
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(Palette.textPrimary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - 2. 114 Sure Tam Liste ve Arama
    private var surahListView: some View {
        let filtered = Self.allSurahs.filter {
            searchText.isEmpty ||
            $0.nameTr.localizedCaseInsensitiveContains(searchText) ||
            String($0.number).contains(searchText)
        }
        return VStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Palette.textSecondary)
                TextField("Sure adı veya numarası ara (ör. Yasin, 36)...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(12)
            .background(Palette.card)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 16)

            List(filtered) { surah in
                NavigationLink {
                    SurahReaderView(surah: surah)
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Palette.accent.opacity(0.15))
                                .frame(width: 38, height: 38)
                            Text("\(surah.number)")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Palette.accent)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(surah.nameTr)
                                .font(.headline)
                                .foregroundStyle(Palette.textPrimary)
                            Text("\(surah.revelationPlace) · \(surah.ayahCount) Ayet")
                                .font(.caption)
                                .foregroundStyle(Palette.textSecondary)
                        }
                        Spacer()
                        Text(surah.nameAr)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Palette.gold)
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.plain)
        }
    }

    // MARK: - 3. Hatim Paylaşımı & Dua Kardeşliği (Ezan Vakti Pro s8.png Birebir)
    private var khatmSharingView: some View {
        ScrollView {
            VStack(spacing: 18) {
                // Kişisel 30 Cüz Hatim İlerlemesi
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Kişisel Kur'an-ı Kerim Hatmim")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(Palette.textPrimary)
                            Text("Okuduğunuz cüzlere dokunarak işaretleyin")
                                .font(.caption)
                                .foregroundStyle(Palette.textSecondary)
                        }
                        Spacer()
                        Text("\(completedJuzSet.count) / 30 Cüz")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Palette.accent)
                    }

                    ProgressView(value: Double(completedJuzSet.count), total: 30)
                        .tint(Palette.accent)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                        ForEach(1...30, id: \.self) { juz in
                            let done = completedJuzSet.contains(juz)
                            Button {
                                toggleJuz(juz)
                            } label: {
                                VStack(spacing: 2) {
                                    Text("\(juz).")
                                        .font(.subheadline.weight(.bold))
                                    Text("Cüz")
                                        .font(.caption2)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(done ? Palette.accent : Palette.background)
                                .foregroundStyle(done ? Color.white : Palette.textPrimary)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(done ? Color.clear : Palette.separator, lineWidth: 1)
                                )
                            }
                        }
                    }
                }
                .padding(16)
                .sekineCard()

                // Online Hatim Kardeşliği (Ezan Vakti Pro s8.png)
                Text("Hatim ilerlemeniz bu cihazda saklanır. Tamamladığınız cüzlere tekrar dokunarak işareti kaldırabilirsiniz.")
                    .font(.caption).foregroundStyle(Palette.textSecondary).padding(.horizontal, 4)

            }
            .padding(16)
        }
    }
}

struct QuranRecitersView: View {
    @ObservedObject private var audio = IkraAudioAndRadioCenter.shared
    @ObservedObject private var player = AdhanPlayer.shared
    @State private var search = ""
    @State private var surahID = 1
    private var selectedSurah: SurahMeta? { QuranAndLibraryView.allSurahs.first { $0.number == surahID } }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Kur’an tilaveti", systemImage: "waveform").font(.title2.bold())
                    Text(audio.currentArabicReciter.name).font(.title3.weight(.medium))
                    Picker("Dinlenecek sûre", selection: $surahID) {
                        ForEach(QuranAndLibraryView.allSurahs) { surah in
                            Text("\(surah.number). \(surah.nameTr)").tag(surah.number)
                        }
                    }.tint(.white).accessibilityLabel("Dinlenecek sûre")
                    HStack {
                        Button {
                            if let surah = selectedSurah { audio.playArabicSurah(surah) }
                        } label: { Label("Sûreyi dinle", systemImage: "play.fill").font(.body.weight(.semibold)) }
                            .buttonStyle(.borderedProminent).tint(Palette.gold)
                        if player.isPlaying {
                            Button("Durdur", systemImage: "stop.fill") { player.stop() }.buttonStyle(.bordered)
                        }
                    }
                    Text("Türk ve dünya hafızları · \(audio.famousArabicReciters.count) okuyucu")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.85))
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.white).background(Palette.accent, in: RoundedRectangle(cornerRadius: 24))

                HStack {
                    Image(systemName: "magnifyingglass")
                    TextField("Hafız adı veya ülke ara", text: $search)
                }.padding(15).background(Palette.card, in: RoundedRectangle(cornerRadius: 18))

                ForEach([true, false], id: \.self) { turkish in
                    let reciters = audio.famousArabicReciters.filter {
                        $0.isTurkish == turkish && (search.isEmpty || "\($0.name) \($0.countryAndTitle)".localizedStandardContains(search))
                    }
                    if !reciters.isEmpty {
                        Text(turkish ? "Türkiye’den hafızlar" : "Dünya hafızları")
                            .font(.title3.weight(.semibold)).foregroundStyle(Palette.textPrimary)
                        ForEach(reciters) { reciter in
                            HStack(spacing: 14) {
                                Button {
                                    audio.selectedArabicReciterId = reciter.id
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: audio.selectedArabicReciterId == reciter.id ? "checkmark.circle.fill" : "person.wave.2")
                                            .font(.title2).foregroundStyle(Palette.accent)
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(reciter.name).font(.body.weight(.medium)).foregroundStyle(Palette.textPrimary)
                                            Text(reciter.countryAndTitle).font(.subheadline).foregroundStyle(Palette.textSecondary)
                                        }
                                        Spacer(minLength: 0)
                                    }.contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                Button {
                                    audio.selectedArabicReciterId = reciter.id
                                    audio.playArabicAyah(surahId: 1, ayah: 1, title: "Fâtiha · 1. ayet")
                                } label: {
                                    Image(systemName: "play.circle.fill").font(.system(size: 34)).foregroundStyle(Palette.accent)
                                }.accessibilityLabel("\(reciter.name), Fâtiha örneğini dinle")
                            }.padding(16).background(Palette.card, in: RoundedRectangle(cornerRadius: 18))
                        }
                    }
                }
                Text("Seçtiğiniz hafız, sûre okuyucusundaki Arapça Tilavet düğmesinde de kullanılır. Tilavet için internet bağlantısı gerekir.")
                    .font(.footnote).foregroundStyle(Palette.textSecondary)
            }.padding(16)
        }
    }
}

// MARK: - Sure Okuyucu & Sesli Tilavet (Ezan Vakti Pro s3.png Birebir)
struct SurahReaderView: View {
    @ObservedObject private var readingSettings = KuranBilmekStore.shared
    let surah: SurahMeta
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var adhan: AdhanPlayer

    @State private var ayahs: [AyahItem] = []
    @State private var isLoading = true
    @State private var activeAyahGlobalNumber: Int?

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        // Klasik Mushaf Başlık Süslemesi (s3.png)
                        VStack(spacing: 6) {
                            Text(surah.nameAr)
                                .font(readingSettings.arabicFontStyle.font(size: 36))
                                .foregroundStyle(Palette.gold)
                            Text("\(surah.nameTr) Sûresi · \(surah.revelationPlace) · \(surah.ayahCount) Ayet")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Palette.textSecondary)
                            if surah.number != 9 {
                                Text("بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ")
                                    .font(readingSettings.arabicFontStyle.font(size: 28))
                                    .foregroundStyle(Palette.textPrimary)
                                    .padding(.top, 4)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(18)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Palette.card)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .strokeBorder(Palette.gold, lineWidth: 2)
                                )
                        )

                        if isLoading {
                            ProgressView("Ayetler ve Diyanet Meali yükleniyor…")
                                .padding(.top, 40)
                        } else if ayahs.isEmpty {
                            ContentUnavailableView("Ayetler yüklenemedi", systemImage: "wifi.slash",
                                description: Text("Bu sûre henüz çevrimdışı kayıtlı değil. İnternet bağlantısıyla tekrar deneyin."))
                            Button("Tekrar dene") { Task { await loadSurah() } }
                        } else {
                            ForEach(ayahs) { ayah in
                                let isActive = activeAyahGlobalNumber == ayah.globalNumber && adhan.isPlaying
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        ZStack {
                                            Circle()
                                                .fill(isActive ? Color.orange : Palette.gold.opacity(0.2))
                                                .frame(width: 32, height: 32)
                                            Text("\(ayah.numberInSurah)")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(isActive ? .white : Palette.gold)
                                        }

                                        Spacer()

                                        Button {
                                            activeAyahGlobalNumber = ayah.globalNumber
                                            IkraAudioAndRadioCenter.shared.playArabicAyah(
                                                surahId: surah.number, ayah: ayah.numberInSurah,
                                                title: "\(surah.nameTr) Sûresi · \(ayah.numberInSurah). Ayet")
                                        } label: {
                                            Label("Arapça Tilavet", systemImage: "play.circle.fill")
                                                .font(.caption.weight(.bold))
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 5)
                                                .background(Palette.accent.opacity(0.15))
                                                .foregroundStyle(Palette.accent)
                                                .clipShape(Capsule())
                                        }

                                        Button {
                                            activeAyahGlobalNumber = ayah.globalNumber
                                            adhan.speakTurkish(
                                                text: "\(surah.nameTr) Suresi \(ayah.numberInSurah). Ayet meali: \(ayah.turkishText)",
                                                title: "\(surah.nameTr) · \(ayah.numberInSurah). Ayet Meali"
                                            )
                                        } label: {
                                            Label("Sesli Meal", systemImage: "speaker.wave.2.fill")
                                                .font(.caption.weight(.bold))
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 5)
                                                .background(Palette.gold.opacity(0.18))
                                                .foregroundStyle(Palette.gold)
                                                .clipShape(Capsule())
                                        }
                                    }

                                    Text(ayah.arabicText)
                                        .font(readingSettings.arabicFontStyle.font(size: 30 * settings.fontScale.multiplier))
                                        .lineSpacing(10)
                                        .environment(\.layoutDirection, .rightToLeft)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .foregroundStyle(Palette.textPrimary)
                                        .multilineTextAlignment(.trailing)
                                        .frame(maxWidth: .infinity, alignment: .trailing)

                                    Text(ayah.turkishText)
                                        .font(readingSettings.turkishFontStyle.font(size: 20 * settings.fontScale.multiplier))
                                        .lineSpacing(7)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .foregroundStyle(Palette.textPrimary)
                                }
                                .padding(16)
                                .sekineCard(active: isActive)
                                .id(ayah.globalNumber)
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle("\(surah.nameTr) Sûresi")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadSurah()
        }
    }

    private func loadSurah() async {
        let local = QuranAndLibraryView.offlineFallbackAyahs(for: surah.number)
        if !local.isEmpty { ayahs = local }
        isLoading = ayahs.isEmpty
        defer { isLoading = false }

        // Önce canlı Diyanet Meali + Uthmani Arapça API'den çekmeyi dene
        let urlStr = "https://api.alquran.cloud/v1/surah/\(surah.number)/editions/quran-uthmani,tr.diyanet"
        if let url = URL(string: urlStr),
           let (data, _) = try? await URLSession.shared.data(from: url),
           let decoded = try? JSONDecoder().decode(AlQuranDualEditionResponse.self, from: data),
           decoded.data.count >= 2 {
            let arList = decoded.data[0].ayahs
            let trList = decoded.data[1].ayahs
            var combined: [AyahItem] = []
            for i in 0..<min(arList.count, trList.count) {
                combined.append(
                    AyahItem(
                        numberInSurah: arList[i].numberInSurah,
                        globalNumber: arList[i].number,
                        arabicText: arList[i].text,
                        turkishText: trList[i].text
                    )
                )
            }
            if !combined.isEmpty {
                self.ayahs = combined
                return
            }
        }

        // Çevrimdışı yedek
        self.ayahs = QuranAndLibraryView.offlineFallbackAyahs(for: surah.number)
    }
}

private struct AlQuranDualEditionResponse: Decodable {
    struct EditionData: Decodable {
        struct AyahDTO: Decodable {
            let number: Int
            let text: String
            let numberInSurah: Int
        }
        let ayahs: [AyahDTO]
    }
    let data: [EditionData]
}

// MARK: - Özel İslami Kitap Okuyucu (Cevşen, Veda Hutbesi, 40 Hadis)
struct FeaturedBookItem: Identifiable {
    let id: String
    let title: String
    let arabicBadge: String
    let icon: String
    let colors: [Color]
    let linkedSurah: SurahMeta?
    let contentSections: [(heading: String, arabic: String, turkish: String)]
}

struct SpecialBookReaderView: View {
    let book: FeaturedBookItem
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var adhan: AdhanPlayer

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(Array(book.contentSections.enumerated()), id: \.offset) { _, sec in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(sec.heading)
                                .font(.headline.weight(.bold))
                                .foregroundStyle(Palette.accent)
                            Spacer()
                            Button {
                                adhan.speakTurkish(text: "\(sec.heading). \(sec.turkish)", title: sec.heading)
                            } label: {
                                Label("Sesli Dinle", systemImage: "speaker.wave.2.fill")
                                    .font(.caption.weight(.bold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Palette.accent.opacity(0.15))
                                    .foregroundStyle(Palette.accent)
                                    .clipShape(Capsule())
                            }
                        }
                        if !sec.arabic.isEmpty {
                            Text(sec.arabic)
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(Palette.gold)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        Text(sec.turkish)
                            .font(SekineFont.row(settings.fontScale))
                            .foregroundStyle(Palette.textPrimary)
                    }
                    .padding(16)
                    .sekineCard()
                }
            }
            .padding(16)
        }
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension QuranAndLibraryView {
    struct CommunityKhatmItem {
        let id: String
        let title: String
        let participants: Int
        let readPercent: Int
        let sharedPercent: Int
    }

    static let communityKhatms: [CommunityKhatmItem] = [
        .init(id: "k1", title: "32853. Hatim · Ümmet Dua Kardeşliği", participants: 69, readPercent: 68, sharedPercent: 90),
        .init(id: "k2", title: "32859. Hatim · Şifa ve Huzur Hatmi", participants: 54, readPercent: 51, sharedPercent: 71),
        .init(id: "k3", title: "32862. Hatim · Geçmişlerimizin Ruhu İçin", participants: 52, readPercent: 77, sharedPercent: 85),
        .init(id: "k4", title: "32905. Hatim · Cuma Bereketi Hatmi", participants: 61, readPercent: 82, sharedPercent: 94)
    ]

    static let popularSurahs: [SurahMeta] = [
        SurahMeta(number: 1, nameTr: "Fâtiha", nameAr: "الفاتحة", ayahCount: 7, revelationPlace: "Mekke"),
        SurahMeta(number: 36, nameTr: "Yâsîn", nameAr: "يس", ayahCount: 83, revelationPlace: "Mekke"),
        SurahMeta(number: 67, nameTr: "Mülk (Tebâreke)", nameAr: "الملك", ayahCount: 30, revelationPlace: "Mekke"),
        SurahMeta(number: 48, nameTr: "Fetih", nameAr: "الفتح", ayahCount: 29, revelationPlace: "Medine"),
        SurahMeta(number: 56, nameTr: "Vâkıa", nameAr: "الواقعة", ayahCount: 96, revelationPlace: "Mekke"),
        SurahMeta(number: 78, nameTr: "Nebê (Amme)", nameAr: "النبأ", ayahCount: 40, revelationPlace: "Mekke"),
        SurahMeta(number: 18, nameTr: "Kehf", nameAr: "الكهف", ayahCount: 110, revelationPlace: "Mekke"),
        SurahMeta(number: 62, nameTr: "Cum'a", nameAr: "الجمعة", ayahCount: 11, revelationPlace: "Medine"),
        SurahMeta(number: 55, nameTr: "Rahmân", nameAr: "الرحمن", ayahCount: 78, revelationPlace: "Medine")
    ]

    static let featuredBooks: [FeaturedBookItem] = [
        FeaturedBookItem(
            id: "yasin", title: "Yâsîn-i Şerîf", arabicBadge: "يس", icon: "book.pages.fill",
            colors: [Color(red: 0.14, green: 0.52, blue: 0.58), Color(red: 0.08, green: 0.28, blue: 0.34)],
            linkedSurah: popularSurahs[1], contentSections: []
        ),
        FeaturedBookItem(
            id: "mulk", title: "Mülk (Tebâreke)", arabicBadge: "الملك", icon: "moon.stars.fill",
            colors: [Color(red: 0.58, green: 0.14, blue: 0.18), Color(red: 0.34, green: 0.06, blue: 0.10)],
            linkedSurah: popularSurahs[2], contentSections: []
        ),
        FeaturedBookItem(
            id: "fetih", title: "Fetih Sûresi", arabicBadge: "الفتح", icon: "sparkles",
            colors: [Color(red: 0.12, green: 0.44, blue: 0.26), Color(red: 0.05, green: 0.22, blue: 0.14)],
            linkedSurah: popularSurahs[3], contentSections: []
        ),
        FeaturedBookItem(
            id: "vakia", title: "Vâkıa Sûresi", arabicBadge: "الواقعة", icon: "sun.max.fill",
            colors: [Color(red: 0.62, green: 0.42, blue: 0.12), Color(red: 0.36, green: 0.22, blue: 0.06)],
            linkedSurah: popularSurahs[4], contentSections: []
        ),
        FeaturedBookItem(
            id: "cevsen", title: "Cevşenü'l-Kebîr", arabicBadge: "الجوشن الكبير", icon: "shield.lefthalf.filled",
            colors: [Color(red: 0.38, green: 0.14, blue: 0.12), Color(red: 0.20, green: 0.06, blue: 0.05)],
            linkedSurah: nil,
            contentSections: [
                ("1. Bâb · Allah'ın Güzel İsimleriyle Münâcât",
                 "سُبْحَانَكَ يَا لَا إِلٰهَ إِلَّا أَنْتَ الْأَمَانُ الْأَمَانُ خَلِّصْنَا مِنَ النَّارِ",
                 "Ey kendisinden başka ilâh olmayan Allah’ım! Seni her türlü noksandan tenzih ederim. Emân ver bize, bizi cehennem ateşinden kurtar."),
                ("2. Bâb · Rahmet ve Mağfiret Niyazı",
                 "يَا أَرْحَمَ الرَّاحِمِينَ يَا أَكْرَمَ الْأَكْرَمِينَ",
                 "Ey merhametlilerin en merhametlisi, ey kerem sahiplerinin en cömerdi! Bizi rahmetinle kuşat ve dualarımızı kabul buyur.")
            ]
        ),
        FeaturedBookItem(
            id: "veda", title: "Veda Hutbesi", arabicBadge: "خطبة الوداع", icon: "scroll.fill",
            colors: [Color(red: 0.10, green: 0.38, blue: 0.18), Color(red: 0.04, green: 0.20, blue: 0.08)],
            linkedSurah: nil,
            contentSections: [
                ("İnsan Hakları ve Eşitlik",
                 "يَا أَيُّهَا النَّاسُ إِنَّ رَبَّكُمْ وَاحِدٌ وَإِنَّ أَبَاكُمْ وَاحِدٌ",
                 "Ey insanlar! Rabbiniz birdir, babanız da birdir. Hepiniz Âdem’in çocuklarısınız, Âdem ise topraktandır. Arap’ın Arap olmayana, beyazın siyaha takvâ dışında hiçbir üstünlüğü yoktur."),
                ("Emanet ve Kul Hakkı",
                 "فَمَنْ كَانَتْ عِنْدَهُ أَمَانَةٌ فَلْيُؤَدِّهَا إِلَى مَنِ ائْتَمَنَهُ عَلَيْهَا",
                 "Kimin yanında bir emanet varsa, onu sahibine versin. Cahiliye devrindeki her türlü faiz ve kan davası kaldırılmıştır. Kadınların haklarını gözetmenizi ve bu hususta Allah’tan korkmanızı tavsiye ederim."),
                ("İki Emanet: Kur'an ve Sünnet",
                 "تَرَكْتُ فِيكُمْ أَمْرَيْنِ لَنْ تَضِلُّوا مَا تَمَسَّكْتُمْ بِهِمَا كِتَابَ اللَّهِ وَسُنَّةَ نَبِيِّهِ",
                 "Size iki emanet bırakıyorum; onlara sımsıkı sarıldığınız sürece asla yolunuzu şaşırmazsınız: Allah’ın Kitabı Kur’an-ı Kerim ve Peygamberinin Sünneti.")
            ]
        )
    ]

    private struct BundledReading: Decodable {
        let chapters: [KBChapter]
        let bundled_verses: [String: [KBVerse]]
    }
    private static let bundledReading: BundledReading? = {
        guard let url = Bundle.main.url(forResource: "kuran_bilmek_offline", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(BundledReading.self, from: data)
    }()
    static let allSurahs: [SurahMeta] = (bundledReading?.chapters ?? []).map {
        SurahMeta(number: $0.id, nameTr: $0.turkishName, nameAr: $0.name_arabic,
                  ayahCount: $0.verses_count, revelationPlace: $0.revelationPlaceTurkish)
    }

    static func offlineFallbackAyahs(for surahNumber: Int) -> [AyahItem] {
        let offset = allSurahs.filter { $0.number < surahNumber }.reduce(0) { $0 + $1.ayahCount }
        return (bundledReading?.bundled_verses[String(surahNumber)] ?? [])
            .filter { $0.surahId == surahNumber }
            .map { AyahItem(numberInSurah: $0.verse_number, globalNumber: offset + $0.verse_number,
                            arabicText: $0.fullArabicText, turkishText: $0.translationText(for: 77) ?? "Diyanet meali bu ayet için yüklenemedi.") }
    }
}
