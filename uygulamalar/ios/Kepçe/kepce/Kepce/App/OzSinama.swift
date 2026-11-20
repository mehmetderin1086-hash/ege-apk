import AVFoundation
import Foundation

/// Uçtan uca öz sınama: `-ozSinama [adres]` açılış argümanıyla çalışır, sonucu konsola yazar ve uygulamayı kapatır.
/// XCTest'ten bağımsızdır; telefonda `devicectl device process launch --console` ile de çalıştırılabilir.
enum OzSinama {
    static var istendi: Bool { ProcessInfo.processInfo.arguments.contains("-ozSinama") || topluIstendi }
    static var topluIstendi: Bool { ProcessInfo.processInfo.arguments.contains("-ozSinamaToplu") }

    /// Kanal → liste çözme → sıraya toplu ekleme → paralel indirme → kütüphane; sonra eklenenleri siler.
    static func toplu() async {
        func yaz(_ s: String) { print("ÖZSINAMA \(s)"); fflush(stdout) }
        let kuyruk = IndirmeKuyrugu.shared, kutuphane = Kutuphane.shared
        do {
            var t = Date()
            let liste = try await PythonMotoru.shared.coz("https://www.youtube.com/@BlenderOfficial", liste: true, sinir: 6)
            let ogeler = (liste.entries ?? []).compactMap { e in e.adres.map { IndirmeKuyrugu.TopluOge(adres: $0, baslik: e.title, kapak: e.thumbnail, sure: e.duration) } }
            yaz("liste '\(liste.title ?? "?")' \(ogeler.count) öğe \(String(format: "%.1f", Date().timeIntervalSince(t))) sn")
            var secim = IndirmeSecimi.hizli(.ses)
            secim.altKlasor = "Kepçe öz sınama"
            secim.liste = liste.title
            let once = Set(kuyruk.isler.map(\.id))
            let sonuc = kuyruk.topluEkle(ogeler, secim: secim, numarala: true, atla: false)
            let yeni = Set(kuyruk.isler.map(\.id)).subtracting(once)
            yaz("eklendi \(sonuc.eklenen), atlandı \(sonuc.atlanan), eşzamanlı \(Ayarlar.shared.esZamanli)")
            t = Date()
            var enCokEtkin = 0
            while Date().timeIntervalSince(t) < 600 {
                let bunlar = kuyruk.isler.filter { yeni.contains($0.id) }
                enCokEtkin = max(enCokEtkin, bunlar.filter { $0.durum.etkin }.count)
                if bunlar.allSatisfy({ $0.durum == .tamam || $0.durum == .hata }) { break }
                try await Task.sleep(for: .milliseconds(500))
            }
            let bunlar = kuyruk.isler.filter { yeni.contains($0.id) }
            let biten = bunlar.filter { $0.durum == .tamam }
            let bayt = biten.compactMap { $0.kutuphaneID }.compactMap { id in kutuphane.ogeler.first { $0.id == id }?.boyut }.reduce(0, +)
            yaz("bitti \(biten.count)/\(bunlar.count), en çok \(enCokEtkin) paralel, \(BicimSecici.boyutMetni(bayt)) \(String(format: "%.1f", Date().timeIntervalSince(t))) sn")
            for h in bunlar where h.durum == .hata { yaz("hata: \(h.hata ?? "")") }
            if let ilk = biten.first?.kutuphaneID, let oge = kutuphane.ogeler.first(where: { $0.id == ilk }) { yaz("örnek dosya \(oge.dosya) liste=\(oge.liste ?? "-")") }
            for h in bunlar {
                if let id = h.kutuphaneID, let oge = kutuphane.ogeler.first(where: { $0.id == id }) { kutuphane.sil(oge) }
                kuyruk.kaldir(h.id)
            }
            try? FileManager.default.removeItem(at: Kutuphane.klasor(.ses).appending(path: "Kepçe öz sınama"))
            yaz(biten.count == bunlar.count && enCokEtkin > 1 ? "SONUÇ BAŞARILI" : "SONUÇ BAŞARISIZ")
            exit(biten.count == bunlar.count ? 0 : 1)
        } catch {
            yaz("HATA \(error.localizedDescription)")
            yaz("SONUÇ BAŞARISIZ")
            exit(1)
        }
    }

