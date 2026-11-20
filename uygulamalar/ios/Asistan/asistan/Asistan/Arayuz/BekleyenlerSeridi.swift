import SwiftUI

/// Çevrimdışı kuyruk şeridi: bağlantı yokken ya da bekleyen mesaj varken giriş çubuğunun üstünde görünür.
/// Başlık satırı "n mesaj bekliyor"; dokununca liste açılır (iptal ve askıdakiler için "Gönder").
struct BekleyenlerSeridi: View {
    @Environment(Beyin.self) private var beyin
    @Environment(\.colorScheme) private var sema
    @State private var acik = false

    var body: some View {
        let ogeler = beyin.bekleyenGonderiler
        let cevrimici = AgIzleyici.ortak.cevrimici
        if cevrimici && ogeler.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { acik.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Label(Self.baslik(ogeler: ogeler, cevrimici: cevrimici, not: beyin.cevrimdisiNotu), systemImage: cevrimici ? "tray.full" : "wifi.slash")
                            .accessibilityIdentifier("cevrimdisi-notu")
                        Spacer(minLength: 4)
                        if !ogeler.isEmpty {
                            Image(systemName: acik ? "chevron.up" : "chevron.down").font(.caption2.weight(.semibold))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(ogeler.isEmpty)
                .accessibilityHint(ogeler.isEmpty ? "" : "Bekleyen mesajları göster")

                if acik && !ogeler.isEmpty {
                    ForEach(Array(ogeler.enumerated()), id: \.element.id) { i, o in
                        satir(o, sira: i)
                    }
                }
            }
            .font(.footnote)
            .foregroundStyle(UyariRengi.renk(sema == .dark))
            .padding(.horizontal)
            .padding(.vertical, 2)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("bekleyenler-seridi")
            .onChange(of: ogeler.isEmpty) { _, bos in if bos { acik = false } }
        }
    }

    private func satir(_ o: BekleyenGonderi, sira i: Int) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(Self.ozet(o)).lineLimit(2).foregroundStyle(.primary)
                HStack(spacing: 6) {
                    Text(o.zaman.formatted(date: Calendar.current.isDateInToday(o.zaman) ? .omitted : .abbreviated, time: .shortened))
                    if !o.gorselAdlari.isEmpty { Label("\(o.gorselAdlari.count)", systemImage: "photo") }
                    if o.belge != nil { Image(systemName: "doc") }
                    if o.askida { Text("askıda") }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if o.askida {
                Button("Gönder") { beyin.bekleyeniSimdiGonder(o.id) }
                    .buttonStyle(.bordered).controlSize(.mini)
                    .accessibilityIdentifier("bekleyen-gonder-\(i)")
            }
            Button { withAnimation { beyin.bekleyeniIptalEt(o.id) } } label: {
                Image(systemName: "xmark").font(.caption.weight(.semibold)).frame(width: 28, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Bekleyen mesajı sil")
            .accessibilityIdentifier("bekleyen-iptal-\(i)")
        }
        .padding(.leading, 22)
    }

    /// Satır metni: ilk 60 karakter (boş metinli fotoğraf için "Fotoğraf").
    nonisolated static func ozet(_ o: BekleyenGonderi) -> String {
        let t = o.metin.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return o.gorselAdlari.isEmpty ? "(boş mesaj)" : "Fotoğraf" }
        return t.count > 60 ? String(t.prefix(60)) + "…" : t
    }

    /// Başlık satırı: kuyruk boşsa çevrimdışı notu; hepsi askıdaysa önceki sohbetten bekleyenler; yoksa sayı.
    nonisolated static func baslik(ogeler: [BekleyenGonderi], cevrimici: Bool, not: String?) -> String {
        if ogeler.isEmpty { return not ?? "Çevrimdışı: bağlantı gelince devam edilir" }
        let askida = ogeler.filter(\.askida).count
        if askida == ogeler.count { return "Önceki sohbetten \(askida) mesaj bekliyor" }
        if askida == 0, let not, !cevrimici { return not }
        let ek = askida > 0 ? " (\(askida) tanesi askıda)" : ""
        return "\(ogeler.count) mesaj bekliyor" + ek + (cevrimici ? "" : "; bağlantı gelince gidecek")
    }
}
