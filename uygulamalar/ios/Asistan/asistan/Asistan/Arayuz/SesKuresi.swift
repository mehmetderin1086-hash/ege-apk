import SwiftUI

/// Ses üretilmeden önceki bekleme, konuşma animasyonu gibi görünmemeli.
nonisolated enum CanliGorselDurum: Equatable, CaseIterable {
    case hazir, baglaniyor, dinliyor, dusunuyor, konusuyor, hata

    static func sec(baglaniyor: Bool, dinliyor: Bool, sesCaliyor: Bool, yanitBekleniyor: Bool, hata: Bool) -> Self {
        if baglaniyor { return .baglaniyor }
        if sesCaliyor { return .konusuyor }
        if dinliyor { return .dinliyor }
        if yanitBekleniyor { return .dusunuyor }
        return hata ? .hata : .hazir
    }

    var baslik: String {
        switch self {
        case .hazir: "Konuşmaya hazır"
        case .baglaniyor: "Hazırlanıyor"
        case .dinliyor: "Dinliyorum"
        case .dusunuyor: "Yanıt hazırlanıyor"
        case .konusuyor: "Konuşuyorum"
        case .hata: "Konuşma durakladı"
        }
    }

    var simge: String {
        switch self {
        case .hazir: "mic"
        case .baglaniyor: "arrow.triangle.2.circlepath"
        case .dinliyor: "mic.fill"
        case .dusunuyor: "ellipsis"
        case .konusuyor: "waveform"
        case .hata: "exclamationmark.circle"
        }
    }

    var ipucu: String {
        switch self {
        case .hazir: "Konuşmak için küreye dokun"
        case .baglaniyor: "Ses bağlantısı hazırlanıyor"
        case .dinliyor: "Konuş; bitince bekle ya da küreye dokun"
        case .dusunuyor, .konusuyor: "Söz almak için küreye dokun"
        case .hata: "Yeniden dinlemek için küreye dokun"
        }
    }

    var hiz: Double {
        switch self {
        case .hazir, .hata: 0
        case .baglaniyor: 0.65
        case .dinliyor: 0.8
        case .dusunuyor: 1.5
        case .konusuyor: 1.1
        }
    }

    /// Kapalı motorun eski ölçümü ya da NaN, çizim geometrisine taşınmaz.
    func duzey(girisDb: Double, cikisDb: Double) -> Double {
        let db: Double
        switch self {
        case .dinliyor: db = girisDb
        case .konusuyor: db = cikisDb
        default: return 0
        }
        guard db.isFinite else { return 0 }
        let deger = min(1, max(0, (db + 55) / 45))
        return deger * deger * (3 - 2 * deger)
    }
}

/// Tek Canvas: ayrı bulanıklık katmanları yerine ışık ve dalgalar aynı yüzeye çizilir.
struct SesGostergesi: View {
    let duzey: Double
    let etkin: Bool
    let profil: GorunumTercihleri
    var durum: CanliGorselDurum? = nil
    var olcum: (() -> Double)? = nil
    @Environment(\.accessibilityReduceMotion) private var azHareket
    @Environment(\.scenePhase) private var sahne

    private var hal: CanliGorselDurum { durum ?? (etkin ? .dinliyor : .hazir) }
    private var hareketli: Bool { profil.hareket && !azHareket && sahne == .active && hal.hiz > 0 }

    var body: some View {
        let ekonomik = GucPolitikasi.ortak.dusukGuc || GucPolitikasi.ortak.termalAgir
        TimelineView(.animation(minimumInterval: ekonomik ? 1.0 / 15 : 1.0 / 30, paused: !hareketli)) { zaman in
            // WebSocket motorlarının ölçümleri kilit altında tutulur, Observable değildir.
            // Her çizimde oku: yalnız durum değişince okunan bir değer küreyi dondururdu.
            let ham = hareketli ? (olcum?() ?? duzey) : 0
            let duzey = ham.isFinite ? min(1, max(0, ham)) : 0
            SesYuzeyi(duzey: hareketli ? duzey : 0,
                      zaman: hareketli ? zaman.date.timeIntervalSinceReferenceDate : 0,
                      durum: hal, renk: profil.vurgu, gosterge: profil.gosterge)
                // Animatable yüzey, gerçek ölçümler arasındaki sert sıçramaları yumuşatır.
                .animation(hareketli ? .easeOut(duration: 0.18) : nil, value: duzey)
        }
        .accessibilityHidden(true)
    }
}

private struct SesYuzeyi: View, Animatable {
    var duzey: Double
    let zaman: Double
    let durum: CanliGorselDurum
    let renk: Color
    let gosterge: GorunumTercihleri.Gosterge
    var animatableData: Double {
        get { duzey }
        set { duzey = newValue }
    }

