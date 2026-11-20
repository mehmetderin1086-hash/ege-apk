import SwiftUI
import SwiftData

/// Raf görünümü ana katalogda tutulur; aynı kayıt ayrıntısına açılır. Gruplar ortak konum
/// biçimiyle adlanır; yeri atanmamış kitaplar her zaman en sonda toplanır.
struct RafKonumListesi: View {
    let kitaplar: [CatalogBook]
    /// Etkin ödünçler; satırdaki durum liste ve ayrıntıyla aynı stok kuralından gelir (`stockByBook`).
    var loans: [ActiveLoan] = []
    var onSelect: ((UUID) -> Void)? = nil
    @Query private var copies: [BookCopy]
    @Query private var reservations: [Reservation]
    private struct Shelf: Identifiable {
        let name: String
        let books: [CatalogBook]
        var id: String { name }
        var yerAtanmamis: Bool { name == CatalogBook.yerAtanmamis }
    }
    private var shelves: [Shelf] {
        Dictionary(grouping: kitaplar) { $0.konumMetni ?? CatalogBook.yerAtanmamis }
            .map { Shelf(name: $0.key, books: $0.value.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }) }
            .sorted { a, b in
                if a.yerAtanmamis != b.yerAtanmamis { return b.yerAtanmamis }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
    }
    var body: some View {
        let stoklar = SchoolLibraryService.stockByBook(books: kitaplar, loans: loans, copies: copies, reservations: reservations)
        List {
            if shelves.isEmpty { ContentUnavailableView("Rafta kitap yok", systemImage: "cabinet", description: Text("Kitap eklerken dolap ve raf bilgilerini girin.")) }
            ForEach(shelves) { shelf in
                Section {
                    ForEach(shelf.books) { book in
                        let stok = stoklar[book.id] ?? LibraryStock(total: max(1, book.quantity ?? 1))
                        if let onSelect { Button { onSelect(book.id) } label: { row(book, stok: stok) }.buttonStyle(.plain) }
                        else { NavigationLink(value: book.id) { row(book, stok: stok) } }
                    }
                } header: {
                    Text("\(shelf.name) · \(shelf.books.count) başlık")
                } footer: {
                    if shelf.yerAtanmamis { Text("Bu kitaplara ayrıntıdaki “Yer değiştir…” ile dolap ve raf atayın.") }
                }
            }
        }
    }
    private func row(_ book: CatalogBook, stok: LibraryStock) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(book.title).font(.headline).foregroundStyle(Color.primary)
            Text(book.author).font(.subheadline).foregroundStyle(KitapTema.ikincilMetin)
            Text(KitapDurumu.rafSatiri(stok))
                .font(.caption).foregroundStyle(KitapTema.ikincilMetin)
        }.padding(.vertical, 4).accessibilityElement(children: .combine)
    }
}

