import Foundation
import SwiftUI

// MARK: - Toplu onay ekranı

/// Seri tarama / toplu fotoğraf sonrası biriken taslakların tek listede onaylanması.
/// Önce "Kontrol gerekli", sonra "Hazır" bölümü gelir. Satıra dokununca düzenleme açılır; kaydırarak
/// silinir; "Adı Olanları Kaydet" adı dolu taslakları kataloğa ekler, adı boş olanlar kuyrukta kalır.
struct BatchReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var drafts: [BookDraft]
    let onEditionDecision: ((UUID, CatalogSaveDecision) -> Void)?
    let editionDecision: ((UUID) -> CatalogSaveDecision)?
    /// Kaydeder ve sonuç cümlesini döndürür; kuyrukta kayıt kalırsa listenin üstünde gösterilir.
    let onSaveAll: () -> String?

    @State private var editingDraft: BookDraft?
    /// Bölümler yazarken değişmesin (satır yer değiştirip odak kaybolmasın) diye sınıflandırma liste değişince,
    /// düzenleme kapanınca ya da ad alanından çıkılınca yenilenir.
    @State private var kontrolKimlikleri: Set<UUID> = []
    @State private var sonuc: String?
    @State private var yenidenAraniyor = false

    init(drafts: Binding<[BookDraft]>,
         onEditionDecision: ((UUID, CatalogSaveDecision) -> Void)? = nil,
         editionDecision: ((UUID) -> CatalogSaveDecision)? = nil,
         onSaveAll: @escaping () -> String?) {
        _drafts = drafts
        self.onEditionDecision = onEditionDecision
        self.editionDecision = editionDecision
        self.onSaveAll = onSaveAll
    }

    /// Kuyrukta aynı kitap iki kez mi var? (aynı ISBN ya da benzer ad+yazar)
    private func isDuplicate(_ candidate: BookDraft) -> Bool {
        drafts.contains { other in
            guard other.id != candidate.id else { return false }
            let candidateISBN = ISBNFormatter.normalize(candidate.isbn)
            let otherISBN = ISBNFormatter.normalize(other.isbn)
            if !candidateISBN.isEmpty, candidateISBN == otherISBN { return true }
            guard !candidate.title.isEmpty else { return false }
            return CatalogMatcher.isSimilarTitle(candidate.title, other.title)
        }
    }

    private var kaydedilebilir: Int { EkleOzeti.kaydedilebilirSayisi(drafts) }

    /// Şüpheli alanı olan ve ISBN'i bilinen taslakları kaynaklardan 3'lü paralel yeniden sorgular.
    private func suphelileriYenidenAra() async {
        let hedefler = SupheliAlanOnarimi.aranabilir(drafts).map { ($0.id, ISBNFormatter.normalize($0.isbn)) }
        guard !hedefler.isEmpty else { return }
        yenidenAraniyor = true
        defer { yenidenAraniyor = false }
        var duzelen = 0
        var ulasilamayan = 0
        for baslangic in stride(from: 0, to: hedefler.count, by: 3) {
            let parca = Array(hedefler[baslangic..<min(baslangic + 3, hedefler.count)])
            await withTaskGroup(of: (UUID, KunyeSonucu).self) { grup in
                for (id, isbn) in parca {
                    grup.addTask { (id, await BookMetadataService.fetchSonucu(isbn: isbn)) }
                }
                for await (id, sonuc) in grup {
                    guard let index = drafts.firstIndex(where: { $0.id == id }) else { continue }
                    if let meta = sonuc.meta {
                        if SupheliAlanOnarimi.uygula(meta, to: &drafts[index]) { duzelen += 1 }
                    } else if sonuc.erisimSorunuVar {
                        ulasilamayan += 1
                    }
                }
            }
            if Task.isCancelled { break }
        }
        bolumleriYenile()
        sonuc = "\(hedefler.count) taslak yeniden arandı: \(duzelen) kayıt güncellendi"
            + (ulasilamayan > 0 ? ", \(ulasilamayan) kayıt için kaynaklara ulaşılamadı." : ".")
    }

    private func bolumleriYenile() {
        kontrolKimlikleri = Set(drafts.filter { EkleOzeti.kontrolGerekli($0) }.map(\.id))
    }

    /// Satır içi ad alanı kimlikle bağlanır: silme sonrası eski konuma yazılmaz.
    private func adBaglantisi(_ id: UUID) -> Binding<String> {
        Binding(
            get: { drafts.first { $0.id == id }?.title ?? "" },
            set: { yeni in
                if let index = drafts.firstIndex(where: { $0.id == id }) { drafts[index].title = yeni }
            }
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if drafts.isEmpty {
                    ContentUnavailableView {
                        Label("Kuyruk boş", systemImage: "tray")
                    } description: {
                        Text("Bekleyen taranmış kitap yok.")
                    }
                } else {
                    let kontrol = drafts.filter { kontrolKimlikleri.contains($0.id) }
                    let hazir = drafts.filter { !kontrolKimlikleri.contains($0.id) }
                    List {
                        // Kaydetme sonucu sayfa kapanmadan, listenin üstünde okunur
                        if let sonuc {
                            Section {
                                Label(sonuc, systemImage: "info.circle")
                                    .font(.subheadline)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier("batch.result")
                            }
                        }
                        if !SupheliAlanOnarimi.aranabilir(drafts).isEmpty {
                            Section {
                                Button {
                                    Task { await suphelileriYenidenAra() }
                                } label: {
                                    Label(yenidenAraniyor ? "Yeniden aranıyor…" : "Şüphelileri yeniden ara (\(SupheliAlanOnarimi.aranabilir(drafts).count))",
                                          systemImage: "arrow.triangle.2.circlepath")
                                }
                                .disabled(yenidenAraniyor)
                                .accessibilityIdentifier("batch.recheck")
                            } footer: {
                                Text("ISBN'i olan ve şüpheli alanı bulunan kitaplar kaynaklarda yeniden aranır; onayladığınız alanlara dokunulmaz.")
                            }
                        }
                        if !kontrol.isEmpty {
                            Section("Kontrol gerekli (\(kontrol.count))") {
                                ForEach(kontrol) { satir($0) }
                                    .onDelete { sil($0, in: kontrol) }
                            }
                        }
                        if !hazir.isEmpty {
                            Section("Hazır (\(hazir.count))") {
                                ForEach(hazir) { satir($0) }
                                    .onDelete { sil($0, in: hazir) }
                            }
                        }
                    }
                    .safeAreaInset(edge: .bottom) {
                        Button {
                            sonuc = onSaveAll()
                            // Kaydedilemeyen ya da baskı kararı bekleyen taslaklar burada kalır.
                            if drafts.isEmpty { dismiss() } else { bolumleriYenile() }
                        } label: {
                            Label("Adı Olanları Kaydet (\(kaydedilebilir))", systemImage: "tray.and.arrow.down.fill")
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .buttonStyle(.kitapDolu())
                        .disabled(kaydedilebilir == 0)
                        .accessibilityIdentifier("batch.saveNamed")
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(.bar)
                    }
                }
            }
            .navigationTitle("Taranan Kitaplar (\(drafts.count))")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
            .onAppear { bolumleriYenile() }
            .onChange(of: drafts.map(\.id)) { bolumleriYenile() }
            .sheet(item: $editingDraft, onDismiss: bolumleriYenile) { editing in
                BookEditorView(validating: editing, save: { book in
                    guard let index = drafts.firstIndex(where: { $0.id == editing.id }) else {
                        return .failed("Taslak artık kuyrukta bulunmuyor.")
                    }
                    var updated = BookDraft(book: book)
                    // Kullanıcı kaydı elle gözden geçirip onayladı: lowConfidenceFields ve bilgiNotu
                    // bilerek taşınmaz (satır "Hazır" bölümüne geçer); okuma kaynağı korunur.
                    // Düzenleme yeni katalog kaydı değildir; kuyruk ve karar kimliği korunur.
                    updated.id = editing.id
                    updated.existingBookID = editing.existingBookID
                    updated.recognizedByGemini = editing.recognizedByGemini
                    updated.recognitionSource = editing.recognitionSource
                    drafts[index] = updated
                    return .updated
                }, initialMergeDecision: editionDecision?(editing.snapshot.id) ?? .automatic,
                   onMergeDecision: onEditionDecision.map { callback in
                       { decision in callback(editing.snapshot.id, decision) }
                   })
            }
        }
    }

    private func satir(_ draft: BookDraft) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Satır içi düzenleme: adı hemen buradan düzeltebilirsin (ad satırda bir kez görünür)
            HStack {
                TextField("Kitap adı", text: adBaglantisi(draft.id))
                    .font(.headline)
                    .submitLabel(.done)
                    .onSubmit { bolumleriYenile() }
                if isDuplicate(draft) {
                    Image(systemName: "exclamationmark.2")
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Kuyrukta aynı kitap birden fazla")
                }
            }

            Button {
                editingDraft = draft
            } label: {
                BatchDraftRow(draft: draft)
            }
            .buttonStyle(.plain)
            // Ad satırda görsel olarak bir kez yazar; VoiceOver'da düğme hangi kitabı açtığını adıyla söyler
            .accessibilityLabel(satirEtiketi(draft))
            .accessibilityValue(satirDegeri(draft))
            .accessibilityHint("Tüm bilgileri düzenler")
        }
    }

    private func satirEtiketi(_ draft: BookDraft) -> String {
        let ad = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return ad.isEmpty ? "Adı okunamamış kitap" : ad
    }

    /// Durum, yazar ve ISBN; boş olanlar okunmaz.
    private func satirDegeri(_ draft: BookDraft) -> String {
        [EkleOzeti.kontrolGerekli(draft) ? "Kontrol gerekli" : "Hazır",
         draft.author.trimmingCharacters(in: .whitespacesAndNewlines),
         draft.isbn.isEmpty ? "" : "ISBN \(draft.isbn)"]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    private func sil(_ offsets: IndexSet, in bolum: [BookDraft]) {
        let silinecek = Set(offsets.map { bolum[$0].id })
        drafts.removeAll { silinecek.contains($0.id) }
    }
}