    static func calistir() async {
        let argumanlar = ProcessInfo.processInfo.arguments
        let adres = argumanlar.drop { $0 != "-ozSinama" }.dropFirst().first ?? "https://www.youtube.com/watch?v=aqz-KE-bpKQ"
        func yaz(_ s: String) { print("ÖZSINAMA \(s)"); fflush(stdout) }
        var basarili = true
        do {
            var t = Date()
            let surum = try await PythonMotoru.shared.surum()
            yaz("motor python=\(surum.python) yt-dlp=\(surum.yt_dlp) ejs=\(surum.ejs) \(String(format: "%.1f", Date().timeIntervalSince(t))) sn")
            t = Date()
            let bilgi = try await PythonMotoru.shared.coz(adres)
            yaz("çözüm '\(bilgi.title ?? "?")' biçim=\(bilgi.formats?.count ?? 0) \(String(format: "%.1f", Date().timeIntervalSince(t))) sn")
            yaz("kaliteler \(BicimSecici.kaliteler(bilgi).map(\.id).joined(separator: ",")) av1=\(BicimSecici.av1Donanim)")
            guard let plan = BicimSecici.plan(bilgi, tur: .video, enFazla: 360) else { throw PythonMotoru.Hata.cozum("plan yok") }
            let klasor = FileManager.default.temporaryDirectory.appending(path: "ozsinama-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: klasor, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: klasor) }
            t = Date()
            let vs = IlerlemeSayaci(), ss = IlerlemeSayaci()
            let vd = plan.video.map { IndirmeKuyrugu.calismaDosyasi(klasor, "video", $0) }, sd = plan.ses.map { IndirmeKuyrugu.calismaDosyasi(klasor, "ses", $0) }
            if let v = plan.video, let vd { try await AkisIndirici.indir(v, hedef: vd, baglanti: 4, sayac: vs, sure: bilgi.duration) }
            if let s = plan.ses, let sd { try await AkisIndirici.indir(s, hedef: sd, baglanti: 2, sayac: ss, sure: bilgi.duration) }
            let sure = Date().timeIntervalSince(t)
            let toplam = vs.alinan + ss.alinan
            yaz("indirme \(plan.etiket) \(BicimSecici.boyutMetni(toplam)) \(String(format: "%.1f", sure)) sn \(BicimSecici.boyutMetni(Int64(Double(toplam) / max(sure, 0.1))))/sn")
            t = Date()
            let cikis = klasor.appending(path: "cikis.mp4")
            try await Birlestirici.birlestir(video: vd, ses: sd,
                                             cikis: cikis, yalnizSes: false, etiket: MedyaEtiketi(baslik: bilgi.title ?? "Öz sınama"), kesit: nil)
            let varlik = AVURLAsset(url: cikis)
            let v = try await varlik.loadTracks(withMediaType: .video).count, a = try await varlik.loadTracks(withMediaType: .audio).count
            let d = try await varlik.load(.duration).seconds
            yaz("birleştirme görüntü=\(v) ses=\(a) süre=\(Int(d)) sn (beklenen \(Int(bilgi.duration ?? 0))) \(String(format: "%.1f", Date().timeIntervalSince(t))) sn")
            if v != 1 || a != 1 || abs(d - (bilgi.duration ?? d)) > 2 { basarili = false }
            // Ses: M4A + kesit + etiket
            if let ses = BicimSecici.sesler(bilgi).last {
                let s2 = klasor.appending(path: "ses2.m4a")
                try await AkisIndirici.indir(ses, hedef: s2, baglanti: 4, sayac: IlerlemeSayaci(), sure: bilgi.duration)
                let m4a = klasor.appending(path: "kesit.m4a")
                try await Birlestirici.birlestir(video: nil, ses: s2, cikis: m4a, yalnizSes: true,
                                                 etiket: MedyaEtiketi(baslik: "Kesit", sanatci: "Kepçe"), kesit: 10...20)
                let ksure = try await AVURLAsset(url: m4a).load(.duration).seconds
                yaz("ses kesiti \(String(format: "%.1f", ksure)) sn (beklenen 10)")
                if abs(ksure - 10) > 0.6 { basarili = false }
            }
            t = Date()
            let arama = try await PythonMotoru.shared.ara("blender open movie", adet: 5)
            yaz("arama \(arama.entries?.count ?? 0) sonuç \(String(format: "%.1f", Date().timeIntervalSince(t))) sn")
        } catch {
            basarili = false
            yaz("HATA \(error.localizedDescription)")
        }
        yaz(basarili ? "SONUÇ BAŞARILI" : "SONUÇ BAŞARISIZ")
        exit(basarili ? 0 : 1)
    }
}
