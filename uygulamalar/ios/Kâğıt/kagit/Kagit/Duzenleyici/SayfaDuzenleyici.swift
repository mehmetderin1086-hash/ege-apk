import CoreTransferable
import KagitKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// Sürükle-bırak ile taşınan sayfa indeksleri.
struct SayfaSurukleme: Codable, Transferable {
    var indeksler: [Int]
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}

/// Sayfalar kipi: küçük resim ızgarasında sıralama, döndürme, silme, çoğaltma, çıkarma ve sayfa ekleme.
/// Her işlem `oturum.degistir` ile geri alınabilir.
struct SayfaDuzenleyici: View {
    let oturum: BelgeOturumu

    @Environment(Kitaplik.self) private var kitaplik
    @Environment(\.horizontalSizeClass) private var boyutSinifi
    @State private var secili: Set<Int> = []
    @State private var secimKipi = false
    @State private var silmeSor = false
    @State private var kaynakSec = false
    @State private var eklemeKonumu = 0
    @State private var hedefIndeks: Int?
    @State private var sonuc: Ileti?

    private var durum: DuzenleyiciDurumu { oturum.duzenleyici }
    private var sayfaSayisi: Int { _ = durum.sayfaSurumu; return oturum.belge?.pageCount ?? 0 }
    private var hucre: CGFloat { boyutSinifi == .regular ? 170 : 110 }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: hucre), spacing: 14)], spacing: 16) {
                    ForEach(0..<sayfaSayisi, id: \.self) { i in sayfaHucresi(i) }
                }
                .padding(14)
            }
            .background(Color(.systemGroupedBackground))
            eylemCubugu
        }
        .confirmationDialog("\(secili.count) sayfa silinsin mi?", isPresented: $silmeSor, titleVisibility: .visible) {
            Button("Sil", role: .destructive) { sil() }
            Button("Vazgeç", role: .cancel) {}
        } message: { Text("İşlem geri alınabilir.") }
        .kaynakSecici(isPresented: $kaynakSec, girdi: .tekPDF) { urller in
            if let u = urller.first { dosyadanEkle(u) }
        }
        .iletiGoster($sonuc)
        .onAppear { if secili.isEmpty { secimKipi = false } }
    }

    // MARK: Izgara

    private func sayfaHucresi(_ i: Int) -> some View {
        let secildi = secili.contains(i)
        return VStack(spacing: 4) {
            SayfaKucukResimHucresi(oturum: oturum, indeks: i, surum: durum.sayfaSurumu)
                .overlay(alignment: .topTrailing) {
                    if secimKipi || secildi {
                        Image(systemName: secildi ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(secildi ? Tema.vurgu : .white)
                            .shadow(radius: 1.5)
                            .padding(5)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(secildi ? Tema.vurgu : (hedefIndeks == i ? Color.accentColor : .clear), lineWidth: 3))
            Text("\(i + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if secimKipi || !secili.isEmpty {
                if secildi { secili.remove(i) } else { secili.insert(i) }
            } else {
                oturum.kip = .oku
                oturum.seciliSayfa = i
                Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    if let s = oturum.belge?.page(at: i) { oturum.pdfView?.go(to: s) }
                }
            }
        }
        .onLongPressGesture { secimKipi = true; secili.insert(i) }
        .draggable(SayfaSurukleme(indeksler: secildi ? secili.sorted() : [i])) {
            SayfaKucukResimHucresi(oturum: oturum, indeks: i, surum: durum.sayfaSurumu).frame(width: 80)
        }
        .dropDestination(for: SayfaSurukleme.self) { ogeler, _ in
            guard let o = ogeler.first else { return false }
            tasi(o.indeksler, oncesine: i)
            return true
        } isTargeted: { hedefte in
            hedefIndeks = hedefte ? i : (hedefIndeks == i ? nil : hedefIndeks)
        }
    }

    // MARK: Alt çubuk

    private var eylemCubugu: some View {
        VStack(spacing: 0) {
            Divider()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    eylem(secimKipi ? "Seçimi bitir" : "Seç", secimKipi ? "checkmark.circle" : "checkmark.circle.badge.plus") {
                        secimKipi.toggle()
                        if !secimKipi { secili = [] }
                    }
                    eylem(secili.count == sayfaSayisi ? "Seçimi kaldır" : "Tümünü seç", "checklist") {
                        secimKipi = true
                        secili = secili.count == sayfaSayisi ? [] : Set(0..<sayfaSayisi)
                    }
                    eylem("Sola döndür", "rotate.left", gerekli: true) { dondur(-90) }
                    eylem("Sağa döndür", "rotate.right", gerekli: true) { dondur(90) }
                    eylem("Çoğalt", "plus.square.on.square", gerekli: true) { cogalt() }
                    eylem("Sil", "trash", gerekli: true) { silmeSor = true }
                    eylem("Çıkar", "square.and.arrow.up.on.square", gerekli: true) { cikar() }
                    Menu {
                        Button("Seçili sayfadan önce") { bosEkle(oncesi: true) }
                        Button("Seçili sayfadan sonra") { bosEkle(oncesi: false) }
                        Button("Belgenin sonuna") { bosEkle(sona: true) }
                    } label: { etiket("Boş sayfa", "doc.badge.plus", etkin: true) }
                    eylem("Dosyadan ekle", "doc.on.doc") {
                        eklemeKonumu = (secili.max() ?? (sayfaSayisi - 1)) + 1
                        kaynakSec = true
                    }
                }
                .padding(.horizontal, 8)
            }
            .padding(.vertical, 4)
            .background(.bar)
        }
    }

    private func eylem(_ ad: String, _ simge: String, gerekli: Bool = false, _ f: @escaping () -> Void) -> some View {
        Button(action: f) { etiket(ad, simge, etkin: !gerekli || !secili.isEmpty) }
            .buttonStyle(.plain)
            .disabled(gerekli && secili.isEmpty)
    }

    private func etiket(_ ad: String, _ simge: String, etkin: Bool) -> some View {
        VStack(spacing: 2) {
            Image(systemName: simge).font(.system(size: 18))
            Text(ad).font(.caption2).lineLimit(1)
        }
        .frame(minWidth: 64)
        .padding(.vertical, 5)
        .foregroundStyle(etkin ? Color.primary : Color.secondary.opacity(0.5))
    }

    // MARK: İşlemler

    /// Sayfa yapısını değiştiren geri alınabilir işlem.
    private func uygula(_ ad: String, ileri: @escaping () -> Void, geri: @escaping () -> Void) {
        let yenile: () -> Void = {
            oturum.pdfView?.layoutDocumentView()
            durum.belgeDegisti()
            durum.sayfaSurumu += 1
        }
        oturum.degistir(ad, yap: { ileri(); yenile() }, geriAl: { geri(); yenile() })
        secili = secili.filter { $0 < (oturum.belge?.pageCount ?? 0) }
    }

    private func tasi(_ indeksler: [Int], oncesine hedef: Int) {
        guard let belge = oturum.belge else { return }
        let sira = BelgeSayfaIslemleri.siralama(sayi: belge.pageCount, tasinacak: indeksler, hedef: hedef)
        guard sira != Array(0..<belge.pageCount) else { return }
        let ters = BelgeSayfaIslemleri.tersSira(sira)
        uygula("Sayfa taşı", ileri: { BelgeSayfaIslemleri.sirala(belge, yeniSira: sira) },
               geri: { BelgeSayfaIslemleri.sirala(belge, yeniSira: ters) })
        secili = []
        hedefIndeks = nil
    }

    private func dondur(_ derece: Int) {
        guard let belge = oturum.belge else { return }
        let liste = secili.sorted()
        uygula("Döndür", ileri: { BelgeSayfaIslemleri.dondur(belge, indeksler: liste, derece: derece) },
               geri: { BelgeSayfaIslemleri.dondur(belge, indeksler: liste, derece: -derece) })
    }

    private func sil() {
        guard let belge = oturum.belge, secili.count < belge.pageCount else {
            sonuc = Ileti(baslik: "Silinemez", metin: "Belgenin bütün sayfaları silinemez.")
            return
        }
        let liste = secili.sorted()
        let kutu = SayfaKutusu()
        uygula("Sayfa sil", ileri: { kutu.silinen = BelgeSayfaIslemleri.sil(belge, indeksler: liste) },
               geri: { BelgeSayfaIslemleri.geriKoy(belge, kutu.silinen) })
        secili = []
    }

    private func cogalt() {
        guard let belge = oturum.belge else { return }
        let liste = secili.sorted()
        let kutu = SayfaKutusu()
        uygula("Sayfa çoğalt", ileri: { kutu.eklenen = BelgeSayfaIslemleri.cogalt(belge, indeksler: liste) },
               geri: { kaldir(kutu.eklenen, belge) })
        secili = []
    }

    private func bosEkle(oncesi: Bool = false, sona: Bool = false) {
        guard let belge = oturum.belge else { return }
        let sayi = belge.pageCount
        let konum = sona ? sayi : oncesi ? (secili.min() ?? 0) : (secili.max().map { $0 + 1 } ?? sayi)
        let komsu = belge.page(at: min(max(konum - 1, 0), max(sayi - 1, 0)))
        let sayfa = BelgeSayfaIslemleri.bosSayfa(boyut: komsu)
        uygula("Boş sayfa", ileri: { belge.insert(sayfa, at: min(konum, belge.pageCount)) },
               geri: { kaldir([sayfa], belge) })
    }

    private func dosyadanEkle(_ url: URL) {
        guard let belge = oturum.belge else { return }
        do {
            let kaynak = try Belge.ac(url)
            let sayfalar = (0..<kaynak.pageCount).compactMap { kaynak.page(at: $0)?.copy() as? PDFPage }
            guard !sayfalar.isEmpty else { throw KagitHata.bosGirdi }
            let konum = min(eklemeKonumu, belge.pageCount)
            uygula("Dosyadan sayfa ekle",
                   ileri: { for (k, s) in sayfalar.enumerated() { belge.insert(s, at: min(konum + k, belge.pageCount)) } },
                   geri: { kaldir(sayfalar, belge) })
        } catch {
            sonuc = Ileti(error)
        }
    }

    private func kaldir(_ sayfalar: [PDFPage], _ belge: PDFDocument) {
        for s in sayfalar {
            let i = belge.index(for: s)
            if i != NSNotFound, i < belge.pageCount { belge.removePage(at: i) }
        }
    }

    private func cikar() {
        guard let belge = oturum.belge else { return }
        let liste = secili.sorted()
        let ad = "\(oturum.oge.ad) (\(liste.count) sayfa)"
        Task {
            do {
                let veri = try BelgeSayfaIslemleri.cikar(belge, indeksler: liste)
                let gecici = Gecici.dosya("\(ad).pdf")
                try Belge.yaz(veri, gecici, beklenenSayfa: liste.count)
                let yeni = try await kitaplik.ciktiKaydet(gecici, ad: ad, kaynak: oturum.url)
                sonuc = Ileti(baslik: "Çıkarıldı", metin: "\(liste.count) sayfa \"\(yeni.tamAd)\" olarak kitaplığa kaydedildi.", hata: false)
            } catch {
                sonuc = Ileti(error)
            }
        }
    }
}

