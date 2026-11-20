import SwiftUI
import WebKit

struct KazimaSayfasi: Identifiable {
    let id = UUID()
    let url: URL
}

nonisolated struct KazimaOgesi: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let tur: String
    let ad: String
    let deger: String
    let url: String?
}

nonisolated struct KazimaRaporu: Codable, Sendable {
    let kaynak: String
    let baslik: String
    let aciklama: String
    let dil: String
    let taramaTarihi: String
    let ogeler: [KazimaOgesi]
}

enum KazimaDisaAktarici {
    static func veri(_ rapor: KazimaRaporu, csv: Bool) throws -> Data {
        if csv {
            // =, +, -, @ ile başlayan hücre tablo programında formül olarak çalışmasın (güvenilmeyen sayfa verisi; Kaziyici.csv ile aynı).
            func kacis(_ s: String) -> String {
                let g = s.first.map { "=+-@\t\r".contains($0) } == true ? "'" + s : s
                return "\"" + g.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            }
            let satirlar = [["tur", "ad", "deger", "url"]] + rapor.ogeler.map { [$0.tur, $0.ad, $0.deger, $0.url ?? ""] }
            guard let veri = satirlar.map({ $0.map(kacis).joined(separator: ",") }).joined(separator: "\n").data(using: .utf8) else {
                throw IndirmeHatasi.metin("CSV oluşturulamadı.")
            }
            return veri
        }
        let kodlayici = JSONEncoder()
        kodlayici.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try kodlayici.encode(rapor)
    }
}

