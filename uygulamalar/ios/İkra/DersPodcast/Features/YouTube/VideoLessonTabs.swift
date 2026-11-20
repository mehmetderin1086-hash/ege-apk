import SwiftUI
import UIKit

// MARK: - Ortak parçalar

/// "01:15" biçimli zaman rozeti (yalnızca görünüm; düğme içinde kullanılabilir).
struct TimeBadgeLabel: View {
    var time: Double

    var body: some View {
        Text(TranscriptFormat.timestamp(time))
            .font(.caption.monospacedDigit().weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.accentColor.opacity(0.14), in: Capsule())
            .foregroundStyle(Color.accentColor)
    }
}

/// Dokununca videoyu o ana götüren zaman rozeti.
struct TimeBadge: View {
    var time: Double
    /// Rozet atlamanın tek yoluysa (Notlar) dokunma alanı 44 pt'ye çıkar. Payın 5 pt'si yerleşime sayılmaz (satırlar
    /// fazla açılmasın); alt alta rozetler arasında en az 10 pt boşluk olan yerlerde kullanılır, yoksa alanlar çakışır.
    var expandsHitArea = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            TimeBadgeLabel(time: time)
                .padding(.vertical, expandsHitArea ? 11 : 0)
                .padding(.leading, expandsHitArea ? 6 : 0)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, expandsHitArea ? -5 : 0)
        .accessibilityLabel("\(TranscriptFormat.timestamp(time)) anına git")
    }
}

/// Oynatma konumunu izleyen görünmez görünüm: yalnızca indeks değişince üst görünüm yeniden çizilir.
struct PlaybackIndexObserver: View {
    var player: VideoPlayerModel
    var starts: [Double]
    var lastEnd: Double?
    @Binding var index: Int?

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: player.currentTime, initial: true) { _, time in update(time) }
            .onChange(of: starts) { _, _ in update(player.currentTime) }
    }

    private func update(_ time: Double) {
        let next = TranscriptFormat.currentParagraph(at: time, starts: starts, lastEnd: lastEnd)
        if next != index { index = next }
    }
}

// MARK: - Transkript

struct TranscriptTab: View {
    var transcript: VideoTranscript
    var player: VideoPlayerModel
    var notify: (String) -> Void
    var onAddCard: (TranscriptRow) -> Void
    var onAddNote: (TranscriptRow) -> Void

    @State private var language: TranscriptLanguage
    @State private var rows: [TranscriptRow] = []
    @State private var starts: [Double] = []
    @State private var keys: [[Character]] = []
    @State private var query = ""
    @State private var matches: [Int] = []
    @State private var matchSet: Set<Int> = []
    @State private var cursor = 0
    @State private var current: Int?
    @State private var follower = ReadingFollower()
    @State private var localReader = false
    /// Tam ekran okuma durumunu üst ekran tutar (kapak açılınca ders ekranı "kapanmış" sanılıp oynatıcı sökülmesin).
    var readerBinding: Binding<Bool>? = nil
    private var reader: Binding<Bool> { readerBinding ?? $localReader }
    /// Okuma modunda: tam ekran düğmesi gizli.
    var compact = false
    @State private var showWarnings = false
    /// Ders kimliği (öğrenci konuşması kaydı için) ve terim düzeltme geri çağrısı; nil ise ilgili öğeler gizlenir.
    var lessonID: UUID? = nil
    var onCorrectTerm: ((String, String) -> Void)? = nil
    @AppStorage("reading.clean") private var clean = false
    @AppStorage("reading.tapToSeek") private var tapToSeek = false
    @State private var speakers: LessonSpeakers?
    @State private var analyzing = false
    @State private var termRow: TranscriptRow?
    /// Transkript metni değişince (terim düzeltme) satırlar yeniden kurulur.
    @State private var revision = 0

    init(transcript: VideoTranscript, player: VideoPlayerModel, notify: @escaping (String) -> Void,
         onAddCard: @escaping (TranscriptRow) -> Void, onAddNote: @escaping (TranscriptRow) -> Void, compact: Bool = false,
         lessonID: UUID? = nil, onCorrectTerm: ((String, String) -> Void)? = nil, reader: Binding<Bool>? = nil) {
        self.transcript = transcript
        self.readerBinding = reader
        self.player = player
        self.compact = compact
        self.notify = notify
        self.onAddCard = onAddCard
        self.onAddNote = onAddNote
        self.lessonID = lessonID
        self.onCorrectTerm = onCorrectTerm
        let hasTranslation = !(transcript.translation?.paragraphs.isEmpty ?? true)
        _language = State(initialValue: hasTranslation ? .both : .original)
    }

