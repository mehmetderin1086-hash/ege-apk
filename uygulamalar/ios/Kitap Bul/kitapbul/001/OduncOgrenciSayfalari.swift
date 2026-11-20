import SwiftUI
import SwiftData
import Charts
import UniformTypeIdentifiers

// MARK: - Barkod masası (ödünç ve iade)

/// Ödünçte: 1) öğrenci kartını okut → 2) kitap barkodlarını okut. İadede öğrenci gerekmez; ödünç
/// kaydı kitaptan ya da demirbaştan bulunur. Tarayıcı açık kalır: yeni bir öğrenci kartı okununca
/// sıradaki öğrenciye geçilir. Her kitap işleminin sonucu karar satırında kitap, okur ve yerle görünür.
struct HizliOduncSayfasi: View {
    enum Mode: String, CaseIterable, Identifiable {
        case lend = "Ödünç ver", giveBack = "İade al"
        var id: String { rawValue }
    }
    /// Son kitap işleminin özeti: kitap adı; okur · sınıf · gecikme ya da son gün; yer.
    private struct Karar {
        let kitap: String
        let okur: String
        let konum: String
        let bildirim: String?
        let iade: Bool
    }
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage("scanHapticsEnabled") private var haptics = true
    @Query private var loans: [ActiveLoan]
    @Query private var copies: [BookCopy]
    @State private var student: Student?
    @State private var mode: Mode
    @State private var log: [(text: String, error: Bool)] = []
    /// Her yeni sonuçta artar (log 30 kayıtla sınırlı olduğundan sayısı değişmeyebilir).
    @State private var islemSayaci = 0
    @State private var studentPicker = false
    @State private var manualCode = ""
    @State private var returnCandidates: [ActiveLoan] = []
    @State private var iadeKitabi: CatalogBook?
    /// Aday sayfası demirbaş okutulduktan sonra mı açıldı (nüshasız ödünç)? Açıklama metni buna göre.
    @State private var demirbasOkutuldu = false
    @State private var returnedCondition: String?
    @State private var karar: Karar?
    @State private var suzgec = TekrarSuzgeci()
    /// Barkod masasının ödünçte sorduğu ek soru: hangi nüsha ya da aynı eser ikinci kez verilsin mi.
    private struct Soru {
        enum Tur { case nusha([BookCopy]), yineDeVer(BookCopy?) }
        let kitap: CatalogBook
        let mesaj: String
        let tur: Tur
    }
    @State private var soru: Soru?
    /// İadede "Okudu mu?": nil = bilgi yok. Her iadeden sonra sıfırlanır.
    @State private var okudu: Bool?

    init(baslangic: Mode = .lend) {
        _mode = State(initialValue: baslangic)
    }

