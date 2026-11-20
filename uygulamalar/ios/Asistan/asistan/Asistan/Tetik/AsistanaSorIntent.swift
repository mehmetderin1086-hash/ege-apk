import AppIntents
import Foundation
import UIKit

/// Uygulamayı açmadan soru-cevap (Siri / Kestirmeler). Araç gerektiren istekler uygulamada sürdürülür.
@MainActor
enum SiriYanitlayici {
    nonisolated enum Sonuc: Equatable, Sendable { case yanit(String), uygulamada }
    /// P2.14: son `yanitla` çağrısının yanıtı kaydettiği sohbet (yerel yoldan ya da uygulamaya devredilen yanıtta nil).
    /// Bildirimden arka plan yanıtı bu kimlikle `asistan://sohbet?kimlik=` bildirimini kurar.
    static private(set) var sonSohbetKimligi: UUID?

    /// Araç/yan etki ya da yüksek düşünme gerektirmeyen sorular arka planda yanıtlanabilir.
    /// Güncel bilgi (skor, kur, haber, fiyat) istekleri yarışa hiç girmeden uygulamada sürer (paralelYarisDene ile aynı kural).
    nonisolated static func arkaPlandaYanitlanir(_ soru: String) -> Bool {
        CanliHizliIstemci.uygun(soru) && DusunmeSecimi.sec(soru) != .high && !Beyin.guncelBilgiIstegi(soru)
    }

    /// Saf karar: yarış yanıtı arama işaretiyse ([ARAMA]) uygulamada araçlı yoldan sürer; değilse biçimi düzeltilmiş yanıt.
    nonisolated static func yarisSonucu(_ ham: String) -> Sonuc {
        Beyin.aramaIsaretiMi(ham) ? .uygulamada : .yanit(YanitBicimi.duzelt(ham))
    }

    /// `depo` verilmezse paylaşılan kap yalnız gerçekten gerektiğinde (kilit açıkken) açılır: ilk kilit açılışından önce
    /// kap açılmaya çalışılırsa erişilemez sayılıp oturum boyu bellek kabına düşer (bildirim yanıtı ve kilit ekranı Siri'si).
    static func yanitla(_ ham: String, depo: HafizaDeposu? = nil, ayarlar: Ayarlar = Ayarlar(),
                        korumaliVeriAcik: () -> Bool = { UIApplication.shared.isProtectedDataAvailable }) async -> Sonuc {
        sonSohbetKimligi = nil
        let soru = ham.trimmingCharacters(in: .whitespacesAndNewlines)
        // Önce yerel yol: saat, kısa selamlaşma ve tarih model/ağ gerektirmez (çevrimdışıyken de yanıtlanır).
        if let y = HizliModelSecimi.yerelSaat(soru) ?? HizliModelSecimi.yerelKisaYanit(soru) { return .yanit(y) }
        if YerelKomut.coz(soru) == .tarih { return .yanit(YerelKomut.tarihMetni()) }
        guard !soru.isEmpty, arkaPlandaYanitlanir(soru), AgIzleyici.ortak.cevrimici else { return .uygulamada }
        // Kilit hiç açılmadıysa (yeniden başlatma sonrası) hafıza deposuna dokunulmaz; uygulamada sürdürülür.
        guard korumaliVeriAcik() else {
            TaniGunlugu.yaz("SİRİ → UYGULAMA (koruma altındaki veri kilitli)")
            return .uygulamada
        }
        let depo = depo ?? HafizaDeposu(baglam: HafizaDeposu.paylasilanKap.mainContext)
        await TelefonProxy.ortak.hazirla()
        guard TelefonProxy.ortak.kasaHazir else { return .uygulamada }
        var sistem = Talimatlar.olustur(olgular: depo.talimatOlgulari()) + "\n\n" + ayarlar.dostBaglami
        // Araçsız satır paralel yarışınkiyle (Beyin+Gonderim.swift paralelYarisDene) aynı tutulur.
        sistem += "\nBu yanıtta araç çağıramazsın; yukarıdaki araç talimatları bu yanıt için geçersiz. Şimdiki tarih ve saat 'Oturum başlangıcı' satırındadır. Aracı kullanıyormuş gibi anlatma ('bakıyorum', 'arıyorum' deme); telefonda işlem yaptığını veya bir şeyi kaydettiğini iddia etme. Soru canlı skor, maç sonucu, haber, fiyat/kur gibi güncel bilgi ya da bunların devam sorusu ise ('goller', 'kim attı', 'kaç kaç') yanıt yazma; yalnız \(Beyin.yarisAramaIsareti) yaz."
        sistem += "\nBu yanıt Siri ile sesli okunacak: 1-3 kısa, doğal cümle; liste, bağlantı ve kaynak yazma."
        let modeller = Array(ParalelYaris.yarisModelleri(antigravity: ayarlar.antigravityOncelik, mevcut: TelefonProxy.ortak.modeller.map(\.id)).prefix(ParalelYaris.genislik(ayar: ayarlar.yarisSaglayici, dusukVeri: AgIzleyici.ortak.dusukVeri)))
        guard let r = try? await ParalelYaris.yaris(taban: TelefonProxy.ortak.taban, anahtar: TelefonProxy.ortak.yerelAnahtar,
                                                    modeller: modeller, sistem: sistem, mesajlar: [.init(rol: "user", metin: soru)],
                                                    ilkMetinSiniri: 8, akis: { _, _ in }) else { return .uygulamada }
        // Arama işareti: güncel bilgi gerekiyor; işaret geçmişe yazılmaz, uygulamadaki yol (yarış → araçlı zincir) arar.
        guard case .yanit(let metin) = yarisSonucu(r.metin) else {
            TaniGunlugu.yaz("SİRİ → ARAMA: \(r.model)")
            return .uygulamada
        }
        // "Yaptım" bekçisi: araçsız yanıt bir iş yaptığını iddia ediyorsa (kurdum/gönderdim…) uygulamada araçlı yoldan sürer.
        if !EylemIddiasi.anlatiIstegi(soru), EylemIddiasi.denetle(metin, basariliAraclar: []) != nil {
            TaniGunlugu.yaz("SİRİ → UYGULAMA (eylem iddiası)")
            return .uygulamada
        }
        // Siri'de sorulanlar da geçmişte görünsün.
        let sohbet = depo.sohbetOlustur()
        sonSohbetKimligi = sohbet.kimlik
        depo.ekle(.kullanici, "🎙️ " + soru, sohbet: sohbet)
        depo.ekle(.asistan, metin, sohbet: sohbet)
        SaglikMerkezi.ortak.kaydet("siri_yanit", sure: r.ilkSn, etiket: r.model)
        return .yanit(metin)
    }
}