    private var hasTranslation: Bool { !(transcript.translation?.paragraphs.isEmpty ?? true) }
    private var focusedMatch: Int? { matches.isEmpty ? nil : matches[safe: cursor] }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(rows) { row in
                        let isCurrent = row.id == current
                        TranscriptRowView(
                            row: row,
                            isCurrent: isCurrent,
                            player: isCurrent && !matchSet.contains(row.id) ? player : nil,
                            query: matchSet.contains(row.id) ? query : "",
                            isFocusedMatch: focusedMatch == row.id,
                            tapToSeek: tapToSeek,
                            onSeek: { player.seek(to: row.start) },
                            onPlay: { player.seek(to: row.start); player.play() },
                            onLoop: {
                                if !player.setLoop(start: row.start, end: row.end) { notify("Bu paragraf döngü için çok kısa") }
                            },
                            onCorrectTerm: onCorrectTerm == nil ? nil : { termRow = row },
                            onCopy: {
                                UIPasteboard.general.string = "[\(TranscriptFormat.timestamp(row.start))] " + TranscriptFormat.searchText(row)
                                notify("Kopyalandı")
                            },
                            onCard: { onAddCard(row) },
                            onNote: { onAddNote(row) })
                        .rowWidthLocked(horizontalPadding: 10)
                        .id(row.id)
                        .reportsReadingFrame(row: row.id, to: follower, isCurrent: isCurrent)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .lockedToScrollWidth()
            }
            .scrollDismissesKeyboard(.interactively)
            // Kelimeye dokununca o kelimeye atla (bağlantılar dersseek://satır/kelime).
            .environment(\.openURL, OpenURLAction { url in
                guard let hit = WordSeek.parse(url), let row = rows.first(where: { $0.id == hit.row }),
                      let time = WordSeek.time(of: hit.word, in: row) else { return .systemAction }
                player.seek(to: time)
                return .handled
            })
            .readingFollower(follower)
            // Okunan yeri takip: her oynatma tikinde ölçülen çerçeveye göre (arama açıkken kapalı).
            .background(VideoReadingTick(rows: rows, current: current, player: player, follower: follower, enabled: query.isEmpty))
            .onChange(of: focusedMatch) { _, match in
                guard let match else { return }
                withAnimation(.easeInOut(duration: 0.3)) { follower.position.scrollTo(id: match, anchor: .top) }
            }
            .onChange(of: rows) { _, _ in
                if let current { follower.position.scrollTo(id: current, anchor: UnitPoint(x: 0.5, y: FollowAlong.readingLine)) }
            }
        }
        .background(PlaybackIndexObserver(player: player, starts: starts, lastEnd: rows.last?.end, index: $current))
        .fullScreenCover(isPresented: reader) {
            VideoReaderView(transcript: transcript, player: player, notify: notify, onAddCard: onAddCard, onAddNote: onAddNote,
                            lessonID: lessonID, onCorrectTerm: onCorrectTerm)
        }
        .sheet(item: $termRow) { row in
            TermPickerSheet(text: row.text) { from, to in onCorrectTerm?(from, to) }
        }
        .onAppear {
            #if DEBUG
            if !compact, ProcessInfo.processInfo.arguments.contains("-readerDemo") { reader.wrappedValue = true }
            #endif
        }
        .task(id: RebuildKey(language: language, clean: clean, revision: revision, speakers: speakers)) { await rebuild() }
        .onChange(of: transcript) { _, _ in revision += 1 }
        .onChange(of: query) { _, _ in recomputeMatches() }
        .task(id: lessonID) {
            guard let lessonID else { return }
            speakers = SpeakerAnalysis.load(lesson: lessonID)
        }
    }

    private struct RebuildKey: Hashable {
        var language: TranscriptLanguage
        var clean: Bool
        var revision: Int
        var speakers: LessonSpeakers?
    }

    /// Öğrenci konuşması olan altyazı satırlarının sırası. Kayıt güncel sürümde ve satır sayısıyla uyumluysa (transkript
    /// yenilenmediyse); değilse boş.
    private var studentSegments: Set<Int> {
        guard let speakers, speakers.matches(segmentCount: transcript.segments.count) else { return [] }
        return Set(speakers.student)
    }

    private func analyzeSpeakers() {
        guard let lessonID, !analyzing else { return }
        analyzing = true
        let segments = transcript.segments
        Task {
            defer { analyzing = false }
            do {
                let result = try await SpeakerAnalysis.run(segments: segments, lesson: lessonID)
                speakers = result
                notify(result.student.isEmpty ? "Öğrenci konuşması bulunmadı" : "\(result.student.count) satır öğrenci konuşması")
            } catch is CancellationError {
            } catch {
                notify(error.localizedDescription)
            }
        }
    }

    /// Okuma menüsü: temiz okuma, dokunarak atla, öğrenci konuşması (başlıkta tek düğme; dar ekranda yer kaplamaz).
    private var readingMenu: some View {
        let hasSpeakers = speakers?.matches(segmentCount: transcript.segments.count) ?? false
        let active = clean || tapToSeek || hasSpeakers
        return Menu {
            Toggle(isOn: $clean) { Label("Temiz okuma (dolguları gizle)", systemImage: "sparkles") }
            Toggle(isOn: $tapToSeek) { Label("Dokunarak atla", systemImage: "hand.tap") }
            if lessonID != nil {
                Section("Konuşmacılar") {
                    if analyzing {
                        Text("Çözümleniyor…")
                    } else if hasSpeakers {
                        Button("Yeniden çözümle", systemImage: "arrow.clockwise", action: analyzeSpeakers)
                        Button("Öğrenci renklendirmesini kaldır", systemImage: "xmark", role: .destructive) {
                            if let lessonID { SpeakerAnalysis.delete(lesson: lessonID) }
                            speakers = nil
                        }
                    } else {
                        Button("Öğrenci konuşmasını bul", systemImage: "person.fill.questionmark", action: analyzeSpeakers)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                if analyzing { ProgressView().controlSize(.mini) } else { Image(systemName: active ? "text.badge.checkmark" : "text.viewfinder") }
                Text("Okuma")
            }
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(active ? Color.accentColor.opacity(0.18) : Color(.secondarySystemBackground)))
            .foregroundStyle(active ? Color.accentColor : Color.primary)
        }
        .accessibilityLabel("Okuma seçenekleri")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            if hasTranslation {
                Picker("Dil", selection: $language) {
                    ForEach(TranscriptLanguage.allCases) { Text($0.title).tag($0) }
                }
                .modifier(AccessiblePickerStyle())
            }
            // Simge düğmeleri 36×36 ve bitişik (yanlış simgeye dokunulmasın). Çubuğun yüksekliği aynı kalsın diye dikey boşluk
            // metin alanına, sağ boşluk düğme çerçevesine taşındı.
            HStack(spacing: 0) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).padding(.trailing, 8)
                TextField("Transkriptte ara", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit(next)
                    .padding(.vertical, 7)
                if !query.isEmpty {
                    Text(matches.isEmpty ? "0" : "\(cursor + 1)/\(matches.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.leading, 6)
                    Button(action: previous) {
                        Image(systemName: "chevron.up")
                            .frame(minWidth: Self.toolTarget, minHeight: Self.toolTarget).contentShape(Rectangle())
                    }
                    .disabled(matches.isEmpty)
                    .accessibilityLabel("Önceki eşleşme")
                    Button(action: next) {
                        Image(systemName: "chevron.down")
                            .frame(minWidth: Self.toolTarget, minHeight: Self.toolTarget).contentShape(Rectangle())
                    }
                    .disabled(matches.isEmpty)
                    .accessibilityLabel("Sonraki eşleşme")
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            .frame(minWidth: Self.toolTarget, minHeight: Self.toolTarget).contentShape(Rectangle())
                    }
                    .accessibilityLabel("Aramayı temizle")
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)   // çok büyük yazıda simgeler satırı taşırmasın
            .padding(.leading, 10)
            .padding(.trailing, query.isEmpty ? 10 : 2)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
            // Okuma boyutu ve tam ekran arama kapsülünden buraya alındı: 320 pt'de yazılan sorguya 6-7 harflik yer kalıyordu.
            // Bilgi metni araçlarla sığmazsa önce kısalır (yalnız kaynak), sonra gizlenir: üçüncü satır transkriptten yer alırdı.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    infoText(full: true)
                    Spacer(minLength: 4)
                    headerTools
                }
                HStack(spacing: 6) {
                    infoText(full: false)
                    Spacer(minLength: 4)
                    headerTools
                }
                HStack(spacing: 8) {
                    headerTools
                    Spacer(minLength: 0)
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            // Simgelerin 36 pt'lik dokunma alanının 4 pt'si üstteki/alttaki 8 pt boşluğa taşar: satır 28 pt yer tutar.
            .padding(.vertical, -4)
            if showWarnings {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(transcript.warnings, id: \.self) { Text("• " + $0) }
                }
                .font(.caption)
                .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private static let toolTarget: CGFloat = 36

    /// Başlığın ikinci satırındaki araçlar: okuma seçenekleri, yazı boyutu, tam ekran (okuma modunda yok), uyarılar.
    @ViewBuilder
    private var headerTools: some View {
        readingMenu
        ReadingSizeMenu(minTarget: Self.toolTarget)
        if !compact {
            Button { reader.wrappedValue = true } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right").foregroundStyle(.secondary)
                    .frame(minWidth: Self.toolTarget, minHeight: Self.toolTarget).contentShape(Rectangle())
            }
            .accessibilityLabel("Tam ekran oku")
        }
        warningsButton
    }

    private func infoText(full: Bool) -> some View {
        HStack(spacing: 6) {
            Text(VideoTranscript.sourceTitle(transcript.source))
            if full {
                Text("·")
                Text("\(transcript.paragraphs.count) paragraf")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    @ViewBuilder
    private var warningsButton: some View {
        if !transcript.warnings.isEmpty {
            Button {
                withAnimation { showWarnings.toggle() }
            } label: {
                Label("\(transcript.warnings.count) uyarı", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .lineLimit(1)
                    .fixedSize()
            }
            .tint(.orange)
        }
    }

    private func rebuild() async {
        var built = TranscriptFormat.rows(paragraphs: transcript.paragraphs, translation: transcript.translation, language: language,
                                          segments: transcript.segments, students: studentSegments)
        if clean { built = CleanReading.clean(built) }
        let builtKeys = await LessonFiles.searchKeys(built.map(TranscriptFormat.searchText))
        // Dil yeniden değiştiyse eski hesap yeni satırların üstüne yazılmasın.
        guard !Task.isCancelled else { return }
        rows = built
        starts = built.map(\.start)
        keys = builtKeys
        recomputeMatches()
    }

    private func recomputeMatches() {
        let found = keys.count == rows.count ? TranscriptFormat.matchingIndices(of: query, keys: keys) : []
        let ids = found.map { rows[$0].id }
        matches = ids
        matchSet = Set(ids)
        // İlk eşleşme: çalan paragraftan sonraki ilk eşleşme (yoksa baştan).
        if let current, let after = ids.firstIndex(where: { $0 >= current }) { cursor = after } else { cursor = 0 }
    }

    private func next() {
        guard !matches.isEmpty else { return }
        cursor = (cursor + 1) % matches.count
    }

    private func previous() {
        guard !matches.isEmpty else { return }
        cursor = (cursor - 1 + matches.count) % matches.count
    }

}

/// Oynatıcı tikini takipçiye iletir (yalnızca bu görünüm her tikte yeniden çizilir).
private struct VideoReadingTick: View {
    var rows: [TranscriptRow]
    var current: Int?
    var player: VideoPlayerModel
    var follower: ReadingFollower
    var enabled: Bool

    var body: some View {
        let time = player.currentTime
        Color.clear
            .onChange(of: time, initial: true) { _, time in
                guard enabled, let current, let row = rows.first(where: { $0.id == current }) else { return }
                let timing = FollowAlong.Timing(text: row.text, start: row.start, end: row.end, spans: row.spans)
                let reading = FollowAlong.readingTime(time, rate: player.rate)
                follower.follow(row: current, progress: timing.textProgress(at: reading), playing: player.isPlaying)
                FollowAlong.logSync(time: time, text: row.text, timing: timing, reading: reading)
            }
    }
}

/// Çalan paragraf: oynatıcı zamanına göre kelime kelime takip.
private struct LiveRowText: View {
    var row: TranscriptRow
    var player: VideoPlayerModel
    var tapToSeek = false
    @AppStorage(ReadingSize.key) private var size = ReadingSize.defaultSize

    var body: some View {
        // Öğrenci satırlarının kelimeleri `row.spans`taki `student` bayrağıyla ayrı renkte (FollowAlongText kendisi çözer).
        FollowAlongText(text: row.text, start: row.start, end: row.end,
                        time: FollowAlong.readingTime(player.currentTime, rate: player.rate), font: .system(size: size),
                        spans: row.spans,
                        link: tapToSeek ? { WordSeek.url(row: row.id, word: $0) } : nil)
    }
}

/// Satıra dokununca atlama (dokunarak atla kipinde kapalı).
private struct RowTapModifier: ViewModifier {
    var enabled: Bool
    var action: () -> Void

    func body(content: Content) -> some View {
        if enabled { content.onTapGesture(perform: action) } else { content }
    }
}

struct TranscriptRowView: View {
    var row: TranscriptRow
    var isCurrent: Bool
    /// Yalnızca çalan satıra verilir: kelime kelime takip.
    var player: VideoPlayerModel? = nil
    /// Bu satır eşleşiyorsa sorgu; değilse boş.
    var query: String
    var isFocusedMatch: Bool
    /// Dokunarak atla kipi: her kelime bir bağlantıdır (dersseek://satır/kelime).
    var tapToSeek = false
    var onSeek: () -> Void
    var onPlay: () -> Void
    var onLoop: (() -> Void)? = nil
    var onCorrectTerm: (() -> Void)? = nil
    var onCopy: () -> Void
    var onCard: () -> Void
    var onNote: () -> Void
    @AppStorage(ReadingSize.key) private var readingSize = ReadingSize.defaultSize

    @Environment(\.dynamicTypeSize) private var typeSize

    static let studentColor = FollowAlong.studentColor

    var body: some View {
        // Rozet solda, metin sağda; dar satırda (Ekran Büyütme, büyük yazı) rozet metnin üstüne geçer.
        BadgeColumnLayout(forceStacked: typeSize.isAccessibilitySize) {
            TimeBadge(time: row.start, action: onSeek)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 6) {
                if row.hasStudent {
                    Label("Öğrenci", systemImage: "person.fill.questionmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Self.studentColor)
                }
                if let player {
                    LiveRowText(row: row, player: player, tapToSeek: tapToSeek)
                } else {
                    Text(highlighted(row.text))
                        .font(.system(size: readingSize))
                }
                if let secondary = row.secondary {
                    Text(highlighted(secondary))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(isCurrent ? Color.accentColor.opacity(0.13) : Color.clear))
        .overlay(alignment: .leading) {
            if row.hasStudent { Capsule().fill(Self.studentColor).frame(width: 3).padding(.vertical, 8) }
        }
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(isFocusedMatch ? Color.orange : Color.clear, lineWidth: 1.5))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        // Dokunarak atla açıkken satırın kendi dokunuşu kelime bağlantısını yutmasın: satıra atlama zaman rozetiyle.
        .modifier(RowTapModifier(enabled: !tapToSeek, action: onSeek))
        .contextMenu {
            Button("Buradan oynat", systemImage: "play.fill", action: onPlay)
            if let onLoop { Button("Bu paragrafı döngüye al", systemImage: "repeat", action: onLoop) }
            if let onCorrectTerm { Button("Terimi düzelt", systemImage: "character.cursor.ibeam", action: onCorrectTerm) }
            Button("Kopyala", systemImage: "doc.on.doc", action: onCopy)
            Button("Kart olarak ekle", systemImage: "rectangle.stack.badge.plus", action: onCard)
            Button("Not ekle", systemImage: "note.text.badge.plus", action: onNote)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .accessibilityAction(named: "Buradan oynat", onPlay)
        .accessibilityAction(named: "Bu paragrafı döngüye al") { onLoop?() }
        .accessibilityAction(named: "Kart olarak ekle", onCard)
        .accessibilityAction(named: "Not ekle", onNote)
    }

    private func highlighted(_ text: String) -> AttributedString {
        var attributed: AttributedString
        if text == row.text, tapToSeek || row.hasStudent {
            // Öğrenci kelimeleri teal; dokunarak atla kipinde her kelime bağlantı (renkler açıkça verilir, bağlantı rengi bozmasın).
            let words = FollowAlong.words(in: text)
            attributed = FollowAlong.attributed(text, words: words, current: nil, highlight: FollowAlong.highlight,
                                                readColor: .primary, upcoming: .primary,
                                                students: FollowAlong.studentWords(wordCount: words.count, spans: row.spans),
                                                studentUpcoming: FollowAlong.studentColor,
                                                link: tapToSeek ? { WordSeek.url(row: row.id, word: $0) } : nil)
        } else {
            attributed = AttributedString(text)
        }
        guard !query.isEmpty else { return attributed }
        for range in TranscriptFormat.matchRanges(of: query, in: text) {
            guard let r = Range(range, in: attributed) else { continue }
            attributed[r].backgroundColor = Color.yellow.opacity(0.5)
            attributed[r].foregroundColor = Color.primary
        }
        return attributed
    }
}

/// Rozet solda, metin sağda. Metin sütunu `minTextWidth`'ten dar kalacaksa (320 pt ekran, büyük yazı) rozet metnin üstüne geçer
/// ve metin tam genişliği kullanır.
private struct BadgeColumnLayout: Layout {
    var spacing: CGFloat = 10
    var stackedSpacing: CGFloat = 4
    var minTextWidth: CGFloat = 230
    var forceStacked = false

    private func isStacked(width: CGFloat, badge: CGSize) -> Bool {
        forceStacked || width - badge.width - spacing < minTextWidth
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let width = proposal.width ?? 360
        let badge = subviews[0].sizeThatFits(.unspecified)
        if isStacked(width: width, badge: badge) {
            let text = subviews[1].sizeThatFits(ProposedViewSize(width: width, height: nil))
            return CGSize(width: width, height: badge.height + stackedSpacing + text.height)
        }
        let text = subviews[1].sizeThatFits(ProposedViewSize(width: width - badge.width - spacing, height: nil))
        return CGSize(width: width, height: max(badge.height, text.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let badge = subviews[0].sizeThatFits(.unspecified)
        if isStacked(width: bounds.width, badge: badge) {
            subviews[0].place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(badge))
            subviews[1].place(at: CGPoint(x: bounds.minX, y: bounds.minY + badge.height + stackedSpacing), anchor: .topLeading,
                              proposal: ProposedViewSize(width: bounds.width, height: nil))
        } else {
            subviews[0].place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(badge))
            subviews[1].place(at: CGPoint(x: bounds.minX + badge.width + spacing, y: bounds.minY), anchor: .topLeading,
                              proposal: ProposedViewSize(width: bounds.width - badge.width - spacing, height: nil))
        }
    }
}

// MARK: - Bölümler

struct ChaptersTab: View {
    /// Başlangıca göre sıralı.
    var chapters: [VideoChapter]
    var duration: Double
    var player: VideoPlayerModel
    @State private var current: Int?

    var body: some View {
        if chapters.isEmpty {
            ContentUnavailableView("Bölüm yok", systemImage: "list.bullet.rectangle",
                                   description: Text("Bu video için bölüm bilgisi bulunamadı."))
        } else {
            ScrollViewReader { proxy in
                List {
                    ForEach(Array(chapters.enumerated()), id: \.offset) { index, chapter in
                        Button {
                            player.seek(to: chapter.start)
                        } label: {
                            row(index: index, chapter: chapter)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(index == current ? Color.accentColor.opacity(0.12) : nil)
                        .id(index)
                        .accessibilityAddTraits(index == current ? .isSelected : [])
                    }
                }
                .listStyle(.plain)
                // Çalan bölüm ilk belirlendiğinde (onAppear'da henüz nil olur) ve her bölüm geçişinde görünür kalır.
                .onChange(of: current) { _, new in
                    if let new { withAnimation { proxy.scrollTo(new, anchor: .center) } }
                }
            }
            .background(PlaybackIndexObserver(player: player, starts: chapters.map(\.start), lastEnd: nil, index: $current))
        }
    }

    private func row(index: Int, chapter: VideoChapter) -> some View {
        let isCurrent = index == current
        let end = chapters[safe: index + 1]?.start ?? duration
        return HStack(spacing: 12) {
            ZStack {
                Circle().fill(isCurrent ? Color.accentColor : Color(.tertiarySystemFill))
                if isCurrent {
                    Image(systemName: "speaker.wave.2.fill").font(.caption2).foregroundStyle(.white)
                } else {
                    Text("\(index + 1)").font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(chapter.title)
                    .font(isCurrent ? .body.weight(.semibold) : .body)
                    .foregroundStyle(isCurrent ? Color.accentColor : Color.primary)
                if end > chapter.start {
                    Text("\(TranscriptFormat.timestamp(end - chapter.start)) sürüyor")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            TimeBadgeLabel(time: chapter.start)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - Notlar

struct NotesTab: View {
    var notes: LectureNotes?
    /// Transkriptin uyarıları: notlar yoksa nedeni (ör. "Ders notu hazırlanamadı (…)") buradan gösterilir.
    var warnings: [String] = []
    var player: VideoPlayerModel
    var onAddAll: () -> Void
    @State private var revealed: Set<Int> = []

    var body: some View {
        if let notes {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    let cardCount = notes.concepts.count + notes.questions.count
                    if cardCount > 0 {
                        Button(action: onAddAll) {
                            Label("Hepsini kartlara ekle (\(cardCount))", systemImage: "rectangle.stack.badge.plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    if !notes.summary.isEmpty {
                        NoteSection(title: "Özet", systemImage: "text.alignleft") {
                            Text(notes.summary).textSelection(.enabled)
                        }
                    }
                    if !notes.keyPoints.isEmpty {
                        NoteSection(title: "Ana noktalar", systemImage: "list.bullet") {
                            ForEach(Array(notes.keyPoints.enumerated()), id: \.offset) { _, point in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text("•").foregroundStyle(.secondary)
                                    Text(point.text).frame(maxWidth: .infinity, alignment: .leading)
                                    TimeBadge(time: point.time, expandsHitArea: true) { player.seek(to: point.time) }
                                }
                            }
                        }
                    }
                    if !notes.concepts.isEmpty {
                        NoteSection(title: "Kavramlar", systemImage: "character.book.closed") {
                            ForEach(Array(notes.concepts.enumerated()), id: \.offset) { _, concept in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(concept.name).fontWeight(.semibold)
                                        Text(concept.definition).foregroundStyle(.secondary).textSelection(.enabled)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    TimeBadge(time: concept.time, expandsHitArea: true) { player.seek(to: concept.time) }
                                }
                            }
                        }
                    }
                    if !notes.formulas.isEmpty {
                        NoteSection(title: "Formüller", systemImage: "function") {
                            ForEach(Array(notes.formulas.enumerated()), id: \.offset) { _, formula in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(formula.name).fontWeight(.semibold)
                                        Text(formula.expression)
                                            .font(.body.monospaced())
                                            .padding(.horizontal, 8).padding(.vertical, 4)
                                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 6))
                                            .textSelection(.enabled)
                                        if !formula.meaning.isEmpty {
                                            Text(formula.meaning).font(.callout).foregroundStyle(.secondary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    TimeBadge(time: formula.time, expandsHitArea: true) { player.seek(to: formula.time) }
                                }
                            }
                        }
                    }
                    if !notes.questions.isEmpty {
                        NoteSection(title: "Sorular", systemImage: "questionmark.bubble") {
                            ForEach(Array(notes.questions.enumerated()), id: \.offset) { index, question in
                                questionRow(index: index, question: question)
                            }
                        }
                    }
                    if !notes.examTips.isEmpty {
                        NoteSection(title: "Sınav ipuçları", systemImage: "lightbulb") {
                            ForEach(Array(notes.examTips.enumerated()), id: \.offset) { _, tip in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Image(systemName: "checkmark.seal").foregroundStyle(.orange).font(.caption)
                                    Text(tip)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
        } else {
            let message = TranscriptFormat.missingNotesMessage(warnings: warnings)
            ContentUnavailableView(message.title, systemImage: "note.text", description: Text(message.detail))
        }
    }

    private func questionRow(index: Int, question: NoteQuestion) -> some View {
        let isOpen = revealed.contains(index)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(index + 1). \(question.question)")
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity, alignment: .leading)
                TimeBadge(time: question.time, expandsHitArea: true) { player.seek(to: question.time) }
            }
            if isOpen {
                Text(question.answer)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .transition(.opacity)
            } else {
                Text("Cevabı görmek için dokun")
                    .font(.caption)
                    .foregroundStyle(.tint)
            }
        }
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                if isOpen { revealed.remove(index) } else { revealed.insert(index) }
            }
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(isOpen ? "" : "Cevabı gösterir")
    }
}

private struct NoteSection<Content: View>: View {
    var title: String
    var systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Kareler

struct FramesTab: View {
    var lessonID: UUID
    /// Zamana göre sıralı.
    var frames: [Keyframe]
    var player: VideoPlayerModel
    /// Büyütülen kare. Ders ekranında tutulur: tam ekran kapak açıkken ekranın onDisappear'ı tetiklenir ve
    /// ders ekranı bunu "ekrandan çıkış" saymamalıdır (ses kipi durmasın, ses indirmesi iptal olmasın).
    @Binding var zoomed: Keyframe?
    /// Çalan anın karesi: o ana dek gösterilmiş son kare (ilk kareden önce nil).
    @State private var current: Int?
    @State private var didScroll = false

    var body: some View {
        if frames.isEmpty {
            ContentUnavailableView("Kare yok", systemImage: "photo.on.rectangle",
                                   description: Text("Bu video işlenirken kare yakalama kapalıydı ya da tahta/slayt içeren kare bulunamadı."))
        } else {
            let currentID = current.flatMap { frames[safe: $0]?.id }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 158), spacing: 12)], spacing: 16) {
                        ForEach(frames) { frame in
                            let isCurrent = frame.id == currentID
                            // Yalnız büyütür: 42. dakikada dinlerken 12. dakikanın tahtasına bakmak oynatmayı oraya atlatmasın
                            // (o ana gitmek için büyütme ekranında "Buradan oynat" var).
                            Button {
                                zoomed = frame
                            } label: {
                                KeyframeCell(frame: frame, url: VideoFiles.keyframeURL(lesson: lessonID, frame: frame.id), isCurrent: isCurrent)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(TranscriptFormat.timestamp(frame.time)), \(frame.caption)")
                            .accessibilityValue(isCurrent ? "Şu an çalan kare" : "")
                            .accessibilityHint("Kareyi büyütür")
                        }
                    }
                    .padding()
                }
                // Yalnız ilk belirlemede kaydırılır: sonrasında ızgarada gezinen kullanıcı yerinden edilmez.
                .onChange(of: currentID) { _, new in
                    guard !didScroll, let new else { return }
                    didScroll = true
                    proxy.scrollTo(new, anchor: .center)
                }
            }
            .background(PlaybackIndexObserver(player: player, starts: frames.map(\.time), lastEnd: nil, index: $current))
            .fullScreenCover(item: $zoomed) { frame in
                KeyframeZoomView(frame: frame, url: VideoFiles.keyframeURL(lesson: lessonID, frame: frame.id)) {
                    player.seek(to: frame.time)
                    player.play()
                }
            }
        }
    }
}

private struct KeyframeCell: View {
    var frame: Keyframe
    var url: URL
    /// Oynatma şu an bu karenin anında: çerçeve ve "Şu an" rozeti (yalnız renkle değil).
    var isCurrent = false
    @State private var image: UIImage?
    @State private var missing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color(.secondarySystemBackground)
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else if missing {
                        Image(systemName: "photo").foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .bottomLeading) {
                    Text(TranscriptFormat.timestamp(frame.time))
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 4))
                        .padding(5)
                }
                .overlay(alignment: .topTrailing) {
                    if isCurrent {
                        Label("Şu an", systemImage: "speaker.wave.2.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.accentColor, in: Capsule())
                            .padding(5)
                    }
                }
                .overlay {
                    if isCurrent { RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor, lineWidth: 2) }
                }
            Text(frame.caption.isEmpty ? "Kare" : frame.caption)
                .font(.caption.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .task(id: url) {
            image = await LessonFiles.thumbnail(url, maxPixel: 480)
            missing = image == nil
        }
    }
}

/// Tam ekran kare: sıkıştırarak/çift dokunarak yakınlaştırma, açıklama ve karedeki yazı.
struct KeyframeZoomView: View {
    var frame: Keyframe
    var url: URL
    var onPlayHere: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    /// Dosya okunamadı (silinmiş/bozuk): sonsuz yükleme göstergesi yerine açıklama.
    @State private var missing = false
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ZStack {
                    Color.black
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .scaleEffect(scale)
                            .offset(offset)
                            .gesture(zoomGesture.simultaneously(with: panGesture))
                            .onTapGesture(count: 2) {
                                withAnimation(.spring(duration: 0.3)) {
                                    if scale > 1 { reset() } else { scale = 2.5; lastScale = 2.5 }
                                }
                            }
                            .accessibilityLabel(frame.caption)
                    } else if missing {
                        ContentUnavailableView("Kare dosyası bulunamadı", systemImage: "photo")
                            .environment(\.colorScheme, .dark)   // siyah zeminde okunur renkler
                    } else {
                        ProgressView().tint(.white)
                    }
                }
                .clipped()
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            TimeBadgeLabel(time: frame.time)
                            Text(frame.caption).font(.headline)
                        }
                        if !frame.text.isEmpty {
                            Text("Karedeki yazı").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Text(frame.text).textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
                .frame(maxHeight: 230)
                .background(Color(.systemBackground))
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    if FileManager.default.fileExists(atPath: url.path) {
                        ShareLink(item: url) { Label("Paylaş", systemImage: "square.and.arrow.up") }
                    }
                    Button("Buradan oynat", systemImage: "play.fill") {
                        onPlayHere()
                        dismiss()
                    }
                }
            }
        }
        .task {
            image = await LessonFiles.image(url)
            missing = image == nil
        }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in scale = min(max(lastScale * value.magnification, 1), 6) }
            .onEnded { _ in
                lastScale = scale
                if scale <= 1 { withAnimation { reset() } }
            }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1 else { return }
                offset = CGSize(width: lastOffset.width + value.translation.width, height: lastOffset.height + value.translation.height)
            }
            .onEnded { _ in lastOffset = offset }
    }

    private func reset() {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
    }
}