/// Kullanıcının verdiği HTTPS sayfasını iPhone'da, görünür WebKit ekranına
/// ihtiyaç duymadan hızlıca tarar. JavaScript ile sonradan oluşan sayfalarda
/// `WebKaziyici` ekranı yedek olarak kullanılır.
nonisolated enum WebKazimaHizli {
    /// Getirme `SayfaGetirici.getir` ile: ilk adres ve her yönlendirme urlGuvenli + DNS denetiminden geçer (yerel ağa
    /// istek gitmez), gövde akışla en çok 5 MB okunur, yalnız 2xx kabul edilir, toplam süre 30 sn.
    /// `@concurrent`: getirme ve regex ayrıştırması ana iş parçacığı dışında koşar.
    @concurrent nonisolated static func tara(_ url: URL) async throws -> KazimaRaporu {
        let y = try await SayfaGetirici.getirTam(url)
        guard (200..<300).contains(y.kod) else { throw IndirmeHatasi.metin("Sayfa açılamadı (HTTP \(y.kod)).") }
        let (veri, son) = (y.veri, y.adres)
        guard veri.count <= 2_000_000 else { throw IndirmeHatasi.metin("Sayfa verisi güvenli boyut sınırını aştı.") }
        return rapor(html: WebOkuma.coz(veri, icerikTuru: y.tur), kaynak: son)
    }

    static func rapor(html: String, kaynak: URL, tarih: Date = .now) -> KazimaRaporu {
        var ogeler: [KazimaOgesi] = []
        var gorulen = Set<String>()
        func temiz(_ metin: String) -> String {
            metin
                .replacingOccurrences(of: "&nbsp;", with: " ")
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&#39;", with: "'")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func mutlak(_ ham: String) -> String? {
            guard let url = URL(string: ham, relativeTo: kaynak)?.absoluteURL,
                  url.scheme == "https", url.user == nil, url.password == nil,
                  url.absoluteString.count <= 4096 else { return nil }
            return url.absoluteString
        }
        func ekle(_ tur: String, _ ad: String, _ deger: String, _ hamURL: String? = nil) {
            guard ogeler.count < 1200 else { return }
            let url = hamURL.flatMap(mutlak)
            let deger = temiz(deger)
            guard !deger.isEmpty || url != nil else { return }
            let anahtar = tur + "|" + (url ?? deger)
            guard gorulen.insert(anahtar).inserted else { return }
            ogeler.append(.init(id: String(ogeler.count + 1), tur: tur,
                                ad: String(temiz(ad).prefix(180)).isEmpty ? tur : String(temiz(ad).prefix(180)),
                                deger: String(deger.prefix(12_000)), url: url))
        }
        func eslesmeler(_ desen: String) -> [[String]] {
            guard let regex = try? NSRegularExpression(pattern: desen, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
            let tum = NSRange(html.startIndex..., in: html)
            return regex.matches(in: html, range: tum).map { eslesme in
                (1..<eslesme.numberOfRanges).map { i in
                    guard let aralik = Range(eslesme.range(at: i), in: html) else { return "" }
                    return String(html[aralik])
                }
            }
        }
        func etiketler(_ desen: String) -> [String] {
            guard let regex = try? NSRegularExpression(pattern: desen, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
            return regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap {
                guard let aralik = Range($0.range, in: html) else { return nil }
                return String(html[aralik])
            }
        }
        func ozellik(_ parca: String, _ ad: String) -> String? {
            let desen = #"\b"# + NSRegularExpression.escapedPattern(for: ad) + #"\s*=\s*[\"']([^\"']+)[\"']"#
            guard let regex = try? NSRegularExpression(pattern: desen, options: [.caseInsensitive]),
                  let eslesme = regex.firstMatch(in: parca, range: NSRange(parca.startIndex..., in: parca)),
                  let aralik = Range(eslesme.range(at: 1), in: parca) else { return nil }
            return String(parca[aralik])
        }
        let baslik = eslesmeler(#"<title[^>]*>(.*?)</title>"#).first?.first.map(temiz) ?? ""
        let aciklama = etiketler(#"<meta[^>]+(?:name|property)\s*=\s*[\"'](?:description|og:description)[\"'][^>]*>"#)
            .first.flatMap { ozellik($0, "content").map(temiz) } ?? ""
        let govde = html
            .replacingOccurrences(of: #"<(script|style|noscript)\b[^>]*>[\s\S]*?</\1>"#, with: " ", options: [.regularExpression, .caseInsensitive])   // `.` satır geçmez
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        if !temiz(govde).isEmpty { ekle("metin", baslik.isEmpty ? "Sayfa metni" : baslik, govde) }
        for parca in eslesmeler(#"<a\b[^>]*href\s*=\s*[\"']([^\"']+)[\"'][^>]*>(.*?)</a>"#) {
            guard parca.count >= 2 else { continue }
            let ham = parca[0]; let metin = parca[1].replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            let uzanti = URL(string: ham, relativeTo: kaynak)?.pathExtension.lowercased() ?? ""
            let tur = ["mp3", "m4a", "aac", "wav", "ogg", "flac"].contains(uzanti) ? "ses" :
                ["mp4", "mov", "webm", "mkv", "avi"].contains(uzanti) ? "video" :
                ["pdf", "doc", "docx", "xls", "xlsx", "csv", "zip", "epub", "txt", "json", "xml", "ppt", "pptx"].contains(uzanti) ? "dosya" : "baglanti"
            ekle(tur, metin.isEmpty ? ham : metin, ham, ham)
        }
        for etiket in ["img", "audio", "video", "source", "track"] {
            for parca in etiketler("<" + etiket + #"\b[^>]*>"#) {
                guard let ham = ozellik(parca, "src") else { continue }
                let tur = etiket == "img" ? "gorsel" : (etiket == "audio" ? "ses" : (etiket == "track" ? "altyazi" : "video"))
                ekle(tur, ozellik(parca, "title") ?? baslik, ham, ham)
            }
        }
        for satir in eslesmeler(#"<tr\b[^>]*>(.*?)</tr>"#) {
            guard let ham = satir.first else { continue }
            let hucreler = eslesmelerIcinde(ham, desen: #"<(?:td|th)\b[^>]*>(.*?)</(?:td|th)>"#).map { temiz($0) }.filter { !$0.isEmpty }
            if !hucreler.isEmpty { ekle("tablo", "Tablo satırı", hucreler.joined(separator: " | ")) }
        }
        for veri in eslesmeler(#"<script\b[^>]*type\s*=\s*[\"']application/ld\+json[\"'][^>]*>(.*?)</script>"#) {
            if let json = veri.first, !temiz(json).isEmpty { ekle("yapisal-veri", "JSON-LD", json) }
        }
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return .init(kaynak: kaynak.absoluteString, baslik: baslik, aciklama: aciklama,
                     dil: eslesmeler(#"<html\b[^>]*\blang\s*=\s*[\"']([^\"']+)"#).first?.first ?? "",
                     taramaTarihi: iso.string(from: tarih), ogeler: ogeler)
    }

    private static func eslesmelerIcinde(_ metin: String, desen: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: desen, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        return regex.matches(in: metin, range: NSRange(metin.startIndex..., in: metin)).compactMap {
            guard let aralik = Range($0.range(at: 1), in: metin) else { return nil }
            return String(metin[aralik])
        }
    }
}

@MainActor @Observable
final class WebKaziyici: NSObject, WKNavigationDelegate {
    let web: WKWebView
    var rapor: KazimaRaporu?
    var durum = "Sayfa açılıyor…"
    var taraniyor = false

    override init() {
        let yapilandirma = WKWebViewConfiguration()
        yapilandirma.websiteDataStore = .nonPersistent()
        web = WKWebView(frame: .zero, configuration: yapilandirma)
        super.init()
        web.navigationDelegate = self
    }

    func ac(_ url: URL) {
        web.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        durum = "Sayfa hazır. Dinamik içerik için sayfayı kaydırabilir, sonra Tara’ya dokunabilirsin."
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        durum = error.localizedDescription
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        // Yedek ekran da yerel ağa/özel adrese gitmez; ad özel ağa çözülüyorsa da (DNS) gezinilmez.
        // URL await'ten önce alınır: WKNavigationAction Sendable değil.
        guard let u = navigationAction.request.url else { return .cancel }
        return await WebSayfa.gezinmeGuvenli(u) ? .allow : .cancel
    }

    func tara() async {
        taraniyor = true
        defer { taraniyor = false }
        do {
            let sonuc = try await web.evaluateJavaScript(Self.kaziyici)
            guard let json = sonuc as? String,
                  json.utf8.count <= 2_000_000,
                  let veri = json.data(using: .utf8) else {
                throw IndirmeHatasi.metin("Sayfa verisi güvenli boyut sınırını aştı.")
            }
            rapor = try JSONDecoder().decode(KazimaRaporu.self, from: veri)
            durum = "\(rapor?.ogeler.count ?? 0) öğe çıkarıldı. Sonuçları seçebilir veya veri dosyası oluşturabilirsin."
        } catch {
            durum = "Sayfa taranamadı: \(error.localizedDescription)"
        }
    }

    // Sayfadaki veriler yalnız kaynak veridir; komut olarak çalıştırılmaz.
    static let kaziyici = #"""
    (() => {
      const items = [], seen = new Set();
      const clean = value => String(value || '').replace(/\s+/g, ' ').trim();
      const absolute = raw => {
        try {
          const u = new URL(raw, location.href);
          if (u.protocol !== 'https:' || u.username || u.password || u.href.length > 4096) return null;
          return u.href;
        } catch (_) { return null; }
      };
      const add = (kind, name, value, rawURL = null) => {
        if (items.length >= 1200) return;
        const url = rawURL ? absolute(rawURL) : null;
        const text = clean(value).slice(0, 12000);
        if (!text && !url) return;
        const key = kind + '|' + (url || text);
        if (seen.has(key)) return;
        seen.add(key);
        items.push({id:String(items.length + 1), tur:kind, ad:clean(name).slice(0, 180) || kind, deger:text, url:url});
      };

      const title = clean(document.title).slice(0, 300);
      const description = clean(document.querySelector('meta[name="description"]')?.content || document.querySelector('meta[property="og:description"]')?.content).slice(0, 1000);
      document.querySelectorAll('h1,h2,h3,p,li,blockquote,article').forEach((e, index) => {
        const text = clean(e.innerText);
        if (text.length >= 2) add('metin', e.tagName + ' ' + (index + 1), text.slice(0, 12000));
      });
      document.querySelectorAll('a[href]').forEach(e => {
        const href = absolute(e.href);
        if (!href) return;
        const path = new URL(href).pathname.toLowerCase();
        const ext = (path.match(/\.([a-z0-9]{1,8})$/) || [])[1] || '';
        const audio = ['mp3','m4a','aac','wav','ogg','flac'];
        const video = ['mp4','mov','webm','mkv','avi'];
        const docs = ['pdf','doc','docx','xls','xlsx','csv','zip','epub','txt','json','xml','ppt','pptx'];
        const kind = audio.includes(ext) ? 'ses' : video.includes(ext) ? 'video' : docs.includes(ext) ? 'dosya' : 'baglanti';
        add(kind, clean(e.innerText) || href.split('/').pop(), href, href);
      });
      document.querySelectorAll('img[src],img[srcset]').forEach(e => {
        let raw = e.currentSrc || e.src;
        if (!raw && e.srcset) raw = e.srcset.split(',').pop().trim().split(/\s+/)[0];
        add('gorsel', e.alt || e.title || 'Görsel', raw, raw);
      });
      document.querySelectorAll('video,audio,source,track').forEach(e => {
        const raw = e.currentSrc || e.src;
        const parent = e.closest('audio,video');
        const kind = e.tagName === 'TRACK' ? 'altyazi' : (e.tagName === 'AUDIO' || parent?.tagName === 'AUDIO') ? 'ses' : 'video';
        add(kind, e.title || e.label || document.title || kind, raw, raw);
      });
      document.querySelectorAll('table').forEach((table, tableIndex) => {
        [...table.rows].slice(0, 250).forEach((row, rowIndex) => {
          const cells = [...row.cells].slice(0, 40).map(cell => clean(cell.innerText));
          if (cells.some(Boolean)) add('tablo', 'Tablo ' + (tableIndex + 1) + ' · satır ' + (rowIndex + 1), JSON.stringify(cells));
        });
      });
      document.querySelectorAll('script[type="application/ld+json"]').forEach((e, index) => {
        const value = clean(e.textContent);
        if (value) add('yapisal-veri', 'JSON-LD ' + (index + 1), value.slice(0, 50000));
      });
      return JSON.stringify({
        kaynak: location.href,
        baslik: title,
        aciklama: description,
        dil: document.documentElement.lang || '',
        taramaTarihi: new Date().toISOString(),
        ogeler: items
      });
    })()
    """#
}

private struct KazimaWeb: UIViewRepresentable {
    let kaziyici: WebKaziyici
    func makeUIView(context: Context) -> WKWebView { kaziyici.web }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct WebKazimaEkrani: View {
    let sayfa: KazimaSayfasi
    @State private var kaziyici = WebKaziyici()
    @State private var secilenler: Set<String> = []
    @State private var sorgu = ""
    @State private var tur = "tumu"
    @State private var islemde = false
    @State private var paylasim: PaylasimDosyasi?
    @Environment(\.dismiss) private var kapat

    private var turler: [String] {
        ["tumu"] + Array(Set(kaziyici.rapor?.ogeler.map(\.tur) ?? [])).sorted()
    }
    private var gorunenler: [KazimaOgesi] {
        (kaziyici.rapor?.ogeler ?? []).filter {
            (tur == "tumu" || $0.tur == tur) && (sorgu.isEmpty || $0.ad.localizedCaseInsensitiveContains(sorgu) || $0.deger.localizedCaseInsensitiveContains(sorgu))
        }
    }
    private var indirilebilir: [KazimaOgesi] {
        gorunenler.filter { $0.url != nil && ["gorsel", "video", "ses", "dosya", "altyazi"].contains($0.tur) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                KazimaWeb(kaziyici: kaziyici).frame(minHeight: 220)
                VStack(alignment: .leading, spacing: 8) {
                    Text(kaziyici.durum).font(.footnote).foregroundStyle(.secondary)
                    HStack {
                        Button(kaziyici.taraniyor ? "Taranıyor…" : "Sayfayı tara") { Task { await kaziyici.tara() } }.disabled(kaziyici.taraniyor)
                        Spacer()
                        if kaziyici.rapor != nil {
                            Button("JSON") { disariAktar(csv: false) }
                            Button("CSV") { disariAktar(csv: true) }
                        }
                    }
                    if kaziyici.rapor != nil {
                        TextField("Sonuçlarda ara", text: $sorgu).textFieldStyle(.roundedBorder)
                        Picker("Tür", selection: $tur) { ForEach(turler, id: \.self) { Text($0 == "tumu" ? "Tümü" : $0.capitalized).tag($0) } }.pickerStyle(.menu)
                        List(gorunenler) { oge in
                            HStack(alignment: .top) {
                                if oge.url != nil && ["gorsel", "video", "ses", "dosya", "altyazi"].contains(oge.tur) {
                                    Button { sec(oge) } label: { Image(systemName: secilenler.contains(oge.id) ? "checkmark.circle.fill" : "circle") }.buttonStyle(.plain)
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(oge.ad).font(.headline).lineLimit(2)
                                    Text(oge.tur).font(.caption).foregroundStyle(.secondary)
                                    Text(oge.deger).font(.caption).lineLimit(3).textSelection(.enabled)
                                }
                            }
                        }.listStyle(.plain).frame(maxHeight: 250)
                        HStack {
                            Button("Görünenlerden seç") {
                                secilenler = Set(indirilebilir.prefix(10).map(\.id))
                            }.disabled(indirilebilir.isEmpty)
                            Spacer()
                            Button(islemde ? "Ekleniyor…" : "Seçilenleri indir (\(secilenler.count))") { Task { await indir() } }
                                .disabled(islemde || secilenler.isEmpty)
                        }
                    }
                }.padding().background(.regularMaterial)
            }
            .navigationTitle("Web verisi çıkar").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Kapat") { kapat() } } }
            .sheet(item: $paylasim) { dosya in
                PaylasimSayfasi(ogeler: [dosya.url])
            }
            .task { kaziyici.ac(sayfa.url) }
            // Kimlikler her taramada baştan numaralanır: yeni raporda eski seçim başka öğelere denk gelmesin.
            .onChange(of: kaziyici.rapor?.taramaTarihi) {
                secilenler.removeAll()
                if !turler.contains(tur) { tur = "tumu" }
            }
        }
    }

    private func sec(_ oge: KazimaOgesi) {
        if secilenler.contains(oge.id) { secilenler.remove(oge.id) }
        else if secilenler.count < 10 { secilenler.insert(oge.id) }
        else { kaziyici.durum = "Aynı anda en fazla 10 dosya seçilebilir." }
    }

    private func indir() async {
        guard let rapor = kaziyici.rapor else { return }
        islemde = true
        defer { islemde = false }
        var basarili = 0
        for oge in rapor.ogeler where secilenler.contains(oge.id) && ["gorsel", "video", "ses", "dosya", "altyazi"].contains(oge.tur) {
            guard let adres = oge.url else { continue }
            do {
                let indirmeTuru = oge.tur == "video" ? "video" : oge.tur == "ses" ? "audio" : "file"
                _ = try await IndirmeYoneticisi.ortak.ekle(adres, tur: indirmeTuru)
                basarili += 1
            } catch { kaziyici.durum = "\(basarili) öğe eklendi. Son hata: \(error.localizedDescription)"; return }
        }
        secilenler.removeAll()
        kaziyici.durum = "\(basarili) dosya iPhone indirme kuyruğuna eklendi."
    }

    private func disariAktar(csv: Bool) {
        guard let rapor = kaziyici.rapor else { return }
        do {
            let uzanti = csv ? "csv" : "json"
            let ad = "Web-Verisi-\(Int(Date().timeIntervalSince1970)).\(uzanti)"
            let url = IndirmeYoneticisi.klasor.appending(path: ad)
            try KazimaDisaAktarici.veri(rapor, csv: csv).write(to: url, options: .atomic)
            IndirmeYoneticisi.ortak.yerelDosyaEkle(url: url, gorunenAd: ad)
            paylasim = PaylasimDosyasi(url: url)
        } catch { kaziyici.durum = "Dışa aktarma başarısız: \(error.localizedDescription)" }
    }
}

private struct PaylasimDosyasi: Identifiable { let id = UUID(); let url: URL }
private struct PaylasimSayfasi: UIViewControllerRepresentable {
    let ogeler: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: ogeler, applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
