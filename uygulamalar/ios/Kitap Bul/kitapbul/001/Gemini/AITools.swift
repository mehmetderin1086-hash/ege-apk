import SwiftUI
import SwiftData
import PhotosUI
import UIKit

// MARK: - Araçlar merkezi

/// Yapay zekâ araçları merkezi: renkli kart ızgarası (ortak tema stili), her kart kendi sayfasına gider.
/// Izgara ekran genişliğine uyum sağlar (telefonda 2, tablette 3–4 sütun).
struct AIToolsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isPresented) private var isPresented
    @AppStorage(GeminiSettings.enabledKey) private var aiEnabled = true
    @AppStorage(GeminiSettings.modelKey) private var modelRaw = GeminiModel.flash.rawValue

    private struct Tool: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let icon: String
        let color: Color
    }

    private let tools: [Tool] = [
        Tool(id: "voice", title: "Sesle Kaydet", subtitle: "Kitabı söyle, Gemini kaydı hazırlasın", icon: "mic.badge.plus", color: KitapTema.amazon),
        Tool(id: "scan", title: "Gemini ile Tara", subtitle: "Kapak/künye fotoğrafından kitap kaydı", icon: "camera.viewfinder", color: KitapTema.foto),
        Tool(id: "complete", title: "Eksikleri Tamamla", subtitle: "Kategori, dil ve özetleri toplu doldur", icon: "wand.and.stars", color: KitapTema.amazon),
        Tool(id: "recommend", title: "Kitap Öner", subtitle: "Öğrenciye ya da sınıfa uygun kitaplar", icon: "person.crop.circle.badge.checkmark", color: KitapTema.toplu),
        Tool(id: "card", title: "Kitap Kartı", subtitle: "Özet, anahtar sözcük ve tartışma soruları", icon: "text.book.closed", color: KitapTema.dosya),
        Tool(id: "shelf", title: KatalogAraci.shelfScan.aracBasligi ?? "", subtitle: "Tek fotoğrafta çok kitap ekle ya da rafı say", icon: "books.vertical.circle", color: KitapTema.vurgu),
        Tool(id: "weekly", title: "Haftalık Rapor", subtitle: "Ödünç, gecikme, eksikler + AI yorumu, PDF", icon: "chart.line.text.clipboard", color: KitapTema.basari),
        Tool(id: "quiz", title: "Kitap Soruları", subtitle: "Okuduğunu anlama testi + cevap anahtarı", icon: "questionmark.bubble", color: KitapTema.dosya),
        Tool(id: "lists", title: "Kişisel Listeler", subtitle: "Sınıfa öğrenci başına öneri PDF'i", icon: "list.star", color: KitapTema.toplu),
        Tool(id: "gaps", title: "Koleksiyon Analizi", subtitle: "Eksik alanlar ve alım önerileri", icon: "sparkle.magnifyingglass", color: KitapTema.ana),
        Tool(id: "donation", title: "Bağış Değerlendir", subtitle: "Al / alma / kontrol kararı", icon: "gift", color: KitapTema.basari),
        Tool(id: "categories", title: "Kategori Tutarlılığı", subtitle: "Farklı yazımları tek kategoride topla", icon: "tag.circle", color: KitapTema.foto),
        Tool(id: "compress", title: "Görselleri Sıkıştır", subtitle: "Arka kapak ve künye fotoğraflarını küçült", icon: "photo.badge.arrow.down", color: KitapTema.dosya)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    statusCard
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 14)], spacing: 14) {
                        ForEach(tools) { tool in
                            NavigationLink(value: tool.id) {
                                ToolCard(title: tool.title, subtitle: tool.subtitle, icon: tool.icon, color: tool.color)
                            }
                            .buttonStyle(.kitapSade)
                            .disabled(!aiEnabled)
                            .accessibilityLabel(tool.title)
                            .accessibilityHint(tool.subtitle)
                        }
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .kenardanSekmeKaydir()
            // Telefonda Asistan/Araçlar sekmeleri gizli olduğundan kabuktaki kapı tetiklenmez; onay burada sorulur
            .geminiConsentGate(isRelevant: true)
            .task {
                GeminiReachability.shared.startMonitoring()
                await GeminiReachability.shared.probeIfStale()
            }
            .navigationTitle("Yapay zekâ araçları")
            .toolbar {
                if isPresented {
                    ToolbarItem(placement: .confirmationAction) { Button("Kapat") { dismiss() } }
                }
            }
            .navigationDestination(for: String.self) { id in
                switch id {
                case "voice": VoiceBookEntryPage()   // Gemini/VoiceBookEntry.swift
                case "scan": GeminiScanPage()
                case "complete": AICompletePage()
                case "recommend": AIRecommendPage()
                case "card": AIBookCardPage()
                case "shelf": ShelfScanPage()
                case "weekly": WeeklyReportPage()
                case "quiz": QuizPage()
                case "lists": ClassReadingListsPage()
                case "gaps": GapAnalysisPage()
                case "donation": DonationPage()
                case "categories": CategoryConsistencyPage()
                case "compress": GorselSikistirmaPage()
                default: Text("Bulunamadı")
                }
            }
        }
    }

    private var statusCard: some View {
        // Canlı gradyanlı durum kartı
        HStack(spacing: 14) {
            Image(systemName: aiEnabled ? "sparkles" : "sparkles.slash")
                .font(.title.weight(.semibold))
                .foregroundStyle(.white)
                .symbolEffect(.pulse, isActive: aiEnabled)
                .frame(width: 56, height: 56)
                .background(.white.opacity(0.22), in: .rect(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 2) {
                Text(GeminiSettings.statusDescription)
                    .font(.title3.weight(.bold))
                // Önbellekli, gözlemlenebilir durum: her çizimde Keychain okunmaz
                Text(GeminiDurumu.shared.isActive
                     ? (GeminiModel(rawValue: modelRaw) ?? .flash).displayName
                     : "Ayarlar > Yapay Zekâ bölümünden kurulum ve onayı tamamlayın")
                    .font(.subheadline)
                    .opacity(0.92)
                if GeminiReachability.shared.isBlockedOrOffline {
                    Label(GeminiReachability.shared.durum.etiket, systemImage: "wifi.exclamationmark")
                        .font(.caption.weight(.semibold))
                }
            }
            .foregroundStyle(.white)
            Spacer()
        }
        .padding(18)
        .background {
            CanliGradyan(renkler: [KitapTema.foto, KitapTema.ana, KitapTema.toplu])
                .overlay(Color.black.opacity(0.18))
        }
        .clipShape(.rect(cornerRadius: 22))
        .accessibilityElement(children: .combine)
    }
}

private struct ToolCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(.white.opacity(0.25), in: .rect(cornerRadius: 12))
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(2, reservesSpace: true)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(3, reservesSpace: true)
            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(
            LinearGradient(colors: [color, color.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: .rect(cornerRadius: 18)
        )
    }
}

// MARK: - Ortak parçalar

/// Sayfa başında hata/başarı mesajı.
private struct StatusMessage: View {
    let text: String
    var isError = false
    @AppStorage(GeminiSettings.consentKey) private var consentGiven = false
    @State private var askingConsent = false