// MARK: - Sor

nonisolated struct AskEntry: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var question: String
    var answer: YouTubeAskResponse?
    var error: String?
    var askedAt: Date?
}

nonisolated extension AskEntry {
    /// Eksik alana dayanıklı çözme: bir kayıt bozuk diye dersin bütün geçmişi atılmasın.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        question = try c.decodeIfPresent(String.self, forKey: .question) ?? ""
        answer = try c.decodeIfPresent(YouTubeAskResponse.self, forKey: .answer)
        error = try c.decodeIfPresent(String.self, forKey: .error)
        askedAt = try c.decodeIfPresent(Date.self, forKey: .askedAt)
    }
}

/// Her dersin soru geçmişi: bellekte ve ders klasöründeki ask.json'da (uygulama kapanınca cevaplar gitmesin).
/// Taslak soru ve süren istek de burada durur: sekme değişince AskTab yok olur; dönen yeni görünüm yazılan soruyu,
/// "taranıyor" göstergesini ve o arada gelen cevabı buradan görür.
enum AskHistory {
    @Observable
    final class Live {
        var entries: [UUID: [AskEntry]] = [:]
        var drafts: [UUID: String] = [:]
        var inFlight: Set<UUID> = []
    }

    static let live = Live()
    nonisolated static let limit = 40
    nonisolated static let fileName = "ask.json"

