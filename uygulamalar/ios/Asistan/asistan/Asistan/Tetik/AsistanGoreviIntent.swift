import AppIntents
import Foundation

/// Kestirmeler köprüsü (madde 14): uygulamada çalışan tam ajan görevinin sonucunu bekler.
@MainActor
final class GorevKopru {
    static let ortak = GorevKopru()
    private var devam: CheckedContinuation<String, Never>?
    private var nesil = 0
    /// Kestirmeden gelen ve henüz Beyin'e kabul edilmemiş istek.
    private(set) var beklenen: String?
    /// Kabul edilen isteğin Beyin nesli: yalnız bu nesil biterse yanıt Kestirmeye döner (başka sohbet yanıtı sızmaz).
    private(set) var eslesenNesil: Int?
    /// Siri'den uygulamada sürdürülen, yanıtı beklenmeyen soru (posta kutusu): Beyin kabul edene kadar yeniden yayınlanır.
    private(set) var bekleyenSoru: String?
    private var soruNesli = 0
    /// Sohbet ekranının teslim aldığı yayınlar (`alindi`); tek seferlik istek teslim alınana kadar yinelenebilir.
    private(set) var alinanlar: Set<URL> = []
    /// Beklenen istek Beyin'in çevrimdışı kuyruğuna girdi (`kuyrugaAlindi`): "bekletiliyor" yalnız o zaman söylenir.
    private(set) var kuyrukta = false
    /// Dinleyici teslim bildiriyor mu (bir kez `alindi` geldiyse kalıcı olarak işaretlenir). Bildirmeyen sürümde tek seferlik
    /// yollar eskisi gibi tek yayınla kalır; aksi hâlde teslimi bilinmeyen istek çevrimdışı kuyruğa birden çok kez girerdi.
    nonisolated static let teslimAnahtari = "GorevKopru.teslimBildirilir"
    private var teslimBildirilir = UserDefaults.standard.bool(forKey: GorevKopru.teslimAnahtari)
    /// O4: Siri devrinin kalıcı kutusu (uygulama kapanırsa soru kaybolmasın; testte geçici kutuyla değiştirilebilir).
    var kutu = SiriSoruKutusu.ortak

    /// Sohbet ekranı `.asistanSor` yayınını teslim alınca çağırır.
    func alindi(_ url: URL) {
        if alinanlar.count > 20 { alinanlar.removeAll() }
        alinanlar.insert(url)
        if !teslimBildirilir { teslimBildirilir = true; UserDefaults.standard.set(true, forKey: Self.teslimAnahtari) }
    }
    /// Beyin çevrimdışı kuyruğa bir istek aldığında çağırır; Kestirmenin beklediği istekse işaretlenir.
    func kuyrugaAlindi(_ istek: String) {
        // Çevrimdışı kuyruk kendisi kalıcıdır: Siri kutusundaki kayıt orada sürer, açılışta ikinci kez gönderilmesin.
        kutu.cikar(metin: istek)
        if let b = beklenen, b.trimmingCharacters(in: .whitespacesAndNewlines) == istek.trimmingCharacters(in: .whitespacesAndNewlines) { kuyrukta = true }
    }

