import Foundation
import AVFoundation

/// VPS'teki aktarıcı üzerinden OpenAI ses dökümü (gpt-4o-transcribe → whisper-1). Anahtar sunucuda; uygulama kişisel anahtarla gelir.
nonisolated struct WhisperIstemcisi: Sendable {
    struct Yanit: Decodable { let text: String; let model: String? }

    static var kullanilabilir: Bool { Gizli.vekilToken != nil && Gizli.vekilTaban != nil }

    /// 16 kHz mono Float32 örnekleri Whisper'a gönderir; metni döndürür. Ağ hatasında fırlatır.
    static func cozumle(ornekler: [Float], oran: Double, ipucu: String? = nil, zamanAsimi: TimeInterval = 15) async throws -> String {
        #if DEBUG
        // P3.10-arıza: STT hatası anahtarı açıksa zaman aşımı taklit edilir; Apple metnine düşüş yolu sınanır.
        if ArizaAnahtarlari.tuket(.sttHatasi) { throw URLError(.timedOut) }
        #endif
        guard let taban = Gizli.vekilTaban, let token = Gizli.vekilToken else { throw URLError(.userAuthenticationRequired) }
        let wav = Self.wav(SesTamponu.yenidenOrnekle(ornekler, kaynakOran: oran, hedefOran: 16000), oran: 16000)
        var istek = URLRequest(url: taban.appending(path: "v1/whisper/v1/audio/transcriptions"))
        istek.httpMethod = "POST"
        istek.timeoutInterval = zamanAsimi
        istek.setValue(token, forHTTPHeaderField: "X-Personal-Token")
        let sinir = "----asistan\(UUID().uuidString)"
        istek.setValue("multipart/form-data; boundary=\(sinir)", forHTTPHeaderField: "Content-Type")
        var govde = Data()
        func alan(_ ad: String, _ deger: String) {
            govde.append("--\(sinir)\r\nContent-Disposition: form-data; name=\"\(ad)\"\r\n\r\n\(deger)\r\n".data(using: .utf8)!)
        }
        alan("model", "gpt-4o-transcribe")
        alan("language", "tr")
        // Kişisel dikte sözlüğünün doğru biçimleri istemde (224 belirteç sınırı için en çok 600 karakter).
        let defterIpucu = DikteDilModeli.ayarAcik ? DikteDuzeltmeDefteri.ortak.ipucu() : ""
        let istem = Self.istem(ipucu: ipucu, defter: defterIpucu)
        if !istem.isEmpty { alan("prompt", istem) }
        govde.append("--\(sinir)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"ses.wav\"\r\nContent-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        govde.append(wav)
        govde.append("\r\n--\(sinir)--\r\n".data(using: .utf8)!)
        istek.httpBody = govde
        let (veri, yanit) = try await URLSession.shared.data(for: istek)
        guard let http = yanit as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard http.statusCode == 200 else {
            throw NSError(domain: "Whisper", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: String(data: veri, encoding: .utf8) ?? "HTTP \(http.statusCode)"])
        }
        let metin = try JSONDecoder().decode(Yanit.self, from: veri).text.trimmingCharacters(in: .whitespacesAndNewlines)
        // İstemdeki sözlük listesinin geri yankısı (sessizlikte Whisper istemi tekrarlar) Apple metninin yerine geçmesin.
        if Self.sozlukYankisi(metin, defter: defterIpucu) { return "" }
        guard DikteDilModeli.ayarAcik else { return metin }
        let duzeltilmis = DikteDuzeltmeDefteri.ortak.uygula(metin)
        DikteDuzeltmeDefteri.ortak.sonDikte = duzeltilmis
        return duzeltilmis
    }

    /// Whisper istemi: bağlam ipucu + defterdeki doğru biçimler, en çok 600 karakter (sözcük ortasında kesilmez).
    static func istem(ipucu: String?, defter: String, enFazla: Int = 600) -> String {
        let birlesik = [ipucu ?? "", defter].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
        guard birlesik.count > enFazla else { return birlesik }
        let kesik = String(birlesik.prefix(enFazla))
        if let son = kesik.lastIndex(where: { $0 == "," || $0 == " " }) {
            return String(kesik[..<son]).trimmingCharacters(in: CharacterSet(charactersIn: ", "))
        }
        return kesik
    }

    /// Çıktı yalnız sözlük listesinin bir parçası mı (istem yankısı).
    static func sozlukYankisi(_ metin: String, defter: String) -> Bool {
        let tr = Locale(identifier: "tr_TR")
        let m = metin.lowercased(with: tr).trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
        guard !m.isEmpty, !defter.isEmpty, m.contains(",") || m.split(separator: " ").count >= 2 else { return false }
        return defter.lowercased(with: tr).contains(m)
    }

    /// Float32 [-1,1] → 16 bit PCM WAV.
    static func wav(_ ornekler: [Float], oran: Double) -> Data {
        let kanal: UInt16 = 1, bit: UInt16 = 16
        let veriBoyu = UInt32(ornekler.count * 2)
        var d = Data(capacity: 44 + Int(veriBoyu))
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        d.append("RIFF".data(using: .ascii)!); u32(36 + veriBoyu); d.append("WAVE".data(using: .ascii)!)
        d.append("fmt ".data(using: .ascii)!); u32(16); u16(1); u16(kanal); u32(UInt32(oran))
        u32(UInt32(oran) * UInt32(kanal) * UInt32(bit / 8)); u16(kanal * bit / 8); u16(bit)
        d.append("data".data(using: .ascii)!); u32(veriBoyu)
        var pcm = [Int16](repeating: 0, count: ornekler.count)
        for (i, x) in ornekler.enumerated() { pcm[i] = Int16(max(-1, min(1, x)) * 32767) }
        pcm.withUnsafeBufferPointer { d.append(Data(buffer: $0)) }
        return d
    }
}

