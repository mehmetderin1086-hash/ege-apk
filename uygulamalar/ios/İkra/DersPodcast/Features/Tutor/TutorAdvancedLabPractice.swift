import Charts
import SwiftUI

struct TutorVectorLab: View {
    @State private var mass = 3.0
    @State private var force = 10.0
    @State private var angle = 30.0
    @State private var initialVelocity = 0.0
    @State private var time = 2.0
    @State private var forces = true
    @State private var components = true
    @State private var velocity = true
    @State private var acceleration = true
    private var model: TutorForceModel { .init(mass: mass, force: force, angleDegrees: angle, initialVelocity: initialVelocity, time: time) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sürtünmesiz yatay düzlemde, sabit açılı kuvvet uygulanan blok")
            Canvas { context, size in
                let origin = CGPoint(x: size.width * 0.40, y: size.height * 0.50)
                let largestForce = max(mass * 9.81, model.normal, 15)
                let unit = min((size.width - origin.x - 36) / 15, (size.height * 0.43 - 18) / largestForce)
                let floorY = origin.y + 18
                var floor = Path(); floor.move(to: .init(x: 8, y: floorY)); floor.addLine(to: .init(x: size.width - 8, y: floorY))
                context.stroke(floor, with: .color(.secondary), lineWidth: 2)
                context.fill(Path(CGRect(x: origin.x - 24, y: origin.y - 18, width: 48, height: 36)), with: .color(.gray.opacity(0.4)))
                func arrow(_ x: Double, _ y: Double, color: Color, label: String) {
                    let end = CGPoint(x: origin.x + x * unit, y: origin.y - y * unit)
                    var line = Path(); line.move(to: origin); line.addLine(to: end)
                    let theta = atan2(end.y - origin.y, end.x - origin.x)
                    line.move(to: .init(x: end.x - 8 * cos(theta - .pi / 6), y: end.y - 8 * sin(theta - .pi / 6)))
                    line.addLine(to: end)
                    line.addLine(to: .init(x: end.x - 8 * cos(theta + .pi / 6), y: end.y - 8 * sin(theta + .pi / 6)))
                    context.stroke(line, with: .color(color), lineWidth: 2.5)
                    context.draw(Text(label).font(.caption.bold()).foregroundColor(color), at: .init(x: end.x + (x < 0 ? -14 : 16), y: end.y + (y < 0 ? 8 : -10)))
                }
                // The vertical arrows use the same force scale, bounded by the controls below.
                if forces {
                    arrow(model.horizontalForce, model.verticalForce, color: .teal, label: "F")
                    arrow(0, model.normal, color: .blue, label: "N")
                    arrow(0, -mass * 9.81, color: .purple, label: "mg")
                }
                if components {
                    arrow(model.horizontalForce, 0, color: .orange, label: "Fx")
                    // Offset annotation avoids covering the collinear normal-force label.
                    let end = CGPoint(x: origin.x + model.horizontalForce * unit, y: origin.y - model.verticalForce * unit)
                    var projection = Path(); projection.move(to: .init(x: end.x, y: origin.y)); projection.addLine(to: end)
                    context.stroke(projection, with: .color(.orange), style: .init(lineWidth: 2, dash: [4, 4]))
                    context.draw(Text("Fy").font(.caption.bold()).foregroundColor(.orange), at: .init(x: end.x + 16, y: (end.y + origin.y) / 2))
                }
            }.frame(height: 300).background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
            Toggle("Kuvvetler: F, N ve mg", isOn: $forces)
            Toggle("Kuvvetin x / y bileşenleri", isOn: $components)
            Toggle("Hız katmanı", isOn: $velocity)
            Toggle("İvme katmanı", isOn: $acceleration)
            if velocity { vectorRow("Hız", value: model.velocity, unit: "m/s", color: .green) }
            if acceleration { vectorRow("İvme", value: model.acceleration, unit: "m/s²", color: .orange) }
            TutorAdvancedSlider(title: "Kütle (kg)", value: $mass, range: 2...3.5, step: 0.1)
            TutorAdvancedSlider(title: "Uygulanan kuvvet (N)", value: $force, range: 0...15, step: 0.5)
            TutorAdvancedSlider(title: "Kuvvet açısı (°)", value: $angle, range: -30...60)
            TutorAdvancedSlider(title: "İlk hız (m/s)", value: $initialVelocity, range: -10...10, step: 0.5)
            TutorAdvancedSlider(title: "Geçen süre (s)", value: $time, range: 0...5, step: 0.1)
            TutorLabMetric(title: "Fx = F cos θ", value: "\(model.horizontalForce.formatted(.number.precision(.fractionLength(2)))) N")
            TutorLabMetric(title: "N = mg − F sin θ", value: "\(model.normal.formatted(.number.precision(.fractionLength(2)))) N")
            TutorLabMetric(title: "ax = Fx / m", value: "\(model.acceleration.formatted(.number.precision(.fractionLength(2)))) m/s²")
            Text("Düşey net kuvvet 0: blok yüzeyden ayrılmaz. vx = v₀ + ax·t. Hız negatifken ivmenin pozitif olabileceğini ilk hızı değiştirerek gözlemle.")
            TutorLabNote(text: "g = 9,81 m/s². Sürtünme ve hava direnci yok; kuvvet sabit. Hız ve ivme ayrı birimlere sahip olduğundan ayrı satırlarda gösterilir. Her karede tüm kuvvet okları aynı ölçeği kullanır; çizim ölçeği alana göre uyarlanır.")
        }.learnLabMeasurement(.init(inputs: ["Kütle (kg)": String(mass), "Kuvvet (N)": String(force), "Açı (°)": String(angle), "İlk hız (m/s)": String(initialVelocity), "Süre (s)": String(time)], outputs: ["İvme (m/s²)": model.acceleration, "Hız (m/s)": model.velocity, "Normal (N)": model.normal]))
    }
    private func vectorRow(_ title: String, value: Double, unit: String, color: Color) -> some View {
        HStack {
            Text(title).bold()
            Image(systemName: value < -0.0001 ? "arrow.left" : value > 0.0001 ? "arrow.right" : "circle")
                .foregroundStyle(color)
            Spacer()
            Text("\(value.formatted(.number.precision(.fractionLength(2)))) \(unit)").monospacedDigit()
        }.padding(10).background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct TutorChemistryLab: View {
    @State private var reactionID = "water"
    @State private var coefficients = [1, 1, 1]
    private var reaction: TutorChemistry.Reaction { TutorChemistry.reactions.first { $0.id == reactionID } ?? TutorChemistry.reactions[0] }
    private var charge: (left: Int, right: Int) { reaction.charge(coefficients) }
    private var equation: String {
        func side(_ start: Int, _ species: [TutorChemistry.Species]) -> String {
            species.enumerated().map { offset, item in
                let coefficient = coefficients.indices.contains(start + offset) ? coefficients[start + offset] : 1
                return "\(coefficient == 1 ? "" : String(coefficient))\(item.formula)"
            }.joined(separator: " + ")
        }
        return side(0, reaction.left) + " → " + side(reaction.left.count, reaction.right)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Tepkime", selection: $reactionID) { ForEach(TutorChemistry.reactions) { Text($0.title).tag($0.id) } }
                .onChange(of: reactionID) { _, _ in coefficients = Array(repeating: 1, count: reaction.left.count + reaction.right.count) }
            Text(equation).font(.title3.bold()).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            Text("Yalnız katsayıları değiştir; molekül formülündeki alt indisleri değiştirme.").font(.callout)
            ForEach(Array((reaction.left + reaction.right).enumerated()), id: \.offset) { index, species in
                Stepper("\(index < reaction.left.count ? "Giren" : "Ürün") · \(species.formula): \(coefficients.indices.contains(index) ? coefficients[index] : 1)", value: Binding(get: { coefficients.indices.contains(index) ? coefficients[index] : 1 }, set: { if coefficients.indices.contains(index) { coefficients[index] = $0 } }), in: 1...12)
            }
            Grid(horizontalSpacing: 18, verticalSpacing: 12) {
                GridRow { Text("Korunan").bold(); Text("Giren").bold(); Text("Ürün").bold(); Text("Durum").bold() }
                ForEach(reaction.counts(coefficients), id: \.element) { row in
                    GridRow { Text(row.element); Text(String(row.left)); Text(String(row.right)); Image(systemName: row.left == row.right ? "checkmark.circle.fill" : "xmark.circle").foregroundStyle(row.left == row.right ? .green : .orange) }
                }
                GridRow { Text("Net yük"); Text(String(charge.left)); Text(String(charge.right)); Image(systemName: charge.left == charge.right ? "checkmark.circle.fill" : "xmark.circle").foregroundStyle(charge.left == charge.right ? .green : .orange) }
            }.frame(maxWidth: .infinity).padding().background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
            Label(reaction.balanced(coefficients) ? "Atom sayıları ve net yük korunuyor." : "Henüz denk değil; turuncu satırları kontrol et.", systemImage: reaction.balanced(coefficients) ? "checkmark.seal" : "equal.circle").foregroundStyle(reaction.balanced(coefficients) ? .green : .orange)
            Button("En küçük tam sayı katsayılarını göster") { coefficients = reaction.solution }.buttonStyle(.bordered)
            TutorLabNote(text: "Denkleştirme, tepkimenin verilen biçimindeki atom ve yük korunmasını kontrol eder. Tek başına tepkimenin kendiliğinden gerçekleştiğini kanıtlamaz. Elektronun atom sayısı sıfır, yükü −1'dir.")
            Link("Kaynak: OpenStax · atom ve yük denkliği", destination: URL(string: "https://openstax.org/books/chemistry/pages/17-1-balancing-oxidation-reduction-reactions")!)
        }.learnLabMeasurement(.init(inputs: Dictionary(uniqueKeysWithValues: [("Tepkime", reactionID)] + coefficients.enumerated().map { ("Katsayı " + String($0.offset + 1), String($0.element)) }), outputs: ["Giren yük": Double(charge.left), "Ürün yük": Double(charge.right)], observation: equation + (reaction.balanced(coefficients) ? " · Atom ve yük korunuyor" : " · Denk değil")))
    }
}

