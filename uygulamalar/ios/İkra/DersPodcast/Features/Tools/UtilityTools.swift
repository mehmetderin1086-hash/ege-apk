import PencilKit
import SwiftUI

// MARK: - Bilimsel hesap makinesi

struct CalculatorView: View {
    @AppStorage("tools.calc.degrees") private var degrees = true
    @State private var expression = ""
    @State private var history: [(String, String)] = []
    /// "=" ile hesaplanamayan ifade: sonraki değişikliğe kadar uyarı görünür.
    @State private var invalid = false

    private static let keys: [[String]] = [
        ["C", "(", ")", "÷"],
        ["7", "8", "9", "×"],
        ["4", "5", "6", "−"],
        ["1", "2", "3", "+"],
        ["0", ",", "⌫", "="],
    ]
    private static let functions = ["√", "^", "π", "%", "!", "sin(", "cos(", "tan(", "ln(", "log(", "e"]

    private var preview: String? { Calculator.evaluate(expression, degrees: degrees).map(Calculator.format) }

    var body: some View {
        ToolScaffold(title: "Hesap makinesi") {
            ScrollView {
                VStack(spacing: 10) {
                    VStack(alignment: .trailing, spacing: 4) {
                        ForEach(Array(history.suffix(3).enumerated()), id: \.offset) { _, line in
                            Button("\(line.0) = \(line.1)") { expression = line.1.hasPrefix("-") ? "(\(line.1))" : line.1 }
                                .font(.footnote).foregroundStyle(.secondary).buttonStyle(.plain).lineLimit(1)
                        }
                        // Uzun ifadede en son yazılan görünür kalsın: baştan kırpılır.
                        Text(expression.isEmpty ? "0" : expression)
                            .font(.system(size: 34, weight: .semibold, design: .rounded)).lineLimit(2).minimumScaleFactor(0.4).truncationMode(.head)
                        if invalid {
                            Label("Geçersiz ifade", systemImage: "exclamationmark.triangle.fill").font(.title3).foregroundStyle(.red)
                                .lineLimit(1).minimumScaleFactor(0.5)
                        } else if let preview {
                            Text("= \(preview)").font(.title3).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.5).textSelection(.enabled)
                        } else {
                            Text(Calculator.openParens(expression) > 0 ? "Parantez kapanmadı" : " ").font(.title3).foregroundStyle(.secondary)
                                .lineLimit(1).minimumScaleFactor(0.5)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(12)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
                    // İfade ya da açı birimi değişince eski uyarı kalkar.
                    .onChange(of: expression) { invalid = false }
                    .onChange(of: degrees) { invalid = false }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            Button(degrees ? "DERECE" : "RADYAN") { degrees.toggle() }.buttonStyle(.bordered).tint(.orange)
                            ForEach(Self.functions, id: \.self) { key in Button(key) { expression += key }.buttonStyle(.bordered) }
                        }
                    }
                    Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                        ForEach(Self.keys, id: \.self) { row in
                            GridRow {
                                ForEach(row, id: \.self) { key in
                                    Button { press(key) } label: {
                                        Text(key).font(.title2.weight(.medium)).frame(maxWidth: .infinity, minHeight: 52)
                                            .background(color(key), in: RoundedRectangle(cornerRadius: 12))
                                            .foregroundStyle(key == "=" ? .white : .primary)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(key == "⌫" ? "Sil" : key == "C" ? "Temizle" : key)
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .onAppear {
                // Yalnız Debug: `-calcExpr=<ifade>` ifadeyi hazır yazar; `-calcEquals` ardından "=" basar.
                guard expression.isEmpty, let raw = DebugArg.value("calcExpr") else { return }
                expression = raw
                // Kısa bekleme: ifadenin değişimi uyarıyı sıfırladıktan sonra basılsın.
                if ProcessInfo.processInfo.arguments.contains("-calcEquals") { Task { try? await Task.sleep(for: .milliseconds(300)); press("=") } }
            }
        }
    }

    private func color(_ key: String) -> Color {
        switch key {
        case "=": .accentColor
        case "÷", "×", "−", "+": .orange.opacity(0.3)
        case "C", "⌫", "(", ")": .gray.opacity(0.3)
        default: .gray.opacity(0.14)
        }
    }

    private func press(_ key: String) {
        switch key {
        case "C": expression = ""
        case "⌫": if !expression.isEmpty { expression.removeLast() }
        case "=":
            guard let result = preview else {
                // Hesaplanamayan ifade sessizce yutulmaz.
                if !expression.isEmpty { invalid = true; UINotificationFeedbackGenerator().notificationOccurred(.error) }
                return
            }
            history.append((expression, result))
            // Negatif sonuç parantezle yazılır: ardından ^2 gelirse işaret üssün içinde kalsın.
            expression = result.hasPrefix("-") ? "(\(result))" : result
        default: expression += key
        }
    }
}

// MARK: - Birim çevirici

struct UnitConverterView: View {
    @State private var kind = Kind.length
    @State private var text = "1"
    @State private var from = 0
    @State private var to = 1

    enum Kind: String, CaseIterable, Identifiable {
        case length = "Uzunluk", mass = "Kütle", temperature = "Sıcaklık", volume = "Hacim", speed = "Hız"
        case area = "Alan", duration = "Zaman", energy = "Enerji", pressure = "Basınç", power = "Güç"
        var id: String { rawValue }

        var units: [(String, Dimension)] {
            switch self {
            case .length: [("Metre", UnitLength.meters), ("Kilometre", UnitLength.kilometers), ("Santimetre", UnitLength.centimeters), ("Milimetre", UnitLength.millimeters), ("Mikrometre", UnitLength.micrometers), ("Nanometre", UnitLength.nanometers), ("Mil", UnitLength.miles), ("İnç", UnitLength.inches), ("Fit", UnitLength.feet), ("Işık yılı", UnitLength.lightyears)]
            case .mass: [("Kilogram", UnitMass.kilograms), ("Gram", UnitMass.grams), ("Miligram", UnitMass.milligrams), ("Mikrogram", UnitMass.micrograms), ("Ton", UnitMass.metricTons), ("Libre", UnitMass.pounds), ("Ons", UnitMass.ounces)]
            case .temperature: [("Santigrat °C", UnitTemperature.celsius), ("Kelvin K", UnitTemperature.kelvin), ("Fahrenhayt °F", UnitTemperature.fahrenheit)]
            case .volume: [("Litre", UnitVolume.liters), ("Mililitre", UnitVolume.milliliters), ("Metreküp", UnitVolume.cubicMeters), ("Santimetreküp", UnitVolume.cubicCentimeters), ("Galon (ABD)", UnitVolume.gallons)]
            case .speed: [("m/s", UnitSpeed.metersPerSecond), ("km/sa", UnitSpeed.kilometersPerHour), ("mil/sa", UnitSpeed.milesPerHour), ("Knot", UnitSpeed.knots)]
            case .area: [("Metrekare", UnitArea.squareMeters), ("Kilometrekare", UnitArea.squareKilometers), ("Santimetrekare", UnitArea.squareCentimeters), ("Hektar", UnitArea.hectares), ("Dönüm (1000 m²)", UnitArea.ares)]
            case .duration: [("Saniye", UnitDuration.seconds), ("Dakika", UnitDuration.minutes), ("Saat", UnitDuration.hours), ("Milisaniye", UnitDuration.milliseconds)]
            case .energy: [("Joule", UnitEnergy.joules), ("Kilojoule", UnitEnergy.kilojoules), ("Kalori", UnitEnergy.calories), ("Kilokalori", UnitEnergy.kilocalories), ("Kilovatsaat", UnitEnergy.kilowattHours)]
            case .pressure: [("Pascal", UnitPressure.newtonsPerMetersSquared), ("Kilopascal", UnitPressure.kilopascals), ("Bar", UnitPressure.bars), ("Atmosfer", UnitPressure.bars), ("mmHg", UnitPressure.millimetersOfMercury), ("psi", UnitPressure.poundsForcePerSquareInch)]
            case .power: [("Watt", UnitPower.watts), ("Kilowatt", UnitPower.kilowatts), ("Beygir gücü (hp)", UnitPower.horsepower)]
            }
        }
    }

    /// Virgül de nokta da ondalık ayırıcıdır; "3×4" gibi ifade de yazılabilir.
    private var result: Double? {
        let units = kind.units
        guard let value = Calculator.evaluate(text), units.indices.contains(from), units.indices.contains(to) else { return nil }
        var out = Measurement(value: value, unit: units[from].1).converted(to: units[to].1).value
        // Foundation'da atmosfer ve dönüm yok: elle düzelt.
        if kind == .pressure { if from == 3 { out *= 1.01325 }; if to == 3 { out /= 1.01325 } }
        if kind == .area { if from == 4 { out *= 10 }; if to == 4 { out /= 10 } }
        return out
    }

    var body: some View {
        let units = kind.units
        ToolScaffold(title: "Birim çevirici") {
            Form {
                Picker("Tür", selection: $kind) { ForEach(Kind.allCases) { Text($0.rawValue).tag($0) } }
                Section("Değer") {
                    TextField("Değer", text: $text).keyboardType(.numbersAndPunctuation).autocorrectionDisabled()
                    Picker("Birim", selection: $from) { ForEach(units.indices, id: \.self) { Text(units[$0].0).tag($0) } }
                }
                Section("Sonuç") {
                    Picker("Birim", selection: $to) { ForEach(units.indices, id: \.self) { Text(units[$0].0).tag($0) } }
                    Text(result.map(Calculator.format) ?? "Geçersiz değer").font(.title2.bold()).textSelection(.enabled)
                    Button("Yer değiştir", systemImage: "arrow.up.arrow.down") { swap(&from, &to) }
                }
            }
            .onChange(of: kind) { from = 0; to = 1 }
        }
    }
}

// MARK: - Periyodik tablo

struct PeriodicTableView: View {
    @State private var query = ""
    @State private var mode = 0
    @State private var selected: ChemElement?
    @State private var quiz = ChemElement.all.randomElement()
    @State private var choices: [ChemElement] = []
    @State private var picked: ChemElement?
    @State private var score = 0

    private static let cell: CGFloat = 46

    var body: some View {
        ToolScaffold(title: "Periyodik tablo") {
            VStack(spacing: 0) {
                Picker("Görünüm", selection: $mode) {
                    Text("Tablo").tag(0)
                    Text("Liste").tag(1)
                    Text("Quiz").tag(2)
                }
                .modifier(AccessiblePickerStyle()).padding(12)
                switch mode {
                case 0: table
                case 1: list
                default: quizView
                }
            }
            .sheet(item: $selected) { element in
                ElementDetail(element: element).presentationDetents([.medium])
            }
        }
    }

    private var table: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(1...7, id: \.self) { period in
                    HStack(spacing: 3) {
                        ForEach(1...18, id: \.self) { group in
                            if let element = ChemElement.all.first(where: { $0.period == period && $0.group == group }) {
                                cell(element)
                            } else {
                                Color.clear.frame(width: Self.cell, height: Self.cell)
                            }
                        }
                    }
                }
                Text("Lantanitler ve aktinitler").font(.caption).foregroundStyle(.secondary).padding(.top, 8)
                ForEach([57...71, 89...103], id: \.lowerBound) { range in
                    HStack(spacing: 3) {
                        Color.clear.frame(width: Self.cell * 2 + 3, height: Self.cell)
                        ForEach(ChemElement.all.filter { range.contains($0.number) }) { cell($0) }
                    }
                }
            }
            .padding(12)
        }
    }

    private func cell(_ element: ChemElement) -> some View {
        Button { selected = element } label: {
            VStack(spacing: 0) {
                Text("\(element.number)").font(.system(size: 9))
                Text(element.symbol).font(.system(size: 17, weight: .bold))
            }
            .frame(width: Self.cell, height: Self.cell)
            .background(element.category.color.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(element.number), \(element.name)")
    }

    private var list: some View {
        let needle = AnswerMatch.normalize(query)
        return List(ChemElement.all.filter { needle.isEmpty || AnswerMatch.normalize("\($0.name) \($0.symbol) \($0.number)").contains(needle) }) { element in
            Button { selected = element } label: {
                HStack(spacing: 12) {
                    Text(element.symbol).font(.headline).frame(width: 40, height: 40)
                        .background(element.category.color.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading) {
                        Text("\(element.number). \(element.name)")
                        Text(element.category.title).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Ad, sembol ya da numara")
    }

    private var quizView: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let quiz {
                    Text("Bu sembol hangi element?").foregroundStyle(.secondary)
                    Text(quiz.symbol).font(.system(size: 72, weight: .bold, design: .rounded))
                    ForEach(choices) { choice in
                        Button { answer(choice) } label: {
                            Text(choice.name).frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(picked == nil ? Color.gray.opacity(0.15) : choice == quiz ? Color.green.opacity(0.35)
                                            : choice == picked ? Color.red.opacity(0.35) : Color.gray.opacity(0.15),
                                            in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain).disabled(picked != nil)
                    }
                    Text("Seri: \(score)").font(.subheadline).foregroundStyle(.secondary)
                    if picked != nil { Button("Sıradaki") { nextQuiz() }.buttonStyle(PrimaryButtonStyle()) }
                }
            }
            .padding(20)
        }
        .onAppear { if choices.isEmpty { nextQuiz() } }
    }

    private func nextQuiz() {
        // İlk 56 element: okulda en çok sorulanlar.
        let pool = Array(ChemElement.all.prefix(56))
        guard let target = pool.randomElement() else { return }
        quiz = target
        choices = (pool.filter { $0 != target }.shuffled().prefix(3) + [target]).shuffled()
        picked = nil
    }

    private func answer(_ choice: ChemElement) {
        picked = choice
        score = choice == quiz ? score + 1 : 0
    }
}

private struct ElementDetail: View {
    var element: ChemElement

    var body: some View {
        VStack(spacing: 12) {
            Text(element.symbol).font(.system(size: 64, weight: .bold, design: .rounded))
                .frame(width: 120, height: 120)
                .background(element.category.color.opacity(0.35), in: RoundedRectangle(cornerRadius: 20))
            Text(element.name).font(.title2.bold())
            VStack(spacing: 0) {
                LabeledContent("Atom numarası", value: "\(element.number)").padding(.vertical, 8)
                Divider()
                LabeledContent("Atom kütlesi", value: element.mass.replacingOccurrences(of: ".", with: ",")).padding(.vertical, 8)
                Divider()
                LabeledContent("Sınıf", value: element.category.title).padding(.vertical, 8)
                Divider()
                LabeledContent("Periyot / grup", value: "\(element.period) / \(element.group.map(String.init) ?? "f bloğu")").padding(.vertical, 8)
            }
        }
        .padding(20)
    }
}

extension ChemElement.Category {
    var color: Color {
        switch self {
        case .nonmetal: .green
        case .nobleGas: .purple
        case .alkali: .red
        case .alkalineEarth: .orange
        case .metalloid: .teal
        case .halogen: .yellow
        case .transition: .blue
        case .postTransition: .gray
        case .lanthanide: .pink
        case .actinide: .brown
        }
    }
}

// MARK: - Çizim tahtası

struct WhiteboardView: View {
    @State private var canvas = PKCanvasView()
    @State private var shareImage: ShareItem?
    @State private var confirmClear = false
    @Environment(\.scenePhase) private var scenePhase

    struct ShareItem: Identifiable { var id = UUID(); var image: UIImage }

    private static var fileURL: URL { JSONStoreLocation.defaultDirectory.appending(path: "whiteboard.drawing") }

    var body: some View {
        ToolScaffold(title: "Tahta") {
            CanvasHost(canvas: canvas, onChange: save)
                .ignoresSafeArea(edges: .bottom)
                // Aşağı doğru çizgi sayfayı kapatmasın.
                .interactiveDismissDisabled()
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button("Geri al", systemImage: "arrow.uturn.backward") { canvas.undoManager?.undo() }
                        Button("Paylaş", systemImage: "square.and.arrow.up") {
                            let bounds = canvas.drawing.bounds.isEmpty ? canvas.bounds : canvas.drawing.bounds.insetBy(dx: -20, dy: -20)
                            shareImage = ShareItem(image: Self.lightImage(canvas.drawing, bounds: bounds))
                        }
                        Button("Temizle", systemImage: "trash", role: .destructive) { confirmClear = true }
                    }
                }
                .sheet(item: $shareImage) { ShareSheet(items: [$0.image]) }
                .onAppear {
                    if let data = try? Data(contentsOf: Self.fileURL), let drawing = try? PKDrawing(data: data) { canvas.drawing = drawing }
                }
                .onDisappear { save() }
                .onChange(of: scenePhase) { _, phase in if phase != .active { save() } }
                .confirmationDialog("Tahta silinsin mi?", isPresented: $confirmClear, titleVisibility: .visible) {
                    Button("Temizle", role: .destructive) { canvas.drawing = PKDrawing(); save() }
                }
        }
    }

    private func save() {
        try? FileManager.default.createDirectory(at: JSONStoreLocation.defaultDirectory, withIntermediateDirectories: true)
        try? canvas.drawing.dataRepresentation().write(to: Self.fileURL, options: .atomic)
    }

    /// Karanlık modda da siyah mürekkep + beyaz zemin: başka uygulamaya yapıştırınca görünür kalsın.
    private static func lightImage(_ drawing: PKDrawing, bounds: CGRect) -> UIImage {
        var ink = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent { ink = drawing.image(from: bounds, scale: 2) }
        return UIGraphicsImageRenderer(size: bounds.size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: bounds.size))
            ink.draw(in: CGRect(origin: .zero, size: bounds.size))
        }
    }
}

private struct CanvasHost: UIViewRepresentable {
    var canvas: PKCanvasView
    var onChange: () -> Void

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let picker = PKToolPicker()
        var onChange: () -> Void
        private var pending: Task<Void, Never>?

        init(onChange: @escaping () -> Void) { self.onChange = onChange }

        /// Her çizgiden 1 sn sonra kaydet: uygulama arka planda sonlandırılsa da çizim kalır.
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            pending?.cancel()
            pending = Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                if !Task.isCancelled { self?.onChange() }
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    func makeUIView(context: Context) -> PKCanvasView {
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = .systemBackground
        canvas.alwaysBounceVertical = true
        canvas.contentSize = CGSize(width: 0, height: 3000)
        canvas.delegate = context.coordinator
        let picker = context.coordinator.picker
        picker.setVisible(true, forFirstResponder: canvas)
        picker.addObserver(canvas)
        DispatchQueue.main.async { canvas.becomeFirstResponder() }
        return canvas
    }

    func updateUIView(_ view: PKCanvasView, context: Context) {}
}