/// Ses iş parçacığından biriken örnekler; kilitli, aktör dışı.
nonisolated final class SesTamponu: @unchecked Sendable {
    private let kilit = NSLock()
    private var ornekler: [Float] = []
    private(set) var oran: Double = 16000

    private var azamiOrnek: Int?
    /// Son örneğin eklendiği an (tekdüze saat, ns): tap sustu mu bekçisi için.
    private var sonEkleme = DispatchTime.now().uptimeNanoseconds
    func ayarla(oran: Double, azamiSure: Double? = nil) {
        kilit.withLock {
            self.oran = oran
            azamiOrnek = azamiSure.map { max(1, Int($0 * oran)) }
            ornekler.removeAll(keepingCapacity: false)
            sonEkleme = DispatchTime.now().uptimeNanoseconds
        }
    }
    /// Son örnek ekleneli kaç saniye oldu. Motor ses yolu değişiminde durunca büyür (tampon eski hâliyle donar).
    var sonEklemedenBeri: Double {
        kilit.withLock {
            let simdi = DispatchTime.now().uptimeNanoseconds
            return simdi > sonEkleme ? Double(simdi - sonEkleme) / 1e9 : 0
        }
    }
    func ekle(_ p: UnsafeBufferPointer<Float>) {
        kilit.withLock {
            sonEkleme = DispatchTime.now().uptimeNanoseconds
            ornekler.append(contentsOf: p)
            if let azamiOrnek, ornekler.count > azamiOrnek {
                ornekler.removeFirst(ornekler.count - azamiOrnek)
            }
        }
    }

    /// Float32 / Int16 / Int32 PCM tamponunu (ilk kanal) Float [-1,1] olarak biriktirir.
    func ekle(_ b: AVAudioPCMBuffer) {
        let n = Int(b.frameLength)
        guard n > 0 else { return }
        if let f = b.floatChannelData?[0] {
            ekle(UnsafeBufferPointer(start: f, count: n))
        } else if let i16 = b.int16ChannelData?[0] {
            var v = [Float](repeating: 0, count: n)
            for i in 0..<n { v[i] = Float(i16[i]) / 32768 }
            v.withUnsafeBufferPointer { ekle($0) }
        } else if let i32 = b.int32ChannelData?[0] {
            var v = [Float](repeating: 0, count: n)
            for i in 0..<n { v[i] = Float(i32[i]) / 2147483648 }
            v.withUnsafeBufferPointer { ekle($0) }
        }
    }
    /// Biriken örnekleri alır ve tamponu boşaltır.
    func al() -> [Float] { kilit.withLock { let o = ornekler; ornekler.removeAll(keepingCapacity: true); return o } }
    var sure: Double { kilit.withLock { Double(ornekler.count) / oran } }
    /// Tek seferlik (çevrimdışı) yeniden örnekleme: mono Float32 `kaynakOran` → `hedefOran`. Akışta değil, cümle bitince çağrılır.
    static func yenidenOrnekle(_ o: [Float], kaynakOran: Double, hedefOran: Double) -> [Float] {
        guard !o.isEmpty, kaynakOran != hedefOran,
              let kf = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: kaynakOran, channels: 1, interleaved: false),
              let hf = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: hedefOran, channels: 1, interleaved: false),
              let giris = AVAudioPCMBuffer(pcmFormat: kf, frameCapacity: AVAudioFrameCount(o.count)),
              let d = AVAudioConverter(from: kf, to: hf) else { return o }
        giris.frameLength = AVAudioFrameCount(o.count)
        o.withUnsafeBufferPointer { giris.floatChannelData![0].update(from: $0.baseAddress!, count: o.count) }
        let kapasite = AVAudioFrameCount(Double(o.count) * hedefOran / kaynakOran) + 64
        guard let cikti = AVAudioPCMBuffer(pcmFormat: hf, frameCapacity: kapasite) else { return o }
        var verildi = false
        var hata: NSError?
        d.convert(to: cikti, error: &hata) { _, durum in
            if verildi { durum.pointee = .endOfStream; return nil }
            verildi = true; durum.pointee = .haveData; return giris
        }
        guard hata == nil, cikti.frameLength > 0 else { return o }
        return Array(UnsafeBufferPointer(start: cikti.floatChannelData![0], count: Int(cikti.frameLength)))
    }

    /// Son `saniye` kadar örnek (tamponu boşaltmaz).
    func son(_ saniye: Double) -> [Float] { kilit.withLock { Array(ornekler.suffix(Int(saniye * oran))) } }

    /// Konuşma var mı: RMS ve tepe genliği. Sessizlikte tanıyıcının uydurduğu "Evet" gibi sözcükleri elemek için.
    static func enerji(_ o: [Float]) -> (rms: Float, tepe: Float) {
        guard !o.isEmpty else { return (0, 0) }
        var kare: Float = 0, tepe: Float = 0
        for x in o { kare += x * x; tepe = max(tepe, abs(x)) }
        return ((kare / Float(o.count)).squareRoot(), tepe)
    }

    /// Kabul kapısı: en az `enAzSure` sn ve yeterli enerji. Tek kelimelik kısa onay sözcükleri daha yüksek eşik ister.
    static func konusmaVar(_ o: [Float], oran: Double, metin: String, enAzSure: Double = 0.4) -> Bool {
        if o.isEmpty { return true }  // tampon dolmadıysa (bilinmeyen biçim) kapı karar veremez: açık bırak
        let sure = Double(o.count) / oran
        guard sure >= enAzSure else { return false }
        let e = enerji(o)
        let kelimeler = metin.split(whereSeparator: \.isWhitespace)
        let kisaOnay = kelimeler.count <= 1 && ["evet", "hayır", "hı", "hıhı", "e", "ee", "ha", "tamam"].contains(metin.lowercased().trimmingCharacters(in: .punctuationCharacters))
        let esik: Float = kisaOnay ? 0.02 : 0.006   // ≈ −34 dBFS / −44 dBFS (kısık/uzak konuşma geçsin, sessizlik uydurması geçmesin)
        return e.rms >= esik && e.tepe >= esik * 2
    }
}
