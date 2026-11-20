import SwiftUI

struct GelenKutusuEkrani: View {
    /// Özet/yanıt taslağı turunun sohbet balonunda görünen kısa metni (iletinin kendisi balona yazılmaz).
    nonisolated static func gorunenMetin(_ etiket: String, gonderen: String, kaynak: String) -> String {
        let ad = gonderen.trimmingCharacters(in: .whitespacesAndNewlines)
        return "📥 \(etiket): \(ad.isEmpty ? "ileti" : String(ad.prefix(40))) · \(kaynak)"
    }
    @Environment(Beyin.self) private var beyin
    @Environment(\.dismiss) private var kapat
    @State private var kutu = GelenKutusu.ortak
    @State private var sorgu = ""
    @State private var kaynak = "Tümü"
    @State private var panoUyarisi: String?
    private var gorunen: [GelenIleti] { kutu.iletiler.filter { (kaynak == "Tümü" || $0.kaynak == kaynak) && (sorgu.isEmpty || ($0.gonderen + " " + $0.metin).localizedStandardContains(sorgu)) } }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Kaynak", selection: $kaynak) { ForEach(["Tümü", "Mail", "WhatsApp", "Mesajlar", "Bildirim", "Diğer"], id: \.self) { Text($0).tag($0) } }
                    Button("Panodaki metni ekle", systemImage: "doc.on.clipboard") {
                        guard let metin = UIPasteboard.general.string, !metin.isEmpty else { panoUyarisi = "Panoda metin yok."; return }
                        _ = kutu.ekle(kaynak: "Diğer", gonderen: nil, metin: metin); panoUyarisi = "Panodaki metin eklendi."
                    }
                    if let panoUyarisi { Text(panoUyarisi).font(.caption).foregroundStyle(.secondary) }
                } footer: { Text("Yalnız senin aktardığın içerik burada tutulur. iOS 27'de Kestirmeler bildirim otomasyonu WhatsApp ve seçtiğin diğer uygulamalardan; iletişim otomasyonları Mail ve Mesajlar'dan içerik aktarabilir. Paylaş/Kopyala da kullanılabilir.") }
                if let hata = kutu.hata { Text(hata).foregroundStyle(.red).font(.footnote) }
                ForEach(gorunen) { ileti in
                    NavigationLink { IletiAyrintiEkrani(ileti: ileti) } label: {
                        HStack(alignment: .top) {
                            Image(systemName: ileti.okundu ? "envelope.open" : "envelope.badge").foregroundStyle(ileti.okundu ? Color.secondary : Color.blue)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack { Text(ileti.gonderen).font(.headline); Spacer(); Text(ileti.kaynak).font(.caption).foregroundStyle(.secondary) }
                                Text(ileti.metin).lineLimit(3).foregroundStyle(ileti.okundu ? .secondary : .primary)
                                Text(ileti.tarih, style: .relative).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }.swipeActions { Button(ileti.okundu ? "Yeni" : "Okundu") { kutu.okundu(ileti.id, !ileti.okundu) }.tint(.blue); Button("Sil", role: .destructive) { kutu.sil(ileti.id) } }
                }
                if gorunen.isEmpty { ContentUnavailableView("Aktarılmış ileti yok", systemImage: "tray", description: Text("Kurulum rehberini aç veya bir iletiyi kopyalayıp ekle.")) }
                Section("Kurulum") {
                    NavigationLink("Bildirim, Mail ve Mesaj otomasyonu") { GelenKutusuKurulumEkrani() }
                    Text("Asistan Bildirim Merkezi geçmişini veya WhatsApp gelen kutusunu topluca taramaz. Seçtiğin Kestirmeler otomasyonu yeni bildirim geldiği anda içeriği aktarabilir; eski iletiler Paylaş/Kopyala ile eklenir.").font(.footnote).foregroundStyle(.secondary)
                }
            }.navigationTitle("Gelen Kutusu · \(kutu.okunmamis) yeni").searchable(text: $sorgu, prompt: "Gönderen veya içerik ara")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Tamam") { kapat() } } }
        }
    }
}

