import SwiftUI
import WebKit

struct MedyaSayfasi: Identifiable { let id = UUID(); let url: URL; let tur: String }
struct MedyaBaglantisi: Identifiable, Decodable { var id: String { url }; let url: String; let ad: String; let tur: String }

@MainActor @Observable final class MedyaTarayici: NSObject, WKNavigationDelegate {
    let web = WKWebView(frame: .zero)
    var sonuclar: [MedyaBaglantisi] = []
    var durum = "Sayfa açılıyor…"
    var araniyor = false
    override init() { super.init(); web.navigationDelegate = self }
    func ac(_ url: URL) { web.load(URLRequest(url: url)) }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { durum = "Gerekirse videoyu oynat, ardından Medya bul’a dokun." }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) { durum = error.localizedDescription }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        // Yerel ağa/özel adrese (ya da özel ağa çözülen ada) gezinme yok; URL await'ten önce alınır.
        guard let u = navigationAction.request.url else { return .cancel }
        return await WebSayfa.gezinmeGuvenli(u) ? .allow : .cancel
    }
    func tara() async {
        araniyor = true; defer { araniyor = false }
        do {
            let result = try await web.evaluateJavaScript(Self.bulucu)
            guard let json = result as? String, let data = json.data(using: .utf8) else { throw IndirmeHatasi.metin("Medya listesi okunamadı.") }
            sonuclar = try JSONDecoder().decode([MedyaBaglantisi].self, from: data).filter { (try? IndirmeYoneticisi.dogrula($0.url)) != nil }
            durum = sonuclar.isEmpty ? "Doğrudan indirilebilir medya bulunamadı. Korumalı, şifreli veya parçalı akışlar bu yöntemle indirilemez. YouTube bağlantıları da her zaman desteklenmez." : "\(sonuclar.count) bağlantı bulundu. İndirmek istediğine dokun."
        } catch { durum = "Bu sayfadaki medya okunamadı." }
    }
    // Only addresses are read. Page text is never treated as an assistant instruction.
    static let bulucu = #"""
    (() => {
      const found = new Map();
      function add(raw, name, kind) {
        try {
          const u = new URL(raw, location.href);
          if (u.protocol !== 'https:' || u.username || u.password || raw.length > 4096) return;
          if (/\.(m3u8|mpd)(\?|$)/i.test(u.href)) return;
          if (found.size < 60) found.set(u.href, {url:u.href,ad:String(name || 'Medya').slice(0,140),tur:kind});
        } catch (_) {}
      }
      document.querySelectorAll('video,audio').forEach(e => {
        if (e.currentSrc) add(e.currentSrc, document.title, e.tagName === 'AUDIO' ? 'audio' : 'video');
        if (e.src) add(e.src, document.title, e.tagName === 'AUDIO' ? 'audio' : 'video');
        e.querySelectorAll('source').forEach(s => add(s.src, document.title, e.tagName === 'AUDIO' ? 'audio' : 'video'));
      });
      document.querySelectorAll('a[href]').forEach(e => {
        if (/\.(mp4|mov|webm|mp3|m4a|aac|wav|ogg)(\?|$)/i.test(e.href)) add(e.href, e.textContent || e.href.split('/').pop(), /\.(mp3|m4a|aac|wav|ogg)(\?|$)/i.test(e.href) ? 'audio' : 'video');
      });
      const p = window.ytInitialPlayerResponse;
      if (p && p.streamingData) {
        (p.streamingData.formats || []).forEach(f => { if (f.url && (f.audioQuality || f.audioChannels)) add(f.url, (p.videoDetails?.title || 'Video') + ' · ' + (f.qualityLabel || ''), 'video'); });
        (p.streamingData.adaptiveFormats || []).forEach(f => { if (f.url && String(f.mimeType).startsWith('audio/')) add(f.url, (p.videoDetails?.title || 'Ses') + ' · ' + (f.audioQuality || ''), 'audio'); });
      }
      return JSON.stringify([...found.values()]);
    })()
    """#
}

private struct MedyaWeb: UIViewRepresentable {
    let tarayici: MedyaTarayici
    func makeUIView(context: Context) -> WKWebView { tarayici.web }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct MedyaTarayiciEkrani: View {
    let sayfa: MedyaSayfasi
    @State private var tarayici = MedyaTarayici()
    @State private var ekleniyor = false
    @Environment(\.dismiss) private var kapat
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                MedyaWeb(tarayici: tarayici)
                VStack(alignment: .leading, spacing: 8) {
                    Text(tarayici.durum).font(.footnote).foregroundStyle(.secondary)
                    Button(tarayici.araniyor ? "Aranıyor…" : "Medya bul") { Task { await tarayici.tara() } }.disabled(tarayici.araniyor)
                    if !tarayici.sonuclar.isEmpty {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(tarayici.sonuclar.sorted { $0.tur == sayfa.tur && $1.tur != sayfa.tur }) { medya in
                                    Button {
                                        ekleniyor = true
                                        Task {
                                            defer { ekleniyor = false }
                                            do { _ = try await IndirmeYoneticisi.ortak.ekle(medya.url, tur: medya.tur); kapat() }
                                            catch { tarayici.durum = error.localizedDescription }
                                        }
                                    } label: { Label(medya.ad, systemImage: medya.tur == "audio" ? "music.note" : "film") }.disabled(ekleniyor)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(maxHeight: 160)
                    }
                }.padding().background(.regularMaterial)
            }
            .navigationTitle("Sayfadan medya bul").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Kapat") { kapat() } } }
            .task { tarayici.ac(sayfa.url) }
        }
    }
}
