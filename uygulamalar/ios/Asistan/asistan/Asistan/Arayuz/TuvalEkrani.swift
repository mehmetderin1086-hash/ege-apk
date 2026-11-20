import SwiftUI
import UniformTypeIdentifiers

struct TuvalEkrani: View {
    @State private var depo = TuvalDeposu.ortak
    @State private var yeni = false
    @State private var baslik = ""
    @State private var hata: String?
    @State private var secilen: UUID?
    @State private var olusturulan: UUID?
    @State private var aktar = false

    var body: some View {
        List {
            if let uyari = depo.okumaHatasi { Text(uyari).foregroundStyle(.orange) }
            if let hata { Text(hata).foregroundStyle(.red) }
            if depo.belgeler.isEmpty { ContentUnavailableView("İlk belgeni oluştur", systemImage: "doc.badge.plus", description: Text("Belgeler ve sürümleri bu iPhone’da saklanır.")) }
            ForEach(depo.belgeler) { b in
                NavigationLink(value: b.id) {
                    VStack(alignment: .leading) {
                        Text(b.baslik).font(.headline)
                        Text("\(b.surumler.count) sürüm · \(b.guncel.tarih.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                        if let id = b.projeID, let p = ProjeDeposu.ortak.projeler.first(where: { $0.id == id }) { Text(p.ad).font(.caption) }
                    }
                }.accessibilityIdentifier("tuval-belge")
            }
        }
        .navigationTitle("Tuval")
        .navigationDestination(for: UUID.self) { TuvalDuzenleyici(kimlik: $0) }
        .navigationDestination(item: $secilen) { TuvalDuzenleyici(kimlik: $0) }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { aktar = true } label: { Label("Metin içe aktar", systemImage: "square.and.arrow.down") }
                Button { yeni = true } label: { Label("Yeni belge", systemImage: "plus") }.accessibilityIdentifier("tuval-yeni")
            }
        }
        .sheet(isPresented: $yeni, onDismiss: {
            // Başlık klavyesi ve sunum kapanmadan yeni düzenleyiciye geçme.
            secilen = olusturulan; olusturulan = nil
        }) {
            NavigationStack {
                Form {
                    TextField("Başlık", text: $baslik).accessibilityIdentifier("tuval-yeni-baslik")
                    if let hata { Text(hata).foregroundStyle(.red) }
                }
                .navigationTitle("Yeni belge")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { yeni = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Oluştur") {
                            do {
                                olusturulan = try depo.olustur(baslik: baslik, metin: "", projeID: ProjeDeposu.ortak.aktifKimlik).id
                                baslik = ""; hata = nil; yeni = false
                            } catch { hata = error.localizedDescription }
                        }.accessibilityIdentifier("tuval-olustur")
                    }
                }
            }
        }
        .fileImporter(isPresented: $aktar, allowedContentTypes: [.plainText, .sourceCode, .html], allowsMultipleSelection: false) { sonuc in
            do {
                guard let yol = try sonuc.get().first else { return }
                let erisim = yol.startAccessingSecurityScopedResource(); defer { if erisim { yol.stopAccessingSecurityScopedResource() } }
                guard (try yol.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 800_000 else { throw TuvalHatasi.sinir }
                let metin = try String(contentsOf: yol, encoding: .utf8)
                secilen = try depo.olustur(baslik: yol.deletingPathExtension().lastPathComponent, metin: metin,
                                          tur: yol.pathExtension.lowercased() == "html" ? "html" : "markdown", projeID: ProjeDeposu.ortak.aktifKimlik).id
            } catch { hata = error.localizedDescription }
        }
    }
}

