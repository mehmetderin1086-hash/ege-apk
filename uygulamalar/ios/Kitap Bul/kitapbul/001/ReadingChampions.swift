import SwiftUI
import UniformTypeIdentifiers

/// Kimlikli öğrencilerin tamamlandığı bildirilen okumalarını sıralar. Fiziksel iade
/// tek başına okuma değildir; sınıf hareketin tarihsel kaydından alınır.
struct ReadingChampionsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isExportingCertificate = false
    @State private var certificateData = Data()
    @State private var selectedPerson: OkumaPuani.Satir?

    /// Sınıf, öğrencinin güncel kaydından alınır (mezunsa "Mezun"); kayıt bulunamazsa en yeni hareketin sınıfı kalır.
    private var people: [OkumaPuani.Satir] {
        let aktif = Dictionary(StudentStore.all().map { ($0.id, $0.className) }, uniquingKeysWith: { first, _ in first })
        let mezunlar = Set(((try? GraduatedStudentStore.allVerified()) ?? []).map(\.id))
        return OkumaPuani.siralama(LoanHistoryStore.all).map { satir in
            var guncel = satir
            if let id = satir.studentID {
                if let sinif = aktif[id], !sinif.isEmpty { guncel.classSnapshot = sinif }
                else if mezunlar.contains(id) { guncel.classSnapshot = "Mezun" }
            }
            return guncel
        }
    }

    private var classSummaries: [(String, Int)] {
        var totals: [String: Int] = [:]
        for person in people {
            totals[(person.classSnapshot ?? "").isEmpty ? "Sınıf belirtilmemiş" : person.classSnapshot!, default: 0] += person.kitapSayisi
        }
        return totals.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Yalnız kimlikli öğrencilerin tamamlandığı bildirilen kütüphane okumaları sayılır. Tek eser tekrar okunduğunda puan/sayı artmaz. Eski iade kayıtları okuma tamamlandı kabul edilmez.")
                        .font(.subheadline).fixedSize(horizontal: false, vertical: true)
                }
                Section("Sınıf Sıralaması") {
                    if classSummaries.isEmpty {
                        Text("Henüz okuma verisi yok.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(classSummaries.enumerated()), id: \.offset) { index, entry in
                        HStack {
                            medalLabel(index)
                            Text(entry.0).font(.subheadline.weight(.medium))
                            Spacer()
                            Text("\(entry.1) kitap").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Öğrenci Sıralaması (İlk 20)") {
                    ForEach(Array(people.prefix(20).enumerated()), id: \.offset) { index, person in
                        Button {
                            selectedPerson = person
                        } label: {
                            HStack {
                                medalLabel(index)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(person.ad).font(.subheadline.weight(.medium))
                                    Text(person.classSnapshot ?? "Sınıf belirtilmemiş")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(person.kitapSayisi) kitap")
                                    .font(.headline)
                                    .foregroundStyle(KitapTema.ana)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Okuma Şampiyonları")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
            .sheet(item: $selectedPerson) { person in
                CertificateSheet(person: person, className: person.classSnapshot ?? "Sınıf belirtilmemiş")
            }
        }
    }

    @ViewBuilder
    private func medalLabel(_ index: Int) -> some View {
        switch index {
        case 0: Text("🥇")
        case 1: Text("🥈")
        case 2: Text("🥉")
        default: Text("\(index + 1).").font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Seçili öğrenci için başarı sertifikası PDF'i.
private struct CertificateSheet: View {
    @Environment(\.dismiss) private var dismiss
    let person: OkumaPuani.Satir
    let className: String

    @State private var isExporting = false
    @State private var pdfData = Data()

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "medal.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.yellow)
                Text("Okuma Başarı Sertifikası")
                    .font(.title2.weight(.bold))
                Text(person.ad).font(.title3)
                Text(className).foregroundStyle(.secondary)
                Text("\(person.kitapSayisi) kitap okudu")
                    .font(.headline)
                    .foregroundStyle(KitapTema.ana)

                Button {
                    export()
                } label: {
                    Label("Sertifikayı PDF Olarak Kaydet", systemImage: "doc.richtext")
                }
                .buttonStyle(.borderedProminent)
                Spacer()
            }
            .padding()
            .navigationTitle("Sertifika")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
            .fileExporter(
                isPresented: $isExporting,
                document: PDFDocumentFile(data: pdfData),
                contentType: .pdf,
                defaultFilename: "Sertifika-\(person.ad)"
            ) { _ in }
        }
    }

    private func export() {
        pdfData = PDFReportBuilder.build(
            title: "OKUMA BAŞARI SERTİFİKASI",
            subtitle: "Kitap Bul  •  \(Date.now.formatted(date: .long, time: .omitted))",
            sections: [
                PDFReportBuilder.Section(title: "Bu sertifika", rows: [
                    ("Ad Soyad", person.ad),
                    ("Sınıf", className),
                    ("Okunan Kitap Sayısı", "\(person.kitapSayisi)")
                ])
            ]
        )
        isExporting = true
    }
}
