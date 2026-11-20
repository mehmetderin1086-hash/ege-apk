import KagitKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Ayarlar sekmesindeki “Öğretmen” bölümü: sınıf listeleri, okul başlığı, hazır yorumlar.
struct OgretmenAyarlari: View {
    private let depo = OgretmenDeposu.paylasilan

    var body: some View {
        Section("Öğretmen") {
            NavigationLink { SinifYonetimi() } label: {
                LabeledContent("Sınıf listeleri", value: "\(depo.siniflar.count)")
            }
            NavigationLink { OkulBasligiAyari() } label: { Text("Okul başlığı şablonu") }
            NavigationLink { HazirYorumAyari() } label: {
                LabeledContent("Hazır yorumlar", value: "\(depo.yorumlar.count)")
            }
        }
    }
}

// MARK: - Sınıflar

struct SinifYonetimi: View {
    @State private var depo = OgretmenDeposu.paylasilan
    @State private var yeniAd = ""
    @State private var ekle = false

    var body: some View {
        List {
            ForEach(depo.siniflar) { s in
                NavigationLink { SinifDetayi(sinifId: s.id) } label: {
                    LabeledContent(s.ad, value: "\(s.ogrenciler.count) öğrenci")
                }
            }
            .onDelete { depo.siniflar.remove(atOffsets: $0) }
        }
        .overlay {
            if depo.siniflar.isEmpty {
                ContentUnavailableView("Sınıf yok", systemImage: "person.3", description: Text("Sağ üstten sınıf ekleyin; sonra öğrenci listesini yapıştırın ya da CSV/XLSX/PDF olarak içe aktarın."))
            }
        }
        .navigationTitle("Sınıf listeleri")
        .toolbar { Button { ekle = true } label: { Image(systemName: "plus") } }
        .alert("Yeni sınıf", isPresented: $ekle) {
            TextField("Örn. 9-A", text: $yeniAd)
            Button("Ekle") {
                let ad = yeniAd.trimmingCharacters(in: .whitespaces)
                if !ad.isEmpty { depo.siniflar.append(Sinif(ad: ad)) }
                yeniAd = ""
            }
            Button("Vazgeç", role: .cancel) { yeniAd = "" }
        }
    }
}

struct SinifDetayi: View {
    let sinifId: UUID
    @State private var depo = OgretmenDeposu.paylasilan
    @State private var yapistirAcik = false
    @State private var dosyaAcik = false
    @State private var ileti: Ileti?
    @State private var ogrenciEkle = false
    @State private var yeniNo = ""
    @State private var yeniAd = ""

    private var indeks: Int? { depo.siniflar.firstIndex { $0.id == sinifId } }

    var body: some View {
        Group {
            if let i = indeks {
                List {
                    Section {
                        TextField("Sınıf adı", text: $depo.siniflar[i].ad)
                    }
                    Section("\(depo.siniflar[i].ogrenciler.count) öğrenci") {
                        ForEach(depo.siniflar[i].ogrenciler) { o in
                            HStack {
                                Text(o.no).font(.callout.monospacedDigit()).foregroundStyle(.secondary).frame(width: 52, alignment: .leading)
                                Text(o.ad)
                            }
                        }
                        .onDelete { depo.siniflar[i].ogrenciler.remove(atOffsets: $0) }
                    }
                }
                .toolbar {
                    Menu {
                        Button { yapistirAcik = true } label: { Label("Metin yapıştır", systemImage: "doc.on.clipboard") }
                        Button { dosyaAcik = true } label: { Label("CSV / XLSX / PDF içe aktar", systemImage: "square.and.arrow.down") }
                        Button { ogrenciEkle = true } label: { Label("Öğrenci ekle", systemImage: "person.badge.plus") }
                    } label: { Image(systemName: "plus") }
                }
            } else {
                ContentUnavailableView("Sınıf bulunamadı", systemImage: "person.3")
            }
        }
        .navigationTitle("Sınıf")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $yapistirAcik) { YapistirmaSayfasi { metin in ekleListe(SinifAyristirici.metin(metin)) } }
        .fileImporter(isPresented: $dosyaAcik, allowedContentTypes: [.commaSeparatedText, .plainText, .pdf,
                                                                      UTType(filenameExtension: "xlsx") ?? .data]) { sonuc in
            guard case .success(let u) = sonuc else { return }
            Task {
                let e = u.startAccessingSecurityScopedResource()
                defer { if e { u.stopAccessingSecurityScopedResource() } }
                guard let v = try? Data(contentsOf: u) else { ileti = Ileti(KagitHata.acilamadi(u.lastPathComponent)); return }
                ekleListe(await SinifAyristirici.dosya(v, uzanti: u.pathExtension))
            }
        }
        .alert("Öğrenci ekle", isPresented: $ogrenciEkle) {
            TextField("Numara", text: $yeniNo).keyboardType(.numberPad)
            TextField("Ad Soyad", text: $yeniAd)
            Button("Ekle") {
                if !yeniAd.isEmpty { ekleListe([Ogrenci(no: yeniNo, ad: yeniAd)]) }
                yeniNo = ""; yeniAd = ""
            }
            Button("Vazgeç", role: .cancel) { yeniNo = ""; yeniAd = "" }
        }
        .iletiGoster($ileti)
    }

    private func ekleListe(_ yeni: [Ogrenci]) {
        guard let i = indeks else { return }
        guard !yeni.isEmpty else {
            ileti = Ileti(baslik: "Öğrenci bulunamadı", metin: "Satırlar “123 Ad Soyad” biçiminde olmalı.")
            return
        }
        var mevcut = depo.siniflar[i].ogrenciler
        let numaralar = Set(mevcut.map(\.no).filter { !$0.isEmpty })
        mevcut += yeni.filter { $0.no.isEmpty || !numaralar.contains($0.no) }
        depo.siniflar[i].ogrenciler = mevcut.sorted { (Int($0.no) ?? .max) < (Int($1.no) ?? .max) }
        ileti = Ileti(baslik: "İçe aktarıldı", metin: "\(yeni.count) öğrenci işlendi.", hata: false)
    }
}

