import Foundation
import Speech
import Contacts
import CryptoKit

/// Kişisel dikte dil modeli (cihaz içi, `UyandirmaDilModeli` deseni): kişi adları (yalnız Kişiler izni zaten verilmişse; izin
/// istenmez) ve düzeltme defterindeki doğru biçimler `SFCustomLanguageModelData` ile Speech tanımasına
/// öğretilir. Model indirilmez; ses ya da metin dışarı çıkmaz. Kurulamazsa `hazirYapilandirma` nil kalır ve dinleyici
/// standart `.progressiveShortDictation` ile sürer.
@MainActor
enum DikteDilModeli {
    /// Hazır dil modeli yapılandırması; yoksa (ilk açılış, hata, ayar kapalı) nil.
    static private(set) var hazirYapilandirma: SFSpeechLanguageModel.Configuration?
    /// Son kurulumdaki ifade sayısı ve özet (Dikte sözlüğü ekranı gösterir).
    static private(set) var ifadeSayisi = 0
    static private(set) var hazirlaniyor = false
    private static var hazirlama: Task<Void, Never>?
    private static var gozlemci: (any NSObjectProtocol)?
    private static var bekleyenYeniden = false

    nonisolated static let tanimlayici = "com.mehmetderin.asistan.dikte"
    nonisolated static let enFazlaKisi = 400

    /// Ayar okuması aktör dışından da yapılır (Ayarlar.dikteSozlugu aynı anahtara yazar; varsayılan açık).
    nonisolated static var ayarAcik: Bool { UserDefaults.standard.object(forKey: "ayar.dikteSozlugu") as? Bool ?? true }

    /// Arka planda hazırlar ve bekler. Girdiler değişmediyse dosyadaki model yeniden kurulmaz. Defter değişince kendiliğinden
    /// yeniden kurulur (bildirim gözlemcisi ilk çağrıda bağlanır).
    static func hazirla(zorla: Bool = false) async {
        gozlemciKur()
        guard ayarAcik else { return }
        if let hazirlama {
            if zorla { bekleyenYeniden = true }
            await hazirlama.value
            return
        }
        hazirlaniyor = true
        let defter = DikteDuzeltmeDefteri.ortak.dogruBicimler()
        let is_ = Task<Void, Never> {
            let kisiler = await Self.kisiAdlariOku()
            let ifadeler = Self.ifadeler(kisiler: kisiler, defter: defter)
            let sonuc = await Self.olustur(ifadeler, zorla: zorla)
            hazirYapilandirma = sonuc
            ifadeSayisi = sonuc == nil ? 0 : ifadeler.count
        }
        hazirlama = is_
        await is_.value
        hazirlama = nil
        hazirlaniyor = false
        if bekleyenYeniden { bekleyenYeniden = false; await hazirla() }
    }

    /// Dinlemeyi bekletmeden başlatır (SesDinleyici'nin ilk `basla`'sı).
    static func arkadaHazirla() {
        guard hazirYapilandirma == nil, hazirlama == nil, ayarAcik else { gozlemciKur(); return }
        Task { await hazirla() }
    }

    private static func gozlemciKur() {
        guard gozlemci == nil else { return }
        // Bildirim herhangi bir iş parçacığından gelebilir: kapanış @Sendable, iş ana aktöre aktarılır.
        // Yalnız ortak defter (testlerin geçici defterleri dil modelini yeniden kurdurmaz).
        gozlemci = NotificationCenter.default.addObserver(forName: DikteDuzeltmeDefteri.degisti, object: DikteDuzeltmeDefteri.ortak, queue: .main) { @Sendable _ in
            Task { @MainActor in
                if hazirlama != nil { bekleyenYeniden = true } else { await hazirla() }
            }
        }
    }

    // MARK: girdiler (saf)

