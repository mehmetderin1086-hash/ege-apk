import SwiftUI
import AVFAudio

/// P2.3: giriş çubuğunun üstündeki tek durum iletisi (model hatası, mikrofon, çevrimdışı, kota, ses, kişisel alan).
/// Yeni ileti eklerken `DurumSecici.adaylar`'a tür olarak ekle; öncelik `Tur` sırasıdır (küçük değer = yüksek öncelik).
nonisolated struct DurumBildirimi: Identifiable, Equatable, Sendable {
    nonisolated enum Tur: Int, Comparable, Sendable {
        case modelHatasi, mikrofon, cevrimdisi, kota, ses, kisisel
        static func < (a: Tur, b: Tur) -> Bool { a.rawValue < b.rawValue }
        var ad: String {
            switch self {
            case .modelHatasi: "modelHatasi"
            case .mikrofon: "mikrofon"
            case .cevrimdisi: "cevrimdisi"
            case .kota: "kota"
            case .ses: "ses"
            case .kisisel: "kisisel"
            }
        }
    }
    nonisolated enum Eylem: String, Sendable {
        case yenidenDene, baskaModel, baglantiyiSina, bekleyenleriIptal, mikrofonuYenidenBaslat, ayarlariAc
        var etiket: String {
            switch self {
            case .yenidenDene: "Yeniden dene"
            case .baskaModel: "Başka model"
            case .baglantiyiSina: "Bağlantıyı sına"
            case .bekleyenleriIptal: "Bekleyenleri sil"
            case .mikrofonuYenidenBaslat: "Mikrofonu başlat"
            case .ayarlariAc: "Ayarları aç"
            }
        }
        var simge: String {
            switch self {
            case .yenidenDene: "arrow.clockwise"
            case .baskaModel: "cpu"
            case .baglantiyiSina: "network"
            case .bekleyenleriIptal: "trash"
            case .mikrofonuYenidenBaslat: "mic"
            case .ayarlariAc: "gear"
            }
        }
    }
    /// Tür + metin: aynı ileti kapatılınca yeniden çıkmaz, metni değişen yeni ileti yeniden görünür.
    let id: String
    let tur: Tur
    let metin: String
    let simge: String
    let eylemler: [Eylem]
    let kapatilabilir: Bool

    init(tur: Tur, metin: String, simge: String, eylemler: [Eylem] = [], kapatilabilir: Bool = true) {
        self.id = "\(tur.ad):\(metin)"
        self.tur = tur
        self.metin = metin
        self.simge = simge
        self.eylemler = eylemler
        self.kapatilabilir = kapatilabilir
    }
}

/// Saf seçim: o anki durumlardan aday iletileri üretir ve en öncelikli kapatılmamış olanı seçer.
nonisolated enum DurumSecici {
    static func adaylar(sonHata: String?, hataTuru: HataTuru?, cevrimici: Bool, cevrimdisiNotu: String?, bekleyenSayisi: Int,
                        kota: String?, sesHatasi: String?, kisiselHata: String?, mikrofonHatasi: String?, mikrofonIzniYok: Bool) -> [DurumBildirimi] {
        var a: [DurumBildirimi] = []
        if let h = sonHata?.trimmingCharacters(in: .whitespacesAndNewlines), !h.isEmpty {
            let t = hataTuru ?? .bilinmeyen
            var e: [DurumBildirimi.Eylem] = [.yenidenDene, .baskaModel]
            if t == .baglanti || t == .yetki { e.append(.baglantiyiSina) }
            a.append(DurumBildirimi(tur: .modelHatasi, metin: h, simge: hataSimgesi(t), eylemler: e))
        }
        if mikrofonIzniYok || mikrofonHatasi != nil {
            let m = mikrofonIzniYok ? "Mikrofon izni kapalı. Sesli komut için Ayarlar'dan izin ver." : (mikrofonHatasi ?? "")
            a.append(DurumBildirimi(tur: .mikrofon, metin: m, simge: "mic.slash", eylemler: mikrofonIzniYok ? [.ayarlariAc] : [.mikrofonuYenidenBaslat]))
        }
        if !cevrimici || cevrimdisiNotu != nil {
            let m = cevrimdisiNotu ?? (bekleyenSayisi > 0 ? "Bağlantı yok. \(bekleyenSayisi) mesaj bekliyor." : "Bağlantı yok.")
            a.append(DurumBildirimi(tur: .cevrimdisi, metin: m, simge: "wifi.slash", eylemler: bekleyenSayisi > 0 ? [.bekleyenleriIptal] : []))
        }
        if let k = kota, !k.isEmpty {
            a.append(DurumBildirimi(tur: .kota, metin: k, simge: "gauge.with.dots.needle.100percent", eylemler: [.baskaModel]))
        }
        if let s = sesHatasi, !s.isEmpty { a.append(DurumBildirimi(tur: .ses, metin: s, simge: "speaker.slash")) }
        if let h = kisiselHata, !h.isEmpty { a.append(DurumBildirimi(tur: .kisisel, metin: h, simge: "person.crop.circle.badge.exclamationmark")) }
        return a
    }

    /// Kapatılmamış adaylardan önceliği en yüksek olan ve geride kalan (gösterilmeyen) ileti sayısı.
    static func sec(_ a: [DurumBildirimi], kapatilanlar: Set<String>) -> (DurumBildirimi?, ek: Int) {
        let kalan = a.filter { !kapatilanlar.contains($0.id) }
        guard let ilk = kalan.enumerated().min(by: { ($0.element.tur, $0.offset) < ($1.element.tur, $1.offset) })?.element else { return (nil, 0) }
        return (ilk, kalan.count - 1)
    }

    static func hataSimgesi(_ t: HataTuru) -> String {
        switch t {
        case .yetki: "person.badge.key"
        case .kota: "gauge.with.dots.needle.100percent"
        case .sunucu: "server.rack"
        case .baglanti: "wifi.exclamationmark"
        case .zamanAsimi: "clock.badge.exclamationmark"
        case .baglam: "text.badge.xmark"
        case .kimlik: "key"
        case .bilinmeyen: "exclamationmark.triangle"
        }
    }
}

