import SwiftData
import SwiftUI

/// Cornell not defteri: ipuçları (sol), notlar (sağ), özet (alt).
struct CornellNotesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \CornellNote.updatedAt, order: .reverse) private var notes: [CornellNote]
    /// Belirli bir bölümün notları (nil: hepsi).
    var episode: Episode?
    @State private var editing: CornellNote?
    @State private var query = ""
    /// "Yeni" ile açılan not ve ilk başlığı: hiçbir şey yazılmadan kapatılırsa listede boş not kalmaz.
    @State private var fresh: (note: CornellNote, title: String)?

    var body: some View {
        NavigationStack {
            List {
                let scoped = notes.filter { episode == nil || $0.episodeID == episode?.id }
                let list = scoped.filter { StudySearch.matches([$0.title, $0.cues, $0.notes, $0.summary], query: query) }
                if scoped.isEmpty {
                    ContentUnavailableView("Not yok", systemImage: "note.text",
                                           description: Text("Cornell yöntemi: sağa notlar, sola anahtar sorular, alta 2–3 cümlelik özet."))
                } else if list.isEmpty {
                    ContentUnavailableView("Eşleşen not yok", systemImage: "magnifyingglass",
                                           description: Text("Başlık, ipucu, not ve özet içinde arandı. Aramayı değiştir."))
                }
                ForEach(list) { note in
                    Button { editing = note } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(note.title.isEmpty ? "Adsız not" : note.title).font(.headline)
                            Text(note.summary.isEmpty ? String(note.notes.prefix(90)) : note.summary)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            Text(note.updatedAt, style: .date).font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions { Button("Sil", role: .destructive) { context.delete(note); try? context.save() } }
                }
            }
            .navigationTitle(episode == nil ? "Cornell notları" : "Notlar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Yeni", systemImage: "plus") {
                        let note = CornellNote(title: episode?.title ?? "", episodeID: episode?.id)
                        context.insert(note)
                        try? context.save()
                        fresh = (note, note.title)
                        editing = note
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Notlarda ara")
            .sheet(item: $editing, onDismiss: discardBlankFresh) { note in CornellEditor(note: note) }
            .debugNarrowScreen()
        }
    }

    /// Düzenleyici kapandıktan sonra çalışır (silinmiş notu çizmeye çalışan görünüm kalmasın diye burada).
    /// Yalnız bu açılışta "Yeni" ile eklenen ve boş bırakılan not silinir; var olan notlara dokunulmaz.
    private func discardBlankFresh() {
        guard let fresh else { return }
        self.fresh = nil
        let note = fresh.note
        guard note.modelContext != nil, !note.isDeleted,
              CornellNote.isUntouchedNew(title: note.title, initialTitle: fresh.title, cues: note.cues, notes: note.notes, summary: note.summary)
        else { return }
        context.delete(note)
        try? context.save()
    }
}

extension CornellNote {
    /// İpucu, not ve özet boş (yalnız boşluk ya da satır sonu).
    nonisolated static func isBlank(cues: String, notes: String, summary: String) -> Bool {
        [cues, notes, summary].allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// Yeni açılan nota hiçbir şey yazılmadı: gövde boş, başlık da boş ya da açılıştaki (bölüm adı) hâlinde.
    nonisolated static func isUntouchedNew(title: String, initialTitle: String, cues: String, notes: String, summary: String) -> Bool {
        let now = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let initial = initialTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return isBlank(cues: cues, notes: notes, summary: summary) && (now.isEmpty || now == initial)
    }
}

/// PDF sayfalama: uzun not sayfalara bölünür. PDF'te y yukarı doğru artar; içerik (0, 0)'dan yukarı çizilir.
nonisolated enum CornellPDF {
    /// Her sayfa için içeriğin dikey kayması: ilk sayfada içeriğin üstü sayfanın üstüne oturur, sonrakiler birer sayfa aşağıdan sürer.
    static func pageOffsets(contentHeight: CGFloat, pageHeight: CGFloat = 842) -> [CGFloat] {
        guard pageHeight > 0, contentHeight.isFinite else { return [0] }
        let height = max(0, contentHeight)
        // 1 pt'ye kadar taşma (yuvarlama payı) yeni sayfa açmaz.
        let pages = max(1, Int(((height - 1) / pageHeight).rounded(.up)))
        return (0..<pages).map { pageHeight * CGFloat($0 + 1) - height }
    }
}

struct CornellEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var note: CornellNote
    @Query(sort: \Episode.createdAt, order: .reverse) private var episodes: [Episode]
    @State private var shareURL: URL?
    @State private var showFeynman = false
    /// Açılıştaki içerik: yalnız gerçekten değişen not "güncellendi" sayılır (açıp bakmak tarihi ve sırayı değiştirmesin).
    @State private var original: [String]?