private struct BatchDraftRow: View {
    let draft: BookDraft

    var body: some View {
        HStack(spacing: 12) {
            if
                let data = draft.coverData,
                let image = CoverImageDecoder.thumbnail(from: data, maxPixelSize: 120)
            {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 56)
                    .clipShape(.rect(cornerRadius: 6))
            } else {
                Image(systemName: "book.closed")
                    .frame(width: 40, height: 56)
                    .background(.quaternary, in: .rect(cornerRadius: 6))
                    .accessibilityHidden(true)
            }

            // Kitap adı üstteki alanda; burada yalnız ad yoksa ne yapılacağı yazar
            VStack(alignment: .leading, spacing: 2) {
                if draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Ad okunamadı — üstteki alana yazın")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !draft.author.isEmpty {
                    Text(draft.author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if !draft.isbn.isEmpty {
                    Text("ISBN: \(draft.isbn)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let konumFarki = draft.konumFarki {
                    Text(konumFarki)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            if EkleOzeti.kontrolGerekli(draft) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Kontrol gerekli")
            } else {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.green)
                    .accessibilityLabel("Hazır")
            }
        }
    }
}

// MARK: - Seri tarama kurulumu

/// Seri tarama başlamadan önce hedef raf/konum ve otomatik kayıt tercihi sorulur.
struct ScanSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onStart: (BulkAssignment, Bool) -> Void

