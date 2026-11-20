import SwiftUI
import Vision

// #10: Karelerdeki (tahta/slayt) yazılar Vision ile tanınır; sonuç ders klasöründe `frame_text.json`.

nonisolated struct FrameRef: Hashable, Sendable {
    var id: String
    var time: Double
}

nonisolated enum FrameTextStore {
    static let fileName = "frame_text.json"
    static let preferredLanguages = ["tr-TR", "en-US"]

    struct Entry: Codable, Hashable, Sendable, Identifiable {
        var id: String
        var time: Double
        /// Tanınan yazı; kareden yazı çıkmadıysa boş (yeniden taranmasın diye yine de kaydedilir).
        var text: String
    }

    /// Yan etkisiz yol (klasör oluşturmaz).
    static func fileURL(lesson id: UUID) -> URL {
        URL.applicationSupportDirectory.appending(path: "Videos", directoryHint: .isDirectory)
            .appending(path: id.uuidString, directoryHint: .isDirectory)
            .appending(path: fileName)
    }

    static func load(lesson id: UUID) -> [Entry] {
        (try? Data(contentsOf: fileURL(lesson: id))).flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
    }

    static func save(_ entries: [Entry], lesson id: UUID) {
        _ = VideoFiles.directory(for: id)
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL(lesson: id), options: .atomic)
    }

    // MARK: Saf yardımcılar

    /// Gürültüyü atar: iki harften kısa satırlar çıkar, boşluklar sadeleşir; toplam çok kısaysa boş döner.
    static func cleaned(_ text: String) -> String {
        let lines = text.split(whereSeparator: \.isNewline).map { line in
            line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }.filter { line in line.filter { $0.isLetter || $0.isNumber }.count >= 2 }
        let joined = lines.joined(separator: "\n")
        return joined.filter { $0.isLetter || $0.isNumber }.count >= 3 ? joined : ""
    }

    /// Kimliğe göre birleştirir (yeni kayıt eskinin yerine geçer), zamana göre sıralar.
    static func merge(existing: [Entry], new: [Entry]) -> [Entry] {
        var byID: [String: Entry] = [:]
        for entry in existing + new { byID[entry.id] = entry }
        return byID.values.sorted { $0.time != $1.time ? $0.time < $1.time : $0.id < $1.id }
    }

    /// Yazı çıkan kayıtlar.
    static func nonEmpty(_ entries: [Entry]) -> [Entry] { entries.filter { !$0.text.isEmpty } }

    // MARK: Tanıma

    /// Tek görsel için yazı (eşzamanlı, ağır: ana iş parçacığında çağırma). Hata → boş.
    static func recognizeText(at url: URL) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        // Desteklenmeyen dil istemek hata verir: yalnız desteklenenler istenir; hiçbiri yoksa otomatik algılama.
        let supported = (try? request.supportedRecognitionLanguages()) ?? []
        let wanted = preferredLanguages.filter { supported.contains($0) }
        if wanted.isEmpty {
            request.automaticallyDetectsLanguage = true
        } else {
            request.recognitionLanguages = wanted
        }
        do {
            try VNImageRequestHandler(url: url).perform([request])
        } catch {
            return ""
        }
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return cleaned(lines.joined(separator: "\n"))
    }

    /// Tanıma işleri tek seri, düşük öncelikli kuyrukta çalışır: Vision çağrıları eşzamanlıdır ve Swift eşzamanlılık iş havuzunu
    /// (indirme, kayıt, ağ işleri) bloke etmemelidir.
    private static let ocrQueue = DispatchQueue(label: "derspodcast.frame-ocr", qos: .utility)

    nonisolated final class CancelFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false
        func cancel() { lock.withLock { cancelled = true } }
        var isCancelled: Bool { lock.withLock { cancelled } }
    }

    /// Henüz taranmamış kareleri tarar ve `frame_text.json`'a yazar. İlerleme (bitmiş, toplam) bildirilir; iptalde o ana dek olanı yazar.
    /// Aynı ders için eşzamanlı çağrı yapma: `FrameTextScanner` tekilleştirir.
    static func recognizeAndStore(lesson id: UUID, frames: [FrameRef], progress: (@MainActor @Sendable (Int, Int) -> Void)? = nil) async -> [Entry] {
        let flag = CancelFlag()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<[Entry], Never>) in
                ocrQueue.async {
                    let result = scan(lesson: id, frames: frames, flag: flag) { done, total in
                        if let progress { Task { @MainActor in progress(done, total) } }
                    }
                    continuation.resume(returning: result)
                }
            }
        } onCancel: {
            flag.cancel()
        }
    }

    /// Eşzamanlı tarama gövdesi (yalnız `ocrQueue`'da çağrılır).
    private static func scan(lesson id: UUID, frames: [FrameRef], flag: CancelFlag, progress: @Sendable (Int, Int) -> Void) -> [Entry] {
        let existing = load(lesson: id)
        let done = Set(existing.map(\.id))
        let todo = frames.filter { !done.contains($0.id) && FileManager.default.fileExists(atPath: VideoFiles.keyframeURL(lesson: id, frame: $0.id).path) }
        var fresh: [Entry] = []
        for (index, frame) in todo.enumerated() {
            if flag.isCancelled { break }
            let text = recognizeText(at: VideoFiles.keyframeURL(lesson: id, frame: frame.id))
            fresh.append(Entry(id: frame.id, time: frame.time, text: text))
            progress(index + 1, todo.count)
            if fresh.count % 10 == 0 { save(merge(existing: existing, new: fresh), lesson: id) }
        }
        let all = merge(existing: existing, new: fresh)
        if !fresh.isEmpty { save(all, lesson: id) }
        return all
    }
}