struct AsistanaSorIntent: AppIntent, ForegroundContinuableIntent {
    static let title: LocalizedStringResource = "Asistan'a sor"
    static let description = IntentDescription("Uygulamayı açmadan Asistan'a soru sorar ve yanıtı söyler. Telefonda işlem gerektiren istekleri uygulamada sürdürür.")
    static let openAppWhenRun = false
    static let isDiscoverable = true

    @Parameter(title: "Soru", requestValueDialog: IntentDialog("Ne sormak istersin?"))
    var soru: String

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog & ShowsSnippetIntent {
        // P2.4: Ayarlar → Kurulum durumu'nda Siri adımı "tamam" görünsün (iOS cümlenin kurulu olduğunu söylemez).
        UserDefaults.standard.set(true, forKey: KurulumDurumu.siriAnahtari)
        switch await SiriYanitlayici.yanitla(soru) {
        case .yanit(let metin):
            // P4.4: sesli yanıtın yanında kart (ilk 600 karakter + "Uygulamada aç" / "Yeni soru"); yerel yolda sohbet kimliği nil.
            return .result(value: metin, dialog: IntentDialog(stringLiteral: String(Konusmaci.okunabilir(metin).prefix(900))),
                           snippetIntent: YanitKartiIntent(metin: metin, sohbetKimligi: SiriYanitlayici.sonSohbetKimligi?.uuidString))
        case .uygulamada:
            let metin = soru
            throw needsToContinueInForegroundError(IntentDialog("Bunu uygulamada sesli sürdürüyorum.")) {
                // Tek yayın, sahne kurulurken dinleyici yoksa ya da Beyin meşgulse kayboluyordu: posta kutusu kabul edilene kadar yineler.
                // P2.13: Siri'den gelen iş uygulamada sesli sürer (yanıt okunur, ardından kısa takip dinlemesi).
                await MainActor.run { GorevKopru.ortak.teslimEt(metin, sesli: true) }
            }
        }
    }
}

extension Notification.Name {
    /// Siri'den ya da kullanıcının tetik bildiriminden uygulamaya devredilen soru (object: asistan://sor?metin=… URL'si).
    /// Süreç içi yoldur: dış kaynaklı tur sayılmaz.
    static let asistanSor = Notification.Name("asistan.sor")
}
