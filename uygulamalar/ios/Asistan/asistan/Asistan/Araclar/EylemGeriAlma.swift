import Foundation
import EventKit
import AlarmKit

/// Telefonda sorulmadan yapılan işin kaydı: yanıtın altında eylem kartı olarak görünür (Aç / Düzenle / 10 dakikalık Geri al).
/// Takvim, hatırlatıcı, alarm ve zamanlayıcı geri alınabilir; arama, SMS, WhatsApp ve harita yalnız yeniden açılır
/// (iOS gönderilmiş mesajı ya da yapılmış aramayı geri almaya izin vermez).
nonisolated struct EylemKaydi: Codable, Equatable, Sendable, Identifiable {
    nonisolated enum Tur: String, Codable, Sendable, CaseIterable {
        case takvim, hatirlatici, alarm, zamanlayici, arama, mesaj, whatsapp, harita
    }
    var id: UUID = UUID()
    var tur: Tur
    var baslik: String
    var ozet: String
    /// EKEvent.eventIdentifier, EKReminder.calendarItemIdentifier ya da AlarmKit kimliği (UUID metni).
    var kimlikler: [String]
    var acAdresi: String?
    var zaman: Date = .now

    static let geriAlmaSuresi: TimeInterval = 600
    static let geriAlinabilirTurler: Set<Tur> = [.takvim, .hatirlatici, .alarm, .zamanlayici]
    /// Önizleme (DEBUG) kartının kimliği: geri almada EventKit'e gidilmez, `.bulunamadi` döner.
    static let onizlemeKimligi = "onizleme"
    /// Araç metnine eklenen not (model kartı görür, geri almayı kendisi yapmış gibi söylemez).
    static let geriAlNotu = " Yanıttaki karttan 10 dakika içinde geri alınabilir."

    /// Arama, SMS, WhatsApp ve harita: yalnız Aç düğmesi.
    var yalnizAc: Bool { !Self.geriAlinabilirTurler.contains(tur) }

    /// Geri al düğmesi görünsün mü: kimlik var, tür geri alınabilir, süre (600 sn) dolmadı.
    func geriAlinabilir(simdi: Date = .now) -> Bool {
        !kimlikler.isEmpty && !yalnizAc && simdi.timeIntervalSince(zaman) < Self.geriAlmaSuresi
    }

    /// Geri almaya kalan süre (sn); süre dolduysa 0.
    func kalanSure(simdi: Date = .now) -> TimeInterval { max(0, Self.geriAlmaSuresi - simdi.timeIntervalSince(zaman)) }

    /// Düzenle düğmesi: yalnız tek kimlikli takvim kaydında (EKEventEditViewController tek etkinlik açar).
    var duzenlenebilir: Bool { tur == .takvim && kimlikler.count == 1 }

    static func dugmeMetni(_ k: EylemKaydi) -> String { k.kimlikler.count > 1 ? "Tümünü geri al" : "Geri al" }

    static func simge(_ t: Tur) -> String {
        switch t {
        case .takvim: "calendar"
        case .hatirlatici: "checklist"
        case .alarm: "alarm"
        case .zamanlayici: "timer"
        case .arama: "phone"
        case .mesaj, .whatsapp: "message"
        case .harita: "map"
        }
    }

    // MARK: Adresler (Aç düğmesi)
    /// Takvim uygulamasını verilen güne açar (calshow: referans tarihinden saniye).
    static func takvimAdresi(_ d: Date) -> String { "calshow:\(Int(d.timeIntervalSinceReferenceDate))" }
    /// UygulamaAcAraci'ndaki Saat adresiyle aynı biçim.
    static let alarmAdresi = "clock-alarm://"
    static let hatirlaticiAdresi = "x-apple-reminderkit://"
    /// Haritalar yol tarifi adresi.
    static func haritaAdresi(enlem: Double, boylam: Double) -> String { "maps://?daddr=\(enlem),\(boylam)" }

    /// Kaydı etkin isteğin ek defterine ekler (araçlar ana aktör dışından çağırır).
    func kartaEkle() async {
        let k = self
        await MainActor.run { EkDefteri.ortak.ekle(MesajEki(tur: .eylem(k))) }
    }
}

/// Eylem kartındaki Geri al: kayıttaki kimlikleri EventKit / AlarmKit'ten siler.
/// tani.log'a kişisel metin yazılmaz; yalnız tür ve sayı.
@MainActor
enum EylemGeriAlici {
    nonisolated enum Sonuc: Equatable, Sendable {
        case tamam(Int)
        case kismen(Int, kalan: Int)
        case bulunamadi
        case sureDoldu
        case izinYok
    }

    nonisolated static let geriAlinanAnahtari = "eylem.geriAlinan.v1"
    nonisolated static let enFazlaKayit = 200