    var body: some View {
        LiveISBNScannerView(continuous: true, allowRepeats: true) { kameradan($0) } onCancel: { dismiss() }
            .ignoresSafeArea()
            .safeAreaInset(edge: .top) {
                if mode == .giveBack {
                    // Masanın hangi modda olduğu kameradan başını kaldırmadan da görülsün.
                    Label("İADE", systemImage: "arrow.uturn.left")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color.green.mix(with: .black, by: 0.5))
                        .accessibilityLabel("İade modu")
                        .accessibilityIdentifier("quickLoan.returnBanner")
                }
            }
            .safeAreaInset(edge: .bottom) { panel }
            .sheet(isPresented: $studentPicker) { OgrenciSecimSayfasi(kartOkutma: false) { student = $0 } }
            .sheet(isPresented: Binding(get: { !returnCandidates.isEmpty }, set: { if !$0 { returnCandidates = [] } })) {
                NavigationStack {
                    List {
                        Section {
                            ForEach(returnCandidates) { loan in
                                Button {
                                    let secilen = loan
                                    returnCandidates = []
                                    giveBack(secilen)
                                } label: { adaySatiri(loan) }
                                .accessibilityIdentifier("quickLoan.candidate")
                            }
                        } footer: {
                            if student == nil {
                                Text(demirbasOkutuldu
                                     ? "Okutulan nüsha hiçbir ödünç kaydına bağlı değil; kitap nüsha seçilmeden verilmiş. Kitabı getireni seçin."
                                     : "Bu kitabın birden çok nüshası var. Kitabı getireni seçin; nüshanın demirbaşını okutursanız soru sorulmaz.")
                            }
                        }
                    }
                    .navigationTitle(student == nil ? "Kimin iadesi?" : "İade edilecek nüsha")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { returnCandidates = [] } } }
                }
            }
            .onChange(of: mode) { _, yeni in
                soru = nil
                if yeni == .lend { returnedCondition = nil; okudu = nil }
            }
    }

    /// Sıra: işlem, öğrenci, son sonuç, kod alanı, sonra seyrek kullanılanlar. Son sonuç ile kod alanı
    /// kaydırmadan görünür; "Bitti" kaydırma alanının dışında, her zaman yerinde durur.
    private var panel: some View {
        VStack(spacing: 0) {
            ScrollViewReader { kaydirma in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("İşlem", selection: $mode) { ForEach(Mode.allCases) { Text($0.rawValue).tag($0) } }
                            .pickerStyle(.segmented).accessibilityIdentifier("quickLoan.mode")
                        HStack(spacing: 8) {
                            Button { studentPicker = true } label: {
                                Label(student.map { "\($0.name) · \($0.className) · \($0.number)" }
                                      ?? (mode == .lend ? "1. adım: öğrenci seç veya kartını okut" : "İsteğe bağlı: öğrenci seç veya kartını okut"),
                                      systemImage: "person.crop.circle")
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.kitapTonlu()).accessibilityIdentifier("quickLoan.student")
                            if student != nil {
                                Button { student = nil } label: { Label("Öğrenciyi kaldır", systemImage: "xmark").labelStyle(.iconOnly) }
                                    .buttonStyle(.kitapTonlu())
                            }
                        }
                        if let student { ogrenciOzeti(student) }
                        sonucAlani.id(Self.sonucKimligi)
                        HStack {
                            TextField("ISBN veya demirbaş kodu", text: $manualCode).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder).submitLabel(.go).onSubmit { elleIsle() }
                                .accessibilityIdentifier("quickLoan.code")
                            Button("İşle") { elleIsle() }.buttonStyle(.kitapTonlu()).disabled(manualCode.isEmpty)
                                .accessibilityIdentifier("quickLoan.process")
                        }
                        if mode == .giveBack {
                            Menu {
                                Picker("Kitabın durumu", selection: $returnedCondition) {
                                    Text("Belirtilmedi").tag(Optional<String>.none)
                                    Text("İyi").tag(Optional("İyi"))
                                    ForEach(OduncMerkezi.hasarliIadeDurumlari, id: \.self) { Text($0).tag(Optional($0)) }
                                }
                            } label: {
                                Label("Kitabın durumu: \(returnedCondition ?? "Belirtilmedi")", systemImage: "book.closed")
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.kitapTonlu())
                            .accessibilityHint("Bir sonraki iadeye işlenir; iadeden sonra Belirtilmedi'ye döner")
                            .accessibilityIdentifier("quickLoan.condition")
                            Picker("Okudu mu?", selection: $okudu) {
                                Text("Bilgi yok").tag(Bool?.none)
                                Text("Tamamladı").tag(Bool?.some(true))
                                Text("Tamamlamadı").tag(Bool?.some(false))
                            }
                            .pickerStyle(.segmented)
                            .accessibilityHint("Bir sonraki iadeye işlenir; iadeden sonra Bilgi yok'a döner")
                            .accessibilityIdentifier("quickLoan.reading")
                        }
                        Text(mode == .lend ? "2. adım: ödünç verilecek kitabı veya nüsha barkodunu okut."
                             : "Kitabı veya nüsha barkodunu okut. Öğrenci seçmek gerekmez; çok nüshalı kitapta kimin iadesi olduğu sorulur.")
                            .font(.subheadline).fixedSize(horizontal: false, vertical: true)
                        let oncekiler = Array(log.dropLast().suffix(3))
                        if !oncekiler.isEmpty {
                            Text("Önceki işlemler").font(.footnote.weight(.semibold)).foregroundStyle(KitapTema.ikincilMetin)
                            ForEach(Array(oncekiler.enumerated()), id: \.offset) { _, entry in
                                Label {
                                    Text(entry.text)
                                } icon: {
                                    Image(systemName: entry.error ? "exclamationmark.triangle" : "checkmark.circle")
                                        .foregroundStyle(entry.error ? Color.red : Color.primary)
                                }
                                .font(.subheadline).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }.padding()
                }
                // Panel elle aşağı kaydırılmışsa ya da büyük yazıda sonuç sığmıyorsa yeni sonuç görünür alana gelir.
                .onChange(of: islemSayaci) { withAnimation { kaydirma.scrollTo(Self.sonucKimligi) } }
            }
            Button("Bitti") { dismiss() }.buttonStyle(.kitapDolu(KitapTema.anaDolu))
                .padding([.horizontal, .bottom]).padding(.top, 8)
        }
        .frame(maxHeight: typeSize.isAccessibilitySize ? 480 : 380)
        .background(.regularMaterial)
    }

    private static let sonucKimligi = "quickLoan.sonuc"

    /// Son okutmanın sonucu: son kayıt hataysa hata, değilse son kitap işleminin karar satırı.
    @ViewBuilder private var sonucAlani: some View {
        if let soru {
            soruAlani(soru)
        } else if let son = log.last, son.error {
            Label {
                Text(son.text).font(.subheadline.weight(.semibold))
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.red)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("quickLoan.error")
        } else if let karar {
            kararSatiri(karar)
        }
    }

    private func soruAlani(_ soru: Soru) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            switch soru.tur {
            case .nusha(let adaylar):
                Label("Hangi nüsha?", systemImage: "questionmark.circle.fill").font(.headline)
                Text("“\(soru.kitap.title)” için \(adaylar.count) boş nüsha var. Verdiğiniz nüshanın demirbaşını okutun ya da seçin.")
                    .font(.subheadline).fixedSize(horizontal: false, vertical: true)
                ForEach(adaylar.sorted { $0.accessionCode.localizedStandardCompare($1.accessionCode) == .orderedAscending }.prefix(8)) { nusha in
                    Button { lend(soru.kitap, nusha: nusha) } label: {
                        Text((nusha.accessionCode.isEmpty ? "Nüsha " + String(nusha.id.uuidString.prefix(8)) : nusha.accessionCode) + " · " + nusha.condition)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }.buttonStyle(.kitapTonlu()).accessibilityIdentifier("quickLoan.copyChoice")
                }
                Button { lend(soru.kitap, nusha: nil, secim: .nushasiz) } label: {
                    Text("Nüshasız kaydet").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }.buttonStyle(.kitapTonlu()).accessibilityIdentifier("quickLoan.noCopy")
            case .yineDeVer(let nusha):
                Label("Aynı kitap zaten ödünçte", systemImage: "exclamationmark.triangle.fill").font(.headline)
                Text(soru.mesaj).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                Button { lend(soru.kitap, nusha: nusha, yineDeVer: true) } label: {
                    Text("Yine de ver").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }.buttonStyle(.kitapTonlu()).accessibilityIdentifier("quickLoan.lendAgain")
            }
            Button("Vazgeç", role: .cancel) { self.soru = nil }.frame(minHeight: 44)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("quickLoan.question")
    }

    /// Öğrencinin elindeki ve geciken kitaplar: kota ya da gecikme engeli kitap okutulmadan görünür.
    private func ogrenciOzeti(_ student: Student) -> some View {
        let elinde = loans.filter { $0.memberID == nil && $0.studentID == student.id }
        let geciken = elinde.filter(\.isOverdue).count
        return Label {
            Text("Elinde \(elinde.count) kitap" + (geciken > 0 ? " · \(geciken) gecikmiş" : ""))
        } icon: {
            Image(systemName: geciken > 0 ? "exclamationmark.circle.fill" : "books.vertical")
                .foregroundStyle(geciken > 0 ? Color.red : KitapTema.ikincilMetin)
        }
        .font(.subheadline)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("quickLoan.studentSummary")
    }

    private func kararSatiri(_ karar: Karar) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(karar.iade ? "İade alındı" : "Ödünç verildi", systemImage: karar.iade ? "arrow.uturn.left.circle.fill" : "checkmark.circle.fill")
                .font(.footnote.weight(.semibold))
            Text(karar.kitap).font(.headline)
            Text(karar.okur).font(.subheadline)
            Label(karar.konum, systemImage: "mappin.and.ellipse").font(.subheadline)
            if let bildirim = karar.bildirim, !bildirim.isEmpty {
                Label(bildirim, systemImage: "bell.badge").font(.subheadline)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("quickLoan.result")
    }

    private func adaySatiri(_ loan: ActiveLoan) -> some View {
        let demirbas = copies.first { $0.id == loan.copyID }?.accessionCode ?? ""
        return VStack(alignment: .leading, spacing: 6) {
            Text([loan.studentName, loan.studentClass].filter { !$0.isEmpty }.joined(separator: " · ")).font(.headline)
            if loan.memberID != nil { Text("Üye ödüncü").font(.subheadline) }
            Text(demirbas.isEmpty ? "Veriliş: \(loan.loanedAt.formatted(OduncMerkezi.tarihBicimi))" : "Demirbaş \(demirbas)").font(.subheadline)
            Text(OduncMerkezi.sonGunMetni(loan.dueDate)).font(.subheadline)
        }
        .foregroundStyle(Color.primary)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Kameradan gelen kod: aynı barkod 3 saniye içinde yeniden okunursa yok sayılır.
    private func kameradan(_ kod: String) {
        guard suzgec.kabulEt(kod) else { return }
        process(kod)
    }
    private func elleIsle() {
        process(manualCode)
        manualCode = ""
    }

    private func process(_ raw: String) {
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        soru = nil
        switch OkutCozumleyici.coz(raw, context: context) {
        case .ogrenci(let found):
            student = found
            add("\(found.name) · \(found.className) seçildi.")
        case .hata(let mesaj):
            karar = nil
            add(mesaj, error: true)
        case .kitap(let book, let nusha, _):
            if mode == .lend { lend(book, nusha: nusha) } else { iadeBul(book, nusha: nusha) }
        }
    }
    private func lend(_ book: CatalogBook, nusha: BookCopy?, secim: SchoolLibraryService.NushaSecimi = .sor, yineDeVer: Bool = false) {
        // Ödünç her zaman adı görünen bir öğrenciye yazılır.
        guard let student else { add("Önce öğrenci seçin veya kartını okutun.", error: true); return }
        do {
            let loan = try SchoolLibraryService.lend(book: book, person: student.name, className: student.className, context: context, studentID: student.id,
                                                     copyID: nusha?.id, nusha: secim, yineDeVer: yineDeVer)
            soru = nil
            let sonGun = loan.dueDate.formatted(OduncMerkezi.tarihBicimi)
            karar = Karar(kitap: book.title, okur: [student.name, student.className, "Son gün \(sonGun)"].filter { !$0.isEmpty }.joined(separator: " · "),
                          konum: book.konumMetni(nusha: nusha) ?? CatalogBook.yerAtanmamis, bildirim: nil, iade: false)
            add("\(book.title), \(student.name) adına verildi. Son gün \(sonGun).")
        } catch let hata as SchoolLibraryService.OperationError where hata.kod == .nushaBelirsiz {
            karar = nil
            let bosNushalar = copies.filter { copy in
                copy.bookID == book.id && copy.isCirculating && !loans.contains { $0.copyID == copy.id }
            }
            soru = Soru(kitap: book, mesaj: hata.message, tur: .nusha(bosNushalar))
            add("Hangi nüsha? " + hata.message)
        } catch let hata as SchoolLibraryService.OperationError where hata.kod == .zatenElinde {
            karar = nil
            soru = Soru(kitap: book, mesaj: hata.message, tur: .yineDeVer(nusha))
            add(hata.message)
        } catch { karar = nil; soru = nil; add(error.localizedDescription, error: true) }
    }
    private func iadeBul(_ book: CatalogBook, nusha: BookCopy?) {
        let sonuc = SchoolLibraryService.iadeAdaylari(loans: loans, bookID: book.id, copyID: nusha?.id, student: student,
                                                       nushaSayisi: OkutCozumleyici.nushaSayisi(book, context: context))
        guard let ilk = sonuc.adaylar.first else {
            karar = nil
            add(student == nil ? "“\(book.title)” için açık ödünç kaydı yok." : "Bu öğrenci adına eşleşen ödünç kaydı yok.", error: true)
            return
        }
        iadeKitabi = book
        demirbasOkutuldu = nusha != nil
        if sonuc.onayGerekir { returnCandidates = sonuc.adaylar } else { giveBack(ilk) }
    }
    private func giveBack(_ loan: ActiveLoan) {
        // Ödünç kaydı iadede silinir; satırın bilgileri önce alınır.
        let title = loan.bookTitleSnapshot
        let gecikme = OduncMerkezi.gecikmeGunu(sonGun: loan.dueDate)
        let okur = ([loan.studentName, loan.studentClass].filter { !$0.isEmpty } + (gecikme > 0 ? ["\(gecikme) gün gecikti"] : []))
            .joined(separator: " · ")
        let durum = returnedCondition
        let kitap = iadeKitabi?.id == loan.bookID ? iadeKitabi : nil
        let konum = durum == "Onarım gerekli" ? "Onarıma ayrıldı; rafa konmaz" : kitap?.konumMetni(nusha: copies.first { $0.id == loan.copyID }) ?? CatalogBook.yerAtanmamis
        do {
            let notice = try SchoolLibraryService.returnLoan(loan, context: context, returnedCondition: durum, readingCompleted: okudu)
            returnedCondition = nil
            okudu = nil
            karar = Karar(kitap: title, okur: okur, konum: konum, bildirim: notice, iade: true)
            // Satır VoiceOver'a da duyurulur: gecikme sesli bildirimde de yer alır.
            add("\(title) iade alındı: \(okur)." + (durum.map { " Durum: \($0)." } ?? "") + (notice.map { " " + $0 } ?? ""))
        } catch { karar = nil; add(error.localizedDescription, error: true) }
    }
    private func add(_ text: String, error: Bool = false) {
        log.append((text, error))
        if log.count > 30 { log.removeFirst(log.count - 30) }
        islemSayaci += 1
        if haptics { UINotificationFeedbackGenerator().notificationOccurred(error ? .error : .success) }
        AccessibilityNotification.Announcement(text).post()
    }
}