    /// Onay eksikliği hatası: metin "Ayarlar › Yapay Zekâ" der, burada doğrudan onay da verilebilir.
    private var needsConsent: Bool {
        isError && !consentGiven && text.contains("veri paylaşım onayı")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(text, systemImage: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(isError ? KitapTema.vurgu : KitapTema.basari)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel((isError ? "Hata: " : "") + text)
            if needsConsent {
                Button("Onay ver", systemImage: "checkmark.shield") { askingConsent = true }
                    .buttonStyle(.bordered)
                    .accessibilityHint("Veri paylaşım iznini açar")
            }
        }
        .alert(GeminiConsentGate.alertTitle, isPresented: $askingConsent) {
            Button("Kabul Ediyorum") { consentGiven = true }
            Button("Şimdi Değil", role: .cancel) { }
        } message: {
            Text(GeminiConsentGate.alertMessage)
        }
    }
}

/// UIKit kamera (tek fotoğraf).
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) { }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.9) {
                parent.onImage(data)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - 1) Gemini ile Tara

struct GeminiScanPage: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var books: [CatalogBook]

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var images: [Data] = []
    @State private var fields = GeminiBookFields()
    @State private var quantity = 1
    @State private var isWorking = false
    @State private var isShowingCamera = false
    @State private var message: (text: String, isError: Bool)?
    @State private var hasResult = false
    @State private var isShowingLive = false
    @AppStorage("autoStraightenCover") private var autoStraighten = true

    var body: some View {
        Form {
            Section {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(Array(images.enumerated()), id: \.offset) { index, data in
                            ZStack(alignment: .topTrailing) {
                                CoverThumb(data: data, size: 70)
                                Button {
                                    images.remove(at: index)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.white, .red)
                                }
                                .accessibilityLabel("Fotoğrafı kaldır")
                                .offset(x: 6, y: -6)
                            }
                        }
                        if images.count < 4 {
                            PhotosPicker(selection: $pickerItems, maxSelectionCount: 4 - images.count, matching: .images) {
                                addTile(icon: "photo.on.rectangle", title: "Galeri")
                            }
                            .accessibilityLabel("Galeriden fotoğraf ekle")
                            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                                Button {
                                    isShowingCamera = true
                                } label: {
                                    addTile(icon: "camera", title: "Kamera")
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Kamerayla fotoğraf çek")
                                Button {
                                    isShowingLive = true
                                } label: {
                                    addTile(icon: "text.viewfinder", title: "Canlı")
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Canlı kapak tarama: yazıları anlık görerek çek")
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                Button {
                    Task { await recognize() }
                } label: {
                    Label(isWorking ? "Gemini okuyor…" : "Gemini ile Oku", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.kitapDolu(KitapTema.foto))
                .disabled(images.isEmpty || isWorking)
                Toggle("Kapağı otomatik düzelt (eğik çekim)", isOn: $autoStraighten)
                    .font(.footnote)
            } header: {
                Label("Fotoğraflar (kapak, arka kapak, künye)", systemImage: "photo.stack")
            } footer: {
                Text("Aynı kitabın en fazla 4 fotoğrafını ekleyin. Gemini adı, yazarı, yayınevi, ISBN, yıl, sayfa sayısı, kategori ve kısa özeti çıkarır.")
            }

            if let message {
                Section { StatusMessage(text: message.text, isError: message.isError) }
            }

            if hasResult {
                Section("Kitap Bilgileri (düzenleyebilirsiniz)") {
                    field("Kitap Adı", text: binding(\.title), key: "title")
                    field("Yazar", text: binding(\.author), key: "author")
                    field("Yayınevi", text: binding(\.publisher), key: "publisher")
                    field("ISBN", text: binding(\.isbn), key: "isbn").keyboardType(.numberPad)
                    field("Yıl", text: binding(\.publicationYear), key: "publicationYear").keyboardType(.numberPad)
                    field("Sayfa", text: binding(\.pageCount), key: "pageCount").keyboardType(.numberPad)
                    field("Dil", text: binding(\.language), key: "language")
                    Picker("Kategori", selection: Binding(
                        get: { fields.category ?? "Diğer" },
                        set: { fields.category = $0 }
                    )) {
                        ForEach(KitapKategorileri.liste, id: \.self) { Text($0).tag($0) }
                    }
                    Stepper("Adet: \(quantity)", value: $quantity, in: 1...50)
                    TextField("Özet / not", text: binding(\.summary), axis: .vertical)
                        .lineLimit(2...5)
                        .accessibilityLabel("Özet")
                    field("Seri", text: binding(\.series), key: "series")
                    field("Cilt", text: binding(\.volume), key: "volume").keyboardType(.numberPad)
                    TextField("Etiketler (virgülle)", text: Binding(
                        get: { (fields.tags ?? []).joined(separator: ", ") },
                        set: { yeni in
                            let liste = yeni.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                            fields.tags = liste.isEmpty ? nil : liste
                        }
                    ))
                    Picker("Okuma düzeyi", selection: Binding(
                        get: { fields.readingLevel ?? "" },
                        set: { fields.readingLevel = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("Belirtilmedi").tag("")
                        ForEach(OkumaDuzeyi.liste, id: \.self) { Text($0).tag($0) }
                    }
                    if let uyari = fields.contentWarning {
                        Label(uyari, systemImage: "exclamationmark.bubble")
                            .font(.footnote)
                            .foregroundStyle(KitapTema.vurgu)
                    }
                }

                Section {
                    Button {
                        Task { await save() }
                    } label: {
                        Label("Kataloğa Ekle", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.kitapDolu(KitapTema.basari))
                    .disabled((fields.title ?? "").isEmpty)
                }
            }
        }
        .navigationTitle("Gemini ile Tara")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self), images.count < 4 {
                        images.append(data)
                    }
                }
                pickerItems = []
            }
        }
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraPicker { data in
                if images.count < 4 { images.append(data) }
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $isShowingLive) {
            CanliKapakTaramaSayfasi { foto in
                if images.count < 4 { images.append(foto) }
                // Canlı çekimden sonra hemen okunur (tek dokunuşla kayıt)
                Task { await recognize() }
            }
        }
    }

    private func addTile(icon: String, title: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.title2)
            Text(title).font(.caption2)
        }
        .frame(width: 70, height: 98)
        .foregroundStyle(KitapTema.foto)
        .background(KitapTema.foto.opacity(0.1), in: .rect(cornerRadius: 6))
    }

    private func binding(_ keyPath: WritableKeyPath<GeminiBookFields, String?>) -> Binding<String> {
        Binding(
            get: { fields[keyPath: keyPath] ?? "" },
            set: { fields[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }

    private func field(_ title: String, text: Binding<String>, key: String) -> some View {
        let uncertain = (fields.uncertain ?? []).contains(key)
        return HStack {
            TextField(title, text: text)
                .accessibilityLabel(title)
            if uncertain {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundStyle(KitapTema.vurgu)
                    .accessibilityLabel("Gemini bu alandan emin değil, kontrol edin")
            }
        }
    }

    private func recognize() async {
        isWorking = true
        message = nil
        defer { isWorking = false }
        do {
            fields = try await GeminiBookRecognizer.recognize(images: images)
            if fields.isBook == false {
                message = ("Fotoğraflarda bir kitap kapağı/künyesi görünmüyor.", true)
                hasResult = false
                return
            }
            hasResult = true
            let uncertain = fields.uncertain ?? []
            message = uncertain.isEmpty
                ? ("Bilgiler çıkarıldı. Kontrol edip kataloğa ekleyin.", false)
                : ("Bilgiler çıkarıldı; soru işaretli alanları kontrol edin.", false)
            AccessibilityNotification.Announcement("Kitap bilgileri çıkarıldı").post()
        } catch {
            message = ((error as? GeminiError)?.errorDescription ?? error.localizedDescription, true)
        }
    }

    private func save() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        let isbn = ISBNFormatter.normalize(fields.isbn ?? "")
        var kaynak = images.first
        if autoStraighten, let ilk = kaynak {
            kaynak = await KapakDuzeltici.duzelt(ilk) ?? ilk
        }
        let cover = kaynak.flatMap { GeminiImagePreparer.jpegData(from: $0, maxPixel: 1200) }
        // Arka kapak ve künye de küçültülür (12 MP ham fotoğraf 3-5 MB tutuyordu); künye okunabilir kalsın diye 1600 px
        let extras = Array(images.dropFirst().prefix(2))
        let compressedExtras = await Task.detached(priority: .userInitiated) {
            extras.map { GeminiImagePreparer.jpegData(from: $0, maxPixel: 1600, quality: 0.8) ?? $0 }
        }.value
        let book = Book(
            title: fields.title ?? "",
            author: fields.author ?? "",
            publisher: fields.publisher,
            isbn: isbn.isEmpty ? nil : isbn,
            publicationYear: fields.publicationYear,
            edition: fields.edition,
            pageCount: fields.pageCount,
            notes: fields.summary ?? "",
            category: fields.category,
            language: fields.language,
            readingStatus: "Okunacak",
            quantity: quantity,
            coverData: cover,
            backCoverData: compressedExtras.first,
            imprintData: compressedExtras.count > 1 ? compressedExtras[1] : nil,
            isTextbook: fields.category == "Ders Kitabı" || fields.category == "Yardımcı Kaynak",
            series: fields.series,
            volume: fields.volume.flatMap(Int.init),
            tags: fields.tags?.joined(separator: ", "),
            readingLevel: fields.readingLevel,
            contentWarning: fields.contentWarning
        )
        do {
            let outcome = try CatalogSaveEngine.save(book, context: modelContext, catalog: books, source: "gemini")
            switch outcome {
            case .merged(_, let added): message = ("“\(book.title)” için \(added) nüsha eklendi.", false)
            case .inserted, .updated: message = ("“\(book.title)” kataloğa kaydedildi.", false)
            case .failed(let detail): throw CatalogSaveEngine.SaveError(message: detail)
            }
            AccessibilityNotification.Announcement("Kitap kataloğa eklendi").post()
            hasResult = false
            images = []
            fields = GeminiBookFields()
            quantity = 1
        } catch {
            message = ("Kaydedilemedi: \(error.localizedDescription)", true)
        }
    }
}

// MARK: - 2) Eksikleri Tamamla

/// Gemini'nin toplu tamamlama yanıtındaki tek kitap.
nonisolated struct AICompletionItem: Codable, Sendable {
    var index: Int
    var category: String?
    var language: String?
    var summary: String?
}

enum AICompletionEngine {
    static let systemPrompt = """
    Sen bir okul kütüphanesi kataloglama uzmanısın. Sana kitap listesi verilecek (ad, yazar, \
    yayınevi, yıl). Her kitap için bilgin dahilinde şunları doldur ve YALNIZCA JSON dizisi döndür: \
    [{"index": 0, "category": "", "language": "", "summary": ""}]
    - category: şu listeden bir tanesi: \(KitapKategorileri.liste.joined(separator: ", ")).
    - language: kitabın yazıldığı dil ("Türkçe", "İngilizce" …). Türkçe adlı kitaplar için "Türkçe".
    - summary: Türkçe, 1–2 cümle, öğrenciye yönelik tarafsız tanıtım. Kitabı tanımıyorsan boş bırak; uydurma.
    Her girdi için bir çıktı üret; index değerlerini aynen koru.
    """

    static func complete(_ books: [CatalogBook]) async throws -> [AICompletionItem] {
        let list = books.enumerated().map { index, book in
            "\(index). \(book.title) — \(book.author) | \(book.publisher ?? "") \(book.publicationYear ?? "")"
        }.joined(separator: "\n")
        return try await GeminiClient.shared.generateJSON(
            [AICompletionItem].self,
            prompt: "KİTAPLAR:\n\(list)",
            system: systemPrompt,
            model: .flashLite,
            temperature: 0.2,
            maxOutputTokens: 4096
        )
    }

    /// Yalnızca boş VE kullanıcının seçtiği alanlar doldurulur; mevcut giriş asla ezilmez.
    /// Hiçbir şey yazmadan, uygulanacak değişiklikleri (alan, yeni değer) döndürür: önizleme ve `apply` ortak kullanır.
    static func proposals(
        _ item: AICompletionItem, for book: CatalogBook,
        fillCategory: Bool = true, fillLanguage: Bool = true, fillSummary: Bool = true
    ) -> [(field: String, value: String)] {
        var result: [(field: String, value: String)] = []
        if fillCategory, !BookFieldMetadata.isLocked("category", on: book), (book.category ?? "").isEmpty,
           let category = item.category, KitapKategorileri.liste.contains(category) {
            result.append(("category", category))
        }
        if fillLanguage, !BookFieldMetadata.isLocked("language", on: book), (book.language ?? "").isEmpty, let language = item.language, !language.isEmpty {
            result.append(("language", language))
        }
        if fillSummary, !BookFieldMetadata.isLocked("notes", on: book), book.notes.isEmpty, let summary = item.summary, !summary.isEmpty {
            result.append(("notes", summary))
        }
        return result
    }

    static func apply(
        _ item: AICompletionItem, to book: CatalogBook,
        fillCategory: Bool = true, fillLanguage: Bool = true, fillSummary: Bool = true,
        journal: AIDegisiklikToplayici? = nil
    ) -> Bool {
        guard YetkiDurumu.shared.yonetici else { return false }
        let changes = proposals(item, for: book, fillCategory: fillCategory, fillLanguage: fillLanguage, fillSummary: fillSummary)
        guard !changes.isEmpty else { return false }
        let previous = book.book
        for change in changes {
            switch change.field {
            case "category": book.category = change.value
            case "language": book.language = change.value
            default: book.notes = change.value
            }
        }
        book.update(from: BookFieldMetadata.stampChanges(before: previous, after: book.book, source: "gemini"))
        journal?.note(book, before: previous)
        return true
    }
}

struct AICompletePage: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CatalogBook.addedAt, order: .reverse) private var books: [CatalogBook]

    @State private var fillCategory = true
    @State private var fillLanguage = true
    @State private var fillSummary = true
    @State private var limit = 50
    @State private var isRunning = false
    @State private var isCancelRequested = false
    @State private var progress = 0
    @State private var total = 0
    @State private var updated = 0
    @State private var message: (text: String, isError: Bool)?
    /// İlk 8'lik partinin önizlemesi: kullanıcı onaylayana kadar hiçbir alan yazılmaz.
    @State private var previewRows: [OnizlemeSatiri] = []
    @State private var previewSkipped: Set<UUID> = []
    @State private var previewContinuation: CheckedContinuation<Set<UUID>?, Never>?

    struct OnizlemeSatiri: Identifiable, Equatable {
        var id: UUID { bookID }
        let bookID: UUID
        let title: String
        let changes: [Degisiklik]
        struct Degisiklik: Equatable {
            let label: String
            let old: String
            let new: String
        }
    }

    private var candidates: [CatalogBook] {
        books.filter { book in
            !book.isDeleted && !book.isWithdrawn && !book.title.isEmpty && (
                (fillCategory && (book.category ?? "").isEmpty)
                || (fillLanguage && (book.language ?? "").isEmpty)
                || (fillSummary && book.notes.isEmpty)
            )
        }
    }

    var body: some View {
        Form {
            Section {
                Toggle("Kategori", isOn: $fillCategory)
                Toggle("Dil", isOn: $fillLanguage)
                Toggle("Özet (notlar alanına)", isOn: $fillSummary)
                Picker("En fazla kitap", selection: $limit) {
                    ForEach([20, 50, 100, 250, 500], id: \.self) { Text("\($0)").tag($0) }
                }
            } header: {
                Label("Doldurulacak alanlar", systemImage: "checklist")
            } footer: {
                Text("Eksik alanı olan \(candidates.count) kitap var. Yalnızca BOŞ alanlar doldurulur; mevcut bilgiler değişmez. 8'erli gruplarla gönderilir.")
            }

            Section {
                if isRunning {
                    ProgressView(value: Double(progress), total: Double(max(total, 1))) {
                        Text("İşleniyor: \(progress)/\(total) — güncellenen \(updated)")
                    }
                    .accessibilityValue("\(progress) / \(total)")
                    Button(role: .destructive) {
                        isCancelRequested = true
                    } label: {
                        Label("Durdur", systemImage: "stop.circle")
                    }
                } else {
                    Button {
                        Task { await run() }
                    } label: {
                        Label("Gemini ile Tamamla", systemImage: "wand.and.stars")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.kitapDolu(KitapTema.amazon))
                    .disabled(candidates.isEmpty || !(fillCategory || fillLanguage || fillSummary))
                }
                if let message {
                    StatusMessage(text: message.text, isError: message.isError)
                }
            }

            Section("Sıradaki kitaplar") {
                ForEach(candidates.prefix(12)) { book in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(book.title).font(.subheadline.weight(.semibold))
                        Text(missingSummary(for: book)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if candidates.count > 12 {
                    Text("… ve \(candidates.count - 12) kitap daha").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Eksikleri Tamamla")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { resolvePreview(nil) }
        .sheet(isPresented: Binding(get: { !previewRows.isEmpty }, set: { if !$0 { resolvePreview(nil) } })) {
            previewSheet
                .interactiveDismissDisabled()
        }
    }

    private var previewSheet: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(previewRows) { row in
                        Toggle(isOn: Binding(
                            get: { !previewSkipped.contains(row.bookID) },
                            set: { if $0 { previewSkipped.remove(row.bookID) } else { previewSkipped.insert(row.bookID) } }
                        )) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.title).font(.subheadline.weight(.semibold))
                                ForEach(row.changes, id: \.label) { change in
                                    Text("\(change.label): \(change.old.isEmpty ? "—" : change.old) → \(change.new)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(3)
                                }
                            }
                        }
                    }
                } header: {
                    Text("İlk \(previewRows.count) kitap için öneriler")
                } footer: {
                    Text("İşaretli kitaplar güncellenir. Onayladığınızda kalan kitaplar bu ayarlarla kendiliğinden devam eder. Her şey Ayarlar › Yapay Zekâ bölümünden geri alınabilir.")
                }
            }
            .navigationTitle("Önizleme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç", role: .cancel) { resolvePreview(nil) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Onayla ve devam et") {
                        resolvePreview(Set(previewRows.map(\.bookID)).subtracting(previewSkipped))
                    }
                }
            }
        }
    }

    private func resolvePreview(_ approved: Set<UUID>?) {
        guard let continuation = previewContinuation else { return }
        previewContinuation = nil
        previewRows = []
        previewSkipped = []
        continuation.resume(returning: approved)
    }

    /// Önizlemeyi gösterip kullanıcının kararını bekler (nil = vazgeçti).
    private func requestPreview(_ rows: [OnizlemeSatiri]) async -> Set<UUID>? {
        await withCheckedContinuation { continuation in
            previewSkipped = []
            previewContinuation = continuation
            previewRows = rows
        }
    }

    private func missingSummary(for book: CatalogBook) -> String {
        var parts: [String] = []
        if (book.category ?? "").isEmpty { parts.append("kategori") }
        if (book.language ?? "").isEmpty { parts.append("dil") }
        if book.notes.isEmpty { parts.append("özet") }
        return "Eksik: " + parts.joined(separator: ", ")
    }

    private func run() async {
        let targets = Array(candidates.prefix(limit))
        guard !targets.isEmpty else { return }
        isRunning = true
        isCancelRequested = false
        progress = 0
        total = targets.count
        updated = 0
        message = nil
        defer { isRunning = false }

        var failures = 0
        var failedBooks = 0
        var lastFailure: String?
        let journal = AIDegisiklikToplayici(tool: "tamamla")
        var approved: Set<UUID>?   // nil: kısıtlama yok (önizleme sonrası ya da önizlenecek bir şey yok)
        var previewShown = false
        for start in stride(from: 0, to: targets.count, by: 8) {
            if isCancelRequested { break }
            let batch = Array(targets[start..<min(start + 8, targets.count)])
            do {
                let items = try await AICompletionEngine.complete(batch)
                guard YetkiDurumu.shared.yonetici else { throw CatalogSaveEngine.SaveError(message: "Toplu tamamlama için yönetici kilidini açın.") }
                // İlk partide önizleme: eski → yeni, kitap bazında onay/atla
                if !previewShown {
                    previewShown = true
                    let rows = items.compactMap { item -> OnizlemeSatiri? in
                        guard batch.indices.contains(item.index) else { return nil }
                        let book = batch[item.index]
                        let changes = AICompletionEngine.proposals(item, for: book, fillCategory: fillCategory,
                            fillLanguage: fillLanguage, fillSummary: fillSummary)
                        guard !changes.isEmpty else { return nil }
                        return OnizlemeSatiri(bookID: book.id, title: book.title, changes: changes.map {
                            .init(label: BookFieldMetadata.labels[$0.field] ?? $0.field,
                                  old: BookFieldMetadata.value($0.field, in: book.book), new: String($0.value.prefix(120)))
                        })
                    }
                    if !rows.isEmpty {
                        guard let decision = await requestPreview(rows) else {
                            isCancelRequested = true
                            message = ("Vazgeçildi; hiçbir kitap değiştirilmedi.", false)
                            break
                        }
                        approved = decision
                    }
                }
                let snapshots = batch.map { ($0, $0.book) }
                var batchUpdated = 0
                do {
                    for item in items where batch.indices.contains(item.index) {
                        let book = batch[item.index]
                        guard !book.isDeleted, book.modelContext != nil else { continue }
                        // Önizlemede atlananlar yalnız ilk partiyi etkiler
                        if start == 0, let approved, !approved.contains(book.id) { continue }
                        if AICompletionEngine.apply(item, to: book, fillCategory: fillCategory,
                            fillLanguage: fillLanguage, fillSummary: fillSummary, journal: journal) { batchUpdated += 1; book.refreshSearchKey() }
                    }
                    try modelContext.save()
                    updated += batchUpdated
                    journal.commit()
                } catch {
                    journal.discard()
                    snapshots.forEach { model, previous in if !model.isDeleted { model.update(from: previous) } }
                    throw error
                }
                failures = 0 // "üst üste" sayacı: başarıda sıfırlanır
            } catch {
                failures += 1
                failedBooks += batch.count
                lastFailure = (error as? GeminiError)?.errorDescription ?? error.localizedDescription
                if failures >= 3 {
                    message = ("Üst üste hata alındı, durduruldu: \((error as? GeminiError)?.errorDescription ?? error.localizedDescription)", true)
                    break
                }
            }
            progress = min(start + 8, targets.count)
        }
        if message == nil {
            if failedBooks > 0 {
                message = ("\(updated) kitap güncellendi; \(failedBooks) kitap tamamlanamadı. Eksikler sırada kaldı, yeniden deneyebilirsiniz. \(lastFailure ?? "")", true)
            } else {
                message = (isCancelRequested
                           ? "Durduruldu. \(updated) kitap güncellendi."
                           : "Tamamlandı. \(updated) kitap güncellendi.", false)
            }
        }
        AccessibilityNotification.Announcement(message?.text ?? "").post()
    }
}

