import SwiftUI
import UniformTypeIdentifiers
import QuickLook

@MainActor
enum OfisDonusturucu {
    static let hedefler = ["docx", "xlsx", "pptx", "pdf", "csv", "md", "txt", "json"]
    /// Aktarılan en çok satır; aşılırsa `kesintiNotu` kullanıcıya söyler (girdi zaten BelgeOkuyucu'da 50.000 karakterle sınırlı).
    nonisolated static let satirSiniri = 2_000

    /// Yalnız BelgeOkuyucu'nun eklediği işaretler ("[Sayfa 3]", "[word/document.xml]"); kullanıcının "[Not]" satırı içeriktir.
    nonisolated static func okuyucuIsaretiMi(_ s: String) -> Bool {
        s.hasPrefix("[") && s.hasSuffix("]") && (s.hasPrefix("[Sayfa ") || s.hasSuffix(".xml]"))
    }

    static func tumSatirlar(_ belge: OkunanBelge) -> [String] {
        belge.metin.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !okuyucuIsaretiMi($0) }
    }

    /// Satır sınırı aşıldıysa kullanıcıya gösterilecek not; aşılmadıysa boş.
    static func kesintiNotu(_ belge: OkunanBelge) -> String { kesintiNotu(satirSayisi: tumSatirlar(belge).count) }

    /// Satır sayısı zaten hesaplandıysa metni ikinci kez bölmeden not üretir.
    nonisolated static func kesintiNotu(satirSayisi n: Int) -> String {
        n > satirSiniri ? "\(n) satırın ilk \(satirSiniri) satırı aktarıldı; kalanı yeni dosyada yok." : ""
    }

    static func icerik(_ belge: OkunanBelge) -> OfisOlusturucu.Icerik { icerik(belge, satirlar: tumSatirlar(belge)) }

    /// `tum`: `tumSatirlar(belge)` sonucu (ekran bir kez hesaplayıp hem içerik hem kesinti notu için kullanır).
    static func icerik(_ belge: OkunanBelge, satirlar tum: [String]) -> OfisOlusturucu.Icerik {
        let baslik = URL(fileURLWithPath: belge.ad).deletingPathExtension().lastPathComponent
        let satirlar = Array(tum.prefix(satirSiniri))
        let paragraflar = satirlar.isEmpty ? [belge.metin] : satirlar
        let tablo = ExcelOlusturucu.Tablo(sutunlar: ["Sıra", "İçerik"], satirlar: paragraflar.enumerated().map { [String($0.offset + 1), $0.element] })
        let slaytlar = stride(from: 0, to: paragraflar.count, by: 8).map { bas in
            (baslik: bas == 0 ? baslik : "\(baslik) · \(bas / 8 + 1)", maddeler: Array(paragraflar[bas..<min(bas + 8, paragraflar.count)]))
        }
        return .init(baslik: baslik, paragraflar: paragraflar, tablo: tablo, slaytlar: slaytlar)
    }

    /// PDF dahil bütün biçimler ana aktör dışında üretilir (docx/xlsx/pptx/metin: dize + ZIP; pdf: UIGraphicsPDFRenderer).
    nonisolated static func arkaPlanVerisi(_ i: OfisOlusturucu.Icerik, hedef: String) throws -> Data {
        switch hedef {
        case "docx": return OfisOlusturucu.docx(i)
        case "xlsx":
            guard let t = i.tablo else { throw IndirmeHatasi.metin("Excel'e aktarılacak satır yok.") }
            return ExcelOlusturucu.xlsx(t)
        case "pptx": return OfisOlusturucu.pptx(i)
        case "pdf": return OfisOlusturucu.pdf(i)
        default: return try OfisOlusturucu.metin(i, tur: hedef)
        }
    }

    static func donustur(_ belge: OkunanBelge, hedef: String) throws -> URL {
        guard hedefler.contains(hedef) else { throw IndirmeHatasi.metin("Desteklenmeyen hedef biçimi.") }
        let data = try arkaPlanVerisi(icerik(belge), hedef: hedef)
        return try kaydet(data, belge: belge, hedef: hedef)
    }

    /// Ekranın yolu: her biçim (PDF dahil) arka planda üretilir; arayüz donmaz, "Dönüştürülüyor…" görünür.
    /// Satırlar bir kez hesaplanır (içerik + kesinti notu). Dönüş: dosya + kesinti notu (boş olabilir).
    static func donusturNotlu(_ belge: OkunanBelge, hedef: String) async throws -> (url: URL, not: String) {
        guard hedefler.contains(hedef) else { throw IndirmeHatasi.metin("Desteklenmeyen hedef biçimi.") }
        let tum = tumSatirlar(belge)
        let i = icerik(belge, satirlar: tum)
        let data = try await Task.detached(priority: .userInitiated) { try OfisDonusturucu.arkaPlanVerisi(i, hedef: hedef) }.value
        let url = try kaydet(data, belge: belge, hedef: hedef)
        return (url, kesintiNotu(satirSayisi: tum.count))
    }

    /// Dosyayı İndirmeler'e yazar ve listeye ekler (ana aktörde).
    static func kaydet(_ data: Data, belge: OkunanBelge, hedef: String) throws -> URL {
        let kok = IndirmeYoneticisi.dosyaAdi(URL(fileURLWithPath: belge.ad).deletingPathExtension().lastPathComponent)
        let gorunen = "\(kok)-Dönüştürüldü.\(hedef)"
        let url = IndirmeYoneticisi.klasor.appending(path: UUID().uuidString + "-" + gorunen)
        try data.write(to: url, options: .atomic)
        IndirmeYoneticisi.ortak.yerelDosyaEkle(url: url, gorunenAd: gorunen)
        return url
    }
}

