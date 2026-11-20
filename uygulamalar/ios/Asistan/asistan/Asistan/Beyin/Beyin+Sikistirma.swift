import Foundation
import FoundationModels
import ClaudeForFoundationModels
import CoreGraphics
import UIKit

/// Uzun sohbetlerde bağlam sıkıştırma.
extension Beyin {
    /// Özete girmemiş eski mesajların (güncel soru hariç) toplam uzunluğu eşiği aşıyorsa true.
    /// P3.4: canlı oturum transcript'i bu uzunluğu aşınca da sıkıştırma gerekir (araç çıktıları ekrandaki mesajlarda görünmez).
    nonisolated static let transcriptSikistirmaEsigi = 60_000

    /// `transcriptUzunlugu`: canlı oturumun transcript ölçüsü (`transcriptUzunlugu(_:)`); oturum yoksa 0.
    nonisolated static func sikistirmaGerekli(mesajlar: [String], tabani: Int, transcriptUzunlugu: Int = 0) -> Bool {
        if transcriptUzunlugu > transcriptSikistirmaEsigi { return true }
        let hepsi = mesajlar.dropLast()
        guard hepsi.count > sikistirmadaKorunanMesaj + 1 else { return false }
        return hepsi.dropFirst(tabani).dropLast(sikistirmadaKorunanMesaj).reduce(0) { $0 + $1.count } > sikistirmaEsigi
    }

    /// P3.4: transcript'in karakter ölçüsü: prompt ve response metinleri, araç çağrısı argümanları (JSON) ve araç çıktıları.
    /// Talimat (sıkıştırmayla küçülmez) ve görsel ekler sayılmaz.
    nonisolated static func transcriptUzunlugu(_ t: Transcript) -> Int {
        func metin(_ s: [Transcript.Segment]) -> Int {
            s.reduce(0) { toplam, seg in
                switch seg {
                case .text(let m): toplam + m.content.count
                case .structure(let y): toplam + y.content.jsonString.count
                default: toplam
                }
            }
        }
        return t.reduce(0) { toplam, girdi in
            switch girdi {
            case .prompt(let p): toplam + metin(p.segments)
            case .response(let r): toplam + metin(r.segments)
            case .toolOutput(let o): toplam + metin(o.segments)
            case .toolCalls(let c): toplam + c.reduce(0) { $0 + $1.toolName.count + $1.arguments.jsonString.count }
            default: toplam
            }
        }
    }

    func baglamSikistir() async {
        // Özet beklenirken yeni sohbet açılır ya da istek iptal edilirse eski sohbetin özeti yeni sohbete yazılmamalı.
        let buNesil = nesil
        let buSohbet = sohbet?.kimlik
        let basaEklenenBaslangic = basaEklenenToplam
        let hepsi = Array(mesajlar.dropLast())
        let korunan = Self.sikistirmadaKorunanMesaj
        let eskiler = Array(hepsi.dropFirst(sikistirmaTabani).dropLast(korunan))
        guard !eskiler.isEmpty, TelefonProxy.ortak.kasaHazir else { return }
        func satir(_ m: Goruntu, _ n: Int) -> String { "\(m.rol == .kullanici ? "Kullanıcı" : "Asistan"): \(String(m.metin.prefix(n)))" }
        let girdi = (ozet.isEmpty ? "" : "Önceki özet:\n\(ozet)\n\n") + "Yeni konuşma:\n" + eskiler.map { satir($0, 1500) }.joined(separator: "\n")
        let sistem = "Aşağıdaki konuşmayı Türkçe, en fazla 12 maddede özetle: kullanıcının hedefleri, alınan kararlar, verilen önemli bilgiler (isim, sayı, tarih, tercih) ve açık kalan işler. Yorum ekleme, yeni bilgi uydurma."
        let sonuc = try? await ParalelYaris.yaris(taban: TelefonProxy.ortak.taban, anahtar: TelefonProxy.ortak.yerelAnahtar,
                                                  modeller: ["claude-haiku-4-5", "gpt-6.1-sol"], sistem: sistem,
                                                  mesajlar: [.init(rol: "user", metin: girdi)], ilkMetinSiniri: 12, akis: { _, _ in })
        guard let r = sonuc else { TaniGunlugu.yaz("BAĞLAM SIKIŞTIRMA BAŞARISIZ"); return }
        guard !Task.isCancelled, buNesil == nesil, buSohbet == sohbet?.kimlik else { return }
        ozet = r.metin
        // P3.9: özet beklenirken 'Daha eski mesajlar' başa sayfa eklediyse taban o kadar kayar (dizi başından sayılır).
        sikistirmaTabani = hepsi.count - korunan + (basaEklenenToplam - basaEklenenBaslangic)
        oturum = nil; oturumYolu = nil; oturumModeli = nil; oturumAyarImzasi = nil
        let son = hepsi.suffix(korunan).map { satir($0, 1500) }.joined(separator: "\n")
        disGecmis = [.prompt(.init(segments: [.text(.init(content: "[Önceki konuşmanın özeti — yalnız bağlam]\n\(ozet)\n\n[Son mesajlar]\n\(son)"))])),
                     .response(.init(segments: [.text(.init(content: "Anlaşıldı; bu bağlamı kullanacağım."))]))]
        // OpenClaw "memory flush": sıkıştırmada kaybolacak ayrıntılar kalıcı günlük notuna da yazılır.
        try? CalismaAlani.gunlukEkle("Konuşma özeti: " + String(ozet.prefix(500)))
        TaniGunlugu.yaz("BAĞLAM SIKIŞTIRILDI: \(eskiler.count) mesaj → özet \(ozet.count) karakter")
    }
}
