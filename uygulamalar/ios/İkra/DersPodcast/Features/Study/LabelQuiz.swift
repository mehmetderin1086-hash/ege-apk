import SwiftData
import SwiftUI
import Vision

/// Kesilmiş kaynak şeklindeki etiketler (Kornea, İris, Retina…) cihazda OCR ile bulunur ve maskelenir;
/// öğrenci dokunup yazar ya da söyler. Yanlışlar deftere, sonuçlar aralıklı tekrara girer.
nonisolated struct FigureLabel: Codable, Hashable, Sendable, Identifiable {
    var id: Int
    var text: String
    /// Görüntü içinde 0…1, sol üst köken.
    var box: CGRect
}

nonisolated enum LabelDetector {
    /// Etiket adayları: 2–28 karakter, harf içeren, çok uzun olmayan satırlar (başlık/cümle değil).
    @concurrent
    static func detect(_ image: UIImage) async -> [FigureLabel] {
        guard let cg = image.cgImage else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["tr-TR", "en-US"]
        request.usesLanguageCorrection = false
        try? VNImageRequestHandler(cgImage: cg, orientation: .up).perform([request])
        var labels: [FigureLabel] = []
        for obs in request.results ?? [] {
            guard let best = obs.topCandidates(1).first, best.confidence > 0.4 else { continue }
            let text = clean(best.string)
            guard isLabel(text) else { continue }
            let b = obs.boundingBox   // sol alt köken
            labels.append(FigureLabel(id: labels.count, text: text, box: CGRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height)))
        }
        return labels
    }

    static func clean(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "-–:•·()"))
    }

    static func isLabel(_ text: String) -> Bool {
        let letters = text.filter(\.isLetter).count
        guard letters >= 2, text.count <= 28, letters * 2 >= text.count else { return false }
        if text.lowercased().hasPrefix("görsel") || text.lowercased().hasPrefix("şekil") { return false }   // şekil başlığı
        return text.split(separator: " ").count <= 3
    }

    /// Cevap karşılaştırma: küçük harf, Türkçe aksan katlama, parantez içi atılır; %80 benzerlik yeter.
    static func matches(_ answer: String, expected: String) -> Bool {
        let a = fold(answer), e = fold(expected)
        guard !a.isEmpty, !e.isEmpty else { return false }
        if a == e || e.contains(a) && a.count >= max(3, e.count * 2 / 3) { return true }
        return similarity(a, e) >= 0.8
    }

    static func fold(_ s: String) -> String {
        var t = s.lowercased()
        if let i = t.firstIndex(of: "(") { t = String(t[..<i]) }
        t = t.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "tr"))
        t = t.replacingOccurrences(of: "ı", with: "i")
        return t.filter { $0.isLetter || $0 == " " }.trimmingCharacters(in: .whitespaces)
    }

    /// 1 − Levenshtein / uzunluk.
    static func similarity(_ a: String, _ b: String) -> Double {
        let x = Array(a), y = Array(b)
        if x.isEmpty || y.isEmpty { return 0 }
        var prev = Array(0...y.count)
        for i in 1...x.count {
            var cur = [i] + Array(repeating: 0, count: y.count)
            for j in 1...y.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
            }
            prev = cur
        }
        return 1 - Double(prev[y.count]) / Double(max(x.count, y.count))
    }
}

/// #33: etiket kartı. Ön yüz numarayı taşır; tekrar ekranı şekli aynı önbellekteki kutularla maskeler.
nonisolated enum LabelCard {
    static func front(caption: String, number: Int) -> String {
        "Şekil: \(caption.isEmpty ? "kaynak şekli" : caption) — \(number) numaralı yapı nedir?"
    }

    /// Ön yüzden etiket numarası (1'den başlar); etiket kartı değilse nil.
    static func number(from front: String) -> Int? {
        guard front.hasPrefix("Şekil: "), let tail = front.range(of: " numaralı yapı nedir?", options: [.backwards, .anchored]),
              let dash = front[..<tail.lowerBound].range(of: "— ", options: .backwards),
              let n = Int(front[dash.upperBound..<tail.lowerBound]), n > 0 else { return nil }
        return n
    }

    /// LabelQuiz'in OCR önbelleği (`labels_<şekil>.json`).
    static func cacheURL(episodeID: UUID, figureID: String) -> URL {
        EpisodeFiles.directory(for: episodeID).appending(path: "labels_\(figureID).json")
    }

    static func cachedLabels(episodeID: UUID, figureID: String) -> [FigureLabel] {
        guard let data = try? Data(contentsOf: cacheURL(episodeID: episodeID, figureID: figureID)),
              let labels = try? JSONDecoder().decode([FigureLabel].self, from: data) else { return [] }
        return labels
    }

    /// Karttaki numaranın kutusu; kutu metni kartın cevabıyla uyuşmazsa (önbellek değişmiş) nil: yanlış yer vurgulanmaz.
    static func target(in labels: [FigureLabel], number: Int?, answer: String) -> FigureLabel? {
        guard let number, let label = labels.first(where: { $0.id == number - 1 }),
              LabelDetector.fold(label.text) == LabelDetector.fold(answer) else { return nil }
        return label
    }
}

