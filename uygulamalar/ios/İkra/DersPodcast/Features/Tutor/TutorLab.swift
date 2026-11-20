import Charts
import SwiftUI

/// Hazır, cihazda çalışan küçük deneyler; internet veya model çıktısı yürütme gerektirmez.
struct TutorLabView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var experiment = TutorAdvancedExperiment.function.rawValue

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Değiştir, gözlemle, keşfet")
                        .font(.title2.bold())
                    Text("Ders laboratuvarları, hareket, devre ve hücre deneyleriyle kavramları keşfet. Değerler, çizimler ve kanıt bağlantıları cihazında güncellenir.")
                        .foregroundStyle(.secondary)
                    Picker("Deney", selection: $experiment) {
                        ForEach(TutorAdvancedExperiment.allCases) { Text($0.rawValue).tag($0.rawValue) }
                        Text("Elektrik devresi").tag("Elektrik devresi")
                        Text("Hareket, grafik ve denklem").tag("Hareket, grafik ve denklem")
                        Text("Hücre").tag("Hücre")
                    }
                    .pickerStyle(.menu)
                    if let mode = TutorAdvancedExperiment(rawValue: experiment) {
                        TutorAdvancedLabContent(mode: mode).id(mode)
                    } else if experiment == "Elektrik devresi" {
                        TutorCircuitLab()
                    } else if experiment == "Hareket, grafik ve denklem" {
                        QSCoupledMotionLabPanel()
                    } else {
                        TutorCellLab()
                    }
                }
                .padding()
            }
            .navigationTitle("Etkileşimli laboratuvar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
    }
}

private struct TutorCircuitLab: View {
    @State private var voltage = 6.0
    @State private var resistance = 10.0
    private var current: Double { voltage / resistance }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Ohm yasası: I = V / R").font(.title2)
            Canvas { context, size in
                let left: CGFloat = 30, right = size.width - 30
                let top: CGFloat = 35, bottom = size.height - 35
                var wire = Path()
                wire.move(to: CGPoint(x: left, y: top))
                wire.addLine(to: CGPoint(x: right, y: top))
                wire.addLine(to: CGPoint(x: right, y: bottom))
                wire.addLine(to: CGPoint(x: left, y: bottom))
                wire.closeSubpath()
                context.stroke(wire, with: .color(.secondary), lineWidth: 3)
                let battery = CGRect(x: left - 20, y: size.height / 2 - 22, width: 40, height: 44)
                let resistor = CGRect(x: right - 24, y: size.height / 2 - 27, width: 48, height: 54)
                context.fill(Path(battery), with: .color(.blue))
                context.fill(Path(resistor), with: .color(.orange))
                context.draw(Text("V").bold().foregroundColor(.white), at: CGPoint(x: left, y: size.height / 2))
                context.draw(Text("R").bold().foregroundColor(.black), at: CGPoint(x: right, y: size.height / 2))
                context.draw(Text("I →").bold(), at: CGPoint(x: size.width / 2, y: top - 17))
            }
            .frame(height: 170)
            .accessibilityLabel("Kapalı seri devre şeması: bir gerilim kaynağı ve bir direnç.")
            TutorLabSlider(title: "Gerilim V (volt)", value: $voltage, range: 0...24, step: 0.5)
            TutorLabSlider(title: "Direnç R (ohm)", value: $resistance, range: 1...100, step: 1)
            Text("Akım: \(current.formatted(.number.precision(.fractionLength(3)))) A")
                .font(.title2.bold()).monospacedDigit()
                .accessibilityLabel("Akım \(current.formatted()) amper")
            Text("Güç: \((voltage * current).formatted(.number.precision(.fractionLength(2)))) W")
                .monospacedDigit()
            Text("Dene: direnci sabit tutup gerilimi iki katına çıkar. Sonra gerilimi sabit tutup direnci artır. Akım nasıl değişiyor?")
            Text("İdeal, sıcaklığı sabit ohmik direnç modeli. Kabloların ve kaynağın iç direnci ihmal edilir. Şema ölçekli değildir.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct TutorLabSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(title): \(value.formatted(.number.precision(.fractionLength(1))))")
                .monospacedDigit()
            Slider(value: $value, in: range, step: step) { Text(title) }
                .accessibilityValue(value.formatted(.number.precision(.fractionLength(1))))
        }
    }
}

