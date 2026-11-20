import SwiftUI
import UniformTypeIdentifiers
import QuickLook
import Observation
import ZIPFoundation
import Unrar

@MainActor @Observable
final class ArsivMerkezi {
    static let ortak = ArsivMerkezi()
    var ekranAcik = false
}

/// Ana aktöre bağlı değil: büyük arşiv açma/oluşturma arka planda (Task.detached) çalışır, arayüz donmaz.
nonisolated enum ArsivIslemleri {
    nonisolated enum Hata: LocalizedError {
        case cokBuyuk, cokFazla, guvensizYol, bicim, bos, tasinamadi
        var errorDescription: String? {
            switch self {
            case .tasinamadi: "Çıkarılan dosyalar İndirmeler'e taşınamadı; arşivi yeniden açmayı dene."
            case .cokBuyuk: "Arşivin açılmış toplam boyutu 1 GB sınırını aşıyor."
            case .cokFazla: "Arşiv 1.000 dosya sınırını aşıyor."
            case .guvensizYol: "Arşiv güvenli olmayan bir dosya yolu içeriyor."
            case .bicim: "Yalnız ZIP ve RAR arşivleri açılabilir."
            case .bos: "Arşivlenecek en az bir dosya seç."
            }
        }
    }
    static func guvenli(_ path: String) -> Bool {
        let p = path.replacingOccurrences(of: "\\", with: "/")
        return !p.hasPrefix("/") && !p.split(separator: "/").contains("..") && !p.contains("\0")
    }

    /// İndirmeler klasörü (IndirmeYoneticisi.klasor ana aktöre bağlı; burada nonisolated yol kullanılır).
    static var indirmeler: URL { URL(fileURLWithPath: IndirmeYoneticisi.klasorYolu, isDirectory: true) }

    static func zipOlustur(_ urls: [URL], ad: String) throws -> URL {
        guard !urls.isEmpty else { throw Hata.bos }
        guard urls.count <= 100 else { throw Hata.cokFazla }
        let gorunen = IndirmeYoneticisi.dosyaAdi(ad.lowercased().hasSuffix(".zip") ? ad : ad + ".zip")
        let hedef = indirmeler.appending(path: UUID().uuidString + "-" + gorunen)
        let archive = try ZIPFoundation.Archive(url: hedef, accessMode: .create)
        do {
            var kullanilan = Set<String>()
            for url in urls {
                let erisim = url.startAccessingSecurityScopedResource(); defer { if erisim { url.stopAccessingSecurityScopedResource() } }
                let deger = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                guard deger.isRegularFile == true else { continue }
                guard (deger.fileSize ?? 0) <= 500 * 1024 * 1024 else { throw Hata.cokBuyuk }
                var dosyaAdi = IndirmeYoneticisi.dosyaAdi(url.lastPathComponent), n = 2
                while kullanilan.contains(dosyaAdi) {
                    let u = URL(fileURLWithPath: dosyaAdi), kok = u.deletingPathExtension().lastPathComponent, ext = u.pathExtension
                    dosyaAdi = kok + "-\(n)" + (ext.isEmpty ? "" : "." + ext); n += 1
                }
                kullanilan.insert(dosyaAdi)
                try archive.addEntry(with: dosyaAdi, fileURL: url, compressionMethod: .deflate)
            }
            guard !kullanilan.isEmpty else { throw Hata.bos }
        } catch {
            try? FileManager.default.removeItem(at: hedef)   // yarım/boş .zip kalmasın
            throw error
        }
        return hedef
    }

    static func ac(_ url: URL, parola: String?) throws -> (URL, [URL]) {
        let erisim = url.startAccessingSecurityScopedResource(); defer { if erisim { url.stopAccessingSecurityScopedResource() } }
        let ext = url.pathExtension.lowercased()
        guard ext == "zip" || ext == "rar" else { throw Hata.bicim }
        let ad = IndirmeYoneticisi.dosyaAdi(url.deletingPathExtension().lastPathComponent) + "-Açıldı"
        let kok = indirmeler.appending(path: UUID().uuidString + "-" + ad, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: kok, withIntermediateDirectories: true)
        var sonuc: [URL] = [], toplam: UInt64 = 0
        do {
            if ext == "zip" {
                let archive = try ZIPFoundation.Archive(url: url, accessMode: .read)
                let entries = Array(archive)
                guard entries.count <= 1_000 else { throw Hata.cokFazla }
                for entry in entries {
                    guard guvenli(entry.path), entry.type != .symlink else { throw Hata.guvensizYol }
                    toplam += entry.uncompressedSize; guard toplam <= 1_000_000_000 else { throw Hata.cokBuyuk }
                    let hedef = kok.appending(path: entry.path)
                    if entry.type == .directory { try FileManager.default.createDirectory(at: hedef, withIntermediateDirectories: true) }
                    else { try FileManager.default.createDirectory(at: hedef.deletingLastPathComponent(), withIntermediateDirectories: true); _ = try archive.extract(entry, to: hedef); sonuc.append(hedef) }
                }
            } else {
                let archive = try Unrar.Archive(fileURL: url, password: parola?.isEmpty == false ? parola : nil)
                let entries = try archive.entries(); guard entries.count <= 1_000 else { throw Hata.cokFazla }
                for entry in entries {
                    guard guvenli(entry.fileName) else { throw Hata.guvensizYol }
                    toplam += entry.uncompressedSize; guard toplam <= 1_000_000_000 else { throw Hata.cokBuyuk }
                    let hedef = kok.appending(path: entry.fileName)
                    if entry.directory { try FileManager.default.createDirectory(at: hedef, withIntermediateDirectories: true) }
                    else { try FileManager.default.createDirectory(at: hedef.deletingLastPathComponent(), withIntermediateDirectories: true); try rarAkisla(archive, entry, hedef); sonuc.append(hedef) }
                }
            }
            guard !sonuc.isEmpty else { throw Hata.bos }
        } catch {
            try? FileManager.default.removeItem(at: kok)   // yarım açılmış klasör yetim kalmasın
            throw error
        }
        return (kok, sonuc)
    }

    /// RAR girdisini parça parça diske yazar (girdinin tamamı belleğe alınmaz). Unrar geri çağrısı aynı iş parçacığında, eşzamanlı gelir.
    static func rarAkisla(_ archive: Unrar.Archive, _ entry: Unrar.Entry, _ hedef: URL) throws {
        guard FileManager.default.createFile(atPath: hedef.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        let fh = try FileHandle(forWritingTo: hedef)
        defer { try? fh.close() }
        var yazilan: UInt64 = 0
        var yazmaHatasi: (any Error)?
        do {
            try archive.extract(entry) { parca, ilerleme in
                guard yazmaHatasi == nil else { ilerleme.cancel(); return }
                // Yazma hatasında (disk dolu) iptal: geri çağrı -1 döner, unrar girdinin kalanını boşuna açmaz.
                do { try fh.write(contentsOf: parca); yazilan += UInt64(parca.count) } catch { yazmaHatasi = error; ilerleme.cancel() }
            }
        } catch {
            // İptal edilince Unrar anlamsız bir hata fırlatır; kullanıcı asıl yazma hatasını görmeli.
            throw yazmaHatasi ?? error
        }
        if let yazmaHatasi { throw yazmaHatasi }
        guard yazilan == entry.uncompressedSize else { throw CocoaError(.fileReadCorruptFile) }
    }

    /// İndirmeler'e taşınan dosya: yeni konum + arşiv içindeki göreli yol (görünen ad).
    nonisolated struct TasinanDosya: Sendable { let url: URL; let ad: String }

    /// Taşıma sonucu: taşınanlar + taşınamayan dosya sayısı (kullanıcıya söylenir; sessizce düşmez).
    nonisolated struct TasimaSonucu: Sendable { let tasinan: [TasinanDosya]; let kalan: Int }

    /// UUID öneki (37 bayt) eklenince APFS'in 255 bayt ad sınırı aşılmasın (ENAMETOOLONG); uzantı korunur.
    /// `dosyaAdi` karakter sayısıyla kırpar, çok baytlı (CJK/Kiril) adlarda bayt sınırı yine aşılabilirdi.
    static func baytaSigdir(_ ad: String, _ sinir: Int = 218) -> String {
        guard ad.utf8.count > sinir else { return ad }
        let u = URL(fileURLWithPath: ad), ext = u.pathExtension.isEmpty ? "" : "." + u.pathExtension
        guard ext.utf8.count < sinir else { return "Dosya" }
        var kok = ""
        for c in u.deletingPathExtension().lastPathComponent {
            if (kok + String(c) + ext).utf8.count > sinir { break }
            kok.append(c)
        }
        return (kok.isEmpty ? "Dosya" : kok) + ext
    }

    /// Eski imza (testler): yalnız taşınanları döndürür.
    static func indirmelereTasi(_ acilan: (URL, [URL])) -> [TasinanDosya] { indirmelereTasiSayarak(acilan).tasinan }

    /// Çıkarılan dosyaları İndirmeler köküne düz adla taşır (İndirmeler listesi alt klasör kabul etmez) ve çıkarma klasörünü siler.
    /// Özgün arşiv yerinde durur; taşınamayan dosya sayılır ve çağıran kullanıcıya bildirir.
    static func indirmelereTasiSayarak(_ acilan: (URL, [URL])) -> TasimaSonucu {
        let kokYolu = acilan.0.standardizedFileURL.path + "/"
        var sonuc: [TasinanDosya] = [], kalan = 0, gorulen = Set<String>()
        for dosya in acilan.1 {
            let tam = dosya.standardizedFileURL.path
            // RAR'da yinelenen girdi aynı yolu iki kez verir; ikincisi zaten taşınmıştır, hata sayılmaz.
            guard gorulen.insert(tam).inserted else { continue }
            let goreli = tam.hasPrefix(kokYolu) ? String(tam.dropFirst(kokYolu.count)) : dosya.lastPathComponent
            let yeni = indirmeler.appending(path: UUID().uuidString + "-" + baytaSigdir(IndirmeYoneticisi.dosyaAdi(dosya.lastPathComponent)))
            do { try FileManager.default.moveItem(at: dosya, to: yeni); sonuc.append(TasinanDosya(url: yeni, ad: goreli)) }
            catch { kalan += 1 }
        }
        try? FileManager.default.removeItem(at: acilan.0)
        return TasimaSonucu(tasinan: sonuc, kalan: kalan)
    }

    /// Ekranın yolu: aç + taşı; hiçbir dosya taşınamadıysa başarı gibi görünmesin, hata fırlatır.
    static func acipTasi(_ url: URL, parola: String?) throws -> TasimaSonucu {
        let r = indirmelereTasiSayarak(try ac(url, parola: parola))
        guard !r.tasinan.isEmpty else { throw Hata.tasinamadi }
        return r
    }

    /// Kısmi taşımada kırmızı uyarı metni; hepsi taşındıysa nil.
    static func kalanUyarisi(_ kalan: Int) -> String? {
        kalan > 0 ? "\(kalan) dosya İndirmeler'e taşınamadı ve çıkarılmadı; arşivi yeniden açmayı dene." : nil
    }
}

struct ArsivEkrani: View {
    @Environment(\.dismiss) private var kapat
    @State private var arsivSec = false
    @State private var dosyaSec = false
    @State private var zipAdi = "Mehmet-Asistan-Arsiv"
    @State private var parola = ""
    @State private var isleniyor = false
    @State private var hata: String?
    @State private var sonuc = ""
    @State private var dosyalar: [URL] = []
    @State private var onizleme: URL?

    private var arsivTurleri: [UTType] { ["zip", "rar"].compactMap { UTType(filenameExtension: $0) } }
    var body: some View {
        NavigationStack {
            List {
                Section("Arşiv aç") {
                    SecureField("RAR parolası — isteğe bağlı", text: $parola)
                    Button { arsivSec = true } label: { Label("ZIP veya RAR seç ve aç", systemImage: "archivebox") }.disabled(isleniyor)
                }
                Section("ZIP oluştur") {
                    TextField("Arşiv adı", text: $zipAdi)
                    Button { dosyaSec = true } label: { Label("Dosyaları seç ve ZIP oluştur", systemImage: "archivebox.fill") }.disabled(isleniyor)
                    Text("RAR oluşturma, RAR'ın lisanslı ve kapalı sıkıştırma biçimi olması nedeniyle iPhone uygulamasına gömülü değildir. Aynı dosyaları ZIP olarak oluşturabilirsin.").font(.footnote).foregroundStyle(.secondary)
                }
                if isleniyor { ProgressView("İşleniyor…") }
                if let hata { Text(hata).foregroundStyle(.red).font(.footnote) }
                if !sonuc.isEmpty { Section("Sonuç") { Label(sonuc, systemImage: "checkmark.circle.fill").foregroundStyle(.green) } }
                if !dosyalar.isEmpty {
                    Section("Dosyalar · \(dosyalar.count)") {
                        ForEach(dosyalar, id: \.path) { url in
                            // .borderless: satıra dokunmak önizleme ile paylaşımı birlikte tetiklemesin.
                            HStack { Button(String(url.lastPathComponent.dropFirst(37))) { onizleme = url }.lineLimit(1); Spacer(); ShareLink(item: url) { Image(systemName: "square.and.arrow.up") } }
                                .buttonStyle(.borderless)
                        }
                    }
                }
            }
            .navigationTitle("ZIP ve RAR")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Tamam") { kapat() } } }
            .fileImporter(isPresented: $arsivSec, allowedContentTypes: arsivTurleri) { secim in
                guard case .success(let url) = secim else { if case .failure(let e) = secim { hata = e.localizedDescription }; return }
                let p = parola
                isle({ try ArsivIslemleri.acipTasi(url, parola: p) }) { r in
                    // İndirmeler'e kaydedilir: ekran kapanınca da erişilir, oradan silinebilir.
                    // Çıkarılanlar ayrı türle kaydedilir: İndirmeler'de 'Arşivden çıkanlar' bölümünde görünür.
                    IndirmeYoneticisi.ortak.yerelDosyalarEkle(r.tasinan.map { (url: $0.url, gorunenAd: $0.ad) }, tur: IndirmeYoneticisi.arsivTuru)
                    dosyalar = r.tasinan.map(\.url); sonuc = "\(r.tasinan.count) dosya çıkarıldı; İndirmeler'de."
                    // isle başta hata'yı sıfırlar; kısmi taşıma yeşil sonucun yanında kırmızı uyarıyla söylenir.
                    hata = ArsivIslemleri.kalanUyarisi(r.kalan)
                }
            }
            .fileImporter(isPresented: $dosyaSec, allowedContentTypes: [.data], allowsMultipleSelection: true) { secim in
                guard case .success(let urls) = secim else { if case .failure(let e) = secim { hata = e.localizedDescription }; return }
                let ad = zipAdi
                isle({ try ArsivIslemleri.zipOlustur(urls, ad: ad) }) { url in
                    IndirmeYoneticisi.ortak.yerelDosyaEkle(url: url, gorunenAd: String(url.lastPathComponent.dropFirst(37)))
                    dosyalar = [url]; sonuc = "ZIP oluşturuldu."
                }
            }
            .quickLookPreview($onizleme)
        }
    }
    /// Ağır iş arka planda; sonuç ve @State atamaları ana aktörde. Askıya alma noktası olduğu için "İşleniyor…" gerçekten görünür.
    private func isle<T: Sendable>(_ islem: @escaping @Sendable () throws -> T, sonra: @escaping @MainActor (T) -> Void) {
        isleniyor = true; hata = nil; sonuc = ""; dosyalar = []
        Task {
            do {
                let r = try await Task.detached(priority: .userInitiated) { try islem() }.value
                sonra(r)
            } catch { hata = error.localizedDescription }
            isleniyor = false
        }
    }
}