struct LabelQuizView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    var episode: Episode
    @State private var figures: [SourceFigure] = []
    @State private var figureIndex = 0
    @State private var image: UIImage?
    @State private var labels: [FigureLabel] = []
    @State private var revealed: Set<Int> = []
    @State private var wrong: Set<Int> = []
    @State private var active: FigureLabel?
    @State private var loading = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if figures.isEmpty {
                    ContentUnavailableView("Kaynak şekli yok", systemImage: "photo",
                                           description: Text("Deste ekranından kitap sayfası fotoğrafı ekle; şekiller kesilince burada çalışabilirsin."))
                } else {
                    Picker("Şekil", selection: $figureIndex) {
                        ForEach(Array(figures.enumerated()), id: \.offset) { i, f in Text(f.caption.isEmpty ? "Şekil \(i + 1)" : String(f.caption.prefix(28))).tag(i) }
                    }
                    .pickerStyle(.menu)
                    if let image {
                        GeometryReader { geo in
                            let fit = fitRect(image.size, in: geo.size)
                            ZStack(alignment: .topLeading) {
                                Image(uiImage: image).resizable().interpolation(.high).scaledToFit().frame(width: geo.size.width, height: geo.size.height)
                                ForEach(labels) { label in
                                    let r = CGRect(x: fit.minX + label.box.minX * fit.width, y: fit.minY + label.box.minY * fit.height,
                                                   width: label.box.width * fit.width, height: label.box.height * fit.height)
                                    Button { active = label } label: {
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(revealed.contains(label.id) ? (wrong.contains(label.id) ? Color.red.opacity(0.25) : Color.green.opacity(0.25)) : Color.accentColor)
                                            .overlay {
                                                if !revealed.contains(label.id) {
                                                    Text("\(label.id + 1)").font(.system(size: max(9, min(16, r.height * 0.7)), weight: .bold)).foregroundStyle(.white)
                                                }
                                            }
                                    }
                                    .buttonStyle(.plain)
                                    .frame(width: max(r.width + 8, 22), height: max(r.height + 6, 18))
                                    .position(x: r.midX, y: r.midY)
                                    .disabled(revealed.contains(label.id))
                                }
                            }
                        }
                        .frame(maxHeight: 420)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        HStack {
                            Text(labels.isEmpty ? (loading ? "Etiketler aranıyor…" : "Bu şekilde okunabilir etiket bulunamadı.") : "\(revealed.count)/\(labels.count) etiket · \(wrong.count) yanlış")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Hepsini göster") { revealed = Set(labels.map(\.id)) }.font(.caption).disabled(labels.isEmpty)
                        }
                        .padding(.horizontal, 4)
                    } else if loading {
                        ProgressView("Şekil yükleniyor…")
                    }
                }
                Spacer()
            }
            .padding(16)
            .navigationTitle("Etiketleri tahmin et")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } } }
            .task { figures = episode.sourceFigures }
            // Şekil değişince önceki yükleme iptal edilir; sonuç yalnızca hâlâ aynı şekil seçiliyse yazılır.
            .task(id: "\(figures.count)-\(figureIndex)") { await load(index: figureIndex) }
            .sheet(item: $active) { label in
                LabelAnswerSheet(number: label.id + 1) { answer in check(label, answer: answer) }
                    .presentationDetents([.height(260)])
            }
        }
    }

    private func fitRect(_ size: CGSize, in container: CGSize) -> CGRect {
        let scale = min(container.width / size.width, container.height / size.height)
        let w = size.width * scale, h = size.height * scale
        return CGRect(x: (container.width - w) / 2, y: (container.height - h) / 2, width: w, height: h)
    }

    private func load(index: Int) async {
        guard let figure = figures[safe: index] else { return }
        loading = true
        revealed = []; wrong = []; labels = []; image = nil
        defer { if index == figureIndex { loading = false } }
        let loaded = await DeckAssets.thumbnail(episode.figureURL(figure.id))
        guard !Task.isCancelled, index == figureIndex, let loaded else { return }
        image = loaded
        let cache = LabelCard.cacheURL(episodeID: episode.id, figureID: figure.id)
        if let data = try? Data(contentsOf: cache), let cached = try? JSONDecoder().decode([FigureLabel].self, from: data), !cached.isEmpty {
            labels = cached
            return
        }
        // Etiket tespiti tam çözünürlükte (küçük yazılar için).
        guard let full = UIImage(contentsOfFile: episode.figureURL(figure.id).path) else { return }
        let found = await LabelDetector.detect(full)
        guard !Task.isCancelled, index == figureIndex else { return }
        labels = found
        if !found.isEmpty { try? JSONEncoder().encode(found).write(to: cache) }   // boş sonuç önbelleğe yazılmaz
    }

    private func check(_ label: FigureLabel, answer: String) {
        guard let figure = figures[safe: figureIndex] else { return }
        let ok = LabelDetector.matches(answer, expected: label.text)
        revealed.insert(label.id)
        if !ok {
            wrong.insert(label.id)
            MistakeBook.recordLabel(expected: label.text, given: answer, figureCaption: figure.caption, episode: episode, context: context)
        }
        // Aralıklı tekrar kartı: şekil + etiket numarası benzersiz; yanlışsa hemen tekrar, doğruysa 3 gün sonra.
        let front = LabelCard.front(caption: figure.caption, number: label.id + 1)
        let back = label.text
        let existing = (try? context.fetch(FetchDescriptor<ReviewCard>(predicate: #Predicate { $0.front == front && $0.back == back })))?.first
        let card = existing ?? {
            let c = ReviewCard(episodeID: episode.id, episodeTitle: episode.title, kind: .flashcard, front: front, back: back, sourcePage: figure.page)
            context.insert(c)
            return c
        }()
        // #33: kart şekliyle gelir (tekrar ekranı şekli gösterir).
        if card.figureID == nil { card.figureID = figure.id }
        card.due = ok ? max(card.due, Calendar.current.date(byAdding: .day, value: 3, to: .now) ?? .now) : .now
        try? context.save()
        RecallLog.record(RecallLog.Entry(source: "quiz", question: front, answerText: answer, isCorrect: ok, cardID: card.id),
                         episode: episode, context: context)
    }
}

/// Etiket cevabı: yaz ya da söyle (alert içinde ses kaydı çalışmadığı için ayrı sayfa).
struct LabelAnswerSheet: View {
    @Environment(\.dismiss) private var dismiss
    var number: Int
    var onAnswer: (String) -> Void
    @State private var answer = ""
    @State private var recorder = SpeechRecorder()
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 14) {
            Text("\(number) numaralı yapı nedir?").font(.headline)
            HStack {
                TextField("Cevabın", text: $answer).textFieldStyle(.roundedBorder).focused($focused).onSubmit(submit)
                Button {
                    Task {
                        if recorder.isRecording { answer = await recorder.stop() } else { focused = false; await recorder.start() }
                    }
                } label: {
                    Image(systemName: recorder.isRecording ? "stop.circle.fill" : "mic.circle.fill").font(.system(size: 34))
                        .foregroundStyle(recorder.isRecording ? .red : .accentColor)
                }
            }
            if recorder.isRecording { Text(recorder.transcript.isEmpty ? "Dinliyorum…" : recorder.transcript).font(.caption).foregroundStyle(.secondary) }
            HStack {
                Button("Vazgeç", role: .cancel) { dismiss() }
                Spacer()
                Button("Cevapla", action: submit).buttonStyle(.borderedProminent).disabled(answer.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .onAppear { focused = true }
        .onDisappear { if recorder.isRecording { Task { _ = await recorder.stop() } } }
    }

    private func submit() {
        onAnswer(answer)
        dismiss()
    }
}