// MARK: - Rezervasyonlar

struct RezervasyonlarSayfasi: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Reservation.createdAt, order: .reverse) private var allReservations: [Reservation]
    @State private var showClosed = false
    @State private var search = ""
    private var acik: [Reservation] {
        let index = LibraryIdentitySearchIndex(students: StudentStore.all(), members: MemberStore.all())
        let term = CatalogMatcher.normalize(search)
        return allReservations.filter { reservation in
            reservation.isClosed == showClosed && (term.isEmpty || CatalogMatcher.normalize(reservation.bookTitleSnapshot + " " + index.text(name: reservation.studentName, className: reservation.studentClass, studentID: reservation.studentID, memberID: reservation.memberID, numberSnapshot: reservation.studentNumberSnapshot)).contains(term))
        }
    }
    @State private var error: String?
    @State private var deleteCandidate: Reservation?

    var body: some View {
        List {
            Toggle("Kapalı rezervasyon geçmişini göster", isOn: $showClosed).frame(minHeight: 44)
            if acik.isEmpty {
                ContentUnavailableView("Bekleyen rezervasyon yok", systemImage: "bookmark.slash",
                                       description: Text("Kitap ayrıntısından “Rezerve Et” ile ekleyin. Kitap iade edilince sıradaki okura haber verilir."))
            }
            ForEach(acik) { rez in
                VStack(alignment: .leading, spacing: 4) {
                    Text(rez.bookTitleSnapshot).font(.headline)
                    Text(rez.stateLabel).font(.subheadline.weight(.semibold))
                    Text("\(rez.studentName)\(rez.studentClass.isEmpty ? "" : " (\(rez.studentClass))") · \(rez.createdAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if let bildirim = rez.notifiedAt {
                        Label("Kitap geldi, haber verildi (\(bildirim.formatted(date: .abbreviated, time: .shortened)))", systemImage: "bell.badge.fill")
                            .font(.caption).foregroundStyle(KitapTema.basari)
                    }
                }
                .swipeActions {
                    if !rez.isClosed { Button("İptal et", systemImage: "xmark", role: .destructive) {
                        deleteCandidate = rez
                    } }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .navigationTitle("Rezervasyon sırası")
        .searchable(text: $search, prompt: "Ad, kitap veya okul numarası")
        .alert("Rezervasyon kaydedilemedi", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("Tamam") { error = nil } } message: { Text(error ?? "") }
        .confirmationDialog("Rezervasyon iptal edilsin mi? Geçmiş kaydı korunur.", isPresented: Binding(get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } }), titleVisibility: .visible) {
            Button("İptal et", role: .destructive) { if let reservation = deleteCandidate { changeReservation(reservation, delete: true) }; deleteCandidate = nil }
            Button("Vazgeç", role: .cancel) { deleteCandidate = nil }
        }
    }
    private func changeReservation(_ reservation: Reservation, delete: Bool) {
        do {
            try SchoolLibraryService.cancelReservation(reservation, context: modelContext)
        } catch { modelContext.rollback(); self.error = error.localizedDescription }
    }
}