struct OfisDonusturmeEkrani: View {
    @Environment(\.dismiss) private var kapat
    @State private var dosyaSec = false
    @State private var belge: OkunanBelge?
    @State private var hedef = "pdf"
    @State private var calisiyor = false
    @State private var durum = ""
    @State private var hata: String?
    @State private var onizleme: URL?
    /// Kalıcı sonuç: önizleme kapanınca (QuickLook bağlamayı nil yapar) "Dosyayı aç" / "Kaydet" düğmeleri kaybolmasın.
    @State private var sonucURL: URL?
    @State private var uyari = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Kaynak dosya") {
                    Button { dosyaSec = true } label: { Label(belge?.ad ?? "Dosya seç", systemImage: "doc.badge.plus") }
                    if let belge, !belge.not.isEmpty { Text(belge.not).font(.footnote).foregroundStyle(.secondary) }
                }
                Section("Hedef biçim") {
                    Picker("Biçim", selection: $hedef) {
                        Text("Word (.docx)").tag("docx")
                        Text("Excel (.xlsx)").tag("xlsx")
                        Text("PowerPoint (.pptx)").tag("pptx")
                        Text("PDF (.pdf)").tag("pdf")
                        Text("CSV (.csv)").tag("csv")
                        Text("Markdown (.md)").tag("md")
                        Text("Metin (.txt)").tag("txt")
                        Text("JSON (.json)").tag("json")
                    }
                    Button(calisiyor ? "Dönüştürülüyor…" : "Yeni dosyaya dönüştür") { donustur() }
                        .disabled(belge == nil || calisiyor)
                        .buttonStyle(.borderedProminent)
                }
                if !durum.isEmpty {
                    Section("Sonuç") {
                        if uyari.isEmpty {
                            Label(durum, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        } else {
                            Label(durum, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            Text(uyari).font(.footnote).foregroundStyle(.orange)
                        }
                        if let sonucURL { Button("Dosyayı aç") { onizleme = sonucURL }; ShareLink(item: sonucURL) { Label("Kaydet / paylaş", systemImage: "square.and.arrow.up") } }
                    }
                }
                if let hata { Text(hata).foregroundStyle(.red).font(.footnote) }
                Section {
                    Text("Dönüşüm metin içeriğini taşır (en çok \(OfisDonusturucu.satirSiniri) satır; PDF'te ilk 20 sayfa okunur); özgün dosyayı değiştirmez. Word/PDF/PowerPoint → Excel dönüşümünde her paragraf ayrı satıra yazılır. Excel → Word/PDF/PowerPoint dönüşümünde okunabilen hücre metinleri belge içeriğine çevrilir. Karmaşık sayfa düzeni, animasyon, makro, formül ve özgün yazı tipi görünümü birebir taşınmayabilir.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Dosya dönüştür")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Tamam") { kapat() } } }
            .fileImporter(isPresented: $dosyaSec, allowedContentTypes: BelgeOkuyucu.desteklenenTurler) { sonuc in
                switch sonuc {
                case .success(let url):
                    calisiyor = true; hata = nil; durum = ""; sonucURL = nil; uyari = ""
                    Task {
                        do { belge = try await Task.detached { try BelgeOkuyucu.oku(url) }.value }
                        catch { hata = error.localizedDescription }
                        calisiyor = false
                    }
                case .failure(let error): hata = error.localizedDescription
                }
            }
            .quickLookPreview($onizleme)
        }
    }

    private func donustur() {
        guard let belge, !calisiyor else { return }
        calisiyor = true; hata = nil; durum = ""; sonucURL = nil; uyari = ""
        let hedef = hedef
        Task {
            defer { calisiyor = false }
            do {
                let (url, not) = try await OfisDonusturucu.donusturNotlu(belge, hedef: hedef)
                sonucURL = url; onizleme = url
                uyari = not
                durum = String(url.lastPathComponent.dropFirst(37))   // "UUID-" öneki (36 + 1)
            } catch { hata = error.localizedDescription }
        }
    }
}
