import UIKit

/// Paylaş menüsünden kutuya düşen işleri sırayla Asistan'a verir (fotoğraflar görsel, belgeler metin olarak).
@MainActor
enum PaylasimAlici {
    nonisolated static let resimUzantilari: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "tiff"]
    private static var isleniyor = false
    private static var siraBekleniyor = false

    /// Asistan boşta ve çevrimiçiyse en eski bekleyen paylaşımı gönderir. Belge okuma (PDF OCR) ana iş parçacığı dışında yapılır.
    /// Paylaşım kutudan yalnız istek gerçekten başladıktan sonra silinir (çevrimdışı kuyruk bellekte kalıcı değildir).
    /// Asistan meşgulse sıradaki paylaşım yanıt bitince kendiliğinden başlar (uygulamadan çıkıp dönmek gerekmez).
    static func isle(_ beyin: Beyin) {
        guard !isleniyor, AgIzleyici.ortak.cevrimici else { return }
        guard beyin.durum == .bosta else {
            if !PaylasimKutusu.bekleyenler().isEmpty { sirayiBekle(beyin) }
            return
        }
        guard let (istek, klasor) = PaylasimKutusu.bekleyenler().first else { return }
        isleniyor = true
        let urller = istek.dosyalar.map { klasor.appendingPathComponent($0) }
        let oncekiNesil = beyin.nesil
        Task {
            defer { isleniyor = false }
            let (gorseller, belgeler) = await Task.detached(priority: .userInitiated) { () -> ([CGImage], [String]) in
                var g: [CGImage] = [], b: [String] = []
                for url in urller {
                    if resimUzantilari.contains(url.pathExtension.lowercased()) {
                        if let r = (try? Data(contentsOf: url)).flatMap(UIImage.init(data:)), let cg = r.kucultulmus(1600) { g.append(cg) }
                    } else if let o = try? BelgeOkuyucu.oku(url, ekKopyasi: true) {   // P2.12: paylaşılan PDF pdfIslem'e kaynak olabilir
                        b.append("Dosya: \(o.ad)\n\(o.not)\n\(o.metin)")
                    } else {
                        b.append("Dosya: \(url.lastPathComponent) — içerik okunamadı (desteklenmeyen biçim).")
                    }
                }
                return (g, b)
            }.value
            // Belge okunurken kullanıcı mesaj gönderdiyse ya da hâlâ hazırlıyorsa (görsel küçültme) önce o gitsin:
            // kısa sessizlikten sonra Asistan hâlâ boşta ve araya başka tur girmemişse paylaşım başlar, yoksa sırayı bekler.
            if beyin.durum == .bosta { try? await Task.sleep(for: DisSoruKuyrugu.sessizlik) }
            guard beyin.durum == .bosta, beyin.nesil == oncekiNesil, AgIzleyici.ortak.cevrimici else {
                if AgIzleyici.ortak.cevrimici { sirayiBekle(beyin) }
                return
            }
            // Paylaşım yönergesindeki "/yeni" gibi metin yerel komut olarak çalışmaz: komut yolu Asistan'ı meşgul etmediği için
            // paylaşım kutudan hiç silinmez, her öne gelişte yinelenirdi.
            let goster = !PaylasimKutusu.disKaynakMi(istek)
            beyin.gonder(DisSoruKuyrugu.komutuEtkisizlestir(PaylasimKutusu.istemMetni(istek)), ekGorseller: gorseller, belge: belgeler.isEmpty ? nil : belgeler.joined(separator: "\n\n"),
                         gorunenMetin: (goster ? "👁️ " : "📤 ") + (istek.istem.isEmpty ? (goster ? "Ekran görüntüsü / dosya" : "Paylaşılan içerik") : istek.istem),
                         // Paylaş menüsündeki metin/bağlantı başka uygulamadan gelir: yan etkili adımlar sorulur; görseller kaydedilir.
                         // "Asistan'a göster" kullanıcının kendi kestirmesidir, dış kaynak sayılmaz; ama belge (PDF/metin) varsa
                         // Beyin.disKaynakliTur turu yine dış kaynaklı yapar (belgenin içeriği güvenilmez veridir).
                         disKaynak: PaylasimKutusu.disKaynakMi(istek))
            if beyin.durum != .bosta {
                PaylasimKutusu.sil(klasor)
                if !PaylasimKutusu.bekleyenler().isEmpty { sirayiBekle(beyin) }
            }
        }
    }

    /// Yanıt bitince sıradaki paylaşımı başlatır; yalnız uygulama öndeyken. Asistan `DisSoruKuyrugu.sessizlik` boyunca
    /// kesintisiz boşta görülmeden başlamaz (seslendirme/mikrofon ve kullanıcının hazırladığı mesaj önce); Durdur / Yeni sohbet
    /// sonrası daha uzun bekler (söz kesen sesli komut önce gelsin). Karar `DisSoruKuyrugu.karar` ile ortaktır.
    /// En çok ~30 dk bekler; aşılırsa sahne yeniden etkinleşince `isle` zaten çağrılır.
    private static func sirayiBekle(_ beyin: Beyin) {
        guard !siraBekleniyor else { return }
        siraBekleniyor = true
        let koken = ContinuousClock.now
        Task {
            var g = DisSoruKuyrugu.Gozlem(bostaBaslangic: nil, nesil: beyin.nesil)
            var hazir = false
            for _ in 0..<3_600 {
                try? await Task.sleep(for: DisSoruKuyrugu.yoklamaAraligi)
                // Paylaşım kullanıcının kendi işidir: müdahale sonrası bırakılmaz, yalnız daha uzun beklenir.
                if DisSoruKuyrugu.karar(&g, simdi: ContinuousClock.now - koken, bosta: beyin.durum == .bosta, nesil: beyin.nesil, disKaynak: false) == .gonder {
                    hazir = true; break
                }
            }
            siraBekleniyor = false
            guard hazir, UIApplication.shared.applicationState == .active else { return }
            isle(beyin)   // durum yine meşgulse isle bekleyişi yeniden kurar
        }
    }
}