private struct TutorCellLab: View {
    private struct Organelle: Identifiable {
        let id: Int
        let name: String
        let explanation: String
        let x: CGFloat
        let y: CGFloat
        let color: Color
    }
    private let organelles: [Organelle] = [
        .init(id: 1, name: "Çekirdek", explanation: "DNA'nın büyük bölümünü taşır. Gen ifadesi yoluyla hücrenin faaliyetlerinin düzenlenmesinde rol alır.", x: 0.46, y: 0.44, color: .purple),
        .init(id: 2, name: "Mitokondri", explanation: "Oksijenli solunumun önemli basamakları burada gerçekleşir; ATP üretimine katkı sağlar. Kendine ait DNA'sı vardır.", x: 0.73, y: 0.35, color: .orange),
        .init(id: 3, name: "Ribozom", explanation: "mRNA'daki bilgiye göre amino asitleri birleştirerek protein sentezler. Zarsızdır; sitoplazmada serbest veya granüllü endoplazmik retikuluma bağlı bulunabilir.", x: 0.27, y: 0.30, color: .blue),
        .init(id: 4, name: "Golgi aygıtı", explanation: "Protein ve lipitleri işler, sınıflandırır ve keseciklere paketler. Hücre içi taşımaya ve salgılamaya katılır.", x: 0.64, y: 0.68, color: .pink),
        .init(id: 5, name: "Lizozom", explanation: "Asidik ortamda çalışan enzimlerle hücre içi sindirim yapar; yıpranmış hücresel bileşenlerin parçalanmasına katılır.", x: 0.30, y: 0.67, color: .green)
    ]
    @State private var selectedID = 1
    @State private var selfTest = false
    @State private var revealed = false
    private var selected: Organelle { organelles.first { $0.id == selectedID } ?? organelles[0] }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Hayvan hücresi").font(.title2)
            Text("Bir numaraya dokun; organelin görevini keşfet.")
            GeometryReader { geometry in
                ZStack {
                    Ellipse().fill(.teal.opacity(0.12))
                    Ellipse().stroke(.teal, lineWidth: 4)
                    ForEach(organelles) { organelle in
                        Button {
                            selectedID = organelle.id
                            revealed = false
                        } label: {
                            Text("\(organelle.id)").font(.title3.bold())
                                .foregroundStyle(.primary)
                                .frame(width: 48, height: 48)
                                .background(organelle.color.opacity(0.3), in: Circle())
                                .overlay(Circle().stroke(selectedID == organelle.id ? Color.primary : Color.clear, lineWidth: 3))
                        }
                        .buttonStyle(.plain)
                        .position(x: geometry.size.width * organelle.x, y: geometry.size.height * organelle.y)
                        .accessibilityLabel("\(organelle.id). \(organelle.name)")
                        .accessibilityAddTraits(selectedID == organelle.id ? .isSelected : [])
                    }
                }
            }
            .frame(height: 245)
            Text("Şematik çizimdir; şekiller, sayılar ve boyutlar gerçek hücreyi ölçekli temsil etmez. Hücre zarı dış sınırdır; açık renkli alan sitoplazmayı temsil eder. Bazı hücresel yapılar gösterilmemiştir.")
                .font(.caption).foregroundStyle(.secondary)
            Picker("Organel", selection: $selectedID) {
                ForEach(organelles) { Text("\($0.id). \($0.name)").tag($0.id) }
            }
            .onChange(of: selectedID) { _, _ in revealed = false }
            Toggle("Kendini sına: görevleri gizle", isOn: $selfTest)
                .onChange(of: selfTest) { _, _ in revealed = false }
            Text("\(selected.name) ne yapar?").font(.headline)
            if !selfTest || revealed {
                Text(selected.explanation)
            } else {
                Text("Önce görevi kendi cümlenle söyle, sonra açıklamayla karşılaştır.")
                    .foregroundStyle(.secondary)
                Button("Görevi göster") { revealed = true }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}
