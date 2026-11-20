import Foundation

/// Akan metinden okunmaya hazır tam cümleleri ayırır. Saf mantık; test edilir.
nonisolated struct CumleBolucu: Sendable {
    private(set) var islenen = 0
    /// P3.12 ilk ses hızı: yanıtın ilk öbeği en az `ilkVirgulSiniri` karakterlik bir virgülde (ardından boşluk) bölünür;
    /// ilk ses cümle sonunu beklemez. Yalnız ilk parça için; sonrakiler cümle sonunda kalır (Ayarlar `ilkSesHizli`).
    var ilkVirgul = true
    private(set) var ilkVerildi = false
    static let ilkVirgulSiniri = 40

    /// Kümülatif metni alır; yeni tamamlanmış cümleleri döndürür.
    mutating func yeniCumleler(_ tam: String) -> [String] {
        guard tam.count > islenen else { return [] }
        let kalan = String(tam.dropFirst(islenen))
        var cumleler: [String] = []
        var biriken = ""
        let karakterler = Array(kalan)
        var i = 0
        while i < karakterler.count {
            let c = karakterler[i]
            biriken.append(c)
            if ".!?…".contains(c) {
                // Akış "12." noktasında bölünebilir; sonraki parçada "50" gelmeden sayıyı okuma.
                let sonraki = i + 1 < karakterler.count ? karakterler[i + 1] : " "
                let onceki = i > 0 ? karakterler[i - 1] : " "
                let sayininDevamiBekleniyor = c == "." && onceki.isNumber && i + 1 == karakterler.count
                if !sayininDevamiBekleniyor && (sonraki.isWhitespace || sonraki.isNewline) {
                    let t = biriken.trimmingCharacters(in: .whitespacesAndNewlines)
                    if t.count >= 2 { cumleler.append(t); ilkVerildi = true }
                    islenen += biriken.count
                    biriken = ""
                }
            } else if c == "\n", biriken.trimmingCharacters(in: .whitespacesAndNewlines).count >= 20 {
                cumleler.append(biriken.trimmingCharacters(in: .whitespacesAndNewlines))
                ilkVerildi = true
                islenen += biriken.count
                biriken = ""
            } else if ilkVirgul, !ilkVerildi, c == ",", i + 1 < karakterler.count, karakterler[i + 1].isWhitespace,
                      biriken.trimmingCharacters(in: .whitespacesAndNewlines).count >= Self.ilkVirgulSiniri {
                // Sonraki karakter henüz gelmediyse beklenir ("1,5" gibi ondalık virgül bölünmesin).
                cumleler.append(biriken.trimmingCharacters(in: .whitespacesAndNewlines))
                ilkVerildi = true
                islenen += biriken.count
                biriken = ""
            }
            i += 1
        }
        return cumleler
    }

    /// Akış bitti: kalan her şeyi döndür.
    mutating func kalan(_ tam: String) -> String? {
        guard tam.count > islenen else { return nil }
        let k = String(tam.dropFirst(islenen)).trimmingCharacters(in: .whitespacesAndNewlines)
        islenen = tam.count
        return k.isEmpty ? nil : k
    }

    mutating func sifirla() { islenen = 0; ilkVerildi = false }
}
