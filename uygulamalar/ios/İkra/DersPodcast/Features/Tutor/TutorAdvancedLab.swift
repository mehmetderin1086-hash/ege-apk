import Charts
import SwiftUI

/// A common laboratory entry point, also presented from the question workspace.
struct TutorAdvancedLabView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var mode: TutorAdvancedExperiment
    let sourceText: String
    init(sourceText: String = "", initialMode: TutorAdvancedExperiment = .matter) {
        self.sourceText = sourceText
        _mode = State(initialValue: initialMode)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Picker("Laboratuvar", selection: $mode) {
                        ForEach(TutorAdvancedExperiment.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
                    }.pickerStyle(.menu)
                    TutorAdvancedLabContent(mode: mode, sourceText: sourceText)
                        .id(mode)
                }.padding()
            }
            .navigationTitle("Ders laboratuvarı")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Kapat") { dismiss() } } }
        }
    }
}

struct TutorAdvancedLabContent: View {
    @State private var measurement: LearnLabMeasurement?
    let mode: TutorAdvancedExperiment
    var sourceText: String = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(mode.rawValue, systemImage: mode.symbol).font(.title2.bold())
            LearnLabNotebook(mode: mode.rawValue, sample: measurement).id(mode.rawValue)
            switch mode {
            case .matter: TutorMatterLab()
            case .comparison: TutorComparisonLab()
            case .pedigree: TutorPedigreeLab()
            case .conditions: TutorConditionsLab()
            case .function: TutorFunctionLab()
            case .geometry: TutorGeometryLab()
            case .vectors: TutorVectorLab()
            case .chemistry: TutorChemistryLab()
            case .probability: TutorProbabilityLab()
            case .evidence: TutorEvidenceLab(sourceText: sourceText)
            }
        }.onPreferenceChange(LearnLabMeasurementKey.self) { measurement = $0 }
    }
}

struct TutorAdvancedSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack { Text(title); Spacer(); Text(value.formatted(.number.precision(.fractionLength(0...2)))).monospacedDigit() }
            Slider(value: $value, in: range, step: step) { Text(title) }
        }
    }
}
struct TutorLabNote: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "info.circle")
            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}