/// Kitap ayrıntısında: bekleyen rezervasyonlar + "Rezerve Et".
struct RezervasyonBolumu: View {
    let kitap: CatalogBook
    @Environment(\.modelContext) private var modelContext
    @Query private var rezervasyonlar: [Reservation]
    @State private var recipient: LoanIdentitySelection?
    @State private var operationID = UUID()
    @State private var mesaj: String?
    @State private var hata = false

    init(kitap: CatalogBook) {
        self.kitap = kitap
        let id = kitap.id
        _rezervasyonlar = Query(filter: #Predicate<Reservation> { $0.bookID == id && !$0.isClosed }, sort: \Reservation.createdAt)
    }
    var body: some View {
        Section {
            ForEach(Array(rezervasyonlar.enumerated()), id: \.element.id) { sira, rez in
                LabeledContent("\(sira + 1). \(rez.studentName)", value: rez.memberID == nil ? rez.studentClass : "Üye")
                if let number = rez.studentNumberSnapshot, !number.isEmpty { Text("Okul no: " + number).font(.footnote) }
            }
            LibraryRecipientPicker(selection: $recipient)
            Button("Rezerve et", systemImage: "bookmark.fill") { reserve() }.disabled(recipient == nil)
                .accessibilityIdentifier("reservation.save")
            if let mesaj { Label(mesaj, systemImage: hata ? "exclamationmark.triangle" : "checkmark.circle").font(.subheadline).foregroundStyle(hata ? Color.red : Color.secondary).fixedSize(horizontal: false, vertical: true) }
        } header: { Text("Rezervasyon (\(rezervasyonlar.count))") }
    }
    private func reserve() {
        guard let recipient else { return }
        do {
            let saved: Reservation
            switch recipient {
            case .student(let id):
                guard let student = try SchoolLibraryService.resolvedStudent(name: "", className: "", id: id) else { return }
                saved = try OduncMerkezi.rezerveEt(book: kitap, student: student.name, className: student.className,
                    context: modelContext, studentID: id, operationID: operationID)
            case .member(let id):
                let member = try SchoolLibraryService.resolvedMember(id: id)
                saved = try OduncMerkezi.rezerveEt(book: kitap, student: member.name, className: "",
                    context: modelContext, memberID: id, resolveKnownStudent: false, operationID: operationID)
            }
            hata = false
            mesaj = "\(saved.studentName) sıraya alındı. Kitap döndüğünde Ödünç > Sıra bölümünde hazır görünür."
            self.recipient = nil; operationID = UUID()
        } catch { hata = true; mesaj = error.localizedDescription }
    }
}

// MARK: - Öğrenci profili

struct OgrenciProfili: View {
    let ogrenci: Student
    @Query private var loans: [ActiveLoan]
    @Query private var rezervasyonlar: [Reservation]