    @State private var assignment: BulkAssignment
    @State private var autoSave = true
    @AppStorage(SeriTaramaAyari.cevrimdisiOnce) private var cevrimdisiOnce = false

    /// Konum, son eklenen kitabın konumuyla dolu gelir (`SonKonum`); boşsa alanlar boş kalır.
    init(onStart: @escaping (BulkAssignment, Bool) -> Void) {
        self.onStart = onStart
        let son = SonKonum.yukle()
        var ilk = BulkAssignment()
        ilk.location = son.yer
        ilk.cabinet = son.dolap
        ilk.shelf = son.raf
        _assignment = State(initialValue: ilk)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Taranan kitaplar nereye?") {
                    TextField("Oda / Genel konum", text: $assignment.location)
                    TextField("Dolap", text: $assignment.cabinet)
                    TextField("Raf", text: $assignment.shelf)
                    TextField("Kategori", text: $assignment.category)
                }

                Section {
                    Toggle("Çevrimdışı önce: ISBN'i hemen kaydet", isOn: $cevrimdisiOnce)
                        .accessibilityIdentifier("scanSetup.offlineFirst")
                } footer: {
                    Text("Açıkken okutulan her barkod internet beklemeden konumuyla kaydedilir; ad, yazar ve kapak sonra doldurulur. Zayıf bağlantıda hızlı tarama için uygundur. Dolmayan kayıtlar “Bilgi bekleyen” olarak kalır.")
                }