/// Geri alma kapanışlarının ortak tuttuğu sayfa listeleri.
private final class SayfaKutusu {
    var silinen: [(indeks: Int, sayfa: PDFPage)] = []
    var eklenen: [PDFPage] = []
}

/// Sayfa küçük resmi: sayfa nesnesi ve dönüklüğüne göre önbelleğe alınır.
struct SayfaKucukResimHucresi: View {
    let oturum: BelgeOturumu
    let indeks: Int
    let surum: Int
    @State private var resim: UIImage?

    private static let onbellek = NSCache<NSString, UIImage>()

    var body: some View {
        Group {
            if let resim {
                Image(uiImage: resim).resizable().scaledToFit()
            } else {
                Rectangle().fill(Color(.secondarySystemBackground)).aspectRatio(0.707, contentMode: .fit)
            }
        }
        .background(Color.white)
        .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
        .task(id: "\(indeks)-\(surum)") { await yukle() }
    }

    private func yukle() async {
        guard let s = oturum.belge?.page(at: indeks) else { return }
        let anahtar = "\(ObjectIdentifier(s).hashValue)-\(s.rotation)-\(s.annotations.count)" as NSString
        if let r = Self.onbellek.object(forKey: anahtar) { resim = r; return }
        let r = s.thumbnail(of: CGSize(width: 340, height: 480), for: .cropBox)
        Self.onbellek.setObject(r, forKey: anahtar)
        resim = r
    }
}