    private var anahtar: String { CatalogMatcher.normalize(ogrenci.name) }
    private var gecmis: [LoanEvent] { LoanHistoryStore.all.filter { $0.memberID == nil && $0.studentID == ogrenci.id } }
    private var etkin: [ActiveLoan] { loans.filter { $0.memberID == nil && $0.studentID == ogrenci.id } }
    @State private var historyLimit = 50

    var body: some View {
        let puan = OkumaPuani.siralama(gecmis).reduce(0) { $0 + $1.puan }
        let okunan = Set(gecmis.filter { $0.kind == .returned && $0.readingCompleted == true && $0.loanKind != "textbook" }.map(\.bookID)).count
        let fizikselIade = gecmis.filter { $0.kind == .returned }.count
        let gecikme = gecmis.filter { $0.kind == .returned && $0.wasLate }.count
        List {
            Section {
                HStack(spacing: 16) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(KitapTema.kitapRengi(ogrenci.name).gradient)
                    VStack(alignment: .leading) {
                        Text(ogrenci.name).font(.title3.weight(.bold))
                        Text([ogrenci.className, ogrenci.number.isEmpty ? nil : "No \(ogrenci.number)"]
                            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                            .foregroundStyle(.secondary)
                    }
                }
                HStack {
                    istatistik("\(puan)", "puan", KitapTema.vurgu)
                    istatistik("\(okunan)", "Tamamlanan okuma", KitapTema.basari)
                    istatistik("\(gecikme)", "gecikme", .red)
                }
            }

            Section("İade ve okuma") {
                LabeledContent("Fiziksel iade", value: "\(fizikselIade)")
                LabeledContent("Tamamlanan okuma", value: "\(okunan)")
                Text("İade alınması okunduğu anlamına gelmez. Okuma sayısı yalnız tamamlandığı bildirilen kütüphane kitaplarını kapsar.")
                    .font(.footnote).fixedSize(horizontal: false, vertical: true)
            }

            Section("Şu an elindeki (\(etkin.count))") {
                if etkin.isEmpty { Text("Ödünç kitap yok").foregroundStyle(.secondary) }
                ForEach(etkin) { loan in
                    LabeledContent(loan.bookTitleSnapshot, value: loan.dueDate.formatted(date: .abbreviated, time: .omitted))
                        .foregroundStyle(loan.isOverdue ? .red : .primary)
                }
            }

            let bekleyen = rezervasyonlar.filter { !$0.isClosed && $0.memberID == nil && $0.studentID == ogrenci.id }
            if !bekleyen.isEmpty {
                Section("Rezervasyonları") {
                    ForEach(bekleyen) { Text($0.bookTitleSnapshot) }
                }
            }

            Section("Okuma geçmişi (\(gecmis.count))") {
                if gecmis.isEmpty { Text("Bu öğrenci kimliğine bağlı hareket bulunmuyor.").foregroundStyle(.secondary) }
                ForEach(gecmis.prefix(historyLimit)) { olay in
                    VStack(alignment: .leading) {
                        Text(olay.bookTitle)
                        Text("\(olay.kind.rawValue) · \(olay.date.formatted(date: .abbreviated, time: .omitted))\(olay.wasLate ? " · gecikmeli" : "")")
                            .font(.caption)
                            .foregroundStyle(olay.wasLate ? .red : .secondary)
                    }
                }
                if historyLimit < gecmis.count { Button("Daha fazla göster (\(historyLimit)/\(gecmis.count))") { historyLimit += 50 } }
            }
        }
        .navigationTitle(ogrenci.name)
    }