    var body: some View {
        Canvas { ctx, boyut in
            let d = min(boyut.width, boyut.height)
            let merkez = CGPoint(x: boyut.width / 2, y: boyut.height / 2)
            let t = zaman * durum.hiz
            let r = d * (0.425 + duzey * 0.022)
            let daire = CGRect(x: merkez.x - r, y: merkez.y - r, width: r * 2, height: r * 2)
            let vurgu = durum == .hata ? Color.orange : renk
            if gosterge == .kure {
                ctx.fill(Path(ellipseIn: daire.insetBy(dx: -d * 0.065, dy: -d * 0.065)), with: .radialGradient(
                    Gradient(colors: [vurgu.opacity(0.16 + duzey * 0.1), .clear]), center: merkez,
                    startRadius: r * 0.85, endRadius: r + d * 0.065))
                ctx.drawLayer { yuzey in
                    yuzey.clip(to: Path(ellipseIn: daire))
                    yuzey.fill(Path(ellipseIn: daire), with: .linearGradient(
                        Gradient(colors: [vurgu, vurgu.opacity(0.82), vurgu.opacity(0.42)]),
                        startPoint: CGPoint(x: daire.minX, y: daire.minY), endPoint: CGPoint(x: daire.maxX, y: daire.maxY)))
                    for kat in 0..<3 {
                        let k = Double(kat)
                        var yol = Path()
                        yol.move(to: CGPoint(x: daire.minX, y: daire.maxY))
                        for i in 0...56 {
                            let x = Double(i) / 56
                            let dalga = sin(x * 6.2 + t + k * 1.4) * (0.06 + duzey * 0.13)
                                + cos(x * 10.5 - t * 0.6 + k) * 0.035
                            let y = 0.35 + k * 0.13 + dalga
                            yol.addLine(to: CGPoint(x: daire.minX + x * daire.width, y: daire.minY + y * daire.height))
                        }
                        yol.addLine(to: CGPoint(x: daire.maxX, y: daire.maxY))
                        yol.closeSubpath()
                        yuzey.fill(yol, with: .linearGradient(Gradient(colors: [.white.opacity(0.48 - k * 0.09), .white.opacity(0.02)]),
                            startPoint: CGPoint(x: merkez.x, y: daire.minY + r * 0.4), endPoint: CGPoint(x: merkez.x, y: daire.maxY)))
                    }
                    let isik = CGPoint(x: merkez.x - r * 0.25 + sin(t * 0.4) * r * 0.16,
                                       y: merkez.y - r * 0.4 + cos(t * 0.3) * r * 0.1)
                    yuzey.fill(Path(ellipseIn: daire), with: .radialGradient(Gradient(colors: [.white.opacity(0.8), .clear]),
                        center: isik, startRadius: 0, endRadius: r * 1.25))
                }
                ctx.stroke(Path(ellipseIn: daire), with: .color(.white.opacity(0.3)), lineWidth: 1)
            } else if gosterge == .halkalar {
                for i in 0..<5 {
                    let yaricap = d * (0.17 + Double(i) * 0.06 + duzey * 0.045 * sin(t * 2 + Double(i)))
                    let rect = CGRect(x: merkez.x - yaricap, y: merkez.y - yaricap, width: yaricap * 2, height: yaricap * 2)
                    ctx.stroke(Path(ellipseIn: rect), with: .color(vurgu.opacity(1 - Double(i) * 0.16)), lineWidth: max(2, d * 0.016))
                }
            } else {
                for i in 0..<15 {
                    let x = merkez.x + (Double(i) - 7) * d * 0.055
                    let agirlik = 1 - abs(Double(i) - 7) / 10
                    let yukseklik = d * (0.045 + agirlik * (0.08 + duzey * 0.65) * (0.7 + 0.3 * sin(t * 4 + Double(i) * 0.6)))
                    let rect = CGRect(x: x - d * 0.016, y: merkez.y - yukseklik / 2, width: d * 0.032, height: yukseklik)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: d * 0.016), with: .color(vurgu.opacity(0.6 + agirlik * 0.4)))
                }
            }
            // Bekleme halkası ses ölçümü değildir: sessizlikte de bağlantı/üretim ilerlediğini anlatır.
            if durum == .dusunuyor || durum == .baglaniyor {
                var yay = Path()
                yay.addArc(center: merkez, radius: d * 0.475, startAngle: .radians(t), endAngle: .radians(t + 1.65), clockwise: false)
                ctx.stroke(yay, with: .color(vurgu.opacity(0.7)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
        }
    }
}
