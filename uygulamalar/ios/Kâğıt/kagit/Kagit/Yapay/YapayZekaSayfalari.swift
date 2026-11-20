import KagitKit
import PDFKit
import SwiftUI

// MARK: - Ortak sonuç eylemleri

/// Yapay zekâ sonucunu belgeye not olarak ekleme ve PDF olarak kaydetme.
struct SonucEylemleri: View {
    let oturum: BelgeOturumu
    let baslik: String
    let metin: String
    var etiket: String
    @Environment(Kitaplik.self) private var kitaplik
    @Environment(\.dismiss) private var kapat
    @State private var ileti: Ileti?

    var body: some View {
        HStack {
            ShareLink(item: metin) { Label("Paylaş", systemImage: "square.and.arrow.up") }
            Button { notEkle() } label: { Label("Nota ekle", systemImage: "note.text.badge.plus") }
            Button { pdfKaydet() } label: { Label("PDF kaydet", systemImage: "doc.badge.plus") }
        }
        .buttonStyle(.bordered).controlSize(.small)
        .iletiGoster($ileti)
    }

    private func notEkle() {
        guard let s = oturum.pdfView?.currentPage ?? oturum.belge?.page(at: 0) else { return }
        let kutu = s.bounds(for: .cropBox)
        let a = PDFAnnotation(bounds: CGRect(x: kutu.minX + 20, y: kutu.maxY - 44, width: 24, height: 24), forType: .text, withProperties: nil)
        a.contents = "\(baslik)\n\n\(metin)"
        a.color = .systemIndigo
        a.userName = "\(Isaret.onek)yapay"
        oturum.aciklamaEkle(a, s, ad: "Yapay zekâ notu")
        ileti = Ileti(baslik: "Not eklendi", metin: "Not, geçerli sayfanın sol üstüne konuldu. Belgeyi kaydetmeyi unutmayın.", hata: false)
    }

    private func pdfKaydet() {
        let ad = "\(oturum.oge.ad) - \(baslik)"
        let v = MetinPDF.uret(baslik: ad, altBaslik: "Kaynak: \(etiket)", govde: metin)
        Task {
            do {
                let t = Gecici.dosya("\(ad).pdf")
                try v.write(to: t)
                let o = try await kitaplik.ciktiKaydet(t, ad: ad, kaynak: oturum.url)
                ileti = Ileti(baslik: "Kaydedildi", metin: "“\(o.tamAd)” kitaplığa eklendi.", hata: false)
            } catch { ileti = Ileti(error) }
        }
    }
}

/// Belgeden sayfa aralığındaki metni alır (kaydedilmemiş değişiklikler dahil).
@MainActor
func oturumMetni(_ oturum: BelgeOturumu, aralik: String) async throws -> [Int: String] {
    let v = try oturum.veriAl()
    let n = oturum.belge?.pageCount ?? 0
    let idx = try SayfaAraligi.coz(aralik, sayfaSayisi: n)
    let m = try await BelgeMetni.sayfaMetinleri(veri: v, sayfalar: idx, ocr: true)
    guard !m.isEmpty else { throw KagitHata.yapayZeka("Bu sayfalarda metin bulunamadı.") }
    return m
}

// MARK: - Özet

struct OzetSayfasi: View {
    let oturum: BelgeOturumu
    @Environment(\.dismiss) private var kapat
    @State private var stil: OzetStili = .ayrintili
    @State private var aralik = ""
    @State private var sonuc: YapayCikti?
    @State private var calisiyor = false
    @State private var oran: Double?
    @State private var hata: String?
    @State private var gorev: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Biçim", selection: $stil) { ForEach(OzetStili.allCases) { Text($0.ad).tag($0) } }
                    SayfaAraligiAlani(metin: $aralik)
                    Button { calistir() } label: {
                        HStack { Label(sonuc == nil ? "Özetle" : "Yeniden özetle", systemImage: "text.append"); if calisiyor { Spacer(); ProgressView() } }
                    }
                    .disabled(calisiyor)
                    if let oran, calisiyor { ProgressView(value: oran) }
                }
                if let hata { Section { Text(hata).foregroundStyle(.red) } }
                if let sonuc {
                    Section {
                        Text(sonuc.metin).textSelection(.enabled)
                        KaynakRozeti(etiket: sonuc.kaynakEtiketi)
                        SonucEylemleri(oturum: oturum, baslik: "Özet", metin: sonuc.metin, etiket: sonuc.kaynakEtiketi)
                    } header: { Text("Özet") }
                }
            }
            .navigationTitle("Özetle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { gorev?.cancel(); kapat() } } }
        }
    }

    private func calistir() {
        calisiyor = true; hata = nil; oran = nil
        let yz = YapayAyar.paylasilan.yapayZeka()
        gorev = Task {
            defer { calisiyor = false }
            do {
                if let n = yz.kullanilamazNedeni { throw KagitHata.yapayZeka(n) }
                let m = try await oturumMetni(oturum, aralik: aralik)
                sonuc = try await Ozetleyici.ozetle(sayfalar: m, stil: stil, yz: yz, ilerleme: { o in Task { @MainActor in oran = o } })
            } catch { if !Task.isCancelled { hata = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription } }
        }
    }
}

