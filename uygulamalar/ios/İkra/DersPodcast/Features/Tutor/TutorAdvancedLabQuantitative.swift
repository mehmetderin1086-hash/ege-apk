import Charts
import SwiftUI

struct TutorConditionsLab: View {
    private enum Model: String, CaseIterable { case enzyme = "Derişim · enzim", gas = "Sıcaklık · ideal gaz", light = "Işık · uzaklık" }
    @State private var model = Model.enzyme
    @State private var substrate = 2.0
    @State private var km = 2.0
    @State private var vmax = 10.0
    @State private var temperature = 25.0
    @State private var volume = 10.0
    @State private var moles = 1.0
    @State private var power = 100.0
    @State private var distance = 2.0
    private var video:QSVideoLab {
        switch model {
        case .enzyme: .init(model:"enzyme",from:0.2,to:20,parameters:["km":km,"vmax":vmax])
        case .gas: .init(model:"gas",from:4,to:400,parameters:["moles":moles,"litres":volume])
        case .light: .init(model:"light",from:0.595,to:10,parameters:["watts":power])
        }
    }
    private var samples: [(x: Double, y: Double)] {
        (1...100).map { i in
            switch model {
            case .enzyme:
                let x = Double(i) / 5
                return (x, TutorLabMath.enzymeRate(substrate: x, km: km, vmax: vmax))
            case .gas:
                let x = Double(i) * 4
                return (x, TutorLabMath.gasPressure(kelvin: x, moles: moles, litres: volume))
            case .light:
                let x = 0.5 + Double(i) * 0.095
                return (x, TutorLabMath.irradiance(powerWatts: power, distanceMetres: x))
            }
        }
    }
    private var measurement: LearnLabMeasurement {
        switch model {
        case .enzyme: .init(inputs: ["Model": model.rawValue, "Substrat (mmol/L)": String(substrate), "Km (mmol/L)": String(km), "Vmax (µmol/dk)": String(vmax)], outputs: ["Hız (µmol/dk)": current.y])
        case .gas: .init(inputs: ["Model": model.rawValue, "Sıcaklık (°C)": String(temperature), "Hacim (L)": String(volume), "Madde (mol)": String(moles)], outputs: ["Basınç (atm)": current.y])
        case .light: .init(inputs: ["Model": model.rawValue, "Güç (W)": String(power), "Uzaklık (m)": String(distance)], outputs: ["Işınım (W/m²)": current.y])
        }
    }
    private var current: (x: Double, y: Double) {
        switch model {
        case .enzyme: (substrate, TutorLabMath.enzymeRate(substrate: substrate, km: km, vmax: vmax))
        case .gas: (temperature + 273.15, TutorLabMath.gasPressure(kelvin: temperature + 273.15, moles: moles, litres: volume))
        case .light: (distance, TutorLabMath.irradiance(powerWatts: power, distanceMetres: distance))
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Model", selection: $model) { ForEach(Model.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            Chart {
                ForEach(samples.indices, id: \.self) { i in LineMark(x: .value("Girdi", samples[i].x), y: .value("Sonuç", samples[i].y)).foregroundStyle(.teal) }
                PointMark(x: .value("Girdi", current.x), y: .value("Sonuç", current.y)).foregroundStyle(.orange).symbolSize(90)
            }.frame(height: 220)
                .chartXAxisLabel(model == .enzyme ? "Substrat [S] (mmol/L)" : model == .gas ? "Sıcaklık T (K)" : "Uzaklık r (m)")
                .chartYAxisLabel(model == .enzyme ? "v (µmol/dk)" : model == .gas ? "P (atm)" : "E (W/m²)")
            switch model {
            case .enzyme:
                Text("v = Vmax × [S] / (Km + [S])").font(.headline.monospaced())
                TutorAdvancedSlider(title: "Substrat (mmol/L)", value: $substrate, range: 0...20, step: 0.1)
                TutorAdvancedSlider(title: "Km (mmol/L)", value: $km, range: 0.1...10, step: 0.1)
                TutorAdvancedSlider(title: "Vmax (µmol/dk)", value: $vmax, range: 1...50)
                TutorLabMetric(title: "Başlangıç hızı", value: "\(current.y.formatted(.number.precision(.fractionLength(2)))) µmol/dk")
                Text("[S] = Km olduğunda v = Vmax / 2. Substratı artırdıkça hız Vmax'a yaklaşır.")
                TutorLabNote(text: "Michaelis–Menten başlangıç hızı modeli: sıcaklık ve pH sabit; inhibitör, kooperativite ve ürün birikimi yok. Substrat derişimi enzim derişiminden çok büyüktür. Parametreler seçilmiş örnektir; belirli bir enzimin ölçümü değildir.")
                Link("Kaynak: NCBI · enzim deneyleri", destination: URL(string: "https://www.ncbi.nlm.nih.gov/books/NBK92007/")!)
            case .gas:
                Text("P = nRT / V").font(.headline.monospaced())
                TutorAdvancedSlider(title: "Sıcaklık (°C)", value: $temperature, range: -100...120)
                TutorAdvancedSlider(title: "Hacim (L)", value: $volume, range: 1...30)
                TutorAdvancedSlider(title: "Madde miktarı (mol)", value: $moles, range: 0.1...3, step: 0.1)
                TutorLabMetric(title: "Mutlak sıcaklık", value: "\(current.x.formatted(.number.precision(.fractionLength(2)))) K")
                TutorLabMetric(title: "Basınç", value: "\(current.y.formatted(.number.precision(.fractionLength(3)))) atm")
                TutorLabNote(text: "İdeal gaz modeli; R = 0,082057366 L·atm/(mol·K). Orantı Kelvin ile kurulur. Yüksek basınçta veya yoğuşmaya yakın gerçek gaz davranışı bu modelden sapabilir.")
                Link("Kaynak: OpenStax · ideal gaz yasası", destination: URL(string: "https://openstax.org/books/college-physics/pages/13-3-the-ideal-gas-law")!)
            case .light:
                Text("E = P / (4πr²)").font(.headline.monospaced())
                TutorAdvancedSlider(title: "Işınım gücü (W)", value: $power, range: 1...300)
                TutorAdvancedSlider(title: "Uzaklık (m)", value: $distance, range: 0.5...10, step: 0.1)
                TutorLabMetric(title: "Işınım şiddeti / alan", value: "\(current.y.formatted(.number.precision(.fractionLength(2)))) W/m²")
                Text("Uzaklık iki katına çıkarsa birim alana düşen güç dörtte bire iner.")
                TutorLabNote(text: "Her yöne eşit yayılan noktasal kaynak; soğurma ve yansıma yok. Bu ışınım modelidir; doğrudan fotosentez hızı veya lux değeri değildir.")
            }
            Text("Dene: diğer değerleri sabit tutarak yalnız bir değişkeni değiştir. Girdi iki katına çıkınca çıktı da iki katına çıkıyor mu?").font(.callout)
            QSVideoLabExportButton(spec:video)
        }.learnLabMeasurement(measurement)
    }
}