struct TutorLabMetric: View {
    let title: String
    let value: String
    var body: some View {
        HStack(alignment: .firstTextBaseline) { Text(title); Spacer(minLength: 12); Text(value).bold().monospacedDigit().multilineTextAlignment(.trailing) }
            .padding(10).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct TutorMatterLab: View {
    @State private var carbon = false
    @State private var stage = 0
    @State private var animate = false
    @Namespace private var atomMotion
    private struct Stop { let compound: String; let process: String; let description: String }
    private var route: [Stop] {
        if carbon {
            return [
                .init(compound: "CO₂", process: "Atmosfer", description: "İzlediğimiz karbon atomu başlangıçta atmosferde bir karbondioksit molekülündedir."),
                .init(compound: "Bitkide organik C", process: "Fotosentez ve karbon bağlanması", description: "CO₂'nin karbonu fotosentez yoluyla organik moleküllere katılır. Işık enerjisi maddeye dönüşmez; kimyasal enerjiye aktarılır."),
                .init(compound: "Hayvanda organik C", process: "Beslenme ve özümleme", description: "Örneğimizde bitkiyle beslenen hayvan, organik moleküldeki karbonu kendi moleküllerinde kullanır."),
                .init(compound: "CO₂", process: "Hücresel solunum", description: "Organik maddenin oksidasyonu sırasında izlenen karbon atomu yeniden CO₂'ye geçebilir. Bitkiler de hücresel solunum yapar.")
            ]
        }
        return [
            .init(compound: "N₂", process: "Atmosfer", description: "Renkli N simgesi izlediğimiz tek azot atomudur. Moleküllerin sayısını veya tepkimenin katsayılarını temsil etmez."),
            .init(compound: "NH₄⁺", process: "Biyolojik azot bağlanması", description: "Azot bağlayan mikroorganizmalar N₂'yi amonyağa indirger; sulu ortamda amonyum biçimi bulunabilir. Nitrifikasyon bu basamak değildir."),
            .init(compound: "NO₂⁻", process: "Nitrifikasyonun ilk basamağı", description: "Amonyak/amonyumdaki azot oksitlenerek nitrite geçer."),
            .init(compound: "NO₃⁻", process: "Nitrifikasyonun ikinci basamağı", description: "Nitritteki azot oksitlenerek nitrata geçer. Azot atomu korunurken bulunduğu kimyasal tür değişir."),
            .init(compound: "Bitkide organik N", process: "Alım ve özümleme", description: "Bitki aldığı nitratın azotunu indirgeme ve özümleme basamaklarıyla organik moleküllerine katar. Bitkiler amonyum da alabilir."),
            .init(compound: "NH₄⁺", process: "Amonifikasyon", description: "Organik azotun ayrıştırılmasıyla amonyum oluşabilir. Ayrı bir yol olan denitrifikasyon nitratı gaz hâlindeki azot türlerine dönüştürür; burada çizilen yolun devamı değildir.")
        ]
    }
    private var currentStage: Int { min(stage, route.count - 1) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Atom", selection: $carbon) { Text("Azot").tag(false); Text("Karbon").tag(true) }
                .pickerStyle(.segmented).onChange(of: carbon) { _, _ in stage = 0; animate = false }
            HStack(spacing: 12) {
                Text(carbon ? "C" : "N").font(.largeTitle.bold()).frame(width: 68, height: 68)
                    .background(.teal.opacity(0.2), in: Circle()).overlay(Circle().stroke(.teal, lineWidth: 3))
                VStack(alignment: .leading) {
                    Text(route[currentStage].compound).font(.title2.bold()).contentTransition(.numericText())
                    Text(route[currentStage].process).font(.headline)
                }
            }
            ForEach(route.indices, id: \.self) { index in
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { stage = index }
                } label: {
                    HStack(alignment: .top) {
                        ZStack {
                            Circle().stroke(.secondary.opacity(0.3), lineWidth: 1)
                            if index == stage {
                                Text(carbon ? "C" : "N").font(.caption.bold()).foregroundStyle(.white)
                                    .frame(width: 26, height: 26).background(.teal, in: Circle())
                                    .matchedGeometryEffect(id: "tracked-atom", in: atomMotion)
                            } else if index < stage { Image(systemName: "checkmark").font(.caption).foregroundStyle(.teal) }
                        }.frame(width: 26, height: 26)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(route[index].compound).font(.headline)
                            Text(route[index].process).font(.caption)
                        }
                        Spacer()
                    }.padding(9).background(index == stage ? Color.teal.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain).accessibilityAddTraits(index == stage ? .isSelected : [])
            }
            Text(route[currentStage].description).padding().background(.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            HStack {
                Button("Geri", systemImage: "backward.end") { stage = max(0, stage - 1) }.disabled(stage == 0)
                Spacer()
                Button(animate ? "Durdur" : "İzi oynat", systemImage: animate ? "pause" : "play") { if stage == route.count - 1 { stage = 0 }; animate.toggle() }
                Spacer()
                Button("İleri", systemImage: "forward.end") { stage = min(route.count - 1, stage + 1) }.disabled(stage == route.count - 1)
            }.buttonStyle(.bordered)
            TutorLabNote(text: "Döngünün bütün dalları değil, seçilmiş bir atomun örnek yolu gösterilir. Süre ve ok uzunlukları gerçek hız veya miktar değildir.")
            Link("Kaynak: NASA · madde döngüleri", destination: URL(string: "https://mynasadata.larc.nasa.gov/basic-page/energy-and-matter-cycles")!)
        }.task(id: animate) {
            guard animate else { return }
            while !Task.isCancelled, animate, stage < route.count - 1 {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled, animate else { return }
                withAnimation { stage += 1 }
            }
            animate = false
        }.learnLabMeasurement(.init(inputs: ["Atom": carbon ? "C" : "N", "Basamak": String(currentStage)], observation: route[currentStage].compound + " · " + route[currentStage].description))
    }
}

private struct TutorComparisonLab: View {
    @State private var energy = false
    @State private var focus = "Tüm ölçütler"
    private struct Row { let name: String; let left: String; let right: String }
    private var rows: [Row] {
        energy ? [
            .init(name: "Net madde ilişkisi", left: "Oksijenli fotosentezde CO₂ ve su kullanılır; organik madde ve O₂ oluşur.", right: "Glikozun oksijenli solunumunda organik madde ve O₂ kullanılır; CO₂ ve su oluşur."),
            .init(name: "Enerji", left: "Işık enerjisi kimyasal enerjiye aktarılır; karbon bağlama enerji gerektirir.", right: "Organik moleküllerin kimyasal enerjisinin bir bölümü ATP'ye aktarılır; ısı da açığa çıkar."),
            .init(name: "Ökaryot hücrede yer", left: "Işığa bağlı tepkimeler tilakoit zarında; Calvin döngüsü kloroplast stromasında.", right: "Glikoliz sitozolde; diğer ana basamaklar mitokondri matriksinde ve iç zarında."),
            .init(name: "Ortak yön", left: "Elektron taşıma ve proton gradyanı üzerinden ATP sentezi bulunur.", right: "Elektron taşıma ve proton gradyanı üzerinden ATP sentezi bulunur."),
            .init(name: "Kritik ayrım", left: "O₂'nin atomları sudan gelir. Bitkiler fotosentezin yanında solunum da yapar.", right: "Net madde denklemlerinin ters görünmesi, süreçlerin aynı mekanizmanın tersi olduğu anlamına gelmez.")
        ] : [
            .init(name: "Bölünme sayısı", left: "Bir çekirdek bölünmesi.", right: "Bir DNA eşlenmesini izleyen iki çekirdek bölünmesi."),
            .init(name: "Ploidi", left: "Başlangıç ploidisi korunur: 2n → 2n veya n → n.", right: "Diploit başlangıçta homolog takımlar ayrılır: 2n → n."),
            .init(name: "Ürün sayısı", left: "Tipik olarak iki yavru hücre.", right: "Dört haploit çekirdek; oogenezde sitoplazma eşit paylaşılmaz ve dört eşdeğer gamet oluşmaz."),
            .init(name: "Genetik benzerlik", left: "Mutasyonlar dışında yavruların kalıtsal bilgisi genellikle aynı kalır.", right: "Bağımsız dağılım ve varsa crossing-over genetik çeşitliliğe katkı sağlar."),
            .init(name: "İlk ayrılan yapılar", left: "Kardeş kromatitler ayrılır.", right: "Mayoz I'de homolog kromozomlar, mayoz II'de kardeş kromatitler ayrılır.")
        ]
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Karşılaştırma", selection: $energy) { Text("Mitoz / Mayoz").tag(false); Text("Fotosentez / Solunum").tag(true) }.pickerStyle(.menu)
                .onChange(of: energy) { _, _ in focus = "Tüm ölçütler" }
            Picker("Ölçüt", selection: $focus) {
                Text("Tüm ölçütler").tag("Tüm ölçütler")
                ForEach(rows, id: \.name) { Text($0.name).tag($0.name) }
            }
            ForEach(rows.filter { focus == "Tüm ölçütler" || $0.name == focus }, id: \.name) { row in
                VStack(alignment: .leading, spacing: 10) {
                    Text(row.name).font(.headline)
                    VStack(alignment: .leading, spacing: 4) { Text(energy ? "Fotosentez" : "Mitoz").bold().foregroundStyle(.teal); Text(row.left) }
                    Divider()
                    VStack(alignment: .leading, spacing: 4) { Text(energy ? "Oksijenli solunum" : "Mayoz").bold().foregroundStyle(.purple); Text(row.right) }
                }.padding().background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
            }
            TutorLabNote(text: "Genel okul biyolojisi modeli. Özel canlı grupları ve farklı yaşam döngüleri için kapsam ayrıca değerlendirilir.")
            Link("Kaynak: OpenStax Biology 2e", destination: URL(string: "https://openstax.org/books/biology-2e/pages/11-1-the-process-of-meiosis")!)
        }.learnLabMeasurement(.init(inputs: ["Karşılaştırma": energy ? "Fotosentez / Solunum" : "Mitoz / Mayoz", "Ölçüt": focus], observation: rows.filter { focus == "Tüm ölçütler" || $0.name == focus }.map { $0.name + ": " + $0.left + " / " + $0.right }.joined(separator: "\n")))
    }
}