                Section {
                    Toggle("Tam dolan kitapları otomatik kaydet", isOn: $autoSave)
                } footer: {
                    Text("Açıkken: Amazon’dan adı, yazarı ve kapağı tam gelen kitaplar onay beklemeden kataloğa eklenir. Eksik kalanlar tarama sonunda onay listesine düşer. Boş bırakılan konum alanları atlanır.")
                }

                Section {
                    Button {
                        onStart(assignment, autoSave)
                        dismiss()
                    } label: {
                        HStack {
                            Spacer()
                            Label("Taramaya Başla", systemImage: "barcode.viewfinder")
                                .font(.headline)
                            Spacer()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .navigationTitle("Seri Tarama")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Depo modu kurulumu

/// Çok büyük koleksiyonlar için hızlı kayıt: tarama sırasında ağa çıkılmaz, yalnızca
/// ISBN + dolap/raf kaydedilir. Kitap bilgileri sonra zenginleştirme kuyruğuyla dolar.
struct DepotSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onStart: (_ location: String, _ cabinet: String, _ shelf: String, _ category: String) -> Void

    @State private var location = ""
    @State private var cabinet = "1"
    @State private var shelf = "1"
    @State private var category = ""
    /// Kayıtlı kitap okutulunca yapılacak iş; `SonKonum` gibi hatırlanır.
    @AppStorage(DepoEslesmeKarari.anahtar) private var eslesme = DepoEslesmeKarari.nusha.rawValue

    var body: some View {
        NavigationStack {
            Form {
                Section("Neresi taranıyor?") {
                    TextField("Oda / Depo adı", text: $location)
                    TextField("Dolap no", text: $cabinet)
#if os(iOS)
                        .keyboardType(.numberPad)
#endif
                    TextField("Başlangıç raf no", text: $shelf)
#if os(iOS)
                        .keyboardType(.numberPad)
#endif
                    TextField("Kategori (isteğe bağlı)", text: $category)
                }

                Section {
                    Picker("Kayıtlı kitap okutulunca", selection: $eslesme) {
                        ForEach(DepoEslesmeKarari.allCases) { Text($0.baslik).tag($0.rawValue) }
                    }
                    .accessibilityIdentifier("depot.matchPolicy")
                } footer: {
                    Text((DepoEslesmeKarari(rawValue: eslesme) ?? .nusha).aciklama)
                }

                Section {
                    Button {
                        onStart(location, cabinet, shelf, category)
                        dismiss()
                    } label: {
                        HStack {
                            Spacer()
                            Label("Depo Taramasını Başlat", systemImage: "shippingbox")
                                .font(.headline)
                            Spacer()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                } footer: {
                    Text("Depo modunda tarama internet beklemez: her barkod anında dolap/raf bilgisiyle kaydedilir (saniyede 1-2 kitap). Kitap adı, yazar ve kapaklar daha sonra ana ekrandaki \"Amazon'dan Doldur\" kuyruğuyla otomatik tamamlanır. Raf bitince ekrandaki Raf + düğmesiyle sonraki rafa geçin.")
                }
            }
            .navigationTitle("Depo Modu")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Raf atama kurulumu

/// Katalogda zaten kayıtlı kitaplara barkodla raf numarası atamak için hedef seçimi.
struct ShelfAssignSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onStart: (_ cabinet: String, _ shelf: String) -> Void

    @State private var cabinet: String
    @State private var shelf: String
    /// Son konumdan gelen dolap; alan hâlâ bu değerdeyse not kaynağını da söyler
    private let sonDolap: String

    /// Son konum tek dokunuşla (`SonKonum`) alınır ama alanlar boş başlar: dolu dolap okutulan
    /// mevcut kitapların dolabının üzerine yazıldığından, kullanıcı seçmeden dolap yazılmaz.
    private let sonRaf: String

    init(onStart: @escaping (_ cabinet: String, _ shelf: String) -> Void) {
        self.onStart = onStart
        let son = SonKonum.yukle()
        sonDolap = son.dolap.trimmingCharacters(in: .whitespacesAndNewlines)
        sonRaf = son.raf.trimmingCharacters(in: .whitespacesAndNewlines)
        _cabinet = State(initialValue: "")
        _shelf = State(initialValue: "1")
    }

    /// Dolu dolap, okutulan mevcut kitapların kayıtlı dolabının üzerine yazılır; bu yüzden
    /// alanın etkisi (ve son konumdan geldiyse kaynağı) her zaman açıkça yazılır.
    static func dolapNotu(dolap: String, sonKonumdan: Bool) -> String {
        let temiz = dolap.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !temiz.isEmpty else { return "Dolap boş kalırsa kitapların kayıtlı dolabı korunur; yalnız raf değişir." }
        let kaynak = sonKonumdan ? "Dolap, son eklenen kitabın konumundan alındı. " : ""
        return kaynak + "Okutulan her kitabın dolabı “\(temiz)” olarak değişir. Yalnız rafı değiştirmek için dolap alanını boşaltın."
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if !sonDolap.isEmpty, cabinet != sonDolap,
                       let baslik = SonKonum.dugmeBasligi(yer: "", dolap: sonDolap, raf: sonRaf) {
                        Button(baslik, systemImage: "clock.arrow.circlepath") {
                            cabinet = sonDolap
                            if !sonRaf.isEmpty { shelf = sonRaf }
                        }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("shelfAssign.useLastLocation")
                    }
                    TextField("Dolap (örn. A)", text: $cabinet)
                    TextField("Başlangıç raf no", text: $shelf)
#if os(iOS)
                        .keyboardType(.numberPad)
#endif
                } header: {
                    Text("Nereye raf atanacak?")
                } footer: {
                    Text(Self.dolapNotu(dolap: cabinet, sonKonumdan: !sonDolap.isEmpty && cabinet == sonDolap))
                }

                Section {
                    Button {
                        // Yalnız boşluk girilen dolap boş sayılır (kayıtlı dolap korunur)
                        onStart(cabinet.trimmingCharacters(in: .whitespacesAndNewlines),
                                shelf.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    } label: {
                        HStack {
                            Spacer()
                            Label("Raf Atamaya Başla", systemImage: "barcode.viewfinder")
                                .font(.headline)
                            Spacer()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                } footer: {
                    Text("Dolaptaki kitapların barkodlarını sırayla okutun; her biri geçerli raf numarasına atanır. Raf değiştikçe ekrandaki \"Raf +\" ile ilerleyin.")
                }
            }
            .navigationTitle("Raf Atama Modu")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
            }
        }
    }
}

// MARK: - CSV önizleme

/// İçe aktarmadan önce dosyadan okunan kitapların ön izlemesi.
struct CSVPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let books: [Book]
    let onImport: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Okunan kitap", value: "\(books.count)")
                    LabeledContent("ISBN'li", value: "\(books.filter { !($0.isbn ?? "").isEmpty }.count)")
                } footer: {
                    Text("Sütun eşleşmesini kontrol edin. Yanlışsa dosyadaki başlıkları düzeltip yeniden deneyin.")
                }

                Section("Önizleme") {
                    ForEach(books.prefix(50)) { book in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(book.title).font(.headline)
                            Text([book.author, book.publisher, book.isbn]
                                .compactMap { $0 }
                                .filter { !$0.isEmpty }
                                .joined(separator: " • "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if books.count > 50 {
                        Text("… ve \(books.count - 50) kitap daha")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("İçe Aktarma Önizleme")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("İçe Aktar (\(books.count))") {
                        onImport()
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Bekleyen kuyruk kalıcılığı

/// Kuyruktaki bir taslak ve yalnız arayüzde anlamı olan alanları. `Book` tek başına şüpheli alan
/// işaretlerini, okuma kaynağını ve bilgi notunu taşımadığı için uygulama kapanıp açılınca kaybolurdu.
nonisolated struct KuyrukTaslagi: Codable, Equatable, Sendable {
    var book: Book
    var lowConfidenceFields: [String] = []
    var recognizedByGemini = false
    var recognitionSource: String?
    var bilgiNotu: String?
    var konumFarki: String?

    init(book: Book, lowConfidenceFields: [String] = [], recognizedByGemini: Bool = false,
         recognitionSource: String? = nil, bilgiNotu: String? = nil, konumFarki: String? = nil) {
        self.konumFarki = konumFarki
        self.book = book
        self.lowConfidenceFields = lowConfidenceFields
        self.recognizedByGemini = recognizedByGemini
        self.recognitionSource = recognitionSource
        self.bilgiNotu = bilgiNotu
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        book = try c.decode(Book.self, forKey: .book)
        lowConfidenceFields = try c.decodeIfPresent([String].self, forKey: .lowConfidenceFields) ?? []
        recognizedByGemini = try c.decodeIfPresent(Bool.self, forKey: .recognizedByGemini) ?? false
        recognitionSource = try c.decodeIfPresent(String.self, forKey: .recognitionSource)
        bilgiNotu = try c.decodeIfPresent(String.self, forKey: .bilgiNotu)
        konumFarki = try c.decodeIfPresent(String.self, forKey: .konumFarki)
    }
}

@MainActor
extension KuyrukTaslagi {
    /// `book`, kayıt kaynağını alan geçmişine işlenmiş hâliyle verilir (`ContentView.book(from:)`).
    init(draft: BookDraft, book: Book) {
        self.init(book: book, lowConfidenceFields: draft.lowConfidenceFields.sorted(),
                  recognizedByGemini: draft.recognizedByGemini, recognitionSource: draft.recognitionSource,
                  bilgiNotu: draft.bilgiNotu, konumFarki: draft.konumFarki)
    }

    var draft: BookDraft {
        var taslak = BookDraft(book: book)
        taslak.lowConfidenceFields = Set(lowConfidenceFields)
        taslak.recognizedByGemini = recognizedByGemini
        taslak.recognitionSource = recognitionSource
        taslak.bilgiNotu = bilgiNotu
        taslak.konumFarki = konumFarki
        return taslak
    }
}

/// Seri tarama kuyruğunu diske yazar; uygulama kapansa da taranan kitaplar kaybolmaz.
/// Dosya `{"surum":2,"taslaklar":[…]}` biçimindedir; eski sürümün yazdığı çıplak `[Book]` dizisi de okunur.
nonisolated enum PendingQueueStore {
    struct Dosya: Codable { var surum = 2; var taslaklar: [KuyrukTaslagi] }

    struct YuklemeSonucu: Equatable {
        var taslaklar: [KuyrukTaslagi]
        /// Dosya okunamadıysa verinin taşındığı yan dosya; kullanıcıya bildirilir.
        var bozukYedek: URL?
    }

    /// Testler için; `nil` iken uygulama Documents klasörü kullanılır.
    static var directoryOverride: URL?

    private static var url: URL? {
        (directoryOverride ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)?
            .appendingPathComponent("BekleyenKuyruk.json")
    }

    /// Yazma hatası yutulmaz: çağıran bellekteki kuyruğun diske inmediğini kullanıcıya gösterir.
    static func save(_ items: [KuyrukTaslagi]) throws {
        guard let url else { throw CocoaError(.fileNoSuchFile) }
        if items.isEmpty {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            return
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(Dosya(taslaklar: items))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    /// Yeni biçimi, olmazsa eski `[Book]` dizisini çözer; ikisi de olmuyorsa `nil`.
    static func decode(_ data: Data) -> [KuyrukTaslagi]? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let dosya = try? decoder.decode(Dosya.self, from: data) { return dosya.taslaklar }
        if let eski = try? decoder.decode([Book].self, from: data) { return eski.map { KuyrukTaslagi(book: $0) } }
        return nil
    }

    /// Bozuk dosya sessizce yok sayılıp bir sonraki kayıtta ezilmez; `.bozuk` yedeği olarak yanına taşınır.
    static func loadResult() -> YuklemeSonucu {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return YuklemeSonucu(taslaklar: []) }
        guard let data = try? Data(contentsOf: url) else {
            return YuklemeSonucu(taslaklar: [], bozukYedek: bozukOlarakTasi(url))
        }
        if let taslaklar = decode(data) { return YuklemeSonucu(taslaklar: taslaklar) }
        return YuklemeSonucu(taslaklar: [], bozukYedek: bozukOlarakTasi(url))
    }

    static func load() -> [KuyrukTaslagi] { loadResult().taslaklar }

    static func clear() {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static func bozukOlarakTasi(_ url: URL) -> URL? {
        let hedef = url.deletingPathExtension().appendingPathExtension("bozuk")
        try? FileManager.default.removeItem(at: hedef)
        do { try FileManager.default.moveItem(at: url, to: hedef); return hedef }
        catch { return nil }
    }
}