/// Aynı adlı öğrenciler ad, sınıf, numara ve kayıt kimliğiyle ayrılır. Liste sınıf bölümlerine
/// ayrılır; sınıf menüsüyle daraltılır ya da öğrenci kartı okutularak doğrudan seçilir.
struct OgrenciSecimSayfasi: View {
    /// Barkod masası kartı kendi kamerasıyla okur: oradan açılınca ikinci bir tarayıcı açılmaz.
    var kartOkutma = true
    let onSelect: (Student) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var students = StudentStore.all()
    @State private var sinif = ""
    @State private var manage = false
    @State private var kartOkut = false
    @State private var kartHatasi: String?
    private var filtered: [Student] {
        let term = CatalogMatcher.normalize(search)
        return students.filter { (sinif.isEmpty || $0.className == sinif) && (term.isEmpty || CatalogMatcher.normalize([$0.name, $0.className, $0.number].joined(separator: " ")).contains(term)) }
            .sorted {
                if $0.className != $1.className { return $0.className.localizedStandardCompare($1.className) == .orderedAscending }
                if $0.name != $1.name { return $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                return $0.number.localizedStandardCompare($1.number) == .orderedAscending
            }
    }
    /// Sınıf bölümleri, listedeki sırayla (sınıfsızlar en sonda).
    private var bolumler: [(sinif: String, ogrenciler: [Student])] {
        let gruplar = Dictionary(grouping: filtered, by: \.className)
        return gruplar.keys.sorted { a, b in
            if a.isEmpty != b.isEmpty { return !a.isEmpty }
            return a.localizedStandardCompare(b) == .orderedAscending
        }.map { ($0, gruplar[$0] ?? []) }
    }
    /// Ad, sınıf ve numarası aynı olan kayıtlar: liste başına bir kez hesaplanır.
    private var yinelenenler: Set<String> {
        Set(Dictionary(grouping: students, by: { anahtar($0) }).filter { $0.value.count > 1 }.keys)
    }
    private func anahtar(_ student: Student) -> String { [student.name, student.className, student.number].joined(separator: "|") }

    var body: some View {
        let yinelenen = yinelenenler
        NavigationStack {
            List {
                if let kartHatasi { Label(kartHatasi, systemImage: "exclamationmark.triangle").foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
                if filtered.isEmpty { ContentUnavailableView("Öğrenci bulunamadı", systemImage: "person.crop.circle.badge.questionmark", description: Text("Aramayı ya da sınıf seçimini değiştirin veya öğrenci listesine kayıt ekleyin.")) }
                ForEach(bolumler, id: \.sinif) { bolum in
                    Section {
                        ForEach(bolum.ogrenciler) { student in
                            Button { onSelect(student); dismiss() } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(student.name).font(.headline).foregroundStyle(Color.primary)
                                    if yinelenen.contains(anahtar(student)) { Text("Kayıt \(student.id.uuidString.prefix(8))").font(.caption).foregroundStyle(.secondary) }
                                    Text([student.className, student.number.isEmpty ? nil : "No \(student.number)"].compactMap { $0 }.joined(separator: " · "))
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }.padding(.vertical, 4).frame(minHeight: 44).accessibilityElement(children: .combine)
                            }.accessibilityIdentifier("student.option.\(student.name).\(student.className).\(student.number)")
                        }
                    } header: {
                        Text("\(bolum.sinif.isEmpty ? "Sınıfsız" : bolum.sinif) (\(bolum.ogrenciler.count))")
                    }
                }
            }
            .searchable(text: $search, prompt: "Ad, sınıf veya öğrenci numarası")
            .navigationTitle(sinif.isEmpty ? "Öğrenci seç" : "Öğrenci seç · \(sinif)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } }
                ToolbarItemGroup(placement: .primaryAction) {
                    if kartOkutma {
                        Button("Kartı okut", systemImage: "person.text.rectangle") { kartHatasi = nil; kartOkut = true }
                    }
                    Menu {
                        Button("Tüm sınıflar") { sinif = "" }
                        ForEach(StudentStore.classNames(), id: \.self) { ad in Button(ad) { sinif = ad } }
                    } label: { Label("Sınıf", systemImage: "line.3.horizontal.decrease") }
                    Button("Öğrenciler", systemImage: "person.badge.plus") { manage = true }
                }
            }
            .sheet(isPresented: $manage, onDismiss: { students = StudentStore.all() }) { StudentsView() }
            .fullScreenCover(isPresented: $kartOkut) {
                ZStack(alignment: .topTrailing) {
                    LiveISBNScannerView { kod in
                        kartOkut = false
                        kartiCoz(kod)
                    } onCancel: { kartOkut = false }
                    .ignoresSafeArea()
                    // Düğme güvenli alanda kalır: durum çubuğunun ve ekran köşesinin altına girmez.
                    Button { kartOkut = false } label: {
                        Label("Kapat", systemImage: "xmark.circle.fill").labelStyle(.iconOnly).font(.largeTitle)
                            .foregroundStyle(.white).shadow(radius: 3).frame(minWidth: 44, minHeight: 44)
                    }
                    .padding()
                    .accessibilityLabel("Kart okumayı kapat")
                }
            }
        }
    }

    private func kartiCoz(_ kod: String) {
        do {
            let ogrenci = try SchoolLibraryService.student(forCard: kod)
            onSelect(ogrenci)
            dismiss()
        } catch { kartHatasi = error.localizedDescription }
    }
}

