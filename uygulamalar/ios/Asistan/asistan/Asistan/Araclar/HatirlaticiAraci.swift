import Foundation
import FoundationModels
import EventKit
import MapKit
import CoreLocation

nonisolated struct HatirlaticiAraci: Tool {
    let name = "hatirlatici"
    let description = "Hatırlatıcıları listeler, yeni hatırlatıcı ekler ya da birini tamamlandı işaretler. Zaman yerel ISO 8601. Birden çok hatırlatıcı gerekiyorsa (ör. haftalık program) tek tek değil, 'ekle' işleminde 'toplu' listesini kullan: hepsi tek çağrıda oluşturulur. Birden çok hatırlatıcıyı tamamlamak için de tek 'tamamla' çağrısında 'toplu'ya başlıkları yaz. Konuma bağlı hatırlatma için 'konum' (yer adı/adres) ve 'konumOlayi' ('varinca' ya da 'ayrilinca') ver; zaman gerekmez. Ayrı bir hatırlatıcı listesi için 'liste' ver (ör. ödevler 'Ödevler 9-B'); 'listeler' mevcut listelerin adlarını verir."

    /// Liste adı eşleşmesi: tr_TR büyük/küçük harf ve aksan duyarsız tam eşleşme (baştaki/sondaki boşluk yok sayılır).
    static func listeEslestir(_ adlar: [String], _ istenen: String) -> Int? {
        let p = listeAdiTemizle(istenen)
        guard !p.isEmpty else { return nil }
        let tr = Locale(identifier: "tr_TR")
        return adlar.firstIndex {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).compare(p, options: [.caseInsensitive, .diacriticInsensitive], range: nil, locale: tr) == .orderedSame
        }
    }

    /// Liste adı: satır sonları boşluğa çevrilir, kırpılır, en çok 60 karakter.
    static func listeAdiTemizle(_ ad: String) -> String {
        let tek = ad.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return String(tek.prefix(60)).trimmingCharacters(in: .whitespaces)
    }

    /// Adı verilen hatırlatıcı listesi (varsa); yoksa nil. Oluşturmaz (listele/tamamla için).
    static func listeBul(_ depo: EKEventStore, ad: String) -> EKCalendar? {
        let takvimler = depo.calendars(for: .reminder)
        return listeEslestir(takvimler.map(\.title), ad).map { takvimler[$0] }
    }

    nonisolated enum ListeHatasi: Error { case kaynakYok }

    /// listele/tamamla'da verilen liste yoksa (oluşturulmaz).
    static func listeYokMetni(_ ad: String) -> String {
        "Bu adla hatırlatıcı listesi yok: '\(ad)'. Mevcut listeler için 'listeler' işlemini çağır."
    }

    /// Adı verilen hatırlatıcı listesini bulur; yoksa varsayılan listenin kaynağında oluşturup kaydeder ('ekle').
    static func listeBulYaDaKur(_ depo: EKEventStore, ad: String) throws -> EKCalendar {
        if let bulunan = listeBul(depo, ad: ad) { return bulunan }
        let yeni = EKCalendar(for: .reminder, eventStore: depo)
        yeni.title = listeAdiTemizle(ad)
        guard let kaynak = depo.defaultCalendarForNewReminders()?.source
                ?? depo.sources.first(where: { !$0.calendars(for: .reminder).isEmpty }) else { throw ListeHatasi.kaynakYok }
        yeni.source = kaynak
        try depo.saveCalendar(yeni, commit: true)
        return yeni
    }

    /// Dış kaynaklı turda 'ekle' onayının ayrıntısı: ilk 5 başlık (+ zaman).
    static func ekleAyrintisi(_ maddeler: [(baslik: String, zaman: Date?)]) -> String {
        let satirlar = maddeler.prefix(5).map { m in "• \(m.baslik.prefix(80))" + (m.zaman.map { " — \(AracYardim.kisa($0))" } ?? "") }
        return satirlar.joined(separator: "\n") + (maddeler.count > 5 ? "\n…ve \(maddeler.count - 5) tane daha" : "")
    }

    struct Madde: Equatable { var baslik: String; var zaman: String?; var haftalik: Bool? }

    /// "başlık | zaman ISO 8601 | haftalık (evet/hayır)" metnini ayrıştırır.
    static func maddeCoz(_ satir: String) -> Madde? {
        let p = satir.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard let b = p.first, !b.isEmpty else { return nil }
        return Madde(baslik: b, zaman: p.count > 1 && !p[1].isEmpty ? p[1] : nil,
                     haftalik: p.count > 2 ? ["evet", "e", "true", "haftalik", "haftalık", "1"].contains(p[2].lowercased()) : nil)
    }

    nonisolated enum Secim: Equatable { case yok, tek(Int), belirsiz([Int]) }

    /// 'tamamla' hedefi: önce tam başlık (büyük/küçük harf ve aksan duyarsız), yoksa alt dize; birden çok alt dize eşleşmesi belirsizdir.
    /// Aynı tam başlıklı birden çok kayıtta (ör. her hafta aynı ders) en yakın vadeli kapanır; tarihsizler sona kalır (`tarihler` başlıklarla paralel).
    static func hedefSec(_ basliklar: [String], tarihler: [Date?] = [], parca: String) -> Secim {
        let p = parca.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else { return .yok }
        let tr = Locale(identifier: "tr_TR")
        let tam = basliklar.indices.filter {
            basliklar[$0].trimmingCharacters(in: .whitespacesAndNewlines).compare(p, options: [.caseInsensitive, .diacriticInsensitive], range: nil, locale: tr) == .orderedSame
        }
        if tam.count == 1 { return .tek(tam[0]) }
        if tam.count > 1 {
            func vade(_ i: Int) -> Date { i < tarihler.count ? (tarihler[i] ?? .distantFuture) : .distantFuture }
            // `min` eşitlikte ilkini korur: tarihler bilinmiyorsa davranış eskisi gibi ilk kayıt.
            return .tek(tam.min { vade($0) < vade($1) } ?? tam[0])
        }
        let eslesen = basliklar.indices.filter { basliklar[$0].localizedCaseInsensitiveContains(p) }
        switch eslesen.count {
        case 0: return .yok
        case 1: return .tek(eslesen[0])
        default: return .belirsiz(eslesen)
        }
    }

    /// Birden çok 'tamamla' hedefi tek seferde: seçilen kayıt sonraki parçalara kapatılır (aynı kayıt iki kez seçilmez,
    /// aynı başlıklı iki parça iki ayrı kaydı kapatır). Dönen dizi `parcalar` ile paralel.
    static func topluHedefSec(_ basliklar: [String], tarihler: [Date?] = [], parcalar: [String]) -> [Secim] {
        var kalan = basliklar
        return parcalar.map { (p: String) -> Secim in
            let s = hedefSec(kalan, tarihler: tarihler, parca: p)
            if case .tek(let i) = s { kalan[i] = "" }   // boş başlık ne tam ne alt dize eşleşir
            return s
        }
    }

    nonisolated enum ZamanCozum: Equatable { case yok, tamam(Date), anlasilmadi(String) }

    /// Tek 'ekle' zamanı: boş/yalnız boşluk "zaman yok"; dolu ama çözülemeyen zaman sessizce tarihsiz kayda dönüşmesin diye ayrı bildirilir.
    static func zamanCoz(_ ham: String?) -> ZamanCozum {
        let t = ham?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !t.isEmpty else { return .yok }
        guard let z = AracYardim.hatirlatmaZamani(t) else { return .anlasilmadi(t) }
        return .tamam(z)
    }

    /// Kapanan kaydın görünen adı (varsa vadesiyle; aynı başlıklılardan hangisinin kapandığı görülsün).
    static func etiket(_ r: EKReminder) -> String {
        (r.title ?? "") + (r.dueDateComponents?.date.map { " — \(AracYardim.kisa($0))" } ?? "")
    }

    @Generable
    struct Arguments {
        @Guide(description: "ekle: aynı anda eklenecek birden çok hatırlatıcı (en çok 40). Her madde tek metin: 'başlık | zaman ISO 8601 | haftalık (evet/hayır)'. Örn: '9B Biyoloji dersi | 2026-10-19T08:28 | evet'. tamamla: tamamlanacak hatırlatıcıların başlıkları, her madde bir başlık (tek çağrıda hepsi)") var toplu: [String]?
        @Guide(description: "'listele', 'ekle', 'tamamla' ya da 'listeler' (mevcut hatırlatıcı listelerinin adları)") var islem: String
        @Guide(description: "Hatırlatıcı listesi adı (ör. 'Ödevler 9-B'); ekle'de yoksa oluşturulur; listele/tamamla'da yalnız o liste") var liste: String?
        @Guide(description: "ekle: başlık; tamamla: hatırlatıcının tam başlığı (bilinmiyorsa ayırt edici parçası)") var baslik: String?
        @Guide(description: "ekle: hatırlatma zamanı ISO 8601 (isteğe bağlı)") var zaman: String?
        @Guide(description: "ekle: not (isteğe bağlı)") var not: String?
        @Guide(description: "ekle: konuma bağlı hatırlatma için yer adı ya da adres (ör. 'Cumhuriyet Anadolu Lisesi Beykoz')") var konum: String?
        @Guide(description: "ekle: 'varinca' (varsayılan) ya da 'ayrilinca'") var konumOlayi: String?
    }

    /// Dış kaynaklı ya da güvenilmeyen içerik okunmuş turda 'tamamla' (silmeye en yakın dal) ve 'ekle' (ör. paylaşılan PDF'ten son tarihler) tek onayla sorulur.
    var onay: OnayKapisi? = nil

    func call(arguments a: Arguments) async throws -> String {
        let depo = EKEventStore()
        guard try await depo.requestFullAccessToReminders() else {
            await IzinKarti.ekle(.hatirlatici)
            return "Hatırlatıcı izni verilmedi."
        }
        // Ayrı liste (ör. 'Ödevler 9-B'): listele/tamamla yalnız onda arar; ekle yoksa onaydan sonra kurar.
        let listeAdi = a.liste.map { Self.listeAdiTemizle($0) } ?? ""
        let listeEki = listeAdi.isEmpty ? "" : " (\(listeAdi) listesine)"
        /// 'ekle' hedef listesi: liste verilmediyse varsayılan; verildiyse bulunur ya da kurulur (kurulamazsa fırlatır).
        func eklemeListesi() throws -> EKCalendar? {
            try listeAdi.isEmpty ? depo.defaultCalendarForNewReminders() : Self.listeBulYaDaKur(depo, ad: listeAdi)
        }
        let kurulamadi = "'\(listeAdi)' hatırlatıcı listesi oluşturulamadı; hatırlatıcı eklenmedi."
        switch a.islem.lowercased() {
        case "listeler":
            let adlar = depo.calendars(for: .reminder).map(\.title).sorted { $0.localizedCompare($1) == .orderedAscending }
            return adlar.isEmpty ? "Hatırlatıcı listesi yok." : "Hatırlatıcı listeleri:\n" + adlar.prefix(50).map { "• \($0)" }.joined(separator: "\n")
        case "listele":
            var takvimler: [EKCalendar]? = nil
            if !listeAdi.isEmpty {
                guard let l = Self.listeBul(depo, ad: listeAdi) else { return Self.listeYokMetni(listeAdi) }
                takvimler = [l]
            }
            let p = depo.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: takvimler)
            let liste = await Self.getir(depo, p)
            if liste.isEmpty { return listeAdi.isEmpty ? "Açık hatırlatıcı yok." : "'\(listeAdi)' listesinde açık hatırlatıcı yok." }
            let sirali = liste.sorted { ($0.dueDateComponents?.date ?? .distantFuture) < ($1.dueDateComponents?.date ?? .distantFuture) }
            return sirali.prefix(25).map { r in
                let z = r.dueDateComponents?.date.map { " — \(AracYardim.kisa($0))" } ?? ""
                return "• \(r.title ?? "(adsız)")\(z)"
            }.joined(separator: "\n")
        case "ekle":
            if let toplu = a.toplu, !toplu.isEmpty {
                var eklenen: [String] = [], atlanan: [String] = []
                var kaydedilen: [EKReminder] = []   // kimlikler commit'ten sonra okunur
                var maddeler: [(m: Madde, zaman: Date?)] = []
                let kesilen = max(0, toplu.count - 40)
                for (i, ham) in toplu.prefix(40).enumerated() {
                    guard let m = Self.maddeCoz(ham) else { atlanan.append("\(i + 1). \(ham.prefix(60))"); continue }
                    // Zaman verilmiş ama çözülemiyorsa tarihsiz/tekrarsız kayıt açılmaz; satır raporlanır.
                    var zaman: Date?
                    if let zamanMetni = m.zaman {
                        guard let z = AracYardim.hatirlatmaZamani(zamanMetni) else { atlanan.append("\(i + 1). \(m.baslik.prefix(60)) — zaman anlaşılmadı"); continue }
                        zaman = z
                    }
                    maddeler.append((m: m, zaman: zaman))
                }
                let ozet = AracYardim.topluOzet(atlanan: atlanan, kesilen: kesilen, sinir: 40)
                guard !maddeler.isEmpty else { return "Hiç hatırlatıcı eklenmedi." + ozet }
                // Dış kaynaklı turda (ör. paylaşılan PDF'teki son tarihler) tek onay; doğrudan komutta soru çıkmaz.
                if let onay, !(await onay.disKaynaktaIste(baslik: "\(maddeler.count) hatırlatıcı eklensin mi?",
                                                         ayrinti: String(Self.ekleAyrintisi(maddeler.map { (baslik: $0.m.baslik, zaman: $0.zaman) }).prefix(400)))) {
                    return "Kullanıcı onaylamadı; hatırlatıcı eklenmedi."
                }
                let takvim: EKCalendar?
                do { takvim = try eklemeListesi() } catch { return kurulamadi }
                for (m, zaman) in maddeler {
                    let r = EKReminder(eventStore: depo)
                    r.title = m.baslik
                    r.calendar = takvim
                    if let z = zaman {
                        r.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: z)
                        r.addAlarm(EKAlarm(absoluteDate: z))
                        if m.haftalik == true { r.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil)) }
                    }
                    try depo.save(r, commit: false)
                    kaydedilen.append(r)
                    eklenen.append(m.baslik)
                }
                try depo.commit()
                let kart = EylemKaydi(tur: .hatirlatici, baslik: "\(eklenen.count) hatırlatıcı eklendi",
                                      ozet: eklenen.prefix(3).joined(separator: ", ") + (eklenen.count > 3 ? "…" : ""),
                                      kimlikler: Self.kimlikler(kaydedilen), acAdresi: EylemKaydi.hatirlaticiAdresi)
                await kart.kartaEkle()
                return "\(eklenen.count) hatırlatıcı eklendi\(listeEki): " + eklenen.prefix(10).joined(separator: "; ") + (eklenen.count > 10 ? "…" : "") + ozet + (kart.kimlikler.isEmpty ? "" : EylemKaydi.geriAlNotu)
            }
            guard let baslik = a.baslik, !baslik.isEmpty else { return "Başlık gerekli." }
            if let yer = a.konum?.trimmingCharacters(in: .whitespacesAndNewlines), !yer.isEmpty {
                guard let bulunan = await KonumCozucu.bul(yer) else { return "'\(yer)' konumu bulunamadı; daha açık bir adres ver." }
                let ayrilinca = (a.konumOlayi ?? "").lowercased().hasPrefix("ayril")
                if let onay, !(await onay.disKaynaktaIste(baslik: "1 hatırlatıcı eklensin mi?",
                                                         ayrinti: String("• \(baslik.prefix(80)) — \(bulunan.ad) \(ayrilinca ? "ayrılınca" : "varınca")".prefix(400)))) {
                    return "Kullanıcı onaylamadı; hatırlatıcı eklenmedi."
                }
                let takvim: EKCalendar?
                do { takvim = try eklemeListesi() } catch { return kurulamadi }
                let r = Self.konumluKur(depo, baslik: baslik, yerAdi: bulunan.ad, konum: bulunan.konum, ayrilinca: ayrilinca, not: a.not)
                if !listeAdi.isEmpty { r.calendar = takvim }
                try depo.save(r, commit: true)
                let kart = EylemKaydi(tur: .hatirlatici, baslik: baslik, ozet: "\(bulunan.ad) · \(ayrilinca ? "ayrılınca" : "varınca")",
                                      kimlikler: Self.kimlikler([r]), acAdresi: EylemKaydi.hatirlaticiAdresi)
                await kart.kartaEkle()
                return "Konuma bağlı hatırlatıcı eklendi\(listeEki): \(baslik) — \(bulunan.ad) konumuna \(ayrilinca ? "ayrılınca" : "varınca") (yaklaşık \(Int(Self.konumYaricapi)) m). Çalışması için Hatırlatıcılar'ın konum izni 'Her Zaman' olmalı." + (kart.kimlikler.isEmpty ? "" : EylemKaydi.geriAlNotu)
            }
            // Zaman verilmiş ama çözülemiyorsa tarihsiz/alarmsız kayıt açılıp "eklendi" denmez (toplu yoldaki gibi).
            let zaman: Date?
            switch Self.zamanCoz(a.zaman) {
            case .yok: zaman = nil
            case .tamam(let z): zaman = z
            case .anlasilmadi(let t):
                return "Hatırlatma zamanı anlaşılmadı: '\(t.prefix(60))'. Hatırlatıcı eklenmedi; zamanı yerel ISO 8601 ver (ör. 2026-10-21T08:30) ve yeniden 'ekle' çağır."
            }
            if let onay, !(await onay.disKaynaktaIste(baslik: "1 hatırlatıcı eklensin mi?",
                                                     ayrinti: String(Self.ekleAyrintisi([(baslik: baslik, zaman: zaman)]).prefix(400)))) {
                return "Kullanıcı onaylamadı; hatırlatıcı eklenmedi."
            }
            let takvim: EKCalendar?
            do { takvim = try eklemeListesi() } catch { return kurulamadi }
            let r = EKReminder(eventStore: depo)
            r.title = baslik
            r.notes = a.not
            r.calendar = takvim
            if let z = zaman {
                r.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: z)
                r.addAlarm(EKAlarm(absoluteDate: z))
            }
            try depo.save(r, commit: true)
            let z = zaman.map { ", \(AracYardim.kisa($0))" } ?? ""
            let saatNotu = zaman != nil && AracYardim.yalnizGun(a.zaman?.trimmingCharacters(in: .whitespacesAndNewlines)) ? " Saat verilmediği için 09:00'a kuruldu." : ""
            let kart = EylemKaydi(tur: .hatirlatici, baslik: baslik, ozet: zaman.map { AracYardim.kisa($0) } ?? "Tarihsiz",
                                  kimlikler: Self.kimlikler([r]), acAdresi: EylemKaydi.hatirlaticiAdresi)
            await kart.kartaEkle()
            return "Hatırlatıcı eklendi\(listeEki): \(baslik)\(z).\(saatNotu)" + (kart.kimlikler.isEmpty ? "" : EylemKaydi.geriAlNotu)
        case "tamamla":
            // Birden çok başlık tek çağrıda: tek onay, tek kayıt (paralel 'tamamla' çağrıları birbirinin onayını düşürmesin).
            let topluParcalar = (a.toplu ?? []).prefix(40).compactMap { Self.maddeCoz($0)?.baslik }
            let parca = a.baslik?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !topluParcalar.isEmpty || !parca.isEmpty else { return "Hangi hatırlatıcı? Başlık gerekli." }
            var takvimler: [EKCalendar]? = nil
            if !listeAdi.isEmpty {
                guard let l = Self.listeBul(depo, ad: listeAdi) else { return Self.listeYokMetni(listeAdi) }
                takvimler = [l]
            }
            let p = depo.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: takvimler)
            let liste = await Self.getir(depo, p)
            let basliklar = liste.map { $0.title ?? "" }, tarihler = liste.map { $0.dueDateComponents?.date }
            if !topluParcalar.isEmpty {
                var hedefler: [EKReminder] = [], sorunlar: [String] = []
                for (tp, s) in zip(topluParcalar, Self.topluHedefSec(basliklar, tarihler: tarihler, parcalar: topluParcalar)) {
                    switch s {
                    case .tek(let i): hedefler.append(liste[i])
                    case .yok: sorunlar.append("'\(tp.prefix(60))' bulunamadı")
                    case .belirsiz(let ix): sorunlar.append("'\(tp.prefix(60))' birden çok kayıtla eşleşti (" + ix.prefix(5).map { liste[$0].title ?? "(adsız)" }.joined(separator: ", ") + ")")
                    }
                }
                let sorunNotu = sorunlar.isEmpty ? "" : " Kapatılmayanlar: " + sorunlar.prefix(10).joined(separator: "; ") + ". Belirsizleri kullanıcıya sor; sonra tam başlıkla yeniden 'tamamla' çağır."
                guard !hedefler.isEmpty else { return "Hiçbir hatırlatıcı tamamlanmadı." + sorunNotu }
                if let onay {
                    let ayrinti = hedefler.map { Self.etiket($0) }.joined(separator: "\n")
                    guard await onay.disKaynaktaIste(baslik: "\(hedefler.count) hatırlatıcı tamamlandı işaretlensin mi?", ayrinti: String(ayrinti.prefix(300))) else {
                        return "Kullanıcı onaylamadı; hatırlatıcılar açık kaldı."
                    }
                }
                for h in hedefler { h.isCompleted = true; try depo.save(h, commit: false) }
                try depo.commit()
                return "\(hedefler.count) hatırlatıcı tamamlandı: " + hedefler.prefix(10).map { Self.etiket($0) }.joined(separator: "; ") + (hedefler.count > 10 ? "…" : "") + "." + sorunNotu
            }
            switch Self.hedefSec(basliklar, tarihler: tarihler, parca: parca) {
            case .yok:
                return "'\(parca)' içeren açık hatırlatıcı bulunamadı."
            case .tek(let i):
                let hedef = liste[i]
                if let onay {
                    guard await onay.disKaynaktaIste(baslik: "Hatırlatıcı tamamlandı işaretlensin mi?", ayrinti: String(Self.etiket(hedef).prefix(300))) else {
                        return "Kullanıcı onaylamadı; hatırlatıcı açık kaldı."
                    }
                }
                hedef.isCompleted = true
                try depo.save(hedef, commit: true)
                return "Tamamlandı: \(Self.etiket(hedef))."
            case .belirsiz(let ix):
                // Birden çok eşleşmede hiçbiri kapatılmaz: yanlış hatırlatıcıyı tamamlamak geri alınması zor bir hata.
                let sirali = ix.map { liste[$0] }.sorted { ($0.dueDateComponents?.date ?? .distantFuture) < ($1.dueDateComponents?.date ?? .distantFuture) }
                let satirlar = sirali.prefix(10).map { r in
                    "• \(r.title ?? "(adsız)")" + (r.dueDateComponents?.date.map { " — \(AracYardim.kisa($0))" } ?? "")
                }.joined(separator: "\n")
                return "'\(parca)' birden çok açık hatırlatıcıyla eşleşti:\n\(satirlar)\nHangisi olduğunu kullanıcıya sor; sonra tam başlıkla yeniden 'tamamla' çağır."
            }
        default:
            return "Bilinmeyen işlem: \(a.islem)."
        }
    }

    static let konumYaricapi: Double = 150

    /// Eylem kartı için kimlikler (kaydedildikten/commit'ten sonra; boş olanlar atlanır).
    static func kimlikler(_ liste: [EKReminder]) -> [String] {
        liste.map { $0.calendarItemIdentifier }.filter { !$0.isEmpty }
    }

    /// Konuma bağlı hatırlatıcıyı kurar (kaydetmez): yere varınca ya da ayrılınca tetiklenir.
    static func konumluKur(_ depo: EKEventStore, baslik: String, yerAdi: String, konum: CLLocation, ayrilinca: Bool, not: String? = nil) -> EKReminder {
        let r = EKReminder(eventStore: depo)
        r.title = baslik; r.notes = not
        r.calendar = depo.defaultCalendarForNewReminders()
        let yer = EKStructuredLocation(title: yerAdi)
        yer.geoLocation = konum; yer.radius = konumYaricapi
        let alarm = EKAlarm()
        alarm.structuredLocation = yer
        alarm.proximity = ayrilinca ? .leave : .enter
        r.addAlarm(alarm)
        return r
    }

    nonisolated private struct Kutu: @unchecked Sendable { let liste: [EKReminder] }
    private static func getir(_ depo: EKEventStore, _ p: NSPredicate) async -> [EKReminder] {
        let kutu: Kutu = await withCheckedContinuation { c in
            depo.fetchReminders(matching: p) { c.resume(returning: Kutu(liste: $0 ?? [])) }
        }
        return kutu.liste
    }
}
