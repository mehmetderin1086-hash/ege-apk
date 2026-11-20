import SwiftUI

/// Kitap bulma ile öğretim programını gezme ayrı işlerdir: katalog doğrudan kitapları gösterir.
struct MEBLibraryView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var query = ""
    @State private var grade = 0
    @State private var course = 0
    @State private var downloadedOnly = false
    @AppStorage("meb.grade") private var programGrade = 11
    @State private var opened: MEBCatalog.Course?
    @State private var debugReader: MEBFile?
    private let catalog = MEBCatalog.shared
    private var library: MEBLibrary { MEBLibrary.shared }

    init(query: String = "") { _query = State(initialValue: query) }

    private var books: [MEBCatalog.Book] {
        MEBBookQuery.results(catalog: catalog, query: query, grade: grade, course: course,
                             downloadedOnly: downloadedOnly, stored: library.stored)
    }
    private var hasFilters: Bool { grade != 0 || course != 0 || downloadedOnly || !query.isEmpty }

    var body: some View {
        List {
            if !hasFilters, let recent = library.recentFile {
                Section("Kaldığın yer") { MEBContinueCard(file: recent, onOpen: { debugReader = $0 }) }
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
            Section {
                (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Sınıf").font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
                        Menu {
                            Picker("Sınıf", selection: $grade) {
                                Text("Tüm sınıflar").tag(0)
                                ForEach(catalog.grades) { Text($0.name).tag($0.id) }
                            }
                        } label: {
                            filterLabel(catalog.grades.first { $0.id == grade }?.name ?? "Tüm sınıflar")
                        }.buttonStyle(.plain).accessibilityLabel("Sınıf filtresi")
                            .accessibilityValue(catalog.grades.first { $0.id == grade }?.name ?? "Tüm sınıflar")
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Ders").font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
                        Menu {
                            Picker("Ders", selection: $course) {
                                Text("Tüm dersler").tag(0)
                                ForEach(catalog.courses) { Text($0.shortName).tag($0.id) }
                            }
                        } label: {
                            filterLabel(catalog.courses.first { $0.id == course }?.shortName ?? "Tüm dersler")
                        }.buttonStyle(.plain).accessibilityLabel("Ders filtresi")
                            .accessibilityValue(catalog.courses.first { $0.id == course }?.shortName ?? "Tüm dersler")
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                Button { downloadedOnly.toggle() } label: {
                    (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))) {
                        Text("Yalnız indirilenler").foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                        if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                        HStack(spacing: 8) {
                            Image(systemName: downloadedOnly ? "checkmark.circle.fill" : "circle").font(.title2)
                            if typeSize.isAccessibilitySize { Text(downloadedOnly ? "Seçili" : "Seçili değil").font(.caption) }
                        }.foregroundStyle(Color.accentColor).accessibilityHidden(true)
                    }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).multilineTextAlignment(.leading)
                    .accessibilityLabel("Yalnız indirilenler")
                    .accessibilityValue(downloadedOnly ? "Seçili" : "Seçili değil")
                    .accessibilityAddTraits(downloadedOnly ? .isSelected : [])
                if hasFilters {
                    Button("Filtreleri temizle", systemImage: "line.3.horizontal.decrease.circle") {
                        grade = 0; course = 0; downloadedOnly = false; query = ""
                    }
                }
            } header: {
                Text("Kitabını bul")
            } footer: {
                Text("İndirilen kitaplar internet olmadan açılır. Sınıf ve ders filtreleri listedeki tüm kitaplara uygulanır.")
            }
            Section {
                if books.isEmpty {
                    ContentUnavailableView("Kitap bulunamadı", systemImage: "magnifyingglass",
                                           description: Text("Aramayı veya sınıf ve ders filtrelerini değiştir."))
                } else {
                    ForEach(books) { book in
                        if let file = MEBFile(book: book) {
                            MEBFileRow(file: file, detail: book.kind == "ders" ? "Ders kitabı" : "Etkinlik kitabı", onOpen: { debugReader = $0 })
                        }
                    }
                }
            } header: { Text("\(books.count) kitap\(downloadedOnly ? " · cihazda hazır" : "")") }
            let programs = library.downloaded.filter { $0.id.hasPrefix("program-") && (query.isEmpty || $0.title.localizedStandardContains(query)) }
            if !programs.isEmpty, grade == 0, course == 0 {
                Section("İndirilen öğretim programları") { ForEach(programs) { MEBFileRow(file: $0, onOpen: { debugReader = $0 }) } }
            }
            Section {
                NavigationLink { MEBProgramBrowser() } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Dersler ve konular").font(.headline)
                            Text("Temalar, öğrenme çıktıları ve öğretim programları").font(.subheadline).foregroundStyle(.secondary)
                        }.fixedSize(horizontal: false, vertical: true)
                    } icon: { Image(systemName: "list.bullet.rectangle").accessibilityHidden(true) }
                }
                LabeledContent("Cihazdaki belgeler", value: "\(library.stored.count) · \(MEBFile.size(library.usedBytes))")
            } footer: { Text("Kaynak: Millî Eğitim Bakanlığı · Katalog: \(catalog.version)") }
        }
        .scrollContentBackground(.hidden).background(Theme.canvas)
        .navigationTitle("Kitaplar").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Kitap adı veya ders ara")
        .navigationDestination(for: MEBCatalog.Course.self) { MEBCourseView(course: $0, grade: grade == 0 ? programGrade : grade) }
        .navigationDestination(item: $opened) { MEBCourseView(course: $0, grade: grade == 0 ? programGrade : grade) }
        .fullScreenCover(item: $debugReader) { MEBReader(title: $0.title, url: library.location($0), key: $0.id) }
        .task {
            library.reload()
            if let wanted = DebugArg.value("mebCourse").flatMap({ Int($0) }), opened == nil { opened = catalog.courses.first { $0.id == wanted } }
            #if DEBUG
            if let wanted = DebugArg.value("mebRead"), let file = library.downloaded.first(where: { $0.id == "kitap-" + wanted }) { debugReader = file }
            if let wanted = DebugArg.value("mebDownload").flatMap({ Int($0) }), let book = catalog.books.first(where: { $0.id == wanted }), let file = MEBFile(book: book) { library.download(file) }
            #endif
        }
    }

    private func filterLabel(_ title: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.down").font(.caption.weight(.semibold)).accessibilityHidden(true)
        }
        .foregroundStyle(Color.accentColor).padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
    }
}