// MARK: - 3) Kitap Öner

nonisolated struct AIRecommendation: Codable, Sendable {
    var title: String
    var reason: String
    var bookID: String? = nil
}

nonisolated struct AIRecommendationReply: Codable, Sendable {
    var recommendations: [AIRecommendation]
    var note: String?
}

enum AIRecommendEngine {
    static let systemPrompt = """
    Sen bir okul kütüphanecisisin. Sana öğrenci bilgisi (sınıf, ilgi alanları, daha önce okuduğu \
    kitaplar) ve kütüphanede ŞU AN BOŞTA olan kitapların listesi verilecek. YALNIZCA bu listeden \
    seç; listede olmayan kitap önerme. Öğrencinin yaş/sınıf düzeyine uygun, daha önce okumadığı, \
    ilgi alanlarıyla örtüşen kitapları seç ve her biri için bir cümle Türkçe gerekçe yaz. \
    Her öneride listedeki bookID kimliğini aynen kopyala. YALNIZCA JSON döndür: \
    {"recommendations": [{"bookID": "listedeki UUID", "title": "liste ile AYNEN aynı ad", "reason": ""}], "note": "kısa genel not"}
    """

    static func recommend(
        className: String, studentName: String, interests: String, previous: [String],
        candidates: [CatalogBook], loans: [ActiveLoan], count: Int
    ) async throws -> AIRecommendationReply {
        // Kısmen ödünçteki kitabın satırı gerçek okur adını taşımasın: takma adla yazılır
        let aliases = PersonAliases()
        let list = candidates.map { "bookID=\($0.id.uuidString) | " + AssistantContext.line(for: $0, loans: loans, aliases: aliases) }.joined(separator: "\n- ")
        // Öğrencinin adı Google'a gönderilmez; yalnızca sınıf ve okuma geçmişi (kitap adları) gider
        let prompt = """
        ÖĞRENCİ: \(studentName.isEmpty ? "sınıfın geneli" : "bir öğrenci"), sınıf: \(className.isEmpty ? "belirtilmedi" : className)
        İLGİ ALANLARI: \(interests.isEmpty ? "belirtilmedi" : interests)
        DAHA ÖNCE OKUDUĞU: \(previous.isEmpty ? "kayıt yok" : previous.joined(separator: "; "))
        İSTENEN ÖNERİ SAYISI: \(count)

        BOŞTA OLAN KİTAPLAR:
        - \(list)
        """
        return try await GeminiClient.shared.generateJSON(
            AIRecommendationReply.self,
            prompt: prompt,
            system: systemPrompt,
            temperature: 0.6,
            maxOutputTokens: 2048,
            thinking: .auto
        )
    }

