import Foundation
import Observation

/// P3.3: yanıtın hangi yoldan (yerel, müzik, yarış, atölye, sunucu, araştırma, zincir),
/// hangi kip ve çabayla, hangi araçlar başarıyla çalışarak üretildiği. Kalite kaydına ve değerlendirme setine yazılır.
nonisolated struct YanitIzi: Equatable, Codable, Sendable {
    var yol: String
    var kip: String
    var caba: String?
    var araclar: [String]
}

/// P3.3: yanıt kalitesi geri bildirimi. Açık sinyal (balon altındaki beğeni/beğenmeme) ve örtük sinyaller
/// (Durdur, yeniden üret, "hayır/yanlış anladın" itirazı) model ve yol bazında sayılır.
/// Kullanıcının ya da yanıtın METNİ yazılmaz; yalnız olay, model etiketi ve iz. Application Support/kalite.json, en çok 500 kayıt.
@MainActor @Observable
final class KaliteDefteri {
    static let ortak = KaliteDefteri()

    nonisolated enum Olay: Codable, Equatable, Sendable {
        case begeni
        case begenmeme(neden: String)
        case durdur
        case yenidenUret
        case itiraz
    }

    nonisolated struct Kayit: Codable, Equatable, Identifiable, Sendable {
        var id = UUID()
        let zaman: Date
        let olay: Olay
        /// Balonda görünen model etiketi (`Beyin.modelEtiketi`); hızlı yollarda "iPhone · …".
        let model: String?
        let yol: String?
        let kip: String?
        let caba: String?
        let araclar: [String]
    }

    /// Model bazlı özet satırı (Kalite ekranı).
    nonisolated struct ModelOzeti: Equatable, Identifiable, Sendable {
        let model: String
        var begeni = 0
        var begenmeme = 0
        var itiraz = 0
        var durdur = 0
        var yenidenUret = 0
        var id: String { model }
        var toplam: Int { begeni + begenmeme + itiraz + durdur + yenidenUret }
    }

    /// Beğenmeme nedeni seçenekleri (balondaki diyalog; sıra sabit).
    nonisolated static let nedenler = ["Yanlış bilgi", "İşi yapmadı", "Yanlış araç", "Çok uzun", "Yavaş", "Diğer"]
    nonisolated static let enFazlaKayit = 500

    private(set) var kayitlar: [Kayit] = []
    /// Bu oturumda balonda verilen oy (mesaj kimliği → beğendi mi). Yalnız simgenin dolu çizilmesi için; kalıcı değil.
    private(set) var oylar: [UUID: Bool] = [:]
    private let dosya: URL

    init(dosya: URL? = nil) {
        if let dosya {
            self.dosya = dosya
        } else if OnayKapisi.testte {
            // Birim/arayüz testleri gerçek kalite kayıtlarını kirletmesin.
            self.dosya = FileManager.default.temporaryDirectory.appendingPathComponent("kalite-\(UUID().uuidString).json")
        } else {
            let taban = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
            self.dosya = taban.appendingPathComponent("kalite.json")
        }
        kayitlar = (try? Data(contentsOf: self.dosya)).flatMap { try? Self.cozucu.decode([Kayit].self, from: $0) } ?? []
    }

    /// Olayı kaydeder; en yeni kayıt sondadır, 500'ü aşan en eskiler atılır.
    func kaydet(_ olay: Olay, model: String?, iz: YanitIzi?, zaman: Date = .now) {
        // Dosya iso8601 (saniye) yazar: bellekteki kayıt da saniyeye yuvarlanır, yeniden yüklenen kayıtlar eşit kalır.
        let zaman = Date(timeIntervalSince1970: zaman.timeIntervalSince1970.rounded(.down))
        kayitlar.append(Kayit(zaman: zaman, olay: olay, model: model, yol: iz?.yol, kip: iz?.kip, caba: iz?.caba, araclar: iz?.araclar ?? []))
        if kayitlar.count > Self.enFazlaKayit { kayitlar.removeFirst(kayitlar.count - Self.enFazlaKayit) }
        yaz()
    }

    /// Balondaki beğeni/beğenmeme. Aynı mesajda aynı oy ikinci kez sayılmaz; fikir değişirse yeni oy eklenir.
    func oyla(_ mesajID: UUID, begendi: Bool, neden: String? = nil, model: String?, iz: YanitIzi?) {
        if oylar[mesajID] == begendi, begendi { return }
        oylar[mesajID] = begendi
        kaydet(begendi ? .begeni : .begenmeme(neden: neden ?? "Diğer"), model: model, iz: iz)
    }