struct TutorProbabilityLab: View {
    @State private var event = TutorProbability.Event.coin
    @State private var trials: [TutorProbabilityTrial] = []
    private var plotted: [TutorProbabilityTrial] {
        let strideSize = max(1, trials.count / 400)
        return trials.enumerated().compactMap { index, trial in index % strideSize == 0 || index == trials.count - 1 ? trial : nil }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Olay", selection: $event) { ForEach(TutorProbability.Event.allCases) { Text($0.rawValue).tag($0) } }
                .onChange(of: event) { _, _ in trials = [] }
            TutorLabMetric(title: "Kuramsal olasılık", value: event.theoretical.formatted(.percent.precision(.fractionLength(2))))
            Chart {
                RuleMark(y: .value("Kuramsal", event.theoretical)).foregroundStyle(.orange).lineStyle(.init(lineWidth: 2, dash: [5, 3]))
                ForEach(plotted) { trial in LineMark(x: .value("Deneme", trial.id), y: .value("Göreli sıklık", trial.frequency)).foregroundStyle(.blue) }
            }.chartYScale(domain: 0.0...1.0).frame(height: 230).chartXAxisLabel("Bağımsız deneme sayısı").chartYAxisLabel("Göreli sıklık")
            HStack {
                ForEach([1, 100, 1000], id: \.self) { count in Button("+\(count)") { var rng = SystemRandomNumberGenerator(); trials = TutorProbability.append(count, event: event, trials: trials, using: &rng) }.buttonStyle(.bordered).disabled(trials.count >= 10000) }
                Spacer()
                Button("Sıfırla") { trials = [] }.disabled(trials.isEmpty)
            }
            TutorLabMetric(title: "Deneme / olayın oluşması", value: "\(trials.count) / \(trials.last?.successes ?? 0)")
            if let last = trials.last {
                TutorLabMetric(title: "Deneysel göreli sıklık", value: last.frequency.formatted(.percent.precision(.fractionLength(2))))
                TutorLabMetric(title: "Mutlak fark", value: "\((abs(last.frequency - event.theoretical) * 100).formatted(.number.precision(.fractionLength(2)))) yüzde puanı")
            }
            Text("Mavi çizgi her yeni deneyde yeniden hesaplanır; turuncu kesikli çizgi kuramsal olasılıktır. Sonraki atışın olasılığı önceki sonuçlara göre değişmez.")
            TutorLabNote(text: "Adil para/zar ve bağımsız atışlar varsayılır. Çok deneme yakınlaşma eğilimi sağlar; her adımda daha yakın sonuç veya tam eşitlik garantilemez. Cihazın rastgele sayı üreteci kullanılır; oturum sınırı 10.000 denemedir.")
        }.learnLabMeasurement(.init(inputs: ["Olay": event.rawValue, "Deneme sayısı": String(trials.count)], outputs: ["Göreli sıklık": trials.last?.frequency ?? 0, "Kuramsal olasılık": event.theoretical], observation: "Bağımsız rastgele örneklem; farklı koşulların nedensel karşılaştırması değildir."))
    }
}