private struct IletiAyrintiEkrani: View {
    @Environment(Beyin.self) private var beyin
    let ileti: GelenIleti
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 16) {
            LabeledContent("Kaynak", value: ileti.kaynak); LabeledContent("Gönderen", value: ileti.gonderen); Text(ileti.metin).textSelection(.enabled)
            Button("Özetle", systemImage: "text.alignleft") { gonder("Özetle", gorev: "Şu \(ileti.kaynak) iletisini kısa maddelerle özetle:") }
                .buttonStyle(.borderedProminent).disabled(beyin.durum != .bosta)
            Button("Yanıt taslağı hazırla", systemImage: "arrowshape.turn.up.left") { gonder("Yanıt taslağı", gorev: "\(ileti.gonderen) tarafından gelen şu \(ileti.kaynak) iletisine uygun bir yanıt taslağı hazırla:") }
                .buttonStyle(.bordered).disabled(beyin.durum != .bosta)
            ShareLink(item: ileti.metin) { Label("Paylaş", systemImage: "square.and.arrow.up") }
        }.padding() }.navigationTitle(ileti.gonderen).onAppear { GelenKutusu.ortak.okundu(ileti.id) }
    }

    /// Üçüncü kişinin iletisi güvenilmeyen içeriktir: tur dış kaynaklı gönderilir, yan etkili adımlar kullanıcıya sorulur.
    /// (Yazı alanına taslak olarak bırakılsaydı gönderim kullanıcının kendi komutu sayılırdı.)
    private func gonder(_ etiket: String, gorev: String) {
        beyin.gonder(GelenIleti.istem(ileti, gorev: gorev),
                     gorunenMetin: GelenKutusuEkrani.gorunenMetin(etiket, gonderen: ileti.gonderen, kaynak: ileti.kaynak),
                     disKaynak: true)
        GelenKutusu.ortak.ekranAcik = false
    }
}

struct GelenKutusuKurulumEkrani: View {
    var body: some View {
        List {
            Section {
                Link("Kestirmeler Otomasyonlarını aç", destination: URL(string: "shortcuts://automations")!)
            } footer: { Text("Hazır Asistan eylemleri yüklüdür. iOS, kişisel tetikleyiciyi yalnız Kestirmeler uygulamasında cihaz sahibi oluşturduğunda kaydeder.") }
            Section("WhatsApp ve diğer bildirimler · iOS 27") { Text("1. Kestirmeler → Otomasyon → Yeni Otomasyon → Bildirim'i aç."); Text("2. Uygulama olarak WhatsApp'ı veya istediğin uygulamayı seç; gerekirse başlık, alt başlık ya da mesaj filtresi ekle."); Text("3. WhatsApp için ‘WhatsApp bildirimini kaydet’; diğer uygulamalar için ‘Gelen iletiyi kaydet’ eylemini ekle. Bildirim başlığını Gönderen'e, mesajını İçerik'e bağla."); Text("4. Otomasyonu ‘Hemen Çalıştır’ olarak ayarla. Aynı kurulumu başka uygulamalar için tekrarlayabilirsin.") }
            Section("Mail / Mesajlar") { Text("1. Kestirmeler → Otomasyon → Yeni Otomasyon'u aç."); Text("2. E-posta veya Mesaj tetikleyicisini seç; gönderen ve koşulları belirle."); Text("3. ‘Mail iletisini kaydet’ veya ‘Mesajlar iletisini kaydet’ eylemini ekle. Tetikleyicinin gönderen ve içerik değişkenlerini eş alanlara bağla."); Text("4. ‘Hemen Çalıştır’ seçeneğini aç.") }
            Section("Eski iletiler") { Text("İletiye uzun basıp Kopyala; Asistan → Gelen Kutusu → Panodaki metni ekle yolunu kullan. Paylaş menüsündeki bir Kestirme de aynı eyleme metni aktarabilir.") }
            Section("Gizlilik") { Text("Aktarılan metin iPhone'da dosya korumasıyla saklanır. Model yalnız sen özet veya yanıt istediğinde içeriği işler. Parola, doğrulama kodu ve kart bilgisi aktarma.") }
        }.navigationTitle("Otomasyon kurulumu")
    }
}