    static func geriAl(_ k: EylemKaydi, simdi: Date = .now, defaults: UserDefaults = .standard) async -> Sonuc {
        guard !k.yalnizAc, !k.kimlikler.isEmpty else { return .bulunamadi }
        // Süre denetimi önce: süresi geçmiş kayıtta EventKit/AlarmKit'e hiç gidilmez.
        guard k.geriAlinabilir(simdi: simdi) else { return .sureDoldu }
        let kimlikler = k.kimlikler.filter { $0 != EylemKaydi.onizlemeKimligi }
        guard !kimlikler.isEmpty else { return .bulunamadi }
        let silinen: Int
        switch k.tur {
        case .takvim:
            guard let n = await takvimdenSil(kimlikler) else { TaniGunlugu.yaz("EYLEM GERİ AL: takvim izin yok"); return .izinYok }
            silinen = n
        case .hatirlatici:
            guard let n = await hatirlaticidanSil(kimlikler) else { TaniGunlugu.yaz("EYLEM GERİ AL: hatırlatıcı izin yok"); return .izinYok }
            silinen = n
        case .alarm, .zamanlayici:
            silinen = alarmlariIptal(kimlikler)
        case .arama, .mesaj, .whatsapp, .harita:
            return .bulunamadi
        }
        TaniGunlugu.yaz("EYLEM GERİ AL: \(k.tur.rawValue) \(silinen)/\(kimlikler.count)")
        guard silinen > 0 else { return .bulunamadi }
        isaretle(k.id, defaults: defaults)
        return silinen >= kimlikler.count ? .tamam(silinen) : .kismen(silinen, kalan: kimlikler.count - silinen)
    }

    /// Kartta gösterilecek sonuç metni.
    nonisolated static func metin(_ s: Sonuc, tur: EylemKaydi.Tur) -> String {
        switch s {
        case .tamam(let n): n > 1 ? "\(n) kayıt geri alındı" : "Geri alındı"
        case .kismen(let n, let kalan): "\(n)/\(n + kalan) geri alındı"
        case .bulunamadi: "Geri alınamadı (kayıt bulunamadı)"
        case .sureDoldu: "Süre doldu"
        case .izinYok: tur == .hatirlatici ? "Geri alınamadı (hatırlatıcı izni yok)" : "Geri alınamadı (takvim izni yok)"
        }
    }

    // MARK: Geri alınanlar (kart yeniden çizilince "Geri alındı" kalsın)

    nonisolated static func geriAlindiMi(_ id: UUID, defaults: UserDefaults = .standard) -> Bool {
        (defaults.stringArray(forKey: geriAlinanAnahtari) ?? []).contains(id.uuidString)
    }

    /// En çok `enFazlaKayit` kimlik tutulur; sınır aşılınca en eskisi düşer.
    nonisolated static func isaretle(_ id: UUID, defaults: UserDefaults = .standard) {
        var l = defaults.stringArray(forKey: geriAlinanAnahtari) ?? []
        l.removeAll { $0 == id.uuidString }
        l.append(id.uuidString)
        if l.count > enFazlaKayit { l.removeFirst(l.count - enFazlaKayit) }
        defaults.set(l, forKey: geriAlinanAnahtari)
    }

    // MARK: Silme çekirdekleri (ana iş parçacığı dışında)

    /// Etkinlikleri siler; tekrarlı etkinlik ilk tekrarından bütün geleceğiyle (seri baştan) silinir. İzin yoksa nil.
    @concurrent nonisolated private static func takvimdenSil(_ kimlikler: [String]) async -> Int? {
        let depo = EKEventStore()
        guard (try? await depo.requestFullAccessToEvents()) == true else { return nil }
        var n = 0
        for id in kimlikler {
            guard let e = depo.event(withIdentifier: id) else { continue }
            do { try depo.remove(e, span: .futureEvents, commit: false); n += 1 } catch { continue }
        }
        guard n > 0 else { return 0 }
        do { try depo.commit() } catch { depo.reset(); return 0 }
        return n
    }

    @concurrent nonisolated private static func hatirlaticidanSil(_ kimlikler: [String]) async -> Int? {
        let depo = EKEventStore()
        guard (try? await depo.requestFullAccessToReminders()) == true else { return nil }
        var n = 0
        for id in kimlikler {
            guard let r = depo.calendarItem(withIdentifier: id) as? EKReminder else { continue }
            do { try depo.remove(r, commit: false); n += 1 } catch { continue }
        }
        guard n > 0 else { return 0 }
        do { try depo.commit() } catch { depo.reset(); return 0 }
        return n
    }

    /// Alarm/zamanlayıcı iptali; çalmış ve bitmiş kayıt bulunamaz sayılır. Etiket kaydı da temizlenir.
    nonisolated private static func alarmlariIptal(_ kimlikler: [String]) -> Int {
        var silinen: [String] = []
        for s in kimlikler {
            guard let id = UUID(uuidString: s) else { continue }
            do { try AlarmManager.shared.cancel(id: id); silinen.append(s) } catch { continue }
        }
        if !silinen.isEmpty {
            ZamanlayiciAraci.kayitlariGuncelle { (k: inout [String: ZamanlayiciAraci.AlarmKaydi]) -> Void in for s in silinen { k[s] = nil } }
        }
        return silinen.count
    }
}