    private func istatistik(_ deger: String, _ ad: String, _ renk: Color) -> some View {
        VStack {
            Text(deger).font(.title2.weight(.bold)).foregroundStyle(renk)
            Text(ad).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Sınıf panosu

struct SinifPanosu: View {
    @Query private var loans: [ActiveLoan]
    @AppStorage("schoolName") private var schoolName = ""
    @State private var sinif = StudentStore.classNames().first ?? ""

    var body: some View {
        let ogrenciler = StudentStore.students(in: sinif)
        let ids = Set(ogrenciler.map(\.id))
        let sinifOdunc = loans.filter { $0.memberID == nil && $0.studentID.map { ids.contains($0) } == true }
        let allHistory = LoanHistoryStore.all
        let history = allHistory.filter { $0.memberID == nil && $0.studentID.map { ids.contains($0) } == true }
        let siralama = OkumaPuani.siralama(history)
        let borrowedIDs = Set(history.filter { $0.kind == .lent && $0.loanKind != "textbook" }.compactMap(\.studentID))
            .union(sinifOdunc.filter { $0.kind != "textbook" }.compactMap(\.studentID))
        let neverBorrowed = ogrenciler.filter { !borrowedIDs.contains($0.id) }
        let unresolved = loans.filter { $0.memberID == nil && $0.studentID == nil && $0.studentClass == sinif }
        let unresolvedEvents = allHistory.filter { $0.memberID == nil && $0.studentID == nil && $0.classSnapshot == sinif }
        List {
            Picker("Sınıf", selection: $sinif) {
                ForEach(StudentStore.classNames(), id: \.self) { Text($0).tag($0) }
            }
            Section {
                HStack {
                    kutu("\(ogrenciler.count)", "öğrenci")
                    kutu("\(sinifOdunc.count)", "ödünçte")
                    kutu("\(sinifOdunc.filter(\.isOverdue).count)", "gecikmiş", renk: .red)
                    kutu("\(siralama.reduce(0) { $0 + $1.kitapSayisi })", "okunan")
                }
            }
            if !siralama.isEmpty {
                Section("En çok okuyanlar") {
                    Chart(siralama.prefix(8)) { satir in
                        BarMark(x: .value("Puan", satir.puan), y: .value("Öğrenci", satir.ad))
                            .foregroundStyle(KitapTema.toplu.gradient)
                    }
                    .frame(height: CGFloat(min(8, siralama.count)) * 30 + 10)
                    .accessibilityLabel("En çok okuyanlar: " + siralama.prefix(5).map { "\($0.ad) \($0.puan) puan" }.joined(separator: ", "))
                }
            }
            Section("Kimlikli kayıtlarda kitap almamış (\(neverBorrowed.count))") {
                ForEach(neverBorrowed) { o in NavigationLink(o.name) { OgrenciProfili(ogrenci: o) } }
            }
            if !unresolved.isEmpty || !unresolvedEvents.isEmpty {
                Section("Kimlik eşleştirmesi bekleyen eski kayıtlar") {
                    Text("\(unresolved.count) etkin ödünç ve \(unresolvedEvents.count) geçmiş hareketi öğrencilere tahminle atanmadı. Kitap almamış listesi yalnız kimlikli kayıtları kapsar.")
                        .font(.footnote).fixedSize(horizontal: false, vertical: true)
                    ForEach(unresolved) { loan in
                        NavigationLink { OduncDetaySayfasi(loan: loan) } label: { Text(loan.studentName + " · " + loan.bookTitleSnapshot) }
                    }
                }
            }
            if !sinifOdunc.filter(\.isOverdue).isEmpty {
                Section("Gecikenler") {
                    ShareLink(item: OduncMerkezi.sinifVeliMesajlari(LoanKindFilter.gecikenKutuphane(loans: sinifOdunc) + sinifOdunc.filter { $0.kind == "textbook" && $0.isOverdue }, okul: schoolName)) {
                        Label("Bu sınıfın veli mesajlarını paylaş", systemImage: "square.and.arrow.up.on.square")
                    }.frame(minHeight: 44).accessibilityIdentifier("classBoard.messages")
                    ForEach(sinifOdunc.filter(\.isOverdue)) { loan in
                        LabeledContent(loan.studentName, value: loan.bookTitleSnapshot)
                    }
                }
            }
        }
        .navigationTitle("Sınıf Panosu")
    }

    private func kutu(_ deger: String, _ ad: String, renk: Color = KitapTema.ana) -> some View {
        VStack {
            Text(deger).font(.title3.weight(.bold)).foregroundStyle(renk)
            Text(ad).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Sınıf atlatma sihirbazı

struct SinifAtlatmaSihirbazi: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage("promotionLastGrade") private var sonKademe = 8
    @State private var onayIsteniyor = false
    @State private var sonuc: String?
    @State private var error: String?
    @State private var previewLimit = 200

    var body: some View {
        let plan = SinifAtlatma.plan(StudentStore.all(), sonKademe: sonKademe)
        let degisen = plan.filter { $0.yeniSinif != $0.ogrenci.className }
        List {
            Section {
                Stepper("Son kademe: \(sonKademe). sınıf", value: $sonKademe, in: 4...12)
                Text("\(sonKademe). sınıftakiler mezun olur ve listeden çıkar; diğerleri bir üst sınıfa geçer (5-A → 6-A). Etkin ödünçlerin sınıf bilgisi de güncellenir.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Önizleme (\(degisen.count) değişiklik)") {
                ForEach(degisen.prefix(previewLimit)) { satir in
                    LabeledContent(satir.ogrenci.name, value: "\(satir.ogrenci.className) → \(satir.yeniSinif ?? "Mezun")")
                        .foregroundStyle(satir.yeniSinif == nil ? KitapTema.vurgu : .primary)
                }
                if previewLimit < degisen.count { Button("Daha fazla göster (\(previewLimit)/\(degisen.count))") { previewLimit += 200 } }
            }
            Section {
                Button("Sınıf Atlatmayı Uygula", systemImage: "arrow.up.forward.circle.fill") { onayIsteniyor = true }
                    .buttonStyle(.kitapDolu(KitapTema.ana))
                    .disabled(degisen.isEmpty)
            } footer: {
                Text("Uygulamadan önce Ayarlar › Veri Güvenliği'nden arşiv almanız önerilir.")
            }
        }
        .navigationTitle("Sınıf Atlatma")
        .confirmationDialog("\(degisen.count) öğrencinin sınıfı değişecek. Emin misiniz?", isPresented: $onayIsteniyor, titleVisibility: .visible) {
            Button("Uygula") {
                Task {
                    guard await YetkiDurumu.shared.yoneticiOl() else { error = YetkiDurumu.shared.hata ?? "Yönetici kimliği gerekir."; return }
                    do {
                        let (atlayan, mezun) = try SinifAtlatma.uygulaVerified(plan, context: modelContext)
                        sonuc = "\(atlayan) öğrenci üst sınıfa geçti, \(mezun) öğrenci mezun oldu."
                    } catch { self.error = error.localizedDescription }
                }
            }
            Button("Vazgeç", role: .cancel) { }
        }
        .alert("Sınıf atlatma kaydedilemedi", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("Tamam") { error = nil } } message: { Text(error ?? "") }
        .alert("Sınıf Atlatma", isPresented: Binding(get: { sonuc != nil }, set: { if !$0 { sonuc = nil; dismiss() } })) {
            Button("Tamam", role: .cancel) { }
        } message: {
            Text(sonuc ?? "")
        }
    }
}

// MARK: - CSV sütun eşleme

struct OgrenciCSVEslestirmeSayfasi: View {
    let satirlar: [[String]]
    let onBitti: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var adSutunu = 0
    @State private var noSutunu = -1
    @State private var sinifSutunu = -1
    @State private var baslikVar = true
    @State private var error: String?
    @State private var importing = false
    @State private var previewLimit = 20
    @State private var discard = false
    @State private var preview: StudentImportPreview?
    @State private var resolutions: [Int: StudentImportResolution] = [:]
    @State private var yalnizKararsiz = false
    private let initialMapping: String
    private var mapping: String { "\(adSutunu)|\(noSutunu)|\(sinifSutunu)|\(baslikVar)" }
    private var dirty: Bool { mapping != initialMapping }
    private var validMapping: Bool {
        let chosen = [adSutunu, noSutunu, sinifSutunu].filter { $0 >= 0 }
        return Set(chosen).count == chosen.count
    }

    init(satirlar: [[String]], onBitti: @escaping (Int) -> Void) {
        self.satirlar = satirlar
        self.onBitti = onBitti
        let tahmin = OgrenciCSVEslestirme.tahmin(satirlar.first ?? [])
        _adSutunu = State(initialValue: tahmin.ad ?? 0)
        _noSutunu = State(initialValue: tahmin.no ?? -1)
        _sinifSutunu = State(initialValue: tahmin.sinif ?? -1)
        _baslikVar = State(initialValue: tahmin.ad != nil)
        initialMapping = "\(tahmin.ad ?? 0)|\(tahmin.no ?? -1)|\(tahmin.sinif ?? -1)|\(tahmin.ad != nil)"
    }

    private var sutunlar: [(Int, String)] {
        let ilk = satirlar.first ?? []
        return ilk.indices.map { i in (i, baslikVar ? (ilk[i].isEmpty ? "Sütun \(i + 1)" : ilk[i]) : "Sütun \(i + 1) (ör. \(ilk[i]))") }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Sütunlar") {
                    Toggle("İlk satır başlık", isOn: $baslikVar)
                    Picker("Ad Soyad", selection: $adSutunu) {
                        ForEach(sutunlar, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    Picker("Numara", selection: $noSutunu) {
                        Text("Yok").tag(-1)
                        ForEach(sutunlar, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    Picker("Sınıf", selection: $sinifSutunu) {
                        Text("Yok").tag(-1)
                        ForEach(sutunlar, id: \.0) { Text($0.1).tag($0.0) }
                    }
                }
                if let preview, !(preview.conflicts.isEmpty && preview.autoUpdates.isEmpty) {
                    Section {
                        Toggle("Yalnız kararsızları göster", isOn: $yalnizKararsiz).frame(minHeight: 44)
                            .accessibilityIdentifier("import.onlyUndecided")
                        Menu {
                            Button("Tümünde kimliği güncelle") { topluKarar(.guncelle, preview) }
                            Button("Tümünü yeni ekle") { topluKarar(.yeni, preview) }
                            Button("Tümünü atla") { topluKarar(.atla, preview) }
                            Button("Önerilene dön", role: .destructive) { resolutions = [:] }
                        } label: { Label("Eşleşen satırlara toplu karar", systemImage: "checklist") }
                        .frame(minHeight: 44).accessibilityIdentifier("import.bulk")
                    } header: { Text("Toplu karar") } footer: {
                        Text("Aynı okul numarası tek öğrenciye uyuyorsa kimlik korunur ve ad/sınıf güncellenir; yalnız belirsiz satırlar sizden karar bekler.")
                    }
                }
                if let preview {
                    Section("Önizleme (\(preview.rows.count) satır · \(preview.errors.count) hatalı · \(preview.autoUpdates.count) güncelleme · \(preview.conflicts.count) kimlik seçimi)") {
                        ForEach(preview.rows.filter { !yalnizKararsiz || ($0.requiresDecision && !$0.unchanged && resolutions[$0.line] == nil) }.prefix(previewLimit)) { row in
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Satır \(row.line): \(row.student?.name ?? "Aktarılmayacak satır")").font(.headline)
                                if let student = row.student {
                                    Text([student.number, student.className].filter { !$0.isEmpty }.joined(separator: " · ")).font(.subheadline)
                                }
                                if let issue = row.issue { Label(issue, systemImage: row.student == nil ? "exclamationmark.triangle" : "person.crop.circle.badge.questionmark").font(.footnote).fixedSize(horizontal: false, vertical: true) }
                                if (row.requiresDecision || row.defaultResolution != nil) && !row.unchanged {
                                    Menu {
                                        Button("Satırı atla") { resolutions[row.line] = .skip }
                                        Button("Ayrı kimlikle yeni öğrenci ekle") { resolutions[row.line] = .newStudent }
                                        ForEach(row.candidates) { candidate in
                                            Button("\(candidate.name) · No \(candidate.number) · \(candidate.className) kimliğini güncelle") { resolutions[row.line] = .update(candidate.id) }
                                        }
                                    } label: { Label(resolutionLabel(row), systemImage: "person.badge.key.fill") }
                                    .frame(minHeight: 44)
                                }
                            }.padding(.vertical, 4)
                        }
                        if previewLimit < preview.rows.count { Button("Daha fazla göster (\(previewLimit)/\(preview.rows.count))") { previewLimit += 50 } }
                    }
                }
                if !validMapping { Section { Label("Her alan için farklı bir CSV sütunu seçin.", systemImage: "exclamationmark.triangle").foregroundStyle(.red) } }
                if let error { Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) } }
            }
            .navigationTitle("Öğrenci İçe Aktar")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { if dirty { discard = true } else { dismiss() } } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(importing ? "Aktarılıyor…" : "İçe Aktar") {
                        Task {
                            guard await YetkiDurumu.shared.yoneticiOl() else { error = YetkiDurumu.shared.hata ?? "Yönetici kimliği gerekir."; return }
                            importing = true
                            defer { importing = false }
                            do {
                                guard let preview else { throw SchoolLibraryService.OperationError(message: "Önizleme hazır değil.") }
                                let result = try StudentImportService.apply(preview, resolutions: resolutions, context: modelContext)
                                onBitti(result.added + result.updated); dismiss()
                            }
                            catch { self.error = error.localizedDescription }
                        }
                    }
                    .disabled(preview?.rows.contains(where: { $0.student != nil && !$0.unchanged }) != true || !validMapping || importing ||
                              (preview?.conflicts.contains(where: { resolutions[$0.line] == nil }) ?? true))
                }
            }
            .interactiveDismissDisabled(dirty || importing)
            .onAppear { refreshPreview() }
            .onChange(of: mapping) { _, _ in resolutions = [:]; refreshPreview() }
            .confirmationDialog("Sütun eşlemesi kaydedilmeden kapatılsın mı?", isPresented: $discard, titleVisibility: .visible) {
                Button("Kapat", role: .destructive) { dismiss() }
                Button("Devam et", role: .cancel) { }
            }
        }
    }

    private func refreshPreview() {
        do {
            preview = try StudentImportService.preview(rows: satirlar,
                mapping: StudentImportMapping(nameColumn: adSutunu, numberColumn: noSutunu < 0 ? nil : noSutunu,
                                              classColumn: sinifSutunu < 0 ? nil : sinifSutunu, hasHeader: baslikVar))
            error = nil
        } catch { preview = nil; self.error = error.localizedDescription }
    }
    private enum TopluKarar { case guncelle, yeni, atla }

    /// Aday bulunan satırlara tek seferde karar uygular; aynı kimliğe iki satır eşlenmez, belirsiz satır boş kalır.
    private func topluKarar(_ karar: TopluKarar, _ preview: StudentImportPreview) {
        var kullanilan = Set<UUID>()
        for row in preview.rows where row.student != nil && !row.unchanged && !row.candidates.isEmpty {
            switch karar {
            case .guncelle:
                if row.candidates.count == 1, let aday = row.candidates.first, kullanilan.insert(aday.id).inserted { resolutions[row.line] = .update(aday.id) }
            case .yeni: resolutions[row.line] = .newStudent
            case .atla: resolutions[row.line] = .skip
            }
        }
    }

    private func resolutionLabel(_ row: StudentImportRow) -> String {
        switch resolutions[row.line] {
        case .skip: return "Atlanacak"
        case .newStudent: return "Ayrı öğrenci eklenecek"
        case .update(let id): return "Kimlik korunarak güncellenecek: " + (row.candidates.first { $0.id == id }?.name ?? "")
        case nil: return row.defaultResolution != nil ? "Önerilen: kimlik korunarak güncellenecek" : "Kimlik için karar verin"
        }
    }
}
