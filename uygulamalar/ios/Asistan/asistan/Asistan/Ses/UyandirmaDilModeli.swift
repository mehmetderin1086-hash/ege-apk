import Foundation
import Speech

/// Uyandırma sözcüklerini cihaz içi Speech tanımasına öğretir.
/// Oluşturma başarısızsa çağıran standart Apple kısa-ifadeye döner; ses veya metin kaydı tutulmaz.
@MainActor
enum UyandirmaDilModeli {
    private static var yapilandirma: SFSpeechLanguageModel.Configuration?
    private static var hazirlama: Task<SFSpeechLanguageModel.Configuration?, Never>?

    static func hazirla() async -> SFSpeechLanguageModel.Configuration? {
        if let yapilandirma { return yapilandirma }
        if let hazirlama { return await hazirlama.value }
        let is_ = Task<SFSpeechLanguageModel.Configuration?, Never> {
            await olustur()
        }
        hazirlama = is_
        let sonuc = await is_.value
        hazirlama = nil
        yapilandirma = sonuc
        return sonuc
    }

    private nonisolated static func olustur() async -> SFSpeechLanguageModel.Configuration? {
        let kok = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "UyandirmaDilModeli", directoryHint: .isDirectory)
        // v2: yalnız çağrı sözü yerine, yaygın devam komutlarını da öğretir.
        // Böylece tanıyıcı ilk "Hey" hecesini ya da çağrıdan sonraki kısa
        // komutu daha az düşürür. Eski model korunur; yeni sürüm ayrı hazırlanır.
        let veri = kok.appending(path: "hey-asistan-v2.bin")
        let model = kok.appending(path: "hey-asistan-v2.lm")
        do {
            try FileManager.default.createDirectory(at: kok, withIntermediateDirectories: true)
            let ayar = SFSpeechLanguageModel.Configuration(languageModel: model)
            if !FileManager.default.fileExists(atPath: model.path) {
                let egitim = SFCustomLanguageModelData(locale: Locale(identifier: "tr_TR"), identifier: "com.mehmetderin.asistan.hey", version: "1") {
                    SFCustomLanguageModelData.PhraseCount(phrase: "Hey Asistan", count: 2_000)
                    SFCustomLanguageModelData.PhraseCount(phrase: "Ey Asistan", count: 700)
                    SFCustomLanguageModelData.PhraseCount(phrase: "Hey Assistant", count: 600)
                    SFCustomLanguageModelData.PhraseCount(phrase: "Hey Asistan saat kaç", count: 500)
                    SFCustomLanguageModelData.PhraseCount(phrase: "Hey Asistan beni duyuyor musun", count: 350)
                    SFCustomLanguageModelData.PhraseCount(phrase: "Hey Asistan müzik aç", count: 300)
                    SFCustomLanguageModelData.PhraseCount(phrase: "Hey Asistan mesaj yaz", count: 300)
                }
                try await egitim.export(to: veri)
                try await withCheckedThrowingContinuation { (devam: CheckedContinuation<Void, Error>) in
                    SFSpeechLanguageModel.prepareCustomLanguageModel(for: veri, configuration: ayar) { hata in
                        if let hata { devam.resume(throwing: hata) }
                        else { devam.resume() }
                    }
                }
            }
            return ayar
        } catch {
            return nil
        }
    }
}