/// "Yeniden dene" onayı bekleyen istek (yan etkili turda): `model` nil ise model zorlanmaz.
struct YenidenDenemeIstegi: Identifiable {
    let id = UUID()
    let model: String?
}

/// Tek satırlık durum şeridi: simge + en çok 2 satır metin + kapat; altında eylem düğmeleri (varsa).
/// Kimlikler: `durum-seridi`, `durum-eylem-<rawValue>`, `durum-kapat`, `durum-ek`.
struct DurumSeridi: View {
    let bildirim: DurumBildirimi
    let ek: Int
    let eylem: (DurumBildirimi.Eylem) -> Void
    let baskaModel: (String) -> Void
    let kapat: () -> Void
    @Environment(\.colorScheme) private var sema

    /// Mikrofon izni kalıcı olarak reddedilmiş mi (sistem sorusu artık çıkmaz; Ayarlar'a gönderilir).
    static func mikrofonIzniYok() -> Bool { AVAudioApplication.shared.recordPermission == .denied }

    var body: some View {
        let renk: Color = bildirim.tur == .modelHatasi ? .red : UyariRengi.renk(sema == .dark)
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: bildirim.simge).accessibilityHidden(true)
                Text(bildirim.metin).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                if ek > 0 {
                    Text("+\(ek)").font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(renk.opacity(0.15)))
                        .accessibilityLabel("\(ek) uyarı daha")
                        .accessibilityIdentifier("durum-ek")
                }
                if bildirim.kapatilabilir {
                    Button(action: kapat) { Image(systemName: "xmark").font(.caption.weight(.semibold)).padding(4).contentShape(Rectangle()) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Kapat")
                        .accessibilityIdentifier("durum-kapat")
                }
            }
            .font(.footnote)
            .foregroundStyle(renk)
            if !bildirim.eylemler.isEmpty {
                // Büyük yazı boyutunda düğmeler yan yana sığmazsa alt alta dizilir.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        ForEach(bildirim.eylemler, id: \.self) { e in dugme(e) }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(bildirim.eylemler, id: \.self) { e in dugme(e) }
                    }
                }
                .font(.caption)
                .controlSize(.small)
                .buttonStyle(.bordered)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
        }
        .padding(.horizontal).padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("durum-seridi")
    }

    @ViewBuilder
    private func dugme(_ e: DurumBildirimi.Eylem) -> some View {
        if e == .baskaModel {
            Menu {
                ForEach(Beyin.yenidenUretModelleri, id: \.self) { m in
                    Button(Beyin.modelEtiketi(m)) { baskaModel(m) }
                }
            } label: {
                Label(e.etiket, systemImage: e.simge)
            }
            .accessibilityIdentifier("durum-eylem-\(e.rawValue)")
        } else {
            Button { eylem(e) } label: { Label(e.etiket, systemImage: e.simge) }
                .accessibilityIdentifier("durum-eylem-\(e.rawValue)")
        }
    }
}
