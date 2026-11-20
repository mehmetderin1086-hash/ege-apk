// Ekleme oturumu: kayıt günlüğü, geri alma, oturum diski ve kayıttan sonraki şerit.
// ContentView'dan (P8) taşındı; davranış değişmedi.
import SwiftUI
import SwiftData
import PhotosUI
@preconcurrency import Vision
import PDFKit
import ImageIO
import UniformTypeIdentifiers
import CoreImage
#if os(iOS)
import UIKit
import VisionKit
#endif

extension ContentView {
    // MARK: - Ekleme oturumu (geri alma için)

    func beginAddSession() {
        guard acceptsActiveCatalogResult() else { return }
        lastSessionInserted = []
        lastSessionMerged = [:]
        scanSession = ScanSession(kind: .photo, title: "Kitap ekleme")
        persistScanSession()
    }

    /// Oturum durumunu hemen günceller (bellekteki `scanSession` ve Son Eklemeler listesi); yalnız DİSK yazmasını
    /// 400 ms erteler: seri taramada her okutma ve taslak değişikliği ayrı bir yazma başlatmasın.
    /// Durum güncellemesi ertelenmez; açık bir sheet'in altında gecikmeli @State değişimi sheet'i kapatabiliyordu.
    /// Uygulama kapanırken ya da ekran kapanırken `persistScanSessionNow` çağrılır.
    func persistScanSession() {
        guard let session = guncelOturum() else { return }
        scanSessionKaydiGorevi?.cancel()
        scanSessionKaydiGorevi = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            diskeYaz(session)
        }
    }

    /// Beklemeden yazar: kodlama ve disk yazması arka plan kuyruğunda yürür, hata ana iş parçacığına döner.
    func persistScanSessionNow() {
        scanSessionKaydiGorevi?.cancel()
        scanSessionKaydiGorevi = nil
        guard let session = guncelOturum() else { return }
        diskeYaz(session)
    }

    private func diskeYaz(_ session: ScanSession) {
        let hataBildir: @Sendable (Error) -> Void = { hata in
            Task { @MainActor in recognitionError = "Tarama oturumu saklanamadı: \(hata.localizedDescription)" }
        }
        ScanSessionStore.saveInBackground(session, onFailure: hataBildir)
    }

    /// Güncel taslaklar, günlük ve bekleyen ISBN'lerle oturumu kurar, bellekteki durumu günceller.
    private func guncelOturum() -> ScanSession? {
        guard acceptsActiveCatalogResult() else { return nil }
        guard var session = scanSession else { return nil }
        let completed = Set(session.savedOperationIDs ?? [])
        var pending = bulkPendingBooks + (batchDrafts + (draft.map { [$0] } ?? [])).map { book(from: $0) }
        pending = pending.filter { !completed.contains($0.id) }
        var seen = Set<UUID>()
        session.pendingBooks = pending.filter { seen.insert($0.id).inserted }
        session.insertedIDs = lastSessionInserted
        session.mergedCopies = lastSessionMerged
        session.pendingISBNs = tarama.bekleyenISBNler
        session.seriAtama = session.pendingISBNs == nil ? nil : SeriAtama(
            location: scanAssignment.location, cabinet: scanAssignment.cabinet, shelf: scanAssignment.shelf,
            category: scanAssignment.category, otoKayit: autoSaveScans)
        scanSession = session
        // Listeyi diskten yeniden okumak yerine bellekteki oturumla güncelle (fotoğraflar tekrar yüklenmez)
        if let index = recentScanSessions.firstIndex(where: { $0.id == session.id }) {
            recentScanSessions[index] = session
        } else {
            recentScanSessions.insert(session, at: 0)
        }
        return session
    }

    func refreshScanSessions() {
        do {
            try requireActiveCatalog()
            ScanSessionStore.flush()
            recentScanSessions = try ScanSessionStore.allVerified(hydratePhotos: false).map { session in
                let recovered = try ScanSessionStore.reconciled(session, context: modelContext)
                if recovered != session { try ScanSessionStore.save(recovered) }
                return recovered
            }
        } catch { recognitionError = "Kaydedilen oturumlar okunamadı; dosyalar korundu: \(error.localizedDescription)" }
    }

    var lastSessionCount: Int {
        lastSessionInserted.count + lastSessionMerged.values.reduce(0, +)
    }

    func recordSession(_ outcome: SaveOutcome) {
        guard acceptsActiveCatalogResult() else { return }
        switch outcome {
        case .inserted(let id):
            lastSessionInserted.append(id)
        case .merged(let id, let added):
            lastSessionMerged[id, default: 0] += added
        case .updated, .failed:
            break
        }
        if outcome.succeeded, let operationID = lastSavedOperationID, var session = scanSession {
            var ids = session.savedOperationIDs ?? []
            if !ids.contains(operationID) { ids.append(operationID) }
            session.savedOperationIDs = ids
            scanSession = session
        }
        lastSavedOperationID = nil
        if outcome.succeeded { persistScanSession() }
    }

    func undoLastSession() {
        guard acceptsActiveCatalogResult() else { return }
        let count = lastSessionCount
        do {
            try CatalogSaveEngine.undo(insertedIDs: lastSessionInserted, mergedCopies: lastSessionMerged,
                                       catalog: catalogBooks, context: modelContext, operationIDs: scanSession?.savedOperationIDs ?? [])
            if let id = scanSession?.id { try ScanSessionStore.remove(id) }
            lastSessionInserted = []
            lastSessionMerged = [:]
            scanSession = nil
            // Son işlem bu oturumla birlikte geri alındı: şerit ve tek kayıt geri alması ikinci kez çalışmaz
            lastScanAction = nil
            lastScanOperationID = nil
            sonEkleme = nil
            sonEklemeEylemi = nil
            recentScanSessions = ScanSessionStore.all()
            CatalogBackup.saveLight(catalogBooks)
            bulkMessage = "\(count) ekleme geri alındı."
        } catch { recognitionError = "Geri alınamadı: \(error.localizedDescription)" }
    }

    /// Seri taramada son okumayı geri alır.
    func undoLastScan() {
        guard acceptsActiveCatalogResult() else { return }
        guard let action = lastScanAction else { return }
        do {
            switch action {
            case .saved(let id):
                try CatalogSaveEngine.undo(insertedIDs: [id], mergedCopies: [:], catalog: catalogBooks, context: modelContext,
                    operationIDs: lastScanOperationID.map { [$0] } ?? [])
                lastSessionInserted.removeAll { $0 == id }
                depotIndex = depotIndex.filter { $0.value.id != id }
            case .queued(let id): batchDrafts.removeAll { $0.id == id }; persistPendingQueue()
            case .merged(let id, let added):
                try CatalogSaveEngine.undo(insertedIDs: [], mergedCopies: [id: added], catalog: catalogBooks, context: modelContext,
                    operationIDs: lastScanOperationID.map { [$0] } ?? [])
                // Sıfıra inen kayıt günlükten çıkar: oturum kartında boş "Eklemeleri Geri Al" kalmasın
                let kalan = (lastSessionMerged[id] ?? added) - added
                lastSessionMerged[id] = kalan > 0 ? kalan : nil
            }
            if let operationID = lastScanOperationID { scanSession?.savedOperationIDs?.removeAll { $0 == operationID } }
            lastScanOperationID = nil
            persistScanSession()
            serialScanCount = max(0, serialScanCount - 1)
            appendSerialLog("↩︎ Son okuma geri alındı")
            lastScanAction = nil
        } catch { recognitionError = "Geri alınamadı: \(error.localizedDescription)" }
    }

    func appendSerialLog(_ line: String) {
        tarama.gunlugeEkle(line)
        // Kamera ekranına bakmayan kullanıcı her okutmanın sonucunu duyar
        AccessibilityNotification.Announcement(line).post()
    }

    // MARK: - Kayıttan sonraki şerit

    /// Yeni kayıtta ya da nüsha eklemede alttaki şeridi gösterir; geri alma bu tek kayda bağlanır.
    func sonEklemeyiGoster(_ outcome: SaveOutcome, kitapAdi: String) {
        let tur: SonEklemeSeridi.Tur
        var kayitAni: Book?
        switch outcome {
        case .inserted(let id):
            lastScanAction = .saved(id)
            tur = .yeniKayit
            kayitAni = guncelKayit(id)
        case .merged(let id, let added) where added > 0:
            lastScanAction = .merged(id, added: added)
            tur = .nusha(added)
        default:
            return
        }
        let serit = SonEklemeSeridi(kitapAdi: kitapAdi, tur: tur, islemKimligi: lastScanOperationID,
                                    oturumKimligi: scanSession?.id, kayitAni: kayitAni)
        sonEklemeEylemi = lastScanAction
        sonEkleme = serit
        AccessibilityNotification.Announcement(serit.metin).post()
    }

    /// Onay kuyruğu diske yazılamadığında: taslaklar bellekte durur, "Yeniden dene" yazmayı tekrarlar.
    func kuyrukHataSeridi(_ mesaj: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(mesaj, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("add.queueFailed")
            Button("Yeniden dene") { persistPendingQueue() }
                .buttonStyle(.kitapTonlu())
                .accessibilityIdentifier("add.queueFailed.retry")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    @ViewBuilder
    func sonEklemeSeridi(_ serit: SonEklemeSeridi) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label {
                    Text(serit.metin)
                } icon: {
                    Image(systemName: serit.geriAlinabilir ? "checkmark.circle.fill" : "arrow.uturn.backward.circle")
                        .accessibilityHidden(true)
                }
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("add.lastSaved")
                Button { sonEkleme = nil } label: {
                    Label("Bildirimi kapat", systemImage: "xmark").labelStyle(.iconOnly).frame(width: 44, height: 44)
                }
                .accessibilityIdentifier("add.lastSaved.close")
            }
            // Dar ekranda ve büyük yazıda düğmeler alt alta iner
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { sonEklemeDugmeleri(serit) }
                VStack(alignment: .leading, spacing: 8) { sonEklemeDugmeleri(serit) }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    @ViewBuilder
    func sonEklemeDugmeleri(_ serit: SonEklemeSeridi) -> some View {
        if serit.geriAlinabilir {
            Button { sonEklemeyiGeriAl() } label: {
                Label("Geri al", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(.kitapTonlu(KitapTema.vurgu))
            .accessibilityIdentifier("add.lastSaved.undo")
        }
#if os(iOS)
        Button {
            sonEkleme = nil
            startBarcodeScan(serial: false)
        } label: {
            Label("Sonrakini okut", systemImage: "barcode.viewfinder")
        }
        .buttonStyle(.kitapTonlu())
        .accessibilityIdentifier("add.lastSaved.next")
#endif
    }

    /// Kaydın veritabanındaki güncel hâli (`catalogBooks` sorgusu kayıttan hemen sonra henüz yenilenmemiş olabilir).
    func guncelKayit(_ id: UUID) -> Book? {
        (try? modelContext.fetch(FetchDescriptor<CatalogBook>(predicate: #Predicate { $0.id == id })).first)?.book
    }

    /// Şeritteki "Geri al": yalnız bu kaydı geri alır (`undoLastScan`). Geri alma yönetici ister;
    /// rol kilidi açıksa önce kimlik sorulur.
    func sonEklemeyiGeriAl(_ istenen: SonEklemeSeridi? = nil, degisiklikOnaylandi: Bool = false) {
        guard let serit = istenen ?? sonEkleme else { return }
        Task { @MainActor in
            guard await YetkiDurumu.shared.yoneticiOl(neden: "Eklemeyi geri almak için kimliğinizi doğrulayın") else {
                recognitionError = YetkiDurumu.shared.hata ?? "Eklemeyi geri almak için yönetici kimliği gerekir."
                return
            }
            guard acceptsActiveCatalogResult() else { return }
            let hedef: UUID?
            switch sonEklemeEylemi {
            case .saved(let id), .merged(let id, _): hedef = id
            case .queued, .none: hedef = nil
            }
            // Bu arada başka bir kayıt ya da işlem son işlem olduysa, oturum değiştiyse ya da aynı ekleme
            // Son Eklemeler'den geri alındıysa (makbuz silinmiş) yanlış kitap ya da ikinci kez geri alınmaz
            guard sonEkleme == serit, let hedef, lastScanAction == sonEklemeEylemi,
                  lastScanOperationID == serit.islemKimligi, serit.oturumKimligi == scanSession?.id else {
                sonEkleme = nil
                recognitionError = "Bu ekleme artık buradan geri alınamaz; Son Eklemeler’deki “Eklemeleri Geri Al” düğmesini kullanın."
                return
            }
            guard serit.makbuzDuruyor(hedef: hedef, context: modelContext) else {
                sonEkleme = nil
                recognitionError = "Bu ekleme zaten geri alınmış; katalogdaki güncel kaydı kontrol edin."
                return
            }
            // Yeni kayıt sonradan düzenlendiyse geri alma bu bilgileri de kalıcı siler: önce sorulur
            if !degisiklikOnaylandi, serit.sonradanDegisti(guncelKayit(hedef)) {
                degisenEklemeOnayi = serit
                return
            }
            undoLastScan()
            // Geri alma başarısızsa (ör. kitap ödünç verildi) uyarı çıkar, şerit kalır
            guard lastScanAction == nil else { return }
            var geriAlinan = serit
            geriAlinan.tur = .geriAlindi
            sonEklemeEylemi = nil
            sonEkleme = geriAlinan
            AccessibilityNotification.Announcement(geriAlinan.metin).post()
        }
    }
}