    func temizle() {
        kayitlar = []
        oylar = [:]
        yaz()
    }

    /// Son `gun` günün model bazlı özeti.
    func ozet(gun: Int = 7, simdi: Date = .now) -> [ModelOzeti] { Self.ozetle(kayitlar, gun: gun, simdi: simdi) }

    /// Saf özet: son `gun` gün içindeki kayıtlar model etiketine göre toplanır; en çok olaylı model başta.
    nonisolated static func ozetle(_ kayitlar: [Kayit], gun: Int = 7, simdi: Date = .now) -> [ModelOzeti] {
        let esik = simdi.addingTimeInterval(-Double(gun) * 86_400)
        var tablo: [String: ModelOzeti] = [:]
        for k in kayitlar where k.zaman >= esik && k.zaman <= simdi.addingTimeInterval(60) {
            let ad = k.model ?? "Bilinmeyen"
            var o = tablo[ad] ?? ModelOzeti(model: ad)
            switch k.olay {
            case .begeni: o.begeni += 1
            case .begenmeme: o.begenmeme += 1
            case .itiraz: o.itiraz += 1
            case .durdur: o.durdur += 1
            case .yenidenUret: o.yenidenUret += 1
            }
            tablo[ad] = o
        }
        return tablo.values.sorted { $0.toplam != $1.toplam ? $0.toplam > $1.toplam : $0.model < $1.model }
    }

    /// Saf: son `gun` gündeki beğenmeme nedenlerinin sayısı (en çoktan aza).
    nonisolated static func nedenSayilari(_ kayitlar: [Kayit], gun: Int = 7, simdi: Date = .now) -> [(neden: String, sayi: Int)] {
        let esik = simdi.addingTimeInterval(-Double(gun) * 86_400)
        var sayac: [String: Int] = [:]
        for k in kayitlar where k.zaman >= esik { if case .begenmeme(let n) = k.olay { sayac[n, default: 0] += 1 } }
        return sayac.map { (neden: $0.key, sayi: $0.value) }.sorted { $0.sayi != $1.sayi ? $0.sayi > $1.sayi : $0.neden < $1.neden }
    }

    /// Saf karar: istek bir önceki yanıta itiraz mı ("Hayır", "Yanlış anladın", "Olmadı", "Öyle değil", "Bu değil").
    /// "Hayırlı olsun", "yanlışlık nedir", "hayır teşekkürler" itiraz sayılmaz.
    nonisolated static func itirazMi(_ metin: String) -> Bool {
        let s = AtolyeYonlendirme.normalize(metin)
        guard !s.isEmpty, s.count <= 400, !s.contains("tesekkur"), !s.contains("sag ol") else { return false }
        return s.range(of: #"^(hayir|yanlis anladin|yanlis|olmadi|oyle degil|bu degil)\b"#, options: .regularExpression) != nil
    }

    // MARK: Kalıcılık

    nonisolated private static let yazmaKuyrugu = DispatchQueue(label: "asistan.kalite-defteri", qos: .utility)
    nonisolated private static var kodlayici: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }
    nonisolated private static var cozucu: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }

    /// Yazımlar tek seri kuyrukta, sırayla (AjanDefteri deseni): eski anlık görüntü yenisinin üstüne yazılamaz.
    private func yaz() {
        let v = kayitlar, url = dosya
        Self.yazmaKuyrugu.async { try? Self.kodlayici.encode(v).write(to: url, options: .atomic) }
    }

    /// Test: bekleyen yazımların bitmesini bekler.
    nonisolated static func yazimlariBekle() { yazmaKuyrugu.sync {} }
}

extension Beyin {
    /// P3.3: şu anki (ya da az önce biten) isteğin izi. Araçlar AjanDefteri'nin etkin görevinde 'Tamam' biten adımlardır;
    /// kısa yollar (müzik) araç sarmalayıcısından geçmediği için orada araç listesi boş kalır, yol adı yeterlidir.
    func yanitIzi() -> YanitIzi {
        let araclar = AjanDefteri.ortak.gorevler.first?.adimlar.filter { $0.durum == "Tamam" }.map(\.arac) ?? []
        var tekil: [String] = []
        for a in araclar where !tekil.contains(a) { tekil.append(a) }
        return YanitIzi(yol: sonYonlendirme, kip: aktifKip.rawValue, caba: (uygulananCaba ?? secilenCaba)?.rawValue, araclar: tekil)
    }
}