    /// Yan etkisiz yol (klasör oluşturmaz).
    nonisolated static func fileURL(lesson id: UUID) -> URL {
        URL.applicationSupportDirectory.appending(path: "Videos", directoryHint: .isDirectory)
            .appending(path: id.uuidString, directoryHint: .isDirectory)
            .appending(path: fileName)
    }

    /// Diske yazılacak kayıtlar: hata kayıtları kalıcı değildir, en yeni `limit` cevap tutulur.
    nonisolated static func persistable(_ entries: [AskEntry]) -> [AskEntry] {
        Array(entries.filter { $0.answer != nil }.suffix(limit))
    }

    /// Çözülemeyen tek kayıt atlanır: biri bozuk diye geçmişin tamamı boş görünüp sonraki cevapla dosyanın üzerine yazılmasın.
    nonisolated private struct LossyEntry: Decodable {
        let entry: AskEntry?
        init(from decoder: Decoder) throws { entry = try? AskEntry(from: decoder) }
    }

    nonisolated static func decode(_ data: Data) -> [AskEntry] {
        ((try? JSONDecoder().decode([LossyEntry].self, from: data)) ?? []).compactMap(\.entry)
    }

    nonisolated static func read(_ url: URL) -> [AskEntry] {
        (try? Data(contentsOf: url)).map(decode) ?? []
    }

