import KagitKit
import SwiftUI

/// Öğretmen sekmesi: sınıflar, hızlı eylemler, son notlandırılanlar.
struct OgretmenMerkezi: View {
    @Environment(Yonlendirici.self) private var yon
    @Environment(Kitaplik.self) private var kitaplik
    @State private var depo = OgretmenDeposu.paylasilan

    private let eylemler: [(ad: String, simge: String, id: String?)] = [
        ("Yığını böl", "rectangle.stack.badge.person.crop", "yiginiBol"),
        ("Kitapçık oluştur", "books.vertical", "kitapcikOlustur"),
        ("Soru üret", "sparkles.rectangle.stack", "soruUret"),
        ("Puan tablosu", "tablecells", "puanTablosu"),
        ("Başlık ekle", "text.badge.plus", "basligiEkle"),
        ("Sınav tara", "doc.viewfinder", nil),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section("Hızlı eylemler") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
                        ForEach(eylemler, id: \.ad) { e in
                            Button { calistir(e.id) } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: e.simge).font(.title2).foregroundStyle(.white)
                                        .frame(width: 44, height: 44).background(Color.purple.gradient, in: RoundedRectangle(cornerRadius: 11))
                                    Text(e.ad).font(.caption.weight(.medium)).multilineTextAlignment(.center).lineLimit(2, reservesSpace: true)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
                }

                Section {
                    ForEach(depo.siniflar) { s in
                        NavigationLink { SinifDetayi(sinifId: s.id) } label: {
                            LabeledContent(s.ad, value: "\(s.ogrenciler.count) öğrenci")
                        }
                    }
                    NavigationLink { SinifYonetimi() } label: { Label("Sınıfları yönet", systemImage: "person.3") }
                } header: { Text("Sınıflar") }

                let son = depo.sonNotlandirilan.compactMap { kitaplik.oge(yol: $0) }
                if !son.isEmpty {
                    Section("Son notlandırılanlar") {
                        ForEach(son) { o in
                            Button { yon.ac(o, kip: .ogretmen) } label: {
                                HStack {
                                    KucukResimGorunumu(oge: o, boyut: 34)
                                    VStack(alignment: .leading) {
                                        Text(o.ad).lineLimit(1)
                                        Text(o.degistirilme.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Öğretmen")
        }
    }

    private func calistir(_ id: String?) {
        if let id { yon.aracAc(id: id) } else { yon.taramaAcik = true }
    }
}