private struct TutorPedigreeLab: View {
    @State private var mother = TutorPedigree.Phenotype.unaffected
    @State private var father = TutorPedigree.Phenotype.unaffected
    @State private var child = TutorPedigree.Phenotype.affected
    private var crosses: [TutorPedigree.Cross] { TutorPedigree.possible(mother: mother, father: father, child: child) }
    private var mothers: [String] { Set(crosses.map(\.mother)).sorted() }
    private var fathers: [String] { Set(crosses.map(\.father)).sorted() }
    private var children: [String] { Set(crosses.flatMap(\.children).filter { child.accepts($0) }).sorted() }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Otozomal çekinik tek gen modeli · aa özelliği gösterir; AA ve Aa göstermez.").font(.callout).fixedSize(horizontal: false, vertical: true)
            phenotypePicker("Anne", value: $mother)
            phenotypePicker("Baba", value: $father)
            phenotypePicker("Gözlenen çocuk", value: $child)
            VStack(spacing: 10) {
                HStack { person("Anne", genes: mothers, round: true); Spacer(); person("Baba", genes: fathers, round: false) }
                Rectangle().fill(.secondary).frame(height: 2)
                Rectangle().fill(.secondary).frame(width: 2, height: 20)
                person("Çocuk", genes: children, round: true)
            }.padding().background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 14))
            if crosses.isEmpty { Label("Bu gözlemler seçili modelde birbiriyle çelişiyor.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
            else {
                Text("\(crosses.count) olası ebeveyn eşleşmesi").font(.headline)
                ForEach(crosses.indices, id: \.self) { index in
                    let cross = crosses[index]
                    TutorLabMetric(title: "\(cross.mother) × \(cross.father)", value: "Sonraki çocuk aa: \(cross.affectedProbability.formatted(.percent.precision(.fractionLength(0))))")
                }
            }
            TutorLabNote(text: "Yeşil tek seçenek kesinleşen genotipi; turuncu birden fazla seçenek belirsizliği gösterir. Eşleşmelerin olasılıkları eşit varsayılmaz. Yüzdeler yalnız verilen ebeveyn genotiplerine koşullu, sonraki bağımsız doğuma aittir. Tam penetrans, yeni mutasyon olmaması ve Mendel kalıtımı varsayılır; tıbbi değerlendirme değildir.")
            Link("Kaynak: OpenStax · kalıtım yasaları", destination: URL(string: "https://openstax.org/books/biology/pages/12-3-laws-of-inheritance")!)
        }.learnLabMeasurement(.init(inputs: ["Anne": mother.rawValue, "Baba": father.rawValue, "Çocuk": child.rawValue], outputs: ["Olası ebeveyn eşleşmesi": Double(crosses.count)], observation: "Anne: " + mothers.joined(separator: "/") + " · Baba: " + fathers.joined(separator: "/")))
    }
    private func phenotypePicker(_ title: String, value: Binding<TutorPedigree.Phenotype>) -> some View {
        Picker(title, selection: value) { ForEach(TutorPedigree.Phenotype.allCases) { Text($0.rawValue).tag($0) } }
    }
    private func person(_ title: String, genes: [String], round: Bool) -> some View {
        VStack(spacing: 6) {
            Text(genes.isEmpty ? "∅" : genes.joined(separator: " / "))
                .font(.headline).minimumScaleFactor(0.75).frame(minWidth: 94, minHeight: 62)
                .background((genes.count == 1 ? Color.green : Color.orange).opacity(0.14), in: RoundedRectangle(cornerRadius: round ? 32 : 4))
            Text(title).font(.caption)
            Text(genes.count == 1 ? "Kesin" : genes.isEmpty ? "Çelişki" : "Olası").font(.caption.bold()).foregroundStyle(genes.count == 1 ? .green : .orange)
        }
    }
}