    /// Klasör yoksa yazmaz: silinmiş dersin klasörü geç gelen bir cevap yüzünden yeniden oluşmasın.
    @discardableResult
    nonisolated static func write(_ entries: [AskEntry], to url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path),
              let data = try? JSONEncoder().encode(persistable(entries)) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    /// Panoya giden metin: soru ve (varsa) cevap.
    nonisolated static func copyText(_ entry: AskEntry) -> String {
        guard let answer = entry.answer?.answer, !answer.isEmpty else { return entry.question }
        return "\(entry.question)\n\n\(answer)"
    }

    /// Dersin geçmişi; oturumda ilk kez isteniyorsa diskten okunur.
    @discardableResult
    static func load(lesson id: UUID) -> [AskEntry] {
        if let cached = live.entries[id] { return cached }
        let stored = read(fileURL(lesson: id))
        live.entries[id] = stored
        return stored
    }

    static func append(_ entry: AskEntry, lesson id: UUID) {
        let all = load(lesson: id) + [entry]
        live.entries[id] = all
        if entry.answer != nil { write(all, to: fileURL(lesson: id)) }
    }

    static func remove(_ entryID: UUID, lesson id: UUID) {
        let all = load(lesson: id).filter { $0.id != entryID }
        live.entries[id] = all
        write(all, to: fileURL(lesson: id))
    }

