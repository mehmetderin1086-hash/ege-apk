import SwiftUI
import UniformTypeIdentifiers

/// Çok sayıda bağlantıyı (metin ya da .txt dosyası) tek seferde sıraya ekler; liste/kanal bağlantılarını videolarına açar.
struct TopluEkleSayfasi: View {
    @Environment(\.dismiss) private var kapat
    @Environment(Yonlendirici.self) private var yonlendirici
    @State private var metin = ""
    @State private var tur: IndirmeTuru = Ayarlar.shared.hizliTur == .ham ? .video : Ayarlar.shared.hizliTur
    @State private var cozunurluk = Ayarlar.shared.enFazlaCozunurluk
    @State private var listeleriAc = true
    @State private var klasorle = Ayarlar.shared.listeKlasoru
    @State private var numarala = Ayarlar.shared.listeNumarala
    @State private var atla = Ayarlar.shared.indirilenleriAtla
    @State private var sinir = 0
    @State private var calisiyor = false
    @State private var durum: String?
    @State private var dosyaSecici = false

    private var adresler: [String] { ListeAdresi.hepsi(metin) }
    private var listeSayisi: Int { adresler.filter(ListeAdresi.listeMi).count }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $metin)
                        .frame(minHeight: 160)
                        .font(.callout.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    HStack {
                        PasteButton(payloadType: String.self) { metinler in metin += (metin.isEmpty ? "" : "\n") + metinler.joined(separator: "\n") }
                            .buttonBorderShape(.capsule)
                        Spacer()
                        Button("Dosyadan (.txt)", systemImage: "doc.text") { dosyaSecici = true }
                    }
                } header: {
                    Text("Bağlantılar")
                } footer: {
                    Text(adresler.isEmpty ? "Her satıra bir bağlantı yapıştır. Oynatma listesi ve kanal bağlantıları da olur."
                         : "\(adresler.count) bağlantı bulundu\(listeSayisi > 0 ? " (\(listeSayisi) liste/kanal)" : "").")
                }

                Section("Biçim") {
                    Picker("Tür", selection: $tur) {
                        Text("Video").tag(IndirmeTuru.video)
                        Text("Ses (M4A)").tag(IndirmeTuru.ses)
                    }
                    .pickerStyle(.segmented)
                    if tur == .video {
                        Picker("En yüksek kalite", selection: $cozunurluk) {
                            ForEach(Ayarlar.cozunurlukler, id: \.self) { Text(Ayarlar.cozunurlukAdi($0)).tag($0) }
                        }
                    }
                }

                Section("Seçenekler") {
                    Toggle("Liste ve kanalları videolarına aç", isOn: $listeleriAc)
                    if listeleriAc {
                        Picker("Listeden en çok", selection: $sinir) {
                            Text("Hepsi").tag(0)
                            ForEach([10, 25, 50, 100, 250, 500], id: \.self) { Text("İlk \($0)").tag($0) }
                        }
                        Toggle("Liste adıyla klasöre kaydet", isOn: $klasorle)
                        Toggle("Sıra numarası ekle", isOn: $numarala)
                    }
                    Toggle("Zaten indirilenleri atla", isOn: $atla)
                }

                if let durum {
                    Section { Label(durum, systemImage: calisiyor ? "hourglass" : "checkmark.circle").font(.callout) }
                }
            }
            .navigationTitle("Toplu indir")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Kapat", systemImage: "xmark") { kapat() } }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task { await ekle() }
                } label: {
                    HStack {
                        if calisiyor { ProgressView().tint(.white) }
                        Text(calisiyor ? "Ekleniyor…" : "Sıraya ekle (\(adresler.count))").font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(adresler.isEmpty || calisiyor)
                .padding()
                .background(.bar)
            }
            .fileImporter(isPresented: $dosyaSecici, allowedContentTypes: [.plainText, .text, .commaSeparatedText]) { sonuc in
                guard case .success(let url) = sonuc else { return }
                let erisim = url.startAccessingSecurityScopedResource()
                defer { if erisim { url.stopAccessingSecurityScopedResource() } }
                if let icerik = try? String(contentsOf: url, encoding: .utf8) { metin += (metin.isEmpty ? "" : "\n") + icerik }
            }
            .interactiveDismissDisabled(calisiyor)
        }
    }

    private func ekle() async {
        calisiyor = true
        var secim = IndirmeSecimi.hizli(tur)
        secim.enFazla = cozunurluk
        let kuyruk = IndirmeKuyrugu.shared
        var tekler: [IndirmeKuyrugu.TopluOge] = []
        var eklenen = 0, atlanan = 0, hatali = 0
        let liste = adresler
        for (i, adres) in liste.enumerated() {
            guard listeleriAc && ListeAdresi.listeMi(adres) else {
                tekler.append(.init(adres: adres))
                continue
            }
            durum = "Liste çözülüyor (\(i + 1)/\(liste.count))…"
            do {
                let bilgi = try await PythonMotoru.shared.coz(adres, liste: true, sinir: sinir > 0 ? sinir : nil)
                let ogeler = (bilgi.entries ?? []).filter { !$0.canli }.compactMap { e in
                    e.adres.map { IndirmeKuyrugu.TopluOge(adres: $0, baslik: e.title, kapak: e.thumbnail, sure: e.duration) }
                }
                var s = secim
                s.liste = bilgi.title
                if klasorle { s.altKlasor = bilgi.title ?? bilgi.yazar }
                let sonuc = kuyruk.topluEkle(Array(ogeler.prefix(sinir > 0 ? sinir : ogeler.count)), secim: s, numarala: numarala, atla: atla)
                eklenen += sonuc.eklenen; atlanan += sonuc.atlanan
            } catch {
                hatali += 1
            }
        }
        if !tekler.isEmpty {
            let sonuc = kuyruk.topluEkle(tekler, secim: secim, atla: atla)
            eklenen += sonuc.eklenen; atlanan += sonuc.atlanan
        }
        calisiyor = false
        var ozet = "\(eklenen) öğe sıraya eklendi"
        if atlanan > 0 { ozet += ", \(atlanan) zaten vardı" }
        if hatali > 0 { ozet += ", \(hatali) liste açılamadı" }
        durum = ozet
        yonlendirici.bildirim = ozet
        if hatali == 0 {
            yonlendirici.sekme = .indir
            kapat()
        }
    }
}
