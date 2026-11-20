import Testing
import Foundation
@testable import Asistan

@Suite("Karma tema (Claude + Telegram)") @MainActor
struct KarmaTemaTestleri {
    @Test func karmaGecerliVeVarsayilan() {
        let k = SohbetTemasi.karma
        #expect(k.gecerli())
        #expect(SohbetTemasi.hazirlar.first?.ad == "Karma")
        #expect(GorunumTercihleri().sohbetTemasi == .karma)
        #expect(SohbetTemaAyarlari.vurgu("Karma") == "D97757")
        // Kart temiz: model etiketi, beğeni düğmeleri ve eylem satırı gizli; saat var.
        #expect(!k.modelAdi && !k.eylemSatiri && !k.geriBildirim && k.saat)
        // Eski profillerde alan yok → açık sayılır; Telegram/Claude'da gösterilir.
        #expect(SohbetTemasi.claude.geriBildirim && SohbetTemasi.telegram.geriBildirim)
    }
    @Test func claudeRenkleriTelegramBalonlari() {
        let k = SohbetTemasi.karma, c = SohbetTemasi.claude, t = SohbetTemasi.telegram
        // Renk ve çubuklar Claude'dan.
        #expect(k.acik.zemin == c.acik.zemin && k.koyu.zemin == c.koyu.zemin && !k.acik.desen)
        #expect(k.giris == c.giris && k.menu == c.menu && k.baslik == c.baslik && k.tarihRozeti == c.tarihRozeti && k.dugmeKenarlik == c.dugmeKenarlik)
        // Balon biçimi, yazı tipi ve saat Telegram'dan.
        #expect(k.asistanBalonlu == t.asistanBalonlu && k.kuyruk == t.kuyruk && k.kose == t.kose)
        #expect(k.asistanYaziTipi == t.asistanYaziTipi && k.kullaniciYaziTipi == t.kullaniciYaziTipi && k.saat == t.saat)
    }
    @Test func degistirilmemisClaudeKarmayaTasinirElleDegistirilenKalir() throws {
        func ayarKur(_ sohbet: SohbetTemasi?) throws -> Ayarlar {
            let ud = try #require(UserDefaults(suiteName: "karma.\(UUID().uuidString)"))
            var g = GorunumTercihleri(); g.sohbet = sohbet
            ud.set(try g.veri(), forKey: "ayar.gorunumV1")
            ud.set(true, forKey: "ayar.claudeTemaV1"); ud.set(true, forKey: "ayar.sistemTemaV1"); ud.set(true, forKey: "ayar.sadeSesModlariV1")
            return Ayarlar(defaults: ud)
        }
        #expect(try ayarKur(.claude).gorunum.sohbetTemasi == .karma)
        #expect(try ayarKur(nil).gorunum.sohbetTemasi == .karma)
        var ozel = SohbetTemasi.claude; ozel.kose = 10
        #expect(try ayarKur(ozel).gorunum.sohbetTemasi == ozel, "elle değiştirilmiş Claude teması korunur")
        #expect(try ayarKur(.telegram).gorunum.sohbetTemasi == .telegram)
    }
}
