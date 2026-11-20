import SwiftUI
import UniformTypeIdentifiers

struct SharedQuestionFile: Identifiable { let id = UUID(); let url: URL }
struct QuestionFileShareView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context:Context) -> UIActivityViewController { UIActivityViewController(activityItems:[url],applicationActivities:nil) }
    func updateUIViewController(_ uiViewController:UIActivityViewController,context:Context) {}
}
struct SingleQuestionShareButton: View {
    let question: Question
    @State private var sharing: SharedQuestionFile?
    @State private var failure: String?
    var body: some View {
        Button {
            do {
                let url = try QuestionTransfer.temporaryURL("BilgiArenasi-Soru")
                try QuestionTransfer.exportQuestions([question],to:url)
                sharing = .init(url:url)
            } catch { failure = "Soru dosyası hazırlanamadı." }
        } label: { Label("Soruyu paylaş",systemImage:"square.and.arrow.up") }
        .sheet(item:$sharing) { file in QuestionFileShareView(url:file.url) }
        .alert("Paylaşım",isPresented:Binding(get:{ failure != nil },set:{ if !$0 { failure = nil } })) { Button("Tamam") { failure = nil } } message:{ Text(failure ?? "") }
    }
}
struct QuestionTransferControls: View {
    @EnvironmentObject var game: GameStore
    @EnvironmentObject var pool: DailyQuestionPool
    var search: String = ""
    var topic: Topic = .mixed
    var difficulty: Difficulty? = nil
    var format: QuestionFormat = .mixed
    var study: StudyLesson? = nil
    @State private var importing = false
    @State private var includeHidden = false
    @State private var busy = false
    @State private var status = ""
    @State private var preview: QuestionImportPreview?
    @State private var sharing: SharedQuestionFile?
    @State private var lastImport: (id:String,count:Int)?
    @State private var confirmUndo = false
    @State private var operation: Task<Void,Never>?
    var body: some View {
        DisclosureGroup {
            VStack(alignment:.leading,spacing:14) {
                Text("Tek soru, seçtiğin filtre veya tüm havuz JSON olarak paylaşılır. İndir / paylaş menüsünde Dosyalar'a Kaydet seçebilirsin.").font(.caption).foregroundStyle(.secondary)
                Toggle("Gizlediğim soruları da aktar",isOn:$includeHidden).font(.caption)
                Button { export(filtered:false) } label:{ Label("Tüm havuzu indir / paylaş",systemImage:"square.and.arrow.up") }.accessibilityIdentifier("exportWholePool")
                Button { export(filtered:true) } label:{ Label("Filtredeki soruları indir / paylaş",systemImage:"line.3.horizontal.decrease.circle") }.accessibilityIdentifier("exportFilteredPool")
                Button { importing = true } label:{ Label("JSON dosyalarını toplu içe aktar",systemImage:"square.and.arrow.down") }.accessibilityIdentifier("importQuestionFiles")
                Button {
                    do {
                        let url = try QuestionTransfer.temporaryURL("BilgiArenasi-Ornek")
                        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
                        struct Example: Encodable { let schemaVersion = 1; let guide: String; let questions: [Question] }
                        try encoder.encode(Example(guide:QuestionTransfer.guide,questions:[Seed.questions[0]]+VisualQuestionSeeds.questions+ActivityQuestionSeeds.questions)).write(to:url,options:.atomic)
                        sharing = .init(url:url)
                    } catch { status = "Örnek dosya hazırlanamadı." }
                } label:{ Label("Örnek JSON ve biçim rehberini indir",systemImage:"doc.text") }.accessibilityIdentifier("exportQuestionTemplate")
                if let lastImport { Button("Son aktarımı geri al (\(lastImport.count) soru)") { confirmUndo = true }.font(.caption.bold()).accessibilityIdentifier("undoQuestionImport") }
                if let preview {
                    VStack(alignment:.leading,spacing:10) {
                        Text("İçe aktarım önizlemesi").font(.headline)
                        Text("\(preview.fileCount) dosya · \(preview.questions.count) geçerli aday · \(preview.invalid) geçersiz").font(.caption)
                        ForEach(Array(preview.questions.prefix(3).enumerated()),id:\.offset) { _,q in Text(q.text).font(.caption).lineLimit(2) }
                        Text("Tekrarlar kayıt sırasında ayıklanır. Mevcut sorular değiştirilmez.").font(.caption).foregroundStyle(.secondary)
                        Button("Bu soruları havuza aktar") { commit(preview) }.buttonStyle(PrimaryButton()).disabled(preview.questions.isEmpty).accessibilityIdentifier("confirmQuestionImport")
                        Button("Önizlemeyi kapat") { self.preview = nil }.font(.caption)
                    }.padding(12).arenaPanel(tint:gold,radius:14)
                }
            }.disabled(busy).padding(.top,12)
            if busy { ProgressView(); Button("İşlemi durdur") { operation?.cancel() }.font(.caption) }
            if !status.isEmpty { Text(status).font(.caption).foregroundStyle(gold).padding(.top,8).accessibilityIdentifier("questionTransferStatus") }
        } label:{ Label("Paylaşım ve toplu içe aktarma",systemImage:"tray.and.arrow.up.fill").font(.subheadline.bold()) }
        .padding(16).arenaPanel(tint:aqua,radius:18).tint(aqua)
        .task { lastImport = try? await pool.database?.lastImport() }
        .confirmationDialog("Yalnız bu aktarımın eklediği sorular kaldırılsın mı?",isPresented:$confirmUndo) {
            Button("Aktarımı geri al",role:.destructive) {
                guard let lastImport else { return }
                operation = Task { do { let removed = try await pool.database?.undoImport(lastImport.id) ?? 0; status = "\(removed) içe aktarılan soru kaldırıldı."; self.lastImport = try? await pool.database?.lastImport(); await pool.refresh() } catch { status = "Aktarım geri alınamadı." } }
            }
        }
        .fileImporter(isPresented:$importing,allowedContentTypes:[.json],allowsMultipleSelection:true) { result in
            switch result {
            case .failure: status = "Dosya seçimi tamamlanmadı."
            case .success(let urls):
                busy = true; status = "Dosyalar okunuyor…"
                operation = Task {
                    defer { busy = false }
                    do { preview = try await QuestionTransfer.previewFiles(urls); status = "Önizleme hazır. Aktarmadan önce kontrol et." }
                    catch { status = (error as? QuizError)?.message ?? "JSON dosyaları okunamadı." }
                }
            }
        }
        .sheet(item:$sharing) { file in QuestionFileShareView(url:file.url) }
    }
    private func export(filtered: Bool) {
        guard let database = pool.database else { status = "Havuz hazırlanıyor; tekrar dene."; return }
        busy = true; status = "Dosya hazırlanıyor…"
        operation = Task {
            defer { busy = false }
            do {
                let url = try QuestionTransfer.temporaryURL("BilgiArenasi-Havuz")
                let count = try await database.exportFile(text:filtered ? search : "",topic:filtered ? topic : .mixed,difficulty:filtered ? difficulty : nil,format:filtered ? format : .mixed,includeHidden:includeHidden,study:filtered ? study : nil,to:url)
                status = "\(count) soru hazır. Paylaşım menüsünden Dosyalar'a kaydedebilirsin."
                sharing = .init(url:url)
            } catch { status = (error as? QuizError)?.message ?? "Dosya hazırlanamadı." }
        }
    }
    private func commit(_ preview: QuestionImportPreview) {
        guard let database = pool.database else { status = "Havuz hazırlanıyor; tekrar dene."; return }
        busy = true; status = "Sorular kaydediliyor…"
        operation = Task {
            defer { busy = false }
            do {
                let report = try await QuestionTransfer.store(preview,database:database) { done,total in await MainActor.run { status = "\(done) / \(total) soru işlendi" } }
                status = report.message; self.preview = nil; lastImport = try? await database.lastImport(); await pool.refresh()
            } catch is CancellationError { status = "Aktarım durdu; tamamlanan gruplar saklandı. Aynı dosyayı yeniden seçebilirsin."; lastImport = try? await database.lastImport(); await pool.refresh() }
            catch { status = (error as? QuizError)?.message ?? "Aktarım tamamlanamadı; kaydedilen gruplar korundu."; lastImport = try? await database.lastImport(); await pool.refresh() }
        }
    }
}