nonisolated struct TutorEvidenceAnnotation: Codable, Identifiable, Sendable {
    var id = UUID()
    let claim: String
    let passage: String
    let evidence: [String]
    let kind: TutorEvidence.Kind
}

struct TutorEvidenceLab: View {
    @State private var custom: Bool
    @State private var passage: String
    @State private var claim = ""
    @State private var claimID = 0
    @State private var selected: Set<Int> = []
    @State private var kind = TutorEvidence.Kind.direct
    @State private var reveal = false
    @State private var savedMessage = ""
    @State private var analyzing = false
    @State private var analysis: TutorEvidenceAnalysis.Result?
    @State private var analysisError = ""
    @State private var analysisTask: Task<Void, Never>?
    @AppStorage("tutor.lab.evidence.annotations.v1") private var savedJSON = "[]"
    init(sourceText: String = "") {
        _passage = State(initialValue: sourceText)
        _custom = State(initialValue: !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
    private var sample: TutorEvidence.Claim { TutorEvidence.claims.first { $0.id == claimID } ?? TutorEvidence.claims[0] }
    private var lines: [String] { custom ? TutorEvidence.split(passage) : TutorEvidence.sentences }
    private var annotations: [TutorEvidenceAnnotation] { (try? JSONDecoder().decode([TutorEvidenceAnnotation].self, from: Data(savedJSON.utf8))) ?? [] }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Metin", selection: $custom) { Text("Açıklamalı örnek").tag(false); Text("Kendi metnim").tag(true) }.pickerStyle(.segmented)
                .onChange(of: custom) { _, _ in selected = []; reveal = false; savedMessage = "" }
            if custom {
                Text("Metni düzenle; ayrı değerlendirmek istediğin her cümleyi yeni satıra yaz.").font(.caption)
                TextEditor(text: $passage).frame(minHeight: 120).padding(6).overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.5)))
                    .onChange(of: passage) { _, _ in selected = []; savedMessage = ""; invalidateAnalysis() }
                TextField("Değerlendirilecek iddia / seçenek", text: $claim, axis: .vertical).textFieldStyle(.roundedBorder)
                    .onChange(of: claim) { _, _ in invalidateAnalysis() }
                Button(analyzing ? "Kanıtlar inceleniyor…" : "Metinden kanıtları bul", systemImage: "text.magnifyingglass") { analyze() }
                    .buttonStyle(.borderedProminent).disabled(analyzing || passage.isEmpty || claim.isEmpty)
                if analyzing { ProgressView(); Button("İptal") { invalidateAnalysis() } }
                if !analysisError.isEmpty { Text(analysisError).foregroundStyle(.red) }
                if let analysis {
                    Text("Model değerlendirmesi · \(analysis.kind.rawValue)").font(.headline)
                    Text(analysis.explanation)
                    ForEach(analysis.quotes.indices, id: \.self) { i in Text("“\(analysis.quotes[i].quote)”").font(.callout).foregroundStyle(.secondary) }
                }
            } else {
                Picker("İddia", selection: $claimID) { ForEach(TutorEvidence.claims) { Text($0.text).tag($0.id) } }
                    .onChange(of: claimID) { _, _ in selected = []; reveal = false }
                Text(sample.text).font(.headline)
            }
            Text("Kanıt cümlelerini seç").font(.headline)
            ForEach(lines.indices, id: \.self) { index in
                Button { if selected.contains(index) { selected.remove(index) } else { selected.insert(index) } } label: {
                    HStack(alignment: .top) {
                        Text("\(index + 1)").bold().frame(width: 22)
                        Text(lines[index]).frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: selected.contains(index) ? "checkmark.circle.fill" : "circle")
                    }.padding(10).background(selected.contains(index) ? Color.yellow.opacity(0.3) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain)
            }
            Picker("İlişki", selection: $kind) { ForEach(TutorEvidence.Kind.allCases) { Text($0.rawValue).tag($0) } }
            if custom {
                Button("Kanıt bağlantısını kaydet") { save() }.buttonStyle(.borderedProminent)
                    .disabled(claim.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || lines.isEmpty || (kind != .unsupported && selected.isEmpty))
                if !savedMessage.isEmpty { Text(savedMessage).foregroundStyle(.green) }
                TutorLabNote(text: "İşaretleri kendin düzenleyebilir veya modelden öneri isteyebilirsin. Model alıntıları kaynakta birebir kontrol edilir; mantıksal değerlendirme yine incelenmelidir. Doğrudan bilgi açıkça yazılıdır, çıkarım gerekçe gerektirir. Desteklenmeyen iddia için kanıt seçmek zorunlu değildir.")
            } else {
                Button("Gerekçeyi kontrol et") { reveal = true }.buttonStyle(.borderedProminent)
                if reveal {
                    Label(kind == sample.kind && selected == Set(sample.evidence) ? "İlişki ve kanıtlar eşleşti" : "Gerekçeyle karşılaştır", systemImage: kind == sample.kind && selected == Set(sample.evidence) ? "checkmark.circle" : "magnifyingglass")
                    Text("\(sample.kind.rawValue): \(sample.explanation)")
                    Button("İlgili cümleleri işaretle") { selected = Set(sample.evidence); kind = sample.kind }
                }
            }
            if !annotations.isEmpty {
                DisclosureGroup("Kaydettiğim kanıt bağlantıları · \(annotations.count)") {
                    ForEach(annotations.suffix(20).reversed()) { note in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(note.claim).font(.headline)
                            Text(note.kind.rawValue).font(.caption).foregroundStyle(.secondary)
                            ForEach(note.evidence, id: \.self) { Text("“\($0)”").font(.callout) }
                            Button("Metni ve bağlantıyı aç") {
                                custom = true; passage = note.passage; claim = note.claim; kind = note.kind
                                Task { @MainActor in
                                    await Task.yield()
                                    selected = Set(TutorEvidence.split(note.passage).enumerated().compactMap { note.evidence.contains($0.element) ? $0.offset : nil })
                                }
                            }.font(.caption)
                        }.padding(.vertical, 8)
                        Divider()
                    }
                }
            }
        }.onDisappear { analysisTask?.cancel() }.learnLabMeasurement(.init(inputs: ["Metin": custom ? passage : TutorEvidence.sentences.joined(separator: "\n"), "İddia": custom ? claim : sample.text, "İlişki": kind.rawValue, "Seçilen satırlar": selected.sorted().map(String.init).joined(separator: ",")], observation: custom ? (analysis?.explanation ?? "Öğrencinin işaretlediği kanıt; bağımsız değerlendirme yok") : (reveal ? sample.explanation : "Gerekçe henüz açılmadı")))
    }
    private func invalidateAnalysis() {
        analysisTask?.cancel(); analyzing = false; analysis = nil; analysisError = ""
    }
    private func analyze() {
        analysisTask?.cancel()
        let originalPassage = passage, originalClaim = claim
        analyzing = true; analysisError = ""; analysis = nil
        analysisTask = Task { @MainActor in
            do {
                let prompt = try TutorEvidenceAnalysis.prompt(passage: originalPassage, claim: originalClaim)
                let answer = try await TutorEngine.reply(mode: .summary, subject: "Türkçe · paragrafta kanıt ve çıkarım", level: "Lise / TYT", messages: [.init(role: "user", text: prompt)])
                try Task.checkCancellation()
                let result = try TutorEvidenceAnalysis.parse(answer, passage: originalPassage)
                guard passage == originalPassage, claim == originalClaim else { return }
                analysis = result; kind = result.kind; selected = Set(result.evidence); analyzing = false
            } catch is CancellationError { }
            catch { if !Task.isCancelled { analysisError = error.localizedDescription; analyzing = false } }
        }
    }
    private func save() {
        let note = TutorEvidenceAnnotation(claim: claim.trimmingCharacters(in: .whitespacesAndNewlines), passage: passage, evidence: lines.enumerated().compactMap { selected.contains($0.offset) ? $0.element : nil }, kind: kind)
        var notes = annotations
        if !notes.contains(where: { $0.claim == note.claim && $0.passage == note.passage && $0.kind == note.kind && $0.evidence == note.evidence }) { notes.append(note) }
        if let data = try? JSONEncoder().encode(notes), let json = String(data: data, encoding: .utf8) { savedJSON = json; savedMessage = "Metin, iddia ve kanıt bağlantısı cihazda kaydedildi." }
    }
}