    /// Görevi uygulamaya verir ve yanıt (ya da hata metni) gelene kadar bekler; en çok `sinir` saniye.
    func calistir(_ istek: String, sinir: TimeInterval = 150) async -> String {
        devam?.resume(returning: "Yeni bir görev başladığı için önceki görev bekletilmedi.")
        devam = nil
        nesil += 1
        let benim = nesil
        beklenen = istek; eslesenNesil = nil; kuyrukta = false
        return await withCheckedContinuation { (d: CheckedContinuation<String, Never>) in
            devam = d
            Task {
                // Soğuk açılışta sohbet ekranı dinleyiciyi geç kurabilir, Beyin meşgulse istek düşer: tek yayın kaybolabiliyordu.
                // Kabul edilene kadar (en çok 8 sn) yeniden yayınlanır; kabul `beklenen`i boşalttığı için iki kez çalışmaz.
                try? await Task.sleep(for: .milliseconds(300))
                let cevrimdisi = !AgIzleyici.ortak.cevrimici
                await self.teslimDongusu(istek, sure: .seconds(8)) { self.nesil == benim && self.beklenen != nil && self.eslesenNesil == nil && !self.kuyrukta }
                guard self.nesil == benim else { return }
                if self.eslesenNesil == nil {
                    self.sonlandir(Self.teslimEdilemediMetni(kuyrukta: self.kuyrukta, cevrimdisi: cevrimdisi))
                    return
                }
                try? await Task.sleep(for: .seconds(sinir))
                guard self.nesil == benim else { return }   // bu arada yeni görev başladıysa ona dokunma
                self.sonlandir("Görev \(Int(sinir)) saniyede bitmedi; sonucu uygulamada görebilirsin.")
            }
        }
    }

