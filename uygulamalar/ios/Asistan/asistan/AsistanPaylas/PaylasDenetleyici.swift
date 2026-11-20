import SwiftUI
import UIKit
import UniformTypeIdentifiers
import UserNotifications

/// "Asistan'a gönder" paylaşım uzantısı: seçilen içeriği ve isteği ortak kutuya yazar, bildirimle Asistan'a devreder.
final class PaylasDenetleyici: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let saglayicilar = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        let kap = UIHostingController(rootView: PaylasGorunumu(saglayicilar: saglayicilar, bitir: { [weak self] gonderildi in
            if gonderildi { self?.extensionContext?.completeRequest(returningItems: nil) }
            else { self?.extensionContext?.cancelRequest(withError: CocoaError(.userCancelled)) }
        }))
        addChild(kap)
        kap.view.frame = view.bounds
        kap.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(kap.view)
        kap.didMove(toParent: self)
    }
}

/// Paylaşılan tek parça (yüklenmiş, Sendable).
nonisolated enum PaylasilanParca: Sendable {
    case metin(String)
    case baglanti(String)
    /// Dosya belleğe okunmaz: uzantının geçici klasöründeki kopyası (uzantı belleği ~120 MB).
    case dosya(ad: String, url: URL, boyut: Int)
}

/// NSItemProvider yükleyicisi: tamamlayıcılar sistem kuyruğunda çağrılır (ana aktöre bağlı değil).
nonisolated enum ParcaYukleyici {
    static let dosyaSiniri = 25_000_000
    static let toplamSinir = 60_000_000

    static func yukle(_ p: NSItemProvider) async -> PaylasilanParca? {
        nonisolated(unsafe) let s = p
        if s.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            return await dosya(s, UTType.image.identifier).map { .dosya(ad: (s.suggestedName ?? "foto") + ".jpg", url: $0.url, boyut: $0.boyut) }
        }
        if s.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
            return await dosya(s, UTType.pdf.identifier).map { .dosya(ad: (s.suggestedName ?? "belge") + ".pdf", url: $0.url, boyut: $0.boyut) }
        }
        if s.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let u = await oge(s, UTType.url.identifier) as? URL {
                if u.isFileURL {
                    guard let k = kopyala(u) else { return nil }
                    return .dosya(ad: u.lastPathComponent, url: k.url, boyut: k.boyut)
                }
                return .baglanti(u.absoluteString)
            }
        }
        if s.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            if let t = await oge(s, UTType.plainText.identifier) as? String { return .metin(String(t.prefix(PaylasimKutusu.metinSiniri))) }
        }
        if s.hasItemConformingToTypeIdentifier(UTType.data.identifier) {
            // Dosya adına türün uzantısı eklenir (uygulama belgeyi uzantıya göre okur).
            let tur = s.registeredTypeIdentifiers.compactMap { UTType($0) }.first { $0.preferredFilenameExtension != nil }
            var ad = s.suggestedName ?? "dosya"
            if let u = tur?.preferredFilenameExtension, !ad.lowercased().hasSuffix("." + u) { ad += "." + u }
            return await dosya(s, UTType.data.identifier).map { .dosya(ad: ad, url: $0.url, boyut: $0.boyut) }
        }
        return nil
    }

    /// Boyutu okumadan önce belleğe almaz: dosya temsilini ister, 25 MB üstünü reddeder, sığanı geçici klasöre kopyalar.
    private static func dosya(_ p: NSItemProvider, _ tur: String) async -> (url: URL, boyut: Int)? {
        nonisolated(unsafe) let s = p
        let sonuc: Kopya? = await withCheckedContinuation { (d: CheckedContinuation<Kopya?, Never>) in
            // Sistem geçici URL'yi tamamlayıcı dönünce siler: kopya burada, eşzamanlı yapılmalı.
            _ = s.loadFileRepresentation(forTypeIdentifier: tur) { @Sendable u, _ in
                d.resume(returning: u.flatMap { kopyala($0) }.map { Kopya(url: $0.url, boyut: $0.boyut) })
            }
        }
        return sonuc.map { ($0.url, $0.boyut) }
    }

    nonisolated struct Kopya: Sendable { let url: URL; let boyut: Int }

    /// Dosyayı (25 MB sınırı içinde) uzantının geçici klasörüne kopyalar; veri belleğe okunmaz.
    static func kopyala(_ u: URL) -> (url: URL, boyut: Int)? {
        let erisim = u.startAccessingSecurityScopedResource(); defer { if erisim { u.stopAccessingSecurityScopedResource() } }
        guard let boyut = try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize, boyut <= dosyaSiniri else { return nil }
        let hedef = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-" + u.lastPathComponent)
        guard (try? FileManager.default.copyItem(at: u, to: hedef)) != nil else { return nil }
        return (hedef, boyut)
    }

    private static func oge(_ p: NSItemProvider, _ tur: String) async -> Any? {
        nonisolated(unsafe) let s = p
        let sonuc: (url: URL?, metin: String?) = await withCheckedContinuation { d in
            s.loadItem(forTypeIdentifier: tur, options: nil) { @Sendable o, _ in
                d.resume(returning: (o as? URL, (o as? String) ?? (o as? Data).flatMap { String(data: $0, encoding: .utf8) }))
            }
        }
        return sonuc.url ?? sonuc.metin
    }
}

struct PaylasGorunumu: View {
    let saglayicilar: [NSItemProvider]
    let bitir: (Bool) -> Void
    @State private var parcalar: [PaylasilanParca] = []
    @State private var yukleniyor = true
    @State private var istem = ""
    @State private var gonderildi = false
    @State private var hata: String?
    /// Vazgeç basıldı: yükleme sürüyorsa sonradan kopyalanan dosya da hemen silinir.
    @State private var vazgecildi = false