    /// Ders silindi: bellekteki geçmişi ve taslağı bırakılır (dosya ders klasörüyle birlikte gider).
    static func forget(lesson id: UUID) {
        live.entries[id] = nil
        live.drafts[id] = nil
    }
}

struct AskTab: View {
    var lessonID: UUID
    var title: String
    var paragraphs: [TranscriptParagraph]
    var player: VideoPlayerModel
    var notify: ((String) -> Void)? = nil

    @State private var recorder = SpeechRecorder()
    @State private var toDelete: UUID?
    @FocusState private var focused: Bool

    // Durum görünümde değil paylaşılan geçmişte: sekme değişip dönülünce (ve istek o arada bitince) aynı yerden sürer.
    private var entries: [AskEntry] { AskHistory.live.entries[lessonID] ?? [] }
    private var loading: Bool { AskHistory.live.inFlight.contains(lessonID) }
    private var question: String {
        get { AskHistory.live.drafts[lessonID] ?? "" }
        nonmutating set { AskHistory.live.drafts[lessonID] = newValue.isEmpty ? nil : newValue }
    }

    private var canAsk: Bool {
        question.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 && !loading && !paragraphs.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                input
                if loading {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Transkript taranıyor…").foregroundStyle(.secondary)
                    }
                }
                if entries.isEmpty && !loading {
                    Text("Videoda anlatılan bir konuyu sor; cevap yalnızca bu dersin transkriptine dayanır ve ilgili anlara bağlantı verir.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(entries.reversed()) { entry in
                    AskEntryView(entry: entry, onSeek: { time in
                        player.seek(to: time)
                        player.play()
                    }, onCopy: {
                        UIPasteboard.general.string = AskHistory.copyText(entry)
                        notify?(entry.answer == nil ? "Soru kopyalandı" : "Soru ve cevap kopyalandı")
                    }, onDelete: { toDelete = entry.id })
                }
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .confirmationDialog("Bu soru ve cevabı silinsin mi?",
                            isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Sil", role: .destructive) {
                if let toDelete { AskHistory.remove(toDelete, lesson: lessonID) }
                toDelete = nil
            }
        }
        .onAppear { AskHistory.load(lesson: lessonID) }
        .onDisappear {
            // Sesli soru sürerken sekme değişirse o ana dek söylenen taslağa yazılır ("Bitir"e basılmış gibi).
            if recorder.isRecording {
                Task {
                    let text = await recorder.stop()
                    if !text.isEmpty { question = text }
                }
            }
            // Okuma sahipsiz görevle başlar: sekme ya da ders kapanınca sussun.
            SpeechOut.shared.stop()
        }
    }

    private var input: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Ör. Mitoz ile mayoz arasındaki fark ne?", text: Binding(get: { question }, set: { question = $0 }), axis: .vertical)
                .lineLimit(1...4)
                .focused($focused)
                .submitLabel(.send)
                .onSubmit { Task { await ask() } }
                .padding(10)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
            if recorder.isRecording, !recorder.transcript.isEmpty {
                Text(recorder.transcript).font(.caption).foregroundStyle(.secondary)
            }
            if let error = recorder.error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Button {
                    Task {
                        if recorder.isRecording {
                            let text = await recorder.stop()
                            if !text.isEmpty { question = text }
                        } else {
                            focused = false
                            player.pause()
                            await recorder.start()
                        }
                    }
                } label: {
                    Label(recorder.isRecording ? "Bitir" : "Sesli sor", systemImage: recorder.isRecording ? "stop.circle.fill" : "mic.fill")
                }
                .buttonStyle(.bordered)
                .tint(recorder.isRecording ? .red : nil)
                Spacer()
                Button {
                    Task { await ask() }
                } label: {
                    Label("Sor", systemImage: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canAsk)
            }
        }
    }

    private func ask() async {
        if recorder.isRecording {
            let text = await recorder.stop()
            if !text.isEmpty { question = text }
        }
        let asked = question
        let text = asked.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2, !loading, !paragraphs.isEmpty else { return }
        AskHistory.live.inFlight.insert(lessonID)
        focused = false
        defer { AskHistory.live.inFlight.remove(lessonID) }
        // Kare ve ses içermeyen dersin klasörü hiç açılmamış olabilir. Ders şu an ekranda (silinmemiş): klasör burada
        // güvenle açılır; cevap geldiğinde klasör yoksa ders bu arada silinmiştir ve geçmiş diske yazılmaz.
        _ = VideoFiles.directory(for: lessonID)
        let request = YouTubeAskRequest.make(title: title, question: text, paragraphs: paragraphs)
        var entry = AskEntry(question: request.question, askedAt: .now)
        do {
            entry.answer = try await APIClient.shared.youtubeAsk(request)
            // Beklerken yeni bir soru yazılmaya başlandıysa o taslak silinmez.
            if question == asked { question = "" }
        } catch {
            entry.error = error.localizedDescription
        }
        AskHistory.append(entry, lesson: lessonID)
    }
}

