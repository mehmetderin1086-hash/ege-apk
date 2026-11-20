import SwiftUI
import CoreGraphics
import CoreText

nonisolated struct LibraryPrintProfile: Codable, Sendable, Equatable {
    var marginMM: Double = 10
    var offsetXMM: Double = 0
    var offsetYMM: Double = 0
    var showStudentName = true
    var showStudentClass = true
    var showStudentNumber = false
    var calibration = false

    /// Kaydırma, kenar payından en az 2 mm bırakır; ilk/son hücre sayfa dışına çıkamaz.
    var effectiveMarginMM: Double { marginMM.isFinite ? min(24, max(4, marginMM)) : 10 }
    var maximumOffsetMM: Double { min(10, effectiveMarginMM - 2) }
    var normalized: LibraryPrintProfile {
        var result = self
        result.marginMM = effectiveMarginMM
        result.offsetXMM = boundedOffset(offsetXMM)
        result.offsetYMM = boundedOffset(offsetYMM)
        return result
    }
    private func boundedOffset(_ value: Double) -> Double {
        value.isFinite ? min(maximumOffsetMM, max(-maximumOffsetMM, value)) : 0
    }
    var margin: CGFloat { CGFloat(effectiveMarginMM) * 72 / 25.4 }
    var offset: CGSize {
        CGSize(width: boundedOffset(offsetXMM) * 72 / 25.4,
               height: boundedOffset(offsetYMM) * 72 / 25.4)
    }
    static func load(_ key: String) -> LibraryPrintProfile {
        (UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(Self.self, from: $0) } ?? .init()).normalized
    }
    static func save(_ profile: LibraryPrintProfile, key: String) {
        if let data = try? JSONEncoder().encode(profile.normalized) { UserDefaults.standard.set(data, forKey: key) }
    }
    static let labelsKey = "libraryLabelPrintProfile"
    static let studentKey = "libraryStudentPrintProfile"
    func drawRuler(in context: CGContext, pageHeight: CGFloat) {
        guard calibration else { return }
        let start: CGFloat = 24, y = pageHeight - 14
        context.setStrokeColor(CGColor(gray: 0, alpha: 1)); context.setLineWidth(0.7)
        context.move(to: CGPoint(x: start, y: y)); context.addLine(to: CGPoint(x: start + 100 * 72 / 25.4, y: y))
        for mm in stride(from: 0, through: 100, by: 10) {
            let x = start + CGFloat(mm) * 72 / 25.4
            context.move(to: CGPoint(x: x, y: y - 3)); context.addLine(to: CGPoint(x: x, y: y + 3))
        }
        context.strokePath()
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "100 mm · A4 · %100", attributes: [.font: CTFontCreateWithName("Helvetica" as CFString, 8, nil)]))
        context.textPosition = CGPoint(x: start + 100 * 72 / 25.4 + 8, y: y - 3)
        CTLineDraw(line, context)
    }
}

struct PrintCalibrationView: View {
    @State private var kind = 0
    @State private var profile = LibraryPrintProfile.load(LibraryPrintProfile.labelsKey)
    @State private var sampleURL: URL?
    private var key: String { kind == 0 ? LibraryPrintProfile.labelsKey : LibraryPrintProfile.studentKey }
    var body: some View {
        Form {
            Section("Ölçü profili") {
                Picker("Çıktı", selection: $kind) { Text("Kitap etiketi").tag(0); Text("Öğrenci kartı").tag(1) }
                    .onChange(of: kind) { profile = LibraryPrintProfile.load(key); sampleURL = nil }
                Stepper("Kenar payı: \(profile.marginMM.formatted()) mm", value: $profile.marginMM, in: 4...24, step: 1)
                Stepper("Yatay kaydırma: \(profile.offsetXMM.formatted()) mm", value: $profile.offsetXMM, in: -profile.maximumOffsetMM...profile.maximumOffsetMM, step: 0.5)
                Stepper("Dikey kaydırma: \(profile.offsetYMM.formatted()) mm", value: $profile.offsetYMM, in: -profile.maximumOffsetMM...profile.maximumOffsetMM, step: 0.5)
                Text("Kaydırma sınırı kenar payına göre ±\(profile.maximumOffsetMM.formatted()) mm'dir; sayfa kenarında en az 2 mm kalır.")
                    .font(.footnote).foregroundStyle(.secondary)
                if kind == 1 {
                    Toggle("Tam adı göster", isOn: $profile.showStudentName)
                    Toggle("Sınıfı göster", isOn: $profile.showStudentClass)
                    Toggle("Okul numarasını göster", isOn: $profile.showStudentNumber)
                }
                Button("Profili kaydet") { LibraryPrintProfile.save(profile, key: key) }
            }
            Section("Prova") {
                Text("A4, %100 gerçek boyutta yazdırın. Cetvel çizgisini 100 mm ölçün; taşma ve barkod/QR okumasını telefonla kontrol edin.")
                Button("Kişisel veri içermeyen prova PDF'i hazırla") {
                    let id = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
                    var proof = profile
                    proof.calibration = true
                    let data = kind == 0
                        ? SpineLabelBuilder.build([.init(callNumber: "813 / YAZ", title: "Uzun Başlıklı Türkçe Örnek Kitap — Ş, Ğ, İ, Ö, Ü, Ç", accessionCode: "DEMO-0001", barcodeValue: "KBDEMO0001", bookID: id)], profile: proof)
                        : StudentCardBuilder.build([.init(name: "Örnek Öğrenci Adı", className: "7/A", number: "101", barcodeValue: "OGRID" + id.uuidString.replacingOccurrences(of: "-", with: ""))], profile: proof)
                    sampleURL = GeciciDosya.yaz(data, ad: "Baski-Prova.pdf")
                }
                if let sampleURL { ShareLink(item: sampleURL) { Label("Prova PDF'ini paylaş / yazdır", systemImage: "printer") } }
            }
        }.navigationTitle("Baskı Profilleri")
            .onChange(of: profile) { _, _ in
                profile = profile.normalized
                sampleURL = nil
            }
    }
}