/// Üye seçimi ad benzerliğine göre öğrenci kaydına dönüşmez; sabit UUID taşınır.
struct UyeSecimSayfasi: View {
    let onSelect: (Member) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var members: [Member] = []
    @State private var error: String?
    @State private var manage = false
    private var filtered: [Member] {
        let term = CatalogMatcher.normalize(search)
        return members.filter { term.isEmpty || CatalogMatcher.normalize([$0.name, $0.memberNumber, $0.note].joined(separator: " ")).contains(term) }
            .sorted {
                $0.name != $1.name ? $0.name.localizedStandardCompare($1.name) == .orderedAscending
                    : $0.memberNumber.localizedStandardCompare($1.memberNumber) == .orderedAscending
            }
    }
    var body: some View {
        NavigationStack {
            List {
                if let error { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                if filtered.isEmpty && error == nil { ContentUnavailableView("Üye bulunamadı", systemImage: "person.crop.circle.badge.questionmark", description: Text("Aramayı değiştirin veya üye listesine kayıt ekleyin.")) }
                ForEach(filtered) { member in
                    Button { onSelect(member); dismiss() } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(member.name).font(.headline).foregroundStyle(Color.primary)
                            Text(member.memberNumber.isEmpty ? "Kayıt \(member.id.uuidString.prefix(8))" : "Üye no \(member.memberNumber)").font(.subheadline).foregroundStyle(.secondary)
                        }.padding(.vertical, 4).frame(minHeight: 44).accessibilityElement(children: .combine)
                    }.accessibilityIdentifier("member.option.\(member.id.uuidString)")
                }
            }
            .searchable(text: $search, prompt: "Ad veya üye numarası")
            .navigationTitle("Üye seç")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button("Üyeler", systemImage: "person.badge.plus") { manage = true } }
            }
            .onAppear { reload() }
            .sheet(isPresented: $manage, onDismiss: { reload() }) { MembersView() }
        }
    }
    private func reload() {
        do { members = try MemberStore.allVerified(); error = nil }
        catch { self.error = "Üye dosyası okunamadı: " + error.localizedDescription }
    }
}

