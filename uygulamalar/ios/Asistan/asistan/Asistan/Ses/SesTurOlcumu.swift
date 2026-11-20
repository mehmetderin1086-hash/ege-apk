import Foundation

/// Sıralı sesli tur ölçümü (SesDinleyici → Beyin → Konusmaci): kullanıcının sözü bittikten asistanın ilk sesine
/// kadar geçen süre ve aşamaları. Gerçek zamanlı motorlar (OpenAI Realtime / Gemini Live) bu ölçüme girmez.
/// Yalnız zaman damgası tutar; metin/ses içeriği yoktur.
nonisolated struct SesTurOlcumu: Equatable, Sendable {
    /// Son sesli blok (dinleyici); yoksa/distantPast ise `kesinlesme` taban alınır.
    var sonSes: Date?
    /// Dinleyici metni kesinleştirdi (kullaniciKonustu).
    var kesinlesme: Date?
    /// `beyin.gonder` çağrıldı.
    var gonderim: Date?
    /// Modelden ilk boş olmayan metin geldi.
    var ilkMetin: Date?
    /// İlk cümle seslendirme kuyruğuna alındı (TTS üretimi başladı).
    var ilkTTS: Date?
    /// İlk ses çalmaya başladı.
    var ilkOynatma: Date?
    /// "normal" | "eller-serbest" | "live"
    var kip: String

    init(sonSes: Date? = nil, kesinlesme: Date? = nil, gonderim: Date? = nil, ilkMetin: Date? = nil,
         ilkTTS: Date? = nil, ilkOynatma: Date? = nil, kip: String) {
        self.sonSes = sonSes; self.kesinlesme = kesinlesme; self.gonderim = gonderim
        self.ilkMetin = ilkMetin; self.ilkTTS = ilkTTS; self.ilkOynatma = ilkOynatma; self.kip = kip
    }

    nonisolated struct Asama: Equatable, Sendable {
        let tur: String
        let sure: TimeInterval
    }

    /// SaglikMerkezi'ne yazılacak aşamalar (saf). İlk oynatma ya da kesinleşme yoksa ya da ana sıra bozuksa
    /// (söz bitti > kesinleşme > ilk ses sırası tutmuyorsa) nil. Kendi içinde sırası bozuk ara aşama
    /// (ör. ilk metin gönderimden önce) atlanır, öbürleri yazılır.
    func asamalar() -> [Asama]? {
        guard let oynatma = ilkOynatma, let kesin = kesinlesme else { return nil }
        let taban: Date = if let s = sonSes, s > .distantPast, s <= kesin { s } else { kesin }
        let toplam = oynatma.timeIntervalSince(taban)
        let bekleme = kesin.timeIntervalSince(taban)
        guard toplam >= 0, bekleme >= 0, oynatma >= kesin else { return nil }
        var sonuc = [Asama(tur: "ses_tur", sure: toplam), Asama(tur: "ses_tur_bekleme", sure: bekleme)]
        if let g = gonderim, let m = ilkMetin, m >= g {
            sonuc.append(Asama(tur: "ses_tur_model", sure: m.timeIntervalSince(g)))
        }
        if let t = ilkTTS, oynatma >= t {
            sonuc.append(Asama(tur: "ses_tur_tts", sure: oynatma.timeIntervalSince(t)))
        }
        return sonuc
    }
}