struct MEBContinueCard: View {
    let file: MEBFile
    var onOpen: ((MEBFile) -> Void)? = nil
    @AppStorage private var savedPage: Int

    init(file: MEBFile, onOpen: ((MEBFile) -> Void)? = nil) {
        self.file = file; self.onOpen = onOpen
        _savedPage = AppStorage(wrappedValue: 1, "meb.page." + file.id)
    }
    @State private var reading = false
    @Environment(\.dynamicTypeSize) private var typeSize
    private var library: MEBLibrary { MEBLibrary.shared }
    var body: some View {
        Button { if let onOpen { onOpen(file) } else { reading = true } } label: {
            HStack(alignment: .top, spacing: 14) {
                if !typeSize.isAccessibilitySize {
                    Image(systemName: "book.pages.fill").font(.title).foregroundStyle(Color.accentColor)
                        .frame(width: 52, height: 66).background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(file.title).font(.headline).foregroundStyle(Color.primary).fixedSize(horizontal: false, vertical: true)
                    Text("Sayfa \(max(1, savedPage)) · cihazda hazır").font(.subheadline).foregroundStyle(Color.secondary)
                    Label("Okumaya devam et", systemImage: "arrow.right").font(.subheadline.weight(.semibold)).foregroundStyle(Color.accentColor)
                }
                Spacer(minLength: 0)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(18).okuSurface()
        }.buttonStyle(.plain).accessibilityIdentifier("meb.continue")
            .fullScreenCover(isPresented: $reading) { MEBReader(title: file.title, url: library.location(file), key: file.id) }
    }
}

private struct MEBProgramBrowser: View {
    @AppStorage("meb.grade") private var grade = 11
    private let catalog = MEBCatalog.shared
    var body: some View {
        List {
            Picker("Sınıf", selection: $grade) { ForEach(catalog.grades) { Text($0.name).tag($0.id) } }
            Section("Ders programları") {
                ForEach(catalog.courses(in: grade)) { course in
                    NavigationLink { MEBCourseView(course: course, grade: grade) } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(course.shortName).font(.headline)
                                Text("\(course.themes(in: grade).count) tema · \(catalog.books(course: course.id, grade: grade).count) kitap")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }.fixedSize(horizontal: false, vertical: true)
                        } icon: { Image(systemName: "text.book.closed").accessibilityHidden(true) }
                    }
                }
            }
        }.navigationTitle("Dersler ve konular").navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden).background(Theme.canvas)
    }
}

struct MEBCourseView: View {
    let course: MEBCatalog.Course
    let grade: Int
    @State private var theme: MEBCatalog.Theme?
    private let catalog = MEBCatalog.shared