    /// Kişiler + defter: tekrarsız (harf büyüklüğü katlanmış), sıralı, boşluksuz.
    nonisolated static func ifadeler(kisiler: [String], defter: [String]) -> [String] {
        var gorulen = Set<String>(), sonuc: [String] = []
        for s in kisiler.prefix(enFazlaKisi) + defter {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard t.count >= 2, gorulen.insert(t.lowercased(with: Locale(identifier: "tr_TR"))).inserted else { continue }
            sonuc.append(t)
        }
        return sonuc
    }

    /// Girdilerin sıra bağımsız, kararlı özeti (SHA256'nın ilk 12 onaltılık karakteri): dosya adı `dikte-<ozet>.lm`.
    nonisolated static func girdiOzeti(_ ifadeler: [String]) -> String {
        let birlesik = ifadeler.map { $0.lowercased(with: Locale(identifier: "tr_TR")) }.sorted().joined(separator: "\n")
        let ozet = SHA256.hash(data: Data(birlesik.utf8))
        return String(ozet.map { String(format: "%02x", $0) }.joined().prefix(12))
    }

    // MARK: kurulum (aktör dışı)

    /// Kişiler izni zaten verilmişse ad + soyadlar; izin yoksa boş (izin İSTENMEZ).
    @concurrent nonisolated private static func kisiAdlariOku() async -> [String] {
        let durum = CNContactStore.authorizationStatus(for: .contacts)
        guard durum == .authorized || durum == .limited else { return [] }
        let depo = CNContactStore()
        let istek = CNContactFetchRequest(keysToFetch: [CNContactGivenNameKey as CNKeyDescriptor, CNContactFamilyNameKey as CNKeyDescriptor])
        var adlar: [String] = []
        try? depo.enumerateContacts(with: istek) { kisi, dur in
            let ad = [kisi.givenName, kisi.familyName].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
            if !ad.isEmpty { adlar.append(ad) }
            if adlar.count >= enFazlaKisi { dur.pointee = true }
        }
        return adlar
    }

    @concurrent nonisolated private static func olustur(_ ifadeler: [String], zorla: Bool) async -> SFSpeechLanguageModel.Configuration? {
        guard !ifadeler.isEmpty else { return nil }
        let fm = FileManager.default
        let kok = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "DikteDilModeli", directoryHint: .isDirectory)
        let ozet = girdiOzeti(ifadeler)
        let veri = kok.appending(path: "dikte-\(ozet).bin")
        let model = kok.appending(path: "dikte-\(ozet).lm")
        do {
            try fm.createDirectory(at: kok, withIntermediateDirectories: true)
            // Eski sürümlerin dosyaları silinir (girdiler değişti); bu sürüm değişmediyse yeniden kurulmaz.
            for u in (try? fm.contentsOfDirectory(at: kok, includingPropertiesForKeys: nil)) ?? []
            where u.lastPathComponent.hasPrefix("dikte-") && !u.lastPathComponent.hasPrefix("dikte-\(ozet).") {
                try? fm.removeItem(at: u)
            }
            let ayar = SFSpeechLanguageModel.Configuration(languageModel: model)
            if zorla || !fm.fileExists(atPath: model.path) {
                let egitim = SFCustomLanguageModelData(locale: Locale(identifier: "tr_TR"), identifier: tanimlayici, version: "1")
                for s in ifadeler { egitim.insert(phraseCount: SFCustomLanguageModelData.PhraseCount(phrase: s, count: 100)) }
                try await egitim.export(to: veri)
                try await withCheckedThrowingContinuation { (devam: CheckedContinuation<Void, Error>) in
                    SFSpeechLanguageModel.prepareCustomLanguageModel(for: veri, configuration: ayar) { @Sendable hata in
                        if let hata { devam.resume(throwing: hata) } else { devam.resume() }
                    }
                }
            }
            return ayar
        } catch {
            TaniGunlugu.yaz("DİKTE DİL MODELİ kurulamadı: \((error as NSError).domain) \((error as NSError).code)")
            return nil
        }
    }
}
