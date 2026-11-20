import SwiftData
import SwiftUI

/// Elle eklenen kartların ait olduğu sanal "bölüm".
enum ManualCards {
    static let deckID = UUID(uuidString: "00000000-0000-0000-0000-00000000C0DE") ?? UUID()
    static let deckTitle = "Kendi kartlarım"
}

// MARK: - Kart tarayıcı

struct CardBrowserView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ReviewCard.createdAt, order: .reverse) private var cards: [ReviewCard]
    @State private var query = ""
    @State private var filter = Filter.all
    @State private var editing: ReviewCard?

    enum Filter: String, CaseIterable, Identifiable {
        case all = "Tümü", due = "Zamanı gelen", weak = "Zayıf", manual = "Kendi kartlarım", books = "Kitaplardan"
        var id: String { rawValue }
    }

    init(filter: Filter = .all) {
        _filter = State(initialValue: filter)
    }

    private var shown: [ReviewCard] {
        let needle = AnswerMatch.normalize(query)
        return cards.filter { card in
            switch filter {
            case .all: true
            case .due: card.isDue
            case .weak: card.isWeak
            case .manual: card.episodeID == ManualCards.deckID
            case .books: card.sourceBookID != nil
            }
        }
        .filter { needle.isEmpty || AnswerMatch.normalize($0.front + " " + $0.back + " " + $0.episodeTitle).contains(needle) }
    }

    var body: some View {
        ToolScaffold(title: "Kartlarım") {
            List {
                Picker("Süzgeç", selection: $filter) { ForEach(Filter.allCases) { Text($0.rawValue).tag($0) } }
                Section("\(shown.count) kart") {
                    ForEach(shown) { card in
                        Button { editing = card } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(card.front).font(.subheadline.weight(.semibold)).lineLimit(3)
                                Text(card.back).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                                Text("\(card.episodeTitle) · \(card.isDue ? "tekrar zamanı" : "sıradaki \(card.due.formatted(date: .abbreviated, time: .omitted))")")
                                    .font(.caption2).foregroundStyle(card.isDue ? .orange : .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .swipeActions { Button("Sil", role: .destructive) { context.delete(card); try? context.save() } }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Kartlarda ara")
            .sheet(item: $editing) { CardEditor(card: $0) }
        }
    }
}

private struct CardEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var card: ReviewCard
    @State private var showBookSource = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Ön yüz") { TextField("Soru", text: $card.front, axis: .vertical) }
                Section("Arka yüz") { TextField("Cevap", text: $card.back, axis: .vertical) }
                if card.sourceBookID != nil, let page = card.sourcePage {
                    Section("Kitap kaynağı") {
                        Text(card.episodeTitle).font(.subheadline)
                        Button("Kitapta aç · sayfa \(page)", systemImage: "book") { showBookSource = true }
                            .frame(minHeight: 44)
                    }
                }
                Section("Durum") {
                    LabeledContent("Aralık", value: "\(card.intervalDays) gün")
                    LabeledContent("Tekrar sayısı", value: "\(card.repetitions)")
                    LabeledContent("Bilemedim", value: "\(card.lapses)")
                    Button("Bugün tekrar sor") { card.due = .now }
                }
            }
            .navigationTitle("Kart")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { try? context.save(); dismiss() } } }
            .debugNarrowScreen()
            .fullScreenCover(isPresented: $showBookSource) {
                if let bookID = card.sourceBookID, let page = card.sourcePage {
                    BookSourceView(bookID: bookID, title: card.episodeTitle, page: page)
                }
            }
        }
    }
}

// MARK: - Kart ekle / içe aktar

struct CardCreateView: View {
    @Environment(\.modelContext) private var context
    /// Elle eklenen kartlar: kopya denetimi ve "geri al" için.
    @Query private var manualCards: [ReviewCard]
    @AppStorage("tools.cards.deck") private var deck = ""
    @State private var front = ""
    @State private var back = ""
    @State private var bulk = ""
    @State private var added = 0
    /// Son eklemede oluşan kartlar (yanlış aktarma geri alınabilsin).
    @State private var lastBatch: [UUID] = []
    /// Son toplu eklemede metin alanının önceki ve sonraki hâli: geri alınınca liste düzeltilmek üzere geri gelir.
    @State private var lastBulk: (before: String, after: String)?
    @State private var confirmUndo = false
    /// Elle eklenmiş kartların kopya anahtarları; gövdede değil, kart sayısı değişince hesaplanır (binlerce kartlı destede her tuş vuruşu bütün desteyi dolaşmasın).
    @State private var existingKeys: Set<String> = []