private struct AskEntryView: View {
    var entry: AskEntry
    var onSeek: (Double) -> Void
    var onCopy: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(entry.question, systemImage: "person.fill.questionmark")
                .font(.subheadline.weight(.semibold))
            if let answer = entry.answer {
                SpokenText(text: answer.answer.isEmpty ? "Cevap alınamadı." : answer.answer, speech: SpeechOut.shared)
                    .textSelection(.enabled)
                if !answer.citations.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(answer.citations.enumerated()), id: \.offset) { _, citation in
                            Button {
                                onSeek(citation.time)
                            } label: {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    TimeBadgeLabel(time: citation.time)
                                    Text("“\(citation.quote)”")
                                        .font(.callout)
                                        .italic()
                                        .foregroundStyle(.secondary)
                                        .lineLimit(3)
                                        .multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Videoyu bu ana götürür")
                        }
                    }
                }
                if !answer.answer.isEmpty {
                    // `speak` aynı metin okunurken yeniden istenince durdurur: düğme durumu göstersin.
                    let reading = SpeechOut.shared.isSpeaking && SpeechOut.shared.spokenText == answer.answer
                    Button(reading ? "Durdur" : "Sesli oku", systemImage: reading ? "stop.circle" : "speaker.wave.2") {
                        Task { await SpeechOut.shared.speak(answer.answer) }
                    }
                    .font(.caption)
                }
            } else if let error = entry.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .contextMenu {
            Button("Kopyala", systemImage: "doc.on.doc", action: onCopy)
            Button("Sil", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }
}