struct KitapOduncFormu: View {
    let kitap: CatalogBook
    /// Kayıttan hemen önce çağıranın denetimi (ör. etkin katalog hâlâ aynı mı); hata atarsa kayıt yapılmaz.
    var kayitOncesi: (@MainActor () throws -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var loans: [ActiveLoan]
    @Query private var copies: [BookCopy]
    @Query private var reservations: [Reservation]
    private enum Recipient: String, CaseIterable, Identifiable {
        case student = "Öğrenci", member = "Üye", manual = "Elle"
        var id: String { rawValue }
    }
    @State private var recipient: Recipient = .student
    @State private var student: Student?
    @State private var member: Member?
    @State private var manualName = ""
    @State private var manualClass = ""
    @State private var memberPicker = false
    @State private var copyID: UUID?
    @State private var studentPicker = false
    @State private var error: String?
    @State private var discard = false
    @State private var saving = false
    /// Aynı okur aynı kitabı zaten tutuyorsa sorulan onay metni.
    @State private var yineDeVerSorusu: String?

    private var person: String {
        switch recipient { case .student: student?.name ?? ""; case .member: member?.name ?? ""; case .manual: manualName.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    private var personClass: String { recipient == .student ? student?.className ?? "" : recipient == .manual ? manualClass.trimmingCharacters(in: .whitespacesAndNewlines) : "" }
    private var dirty: Bool { student != nil || member != nil || !manualName.isEmpty || !manualClass.isEmpty || copyID != nil }
    private var stock: LibraryStock { SchoolLibraryService.stock(for: kitap, loans: loans, copies: copies, reservations: reservations) }
    private var availableCopies: [BookCopy] {
        copies.filter { copy in
            copy.bookID == kitap.id && copy.status == "Rafta" && !loans.contains { $0.copyID == copy.id }
                && !reservations.contains { reservation in
                    reservation.copyID == copy.id && !reservation.isClosed && reservation.notifiedAt != nil
                        && reservation.expiresAt.map { $0 > .now } != false
                        && !(recipient == .student && student != nil && reservation.studentID == student?.id)
                }
        }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Kitap") {
                    Text(kitap.title).font(.headline)
                    Text(kitap.author).foregroundStyle(.secondary)
                    LabeledContent("Nüshalar", value: "\(stock.available) rafta · \(stock.reserved) ayrılmış")
                }
                Section("Ödünç alan") {
                    Picker("Okur türü", selection: $recipient) { ForEach(Recipient.allCases) { Text($0.rawValue).tag($0) } }
                        .accessibilityIdentifier("lend.recipientKind")
                    switch recipient {
                    case .student:
                        Button { studentPicker = true } label: {
                            if let student { Label("\(student.name) · \(student.className) · \(student.number)", systemImage: "person.crop.circle") }
                            else { Label("Öğrenci seç", systemImage: "person.badge.plus") }
                        }.accessibilityIdentifier("lend.selectStudent")
                    case .member:
                        Button { memberPicker = true } label: {
                            if let member { Label("\(member.name) · \(member.memberNumber)", systemImage: "person.crop.circle") }
                            else { Label("Üye seç", systemImage: "person.badge.plus") }
                        }.accessibilityIdentifier("lend.selectMember")
                    case .manual:
                        TextField("Okur adı", text: $manualName).accessibilityIdentifier("lend.manualName")
                        TextField("Sınıf (isteğe bağlı)", text: $manualClass)
                        Text("Bu kayıt serbest okur olarak saklanır. Aynı adlı öğrenci veya üye kaydına otomatik bağlanmaz.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if !availableCopies.isEmpty {
                    Section("Fiziksel nüsha") {
                        Picker("Demirbaş", selection: $copyID) {
                            Text("İlk uygun nüsha").tag(UUID?.none)
                            ForEach(availableCopies) { copy in Text(copy.accessionCode.isEmpty ? "Nüsha \(copy.id.uuidString.prefix(8))" : copy.accessionCode).tag(Optional(copy.id)) }
                        }
                    }
                }
                Section {
                    Text("Süre, öğrenci sınıfının ödünç kuralına göre belirlenir. Kota, gecikme ve rezervasyon uygunluğu kaydetmeden önce kontrol edilir.").font(.footnote).foregroundStyle(.secondary)
                    if let error { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
                }
            }
            .navigationTitle("Ödünç ver")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { if dirty { discard = true } else { dismiss() } } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Kaydediliyor…" : "Ödünç ver") { lend() }.disabled(person.isEmpty || saving)
                        .accessibilityIdentifier("lend.save")
                }
            }
            .sheet(isPresented: $studentPicker) { OgrenciSecimSayfasi { student = $0; copyID = nil } }
            .sheet(isPresented: $memberPicker) { UyeSecimSayfasi { member = $0; copyID = nil } }
            .onChange(of: recipient) { student = nil; member = nil; copyID = nil; error = nil }
            .interactiveDismissDisabled(dirty)
            .confirmationDialog("Ödünç işlemi kaydedilmeden kapatılsın mı?", isPresented: $discard, titleVisibility: .visible) {
                Button("Kaydetmeden kapat", role: .destructive) { dismiss() }
                Button("Devam et", role: .cancel) { }
            }
            .confirmationDialog(yineDeVerSorusu ?? "", isPresented: Binding(get: { yineDeVerSorusu != nil }, set: { if !$0 { yineDeVerSorusu = nil } }), titleVisibility: .visible) {
                Button("Yine de ver") { yineDeVerSorusu = nil; lend(yineDeVer: true) }
                Button("Vazgeç", role: .cancel) { yineDeVerSorusu = nil }
            }
        }
    }
    private func lend(yineDeVer: Bool = false) {
        guard !person.isEmpty else { return }
        saving = true
        defer { saving = false }
        do {
            try kayitOncesi?()
            _ = try SchoolLibraryService.lend(book: kitap, person: person, className: personClass, context: context,
                studentID: recipient == .student ? student?.id : nil, copyID: copyID,
                memberID: recipient == .member ? member?.id : nil, resolveKnownStudent: recipient == .student, yineDeVer: yineDeVer)
            AccessibilityNotification.Announcement("\(kitap.title), \(person) adına ödünç verildi.").post()
            dismiss()
        } catch let hata as SchoolLibraryService.OperationError where hata.kod == .zatenElinde {
            yineDeVerSorusu = hata.message
        } catch { self.error = error.localizedDescription }
    }
}

struct OduncDetaySayfasi: View {
    let loan: ActiveLoan
    /// İade sonrası sonuç metni (rezervasyon bildirimi dahil) çağıran ekranın mesaj şeridine iletilir.
    var onReturned: ((String) -> Void)? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("loanDurationDays") private var duration = 15
    @Query private var copies: [BookCopy]
    @State private var error: String?
    @State private var lostConfirm = false
    @State private var report: String?
    @State private var identityReview = false
    @State private var completedReading: Bool? = nil
    @State private var returnedCondition: String? = nil
    /// Uzatmadan sonra "Tarihler" bölümünde geçici onay.
    @State private var extendedNotice: String?
    private var studentNumber: String? { loan.studentNumberSnapshot ?? StudentStore.all().first { $0.id == loan.studentID }?.number }
    private var accession: String? { copies.first { $0.id == loan.copyID }?.accessionCode }