    init() {
        let deckID = ManualCards.deckID
        _manualCards = Query(filter: #Predicate<ReviewCard> { $0.episodeID == deckID })
    }

    var body: some View {
        let outcome = bulk.isEmpty ? CardImport.Outcome() : CardImport.analyze(bulk, existing: existingKeys)
        ToolScaffold(title: "Kart ekle") {
            Form {
                Section("Deste (isteğe bağlı)") { TextField(ManualCards.deckTitle, text: $deck) }
                Section("Tek kart") {
                    TextField("Ön yüz (soru)", text: $front, axis: .vertical)
                    TextField("Arka yüz (cevap)", text: $back, axis: .vertical)
                    Button("Kartı ekle") {
                        add([CardImport.Pair(front: front.trimmingCharacters(in: .whitespacesAndNewlines), back: back.trimmingCharacters(in: .whitespacesAndNewlines))])
                        lastBulk = nil
                        front = ""; back = ""
                    }
                    .disabled(front.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || back.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Section {
                    TextEditor(text: $bulk).frame(minHeight: 120).font(.callout)
                    Button("Panodan yapıştır", systemImage: "doc.on.clipboard") { bulk = UIPasteboard.general.string ?? bulk }
                    Button("\(outcome.cards.count) kartı ekle") {
                        // Okunamayan satırlar alanda kalır: düzeltilip yeniden eklenebilir.
                        let rest = outcome.skipped.joined(separator: "\n")
                        add(outcome.cards)
                        lastBulk = (bulk, rest)
                        bulk = rest
                    }
                    .disabled(outcome.cards.isEmpty)
                    if !bulk.isEmpty {
                        Text(Self.summary(outcome)).font(.footnote).foregroundStyle(.secondary)
                        if !outcome.skipped.isEmpty {
                            Label {
                                Text(outcome.skipped.prefix(3).joined(separator: "\n") + (outcome.skipped.count > 3 ? "\n… ve \(outcome.skipped.count - 3) satır daha" : ""))
                            } icon: {
                                Image(systemName: "exclamationmark.triangle.fill")
                            }
                            .font(.caption).foregroundStyle(.orange)
                        }
                    }
                } header: {
                    Text("Toplu ekle")
                } footer: {
                    Text("Her satır bir kart: “mitokondri ; hücrenin enerji santrali”. Ayırıcı olarak ; = - : ya da sekme kullanılabilir (Excel, Quizlet, Anki dışa aktarımı). Tire ayırıcı sayılsın diye iki yanında boşlukla yazılır. Kendi kartlarında zaten olan kart yeniden eklenmez.")
                }
                if added > 0 { Section { Label("\(added) kart eklendi; Aralıklı tekrar'da karşına çıkacak.", systemImage: "checkmark.circle.fill").foregroundStyle(.green) } }
                if !lastBatch.isEmpty {
                    Section { Button("Son eklenen \(lastBatch.count) kartı geri al", systemImage: "arrow.uturn.backward", role: .destructive) { confirmUndo = true } }
                }
            }
            // Aşağı çekmek yazılanı silmesin ("Kapat" yine çalışır).
            .interactiveDismissDisabled(!bulk.isEmpty || !front.isEmpty || !back.isEmpty)
            // Ekran kipli (sheet) olduğundan açıkken deste yalnız buradaki ekleme/geri almayla değişir; ikisi de kart sayısını değiştirir.
            .onChange(of: manualCards.count, initial: true) { existingKeys = Set(manualCards.map { CardImport.key(front: $0.front, back: $0.back) }) }
            .confirmationDialog("Son eklenen \(lastBatch.count) kart silinsin mi?", isPresented: $confirmUndo, titleVisibility: .visible) {
                Button("Kartları sil", role: .destructive) { undoLastBatch() }
                Button("Vazgeç", role: .cancel) {}
            } message: {
                if lastBulk != nil { Text("Liste, düzeltip yeniden ekleyebilmen için metin alanına geri gelir.") }
            }
        }
    }

    private static func summary(_ outcome: CardImport.Outcome) -> String {
        var parts = ["\(outcome.cards.count) kart hazır"]
        if !outcome.skipped.isEmpty { parts.append("\(outcome.skipped.count) satır okunamadı") }
        if outcome.duplicates > 0 { parts.append("\(outcome.duplicates) kopya atlanacak") }
        return parts.joined(separator: " · ")
    }

    private func add(_ pairs: [CardImport.Pair]) {
        let title = deck.trimmingCharacters(in: .whitespaces)
        var ids: [UUID] = []
        for pair in pairs {
            let card = ReviewCard(episodeID: ManualCards.deckID, episodeTitle: title.isEmpty ? ManualCards.deckTitle : title, kind: .flashcard,
                                  front: pair.front, back: pair.back, sourcePage: nil)
            card.origin = "manual"
            context.insert(card)
            ids.append(card.id)
        }
        try? context.save()
        added += pairs.count
        lastBatch = ids
    }

    private func undoLastBatch() {
        let ids = Set(lastBatch)
        let batch = manualCards.filter { ids.contains($0.id) }
        for card in batch { context.delete(card) }
        try? context.save()
        added = max(0, added - batch.count)
        lastBatch = []
        // Alan eklemeden beri değişmediyse liste geri gelir; kullanıcı yeni bir şey yazdıysa ezilmez.
        if let lastBulk, bulk == lastBulk.after { bulk = lastBulk.before }
        lastBulk = nil
    }
}

// MARK: - Yazarak tekrar

struct TypeReviewView: View {
    @Environment(\.modelContext) private var context
    @Query private var cards: [ReviewCard]
    @State private var session: [ReviewCard] = []
    @State private var round = ReviewRound<UUID>(ids: [])
    /// Bilinemeyenlerle açılan tekrar turu: alıştırmadır, kartların aralığını ve kayıtları değiştirmez.
    @State private var practiceOnly = false
    @State private var typed = ""
    @State private var verdict: AnswerMatch.Verdict?
    @FocusState private var focused: Bool

    private var currentCard: ReviewCard? { round.current.flatMap { id in session.first { $0.id == id } } }

    var body: some View {
        ToolScaffold(title: "Yazarak tekrar") {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if session.isEmpty {
                        let due = cards.filter(\.isDue).count
                        Text("Cevabı görmeden önce yazarsın; yazmak hatırlamayı zorlaştırır ve kalıcılığı artırır.").foregroundStyle(.secondary)
                        Text(cards.isEmpty ? "Henüz kartın yok." : due > 0 ? "\(due) kartın tekrar zamanı gelmiş." : "Zamanı gelen kart yok; istersen rastgele 10 kartla çalış.")
                        Button(due > 0 ? "Başla" : "Rastgele 10 kart") {
                            let pool = due > 0 ? cards.filter(\.isDue) : cards
                            session = Array(pool.shuffled().prefix(due > 0 ? 20 : 10))
                            round = ReviewRound(ids: session.map(\.id))
                            practiceOnly = false; typed = ""; verdict = nil; focused = true
                        }
                        .buttonStyle(PrimaryButtonStyle(enabled: !cards.isEmpty)).disabled(cards.isEmpty)
                    } else if let card = currentCard {
                        ProgressView(value: Double(round.index), total: Double(round.ids.count))
                        Text(practiceOnly ? "Alıştırma turu · kart aralıkları değişmez" : card.episodeTitle).font(.caption).foregroundStyle(.secondary)
                        Text(card.front).font(.title3.weight(.semibold))
                        TextField("Cevabını yaz", text: $typed, axis: .vertical)
                            .textFieldStyle(.roundedBorder).focused($focused).disabled(verdict != nil)
                            .submitLabel(.done)
                            .onAppear { focused = true }
                            .autocorrectionDisabled()
                            // Her kartta taze alan: önceki kartta devre dışı kalan alan odağı düşürmesin.
                            .id(card.id)
                            .onChange(of: typed) { _, value in
                                // Dikey alanda Return yeni satır ekler; "Kontrol et" sayılır.
                                guard verdict == nil, value.contains(where: \.isNewline) else { return }
                                typed = value.split(whereSeparator: \.isNewline).joined(separator: " ")
                                check()
                            }
                        if let verdict {
                            VStack(alignment: .leading, spacing: 6) {
                                Label(verdict == .exact ? "Doğru" : verdict == .close ? "Çok yakın" : "Farklı", systemImage: verdict == .wrong ? "xmark.circle.fill" : "checkmark.circle.fill")
                                    .font(.headline).foregroundStyle(verdict == .exact ? .green : verdict == .close ? .orange : .red)
                                Text("Beklenen cevap").font(.caption).foregroundStyle(.secondary)
                                Text(card.back)
                            }
                            Text("Kendini değerlendir").font(.caption).foregroundStyle(.secondary)
                            ForEach(ReviewGrade.allCases, id: \.self) { grade in
                                if grade == suggestion(verdict) {
                                    Button(grade.title) { apply(grade, to: card) }.buttonStyle(.borderedProminent).frame(maxWidth: .infinity, alignment: .leading)
                                } else {
                                    Button(grade.title) { apply(grade, to: card) }.buttonStyle(.bordered).frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        } else {
                            Button("Kontrol et") { check() }.buttonStyle(PrimaryButtonStyle())
                            Button("Bilmiyorum, göster") { reveal() }.buttonStyle(.bordered)
                        }
                    } else {
                        finished
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            // Soru uzunken ekrandaki düğmeler klavyenin arkasında kalır: aynı işlemler klavye çubuğunda.
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Button("Bilmiyorum") { reveal() }
                    Spacer()
                    Button("Kontrol et") { check() }.bold()
                }
            }
        }
    }

    /// Tur sonu: sonuç, bilinemeyen kartlar ve yalnız onlarla yeni tur.
    @ViewBuilder private var finished: some View {
        let missed = round.missed.compactMap { id in session.first { $0.id == id } }
        Label("Tur bitti", systemImage: "checkmark.seal.fill").font(.title2.bold()).foregroundStyle(.green)
        Text("\(round.ids.count) karttan \(round.correct) tanesini doğru yazdın.")
        if practiceOnly { Text("Bu tur alıştırmaydı; kartların tekrar aralığı değişmedi.").font(.footnote).foregroundStyle(.secondary) }
        if missed.isEmpty {
            Button("Yeni tur") { session = [] }.buttonStyle(PrimaryButtonStyle())
        } else {
            Text("Bilemediklerin").font(.headline)
            ForEach(missed) { card in
                VStack(alignment: .leading, spacing: 3) {
                    Text(card.front).font(.subheadline.weight(.semibold))
                    Label(card.back, systemImage: "arrow.turn.down.right").font(.footnote).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
            }
            Button("Bilemediklerimi tekrar çalış (\(missed.count))") {
                round = round.retry()
                practiceOnly = true; typed = ""; verdict = nil
                focusSoon()
            }
            .buttonStyle(PrimaryButtonStyle())
            Button("Yeni tur") { session = [] }.buttonStyle(.bordered)
        }
    }

    private func suggestion(_ verdict: AnswerMatch.Verdict) -> ReviewGrade {
        switch verdict {
        case .exact: .good
        case .close: .hard
        case .wrong: .again
        }
    }

    private func check() {
        guard verdict == nil, let card = currentCard else { return }
        verdict = AnswerMatch.verdict(typed: typed, expected: card.back)
        focused = false
    }

    private func reveal() {
        guard verdict == nil, currentCard != nil else { return }
        verdict = .wrong
        focused = false
    }

    private func apply(_ grade: ReviewGrade, to card: ReviewCard) {
        // Alıştırma turu zamanlamaya yazılmaz: aynı gün ikinci notlama aralığı şişirmesin, hatırlama kaydı çiftlenmesin.
        if !practiceOnly {
            card.reviewWithMemory(grade, retention: LearningAdaptiveReview.target(for: card))
            try? context.save()
            RecallLog.record(RecallLog.Entry(source: "review", question: card.front, isCorrect: grade != .again,
                                             chapterIndex: card.chapterIndex, cardID: card.id),
                             episodeID: card.episodeID, episodeTitle: card.episodeTitle, context: context)
        }
        round.record(correct: grade != .again)
        typed = ""; verdict = nil
        if !round.isFinished { focusSoon() }
    }

    /// Alan bu güncellemede hâlâ devre dışı: odak bir sonraki döngüde verilir (yoksa düşer, klavye kapanır).
    private func focusSoon() {
        Task { @MainActor in focused = true }
    }
}

// MARK: - Eşleştirme oyunu

struct MatchGameView: View {
    @Query private var cards: [ReviewCard]
    @AppStorage("tools.match.best") private var best = 0.0
    @State private var tiles: [Tile] = []
    @State private var picked: [Int] = []
    @State private var matched: Set<UUID> = []
    @State private var wrongPair: Set<Int> = []
    @State private var startedAt: Date?
    @State private var finishedIn: Double?
    @State private var moves = 0
    @State private var tooFew = false

    struct Tile: Identifiable { var id = UUID(); var cardID: UUID; var text: String }

    /// Kısa kartlar: kutucuğa sığsın.
    private var usable: [ReviewCard] { cards.filter { $0.front.count <= 80 && $0.back.count <= 80 && !$0.front.isEmpty && !$0.back.isEmpty } }

    var body: some View {
        ToolScaffold(title: "Eşleştirme") {
            ScrollView {
                VStack(spacing: 14) {
                    if tiles.isEmpty {
                        Text("Sorularla cevaplarını eşleştir. Kartların kendi tekrar kartlarından gelir.").foregroundStyle(.secondary)
                        if let finishedIn {
                            Label("\(Int(finishedIn.rounded())) saniyede, \(moves) hamlede bitti", systemImage: "flag.checkered").font(.headline)
                        }
                        if best > 0 { Text("En iyi süre: \(Int(best.rounded())) sn").font(.subheadline).foregroundStyle(.secondary) }
                        if usable.count < 4 || tooFew {
                            Text("Oyun için en az 4 kısa kart gerekiyor.").foregroundStyle(.orange)
                        } else {
                            Button("Oyunu başlat") { start() }.buttonStyle(PrimaryButtonStyle())
                        }
                    } else {
                        TimelineView(.periodic(from: .now, by: 1)) { timeline in
                            Text("Süre \((startedAt.map { timeline.date.timeIntervalSince($0) } ?? 0).clockText) · hamle \(moves)")
                                .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], spacing: 8) {
                            ForEach(Array(tiles.enumerated()), id: \.element.id) { i, tile in
                                let done = matched.contains(tile.cardID)
                                Button { tap(i) } label: {
                                    Text(tile.text).font(.footnote.weight(.medium)).multilineTextAlignment(.center)
                                        .lineLimit(5).minimumScaleFactor(0.75)
                                        .padding(8).frame(maxWidth: .infinity, minHeight: 84)
                                        .background(done ? Color.green.opacity(0.25) : wrongPair.contains(i) ? Color.red.opacity(0.3)
                                                    : picked.contains(i) ? Color.accentColor.opacity(0.3) : Color.gray.opacity(0.15),
                                                    in: RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain).disabled(done).opacity(done ? 0.45 : 1)
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    private func start() {
        // Aynı metinli iki kart (örn. iki "Doğru") doğru eşleşmeyi yanlış saydırır: metne göre tekilleştir.
        var seen = Set<String>()
        let chosen = usable.shuffled().filter { card in
            let front = AnswerMatch.normalize(card.front), back = AnswerMatch.normalize(card.back)
            guard front != back, !seen.contains(front), !seen.contains(back) else { return false }
            seen.insert(front); seen.insert(back)
            return true
        }.prefix(6)
        guard chosen.count >= 4 else { tooFew = true; return }
        tiles = (chosen.map { Tile(cardID: $0.id, text: $0.front) } + chosen.map { Tile(cardID: $0.id, text: $0.back) }).shuffled()
        picked = []; matched = []; wrongPair = []; moves = 0; finishedIn = nil; startedAt = .now
    }

    private func tap(_ i: Int) {
        guard wrongPair.isEmpty, !picked.contains(i) else { return }
        picked.append(i)
        guard picked.count == 2 else { return }
        moves += 1
        let pair = picked
        picked = []
        if tiles[pair[0]].cardID == tiles[pair[1]].cardID {
            matched.insert(tiles[pair[0]].cardID)
            if matched.count * 2 == tiles.count {
                let seconds = startedAt.map { Date.now.timeIntervalSince($0) } ?? 0
                finishedIn = seconds
                if best == 0 || seconds < best { best = seconds }
                tiles = []
            }
        } else {
            wrongPair = Set(pair)
            Task {
                try? await Task.sleep(for: .milliseconds(600))
                wrongPair = []
            }
        }
    }
}