    /// Yapılandırılmış JSON, kitabın katalogda ve müsait olduğunu kanıtlamaz.
    /// Eski yanıtlar yalnız aday listesinde tek, tam başlık eşleşmesi varsa kabul edilir.
    static func validated(_ reply: AIRecommendationReply, candidates: [CatalogBook], loans: [ActiveLoan],
                          copies: [BookCopy] = [], reservations: [Reservation] = [], count: Int = 8) -> AIRecommendationReply {
        let byID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
        let byTitle = Dictionary(grouping: candidates, by: { CatalogMatcher.normalize($0.title) })
        var seen = Set<UUID>()
        let items = reply.recommendations.compactMap { item -> AIRecommendation? in
            let book: CatalogBook?
            if let value = item.bookID {
                book = UUID(uuidString: value).flatMap { byID[$0] }
            } else {
                let exact = byTitle[CatalogMatcher.normalize(item.title)] ?? []
                book = exact.count == 1 ? exact.first : nil
            }
            guard let book, !seen.contains(book.id),
                  SchoolLibraryService.stock(for: book, loans: loans, copies: copies, reservations: reservations).available > 0 else { return nil }
            seen.insert(book.id)
            return AIRecommendation(title: book.title, reason: String(item.reason.prefix(600)), bookID: book.id.uuidString)
        }
        var result = reply
        result.recommendations = Array(items.prefix(max(0, count)))
        let removed = reply.recommendations.count - result.recommendations.count
        if removed > 0 {
            result.note = [reply.note, "Katalog/müsaitlik kontrolünde \(removed) öneri çıkarıldı."].compactMap { $0 }.joined(separator: " ")
        }
        return result
    }
}

