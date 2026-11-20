import SwiftUI
import UniformTypeIdentifiers
import QuickLook

struct CalismaMerkezi: View {
    @Environment(\.scenePhase) private var sahne
    @State private var sunucu = CalismaSunucusu.ortak
    @State private var tur = "document"
    @State private var metin = ""
    @State private var dosyalar: [KasaDosyasi] = []
    @State private var aktar = false
    @State private var hata: String?
    @State private var mesgul = false
    @State private var anahtar = UUID()
    @State private var acilan: UUID?
    @State private var bildirimGorevi: String?

    init(kaynak: KasaDosyasi? = nil) {
        _tur = State(initialValue: kaynak == nil ? "document" : "research")
        _dosyalar = State(initialValue: kaynak.map { [$0] } ?? [])
    }

    var body: some View {
        List {
            Section {
                NavigationLink { TuvalEkrani() } label: { Label("Tuval · belgeler ve sürümler", systemImage: "doc.text") }.accessibilityIdentifier("calisma-tuval")
                NavigationLink {
                    DosyaKasasiEkrani(tur: tur, kaynakEkle: { d in
                        if !dosyalar.contains(where: { $0.id == d.id }) { dosyalar.append(d); anahtar = UUID() }
                    })
                } label: { Label("Dosya kasası · büyük dosyalar", systemImage: "externaldrive") }.accessibilityIdentifier("calisma-dosya-kasasi")
            }
            Section("Yeni çalışma") {
                Picker("Çalışma", selection: $tur) {
                    Text("Belge hazırla").tag("document")
                    Text("Araştırma dosyası").tag("research")
                    Text("Öğrenme sorusu").tag("study")
                    if sunucu.yetenekler?.modules["analysis"] == true { Text("Veri analizi").tag("analysis") }
                    if sunucu.yetenekler?.modules["audio"] == true { Text("Sesli anlatım").tag("audio") }
                }.disabled(mesgul)
                TextField("Ne üzerinde çalışalım?", text: $metin, axis: .vertical).lineLimit(3...8).accessibilityIdentifier("calisma-istem").disabled(mesgul)
                ForEach(dosyalar) { d in HStack { Text(d.name); Spacer(); Button("Kaldır") { dosyalar.removeAll { $0.id == d.id }; anahtar = UUID() }.disabled(mesgul) } }
                if let kaynakUyarisi { Text(kaynakUyarisi).font(.footnote).foregroundStyle(.red).accessibilityIdentifier("calisma-kaynak-uyarisi") }
                Button("Kaynak dosya ekle", systemImage: "paperclip") { aktar = true }.disabled(mesgul || sunucu.yetenekler == nil)
                Button { baslat() } label: { Label(mesgul ? "İşleniyor…" : "Başlat", systemImage: "play.fill") }
                    .disabled(mesgul || metin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || metin.count > 8000 || sunucu.yetenekler == nil || kaynakUyarisi != nil)
                    .accessibilityIdentifier("calisma-baslat")
                Text("Yeni ücretli API kullanımı kapalı. Büyük metinleri Dosya kasası üzerinden araştırmaya ekleyebilirsin; soruna en uygun bölümler kaynak konumlarıyla seçilir. PDF sayfaları iPhone’da numaralı metne çevrilir; metin katmanı olmayan sayfalar cihaz içi OCR ile okunur (en çok 60 sayfa, hata olabilir).").font(.footnote).foregroundStyle(.secondary)
                if let hata { Text(hata).foregroundStyle(.red) }
            }
            if let hata = sunucu.hata {
                Section { Text(hata).font(.footnote); Button("Bağlantıyı yenile") { Task { await sunucu.yenile() } } }
            }
            Section("Görevler") {
                if sunucu.gorevler.isEmpty { Text("Henüz çalışma yok.").foregroundStyle(.secondary) }
                ForEach(sunucu.gorevler) { g in
                    NavigationLink { CalismaGorevAyrintisi(kimlik: g.id) } label: {
                        VStack(alignment: .leading) { Text(g.request.input.prompt).lineLimit(2); Text(g.durum).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
        }
        .navigationTitle("Çalışma alanı")
        .navigationDestination(item: $acilan) { TuvalDuzenleyici(kimlik: $0) }
        .navigationDestination(item: $bildirimGorevi) { CalismaGorevAyrintisi(kimlik: $0) }
        .task(id: sahne) {
            guard sahne == .active else { return }
            repeat {
                await sunucu.yenile()
                if let id = sunucu.bildirimGorevi, sunucu.gorevler.contains(where: { $0.id == id }) { bildirimGorevi = id; sunucu.bildirimGorevi = nil }
                do { try await Task.sleep(for: .seconds(sunucu.gorevler.contains(where: \.etkin) ? 3 : 10)) } catch { return }
            } while !Task.isCancelled
        }
        .onChange(of: metin) { _, _ in anahtar = UUID() }
        .onChange(of: tur) { _, _ in anahtar = UUID() }
        .fileImporter(isPresented: $aktar, allowedContentTypes: [.plainText, .commaSeparatedText, .json, .pdf, UTType(filenameExtension: "xlsx") ?? .data], allowsMultipleSelection: false) { sonuc in
            Task {
                mesgul = true; defer { mesgul = false }
                do { if let yol = try sonuc.get().first { dosyalar.append(try await sunucu.yukle(yol)); anahtar = UUID(); hata = nil } }
                catch { hata = error.localizedDescription }
            }
        }
    }

    private func baslat() {
        guard kaynakUyarisi == nil else { return }
        let istekAnahtari = anahtar, girdi = metin, secili = dosyalar.map(\.id), kip = tur
        mesgul = true
        Task {
            defer { mesgul = false }
            do { _ = try await sunucu.baslat(tur: kip, metin: girdi, dosyalar: secili, anahtar: istekAnahtari); metin = ""; dosyalar = []; anahtar = UUID(); hata = nil }
            catch { hata = error.localizedDescription }
        }
    }
    private var kaynakUyarisi: String? {
        KasaDosyasi.kaynakUyarisi(dosyalar, tur: tur, arastirmaSiniri: sunucu.yetenekler?.arastirmaKaynakSiniri ?? 200_000)
    }
}

private struct CalismaGorevAyrintisi: View {
    let kimlik: String
    @Environment(\.scenePhase) private var sahne
    @State private var sunucu = CalismaSunucusu.ortak
    @State private var olaylar: [CalismaOlayi] = []
    @State private var cikti: CalismaCiktisi?
    @State private var hata: String?
    @State private var yerel: UUID?
    @State private var cevap = ""
    @State private var mesgul = false
    @State private var cevapAnahtari = UUID()
    @State private var yoklamaNesli = 0
    @State private var dosyaOnizleme: URL?
    @State private var oynatici: OynaticiHedefi?
    /// İndirilmiş ses çıktısı; ayrıntılı oynatıcı (bölümler, hız, transkript) bununla açılır.
    struct OynaticiHedefi: Identifiable, Hashable { let id: String; let url: URL }
    nonisolated static func sesMi(_ ad: String) -> Bool {
        ["mp3", "m4a", "wav", "aac"].contains((ad as NSString).pathExtension.lowercased())
    }
    private var gorev: CalismaGorevi? { sunucu.gorevler.first { $0.id == kimlik } }
    var body: some View {
        List {
            if let g = gorev {
                Section(g.durum) { Text(g.request.input.prompt); if !g.error.isEmpty { Text(g.error).foregroundStyle(.red) } }
                Section("Adımlar") { ForEach(olaylar) { Text($0.message) } }
                if let cikti {
                    Section("Çıktı") {
                        Text(cikti.content).textSelection(.enabled)
                        Button("Tuval’e kaydet") {
                            do {
                                if yerel == nil { yerel = try TuvalDeposu.ortak.olustur(baslik: cikti.title, metin: cikti.content, projeID: cikti.project_id.flatMap(UUID.init(uuidString:))).id }
                            } catch { hata = error.localizedDescription }
                        }
                        if let yerel { NavigationLink("Tuval’de aç") { TuvalDuzenleyici(kimlik: yerel) } }
                        ShareLink(item: cikti.content)
                        ForEach(cikti.files ?? []) { dosya in
                            if Self.sesMi(dosya.name) {
                                Button("Oynatıcıda dinle", systemImage: "play.circle") {
                                    Task { do { oynatici = OynaticiHedefi(id: dosya.id, url: try await sunucu.dosyaIndir(dosya)) } catch { hata = error.localizedDescription } }
                                }.accessibilityIdentifier("calisma-ses-oynatici")
                            }
                            Button(dosya.name, systemImage: "doc") {
                                Task { do { dosyaOnizleme = try await sunucu.dosyaIndir(dosya) } catch { hata = error.localizedDescription } }
                            }
                        }
                    }
                    if g.kind == "study" {
                        Section("Cevabın") {
                            TextField("Cevabını yaz veya ipucu iste", text: $cevap, axis: .vertical).disabled(mesgul)
                            Button("Değerlendir ve devam et") {
                                let p = String(g.request.input.prompt.prefix(2000)) + "\nÖnceki soru:\n" + String(cikti.content.prefix(4000)) + "\nKullanıcının cevabı:\n" + String(cevap.prefix(1500))
                                mesgul = true
                                Task {
                                    defer { mesgul = false }
                                    do { _ = try await sunucu.baslat(tur: "study", metin: p, dosyalar: [], anahtar: cevapAnahtari); cevap = ""; hata = nil }
                                    catch { hata = error.localizedDescription }
                                }
                            }.disabled(mesgul || cevap.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
                if g.etkin || g.surdurulebilir {
                    Section {
                        if g.surdurulebilir { Button("Kaldığı yerden devam et") { islem(g, devam: true) } }
                        Button("İptal et", role: .destructive) { islem(g, devam: false) }
                    }
                }
            }
            if let hata { Text(hata).foregroundStyle(.red) }
        }
        .navigationTitle("Çalışma")
        .quickLookPreview($dosyaOnizleme)
        .navigationDestination(item: $oynatici) { o in
            SesOynaticiEkrani(dosya: o.url, transkript: cikti?.content ?? "", baslik: cikti?.title ?? "Sesli anlatım", kimlik: o.id)
        }
        .onChange(of: cevap) { _, _ in cevapAnahtari = UUID() }
        .task(id: "\(sahne == .active)-\(yoklamaNesli)") {
            guard sahne == .active else { return }
            repeat {
                await sunucu.yenile()
                do {
                    olaylar = try await sunucu.olaylar(kimlik)
                    if cikti == nil, let id = gorev?.artifact_ids.first { cikti = try await sunucu.cikti(id) }
                    guard gorev?.etkin == true else { return }
                    try await Task.sleep(for: .seconds(3))
                } catch { if !Task.isCancelled { hata = error.localizedDescription }; return }
            } while !Task.isCancelled
        }
    }
    private func islem(_ g: CalismaGorevi, devam: Bool) {
        Task { do { try await sunucu.islem(g, devam: devam); yoklamaNesli += 1; hata = nil } catch { hata = error.localizedDescription } }
    }
}