struct TuvalDuzenleyici: View {
    let kimlik: UUID
    @Environment(\.dismiss) private var kapat
    @Environment(\.scenePhase) private var sahne
    @State private var depo = TuvalDeposu.ortak
    @State private var metin = ""
    @State private var temel: UUID?
    @State private var hata: String?
    @State private var gecmis = false
    @State private var onizleme = false
    @State private var paylasim: URL?
    @State private var secim: NSRange?
    @State private var degisim = ""
    @State private var secimAcik = false
    @State private var seciliAralik: NSRange?
    private var belge: TuvalBelgesi? { depo.bul(kimlik) }
    private var degisti: Bool { metin != belge?.guncel.metin }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let hata { Text(hata).font(.footnote).foregroundStyle(.red).padding(.horizontal) }
            if let b = belge, temel != nil, temel != b.guncel.id {
                Button("Taslağı ayrı belgeye kaydet ve güncel sürümü aç") {
                    do {
                        _ = try depo.olustur(baslik: b.baslik + " · kurtarılan taslak", metin: metin, projeID: b.projeID)
                        metin = b.guncel.metin; temel = b.guncel.id; hata = nil
                    } catch { hata = error.localizedDescription }
                }
                    .font(.footnote).padding(.horizontal)
            }
            TuvalMetinAlani(metin: $metin, secim: $secim).padding(.horizontal, 6)
            HStack {
                Text("\(metin.count) karakter").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Seçimi değiştir") { secimiAc() }.disabled(secim == nil).accessibilityIdentifier("tuval-secim")
            }.padding()
        }
        .navigationTitle(belge?.baslik ?? "Belge")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .task { if let b = belge, temel == nil {
            let taslak = depo.taslak(kimlik)
            temel = taslak?.temel ?? b.guncel.id; metin = taslak?.metin ?? b.guncel.metin
        } }
        .onChange(of: metin) { _, yeni in
            guard let temel else { return }
            do { try depo.taslakKaydet(kimlik, temel: temel, metin: yeni) }
            catch { hata = "Taslak kaydedilemedi: " + error.localizedDescription }
        }
        .onChange(of: sahne) { _, yeni in if yeni != .active, degisti { _ = kaydet() } }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button("Geri", systemImage: "chevron.left") { if kaydet() { kapat() } }.accessibilityIdentifier("tuval-geri") }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Kaydet") { kaydet() }.disabled(!degisti).accessibilityIdentifier("tuval-kaydet")
                Menu {
                    Button("Sürüm geçmişi", systemImage: "clock.arrow.circlepath") { gecmis = true }
                    Button("Önizleme", systemImage: "eye") { onizleme = true }
                    Button("Markdown olarak paylaş", systemImage: "square.and.arrow.up") {
                        guard kaydet() else { return }
                        do { paylasim = try depo.disaAktar(kimlik) } catch { hata = error.localizedDescription }
                    }
                } label: { Image(systemName: "ellipsis.circle") }.accessibilityIdentifier("tuval-menu")
            }
        }
        .onDisappear { if degisti { kaydet() } }
        .sheet(isPresented: $gecmis) {
            NavigationStack {
                List(belge?.surumler.reversed().map { $0 } ?? []) { s in
                    NavigationLink {
                        ScrollView { VStack(alignment: .leading, spacing: 16) {
                            Text("Seçilen sürüm").font(.headline)
                            Text(s.metin).textSelection(.enabled)
                            Divider()
                            Text("Şu anki metin").font(.headline)
                            Text(metin).textSelection(.enabled)
                        }.padding() }
                        .toolbar { Button("Bu sürüme dön") {
                            do {
                                guard kaydet(), let temel else { return }
                                let b = try depo.geriDon(kimlik, surum: s.id, temel: temel)
                                metin = b.guncel.metin; self.temel = b.guncel.id; gecmis = false; hata = nil
                            } catch { hata = error.localizedDescription; gecmis = false }
                        } }
                    } label: { VStack(alignment: .leading) { Text(s.aciklama); Text(s.tarih, style: .time).font(.caption) } }
                }.navigationTitle("Sürüm geçmişi")
                .toolbar { Button("Tamam") { gecmis = false } }
            }
        }
        .sheet(isPresented: $onizleme) {
            NavigationStack {
                Group {
                    if belge?.tur == "html" { TuvalHTMLOnizleme(html: metin) }
                    else { ScrollView { Text(.init(metin)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding() } }
                }.navigationTitle("Önizleme").toolbar { Button("Tamam") { onizleme = false } }
            }
        }
        .sheet(isPresented: Binding(get: { paylasim != nil }, set: { if !$0 { paylasim = nil } })) {
            if let paylasim { ShareLink(item: paylasim) { Label("Belgeyi paylaş", systemImage: "square.and.arrow.up") }.padding() }
        }
        .sheet(isPresented: $secimAcik) {
            NavigationStack {
                TextEditor(text: $degisim).padding().accessibilityIdentifier("tuval-secim-metni")
                    .navigationTitle("Seçili bölüm")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { secimAcik = false } }
                        ToolbarItem(placement: .confirmationAction) { Button("Uygula") {
                            guard let seciliAralik, let r = Range(seciliAralik, in: metin) else { hata = TuvalHatasi.gecersizSecim.localizedDescription; return }
                            metin.replaceSubrange(r, with: degisim); secim = nil; secimAcik = false; kaydet()
                        } }
                    }
            }
        }
    }

    private func secimiAc() {
        guard let secim, let r = Range(secim, in: metin) else { return }
        seciliAralik = secim; degisim = String(metin[r]); secimAcik = true
    }
    @discardableResult private func kaydet() -> Bool {
        guard let temel else { return false }
        do { let b = try depo.kaydet(kimlik, temel: temel, metin: metin); self.temel = b.guncel.id; hata = nil; return true }
        catch { hata = error.localizedDescription; return false }
    }
}

/// Seçim ve klavye aynı UITextView üzerinde yönetilir; yeniden çizim imleci sıfırlamaz.
private struct TuvalMetinAlani: UIViewRepresentable {
    @Binding var metin: String
    @Binding var secim: NSRange?
    func makeCoordinator() -> Esleyici { Esleyici(self) }
    func makeUIView(context: Context) -> UITextView {
        let v = UITextView()
        v.font = .preferredFont(forTextStyle: .body)
        v.adjustsFontForContentSizeCategory = true
        v.backgroundColor = .clear
        v.isEditable = true; v.isSelectable = true
        v.accessibilityIdentifier = "tuval-metin"
        v.delegate = context.coordinator
        return v
    }
    func updateUIView(_ v: UITextView, context: Context) {
        context.coordinator.ust = self
        guard v.text != metin else { return }
        context.coordinator.yenileniyor = true
        let onceki = v.selectedRange
        v.text = metin
        if Range(onceki, in: metin) != nil { v.selectedRange = onceki }
        context.coordinator.yenileniyor = false
    }
    @MainActor final class Esleyici: NSObject, UITextViewDelegate {
        var ust: TuvalMetinAlani
        var yenileniyor = false
        init(_ ust: TuvalMetinAlani) { self.ust = ust }
        func textViewDidChange(_ textView: UITextView) {
            guard !yenileniyor else { return }
            ust.metin = textView.text
        }
        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !yenileniyor else { return }
            let r = textView.selectedRange
            ust.secim = r.length > 0 && Range(r, in: textView.text) != nil ? r : nil
        }
    }
}