    var body: some View {
        NavigationStack {
            if let report {
                ScrollView { Text(report).textSelection(.enabled).padding() }
                    .navigationTitle("Kayıp tutanağı")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Kapat") { dismiss() } }; ToolbarItem(placement: .primaryAction) { ShareLink(item: report) } }
            } else {
            Form {
                Section("Kitap ve nüsha") {
                    Text(loan.bookTitleSnapshot).font(.headline)
                    if let accession, !accession.isEmpty { LabeledContent("Demirbaş", value: accession) }
                    else { Text("Bu eski kayıtta nüsha kimliği bulunmuyor.").font(.footnote).foregroundStyle(.secondary) }
                }
                Section("Okur") {
                    LabeledContent("Ad", value: loan.studentName)
                    if loan.memberID != nil { LabeledContent("Kayıt türü", value: "Üye") }
                    LabeledContent("Sınıf", value: loan.studentClass)
                    if let studentNumber, !studentNumber.isEmpty { LabeledContent("Numara", value: studentNumber) }
                    if loan.needsIdentityReview || loan.identitySource == nil || loan.identitySource == "legacy" || loan.identitySource == "unresolved" || loan.copyID == nil {
                        if loan.needsIdentityReview { Label("Okur kimliği yönetici incelemesi bekliyor", systemImage: "person.crop.circle.badge.questionmark").font(.footnote) }
                        Button("Okur / nüsha kimliğini düzelt", systemImage: "person.crop.circle.badge.checkmark") { identityReview = true }
                            .accessibilityIdentifier("loan.reviewIdentity")
                    }
                }
                Section("Tarihler") {
                    LabeledContent("Verildi", value: loan.loanedAt.formatted(OduncMerkezi.tarihBicimi))
                    LabeledContent("Son gün", value: loan.dueDate.formatted(OduncMerkezi.tarihBicimi))
                    LabeledContent("Uzatma sayısı", value: "\(loan.extensionCount)")
                    if loan.isOverdue {
                        Label { Text(OduncMerkezi.sonGunMetni(loan.dueDate)) } icon: { Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red) }
                    }
                    if let extendedNotice {
                        Label { Text(extendedNotice) } icon: { Image(systemName: "checkmark.circle.fill").foregroundStyle(KitapTema.basari) }
                    }
                }
                if loan.kind != "textbook" {
                    Section("İadede okuma bilgisi") {
                        Picker("Okuma durumu", selection: $completedReading) {
                            Text("Bilgi verilmedi").tag(Optional<Bool>.none)
                            Text("Tamamladı").tag(Optional(true))
                            Text("Tamamlamadı").tag(Optional(false))
                        }.pickerStyle(.menu).accessibilityIdentifier("loan.readingCompleted")
                    }
                }
                Section {
                    Picker("Kitabın durumu", selection: $returnedCondition) {
                        Text("Belirtilmedi").tag(Optional<String>.none)
                        Text("İyi").tag(Optional("İyi"))
                        ForEach(OduncMerkezi.hasarliIadeDurumlari, id: \.self) { Text($0).tag(Optional($0)) }
                    }.pickerStyle(.menu).accessibilityIdentifier("loan.returnedCondition")
                } header: { Text("İadede kitabın durumu") } footer: {
                    Text("“Onarım gerekli” seçilirse nüsha onarıma ayrılır ve rafta sayılmaz.")
                }
                Section {
                    Button("Süreyi uzat", systemImage: "calendar.badge.plus") { extend() }
                        .disabled(uzatmaSiniri)
                        .accessibilityIdentifier("loan.extend")
                    ShareLink(item: OduncMerkezi.veliMesaji(ogrenci: loan.studentName, sinif: loan.studentClass, kitap: loan.bookTitleSnapshot, sonGun: loan.dueDate)) { Label("Veli mesajını paylaş", systemImage: "square.and.arrow.up") }
                    Button("Kayıp bildir", systemImage: "exclamationmark.octagon", role: .destructive) { lostConfirm = true }
                } header: { Text("İşlemler") } footer: {
                    if uzatmaSiniri { Text("Bu ödünç en fazla \(OduncMerkezi.enFazlaUzatma) kez uzatılabilir; sınıra ulaşıldı.") }
                }
                if let error { Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) } }
            }
            // İade düğmesi her zaman görünür alt şeritte; overlay değil, form içeriği şeridin üstünde kalır.
            .safeAreaInset(edge: .bottom) {
                Button { returnLoan() } label: {
                    Label(iadeEtiketi, systemImage: "arrow.uturn.left")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.kitapDolu(KitapTema.anaDolu))
                .accessibilityIdentifier("loan.return")
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
            }
            .navigationTitle("Ödünç ayrıntısı")
            .sheet(isPresented: $identityReview) {
                YoneticiKilidi(baslik: "Ödünç kimliğini düzelt") {
                    LoanIdentityReviewSheet(loan: loan) { identityReview = false }
                }
            }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Kapat") { dismiss() } } }
            .confirmationDialog("Bu nüsha kayıp olarak kaydedilsin mi?", isPresented: $lostConfirm, titleVisibility: .visible) {
                Button("Kayıp bildir", role: .destructive) {
                    Task {
                        do {
                            report = try await YetkiKapisi.yoneticiyleCalistir(neden: "Kayıp bildirmek için kimliğinizi doğrulayın") {
                                try SchoolLibraryService.reportLost(loan, context: context)
                            }
                        } catch let hata as SchoolLibraryService.OperationError where hata.kod == .kayipNushaGerekli {
                            // Hangi nüshanın kaybolduğu bilinmiyor: nüsha kimliği düzeltme ekranı açılır.
                            self.error = hata.message
                            identityReview = true
                        } catch { self.error = error.localizedDescription }
                    }
                }
            }
            }
        }
    }
    private var uzatmaSiniri: Bool { loan.extensionCount >= OduncMerkezi.enFazlaUzatma }
    /// Düğme, iadeye işlenecek kitap durumunu da söyler ("İade al · Onarım gerekli").
    private var iadeEtiketi: String { returnedCondition.map { "İade al · \($0)" } ?? "İade al" }

    private func extend() {
        do {
            let yeni = try OduncMerkezi.uzat(loan, context: context, defaultDays: duration)
            let metin = "Süre uzatıldı. Yeni son gün: \(yeni.formatted(OduncMerkezi.tarihBicimi))"
            error = nil
            extendedNotice = metin
            AccessibilityNotification.Announcement(metin).post()
        } catch { self.error = error.localizedDescription }
    }
    private func returnLoan() {
        do {
            let title = loan.bookTitleSnapshot
            let person = loan.studentName
            let notice = try SchoolLibraryService.returnLoan(loan, context: context, returnedCondition: returnedCondition,
                                                                 readingCompleted: loan.kind == "textbook" ? nil : completedReading)
            let metin = "\(title) iade alındı: \(person)." + (notice.map { " " + $0 } ?? "")
            AccessibilityNotification.Announcement(metin).post()
            onReturned?(metin)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

/// Liste ve menülerde hızlı iadenin yanında sunulan "hasarlı iade" seçenekleri.
/// Hızlı iade durum belirtmez; bunlar kitabın durumunu geçmişe ve nüshaya işler.
struct HasarliIadeSecenekleri: View {
    let iadeAl: (String) -> Void
    var body: some View {
        ForEach(OduncMerkezi.hasarliIadeDurumlari, id: \.self) { durum in
            Button("\(durum) olarak iade al", systemImage: durum == "Onarım gerekli" ? "wrench.and.screwdriver" : "book.closed") { iadeAl(durum) }
        }
    }
}

struct NushaDuzenlemeSayfasi: View {
    let copy: BookCopy
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var loans: [ActiveLoan]
    @State private var accession: String
    @State private var condition: String
    @State private var status: String
    @State private var note: String
    @State private var cabinet: String
    @State private var shelf: String
    @State private var error: String?
    @State private var discard = false
    init(copy: BookCopy) {
        self.copy = copy
        _accession = State(initialValue: copy.accessionCode)
        _condition = State(initialValue: copy.condition)
        _status = State(initialValue: copy.status)
        _note = State(initialValue: copy.note)
        _cabinet = State(initialValue: copy.cabinet ?? "")
        _shelf = State(initialValue: copy.shelf ?? "")
    }
    private var dirty: Bool { accession != copy.accessionCode || condition != copy.condition || status != copy.status || note != copy.note || cabinet != (copy.cabinet ?? "") || shelf != (copy.shelf ?? "") }
    private var loaned: Bool { loans.contains { $0.copyID == copy.id } }
    var body: some View {
        NavigationStack {
            Form {
                Section("Fiziksel nüsha") {
                    TextField("Demirbaş kodu", text: $accession).textInputAutocapitalization(.characters).autocorrectionDisabled()
                    Picker("Fiziksel durum", selection: $condition) { ForEach(BookCopy.conditions, id: \.self) { Text($0).tag($0) } }
                    Picker("Dolaşım durumu", selection: $status) { ForEach(BookCopy.statuses, id: \.self) { Text($0).tag($0) } }.disabled(loaned)
                    TextField("Not", text: $note, axis: .vertical)
                }
                Section {
                    TextField("Nüshanın dolabı (boşsa eserden devral)", text: $cabinet).disabled(loaned)
                    TextField("Nüshanın rafı (boşsa eserden devral)", text: $shelf).disabled(loaned)
                } header: { Text("Nüshaya özel konum").foregroundStyle(.primary) } footer: {
                    Text("Boş alan eser konumunu devralır. Aynı eserin farklı nüshaları farklı dolap ve raflarda tutulabilir. Ödünçteki nüsha taşınmadan önce iade alınır.")
                }
                if loaned { Section { Text("Nüsha şu an ödünçte. Kayıp işlemini ilgili ödünç ayrıntısından yapın; diğer dolaşım değişiklikleri için önce iade alın.").font(.footnote) } }
                if let error { Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) } }
            }
            .navigationTitle("Nüsha düzenle")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { if dirty { discard = true } else { dismiss() } } }
                ToolbarItem(placement: .confirmationAction) { Button("Kaydet") { Task { await save() } }.disabled(!dirty) }
            }
            .interactiveDismissDisabled(dirty)
            .confirmationDialog("Nüsha değişiklikleri kaydedilmeden kapatılsın mı?", isPresented: $discard, titleVisibility: .visible) {
                Button("Kaydetmeden kapat", role: .destructive) { dismiss() }
                Button("Devam et", role: .cancel) { }
            }
        }
    }
    private func save() async {
        guard await YetkiDurumu.shared.yoneticiOl() else { error = YetkiDurumu.shared.hata ?? "Yönetici kimliği gerekir."; return }
        let code = accession.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let copies = try context.fetch(FetchDescriptor<BookCopy>())
            guard code.isEmpty || !copies.contains(where: { $0.id != copy.id && CatalogMatcher.normalize($0.accessionCode) == CatalogMatcher.normalize(code) }) else {
                error = "Bu demirbaş kodu başka bir nüshada kullanılıyor."; return
            }
            let currentLoans = try context.fetch(FetchDescriptor<ActiveLoan>())
            guard status == copy.status || !currentLoans.contains(where: { $0.copyID == copy.id }) else { error = "Ödünçteki nüshanın dolaşım durumu değiştirilemez."; return }
            guard !currentLoans.contains(where: { $0.copyID == copy.id }) ||
                (cabinet == (copy.cabinet ?? "") && shelf == (copy.shelf ?? "")) else {
                error = "Ödünçteki nüshanın konumu değiştirilemez; önce iade alın."; return
            }
            copy.accessionCode = code
            copy.condition = condition
            copy.status = status
            copy.note = note
            let cleanCabinet = cabinet.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanShelf = shelf.trimmingCharacters(in: .whitespacesAndNewlines)
            copy.cabinet = cleanCabinet.isEmpty ? nil : cleanCabinet
            copy.shelf = cleanShelf.isEmpty ? nil : cleanShelf
            try context.save()
            dismiss()
        } catch { context.rollback(); self.error = error.localizedDescription }
    }
}