/// Tam ekran okuma: transkript + küçük oynatma çubuğu (video/ses arka planda çalmaya devam eder).
struct VideoReaderView: View {
    var transcript: VideoTranscript
    var player: VideoPlayerModel
    var notify: (String) -> Void
    var onAddCard: (TranscriptRow) -> Void
    var onAddNote: (TranscriptRow) -> Void
    var lessonID: UUID? = nil
    var onCorrectTerm: ((String, String) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.down").font(.title3.weight(.semibold))
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("Okuma modundan çık")
                Spacer()
                Text(transcript.video.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            // 44 pt'lik dokunma alanı eski kenar boşluklarının yerini alır: simge aynı yerde, çubuk aynı yükseklikte.
            .padding(.horizontal, 4)
            TranscriptTab(transcript: transcript, player: player, notify: notify, onAddCard: onAddCard, onAddNote: onAddNote, compact: true,
                          lessonID: lessonID, onCorrectTerm: onCorrectTerm)
            ReaderTransportBar(
                timeText: TranscriptFormat.timestamp(player.currentTime),
                progress: player.duration > 0 ? player.currentTime / player.duration : 0,
                isPlaying: player.isPlaying,
                rateText: String(format: "%g×", player.rate),
                rates: VideoPlayerModel.rates,
                back: { player.skip(-15) },
                toggle: { player.togglePlay() },
                forward: { player.skip(30) },
                setRate: { player.rate = $0 },
                currentRate: player.rate)
        }
        .pinnedToScreenWidth()
        .background(Color(.systemBackground))
        .debugNarrowScreen()
    }
}