/// Ders başına tek tarama: içe aktarmanın arka plan taraması sürerken ders ekranı ikinci bir tarama başlatmaz, sürene katılır.
@MainActor
enum FrameTextScanner {
    private static var running: [UUID: Task<[FrameTextStore.Entry], Never>] = [:]

    static func isScanning(_ lesson: UUID) -> Bool { running[lesson] != nil }

    /// Bu ders için tarama sürüyorsa onun bitmesini bekler (ilerleme yalnız başlatana bildirilir); yoksa başlatır.
    /// Tarama, çağıran görev iptal edilse de sürer (sonuç dosyaya yazılır).
    static func scan(lesson id: UUID, frames: [FrameRef], progress: (@MainActor @Sendable (Int, Int) -> Void)? = nil) async -> [FrameTextStore.Entry] {
        if let existing = running[id] { return await existing.value }
        let task = Task { await FrameTextStore.recognizeAndStore(lesson: id, frames: frames, progress: progress) }
        running[id] = task
        let result = await task.value
        running[id] = nil
        return result
    }
}

/// Dersin karelerindeki yazılar: ara, dokununca videoyu o ana götür, kopyala. Eksikse taramayı başlatır.
struct FrameTextView: View {
    var context: LessonContext

    @Environment(\.dismiss) private var dismiss
    @State private var entries: [FrameTextStore.Entry] = []
    @State private var query = ""
    @State private var scanning = false
    @State private var scanned = 0
    @State private var scanTotal = 0
    @State private var worker: Task<Void, Never>?
    @State private var didLoad = false

    private var frames: [FrameRef] { context.transcript.keyframes.map { FrameRef(id: $0.id, time: $0.time) } }
    private var pendingCount: Int {
        let done = Set(entries.map(\.id))
        return frames.filter { !done.contains($0.id) }.count
    }
    private var visible: [FrameTextStore.Entry] {
        let all = FrameTextStore.nonEmpty(entries)
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return all }
        return all.filter { LibrarySearch.matches(text: $0.text, tokens: LibrarySearch.tokens(needle)) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if frames.isEmpty {
                        Label("Bu derste kayıtlı kare yok. Videoyu ‘Tahta/slayt karelerini yakala’ seçeneğiyle işlemen gerekir.", systemImage: "photo.on.rectangle")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else if scanning {
                        VStack(alignment: .leading, spacing: 6) {
                            // Arka plandaki (içe aktarmadan kalan) taramaya katıldıysak ilerleme bilinmez.
                            if scanTotal > 0 {
                                ProgressView(value: Double(scanned), total: Double(max(1, scanTotal)))
                                Text("Taranıyor: \(scanned)/\(scanTotal) kare").font(.footnote).foregroundStyle(.secondary)
                            } else {
                                ProgressView()
                                Text("Kareler taranıyor…").font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    } else if pendingCount > 0 {
                        Button {
                            scan()
                        } label: {
                            Label("\(pendingCount) kareyi tara", systemImage: "text.viewfinder")
                        }
                    } else {
                        Text("\(FrameTextStore.nonEmpty(entries).count) karede yazı bulundu.").font(.footnote).foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Yazılar cihazda tanınır (Türkçe ve İngilizce) ve kütüphane aramasında da bulunur.")
                }
                Section {
                    ForEach(visible) { entry in
                        FrameTextRow(entry: entry, imageURL: context.lesson.keyframeURL(entry.id)) {
                            context.player.seek(to: entry.time)
                            dismiss()
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Karelerde ara")
            .overlay {
                if didLoad && !scanning && visible.isEmpty && !frames.isEmpty && pendingCount == 0 {
                    ContentUnavailableView(query.isEmpty ? "Karelerde yazı bulunamadı" : "Sonuç yok", systemImage: "text.viewfinder")
                }
            }
            .navigationTitle("Karelerdeki yazılar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } } }
            .task {
                entries = FrameTextStore.load(lesson: context.lesson.id)
                didLoad = true
                if !entries.isEmpty || frames.isEmpty { return }
                scan()
            }
            .onDisappear { worker?.cancel() }
        }
    }

    private func scan() {
        guard worker == nil else { return }
        let id = context.lesson.id
        let refs = frames
        scanning = true
        scanned = 0
        // Sürmekte olan bir tarama varsa katılırız: toplam bilinmez (indeterminate).
        scanTotal = FrameTextScanner.isScanning(id) ? 0 : pendingCount
        worker = Task {
            let all = await FrameTextScanner.scan(lesson: id, frames: refs) { done, total in
                scanned = done
                scanTotal = total
            }
            entries = all
            scanning = false
            worker = nil
        }
    }
}

private struct FrameTextRow: View {
    var entry: FrameTextStore.Entry
    var imageURL: URL
    var open: () -> Void

    @State private var image: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: open) {
                HStack(spacing: 10) {
                    Group {
                        if let image {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else {
                            Rectangle().fill(.quaternary)
                        }
                    }
                    .frame(width: 80, height: 45)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    Label(VideoTime.string(entry.time), systemImage: "play.circle")
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                }
            }
            .buttonStyle(.plain)
            Text(entry.text)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .task { image = await LessonFiles.thumbnail(imageURL, maxPixel: 240) }
        .contextMenu {
            Button("Yazıyı kopyala", systemImage: "doc.on.doc") { UIPasteboard.general.string = entry.text }
        }
    }
}