    /// Siri'den uygulamaya devredilen soruyu teslim eder (yanıt beklenmez): dinleyici henüz kurulmamış ya da Beyin meşgulse
    /// kaybolmasın diye kabul edilene kadar en çok 30 sn yeniden yayınlanır. `sesli` (P2.13): Siri'den gelen iş uygulamada
    /// sesli sürer (`ses=1`; yanıt okunur, kısa takip dinlemesi açılır). Meşgulken sıraya giren devir yazılı sürer.
    func teslimEt(_ soru: String, sesli: Bool = false) {
        // O4: kalıcı kutuya yalnız kabulü kesin eşleşen istek girer (eğik çizgi komutu, 4000+ karakter bellek içi yolda kalır).
        if Self.yinelenebilir(soru) { kutu.ekle(soru) }
        soruNesli += 1
        let benim = soruNesli
        bekleyenSoru = soru
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            await self.teslimDongusu(soru, sesli: sesli, sure: .seconds(30)) { self.soruNesli == benim && self.bekleyenSoru != nil }
            if self.soruNesli == benim { self.bekleyenSoru = nil }
        }
    }

    /// `bekle` true kaldıkça isteği `asistan://sor` olarak yayınlar. Kabul edilmeden tek seferde işlenen yollar (çevrimdışı
    /// kuyruğu, eğik çizgi komutu, bağlantıda 4000 karakterde kesilen metin: kabul eşleşmez) yinelenirse iş çoğalırdı;
    /// bunlarda dinleyici teslimi bildiriyorsa teslim alınana kadar, bildirmiyorsa yalnız bir kez yayınlanır, sonra beklenir.
    private func teslimDongusu(_ istek: String, sesli: Bool = false, sure: Duration, bekle: () -> Bool) async {
        guard let url = Self.soruAdresi(istek, sesli: sesli) else { return }
        let yinelenir = Self.yinelenebilir(istek)
        let son = ContinuousClock.now + sure
        var yayinlandi = false
        alinanlar.remove(url)   // önceki aynı istekten kalan teslim bu yayını teslim edilmiş saydırmasın
        while bekle(), ContinuousClock.now < son {
            // Çevrimdışı durum her turda bakılır: kuyruğa giren istek bir daha yayınlanmaz.
            let tekSefer = !yinelenir || !AgIzleyici.ortak.cevrimici
            // Tek seferlik yolda soğuk açılışta dinleyiciye pay: ilk yayın eskisi gibi ~600 ms'de.
            if tekSefer, !yayinlandi { try? await Task.sleep(for: .milliseconds(300)); guard bekle() else { return } }
            if Self.yayinlanmali(tekSefer: tekSefer, yayinlandi: yayinlandi, teslimBildirilir: teslimBildirilir, alindi: alinanlar.contains(url)) {
                NotificationCenter.default.post(name: .asistanSor, object: url); yayinlandi = true
            }
            try? await Task.sleep(for: .milliseconds(400))
        }
    }

    /// Saf: yayınlanan `asistan://sor?metin=…` adresi; `sesli` ise `ses=1` eklenir (AsistanBaglantisi.sesliMi okur).
    nonisolated static func soruAdresi(_ istek: String, sesli: Bool) -> URL? {
        var c = URLComponents(); c.scheme = "asistan"; c.host = "sor"
        c.queryItems = [URLQueryItem(name: "metin", value: istek)] + (sesli ? [URLQueryItem(name: "ses", value: "1")] : [])
        return c.url
    }

    /// Saf: bu turda yayın yapılmalı mı. Yinelenebilir istek her turda; tek seferlik istek ilk turda, dinleyici teslim
    /// bildiriyorsa teslim alınana kadar (yayın ve alıcı aynı ana iş parçacığında eşzamanlı: teslimden sonra çift iş çıkmaz).
    nonisolated static func yayinlanmali(tekSefer: Bool, yayinlandi: Bool, teslimBildirilir: Bool, alindi: Bool) -> Bool {
        if !tekSefer || !yayinlandi { return true }
        return teslimBildirilir && !alindi
    }

    /// Saf: istek kabul edilmeden süre dolunca Kestirmeye dönen metin. "Bekletiliyor" yalnız kuyruğa alındığı doğrulanınca.
    nonisolated static func teslimEdilemediMetni(kuyrukta: Bool, cevrimdisi: Bool) -> String {
        if kuyrukta { return "Bağlantı yok; istek uygulamada bekletiliyor, bağlantı gelince gönderilecek." }
        if cevrimdisi { return "Bağlantı yok; isteğin uygulamada sıraya alındığı doğrulanamadı. Uygulamada görünmüyorsa bağlantı gelince tekrar dene." }
        return "Asistan isteği alamadı (meşgul ya da henüz açılmadı); biraz sonra tekrar dene."
    }

    /// Yeniden yayın yalnız kabulü kesin eşleşecek isteklerde güvenli.
    nonisolated static func yinelenebilir(_ istek: String) -> Bool {
        let t = istek.trimmingCharacters(in: .whitespacesAndNewlines)
        return !t.isEmpty && t.count <= 4_000 && SlashKomutlari.coz(t) == nil
    }

    /// Beyin isteği kabul ederken çağırır: istek Kestirmeden geliyorsa nesli eşlenir.
    func kabul(_ istek: String, nesil n: Int) {
        let t = istek.trimmingCharacters(in: .whitespacesAndNewlines)
        if let s = bekleyenSoru, s.trimmingCharacters(in: .whitespacesAndNewlines) == t { bekleyenSoru = nil }
        kutu.cikar(metin: t)   // kutuda yoksa diske yazmaz
        guard let b = beklenen, b.trimmingCharacters(in: .whitespacesAndNewlines) == t else { return }
        eslesenNesil = n; beklenen = nil
    }

    /// Beyin yanıtı bitirince çağırır; yalnız eşleşen nesil Kestirmeye döner.
    func bitti(_ metin: String, nesil n: Int) {
        guard eslesenNesil == n else { return }
        sonlandir(metin)
    }

    private func sonlandir(_ metin: String) {
        guard let d = devam else { return }
        devam = nil; eslesenNesil = nil; beklenen = nil; kuyrukta = false
        d.resume(returning: metin)
    }
}

struct AsistanGoreviIntent: AppIntent {
    static let title: LocalizedStringResource = "Asistan görevi yap"
    static let description = IntentDescription("Asistan'ı açıp görevi bütün araçlarıyla (takvim, dosya, web, mesaj taslağı…) yapar ve sonucu metin olarak sonraki Kestirme adımına verir.")
    static let openAppWhenRun = true
    static let isDiscoverable = true

    @Parameter(title: "Görev", requestValueDialog: IntentDialog("Ne yapmamı istersin?"))
    var gorev: String

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let metin = await GorevKopru.ortak.calistir(gorev)
        return .result(value: metin, dialog: IntentDialog(stringLiteral: String(Konusmaci.okunabilir(metin).prefix(600))))
    }
}