    private var fields: [String] { [note.title, note.cues, note.notes, note.summary, note.episodeID?.uuidString ?? ""] }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    TextField("Başlık", text: $note.title).font(.title3.bold())
                    episodePicker
                    // Dar ekranda (320 pt, büyük yazı) bölmeler alt alta.
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 10) {
                            pane("İpuçları / sorular", text: $note.cues, minHeight: 260).frame(width: 130)
                            pane("Notlar", text: $note.notes, minHeight: 260).frame(minWidth: 170)
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            pane("İpuçları / sorular", text: $note.cues, minHeight: 140)
                            pane("Notlar", text: $note.notes, minHeight: 220)
                        }
                    }
                    pane("Özet (2–3 cümle)", text: $note.summary, minHeight: 90)
                    Text("İpucu: Dinlerken sağa yaz; sonra sola her paragraf için bir soru çıkar; en sonda kapatıp özeti kendi cümlelerinle yaz.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(16)
            }
            .navigationTitle("Cornell notu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Bitti") { save(); dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("PDF olarak paylaş", systemImage: "doc.richtext") { exportPDF() }
                        Button("Özeti sesli anlat (Feynman)", systemImage: "person.wave.2") { showFeynman = true }
                            .disabled(note.episodeID == nil)
                    } label: { Image(systemName: "square.and.arrow.up") }
                }
            }
            .onAppear { if original == nil { original = fields } }
            .onDisappear { save() }   // her tuş vuruşunda değil, çıkarken kaydedilir
            .sheet(item: $shareURL) { ShareSheet(items: [$0]) }
            .sheet(isPresented: $showFeynman) {
                if let id = note.episodeID, let episode = try? context.fetch(FetchDescriptor<Episode>(predicate: #Predicate { $0.id == id })).first {
                    FeynmanView(episode: episode)
                }
            }
        }
    }

    /// #50: genel listeden açılan notun bölümü seçilebilir (Feynman ve "bölümün notları" buna bağlı).
    private var episodePicker: some View {
        let ready = episodes.filter { $0.status == .ready }
        let current = ready.first { $0.id == note.episodeID }
        return Menu {
            Button("Bölüm yok") { note.episodeID = nil }
            ForEach(ready) { episode in
                Button {
                    note.episodeID = episode.id
                    if note.title.isEmpty { note.title = episode.title }
                } label: {
                    if episode.id == note.episodeID { Label(episode.title, systemImage: "checkmark") } else { Text(episode.title) }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "waveform").accessibilityHidden(true)
                Text(current.map { "Bölüm: \($0.title)" } ?? "Bölüm seç").lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down").font(.caption).accessibilityHidden(true)
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        }
        .accessibilityLabel(current.map { "Bölüm: \($0.title)" } ?? "Bölüm seç")
    }

    private func pane(_ title: String, text: Binding<String>, minHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            TextEditor(text: text)
                .font(.body)
                .frame(minHeight: minHeight)
                .padding(6)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func save() {
        // Boş bırakılan yeni not kapanışta silinir; silinmiş nota dokunulmaz.
        guard note.modelContext != nil, !note.isDeleted else { return }
        let current = fields
        if let original, original != current {
            note.updatedAt = .now
            self.original = current
        }
        try? context.save()
    }

    private func exportPDF() {
        let page = VStack(alignment: .leading, spacing: 12) {
            Text(note.title.isEmpty ? "Cornell notu" : note.title).font(.system(size: 22, weight: .bold))
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading) { Text("İpuçları").font(.system(size: 11, weight: .bold)); Text(note.cues).font(.system(size: 11)) }
                    .frame(width: 150, alignment: .topLeading)
                Rectangle().frame(width: 1).foregroundStyle(.gray)
                VStack(alignment: .leading) { Text("Notlar").font(.system(size: 11, weight: .bold)); Text(note.notes).font(.system(size: 11)) }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            Rectangle().frame(height: 1).foregroundStyle(.gray)
            VStack(alignment: .leading) { Text("Özet").font(.system(size: 11, weight: .bold)); Text(note.summary).font(.system(size: 11)) }
            Text("Ders Podcast").font(.system(size: 9)).foregroundStyle(.gray)
        }
        .padding(36)
        .frame(width: 595, alignment: .topLeading)
        .background(Color.white)
        .foregroundStyle(.black)
        .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: page)
        let safe = String(note.title.map { "/\\:?%*|\"<>".contains($0) ? "-" : $0 }.prefix(40))
        let url = URL.temporaryDirectory.appending(path: "\(safe.isEmpty ? "Not" : safe).pdf")
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
        renderer.render { size, draw in
            // Uzun not sayfalara bölünür: her sayfada içerik bir sayfa boyu yukarı kaydırılıp yeniden çizilir.
            for dy in CornellPDF.pageOffsets(contentHeight: size.height) {
                ctx.beginPDFPage(nil)
                ctx.saveGState()
                ctx.translateBy(x: 0, y: dy)
                draw(ctx)
                ctx.restoreGState()
                ctx.endPDFPage()
            }
        }
        ctx.closePDF()
        shareURL = url
    }
}