struct AIRecommendPage: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CatalogBook.title) private var books: [CatalogBook]
    @Query private var loans: [ActiveLoan]
    @Query private var copies: [BookCopy]
    @Query private var reservations: [Reservation]

    @State private var className = ""
    @State private var studentID: UUID?
    private var studentName: String { students.first { $0.id == studentID }?.name ?? "" }
    @State private var interests = ""
    @State private var count = 5
    @State private var isWorking = false
    @State private var reply: AIRecommendationReply?
    @State private var message: (text: String, isError: Bool)?
    @State private var selectedBook: CatalogBook?
    @State private var candidateIDs = Set<UUID>()

    private var classNames: [String] { StudentStore.classNames() }
    private var students: [Student] { className.isEmpty ? [] : StudentStore.students(in: className) }

    var body: some View {
        Form {
            Section("Kime?") {
                Picker("Sınıf", selection: $className) {
                    Text("Seçilmedi").tag("")
                    ForEach(classNames, id: \.self) { Text($0).tag($0) }
                }
                if !students.isEmpty {
                    Picker("Öğrenci", selection: $studentID) {
                        Text("Tüm sınıf").tag(Optional<UUID>.none)
                        ForEach(students) { Text("\($0.name) · No \($0.number)").tag(Optional($0.id)) }
                    }
                }
                TextField("İlgi alanları (macera, uzay, hayvanlar…)", text: $interests)
                    .accessibilityLabel("İlgi alanları")
                Stepper("Öneri sayısı: \(count)", value: $count, in: 3...8)
            }
            .disabled(isWorking)
            .onChange(of: className) { studentID = nil; reply = nil }
            .onChange(of: studentID) { reply = nil }
            .onChange(of: interests) { reply = nil }
            .onChange(of: count) { reply = nil }

            Section {
                Button {
                    Task { await recommend() }
                } label: {
                    Label(isWorking ? "Öneriler hazırlanıyor…" : "Öneri İste", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.kitapDolu(KitapTema.toplu))
                .disabled(isWorking || books.isEmpty)
                if let message {
                    StatusMessage(text: message.text, isError: message.isError)
                }
            } footer: {
                Text("Yalnızca şu an boşta olan kitaplardan seçilir; öğrencinin ödünç geçmişindeki kitaplar önerilmez.")
            }

            if let reply {
                Section("Öneriler") {
                    // Model aynı adı iki kez döndürebilir; kimlik olarak sıra kullanılır
                    ForEach(Array(reply.recommendations.enumerated()), id: \.offset) { _, item in
                        let book = match(item)
                        Button {
                            if let book { selectedBook = book }
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                CoverThumb(data: book?.coverData, size: 44)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title).font(.subheadline.weight(.semibold))
                                    if let book { Text(book.author).font(.caption).foregroundStyle(.secondary) }
                                    Text(item.reason).font(.caption)
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(book == nil)
                        .accessibilityElement(children: .combine)
                    }
                    if let note = reply.note, !note.isEmpty {
                        Text(note).font(.footnote).foregroundStyle(.secondary)
                    }
                    if let url = recommendationPDF(reply) {
                        ShareLink(item: url) {
                            Label("Okuma Listesini PDF Paylaş", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
        .navigationTitle("Kitap Öner")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedBook) { book in
            AIBookInfoSheet(book: book, loans: loans)
                .presentationDetents([.medium, .large])
        }
    }

    /// Sınıfa/öğrenciye dağıtılabilir okuma listesi (öğrenci adı PDF'e yazılmaz).
    private func recommendationPDF(_ reply: AIRecommendationReply) -> URL? {
        let rows: [(String, String)] = reply.recommendations.compactMap { item in
            guard let book = match(item) else { return nil }
            return ("\(book.title) — \(book.author)\n\(item.reason)", book.konumMetni ?? "")
        }
        guard !rows.isEmpty else { return nil }
        let pdf = PDFReportBuilder.build(
            title: "Okuma Listesi" + (className.isEmpty ? "" : " — \(className)"),
            subtitle: [interests.isEmpty ? nil : "İlgi: \(interests)", Date.now.formatted(date: .long, time: .omitted)]
                .compactMap { $0 }.joined(separator: " · "),
            sections: [.init(title: "Önerilen kitaplar", rows: rows)]
        )
        return SharedPDF.write(pdf, name: "Okuma-Listesi")
    }

    private func match(_ item: AIRecommendation) -> CatalogBook? {
        guard let id = item.bookID.flatMap(UUID.init(uuidString:)), candidateIDs.contains(id),
              let book = books.first(where: { $0.id == id }),
              SchoolLibraryService.stock(for: book, loans: loans, copies: copies, reservations: reservations).available > 0 else { return nil }
        return book
    }

    private func recommend() async {
        guard !isWorking else { return }
        isWorking = true
        message = nil
        defer { isWorking = false }
        let history: [LoanEvent]
        do { history = try SchoolLibraryService.historySnapshot(context: modelContext) }
        catch { message = ("Ödünç geçmişi okunamadı: \(error.localizedDescription)", true); return }
        let previous = studentID.map { id in
            history.filter { event in
                event.studentID == id || (event.studentID == nil && event.classSnapshot == className
                    && CatalogMatcher.normalize(event.person) == CatalogMatcher.normalize(studentName))
            }.map(\.bookTitle)
        } ?? []
        let previousSet = Set(previous.map(CatalogMatcher.normalize))
        let candidates = AssistantContext.availableSample(from: books, loans: loans, limit: 150)
            .filter { !previousSet.contains(CatalogMatcher.normalize($0.title)) }
            .filter { SchoolLibraryService.stock(for: $0, loans: loans, copies: copies, reservations: reservations).available > 0 }
        guard !candidates.isEmpty else {
            message = ("Şu an boşta kitap yok.", true)
            return
        }
        candidateIDs = Set(candidates.map(\.id))
        reply = nil
        do {
            let generated = try await AIRecommendEngine.recommend(
                className: className, studentName: studentName, interests: interests,
                previous: Array(Set(previous)).prefix(30).map { $0 },
                candidates: candidates, loans: loans, count: count
            )
            reply = AIRecommendEngine.validated(generated, candidates: books.filter { candidateIDs.contains($0.id) },
                loans: loans, copies: copies, reservations: reservations, count: count)
            if reply?.recommendations.isEmpty == true { message = ("Müsait ve doğrulanmış öneri bulunamadı; tekrar deneyebilirsiniz.", false) }
            AccessibilityNotification.Announcement("\(reply?.recommendations.count ?? 0) öneri hazır").post()
        } catch {
            message = ((error as? GeminiError)?.errorDescription ?? error.localizedDescription, true)
        }
    }
}

// MARK: - 4) Kitap Kartı

nonisolated struct AIBookCard: Codable, Sendable {
    var summary: String
    var keywords: [String]?
    var readingLevel: String?
    var themes: [String]?
    var discussionQuestions: [String]?
}

enum AIBookCardEngine {
    static let systemPrompt = """
    Sen bir Türkçe öğretmeni ve kütüphanecisin. Verilen kitap için öğrencilere yönelik bir \
    "kitap kartı" hazırla. Kitabı tanımıyorsan uydurma; genel bilgiyle sınırlı kal ve bunu \
    summary içinde belirt. YALNIZCA JSON döndür:
    {"summary": "3–4 cümle tanıtım", "keywords": ["5-8 anahtar sözcük"], "readingLevel": "örn. 5–7. sınıf", \
    "themes": ["temalar"], "discussionQuestions": ["3 tartışma sorusu"]}
    """

    static func card(for book: CatalogBook) async throws -> AIBookCard {
        let prompt = """
        KİTAP: \(book.title)
        YAZAR: \(book.author)
        YAYINEVİ: \(book.publisher ?? "") \(book.publicationYear ?? "")
        KATEGORİ: \(book.category ?? "")
        MEVCUT NOT: \(book.notes)
        """
        return try await GeminiClient.shared.generateJSON(
            AIBookCard.self, prompt: prompt, system: systemPrompt, temperature: 0.5, maxOutputTokens: 1500
        )
    }
}

struct AIBookCardPage: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CatalogBook.title) private var books: [CatalogBook]

    @State private var searchText = ""
    @State private var selected: CatalogBook?
    @State private var card: AIBookCard?
    @State private var isWorking = false
    @State private var message: (text: String, isError: Bool)?

    private var matches: [CatalogBook] {
        let term = CatalogMatcher.normalize(searchText)
        guard term.count >= 2 else { return [] }
        return books.filter {
            CatalogMatcher.normalize($0.title).contains(term) || CatalogMatcher.normalize($0.author).contains(term)
        }.prefix(8).map { $0 }
    }

    var body: some View {
        Form {
            Section("Kitap seç") {
                TextField("Kitap adı ya da yazar ara", text: $searchText)
                    .accessibilityLabel("Kitap ara")
                ForEach(matches) { book in
                    Button {
                        selected = book
                        card = nil
                        searchText = ""
                    } label: {
                        HStack {
                            CoverThumb(data: book.coverData, size: 32)
                            VStack(alignment: .leading) {
                                Text(book.title).font(.subheadline)
                                Text(book.author).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isWorking) // istek sürerken kitap değiştirilemez (yanıt yanlış kitaba yazılmasın)
                }
                if let selected, !selected.isDeleted, selected.modelContext != nil {
                    HStack {
                        CoverThumb(data: selected.coverData, size: 40)
                        VStack(alignment: .leading) {
                            Text(selected.title).font(.headline)
                            Text(selected.author).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            Task { await generate(for: selected) }
                        } label: {
                            Label("Kart Üret", systemImage: "sparkles")
                        }
                        .buttonStyle(.kitapDolu(KitapTema.dosya))
                        .disabled(isWorking)
                    }
                }
                if isWorking { ProgressView("Gemini kartı hazırlıyor…") }
                if let message { StatusMessage(text: message.text, isError: message.isError) }
            }

            if let card, let selected, !selected.isDeleted, selected.modelContext != nil {
                Section("Tanıtım") {
                    Text(card.summary).textSelection(.enabled)
                    if let level = card.readingLevel, !level.isEmpty {
                        LabeledContent("Okuma düzeyi", value: level)
                    }
                }
                if let keywords = card.keywords, !keywords.isEmpty {
                    Section("Anahtar sözcükler") {
                        FlowChips(items: keywords, color: KitapTema.dosya)
                    }
                }
                if let themes = card.themes, !themes.isEmpty {
                    Section("Temalar") {
                        FlowChips(items: themes, color: KitapTema.toplu)
                    }
                }
                if let questions = card.discussionQuestions, !questions.isEmpty {
                    Section("Tartışma soruları") {
                        ForEach(Array(questions.enumerated()), id: \.offset) { index, question in
                            Text("\(index + 1). \(question)")
                        }
                    }
                }
                Section {
                    Button {
                        saveToNotes(card, book: selected)
                    } label: {
                        Label("Özeti Kitabın Notlarına Kaydet", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.kitapDolu(KitapTema.basari))
                }
            }
        }
        .navigationTitle("Kitap Kartı")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func generate(for book: CatalogBook) async {
        isWorking = true
        message = nil
        defer { isWorking = false }
        let requestedID = book.id
        do {
            let result = try await AIBookCardEngine.card(for: book)
            // Bekleme sırasında başka kitap seçildiyse eski yanıt gösterilmez
            guard selected?.id == requestedID else { return }
            card = result
            AccessibilityNotification.Announcement("Kitap kartı hazır").post()
        } catch {
            message = ((error as? GeminiError)?.errorDescription ?? error.localizedDescription, true)
        }
    }

    private func saveToNotes(_ card: AIBookCard, book: CatalogBook) {
        guard YetkiDurumu.shared.yonetici else { message = ("Not düzenlemek için yönetici kilidini açın.", true); return }
        guard !book.isDeleted, book.modelContext != nil else { return }
        let previous = book.notes
        var note = card.summary
        if let keywords = card.keywords, !keywords.isEmpty {
            note += "\nAnahtar sözcükler: " + keywords.joined(separator: ", ")
        }
        book.notes = book.notes.isEmpty ? note : book.notes + "\n\n" + note
        do {
            try modelContext.save()
            message = ("Notlara kaydedildi.", false)
        } catch {
            book.notes = previous
            message = ("Kaydedilemedi: \(error.localizedDescription)", true)
        }
    }
}

/// Satır sonunda kıvrılan etiketler (anahtar sözcük, tema).
struct FlowChips: View {
    let items: [String]
    let color: Color

    var body: some View {
        // Basit ve erişilebilir: dikey akış yerine yatay kaydırma, Dynamic Type ile büyür
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.self) { item in
                    Text(item)
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(color.opacity(0.14), in: .capsule)
                        .foregroundStyle(color)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(items.joined(separator: ", "))
    }
}

// MARK: - Ayarlar bölümü

/// Ayarlar formuna eklenen "Yapay Zekâ" bölümü.
struct GeminiSettingsSection: View {
    @AppStorage(GeminiSettings.enabledKey) private var aiEnabled = true
    @AppStorage(GeminiSettings.ocrEnabledKey) private var ocrEnabled = true
    @AppStorage(GeminiSettings.voiceRepliesKey) private var voiceReplies = true
    @AppStorage(GeminiSettings.modelKey) private var modelRaw = GeminiModel.flash.rawValue
    @AppStorage(GeminiSettings.consentKey) private var consentGiven = false
    @AppStorage(GeminiSettings.ttsEnabledKey) private var ttsEnabled = true
    @AppStorage(GeminiSettings.ttsVoiceKey) private var ttsVoiceRaw = GeminiTTSVoice.kore.rawValue

    @State private var previewVoice = SpeechOutput()
    @AppStorage(GeminiSettings.quickSaveKey) private var quickSave = false
    @AppStorage(GeminiSettings.briefConfirmKey) private var briefConfirm = false
    @AppStorage(GeminiSettings.speechOnDeviceKey) private var speechOnDevice = false
    @AppStorage(EnrichmentQueue.enabledKey) private var autoEnrich = true
    @AppStorage(GeminiSettings.proxyURLKey) private var proxyURL = ""
    @State private var usage = GeminiUsage.load()
    @AppStorage(GeminiUsage.limitKey) private var monthlyLimit = 0
    @AppStorage(GeminiUsage.inputPriceKey) private var inputPrice = GeminiUsage.defaultInputPrice
    @AppStorage(GeminiUsage.outputPriceKey) private var outputPrice = GeminiUsage.defaultOutputPrice
    @State private var keyInput = GeminiKeyStore.loadCustomKey()
    @State private var testResult: (text: String, isError: Bool)?
    @State private var isTesting = false

    var body: some View {
        Section {
            Toggle("Yapay zekâ özellikleri", isOn: $aiEnabled)
            Toggle("Ana OCR: Gemini (kapalıysa cihaz OCR)", isOn: $ocrEnabled)
                .disabled(!aiEnabled)
            Toggle("Asistan yanıtlarını sesli oku", isOn: $voiceReplies)
                .disabled(!aiEnabled)
            Toggle("Gemini HD ses (kapalıysa cihaz sesi)", isOn: $ttsEnabled)
                .disabled(!aiEnabled || !voiceReplies)
            Picker("HD ses", selection: $ttsVoiceRaw) {
                ForEach(GeminiTTSVoice.allCases) { Text($0.displayName).tag($0.rawValue) }
            }
            // Uzun ses adları menüde kırpılıyordu; ayrı sayfada tam görünür
            .pickerStyle(.navigationLink)
            .disabled(!aiEnabled || !voiceReplies || !ttsEnabled)
            Button {
                if previewVoice.isSpeaking {
                    previewVoice.stop()
                } else {
                    previewVoice.speak("Merhaba! Ben kütüphane asistanınız. Bugün hangi kitabı arıyoruz?")
                }
            } label: {
                Label(previewVoice.isPreparing ? "Ses hazırlanıyor…" : (previewVoice.isSpeaking ? "Çalıyor… (durdur)" : "Sesi Dinle"),
                      systemImage: previewVoice.isSpeaking ? "stop.circle" : "play.circle")
            }
            .disabled(!aiEnabled || !voiceReplies)
            .accessibilityHint("Seçili sesle örnek cümle okur")
            Picker("Model", selection: $modelRaw) {
                ForEach(GeminiModel.allCases) { Text($0.displayName).tag($0.rawValue) }
            }
            .disabled(!aiEnabled)

            Toggle("Hızlı mod: emin olunan taramayı onaysız kaydet", isOn: $quickSave)
                .disabled(!aiEnabled)
                .accessibilityHint("Gemini tüm alanlardan emin ve fotoğraf iyiyse düzenleyici açılmaz")
            Toggle("Kayıttan sonra AI ile zenginleştir (arka planda)", isOn: $autoEnrich)
                .disabled(!aiEnabled)
            Toggle("Sesli kayıtta kısa onay (titreşim + “Kaydedildi”)", isOn: $briefConfirm)
            Toggle("Konuşma tanıma cihaz üstünde (internetsiz)", isOn: $speechOnDevice)
                .accessibilityHint("Türkçe dikte modeli cihazda yüklüyse internet gerekmez")

            TextField("Vekil sunucu adresi (isteğe bağlı)", text: $proxyURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .accessibilityHint("Boşsa istekler doğrudan Google'a gider; okul sunucunuz anahtarı saklayabilir")

            VStack(alignment: .leading, spacing: 4) {
                Label("Bu ay: \(usage.requests) istek · \(usage.promptTokens + usage.outputTokens) jeton", systemImage: "gauge.with.dots.needle.33percent")
                    .font(.subheadline)
                if usage.failures > 0 {
                    Text("\(usage.failures) başarısız istek").font(.caption).foregroundStyle(KitapTema.vurgu)
                }
                Text("\(GeminiUsage.costLabel) maliyet: $\(GeminiUsage.estimatedCostUSD(usage, inputPrice: inputPrice, outputPrice: outputPrice), specifier: "%.3f") (ücretsiz katmanda 0)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if usage.retries > 0 {
                    Text("\(usage.retries) yeniden deneme (sınıra sayılmaz)").font(.caption).foregroundStyle(.secondary)
                }
                if !usage.byModel.isEmpty {
                    DisclosureGroup("Modele göre kullanım (tahmini)") {
                        ForEach(usage.byModel.keys.sorted(), id: \.self) { name in
                            let item = usage.byModel[name] ?? GeminiUsage.ModelUsage()
                            let cost = GeminiUsage.estimatedCostUSD(GeminiUsage.Snapshot(month: usage.month, promptTokens: item.promptTokens, outputTokens: item.outputTokens),
                                                                    inputPrice: inputPrice, outputPrice: outputPrice)
                            LabeledContent(name == GeminiUsage.ttsModelName ? "HD ses (TTS)" : name) {
                                Text("\(item.requests) istek · $\(cost, specifier: "%.3f")")
                            }
                        }
                    }
                    .font(.footnote)
                }
                if monthlyLimit > 0 {
                    ProgressView(value: Double(min(usage.requests, monthlyLimit)), total: Double(monthlyLimit)) {
                        Text("Aylık sınır: \(usage.requests)/\(monthlyLimit)").font(.caption)
                    }
                    .tint(usage.requests >= monthlyLimit ? .red : KitapTema.ana)
                }
                if !EnrichmentQueue.pendingIDs.isEmpty {
                    Text("Zenginleştirme kuyruğunda \(EnrichmentQueue.pendingIDs.count) kitap").font(.caption).foregroundStyle(.secondary)
                }
            }
            .onAppear { usage = GeminiUsage.load() }

            Stepper(monthlyLimit == 0 ? "Aylık istek sınırı: yok" : "Aylık istek sınırı: \(monthlyLimit)",
                    value: $monthlyLimit, in: 0...100_000, step: monthlyLimit < 1000 ? 100 : 1000)
                .accessibilityHint("Sınıra ulaşınca yapay zekâ ay sonuna kadar durur; 0 sınırsız demektir")
            DisclosureGroup("Fiyat varsayımları (1M jeton, USD)") {
                LabeledContent("Girdi") {
                    TextField("Girdi", value: $inputPrice, format: .number.precision(.fractionLength(2)))
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                }
                LabeledContent("Çıktı") {
                    TextField("Çıktı", value: $outputPrice, format: .number.precision(.fractionLength(2)))
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                }
            }
            .font(.footnote)

            Toggle("Veri paylaşım onayı (Google Gemini)", isOn: $consentGiven)
                .disabled(!aiEnabled)
                .accessibilityHint("Kapatılırsa hiçbir yapay zekâ isteği gönderilmez")

            SecureField("Bu cihazın API anahtarı", text: $keyInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel("Gemini API anahtarı")
            HStack {
                Button("Anahtarı Kaydet") {
                    do {
                        try GeminiKeyStore.saveCustomKeyVerified(keyInput)
                        testResult = (keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                      ? "Bu cihazın anahtarı silindi." : "Anahtar bu cihazın güvenli deposuna kaydedildi.", false)
                    } catch { testResult = (error.localizedDescription, true) }
                }
                Spacer()
                Button {
                    Task { await testConnection() }
                } label: {
                    if isTesting { ProgressView() } else { Text("Bağlantıyı Test Et") }
                }
                .disabled(isTesting || !aiEnabled)
            }
            if let testResult {
                StatusMessage(text: testResult.text, isError: testResult.isError)
            }
        } header: {
            Label("Yapay Zekâ (Gemini)", systemImage: "sparkles")
                .foregroundStyle(KitapTema.ana)
        } footer: {
            Text("Gemini OCR, kapak fotoğrafından ad/yazar/ISBN gibi alanları cihaz OCR'ından daha isabetli çıkarır; hata olursa cihaz OCR sonucu kullanılır. Sorular, katalog özeti ve fotoğraflar Google'a gönderilir; öğrenci ve üye adları takma adla iletilir. Kendi Google AI Studio anahtarınızı girebilirsiniz; anahtar yalnızca bu cihazın Keychain'inde saklanır.")
        }
    }

    private func testConnection() async {
        isTesting = true
        defer { isTesting = false }
        do {
            // Düşünen modeller küçük jeton bütçesini akıl yürütmeye harcayıp boş dönebilir;
            // bütçe bol tutulur, gösterilen metin kısaltılır.
            let text = try await GeminiClient.shared.generateText(
                prompt: "Sadece 'OK' yaz.", temperature: 0, maxOutputTokens: 512
            )
            let shown = text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40)
            testResult = ("Bağlantı başarılı (\(GeminiSettings.model.displayName)): \(shown)", false)
        } catch {
            testResult = ((error as? GeminiError)?.errorDescription ?? error.localizedDescription, true)
        }
    }
}