struct TutorFunctionLab: View {
    @State private var a = 1.0
    @State private var b = 0.0
    @State private var c = -1.0
    @State private var selectedX = 1.0
    private func value(_ x: Double) -> Double { TutorLabMath.polynomial(a: a, b: b, c: c, x: x) }
    private var xs: [Double] { (0...200).map { Double($0) / 20 - 5 } }
    private var roots: [Double] { if case .finite(let values) = TutorLabMath.roots(a: a, b: b, c: c) { values } else { [] } }
    private var rootText: String {
        switch TutorLabMath.roots(a: a, b: b, c: c) {
        case .none: "Gerçek kök yok"
        case .allReal: "Her gerçek x bir köktür"
        case .finite(let values): values.map { $0.formatted(.number.precision(.fractionLength(0...3))) }.joined(separator: " ve ")
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("f(x) = ax² + bx + c").font(.title3.monospaced())
            Chart {
                RuleMark(x: .value("x", 0)).foregroundStyle(.secondary.opacity(0.4))
                RuleMark(y: .value("y", 0)).foregroundStyle(.secondary.opacity(0.4))
                ForEach(xs.indices, id: \.self) { i in LineMark(x: .value("x", xs[i]), y: .value("f(x)", value(xs[i]))).foregroundStyle(.blue) }
                ForEach(roots.filter { (-5...5).contains($0) }, id: \.self) { x in PointMark(x: .value("x", x), y: .value("f(x)", 0)).foregroundStyle(.green).symbolSize(80) }
                PointMark(x: .value("x", selectedX), y: .value("f(x)", value(selectedX))).foregroundStyle(.orange).symbolSize(100)
            }.chartXScale(domain: -5.0...5.0).frame(height: 240)
            TutorAdvancedSlider(title: "a", value: $a, range: -3...3, step: 0.1)
            TutorAdvancedSlider(title: "b", value: $b, range: -5...5, step: 0.1)
            TutorAdvancedSlider(title: "c", value: $c, range: -5...5, step: 0.1)
            TutorAdvancedSlider(title: "Turuncu noktanın x değeri", value: $selectedX, range: -5...5, step: 0.1)
            TutorLabMetric(title: "f(\(selectedX.formatted(.number.precision(.fractionLength(1)))))", value: value(selectedX).formatted(.number.precision(.fractionLength(0...3))))
            TutorLabMetric(title: "Gerçek kökler", value: rootText)
            if abs(a) > 0.000001 {
                let vx = -b / (2 * a)
                TutorLabMetric(title: "Tepe noktası", value: "(\(vx.formatted(.number.precision(.fractionLength(0...2)))), \(value(vx).formatted(.number.precision(.fractionLength(0...2)))))")
            } else { Text(abs(b) > 0.000001 ? "a = 0: doğrusal fonksiyon." : "a = b = 0: sabit fonksiyon.") }
            Grid(horizontalSpacing: 24, verticalSpacing: 8) {
                GridRow { Text("x").bold(); Text("f(x)").bold() }
                ForEach(-2...2, id: \.self) { x in GridRow { Text(String(x)); Text(value(Double(x)).formatted(.number.precision(.fractionLength(0...2)))).monospacedDigit() } }
            }.frame(maxWidth: .infinity).padding().background(.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            TutorLabNote(text: "Grafik −5 ≤ x ≤ 5 aralığını gösterir; dışarıdaki kökler de sayısal sonuçta listelenir. Dikey eksen veriye göre değişir. Yeşil noktalar köklerdir; renk tek başına sonuç yerine geçmez.")
            QSVideoLabExportButton(spec:.init(model:"polynomial",from:-5,to:5,parameters:["a":a,"b":b,"c":c]))
        }.learnLabMeasurement(.init(inputs: ["a": String(a), "b": String(b), "c": String(c), "x": String(selectedX)], outputs: ["f(x)": value(selectedX)], observation: rootText))
    }
}

struct TutorGeometryLab: View {
    @State private var constraint = TutorGeometryModel.Constraint.right
    @State private var handle = CGPoint(x: 0.75, y: 0.25)
    private var points: [CGPoint] { TutorGeometryModel.points(constraint, handle: handle) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Korunacak koşul", selection: $constraint) { ForEach(TutorGeometryModel.Constraint.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.menu)
            Text(constraint == .right ? "C'yi yukarı/aşağı; B'yi sağa/sola sürükle. A açısı 90° kalır." : constraint == .equal ? "C'yi yukarı/aşağı sürükle. AC = BC korunur." : "C'yi sürükle. Karşı kenarlar paralel ve eşit kalır.")
            GeometryReader { geometry in
                let side = min(geometry.size.width, geometry.size.height)
                let offset = CGPoint(x: (geometry.size.width - side) / 2, y: (geometry.size.height - side) / 2)
                let px = points.map { CGPoint(x: offset.x + $0.x * side, y: offset.y + $0.y * side) }
                ZStack {
                    Canvas { context, _ in
                        var path = Path(); path.addLines(px); path.closeSubpath()
                        context.fill(path, with: .color(.teal.opacity(0.12)))
                        context.stroke(path, with: .color(.teal), lineWidth: 3)
                        if constraint == .right {
                            let a = px[0]
                            var angle = Path(); angle.move(to: .init(x: a.x + 18, y: a.y)); angle.addLine(to: .init(x: a.x + 18, y: a.y - 18)); angle.addLine(to: .init(x: a.x, y: a.y - 18))
                            context.stroke(angle, with: .color(.orange), lineWidth: 2)
                        }
                    }
                    ForEach(px.indices, id: \.self) { i in
                        let editable = i == 2 || constraint == .right && i == 1
                        Text(String(UnicodeScalar(65 + i)!)).font(.headline).frame(width: 42, height: 42)
                            .background(editable ? Color.orange.opacity(0.3) : Color.teal.opacity(0.2), in: Circle())
                            .overlay(Circle().stroke(editable ? .orange : .teal, lineWidth: 2))
                            .position(px[i])
                            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("labGeometry")).onChanged { value in
                                guard editable else { return }
                                let normalized = CGPoint(x: (value.location.x - offset.x) / side, y: (value.location.y - offset.y) / side)
                                if constraint == .right, i == 1 { handle.x = normalized.x }
                                else if constraint == .parallel { handle = .init(x: normalized.x - 0.20, y: normalized.y) }
                                else { handle.y = normalized.y }
                            })
                            .accessibilityLabel("\(String(UnicodeScalar(65 + i)!)) köşesi\(editable ? ", sürüklenebilir" : "")")
                    }
                }.coordinateSpace(name: "labGeometry")
            }.frame(height: 300)
            // Sliders provide an exact and accessible alternative to drag gestures.
            TutorAdvancedSlider(title: "Yükseklik denetimi", value: Binding(get: { Double(1 - handle.y) }, set: { handle.y = 1 - $0 }), range: 0.35...0.85, step: 0.01)
            if constraint != .equal {
                TutorAdvancedSlider(title: constraint == .right ? "Taban denetimi" : "Yatay kayma denetimi", value: Binding(get: { Double(handle.x) }, set: { handle.x = $0 }), range: 0.2...0.85, step: 0.01)
            }
            ForEach(points.indices, id: \.self) { i in
                let j = (i + 1) % points.count
                TutorLabMetric(title: "\(String(UnicodeScalar(65 + i)!))\(String(UnicodeScalar(65 + j)!))", value: "\((TutorGeometryModel.distance(points[i], points[j]) * 10).formatted(.number.precision(.fractionLength(2)))) birim")
            }
            TutorLabMetric(title: "Korunan koşul", value: constraint == .right ? "AB ⟂ AC" : constraint == .equal ? "AC = BC" : "AB ∥ CD · AD ∥ BC")
            TutorLabNote(text: "Bağımsız örnek şekildir; yüklediğin sorunun geometrisi değiştirilmez. Kare çizim alanının bir kenarı 10 birimdir; uzunluklar Öklid uzaklığıyla hesaplanır.")
        }.learnLabMeasurement(.init(inputs: ["Koşul": constraint.rawValue, "Yatay": String(Double(handle.x)), "Yükseklik": String(Double(handle.y))], outputs: ["AB (birim)": TutorGeometryModel.distance(points[0], points[1]) * 10, "BC (birim)": TutorGeometryModel.distance(points[1], points[2]) * 10]))
    }
}