struct YapistirmaSayfasi: View {
    let tamam: (String) -> Void
    @Environment(\.dismiss) private var kapat
    @State private var metin = ""

    var body: some View {
        NavigationStack {
            TextEditor(text: $metin)
                .font(.body.monospaced())
                .padding(8)
                .overlay(alignment: .topLeading) {
                    if metin.isEmpty {
                        Text("Her satıra bir öğrenci:\n123 Ayşe Yılmaz\n124 Mehmet Demir").foregroundStyle(.tertiary).padding(14).allowsHitTesting(false)
                    }
                }
                .navigationTitle("Listeyi yapıştır")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { kapat() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Aktar") { tamam(metin); kapat() }.disabled(metin.isEmpty) }
                    ToolbarItem(placement: .bottomBar) {
                        Button("Panodan yapıştır") { metin = UIPasteboard.general.string ?? metin }
                    }
                }
        }
    }
}

// MARK: - Okul başlığı

struct OkulBasligiAyari: View {
    @State private var depo = OgretmenDeposu.paylasilan
    @State private var foto: PhotosPickerItem?

    var body: some View {
        Form {
            Section("Bilgiler") {
                BaslikAlani(ad: "Okul adı", metin: $depo.baslik.okulAdi)
                BaslikAlani(ad: "Ders", metin: $depo.baslik.ders)
                BaslikAlani(ad: "Öğretmen", metin: $depo.baslik.ogretmen)
                BaslikAlani(ad: "Eğitim-öğretim yılı", metin: $depo.baslik.egitimYili)
            }
            Section("Logo (isteğe bağlı)") {
                if let v = depo.baslik.logo, let g = UIImage(data: v) {
                    Image(uiImage: g).resizable().scaledToFit().frame(height: 60)
                    Button("Logoyu kaldır", role: .destructive) { depo.baslik.logo = nil }
                }
                PhotosPicker(selection: $foto, matching: .images) { Text(depo.baslik.logo == nil ? "Logo seç" : "Logoyu değiştir") }
            }
            Section("Önizleme") {
                BaslikOnizleme(baslik: depo.baslik).frame(height: 110)
            }
        }
        .navigationTitle("Okul başlığı")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: foto) { _, y in
            guard let y else { return }
            Task {
                if let v = try? await y.loadTransferable(type: Data.self), let g = UIImage(data: v)?.jpegData(compressionQuality: 0.85) {
                    depo.baslik.logo = g
                }
            }
        }
    }
}

/// Başlığın PDF olarak çizilmiş önizlemesi.
struct BaslikOnizleme: View {
    let baslik: OkulBasligi
    var sinavAdi = "1. Dönem 1. Yazılı"
    @State private var resim: UIImage?

    var body: some View {
        Group {
            if let resim { Image(uiImage: resim).resizable().scaledToFit() } else { ProgressView() }
        }
        .task(id: baslik) {
            let b = baslik, ad = sinavAdi
            let v = await Task.detached { () -> Data in
                let w: CGFloat = 520
                let y = PDFCizim.Yazici()
                y.sayfa(CGRect(x: 0, y: 0, width: w, height: 110)) { ctx in
                    ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: 110))
                    b.ciz(ctx, ustSol: CGPoint(x: 12, y: 108), genislik: w - 24, sinavAdi: ad, kitapcik: nil)
                }
                return y.bitir()
            }.value
            if let belge = PDFDocumentSarmal.ilkSayfaGoruntusu(v, dpi: 150) { resim = belge }
        }
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

import PDFKit

enum PDFDocumentSarmal {
    static func ilkSayfaGoruntusu(_ veri: Data, dpi: CGFloat) -> UIImage? {
        guard let b = PDFDocument(data: veri), let s = b.page(at: 0), let g = PDFCizim.goruntu(s, dpi: dpi) else { return nil }
        return UIImage(cgImage: g)
    }
}

struct HazirYorumAyari: View {
    @State private var depo = OgretmenDeposu.paylasilan
    @State private var yeni = ""

    var body: some View {
        List {
            Section {
                ForEach(depo.yorumlar, id: \.self) { Text($0) }
                    .onDelete { depo.yorumlar.remove(atOffsets: $0) }
                    .onMove { depo.yorumlar.move(fromOffsets: $0, toOffset: $1) }
            } footer: { Text("Bu yorumlar sınav kâğıdında Öğretmen kipinde damga olarak yerleştirilir.") }
            Section {
                HStack {
                    TextField("Yeni yorum", text: $yeni).onSubmit(ekle)
                    Button("Ekle", action: ekle).disabled(yeni.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Button("Varsayılanlara dön") { depo.yorumlar = HazirYorumlar.varsayilan }
            }
        }
        .navigationTitle("Hazır yorumlar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
    }

    private func ekle() {
        let t = yeni.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        depo.yorumlar.append(t)
        yeni = ""
    }
}