// MARK: - Sohbet

struct SohbetSayfasi: View {
    let oturum: BelgeOturumu
    @Environment(\.dismiss) private var kapat

    struct Satir: Identifiable {
        let id = UUID()
        let rol: YapayMesaj.Rol
        var metin: String
        var kaynaklar: [Int] = []
        var etiket: String?
    }

    @State private var sohbet: BelgeSohbeti?
    @State private var satirlar: [Satir] = []
    @State private var soru = ""
    @State private var hazirlaniyor = true
    @State private var yaniyor = false
    @State private var hata: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { kaydir in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if hazirlaniyor { HStack { ProgressView(); Text("Belge okunuyor…").foregroundStyle(.secondary) } }
                            if satirlar.isEmpty && !hazirlaniyor && hata == nil {
                                Text("Belgeyle ilgili bir soru sorun. Yanıtlar kaynak sayfa numaralarıyla gelir.").foregroundStyle(.secondary)
                            }
                            ForEach(satirlar) { s in balon(s).id(s.id) }
                            if yaniyor { ProgressView().padding(.leading) }
                            if let hata { Text(hata).foregroundStyle(.red).font(.callout) }
                        }
                        .padding()
                    }
                    .onChange(of: satirlar.count) { _, _ in if let son = satirlar.last { withAnimation { kaydir.scrollTo(son.id, anchor: .bottom) } } }
                }
                Divider()
                HStack {
                    TextField("Belgeye sor…", text: $soru, axis: .vertical).lineLimit(1...4).textFieldStyle(.roundedBorder).onSubmit(gonder)
                    Button { gonder() } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }
                        .disabled(soru.trimmingCharacters(in: .whitespaces).isEmpty || yaniyor || sohbet == nil)
                }
                .padding(10)
            }
            .navigationTitle("Belgeyle sohbet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { kapat() } } }
            .task { await hazirla() }
        }
    }

    @ViewBuilder private func balon(_ s: Satir) -> some View {
        VStack(alignment: s.rol == .kullanici ? .trailing : .leading, spacing: 4) {
            Text(s.metin).textSelection(.enabled).padding(10)
                .background(s.rol == .kullanici ? Color.accentColor.opacity(0.2) : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            if !s.kaynaklar.isEmpty {
                HStack(spacing: 6) {
                    Text("Kaynak:").font(.caption).foregroundStyle(.secondary)
                    ForEach(s.kaynaklar, id: \.self) { n in
                        Button("s. \(n)") {
                            if let p = oturum.belge?.page(at: n - 1) { oturum.pdfView?.go(to: p) }
                        }
                        .font(.caption.bold()).buttonStyle(.bordered).controlSize(.mini)
                    }
                }
            }
            if let e = s.etiket { KaynakRozeti(etiket: e) }
        }
        .frame(maxWidth: .infinity, alignment: s.rol == .kullanici ? .trailing : .leading)
    }

    private func hazirla() async {
        let yz = YapayAyar.paylasilan.yapayZeka()
        if let n = yz.kullanilamazNedeni { hata = n; hazirlaniyor = false; return }
        do {
            let m = try await oturumMetni(oturum, aralik: "")
            sohbet = BelgeSohbeti(sayfalar: m, yz: yz)
        } catch { hata = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
        hazirlaniyor = false
    }

    private func gonder() {
        let q = soru.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, let sohbet, !yaniyor else { return }
        let gecmis = satirlar.map { YapayMesaj($0.rol, $0.metin) }
        satirlar.append(Satir(rol: .kullanici, metin: q))
        soru = ""; yaniyor = true; hata = nil
        Task {
            defer { yaniyor = false }
            do {
                let y = try await sohbet.sor(q, gecmis: gecmis)
                satirlar.append(Satir(rol: .asistan, metin: y.metin, kaynaklar: y.kaynakSayfalar, etiket: y.kaynakEtiketi))
            } catch { hata = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
        }
    }
}

// MARK: - Seçili metin

struct SecimSayfasi: View {
    let oturum: BelgeOturumu
    let gorev: YapayZekaCubugu.SecimGorevi
    let metin: String
    @Environment(\.dismiss) private var kapat
    @State private var sonuc: YapayCikti?
    @State private var hata: String?

    private var baslik: String { gorev == .acikla ? "Açıklama" : "Sadeleştirme" }

    var body: some View {
        NavigationStack {
            Form {
                Section("Seçili metin") { Text(metin).font(.callout).foregroundStyle(.secondary).lineLimit(6) }
                if let sonuc {
                    Section(baslik) {
                        Text(sonuc.metin).textSelection(.enabled)
                        KaynakRozeti(etiket: sonuc.kaynakEtiketi)
                        SonucEylemleri(oturum: oturum, baslik: baslik, metin: sonuc.metin, etiket: sonuc.kaynakEtiketi)
                    }
                } else if let hata {
                    Section { Text(hata).foregroundStyle(.red) }
                } else {
                    Section { HStack { ProgressView(); Text("Yapay zekâ yanıtlıyor…") } }
                }
            }
            .navigationTitle(baslik)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { kapat() } } }
            .task {
                let yz = YapayAyar.paylasilan.yapayZeka()
                do {
                    if let n = yz.kullanilamazNedeni { throw KagitHata.yapayZeka(n) }
                    sonuc = gorev == .acikla ? try await MetinGorevleri.acikla(metin, yz: yz) : try await MetinGorevleri.sadelestir(metin, yz: yz)
                } catch { hata = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
            }
        }
    }
}

// MARK: - Tüm belgeyi çevir

struct BelgeCeviriSayfasi: View {
    let oturum: BelgeOturumu
    @Environment(Kitaplik.self) private var kitaplik
    @Environment(\.dismiss) private var kapat
    @State private var hedef: Cevirmen.Hedef = .ingilizce
    @State private var aralik = ""
    @State private var calisiyor = false
    @State private var oran: Double?
    @State private var kayit: KitaplikOgesi?
    @State private var hata: String?
    @State private var gorev: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Hedef dil", selection: $hedef) { ForEach(Cevirmen.Hedef.allCases) { Text($0.ad).tag($0) } }.pickerStyle(.segmented)
                    SayfaAraligiAlani(metin: $aralik)
                    Button { calistir() } label: { HStack { Label("Çevir ve PDF oluştur", systemImage: "character.bubble"); if calisiyor { Spacer(); ProgressView() } } }
                        .disabled(calisiyor)
                    if calisiyor, let oran { ProgressView(value: oran) }
                } footer: { Text("Çeviri bulutta yapılır. Sonuç, metni taşıyan yeni bir PDF olarak kitaplığa kaydedilir.") }
                if let hata { Section { Text(hata).foregroundStyle(.red) } }
                if let kayit {
                    Section("Hazır") { Label(kayit.tamAd, systemImage: "doc.richtext") }
                }
            }
            .navigationTitle("Belgeyi çevir")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { gorev?.cancel(); kapat() } } }
        }
    }

    private func calistir() {
        calisiyor = true; hata = nil; kayit = nil; oran = nil
        let yz = YapayAyar.paylasilan.yapayZeka()
        let ad = oturum.oge.ad, h = hedef
        gorev = Task {
            defer { calisiyor = false }
            do {
                if let n = yz.kullanilamazNedeni { throw KagitHata.yapayZeka(n) }
                let m = try await oturumMetni(oturum, aralik: aralik)
                let r = try await Cevirmen.cevir(sayfalar: m, hedef: h, yz: yz, ilerleme: { o in Task { @MainActor in oran = o } })
                let govde = r.sayfalar.keys.sorted().map { "# Sayfa \($0)\n\(r.sayfalar[$0] ?? "")" }.joined(separator: "\n")
                let pdf = MetinPDF.uret(baslik: "\(ad) — \(h.ad)", altBaslik: "Kaynak: \(r.kaynakEtiketi)", govde: govde)
                let t = Gecici.dosya("\(ad) - \(h.ad) çeviri.pdf")
                try pdf.write(to: t)
                kayit = try await kitaplik.ciktiKaydet(t, ad: "\(ad) - \(h.ad) çeviri", kaynak: oturum.url)
            } catch { if !Task.isCancelled { hata = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription } }
        }
    }
}
