import Foundation
import MetricKit
import Observation

/// Çökme, takılma ve performans izleme (MetricKit). Veriler yalnız cihazda tutulur; hiçbir yere gönderilmez.
nonisolated struct IzlemeKaydi: Codable, Equatable, Identifiable, Sendable {
    enum Tur: String, Codable, Sendable { case cokme, takilma, cpu, disk, metrik, nabiz, uyari }
    var id = UUID()
    var zaman: Date
    var tur: Tur
    var ozet: String
}

/// Saf özetleyiciler (MetricKit nesneleri ince bir bağdaştırıcıdan geçer; mantık burada test edilir).
nonisolated enum IzlemeOzet {
    static func cokme(sinyal: Int?, istisnaTuru: Int?, sonlandirmaNedeni: String?, surum: String?) -> String {
        var p: [String] = []
        if let s = sinyal { p.append("sinyal \(s)\(sinyalAdi(s).map { " (\($0))" } ?? "")") }
        if let e = istisnaTuru { p.append("istisna \(e)") }
        if let n = sonlandirmaNedeni, !n.isEmpty { p.append("neden: \(n)") }
        if let v = surum { p.append("sürüm \(v)") }
        return p.isEmpty ? "Çökme (ayrıntı yok)" : "Çökme · " + p.joined(separator: " · ")
    }
    static func sinyalAdi(_ s: Int) -> String? { [4: "SIGILL", 5: "SIGTRAP", 6: "SIGABRT", 7: "SIGBUS", 8: "SIGFPE", 9: "SIGKILL", 11: "SIGSEGV"][s] }

    static func takilma(sureSn: Double) -> String { "Takılma · ana iş parçacığı \(String(format: "%.1f", sureSn).replacingOccurrences(of: ".", with: ",")) sn yanıt vermedi" }

    /// Günlük metrik özeti: açılış, bellek, pil/CPU.
    static func metrik(acilisMs: Double?, tepeBellekMB: Double?, cpuSn: Double?, takilmaOrani: Double?) -> String {
        var p: [String] = []
        if let a = acilisMs { p.append("açılış \(Int(a)) ms") }
        if let b = tepeBellekMB { p.append("tepe bellek \(Int(b)) MB") }
        if let c = cpuSn { p.append("CPU \(Int(c)) sn") }
        if let t = takilmaOrani { p.append("takılma \(String(format: "%.1f", t * 1000).replacingOccurrences(of: ".", with: ",")) ms/sn") }
        return p.isEmpty ? "Günlük metrik (veri yok)" : "Günlük · " + p.joined(separator: " · ")
    }
}

/// Kalıcı izleme günlüğü (son 100 kayıt). Dosya: Application Support/izleme.json
nonisolated final class IzlemeDefteri: @unchecked Sendable {
    static let ortak = IzlemeDefteri()
    static let enFazla = 100
    private let kilit = NSLock()
    private let dosya: URL
    private var kayitlar: [IzlemeKaydi]

    init(dosya: URL? = nil) {
        let taban = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
        self.dosya = dosya ?? taban.appendingPathComponent("izleme.json")
        kayitlar = (try? Data(contentsOf: self.dosya)).flatMap { try? JSONDecoder().decode([IzlemeKaydi].self, from: $0) } ?? []
    }

    func ekle(_ tur: IzlemeKaydi.Tur, _ ozet: String, zaman: Date = .now) {
        kilit.lock(); defer { kilit.unlock() }
        kayitlar.append(IzlemeKaydi(zaman: zaman, tur: tur, ozet: ozet))
        if kayitlar.count > Self.enFazla { kayitlar.removeFirst(kayitlar.count - Self.enFazla) }
        try? JSONEncoder().encode(kayitlar).write(to: dosya, options: .atomic)
        TaniGunlugu.yaz("İZLEME \(tur.rawValue): \(ozet)")
    }
    /// Yeniden eskiye.
    func hepsi() -> [IzlemeKaydi] { kilit.lock(); defer { kilit.unlock() }; return kayitlar.reversed() }
    func sayi(_ tur: IzlemeKaydi.Tur, sonGun: Int = 30, simdi: Date = .now) -> Int {
        hepsi().filter { $0.tur == tur && simdi.timeIntervalSince($0.zaman) <= Double(sonGun) * 86_400 }.count
    }
    func temizle() { kilit.lock(); kayitlar = []; try? FileManager.default.removeItem(at: dosya); kilit.unlock() }
}

/// MetricKit aboneliği: iOS çökme/takılma tanılarını ve günlük metrikleri (en geç ertesi gün) uygulamaya teslim eder.
nonisolated final class IzlemeAbonesi: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let ortak = IzlemeAbonesi()

    func baslat() { MXMetricManager.shared.add(self) }

    func didReceive(_ payloads: [MXMetricPayload]) {
        for p in payloads {
            let acilis = p.applicationLaunchMetrics?.histogrammedTimeToFirstDraw.averageMilliseconds
            let bellek = p.memoryMetrics?.peakMemoryUsage.converted(to: .megabytes).value
            let cpu = p.cpuMetrics?.cumulativeCPUTime.converted(to: .seconds).value
            let takilma = p.applicationResponsivenessMetrics?.histogrammedApplicationHangTime.averageMilliseconds
            IzlemeDefteri.ortak.ekle(.metrik, IzlemeOzet.metrik(acilisMs: acilis, tepeBellekMB: bellek, cpuSn: cpu, takilmaOrani: takilma.map { $0 / 1000 }))
        }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for p in payloads {
            for c in p.crashDiagnostics ?? [] {
                IzlemeDefteri.ortak.ekle(.cokme, IzlemeOzet.cokme(sinyal: c.signal?.intValue, istisnaTuru: c.exceptionType?.intValue,
                                                                  sonlandirmaNedeni: c.terminationReason, surum: c.applicationVersion))
            }
            for h in p.hangDiagnostics ?? [] {
                IzlemeDefteri.ortak.ekle(.takilma, IzlemeOzet.takilma(sureSn: h.hangDuration.converted(to: .seconds).value))
            }
            for c in p.cpuExceptionDiagnostics ?? [] {
                IzlemeDefteri.ortak.ekle(.cpu, "CPU aşımı · \(Int(c.totalCPUTime.converted(to: .seconds).value)) sn CPU / \(Int(c.totalSampledTime.converted(to: .seconds).value)) sn")
            }
            for d in p.diskWriteExceptionDiagnostics ?? [] {
                IzlemeDefteri.ortak.ekle(.disk, "Aşırı disk yazımı · \(Int(d.totalWritesCaused.converted(to: .megabytes).value)) MB")
            }
        }
    }
}

private nonisolated extension MXHistogram where UnitType == UnitDuration {
    /// Kova orta noktalarının sayıya göre ağırlıklı ortalaması (ms).
    var averageMilliseconds: Double? {
        var toplam = 0.0, adet = 0.0
        for k in bucketEnumerator.allObjects.compactMap({ $0 as? MXHistogramBucket<UnitDuration> }) {
            let orta = (k.bucketStart.converted(to: .milliseconds).value + k.bucketEnd.converted(to: .milliseconds).value) / 2
            toplam += orta * Double(k.bucketCount); adet += Double(k.bucketCount)
        }
        return adet > 0 ? toplam / adet : nil
    }
}
