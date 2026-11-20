import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import CryptoKit

/// Sayım (envanter) modu: raflardaki kitaplar seri barkodla okutulur; program beklenen
/// nüsha sayılarıyla karşılaştırıp "eksik (kayıp adayı)", "fazla okutulan" ve
/// "kayıtsız barkod" listelerini çıkarır. Sonuç, Excel'de açılan sayım tutanağı
/// olarak dışa aktarılır.
struct InventoryCountView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \CatalogBook.addedAt) private var catalogBooks: [CatalogBook]
    @Query private var loans: [ActiveLoan]
    @Query private var copies: [BookCopy]
    @Query private var reservations: [Reservation]

    /// Oturumun tek sahibi: ekran açılışında diskten bir kez okunur.
    @State private var durum = SayimDurumu()
    @State private var locations = ["Tümü"]
    @State private var isShowingCounted = false
    @State private var countedSearch = ""
    @State private var countedLimit = 100
    @State private var isShowingScanner = false
    @State private var scannerDuraklatildi = false
    @State private var scannerUyarisi: String?
    @State private var exportDocument = InventoryFileDocument()
    @State private var exportType: UTType = .pdf
    @State private var isExporting = false
    @State private var isPreparingExport = false
    @State private var moveLocation = ""
    @State private var moveCabinet = ""
    @State private var moveShelf = ""
    @State private var moveInherit = true
    @State private var movePreview: InventoryMovePreview?
    @State private var moveSelection = Set<UUID>()
    @State private var confirmMove = false
    @State private var confirmReset = false
    @State private var selectedMissing = Set<UUID>()
    @State private var confirmLost = false
    @State private var sonrasiIslemler: [InventoryActionReceipt] = []
    @State private var islemSuruyor = false
    /// Sayım komisyonu (tutanakta imza alanları) ve okul adı
    @AppStorage("inventoryCommission") private var commission = ""
    @AppStorage("schoolName") private var schoolName = ""

    private struct KaynakImzasi: Equatable {
        var books: Int, loans: Int, copies: Int, reservations: Int
        var location: String
    }
    private var kaynakImzasi: KaynakImzasi {
        KaynakImzasi(books: catalogBooks.count, loans: loans.count, copies: copies.count, reservations: reservations.count,
                     location: durum.selectedLocation)
    }

    /// İlk okutmada ya da elle saymada beklenen listeyi sabitler.
    private func beginCount() -> Bool {
        durum.begin(books: catalogBooks, loans: loans, copies: copies, reservations: reservations)
    }

    var body: some View {
        NavigationStack {
            List {
                ilerlemeKarti
                controlSection
                countedSection
                if let bildirim = durum.bildirim { Text(bildirim).font(.footnote).foregroundStyle(.secondary) }
                ForEach(Array(InventorySnapshot.statusCategories.enumerated()), id: \.offset) { index, category in
                    statusSection(Self.durumBasligi[index], books: durum.statusBooks[index], keyPath: category.1)
                }
                if !durum.identityUncertainBooks.isEmpty {
                    Section("Ödünç nüshası belirsiz — sonuç doğrulanmalı") {
                        Text("Eski ödünçlerde hangi nüshanın verildiği kayıtlı değil. Bu konumun bekleneni güvenli tarafta azaltıldı; kesin sayım için ödüncü doğru nüsha kimliğiyle eşleştirin.").font(.footnote)
                        ForEach(durum.identityUncertainBooks) { book in
                            row(title: book.title, subtitle: book.author, detail: "\(book.unresolvedLoans ?? 0) kimliksiz ödünç", color: .secondary)
                        }
                    }
                }
                otherLocationSection

                Section {
                    TextField("Okul adı", text: $schoolName)
                    TextField("Komisyon üyeleri (virgülle: Ad Soyad, …)", text: $commission, axis: .vertical)
                } header: {
                    Text("Tutanak bilgileri")
                } footer: {
                    Text("Her üye için tutanakta ayrı imza alanı açılır.")
                }

                if !durum.missingEntries.isEmpty {
                    Section {
                        ForEach(durum.missingEntries) { entry in
                            Button {
                                if selectedMissing.contains(entry.id) { selectedMissing.remove(entry.id) } else { selectedMissing.insert(entry.id) }
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    if durum.hasSnapshot {
                                        Image(systemName: selectedMissing.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(selectedMissing.contains(entry.id) ? Color.accentColor : .secondary)
                                            .accessibilityHidden(true)
                                    }
                                    row(
                                        title: entry.book.title,
                                        subtitle: entry.book.author,
                                        detail: "Beklenen \(entry.expected) • Okutulan \(entry.scanned) • Eksik \(entry.expected - entry.scanned)",
                                        color: .red
                                    )
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selectedMissing.contains(entry.id) ? .isSelected : [])
                        }
                        if durum.hasSnapshot {
                            Button("Seçilenleri Kayıp işaretle (\(selectedMissing.count))", systemImage: "questionmark.folder") { confirmLost = true }
                                .disabled(selectedMissing.isEmpty || islemSuruyor)
                                .frame(minHeight: 44)
                                .accessibilityIdentifier("inventory.markLost")
                        }
                    } header: {
                        Text("Eksik — kayıp adayı (\(durum.missingEntries.count))")
                    } footer: {
                        if durum.hasSnapshot { Text("Kayıp işaretleme yalnız sayılmamış, rafta duran ve ödüncü olmayan nüshaları etkiler. Nüsha kimliği bilinmeyen ödüncü olan eserler atlanır; geri alınabilir.") }
                    }
                }

                if !durum.surplusEntries.isEmpty {
                    Section("Fazla okutulan (\(durum.surplusEntries.count))") {
                        ForEach(durum.surplusEntries) { entry in
                            row(
                                title: entry.book.title,
                                subtitle: entry.book.author,
                                detail: "Beklenen \(entry.expected) • Okutulan \(entry.scanned) • Fazla \(entry.scanned - entry.expected)",
                                color: .orange
                            )
                            Button("Yeni nüsha oluştur", systemImage: "plus.square.on.square") { yeniNushaOlustur(entry) }
                                .disabled(islemSuruyor || !durum.hasSnapshot)
                                .frame(minHeight: 44)
                                .accessibilityLabel("\(entry.book.title) için yeni nüsha oluştur")
                        }
                    }
                }

                if !durum.unknownCounts.isEmpty {
                    Section("Kayıtsız barkodlar (\(durum.unknownCounts.count))") {
                        ForEach(durum.unknownCounts.sorted(by: { $0.key < $1.key }), id: \.key) { code, count in
                            row(
                                title: code,
                                subtitle: "Katalogda bulunamadı",
                                detail: "\(count) kez okutuldu",
                                color: .orange
                            )
                            if ISBNFormatter.isBarcodeQuery(code) {
                                Button("Kataloğa ekle", systemImage: "plus.circle") {
                                    DerinBaglanti.shared.bekleyenISBN = code
                                    DerinBaglanti.shared.hedefSekme = .katalog
                                    dismiss()
                                }
                                .frame(minHeight: 44)
                                .accessibilityLabel("\(code) barkodunu kataloğa ekle")
                            }
                        }
                    }
                }

                if !durum.barcodelessBooks.isEmpty {
                    Section("Barkodsuz kitaplar — elle sayın (\(durum.barcodelessBooks.count))") {
                        ForEach(durum.barcodelessBooks) { book in
                            row(
                                title: book.title,
                                subtitle: book.author,
                                detail: "Rafta beklenen \(durum.expectedCount(book)) • Sayılan \(durum.scannedCount(book)) (ISBN yok)",
                                color: .secondary
                            )
                            Button("Bir nüsha say") {
                                durum.elleSay(book, baslat: beginCount)
                            }
                            .frame(minHeight: 44)
                            .accessibilityLabel("\(book.title) için bir nüsha say")
                        }
                    }
                }

                sonrasiIslemSection

                if durum.hasSnapshot && durum.scannedTotal > 0 && durum.missingEntries.isEmpty && durum.surplusEntries.isEmpty
                    && durum.unknownCounts.isEmpty && durum.otherLocationBooks.isEmpty && durum.identityUncertainBooks.isEmpty {
                    Section {
                        Label("Sayım adetleri başlangıç beklentisiyle eşleşti.", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
            // Yönetim ve araç panelindeki adla aynı (tek ad kaynağı: KatalogAraci.inventory)
            .navigationTitle(KatalogAraci.inventory.aracBasligi ?? "")
            .sheet(isPresented: $isShowingCounted) { countedPage }
            .sheet(isPresented: Binding(get: { movePreview != nil }, set: { if !$0 { movePreview = nil } })) { movePreviewPage }
            .task(id: kaynakImzasi) {
                durum.yukle()
                konumlariYenile()
                eskiAyracliKonumuTasi()
                durum.onizlemeyiYenile(books: catalogBooks, loans: loans, copies: copies, reservations: reservations)
                sonrasiIslemleriYenile()
            }
            .onChange(of: scenePhase) { _, yeni in if yeni != .active { durum.flush() } }
            .onDisappear { durum.flush() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { durum.flush(); dismiss() }
                }
                ToolbarItemGroup(placement: .confirmationAction) {
                    if isPreparingExport { ProgressView().accessibilityLabel("Tutanak hazırlanıyor") }
                    Menu {
                        Button("PDF tutanak", systemImage: "doc.richtext") { tutanakHazirla(.pdf) }
                        Button("Excel (XLSX, çok sayfalı)", systemImage: "tablecells") { tutanakHazirla(.excel) }
                        Button("CSV", systemImage: "doc.plaintext") { tutanakHazirla(.csv) }
                    } label: {
                        Label("Tutanak", systemImage: "square.and.arrow.up")
                    }
                    .disabled(durum.scannedTotal == 0 || isPreparingExport)
                    .accessibilityIdentifier("inventory.export")
                }
            }
            // Tutanak yalnız düğmeye basılınca arka planda hazırlanır; her çizimde yeniden üretilmez.
            .fileExporter(
                isPresented: $isExporting,
                document: exportDocument,
                contentType: exportType,
                defaultFilename: "Sayim-Tutanagi"
            ) { _ in exportDocument = InventoryFileDocument() }
            .confirmationDialog("Seçilen \(selectedMissing.count) eserin sayılmayan nüshaları Kayıp işaretlensin mi? Ödünçteki nüshalara dokunulmaz; işlem geri alınabilir.",
                                isPresented: $confirmLost, titleVisibility: .visible) {
                Button("Kayıp işaretle", role: .destructive) { kayipIsaretle() }
                Button("Vazgeç", role: .cancel) { }
            }
#if os(iOS)
            .fullScreenCover(isPresented: $isShowingScanner, onDismiss: { durum.flush() }) { scannerCover }
#endif
        }
    }

    private static let durumBasligi = ["Ödünçte — kapsam dışında", "Kayıp — rafta beklenmez", "Onarımda — rafta beklenmez", "Düşülmüş — rafta beklenmez"]

    // MARK: - İlerleme

    @ViewBuilder private var ilerlemeKarti: some View {
        if durum.hasSnapshot || durum.scannedTotal > 0 {
            let ilerleme = durum.ilerleme
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Okutulan \(ilerleme.okutulan) / \(ilerleme.beklenen) (%\(ilerleme.yuzde))")
                        .font(.title2.bold())
                        .fixedSize(horizontal: false, vertical: true)
                    ProgressView(value: ilerleme.oran).accessibilityHidden(true)
                    if let ozet = ilerlemeOzeti(ilerleme) {
                        Text(ozet).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("inventory.progress")
                if durum.selectedLocation == "Tümü", ilerleme.konumlar.count > 1 {
                    DisclosureGroup("Konum başına dağılım (\(ilerleme.konumlar.count))") {
                        ForEach(ilerleme.konumlar) { konum in
                            Text("\(konum.ad): \(konum.okutulan)/\(konum.beklenen)").font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private func ilerlemeOzeti(_ ilerleme: SayimIlerleme) -> String? {
        var parcalar: [String] = []
        if let son = ilerleme.sonOkutma { parcalar.append("Son okutma " + son.formatted(date: .omitted, time: .shortened)) }
        if let hiz = ilerleme.dakikadaOkutma { parcalar.append("\(hiz) okutma/dk") }
        if let sure = ilerleme.gecenSure, sure >= 1 { parcalar.append(SayimIlerleme.sureMetni(sure)) }
        return parcalar.isEmpty ? nil : parcalar.joined(separator: " · ")
    }

    // MARK: - Kontrol bölümü

    @ViewBuilder private var otherLocationSection: some View {
        if !durum.otherLocationBooks.isEmpty {
            Section("Başka rafta bulunan (\(durum.otherLocationBooks.count) eser)") {
                ForEach(durum.otherLocationBooks) { book in
                    row(title: book.title, subtitle: book.author,
                        detail: "Kayıtlı yer: \(durum.outsidePlaces(for: book)) · Bulunan yer: \(durum.selectedLocation)", color: .secondary)
                }
                TextField("Bulunan hedef konum", text: $moveLocation)
                TextField("Hedef dolap (isteğe bağlı)", text: $moveCabinet)
                TextField("Hedef raf (isteğe bağlı)", text: $moveShelf)
                Button("Bulunan yerler için toplu taşıma önizlemesi", systemImage: "arrow.triangle.swap") { onizlemeOlustur() }
                    .frame(minHeight: 44)
            }
        }
    }

    private func onizlemeOlustur() {
        do {
            let yeni = try InventoryMoveService.preview(session: durum.sessionValue, location: moveLocation,
                cabinet: moveCabinet, shelf: moveShelf, context: modelContext, inheritEmpty: moveInherit)
            if movePreview == nil { moveSelection = Set(yeni.eligible.map(\.id)) }
            else { moveSelection.formIntersection(Set(yeni.eligible.map(\.id))) }
            movePreview = yeni
        } catch { durum.bildirim = error.localizedDescription }
    }

    @ViewBuilder private var movePreviewPage: some View {
        if let preview = movePreview {
            NavigationStack {
                List {
                    Section("Hedef: \(preview.location)") {
                        Text("Demirbaşla tanınan nüsha ayrı taşınır; eser konumu korunur. ISBN sayımında yalnız tüm nüshaları doğrulanan eser taşınır.")
                        if preview.candidates.contains(where: { $0.copyID == nil }) {
                            Text("Eser taşınırken dolap ve raf boş bırakılırsa eserin önceki dolap ve rafı da temizlenir.").font(.footnote)
                        }
                        if preview.candidates.contains(where: { $0.copyID != nil }) {
                            Toggle("Boş alanlar eserden devralsın", isOn: $moveInherit)
                                .onChange(of: moveInherit) { onizlemeOlustur() }
                            Text("Kapalıyken boş bırakılan dolap veya raf nüshada açıkça boşaltılır.").font(.footnote)
                        }
                    }
                    if let bildirim = durum.bildirim { Section { Text(bildirim).fixedSize(horizontal: false, vertical: true) } }
                    Section("Önce → sonra") {
                        ForEach(preview.candidates) { candidate in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(candidate.before.title).font(.headline)
                                ViewThatFits(in: .horizontal) {
                                    HStack(alignment: .top, spacing: 12) {
                                        yerSutunu("Kitap", candidate.copyID == nil ? "Eser" : "Nüsha")
                                        yerSutunu("Önce", candidate.beforePlace.isEmpty ? candidate.sourcePlace : candidate.beforePlace)
                                        yerSutunu("Sonra", candidate.afterPlace.isEmpty ? candidate.targetPlace : candidate.afterPlace)
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        yerSutunu("Önce", candidate.beforePlace.isEmpty ? candidate.sourcePlace : candidate.beforePlace)
                                        yerSutunu("Sonra", candidate.afterPlace.isEmpty ? candidate.targetPlace : candidate.afterPlace)
                                    }
                                }
                                Text("\(candidate.counted) doğrulanmış nüsha").font(.footnote).foregroundStyle(.secondary)
                                if let reason = candidate.reason { Label(reason, systemImage: "exclamationmark.triangle").font(.footnote) }
                                else {
                                    Toggle("Konumu değiştir", isOn: Binding(get: { moveSelection.contains(candidate.id) }, set: { value in
                                        if value { moveSelection.insert(candidate.id) } else { moveSelection.remove(candidate.id) }
                                    }))
                                }
                            }.fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Button("Seçili \(moveSelection.count) konum kaydını taşı") { confirmMove = true }.disabled(moveSelection.isEmpty).frame(minHeight: 44)
                }
                .navigationTitle("Konum taşıma önizlemesi")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { movePreview = nil } } }
                .confirmationDialog("Önizlenen nüsha veya eser konumları değiştirilsin mi?", isPresented: $confirmMove, titleVisibility: .visible) {
                    Button("Konumları değiştir") {
                        Task {
                            guard await YetkiDurumu.shared.yoneticiOl() else { durum.bildirim = YetkiDurumu.shared.hata ?? "Yönetici kimliği gerekir."; return }
                            do {
                                let fis = try InventoryMoveService.applyWithReceipt(preview, selectedIDs: moveSelection, context: modelContext)
                                durum.bildirim = "\(fis.changes.count) konum kaydı değiştirildi. Sayım başlangıç beklentisi korunuyor; 'Son işlemi geri al' ile geri alınabilir."
                                movePreview = nil
                                sonrasiIslemleriYenile()
                            } catch { durum.bildirim = error.localizedDescription }
                        }
                    }
                }
            }
        }
    }

    private func yerSutunu(_ baslik: String, _ deger: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(baslik).font(.caption).foregroundStyle(.secondary)
            Text(deger).font(.subheadline).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var controlSection: some View {
        Section {
            TextField("Sayım oturumu adı", text: $durum.sessionName).disabled(durum.hasSnapshot)
            TextField("Sayan görevli", text: $durum.operatorName).disabled(durum.hasSnapshot)
            Picker("Sayım yöntemi", selection: $durum.method) {
                Text("ISBN nüsha sayımı").tag("ISBN nüsha sayımı")
                Text("Benzersiz demirbaş").tag("Benzersiz demirbaş")
            }.disabled(durum.hasSnapshot)
            Picker("Sayılacak konum", selection: $durum.selectedLocation) {
                ForEach(locations, id: \.self) { location in
                    Text(location).tag(location)
                }
            }
            .disabled(durum.hasSnapshot)
            if !durum.hasSnapshot {
                Button("Beklenen listeyi sabitle ve sayımı başlat", systemImage: "checklist") { _ = beginCount() }.frame(minHeight: 44)
            } else {
                Text("Beklenen liste başlangıç anına sabitlendi. Sonraki ödünç/konum değişiklikleri bu sayımın beklentisini değiştirmez.").font(.footnote).foregroundStyle(.secondary)
                Button("Oturumu yeniden kaydet", systemImage: "square.and.arrow.down") { durum.yenidenKaydet() }.frame(minHeight: 44)
            }

            LabeledContent("Rafta beklenen") {
                Text("\(durum.expectedTotal) nüsha")
            }
            LabeledContent("Okutulan") {
                Text("\(durum.matchedTotal) nüsha")
                    .fontWeight(.semibold)
            }
            if durum.unmatchedTotal > 0 {
                LabeledContent("Liste dışı okutma") {
                    Text("\(durum.unmatchedTotal) nüsha")
                }
            }

#if os(iOS)
            Button {
                guard beginCount() else { return }
                scannerDuraklatildi = false
                isShowingScanner = true
            } label: {
                HStack {
                    Spacer()
                    Label("Barkod Okutmaya Başla", systemImage: "barcode.viewfinder")
                    Spacer()
                }
            }
            .frame(minHeight: 44)
#endif

            if durum.hasSnapshot || durum.scannedTotal > 0 {
                LabeledContent("Sayım başlangıcı") {
                    Text(durum.startedAt.formatted(date: .abbreviated, time: .shortened))
                }
                Button(role: .destructive) {
                    confirmReset = true
                } label: {
                    Label("Sayımı Sıfırla", systemImage: "arrow.counterclockwise")
                }
                // Saatler süren sayım tek dokunuşla silinmesin
                .confirmationDialog("Sayım sıfırlansın mı? \(durum.scannedTotal) okutma, gözlemler ve sabitlenen beklenti silinir; geri alınamaz.",
                                    isPresented: $confirmReset, titleVisibility: .visible) {
                    Button("Sayımı Sıfırla", role: .destructive) {
                        do { try durum.sifirla(); selectedMissing.removeAll() }
                        catch { durum.bildirim = "Sayım sıfırlanamadı: " + error.localizedDescription }
                    }
                    Button("Vazgeç", role: .cancel) { }
                }
            }
        } footer: {
            Text("Raftaki nüshaları ISBN veya benzersiz demirbaş barkoduyla sayın. Demirbaş ikinci kez sayılmaz. ISBN ile aynı nüshayı tekrar okutmak adedi artırır. Ödünçte, kayıp, onarımda ve düşülen nüshalar raf beklentisine girmez; hazır rezervasyonlar rafta beklenir. Sayım kaldığı yerden devam eder.")
        }
    }

    @ViewBuilder private func statusSection(_ title: String, books: [InventoryExpectedItem], keyPath: KeyPath<LibraryStock, Int>) -> some View {
        if !books.isEmpty {
            Section(title) {
                ForEach(books) { book in row(title: book.title, subtitle: book.author, detail: "\(book.stock[keyPath: keyPath]) nüsha", color: .secondary) }
            }
        }
    }

    private func row(title: String, subtitle: String, detail: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(color)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Hesaplamalar

    private func konumlariYenile() {
        let booksByID = Dictionary(catalogBooks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let all = catalogBooks.map { InventorySnapshot.eserYeri($0) }.filter { !$0.isEmpty } + copies.compactMap { copy in
            booksByID[copy.bookID].map { copy.effectivePlace(for: $0) }
        }.filter { !$0.isEmpty }
        let yeni = ["Tümü"] + Array(Set(all)).sorted()
        if yeni != locations { locations = yeni }
    }

    /// Ayraç " • " iken kaydedilmiş konum seçimi bugünkü seçeneğe taşınır; yoksa ilk okutmada beklenen
    /// liste boş kalır ve her kitap "başka rafta" sayılırdı.
    private func eskiAyracliKonumuTasi() {
        let guncel = InventorySnapshot.guncelKonum(durum.selectedLocation, secenekler: locations)
        durum.konumuGuncelle(guncel)
    }

    // MARK: - Sayılan kitaplar

    private var filteredCounted: [InventoryCountEntry] {
        InventoryCountResult.search(durum.countedEntries, query: countedSearch)
    }

    private var countedSection: some View {
        Section("Sayılan kitaplar (\(durum.countedEntries.count) eser)") {
            if durum.countedEntries.isEmpty {
                Text(!durum.hasSnapshot ? "Sayımı başlatıp barkod okuttuğunuzda sayılan kitaplar burada görünür." : "Bu kapsamda henüz bir kitap sayılmadı. Kayıtsız barkodlar ve başka konumda bulunanlar kendi listelerinde gösterilir.")
                    .font(.subheadline).fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(durum.countedEntries.prefix(3)) { entry in countedRow(entry) }
                Button("Sayılan kitapların tümünü gör (\(durum.countedEntries.count))", systemImage: "checklist") {
                    countedSearch = ""; countedLimit = 100; isShowingCounted = true
                }.frame(minHeight: 44).accessibilityIdentifier("inventory.counted.open")
            }
        }
    }

    private var countedPage: some View {
        NavigationStack {
            List {
                Section {
                    Text("\(durum.countedEntries.count) eser · \(durum.countedEntries.reduce(0) { $0 + $1.scanned }) sayılan nüsha")
                    Text("Beklenen adet, sayım başlangıcındaki rafta bulunabilir stoktur. ISBN aynı nüshanın yeniden okutulmasını ayıramaz; tam adet eşleşmesi benzersiz nüsha doğrulaması anlamına gelmez.")
                        .font(.footnote).fixedSize(horizontal: false, vertical: true)
                }
                if filteredCounted.isEmpty {
                    ContentUnavailableView(countedSearch.isEmpty ? "Henüz kitap sayılmadı" : "Sayılan kitap bulunamadı", systemImage: "magnifyingglass", description: Text("Kitap adı, yazar, ISBN veya demirbaşla arayın."))
                } else {
                    Section("Sayılan kayıtlar (\(filteredCounted.count))") {
                        ForEach(filteredCounted.prefix(countedLimit)) { entry in countedRow(entry) }
                        if filteredCounted.count > countedLimit {
                            Button("Sonraki 100 kaydı göster") { countedLimit += 100 }.frame(minHeight: 44)
                        }
                    }
                }
            }
            .searchable(text: $countedSearch, prompt: "Sayılanlarda ad, yazar, ISBN, demirbaş")
            .onChange(of: countedSearch) { countedLimit = 100 }
            .navigationTitle("Sayılan kitaplar")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { isShowingCounted = false } } }
        }
    }

    private func countedRow(_ entry: InventoryCountEntry) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(entry.book.title).font(.headline)
            if !entry.book.author.isEmpty { Text(entry.book.author).font(.subheadline) }
            if let isbn = entry.book.isbn, !isbn.isEmpty { Text("ISBN: " + isbn).font(.caption) }
            Text("Beklenen \(entry.expected) · Sayılan \(entry.scanned) · \(entry.statusTitle)").font(.subheadline)
            Text(entry.confidenceNote(hasSnapshot: durum.hasSnapshot)).font(.footnote).foregroundStyle(.secondary)
        }.fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Tarayıcı

#if os(iOS)
    private var scannerCover: some View {
        ZStack(alignment: .topTrailing) {
            LiveISBNScannerView(continuous: true, allowRepeats: true, onScan: { _ in }, onCancel: {
                isShowingScanner = false
            }, onScanResult: { code in
                tara(code).tarayiciGeriBildirimi
            })

            Button {
                isShowingScanner = false
            } label: {
                Label("Kapat", systemImage: "xmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .font(.largeTitle)
                    .foregroundStyle(.white)
                    .shadow(radius: 3)
            }
            .frame(minWidth: 44, minHeight: 44)
            .padding()
            .accessibilityLabel("Sayım tarayıcısını kapat")
            .accessibilityIdentifier("scanner.close")

            SayimTarayiciPaneli(durum: durum, uyari: scannerUyarisi, duraklatildi: scannerDuraklatildi,
                                tekrarDene: { tekrarDene() }, geriAl: { geriAl() })
        }
        .ignoresSafeArea()
    }

    /// Bir okutmayı işler; sonuç titreşim, uyarı ve VoiceOver duyurusunu belirler.
    @discardableResult
    private func tara(_ code: String) -> SayimSonucu {
        guard !scannerDuraklatildi else { return .kaydedilemedi }
        let sonuc = durum.record(code, baslat: beginCount)
        sonucuBildir(sonuc)
        return sonuc
    }

    private func sonucuBildir(_ sonuc: SayimSonucu) {
        let mesaj = durum.bildirim ?? sonuc.baslik
        AccessibilityNotification.Announcement(mesaj).post()
        switch sonuc {
        case .sayildi: scannerUyarisi = nil
        case .baskaRaf, .kayitsiz, .reddedildi:
            scannerUyarisi = mesaj
            Task {
                try? await Task.sleep(for: .seconds(2))
                if scannerUyarisi == mesaj { scannerUyarisi = nil }
            }
        case .kaydedilemedi:
            scannerDuraklatildi = true
            scannerUyarisi = mesaj
        }
    }

    private func tekrarDene() {
        if durum.flush() { scannerDuraklatildi = false; scannerUyarisi = nil }
        else { scannerUyarisi = durum.bildirim }
    }

    private func geriAl() {
        if durum.geriAl() { AccessibilityNotification.Announcement("Son okutma geri alındı").post() }
    }
#endif

    // MARK: - Tutanak

    private func tutanakHazirla(_ bicim: SayimTutanagi.Bicim) {
        guard !isPreparingExport else { return }
        durum.flush()
        isPreparingExport = true
        let girdi = durum.tutanakGirdisi(commission: commission, schoolName: schoolName, sonrasiIslemler: sonrasiIslemler)
        Task {
            let veri = await Task.detached(priority: .userInitiated) { SayimTutanagi.uret(girdi, bicim: bicim) }.value
            isPreparingExport = false
            guard !veri.isEmpty else { durum.bildirim = "Tutanak hazırlanamadı; yeniden deneyin."; return }
            exportDocument = InventoryFileDocument(data: veri)
            exportType = bicim.contentType
            isExporting = true
        }
    }

    // MARK: - Sayım sonrası işlemler

    @ViewBuilder private var sonrasiIslemSection: some View {
        let sonuncu = sonrasiIslemler.last
        if let sonuncu {
            Section {
                ForEach(sonrasiIslemler.suffix(5)) { fis in
                    Label(fis.title, systemImage: fis.kind == .move ? "arrow.triangle.swap" : (fis.kind == .markLost ? "questionmark.folder" : "plus.square.on.square"))
                        .font(.subheadline)
                }
                Button("Son işlemi geri al: \(sonuncu.title)", systemImage: "arrow.uturn.backward") { sonIslemiGeriAl(sonuncu) }
                    .disabled(islemSuruyor)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("inventory.undoAction")
            } header: { Text("Sayım sonrası işlemler") } footer: {
                Text("Bu işlemler tutanağa eklenir. Son işlem, sonradan değişmediyse geri alınabilir.")
            }
        }
    }

    private func sonrasiIslemleriYenile() {
        guard let hepsi = try? InventoryActionService.reconcile(context: modelContext) else { return }
        let baslangic = durum.startedAt
        sonrasiIslemler = hepsi.filter { $0.state == .committed && $0.createdAt >= baslangic }
    }

    private func kayipIsaretle() {
        let secili = durum.missingEntries.filter { selectedMissing.contains($0.id) }
        guard !secili.isEmpty, !islemSuruyor else { return }
        islemSuruyor = true
        let atlanan = (try? InventoryActionService.kimliksizOduncluEserler(entries: secili, context: modelContext))?.count ?? 0
        Task {
            defer { islemSuruyor = false }
            guard await YetkiDurumu.shared.yoneticiOl(neden: "Eksik nüshaları Kayıp işaretlemek için kimliğinizi doğrulayın") else {
                durum.bildirim = YetkiDurumu.shared.hata ?? "Yönetici kimliği gerekir."; return
            }
            do {
                let fis = try InventoryActionService.markLost(entries: secili, scanned: durum.scannedCounts, context: modelContext)
                durum.bildirim = fis.title + ". Beklenen liste sabit kaldı."
                    + (atlanan > 0 ? " Nüsha kimliği bilinmeyen ödüncü olan \(atlanan) eser atlandı; önce ödüncü nüshayla eşleştirin." : "")
                selectedMissing.removeAll()
                sonrasiIslemleriYenile()
            } catch { durum.bildirim = error.localizedDescription }
        }
    }

    private func yeniNushaOlustur(_ entry: InventoryCountEntry) {
        guard !islemSuruyor else { return }
        islemSuruyor = true
        Task {
            defer { islemSuruyor = false }
            guard await YetkiDurumu.shared.yoneticiOl(neden: "Fazla bulunan kitap için yeni nüsha açmak üzere kimliğinizi doğrulayın") else {
                durum.bildirim = YetkiDurumu.shared.hata ?? "Yönetici kimliği gerekir."; return
            }
            do {
                let fis = try InventoryActionService.createSurplusCopy(book: entry.book.id, scope: durum.selectedLocation, context: modelContext)
                durum.bildirim = fis.title + ". Demirbaş kodunu nüsha ekranından yazın."
                sonrasiIslemleriYenile()
            } catch { durum.bildirim = error.localizedDescription }
        }
    }

    private func sonIslemiGeriAl(_ fis: InventoryActionReceipt) {
        guard !islemSuruyor else { return }
        islemSuruyor = true
        Task {
            defer { islemSuruyor = false }
            guard await YetkiDurumu.shared.yoneticiOl() else { durum.bildirim = YetkiDurumu.shared.hata ?? "Yönetici kimliği gerekir."; return }
            do {
                try InventoryActionService.undo(receiptID: fis.id, context: modelContext)
                durum.bildirim = "Geri alındı: " + fis.title
                sonrasiIslemleriYenile()
            } catch { durum.bildirim = error.localizedDescription }
        }
    }
}

#if os(iOS)
/// Tarayıcı üstündeki canlı sonuç şeridi: son üç okutma, geçici uyarı, geri al ve kaydedilemedi durumu.
struct SayimTarayiciPaneli: View {
    let durum: SayimDurumu
    let uyari: String?
    let duraklatildi: Bool
    let tekrarDene: () -> Void
    let geriAl: () -> Void

    private func renk(_ sonuc: SayimSonucu) -> Color {
        switch sonuc.titresim { case .basari: .green; case .uyari: .orange; case .hata: .red }
    }

    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            if duraklatildi {
                VStack(spacing: 8) {
                    Label("Kaydedilemedi — tarayıcı duraklatıldı", systemImage: "exclamationmark.octagon.fill").font(.headline)
                    if let uyari { Text(uyari).font(.footnote).fixedSize(horizontal: false, vertical: true) }
                    Button("Yeniden kaydet ve devam et", action: tekrarDene)
                        .buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.red).frame(minHeight: 44)
                }
                .padding().frame(maxWidth: .infinity).background(Color.red.opacity(0.9), in: .rect(cornerRadius: 14))
                .foregroundStyle(.white)
            } else if let uyari {
                Text(uyari).font(.subheadline.weight(.semibold)).padding(12).frame(maxWidth: .infinity)
                    .background(.orange.opacity(0.92), in: .rect(cornerRadius: 12)).foregroundStyle(.black)
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(durum.sonOkutmalar.suffix(3).reversed()) { kayit in
                    HStack(spacing: 8) {
                        Circle().fill(renk(kayit.sonuc)).frame(width: 10, height: 10).accessibilityHidden(true)
                        Text(kayit.baslik).font(.subheadline).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(kayit.sonuc.baslik).font(.caption.weight(.semibold)).foregroundStyle(renk(kayit.sonuc))
                        Text(kayit.saat.formatted(date: .omitted, time: .standard)).font(.caption2).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                if durum.sonOkutmalar.isEmpty { Text("Henüz okutma yok").font(.subheadline).foregroundStyle(.secondary) }
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: .rect(cornerRadius: 14))
            .accessibilityIdentifier("scanner.log")
            HStack {
                Text("Okutulan: \(durum.matchedTotal) / Beklenen: \(durum.expectedTotal)" + (durum.unmatchedTotal > 0 ? " · Liste dışı: \(durum.unmatchedTotal)" : ""))
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Geri al", systemImage: "arrow.uturn.backward", action: geriAl)
                    .disabled(!durum.geriAlinabilir)
                    .frame(minHeight: 44)
                    .accessibilityLabel("Son okutmayı geri al")
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(.regularMaterial, in: .capsule)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 30)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("scanner.panel")
    }
}
#endif

// MARK: - Tutanak üretimi

/// Tutanağın arka planda üretilebilmesi için ekran durumunun değer kopyası.
nonisolated struct SayimTutanakGirdisi: Sendable {
    nonisolated struct BaskaRaf: Sendable { let kitap: String; let kayitliYer: String }
    nonisolated struct SonrasiIslem: Sendable { let ad: String; let tarih: Date; let ayrinti: String }
    var oturum: String
    var gorevli: String
    var yontem: String
    var kapsam: String
    var baslangic: Date
    var uretim: Date
    var beklenenToplam: Int
    var okutulanToplam: Int
    var listeDisiToplam: Int
    var sabitlendi: Bool
    var durumKitaplari: [[InventoryExpectedItem]]
    var belirsiz: [InventoryExpectedItem]
    var baskaRaf: [BaskaRaf]
    var sayilan: [InventoryCountEntry]
    var eksik: [InventoryCountEntry]
    var fazla: [InventoryCountEntry]
    var kayitsiz: [(String, Int)]
    var barkodsuz: [InventoryExpectedItem]
    var okul: String
    var komisyon: [String]
    var sonrasi: [SonrasiIslem]
}

nonisolated enum SayimTutanagi {
    nonisolated enum Bicim: Sendable {
        case pdf, excel, csv
        var contentType: UTType {
            switch self {
            case .pdf: .pdf
            case .csv: .commaSeparatedText
            case .excel: InventoryFileDocument.xlsx
            }
        }
    }

    /// Tek tablo: Excel sayfası/CSV bloğu ve PDF bölümü aynı satırlardan türer.
    nonisolated struct Tablo {
        let sayfa: ReportTableExporter.Sheet
        let pdf: [(String, String)]
        /// Başlık satırı hariç veri satırı sayısı.
        var satirSayisi: Int { max(0, sayfa.rows.count - 1) }
    }

    private typealias Hucre = ReportTableExporter.Cell

    static func tablolar(_ g: SayimTutanakGirdisi) -> [Tablo] {
        func kitap(_ e: InventoryCountEntry) -> String { e.book.title + (e.book.author.isEmpty ? "" : " — " + e.book.author) }
        var sonuc: [Tablo] = []

        let ozet: [(String, Hucre)] = [
            ("Oturum", .text(g.oturum)), ("Sayan görevli", .text(g.gorevli)), ("Yöntem", .text(g.yontem)), ("Kapsam", .text(g.kapsam)),
            ("Tarih", .date(g.uretim)), ("Sayım başlangıcı", .date(g.baslangic)),
            ("Rafta beklenen (nüsha)", .int(g.beklenenToplam)), ("Okutulan (nüsha)", .int(g.okutulanToplam)),
            ("Liste dışı okutma (kayıtsız / başka raf)", .int(g.listeDisiToplam)),
            ("Başlangıç beklentisi", .text(g.sabitlendi ? "Sabitlendi" : "Sabitlenmemiş — sonuç kesin değildir"))
        ]
        sonuc.append(Tablo(sayfa: .init(name: "Özet", rows: [[.text("Gösterge"), .text("Değer")]] + ozet.map { [.text($0.0), $0.1] }),
                           pdf: ozet.map { ($0.0, $0.1.display) }))

        sonuc.append(Tablo(
            sayfa: .init(name: "Sayılan", rows: [["Kitap Adı", "Yazar", "ISBN", "Beklenen", "Sayılan", "Durum", "Doğrulama"].map(Hucre.text)] + g.sayilan.map {
                [.text($0.book.title), .text($0.book.author), .text($0.book.isbn ?? ""), .int($0.expected), .int($0.scanned),
                 .text($0.statusTitle), .text($0.confidenceNote(hasSnapshot: g.sabitlendi))] }),
            pdf: g.sayilan.map { (kitap($0), "Beklenen \($0.expected) / Sayılan \($0.scanned) · \($0.statusTitle) · \($0.confidenceNote(hasSnapshot: g.sabitlendi))") }))

        sonuc.append(Tablo(
            sayfa: .init(name: "Eksik", rows: [["Kitap Adı", "Yazar", "ISBN", "Beklenen", "Okutulan", "Eksik"].map(Hucre.text)] + g.eksik.map {
                [.text($0.book.title), .text($0.book.author), .text($0.book.isbn ?? ""), .int($0.expected), .int($0.scanned), .int($0.expected - $0.scanned)] }),
            pdf: g.eksik.map { (kitap($0), "Beklenen \($0.expected) / Okutulan \($0.scanned)") }))

        sonuc.append(Tablo(
            sayfa: .init(name: "Fazla", rows: [["Kitap Adı", "Yazar", "ISBN", "Beklenen", "Okutulan", "Fazla"].map(Hucre.text)] + g.fazla.map {
                [.text($0.book.title), .text($0.book.author), .text($0.book.isbn ?? ""), .int($0.expected), .int($0.scanned), .int($0.scanned - $0.expected)] }),
            pdf: g.fazla.map { ($0.book.title, "Beklenen \($0.expected) / Okutulan \($0.scanned)") }))

        sonuc.append(Tablo(
            sayfa: .init(name: "Kayıtsız", rows: [["Barkod", "Okutulma"].map(Hucre.text)] + g.kayitsiz.map { [.text($0.0), .int($0.1)] }),
            pdf: g.kayitsiz.map { ($0.0, "\($0.1) kez") }))

        sonuc.append(Tablo(
            sayfa: .init(name: "Barkodsuz", rows: [["Kitap Adı", "Yazar", "Kayıtlı Adet"].map(Hucre.text)] + g.barkodsuz.map {
                [.text($0.title), .text($0.author), .int($0.quantity ?? 1)] }),
            pdf: g.barkodsuz.map { ($0.title, "\($0.quantity ?? 1) adet") }))

        sonuc.append(Tablo(
            sayfa: .init(name: "Başka Raf", rows: [["Kitap Adı", "Kayıtlı yer", "Bulunan yer"].map(Hucre.text)] + g.baskaRaf.map {
                [.text($0.kitap), .text($0.kayitliYer), .text(g.kapsam)] }),
            pdf: g.baskaRaf.map { ($0.kitap, "\($0.kayitliYer) → \(g.kapsam)") }))

        var disi: [(String, InventoryExpectedItem, Int)] = []
        for (index, category) in InventorySnapshot.statusCategories.enumerated() where index < g.durumKitaplari.count {
            disi += g.durumKitaplari[index].map { (category.0, $0, $0.stock[keyPath: category.1]) }
        }
        disi += g.belirsiz.map { ("Nüsha kimliği belirsiz — kesin sonuç değildir", $0, $0.unresolvedLoans ?? 0) }
        sonuc.append(Tablo(
            sayfa: .init(name: "Kapsam Dışı", rows: [["Durum", "Kitap Adı", "Yazar", "ISBN", "Nüsha"].map(Hucre.text)] + disi.map {
                [.text($0.0), .text($0.1.title), .text($0.1.author), .text($0.1.isbn ?? ""), .int($0.2)] }),
            pdf: disi.map { ("\($0.0): \($0.1.title)" + ($0.1.author.isEmpty ? "" : " — " + $0.1.author), "\($0.2) nüsha") }))

        if !g.sonrasi.isEmpty {
            sonuc.append(Tablo(
                sayfa: .init(name: "Sayım Sonrası", rows: [["İşlem", "Ayrıntı", "Tarih"].map(Hucre.text)] + g.sonrasi.map {
                    [.text($0.ad), .text($0.ayrinti), .date($0.tarih)] }),
                pdf: g.sonrasi.map { ($0.ad, $0.ayrinti) }))
        }
        return sonuc
    }

    static func uret(_ g: SayimTutanakGirdisi, bicim: Bicim) -> Data {
        let tablolar = tablolar(g)
        switch bicim {
        case .excel: return ReportTableExporter.excel(sheets: tablolar.map(\.sayfa))
        case .csv: return ReportTableExporter.csv(sheets: tablolar.map(\.sayfa))
        case .pdf:
            let bolumler = tablolar.map { tablo in
                PDFReportBuilder.Section(title: tablo.sayfa.name == "Özet" ? "Özet" : "\(tablo.sayfa.name) (\(tablo.satirSayisi))", rows: tablo.pdf)
            }
            return PDFReportBuilder.build(
                title: (g.okul.isEmpty ? "" : g.okul.uppercased(with: Locale(identifier: "tr_TR")) + " ") + "KÜTÜPHANE SAYIM TUTANAĞI",
                subtitle: "Tarih: \(g.uretim.formatted(date: .long, time: .shortened))  •  Kitap Bul",
                sections: bolumler,
                signatures: g.komisyon.enumerated().map { "\($0.offset == 0 ? "Komisyon Başkanı" : "Üye") \($0.element)" })
        }
    }
}

extension SayimDurumu {
    func tutanakGirdisi(commission: String, schoolName: String, sonrasiIslemler: [InventoryActionReceipt], now: Date = .now) -> SayimTutanakGirdisi {
        SayimTutanakGirdisi(
            oturum: sessionName, gorevli: operatorName, yontem: method, kapsam: selectedLocation,
            baslangic: startedAt, uretim: now, beklenenToplam: expectedTotal, okutulanToplam: matchedTotal,
            listeDisiToplam: unmatchedTotal, sabitlendi: hasSnapshot, durumKitaplari: statusBooks, belirsiz: identityUncertainBooks,
            baskaRaf: otherLocationBooks.map { .init(kitap: $0.title, kayitliYer: outsidePlaces(for: $0)) },
            sayilan: countedEntries, eksik: missingEntries, fazla: surplusEntries,
            kayitsiz: unknownCounts.sorted { $0.key < $1.key }.map { ($0.key, $0.value) },
            barkodsuz: barcodelessBooks, okul: schoolName,
            komisyon: commission.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
            sonrasi: sonrasiIslemler.map { .init(ad: $0.kind == .move ? "Konum taşıma" : ($0.kind == .markLost ? "Kayıp işaretleme" : "Yeni nüsha"),
                                                 tarih: $0.createdAt, ayrinti: $0.title + ": " + $0.changes.prefix(5).map(\.title).joined(separator: ", ")
                                                    + ($0.changes.count > 5 ? " …" : "")) })
    }
}

// MARK: - Oturum modeli

/// Yarım kalan sayım oturumu. Eski sürümlerde tek dosyada (`SayimOturumu.json`) saklanırdı; bugün beklenti ve
/// okutmalar iki dosyadadır, bu tür yalnız bellekteki görünümü ve eski dosya biçimidir.
struct InventorySession: Codable {
    var scanned: [String: Int] = [:]
    var unknown: [String: Int] = [:]
    var location = "Tümü"
    var startedAt: Date?
    var expected: [InventoryExpectedItem]? = nil
    var name: String? = nil
    var operatorName: String? = nil
    var method: String? = nil
    var observations: [InventoryObservation]? = nil
    var catalogSnapshot: [InventoryExpectedItem]? = nil
}

nonisolated struct InventoryCopySnapshot: Codable, Identifiable {
    var id: UUID
    var bookID: UUID
    var accessionCode: String
    var location: String? = nil
    var status: String? = nil
    var cabinet: String? = nil
    var shelf: String? = nil
}

nonisolated struct InventoryExpectedItem: Codable, Identifiable {
    var id: UUID
    var title: String
    var author: String
    var isbn: String?
    var quantity: Int?
    var location: String?
    var stock: LibraryStock
    var copies: [InventoryCopySnapshot]
    var unresolvedLoans: Int? = nil
}

enum InventorySnapshot {
    nonisolated static let statusCategories: [(String, KeyPath<LibraryStock, Int>)] = [
        ("Ödünçte — sayım dışında", \.loaned), ("Kayıp", \.lost), ("Onarımda", \.repair), ("Düşülmüş", \.withdrawn)
    ]
    /// Kayıtlı konum seçeneklerde yoksa ve eski ayraçlı biçimdeyse bugünkü biçimi döner. Listede bulunan
    /// serbest yazılmış yer adı (içinde " • " geçse de) olduğu gibi kalır.
    static func guncelKonum(_ secili: String, secenekler: [String]) -> String {
        guard !secenekler.contains(secili) else { return secili }
        let yeni = BookCopy.eskiAyraciCevir(secili)
        return secenekler.contains(yeni) ? yeni : secili
    }

    /// Eserin yeri tek kuraldır: genel konum doluysa o; değilse eserin dolap/rafından türeyen metin.
    /// Nüshası olmayan (yalnız adetle sayılan) kitap da bu yerle kapsama girer. Raporlardaki adet hesabı
    /// (`LibraryReportEngine.scopedQuantity`) kimliksiz adetlere aynı şekilde eserin dolap/rafını uygular.
    static func eserYeri(_ book: CatalogBook) -> String {
        if let konum = book.location, !konum.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return konum }
        return BookCopy.place(cabinet: book.cabinet, shelf: book.shelf)
    }

    static func capture(books: [CatalogBook], loans: [ActiveLoan], copies: [BookCopy], reservations: [Reservation], location: String, now: Date = .now) -> [InventoryExpectedItem] {
        let grouped = Dictionary(grouping: copies, by: \.bookID)
        let relevant = books.filter { book in
            location == "Tümü" || eserYeri(book) == location || (grouped[book.id] ?? []).contains { $0.effectivePlace(for: book) == location }
        }
        let states = SchoolLibraryService.stockByBook(books: relevant, loans: loans, copies: copies, reservations: reservations, now: now)
        let loansByBook = Dictionary(grouping: loans, by: \.bookID)
        let reservationsByBook = Dictionary(grouping: reservations, by: \.bookID)
        return relevant.map { book in
            let own = grouped[book.id] ?? []
            let selected = location == "Tümü" ? own : own.filter { $0.effectivePlace(for: book) == location }
            let selectedIDs = Set(selected.map(\.id))
            var stock = states[book.id] ?? .init()
            var unresolvedLoans = 0
            let bookPlace = eserYeri(book)
            if location != "Tümü", selected.count != own.count || bookPlace != location {
                let unmanaged = bookPlace == location ? max(0, (book.quantity ?? 1) - own.count) : 0
                stock = .init(); stock.total = selected.count + unmanaged
                if book.isWithdrawn { stock.withdrawn = stock.total }
                else {
                    let bookLoans = loansByBook[book.id] ?? []
                    stock.lost = selected.filter { $0.status == "Kayıp" }.count
                    stock.repair = selected.filter { $0.status == "Onarımda" }.count
                    stock.withdrawn = selected.filter { $0.status == "Düşüldü" }.count
                    let specificLoans = bookLoans.filter { $0.copyID.map(selectedIDs.contains) == true }.count
                    let unassignedLoans = bookLoans.filter { $0.copyID == nil }.count + ((book.loanedTo ?? "").isEmpty ? 0 : 1)
                    unresolvedLoans = unassignedLoans
                    let circulating = max(0, stock.total - stock.lost - stock.repair - stock.withdrawn)
                    stock.loaned = min(circulating, specificLoans + unassignedLoans)
                    stock.reserved = (reservationsByBook[book.id] ?? []).filter {
                        !$0.isClosed && $0.notifiedAt != nil && ($0.expiresAt ?? .distantFuture) > now && ($0.copyID.map(selectedIDs.contains) ?? (unmanaged > 0))
                    }.count
                    stock.available = max(0, stock.total - stock.lost - stock.repair - stock.withdrawn - stock.loaned - stock.reserved)
                }
            }
            return InventoryExpectedItem(id: book.id, title: book.title, author: book.author, isbn: book.isbn, quantity: book.quantity,
                location: book.location, stock: stock,
                copies: selected.map { InventoryCopySnapshot(id: $0.id, bookID: $0.bookID, accessionCode: $0.accessionCode,
                    location: $0.effectivePlace(for: book), status: $0.status, cabinet: $0.cabinet, shelf: $0.shelf) },
                unresolvedLoans: unresolvedLoans > 0 ? unresolvedLoans : nil)
        }
    }
}

// MARK: - Diskte iki dosyalı oturum

/// Beklenti dosyasının içeriği: sayım başlarken bir kez yazılır, okutmalar ayrı günlüktedir.
nonisolated struct InventoryExpectation: Codable {
    var location: String
    var startedAt: Date?
    var name: String?
    var operatorName: String?
    var method: String?
    var expected: [InventoryExpectedItem]?
    var catalogSnapshot: [InventoryExpectedItem]?
}

struct InventoryOpenResult {
    var session: InventorySession
    var undo: [InventoryUndoRecord]
    /// Günlüğün bozuk son satırı atıldı.
    var tailDropped: Bool
    /// Eski tek dosya biçiminden yeni iki dosyaya taşındı.
    var migrated: Bool
}

/// Okutma günlüğü (`SayimOkutmalar.jsonl`): her satır bir olay. Satır satır eklenir, bozuk son satır atılır.
nonisolated enum InventoryLog {
    nonisolated enum Kind: String, Codable { case scan, unknown, undo, base }
    nonisolated struct Line: Codable {
        var t: Kind
        var key: String?
        var obs: InventoryObservation?
        /// `base`: eski oturumdan veya sıkıştırmadan gelen toplam sayaçlar
        var scanned: [String: Int]?
        var unknown: [String: Int]?
        var observations: [InventoryObservation]?
    }
    nonisolated struct Replayed {
        var scanned: [String: Int] = [:]
        var unknown: [String: Int] = [:]
        var observations: [InventoryObservation] = []
        var undo: [InventoryUndoRecord] = []
        var tailDropped = false
        /// Geçerli satırların bittiği bayt konumu (bozuk kuyruk bundan sonrasıdır)
        var goodLength = 0
        /// Son geçerli satır satır sonu karakteri olmadan bitiyor
        var needsNewline = false
    }

    static func encode(_ line: Line) throws -> Data {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        var data = try encoder.encode(line)
        data.append(0x0A)
        return data
    }

    static func decrement(_ counts: inout [String: Int], key: String) {
        guard let value = counts[key] else { return }
        if value <= 1 { counts.removeValue(forKey: key) } else { counts[key] = value - 1 }
    }

    /// Günlüğü baştan oynatır. Ortadaki bozuk satır hatadır (dosya korunur); yalnız son satır atılabilir.
    static func replay(_ data: Data) throws -> Replayed {
        var result = Replayed()
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        var offset = 0
        let bytes = [UInt8](data)
        var lineStart = 0
        var lines: [(start: Int, end: Int, terminated: Bool)] = []
        while lineStart < bytes.count {
            var end = lineStart
            while end < bytes.count, bytes[end] != 0x0A { end += 1 }
            lines.append((lineStart, end, end < bytes.count))
            lineStart = end + 1
        }
        let lastContent = lines.lastIndex { $0.end > $0.start }
        for (index, line) in lines.enumerated() {
            guard line.end > line.start else { offset = min(bytes.count, line.end + 1); result.goodLength = offset; continue }
            let slice = data.subdata(in: line.start..<line.end)
            guard let parsed = try? decoder.decode(Line.self, from: slice) else {
                if index == lastContent { result.tailDropped = true; return result }
                throw CocoaError(.fileReadCorruptFile)
            }
            apply(parsed, to: &result)
            offset = min(bytes.count, line.end + 1)
            result.goodLength = offset
            result.needsNewline = !line.terminated
        }
        return result
    }

    static func apply(_ line: Line, to result: inout Replayed) {
        switch line.t {
        case .scan:
            guard let key = line.key else { return }
            result.scanned[key, default: 0] += 1
            if let obs = line.obs { result.observations.append(obs) }
            result.undo.append(.init(key: key, unknown: false, observationID: line.obs?.id))
        case .unknown:
            guard let key = line.key else { return }
            result.unknown[key, default: 0] += 1
            result.undo.append(.init(key: key, unknown: true, observationID: nil))
        case .undo:
            guard let last = result.undo.popLast() else { return }
            if last.unknown { decrement(&result.unknown, key: last.key) } else { decrement(&result.scanned, key: last.key) }
            if let id = last.observationID, let index = result.observations.lastIndex(where: { $0.id == id }) { result.observations.remove(at: index) }
        case .base:
            for (key, value) in line.scanned ?? [:] { result.scanned[key, default: 0] += value }
            for (key, value) in line.unknown ?? [:] { result.unknown[key, default: 0] += value }
            result.observations.append(contentsOf: line.observations ?? [])
            result.undo.removeAll()
        }
    }
}

/// Okutmaları bellekte toplayıp 300 ms içinde tek yazımda diske ekler (append + fsync).
/// Uygulama arka plana giderken `flush()` zorla yazar.
@MainActor
final class InventoryJournal {
    private var pending = Data()
    private var flushTask: Task<Void, Never>?
    private(set) var lastError: String?
    var bekleyenBayt: Int { pending.count }

    func append(_ line: InventoryLog.Line) {
        do { pending.append(try InventoryLog.encode(line)) }
        catch { lastError = error.localizedDescription; return }
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            self.flushTask = nil
            _ = self.writePending()
        }
    }

    /// Bekleyen satırları hemen yazar; yazılamazsa satırlar bellekte kalır ve sonraki denemede eklenir.
    @discardableResult
    func flush() -> Bool {
        flushTask?.cancel(); flushTask = nil
        return writePending()
    }

    func discardPending() {
        flushTask?.cancel(); flushTask = nil
        pending.removeAll(); lastError = nil
    }

    private func writePending() -> Bool {
        guard !pending.isEmpty else { lastError = nil; return true }
        guard let url = InventorySessionStore.scansURL else { lastError = CocoaError(.fileNoSuchFile).localizedDescription; return false }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) { guard FileManager.default.createFile(atPath: url.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) } }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: pending)
            try handle.synchronize()
            pending.removeAll(); lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }
}

/// Beklenti dosyası geçerli JSON kalır ama gövdesi boyut ve SHA-256 ile mühürlüdür; tam çözümleme olmadan doğrulanır.
nonisolated enum InventorySeal {
    private static let marker = Data(",\"body\":".utf8)

    static func seal(_ body: Data) -> Data {
        let digest = SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
        var out = Data("{\"format\":\"kitapbul-sayim-beklenti\",\"version\":1,\"size\":\(body.count),\"sha256\":\"\(digest)\"".utf8)
        out.append(marker); out.append(body); out.append(0x7D)
        return out
    }

    private nonisolated struct Header: Decodable { let format: String; let size: Int; let sha256: String }

    /// Mührü doğrular ve gövdeyi döner; boyut veya özet uyuşmazsa hata verir.
    static func unseal(_ data: Data) throws -> Data {
        guard let range = data.range(of: marker, in: data.startIndex..<min(data.endIndex, data.startIndex + 512)),
              data.last == 0x7D else { throw CocoaError(.fileReadCorruptFile) }
        let headerData = data.subdata(in: data.startIndex..<range.lowerBound) + Data("}".utf8)
        let header = try JSONDecoder().decode(Header.self, from: headerData)
        let body = data.subdata(in: range.upperBound..<(data.endIndex - 1))
        guard header.format == "kitapbul-sayim-beklenti", header.size == body.count,
              SHA256.hash(data: body).map({ String(format: "%02x", $0) }).joined() == header.sha256 else { throw CocoaError(.fileReadCorruptFile) }
        return body
    }
}

enum InventorySessionStore {
    static var directoryOverride: URL?
    static let legacyFileName = "SayimOturumu.json"
    static let expectationFileName = "SayimBeklenti.json"
    static let scansFileName = "SayimOkutmalar.jsonl"

    private static var directory: URL? { directoryOverride ?? ArchiveSettings.supportingDirectory }
    private static func file(_ name: String) -> URL? { directory?.appendingPathComponent(name) }
    /// Eski tek dosya biçimi
    static var legacyURL: URL? { file(legacyFileName) }
    static var expectationURL: URL? { file(expectationFileName) }
    static var scansURL: URL? { file(scansFileName) }

    private static var fm: FileManager { .default }

    // MARK: Yeni biçim

    /// Beklentiyi mühürleyerek yazar ve yazılanı boyut + SHA ile doğrular. Var olan dosya bozuksa üzerine yazmaz.
    static func writeExpectation(_ expectation: InventoryExpectation) throws {
        guard let url = expectationURL else { throw CocoaError(.fileNoSuchFile) }
        if fm.fileExists(atPath: url.path) { _ = try InventorySeal.unseal(Data(contentsOf: url)) }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let sealed = InventorySeal.seal(try encoder.encode(expectation))
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try sealed.write(to: url, options: .atomic)
        let written = try Data(contentsOf: url)
        guard written.count == sealed.count, SHA256.hash(data: written) == SHA256.hash(data: sealed) else { throw CocoaError(.fileWriteUnknown) }
        _ = try InventorySeal.unseal(written)
    }

    static func readExpectation() throws -> InventoryExpectation? {
        guard let url = expectationURL, fm.fileExists(atPath: url.path) else { return nil }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(InventoryExpectation.self, from: InventorySeal.unseal(Data(contentsOf: url)))
    }

    /// Tüm oturumu yeni iki dosyaya yazar; okutmalar tek `base` satırına sıkıştırılır. Göç ve "yeniden kaydet" kullanır.
    static func saveFull(_ session: InventorySession) throws {
        guard let scans = scansURL else { throw CocoaError(.fileNoSuchFile) }
        if let url = expectationURL, fm.fileExists(atPath: url.path) { _ = try InventorySeal.unseal(Data(contentsOf: url)) }
        try fm.createDirectory(at: scans.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Önce okutmalar: yarıda kalırsa beklenti dosyası olmadığından eski biçim okunmaya devam eder.
        if session.scanned.isEmpty && session.unknown.isEmpty && (session.observations ?? []).isEmpty {
            if fm.fileExists(atPath: scans.path) { try fm.removeItem(at: scans) }
        } else {
            let base = InventoryLog.Line(t: .base, scanned: session.scanned, unknown: session.unknown, observations: session.observations ?? [])
            try InventoryLog.encode(base).write(to: scans, options: .atomic)
        }
        try writeExpectation(InventoryExpectation(location: session.location, startedAt: session.startedAt, name: session.name,
            operatorName: session.operatorName, method: session.method, expected: session.expected, catalogSnapshot: session.catalogSnapshot))
    }

    /// Oturumu açar: yeni iki dosya varsa onları, yoksa eski tek dosyayı okur ve tek seferlik yeni biçime taşır.
    static func openSession() throws -> InventoryOpenResult {
        if let expectation = try readExpectation() {
            var replayed = InventoryLog.Replayed()
            if let scans = scansURL, fm.fileExists(atPath: scans.path) {
                replayed = try InventoryLog.replay(Data(contentsOf: scans))
                try repairTail(scans, replayed: replayed)
            }
            return InventoryOpenResult(session: assemble(expectation, replayed), undo: replayed.undo, tailDropped: replayed.tailDropped, migrated: false)
        }
        guard let legacy = legacyURL, fm.fileExists(atPath: legacy.path) else {
            return InventoryOpenResult(session: InventorySession(), undo: [], tailDropped: false, migrated: false)
        }
        let session = try decodeLegacy(legacy)
        try saveFull(session)
        // Eski dosya silinmez; yedek adıyla yan yana kalır (arşiv kümesi dışında).
        let backup = legacy.appendingPathExtension("eski")
        try? fm.removeItem(at: backup)
        try? fm.moveItem(at: legacy, to: backup)
        return InventoryOpenResult(session: session, undo: [], tailDropped: false, migrated: true)
    }

    private static func assemble(_ e: InventoryExpectation, _ r: InventoryLog.Replayed) -> InventorySession {
        InventorySession(scanned: r.scanned, unknown: r.unknown, location: e.location, startedAt: e.startedAt, expected: e.expected,
                         name: e.name, operatorName: e.operatorName, method: e.method,
                         observations: r.observations, catalogSnapshot: e.catalogSnapshot)
    }

    /// Bozuk kuyruğu keser (sonraki ekleme onun yanına yapışmasın) ve eksik satır sonunu tamamlar.
    private static func repairTail(_ url: URL, replayed: InventoryLog.Replayed) throws {
        guard replayed.tailDropped || replayed.needsNewline else { return }
        let handle = try FileHandle(forUpdating: url)
        defer { try? handle.close() }
        if replayed.tailDropped { try handle.truncate(atOffset: UInt64(replayed.goodLength)) }
        else { try handle.seekToEnd(); try handle.write(contentsOf: Data([0x0A])) }
        try handle.synchronize()
    }

    private static func decodeLegacy(_ url: URL) throws -> InventorySession {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(InventorySession.self, from: Data(contentsOf: url))
    }

    // MARK: Eski API (geri uyum)

    /// Eski tek dosya biçiminde yazar (içe aktarma ve eski sürümle uyum). Bozuk mevcut dosyanın üzerine yazmaz.
    static func saveVerified(_ session: InventorySession) throws {
        guard let url = legacyURL else { throw CocoaError(.fileNoSuchFile) }
        _ = try loadVerified()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(session).write(to: url, options: .atomic)
    }

    static func save(_ session: InventorySession) {
        do { try saveVerified(session) } catch { AppLog.write("Sayım oturumu kaydedilemedi") }
    }

    static func load() -> InventorySession {
        (try? loadVerified()) ?? InventorySession()
    }

    /// Yan etkisiz okuma: yeni iki dosya varsa onlar, yoksa eski tek dosya.
    static func loadVerified() throws -> InventorySession {
        if let expectation = try readExpectation() {
            var replayed = InventoryLog.Replayed()
            if let scans = scansURL, fm.fileExists(atPath: scans.path) { replayed = try InventoryLog.replay(Data(contentsOf: scans)) }
            return assemble(expectation, replayed)
        }
        guard let url = legacyURL else { throw CocoaError(.fileNoSuchFile) }
        guard fm.fileExists(atPath: url.path) else { return InventorySession() }
        return try decodeLegacy(url)
    }

    static func clear() {
        do { try clearVerified() } catch { AppLog.write("Sayım oturumu temizlenemedi") }
    }

    /// Okutmalar önce, beklenti ve eski dosya sonra silinir; yarıda kalırsa oturum sıfırlanmamış görünür.
    static func clearVerified() throws {
        guard let legacy = legacyURL, let expectation = expectationURL, let scans = scansURL else { throw CocoaError(.fileNoSuchFile) }
        for url in [scans, expectation, legacy, legacy.appendingPathExtension("eski")] where fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
    }
}

// MARK: - Dışa aktarma belgeleri

/// Sayım tutanağı (CSV): Excel'in Türkçe karakterleri doğru göstermesi için UTF-8 BOM ile yazılır.
struct InventoryReportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    let text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        text = ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data("\u{FEFF}\(text)".utf8))
    }
}

/// Hazır tutanak baytları (PDF, XLSX veya CSV); dışa aktarma penceresi içeriği olduğu gibi yazar.
struct InventoryFileDocument: FileDocument {
    nonisolated static let xlsx = UTType("org.openxmlformats.spreadsheetml.sheet") ?? .data
    static var readableContentTypes: [UTType] { [.pdf, .commaSeparatedText, xlsx] }

    var data: Data

    init(data: Data = Data()) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