    var body: some View {
        let themes = course.themes(in: grade), books = catalog.books(course: course.id, grade: grade)
        List {
            if !themes.isEmpty {
                Section("Temalar") {
                    ForEach(themes) { item in
                        Button { theme = item } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
                                    Text([item.hours > 0 ? "\(item.hours) ders saati" : nil, "\(item.outcomes.count) öğrenme çıktısı"].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(Color.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
            if !books.isEmpty {
                Section("Kitaplar") { ForEach(books) { book in if let file = MEBFile(book: book) { MEBFileRow(file: file, detail: book.kind == "ders" ? "Ders kitabı" : "Etkinlik kitabı") } } }
            }
            // Toplu indirme: bu sınıfın ya da dersin bütün sınıflarının inmemiş kitapları.
            let library = MEBLibrary.shared
            let here = library.missing(books.compactMap { MEBFile(book: $0) }), everywhere = library.missing(catalog.books(course: course.id).compactMap { MEBFile(book: $0) })
            if !everywhere.files.isEmpty {
                Section {
                    if !here.files.isEmpty {
                        Button("Bu sınıfın kitaplarını indir · \(MEBFile.size(here.bytes))", systemImage: "arrow.down.circle") { library.download(all: here.files) }
                    }
                    if everywhere.files.count > here.files.count {
                        Button("Dersin bütün sınıflarını indir · \(everywhere.files.count) kitap · \(MEBFile.size(everywhere.bytes))", systemImage: "square.and.arrow.down.on.square") { library.download(all: everywhere.files) }
                    }
                } footer: { Text("İndirme uygulama açıkken sürer; kesilirse kaldığı yerden devam eder.") }
            }
            if let program = MEBFile(program: course) {
                Section("Öğretim programı") { MEBFileRow(file: program, detail: "Programın tamamı (PDF)") }
            }
        }
        .navigationTitle(course.shortName).navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $theme) { MEBThemeView(course: course, grade: grade, theme: $0) }
        .task {
            if let wanted = DebugArg.value("mebTheme").flatMap({ Int($0) }), theme == nil { theme = themes.first { $0.id == wanted } }
        }
    }
}

/// Kitabın kendisi birincil eylem; yönetim menüsü ayrı dokunma hedefidir.
struct MEBFileRow: View {
    let file: MEBFile
    var detail = ""
    var onOpen: ((MEBFile) -> Void)? = nil
    @AppStorage private var storedPage: Int

    init(file: MEBFile, detail: String = "", onOpen: ((MEBFile) -> Void)? = nil) {
        self.file = file; self.detail = detail; self.onOpen = onOpen
        _storedPage = AppStorage(wrappedValue: 1, "meb.page." + file.id)
    }
    private var savedPage: Int? { storedPage > 1 ? storedPage : nil }
    @State private var reading = false
    @State private var openAfterDownload = false
    @Environment(\.dynamicTypeSize) private var typeSize
    private var library: MEBLibrary { MEBLibrary.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Button {
                    if library.has(file) { openReader() } else { openAfterDownload = true; library.download(file) }
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        if !typeSize.isAccessibilitySize {
                            Image(systemName: "book.closed.fill").font(.title2).foregroundStyle(Color.accentColor)
                                .frame(width: 40, height: 56).background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                                .accessibilityHidden(true)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text(file.title).font(.headline).foregroundStyle(Color.primary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text([detail, MEBFile.size(file.bytes)].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(Color.secondary)
                            Label(library.has(file) ? savedPage.map { "Devam et · Sayfa \($0)" } ?? "Kitabı oku · cihazda hazır" : "İndir ve oku",
                                  systemImage: library.has(file) ? "book.pages" : "arrow.down.circle")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(Color.accentColor)
                        }
                        Spacer(minLength: 0)
                    }.frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                        .padding(.vertical, 6).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(library.progress[file.id] != nil)
                .accessibilityIdentifier("meb.open." + file.id)
                .accessibilityHint(library.has(file) ? "Kitabı kaldığın sayfadan açar" : "Kitabı cihaza indirir, ardından açar")
                if library.has(file) {
                    Menu {
                        ShareLink(item: library.location(file)) { Label("Paylaş / Dosyalar’a kaydet", systemImage: "square.and.arrow.up") }
                        Button("İndirileni sil", systemImage: "trash", role: .destructive) { library.delete(file) }
                    } label: {
                        Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(Rectangle())
                    }.accessibilityLabel(file.title + ", kitap seçenekleri")
                }
            }
            if let fraction = library.progress[file.id] {
                ProgressView(value: fraction).accessibilityLabel("Kitap indiriliyor")
                Button("İndirmeyi durdur · %\(Int(fraction * 100))", systemImage: "stop.circle") { openAfterDownload = false; library.cancel(file) }
                    .frame(minHeight: 44)
            }
            if let error = library.errors[file.id] {
                Label(error, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(Color.primary)
            }
        }
        .buttonStyle(.borderless)
        .onChange(of: library.has(file)) { _, ready in
            if ready && openAfterDownload { openAfterDownload = false; openReader() }
        }
        .onDisappear { openAfterDownload = false }
        .fullScreenCover(isPresented: $reading) { MEBReader(title: file.title, url: library.location(file), key: file.id) }
    }

    private func openReader() {
        if let onOpen { onOpen(file) } else { reading = true }
    }
}

/// Tema: konular (Ders Video'da konu videosu buradan hazırlanır), öğrenme çıktıları, anahtar kavramlar.
struct MEBThemeView: View {
    let course: MEBCatalog.Course
    let grade: Int
    let theme: MEBCatalog.Theme
    /// Konu videosu ekranına aktarılacak hazır kaynak.
    struct Draft: Identifiable { let id = UUID(); var topic: String; var source: String }
    @State private var draft: Draft?
    @State private var working: String?
    @State private var note: String?
    @State private var search: Task<Void, Never>?
    @State private var confirmingAll = false
    @State private var queueing: String?
    private let catalog = MEBCatalog.shared
    private var library: MEBLibrary { MEBLibrary.shared }
    private var textbooks: [MEBFile] { catalog.books(course: course.id, grade: grade).filter { $0.kind == "ders" }.compactMap { MEBFile(book: $0) } }

    var body: some View {
        List {
            let books = textbooks
            if !books.isEmpty {
                Section { ForEach(books) { MEBFileRow(file: $0, detail: "Ders kitabı") } } header: { Text("Ders kitabı") } footer: {
                    Text(note ?? (books.contains { library.has($0) } ? "Bir konuya dokun: kitabın o bölümü bulunur ve konu videosu ekranına kaynak olarak aktarılır." : "Önce kitabı indir. Sonra bir konuya dokununca kitabın o bölümü konu videosuna kaynak olarak aktarılır."))
                }
            }
            if books.contains(where: { library.has($0) }), allTopics.count > 1 {
                Section {
                    if let queueing { ProgressView(queueing) } else {
                        Button("Tüm konuların videosunu hazırla · \(allTopics.count) konu", systemImage: "square.stack.3d.down.right") { confirmingAll = true }
                    }
                } footer: { Text("Her konunun kitaptaki bölümü bulunur ve videoları sırayla, birer birer hazırlanır. Kitapta bulunamayan konu atlanır. Videolar Konu Videoları sekmesinde birikir.") }
            }
            ForEach(Array(theme.topicGroups.enumerated()), id: \.offset) { _, group in
                Section(group.heading.isEmpty ? "Konular" : group.heading) {
                    ForEach(group.topics, id: \.self) { topic in
                        Button { prepare(topic) } label: {
                            HStack {
                                Text(topic).font(.subheadline).foregroundStyle(Color.primary)
                                Spacer()
                                if working == topic { ProgressView() } else { Image(systemName: "play.rectangle").foregroundStyle(Theme.gradient) }
                            }
                        }.disabled(working != nil)
                    }
                }
            }
            if !theme.summary.isEmpty || theme.hours > 0 {
                Section("Tema hakkında") {
                    if theme.hours > 0 { LabeledContent("Süre", value: "\(theme.hours) ders saati") }
                    if !theme.summary.isEmpty { Text(theme.summary).font(.footnote) }
                }
            }
            if !theme.outcomes.isEmpty {
                Section("Öğrenme çıktıları") { ForEach(Array(theme.outcomes.enumerated()), id: \.offset) { Text($0.element).font(.footnote) } }
            }
            if !theme.keywords.isEmpty { Section("Anahtar kavramlar") { Text(theme.keywords).font(.footnote) } }
        }
        .navigationTitle(theme.shortTitle).navigationBarTitleDisplayMode(.inline)
        .sheet(item: $draft) { TopicVideoCreateView(courseID: nil, topic: $0.topic, source: $0.source) }
        .confirmationDialog("\(allTopics.count) konu videosu sıraya alınsın mı?", isPresented: $confirmingAll, titleVisibility: .visible) {
            Button("Sıraya al ve hazırla") { queueAll() }
            Button("Vazgeç", role: .cancel) {}
        } message: { Text("Her video bir ders planı, seslendirme ve resimler üretir; günlük haklarından düşer. Videolar sırayla hazırlanır, istediğini listeden silebilirsin.") }
        .onDisappear { if draft == nil { search?.cancel(); search = nil; working = nil } }
        #if DEBUG
        // `-mebTopic=<konu>`: konuya dokunulmuş gibi kitabın bölümünü bulur (uçtan uca deneme).
        .task { if let topic = DebugArg.value("mebTopic"), draft == nil { prepare(topic) } }
        #endif
    }

    /// Temanın bütün konuları (en çok 12; kuyruk ve kota makul kalsın).
    private var allTopics: [String] { Array(theme.topicGroups.flatMap(\.topics).prefix(12)) }
    /// Her konunun kitaptaki bölümünü bulur ve videosunu sıraya alır; düzey, ses ve uzunluk son kullanılan ayarlardır.
    private func queueAll() {
        let ready = textbooks.filter { library.has($0) }.map { library.location($0) }, topics = allTopics
        guard !ready.isEmpty else { return }
        let defaults = UserDefaults.standard
        let level = defaults.string(forKey: "topic.level").flatMap(TopicLevel.init) ?? .yazili
        // Ayarlar'daki tek ses (anlatıcı sesi).
        let voice = AppVoice.primary().raw
        note = nil
        search?.cancel()
        search = Task {
            var added = 0, missing: [String] = []
            for (index, topic) in topics.enumerated() {
                guard !Task.isCancelled else { break }
                queueing = "Kitapta aranıyor · \(index + 1)/\(topics.count)"
                let scan = Task.detached(priority: .userInitiated) { () -> String? in
                    for url in ready { if let hit = MEBBookIndex.text(for: topic, in: url, search: false) { return hit.text } }
                    for url in ready { if let hit = MEBBookIndex.text(for: topic, in: url, search: true) { return hit.text } }
                    return nil
                }
                let found = await withTaskCancellationHandler { await scan.value } onCancel: { scan.cancel() }
                if let found, TopicSource.problem(found, topic: topic) == nil {
                    TopicVideoMaker.shared.create(topic: topic, source: found, level: level, twoVoices: false, length: .short, courseID: nil, voiceA: voice, queued: true)
                    added += 1
                } else { missing.append(topic) }
            }
            queueing = nil
            note = "\(added) konu videosu sıraya alındı." + (missing.isEmpty ? "" : " Kitapta bulunamayan \(missing.count) konu atlandı: " + missing.prefix(3).joined(separator: ", ") + (missing.count > 3 ? "…" : ""))
        }
    }

    /// Konunun kitaptaki bölümünü bulur ve konu videosu ekranını o metinle açar. Kitap inmemişse ya da bölüm bulunamazsa
    /// ekran yalnız konu adıyla açılır; kullanıcı sayfaları kendisi ekler.
    private func prepare(_ topic: String) {
        let ready = textbooks.filter { library.has($0) }.map { library.location($0) }
        guard !ready.isEmpty else {
            note = textbooks.isEmpty ? "Bu dersin kitabı katalogda yok; kaynağı kendin ekle." : "Ders kitabı henüz inmedi. Yukarıdan indir; o zamana dek kaynağı kendin ekleyebilirsin."
            draft = Draft(topic: topic, source: "")
            return
        }
        working = topic; note = nil
        search?.cancel()
        search = Task {
            let scan = Task.detached(priority: .userInitiated) { () -> (text: String, pages: ClosedRange<Int>)? in
                // Önce bütün ciltlerin içindekiler dizini; hiçbirinde yoksa sayfalarda arama.
                for url in ready { if let hit = MEBBookIndex.text(for: topic, in: url, search: false) { return hit } }
                for url in ready { if let hit = MEBBookIndex.text(for: topic, in: url, search: true) { return hit } }
                return nil
            }
            let found = await withTaskCancellationHandler { await scan.value } onCancel: { scan.cancel() }
            guard !Task.isCancelled else { return }
            working = nil
            if let found {
                note = "\"\(topic)\" · kitabın \(found.pages.lowerBound)–\(found.pages.upperBound). sayfaları kaynak alındı."
                draft = Draft(topic: topic, source: found.text)
            } else {
                note = "\"\(topic)\" kitabın içindekiler bölümünde bulunamadı; kaynağı kendin ekle."
                draft = Draft(topic: topic, source: "")
            }
        }
    }
}
