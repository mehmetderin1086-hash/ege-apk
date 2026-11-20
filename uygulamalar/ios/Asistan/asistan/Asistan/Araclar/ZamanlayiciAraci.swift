import Foundation
import FoundationModels
import AlarmKit
import SwiftUI

/// AlarmKit: geri sayım zamanlayıcısı ve saatli alarm. Kilit ekranı/Dynamic Island'da görünür, uygulama kapalıyken çalar.
nonisolated struct ZamanlayiciAraci: Tool {
    let name = "zamanlayici"
    let description = "Zamanlayıcı kurar ('zamanlayici', saniye cinsinden süre), belirli saate alarm kurar ('alarm', ISO 8601 zaman), kurulu olanları listeler ('listele') ya da iptal eder ('iptal': baslik etiketi eşleşenleri iptal eder, 'hepsi' tümünü; etiket yoksa 'zamanlayıcı' ya da 'alarm' türü seçer)."

    @Generable
    struct Arguments {
        @Guide(description: "'zamanlayici', 'alarm', 'listele' ya da 'iptal'") var islem: String
        @Guide(description: "zamanlayici: süre saniye (örn. 5 dakika = 300)") var saniye: Int?
        @Guide(description: "alarm: yerel saatte ISO 8601 zaman") var zaman: String?
        @Guide(description: "Etiket (örn. 'Çay', 'Toplantı'); iptal: iptal edilecek kaydın etiketi ya da 'hepsi'") var baslik: String?
    }

    /// AlarmKit etiketi geri vermez: kurulan her kaydın etiketi ve hedef zamanı burada tutulur (kimlik → kayıt).
    nonisolated struct AlarmKaydi: Codable, Sendable { var baslik: String; var hedef: Date }
    static let kayitAnahtari = "asistan.alarmKayitlari"
    static func kayitlar() -> [String: AlarmKaydi] {
        guard let d = UserDefaults.standard.data(forKey: kayitAnahtari),
              let k = try? JSONDecoder().decode([String: AlarmKaydi].self, from: d) else { return [:] }
        return k
    }
    static func kayitlariYaz(_ k: [String: AlarmKaydi]) {
        if let d = try? JSONEncoder().encode(k) { UserDefaults.standard.set(d, forKey: kayitAnahtari) }
    }
    static let kayitKilidi = NSLock()
    /// Oku-değiştir-yaz tek kritik bölgede: paralel araç çağrıları (`call` @concurrent) birbirinin kaydını ezmesin.
    /// `kayitlar`/`kayitlariYaz` araçta yalnız buradan çağrılır. Kapanışta `await` yok; kilit kısa tutulur.
    @discardableResult
    static func kayitlariGuncelle<R>(_ degistir: (inout [String: AlarmKaydi]) throws -> R) rethrows -> R {
        kayitKilidi.lock(); defer { kayitKilidi.unlock() }
        var k = kayitlar()
        let r = try degistir(&k)
        kayitlariYaz(k)
        return r
    }

    static func durumAdi(_ s: Alarm.State) -> String {
        switch s {
        case .scheduled: return "bekliyor"
        case .countdown: return "geri sayıyor"
        case .paused: return "duraklatıldı"
        case .alerting: return "çalıyor"
        @unknown default: return "bilinmiyor"
        }
    }

    nonisolated enum IptalSecimi: Equatable { case bos, iptal([UUID]), eslesmeYok, belirsiz }

    /// Türkçe küçük harf + aksan katlama: "HEPSI" → "hepsi", "Tümünü" → "tumunu", "zamanlayıcıyı" → "zamanlayiciyi".
    static func katla(_ s: String) -> String {
        let tr = Locale(identifier: "tr_TR")
        return s.lowercased(with: tr).replacingOccurrences(of: "ı", with: "i").folding(options: [.diacriticInsensitive], locale: tr)
    }
    static let hepsiSozleri: Set<String> = ["hepsi", "hepsini", "tumu", "tumunu", "tum", "butun", "butunu", "tamami", "tamamini", "all"]
    /// Tür sözcüğü: "zamanlayıcı(yı)/sayaç/timer" → true (zamanlayıcı), "alarm(ı)" → false (saatli alarm), başka → nil.
    static func turSozu(_ katlanmis: String) -> Bool? {
        if ["zamanlay", "sayac", "timer"].contains(where: { katlanmis.hasPrefix($0) }) { return true }
        return katlanmis.hasPrefix("alarm") ? false : nil
    }

    /// İptal edilecekleri seçer: etiket eşleşenler; boş etikette yalnız tek kayıt varsa o; 'hepsi'/'tüm alarmlar' tümü.
    /// `zamanlayicilar` (zamanlayıcı kimlikleri) verilirse tür sözcüğü yedek süzgeçtir: "tüm zamanlayıcıları" yalnız zamanlayıcıları,
    /// etiket tutmayan "alarmı" tek aday varsa onu seçer. Belirsizlikte hiçbir şey silinmez.
    static func iptalSecimi(_ ogeler: [(id: UUID, baslik: String)], baslik: String?, zamanlayicilar: Set<UUID>? = nil) -> IptalSecimi {
        guard !ogeler.isEmpty else { return .bos }
        let b = (baslik ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let sozler = Self.katla(b).split(whereSeparator: \.isWhitespace).map(String.init)
        func turdekiler(_ tur: Bool, _ z: Set<UUID>) -> [UUID] { ogeler.filter { z.contains($0.id) == tur }.map { $0.id } }
        if let ilk = sozler.first, Self.hepsiSozleri.contains(ilk), sozler.dropFirst().allSatisfy({ Self.turSozu($0) != nil }) {
            let turler = Set(sozler.dropFirst().compactMap { Self.turSozu($0) })
            if turler.count == 1, let tur = turler.first, let z = zamanlayicilar {
                let t = turdekiler(tur, z)
                return t.isEmpty ? .eslesmeYok : .iptal(t)
            }
            return .iptal(ogeler.map { $0.id })
        }
        if b.isEmpty { return ogeler.count == 1 ? .iptal([ogeler[0].id]) : .belirsiz }
        let e = ogeler.filter { $0.baslik.localizedStandardContains(b) }.map { $0.id }
        if !e.isEmpty { return .iptal(e) }
        // Etiket tutmadıysa tek tür sözcüğü ("zamanlayıcıyı", "alarmı"): yalnız tek aday varsa o; çoksa sorulur.
        guard let z = zamanlayicilar, sozler.count == 1, let tur = Self.turSozu(sozler[0]) else { return .eslesmeYok }
        let t = turdekiler(tur, z)
        return t.isEmpty ? .eslesmeYok : (t.count == 1 ? .iptal(t) : .belirsiz)
    }

    func call(arguments a: Arguments) async throws -> String {
        let y = AlarmManager.shared
        switch a.islem.lowercased() {
        case "listele", "iptal":
            // Alarm listesi kilidin içinde okunur: kurulum kaydını schedule'dan SONRA kilitle yazdığı için taze kayıt budanmaz.
            let (l, kayitli) = try Self.kayitlariGuncelle { (k: inout [String: AlarmKaydi]) throws -> ([Alarm], [String: AlarmKaydi]) in
                let guncel = try y.alarms
                k = k.filter { kayit in guncel.contains { $0.id.uuidString == kayit.key } }   // biten/silinen kayıtları temizle
                return (guncel, k)
            }
            func satir(_ al: Alarm) -> String {
                var hedef = kayitli[al.id.uuidString]?.hedef
                if hedef == nil, case .fixed(let d)? = al.schedule { hedef = d }
                let tur = al.schedule == nil ? " (zamanlayıcı)" : " (alarm)"
                return "• \(kayitli[al.id.uuidString]?.baslik ?? "(etiketsiz)")\(tur)" + (hedef.map { " — \(AracYardim.kisa($0))" } ?? "") + " — \(Self.durumAdi(al.state))"
            }
            if a.islem.lowercased() == "listele" {
                return l.isEmpty ? "Kurulu alarm ya da zamanlayıcı yok." : "\(l.count) kayıt:\n" + l.map(satir).joined(separator: "\n")
            }
            let liste = l.map(satir).joined(separator: "\n")
            let zamanlayicilar = Set(l.filter { $0.schedule == nil }.map { $0.id })
            switch Self.iptalSecimi(l.map { (id: $0.id, baslik: kayitli[$0.id.uuidString]?.baslik ?? "") }, baslik: a.baslik, zamanlayicilar: zamanlayicilar) {
            case .bos:
                return "İptal edilecek bir şey yok."
            case .eslesmeYok:
                return "'\(a.baslik ?? "")' etiketiyle eşleşen kayıt yok; hiçbir şey iptal edilmedi. Tümü için baslik='hepsi' ver; (etiketsiz) kayıtlar 'hepsi' ya da tür sözcüğüyle ('zamanlayıcı'/'alarm') seçilir. Kurulu olanlar:\n\(liste)"
            case .belirsiz:
                return "Birden çok kayıt var; hangisi iptal edilsin? Etiketi baslik'e yaz ya da tümü için baslik='hepsi' ver. Kurulu olanlar:\n\(liste)"
            case .iptal(let idler):
                var tamam: [String] = [], silinen: [String] = [], hatali = 0
                for id in idler {
                    do {
                        try y.cancel(id: id)
                        tamam.append(kayitli[id.uuidString]?.baslik ?? "(etiketsiz)")
                        silinen.append(id.uuidString)
                    } catch { hatali += 1 }
                }
                // Bayat kopya geri yazılmaz: yalnız iptal edilenler silinir (arada kurulan kaydın etiketi korunur).
                if !silinen.isEmpty { Self.kayitlariGuncelle { (k: inout [String: AlarmKaydi]) -> Void in for s in silinen { k[s] = nil } } }
                let hataNotu = hatali > 0 ? " \(hatali) kayıt iptal edilemedi." : ""
                return tamam.isEmpty ? "Hiçbir kayıt iptal edilemedi.\(hataNotu)" : "\(tamam.count) alarm/zamanlayıcı iptal edildi: \(tamam.joined(separator: ", ")).\(hataNotu)"
            }
        default: break
        }
        let durum = try await y.requestAuthorization()
        guard durum == .authorized else {
            await IzinKarti.ekle(.alarm)
            return "Alarm izni verilmedi. Ayarlar > Asistan'dan açın."
        }
        let etiket = (a.baslik?.isEmpty == false ? a.baslik! : (a.islem.lowercased() == "alarm" ? "Alarm" : "Zamanlayıcı"))
        // P2.14: çalarken ikinci düğme "Ertele 10 dk" geri sayımı (postAlert) başlatır; Durdur'u sistem kendisi gösterir
        // (stopButton iOS 26.1'den beri kullanılmıyor).
        let uyarı = AlarmPresentation.Alert(title: LocalizedStringResource(stringLiteral: etiket), secondaryButton: Self.erteleDugmesi,
                                            secondaryButtonBehavior: .countdown)
        let meta = AsistanAlarmMeta(baslik: etiket)
        switch a.islem.lowercased() {
        case "zamanlayici":
            guard let sn = a.saniye, sn >= 5, sn <= 86400 else { return "Süre 5 saniye ile 24 saat arasında olmalı (saniye)." }
            let sunum = AlarmPresentation(alert: uyarı, countdown: .init(title: LocalizedStringResource(stringLiteral: etiket), pauseButton: AlarmButton(text: "Duraklat", textColor: .white, systemImageName: "pause.fill")),
                                          paused: .init(title: LocalizedStringResource(stringLiteral: "Duraklatıldı"), resumeButton: AlarmButton(text: "Sürdür", textColor: .white, systemImageName: "play.fill")))
            let oznitelik = AlarmAttributes(presentation: sunum, metadata: meta, tintColor: .orange)
            let id = UUID()
            let ayar = AlarmManager.AlarmConfiguration(countdownDuration: Alarm.CountdownDuration(preAlert: TimeInterval(sn), postAlert: Self.erteleSn), attributes: oznitelik)
            _ = try await y.schedule(id: id, configuration: ayar)
            let hedef = Date.now.addingTimeInterval(TimeInterval(sn))
            Self.kayitlariGuncelle { $0[id.uuidString] = AlarmKaydi(baslik: etiket, hedef: hedef) }
            await EylemKaydi(tur: .zamanlayici, baslik: etiket, ozet: "\(Self.sure(sn)) · bitiş \(AracYardim.kisa(hedef))",
                             kimlikler: [id.uuidString], acAdresi: EylemKaydi.alarmAdresi).kartaEkle()
            return "\(Self.sure(sn)) zamanlayıcı kuruldu: \(etiket).\(EylemKaydi.geriAlNotu)"
        case "alarm":
            guard !AracYardim.yalnizGun(a.zaman) else { return "Alarm için saat gerekli (ör. 2026-10-21T07:00)." }
            guard let z = a.zaman.flatMap(AracYardim.tarih) else { return "Alarm zamanı anlaşılmadı." }
            guard z > .now else { return "Bu zaman geçmişte: \(AracYardim.kisa(z))." }
            // Erteleme geri sayımı için countdown/paused görünümü ("Ertelendi", Duraklat/Sürdür).
            let sunum = AlarmPresentation(alert: uyarı, countdown: .init(title: LocalizedStringResource(stringLiteral: "Ertelendi"), pauseButton: AlarmButton(text: "Duraklat", textColor: .white, systemImageName: "pause.fill")),
                                          paused: .init(title: LocalizedStringResource(stringLiteral: "Duraklatıldı"), resumeButton: AlarmButton(text: "Sürdür", textColor: .white, systemImageName: "play.fill")))
            let oznitelik = AlarmAttributes(presentation: sunum, metadata: meta, tintColor: .orange)
            let ayar = AlarmManager.AlarmConfiguration(countdownDuration: Alarm.CountdownDuration(preAlert: nil, postAlert: Self.erteleSn), schedule: .fixed(z), attributes: oznitelik)
            let id = UUID()
            _ = try await y.schedule(id: id, configuration: ayar)
            Self.kayitlariGuncelle { $0[id.uuidString] = AlarmKaydi(baslik: etiket, hedef: z) }
            await EylemKaydi(tur: .alarm, baslik: etiket, ozet: AracYardim.kisa(z),
                             kimlikler: [id.uuidString], acAdresi: EylemKaydi.alarmAdresi).kartaEkle()
            return "Alarm kuruldu: \(etiket), \(AracYardim.kisa(z)).\(EylemKaydi.geriAlNotu)"
        default:
            return "Bilinmeyen işlem: \(a.islem)."
        }
    }

    /// P2.14: "Ertele 10 dk" süresi (sn) ve düğmesi.
    static let erteleSn: TimeInterval = 600
    static var erteleDugmesi: AlarmButton { AlarmButton(text: "Ertele 10 dk", textColor: .white, systemImageName: "zzz") }

    static func sure(_ sn: Int) -> String {
        if sn % 3600 == 0 { return "\(sn / 3600) saatlik" }
        if sn % 60 == 0 { return "\(sn / 60) dakikalık" }
        if sn > 60 { return "\(sn / 60) dakika \(sn % 60) saniyelik" }
        return "\(sn) saniyelik"
    }
}