    /// Uzantının geçici klasörüne kopyalanmış (henüz kutuya taşınmamış) dosyalar.
    private var geciciURLler: [URL] {
        parcalar.compactMap { p -> URL? in
            if case .dosya(_, let u, _) = p { return u }
            return nil
        }
    }

    /// Gönderilmeyen kopyaları siler (büyük PDF'ler uzantı kapsayıcısında birikmesin).
    private func temizle() { PaylasimKutusu.geciciDosyalariSil(geciciURLler) }

    /// Hızlı eylemler (etiket, istem): belge paylaşılınca başa "Özetle ve son tarihi kur" gelir (`PaylasimKutusu.hizliEylemler`).
    private var hizliEylemler: [(etiket: String, istem: String)] {
        PaylasimKutusu.hizliEylemler(dosyaAdlari: parcalar.compactMap { p -> String? in
            if case .dosya(let ad, _, _) = p { return ad }
            return nil
        })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Paylaşılan") {
                    if yukleniyor { ProgressView("İçerik okunuyor…") }
                    ForEach(Array(parcalar.enumerated()), id: \.offset) { _, p in
                        switch p {
                        case .metin(let t): Label(String(t.prefix(120)), systemImage: "text.alignleft").lineLimit(3)
                        case .baglanti(let b): Label(b, systemImage: "link").lineLimit(2)
                        case .dosya(let ad, _, let boyut): Label("\(ad) · \(ByteCountFormatter.string(fromByteCount: Int64(boyut), countStyle: .file))", systemImage: "doc")
                        }
                    }
                    if !yukleniyor, parcalar.isEmpty { Text("Desteklenen içerik bulunamadı.").foregroundStyle(.secondary) }
                }
                Section("Ne yapayım?") {
                    TextField("Örn. Özetle, takvime ekle…", text: $istem, axis: .vertical).lineLimit(1...4)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            let eylemler = hizliEylemler
                            ForEach(eylemler.indices, id: \.self) { n in
                                Button(eylemler[n].etiket) { istem = eylemler[n].istem }.buttonStyle(.bordered)
                            }
                        }
                    }
                }
                if gonderildi {
                    Section { Label("Asistan'a gönderildi. Bildirime dokununca ya da Asistan'ı açınca başlar.", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                }
                if let hata { Section { Text(hata).foregroundStyle(.red) } }
            }
            .navigationTitle("Asistan'a gönder").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { vazgecildi = true; temizle(); bitir(false) } }
                ToolbarItem(placement: .confirmationAction) { Button("Gönder", action: gonder).disabled(yukleniyor || parcalar.isEmpty || gonderildi) }
            }
            .task {
                var toplam = 0, alinamayan = 0
                for s in saglayicilar {
                    guard let p = await ParcaYukleyici.yukle(s) else {
                        if vazgecildi || Task.isCancelled { break }
                        alinamayan += 1; continue
                    }
                    // Yükleme sürerken Vazgeç/kapatma: yeni kopya listeye girmeden silinir, kalan sağlayıcılar okunmaz.
                    if vazgecildi || Task.isCancelled {
                        if case .dosya(_, let u, _) = p { PaylasimKutusu.geciciDosyalariSil([u]) }
                        break
                    }
                    if case .dosya(_, let url, let boyut) = p {
                        // Toplam sınır: birkaç büyük dosya birlikte uzantı belleğini/ana uygulamayı zorlamasın.
                        guard toplam + boyut <= ParcaYukleyici.toplamSinir else { try? FileManager.default.removeItem(at: url); alinamayan += 1; continue }
                        toplam += boyut
                    }
                    parcalar.append(p)
                }
                if alinamayan > 0, !parcalar.isEmpty { hata = "\(alinamayan) öğe alınamadı (dosya başına 25 MB, toplam 60 MB sınırı ya da desteklenmeyen biçim)." }
                yukleniyor = false
            }
            // Aşağı kaydırarak kapatma (Vazgeç'e basılmadan). Gönderilmişse dosyalar kutuya taşınmıştır;
            // başarısız gönderimde geriTasi onları geri koyduğu için burada silinirler.
            .onDisappear { if !gonderildi { temizle() } }
        }
    }

    private func gonder() {
        var istek = PaylasimKutusu.Istek(istem: istem)
        var dosyalar: [(ad: String, url: URL)] = []
        for p in parcalar {
            switch p {
            case .metin(let t):
                guard istek.metin.count < PaylasimKutusu.metinSiniri else { break }
                istek.metin += (istek.metin.isEmpty ? "" : "\n\n") + t
                istek.metin = String(istek.metin.prefix(PaylasimKutusu.metinSiniri))
            case .baglanti(let b): istek.baglanti = b
            case .dosya(let ad, let url, _): dosyalar.append((ad, url))
            }
        }
        do {
            try PaylasimKutusu.yaz(istek, dosyaURLleri: dosyalar)
            let c = UNMutableNotificationContent()
            c.title = "Asistan'a gönderildi"
            c.body = (istem.isEmpty ? "Paylaşılan içerik" : istem) + " — başlatmak için dokun."
            c.userInfo = [PaylasimKutusu.bildirimAnahtari: istek.id.uuidString]
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "paylasim-\(istek.id)", content: c, trigger: nil))
            gonderildi = true
            Task { try? await Task.sleep(for: .seconds(1.2)); bitir(true) }
        } catch {
            hata = "Kaydedilemedi: \(error.localizedDescription)"
        }
    }
}
