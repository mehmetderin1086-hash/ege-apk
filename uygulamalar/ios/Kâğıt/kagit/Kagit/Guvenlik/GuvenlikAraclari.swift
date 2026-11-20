import KagitKit
import SwiftUI

// MARK: - Parola koy

struct ParolaKoyEkrani: View {
    static let arac = Arac(id: "parolaKoy", ad: "Parola koy",
                           aciklama: "PDF'i parolayla koru; yazdırma, kopyalama ve değiştirmeyi kısıtla.",
                           simge: "lock.doc", kategori: .guvenlik, girdi: .birVeyaCokPDF, topluUygun: true) {
        ParolaKoyEkrani(baglam: $0)
    }

    let baglam: AracBaglami
    @State private var kullanici = ""
    @State private var tekrar = ""
    @State private var sahip = ""
    @State private var mevcut = ""
    @State private var yazdirma = true
    @State private var kopyalama = true
    @State private var degistirme = true
    @State private var aciklama = true
    @State private var form = true
    @State private var birlestirme = true

    private var izinler: Izinler {
        var i: Izinler = [.erisilebilirlik]
        if yazdirma { i.formUnion([.yazdirma, .yuksekKaliteYazdirma]) }
        if kopyalama { i.insert(.kopyalama) }
        if degistirme { i.insert(.degistirme) }
        if aciklama { i.insert(.aciklama) }
        if form { i.insert(.formDoldurma) }
        if birlestirme { i.insert(.sayfaBirlestirme) }
        return i
    }

    private var eslesiyor: Bool { kullanici == tekrar }

    private var hazir: Bool {
        guard eslesiyor else { return false }
        if izinler != .hepsi && sahip.isEmpty { return false }
        return !kullanici.isEmpty || !sahip.isEmpty
    }

    var body: some View {
        AracSablonu(arac: Self.arac, girdiler: baglam.girdiler, hazir: hazir) {
            Section {
                SecureField("Açılış parolası", text: $kullanici)
                SecureField("Parolayı tekrarla", text: $tekrar)
                if !tekrar.isEmpty && !eslesiyor {
                    Text("Parolalar aynı değil.").font(.footnote).foregroundStyle(.red)
                }
            } header: {
                Text("Açılış parolası")
            } footer: {
                Text("Belge açılırken sorulur. Boş bırakırsan belge serbest açılır, yalnız aşağıdaki izinler kısıtlanır. Parolayı unutursan belgeye erişemezsin.")
            }
            Section {
                SecureField("Sahip parolası", text: $sahip)
                Toggle("Yazdırma", isOn: $yazdirma)
                Toggle("Metni kopyalama", isOn: $kopyalama)
                Toggle("Değiştirme", isOn: $degistirme)
                Toggle("Açıklama ekleme", isOn: $aciklama)
                Toggle("Form doldurma", isOn: $form)
                Toggle("Sayfa ekleme / silme", isOn: $birlestirme)
            } header: {
                Text("Sahip parolası ve izinler")
            } footer: {
                if izinler != .hepsi && sahip.isEmpty {
                    Text("İzinleri kısıtlamak için sahip parolası gerekir.").foregroundStyle(.red)
                } else {
                    Text("Sahip parolasını bilen izinlere bakmadan her şeyi yapabilir.")
                }
            }
            Section("Dosya zaten parolalıysa") {
                SecureField("Mevcut parola", text: $mevcut)
            }
        } calistir: { girdiler, ilerleme in
            let k = kullanici.isEmpty ? nil : kullanici
            let s = sahip.isEmpty ? nil : sahip
            let m = mevcut.isEmpty ? nil : mevcut
            let iz = izinler
            var cikti: [URL] = []
            for (i, u) in girdiler.enumerated() {
                cikti.append(try await arkaplandaCalistir {
                    let veri = try Data(contentsOf: u)
                    let r = try Koruma.parolaKoy(veri: veri, kaynakParola: m, kullaniciParolasi: k,
                                                 sahipParolasi: s, izinler: iz)
                    let h = Gecici.dosya("\(u.adSiz) (korumalı).pdf")
                    try Belge.yaz(r, h, parola: k)
                    return h
                })
                ilerleme(Double(i + 1) / Double(girdiler.count))
            }
            return cikti
        }
    }
}

// MARK: - Parola kaldır

struct ParolaKaldirEkrani: View {
    static let arac = Arac(id: "parolaKaldir", ad: "Parolayı kaldır",
                           aciklama: "Parolayı sorup korumasız bir kopya üretir.",
                           simge: "lock.open", kategori: .guvenlik, girdi: .birVeyaCokPDF, topluUygun: true) {
        ParolaKaldirEkrani(baglam: $0)
    }

    let baglam: AracBaglami
    @State private var parola = ""

    var body: some View {
        AracSablonu(arac: Self.arac, girdiler: baglam.girdiler) {
            Section {
                SecureField("Parola", text: $parola)
            } header: {
                Text("Parola")
            } footer: {
                Text("Açılış ya da sahip parolası. Birden çok dosya seçtiysen hepsi için aynı parola denenir. Özgün dosya değişmez, korumasız bir kopya eklenir.")
            }
        } calistir: { girdiler, ilerleme in
            let p = parola.isEmpty ? nil : parola
            var cikti: [URL] = []
            for (i, u) in girdiler.enumerated() {
                cikti.append(try await arkaplandaCalistir {
                    let veri = try Data(contentsOf: u)
                    let r = try Koruma.parolaKaldir(veri: veri, parola: p)
                    let h = Gecici.dosya("\(u.adSiz) (parolasız).pdf")
                    try Belge.yaz(r, h)
                    return h
                })
                ilerleme(Double(i + 1) / Double(girdiler.count))
            }
            return cikti
        }
    }
}

// MARK: - Üst veri

struct UstVeriEkrani: View {
    static let arac = Arac(id: "ustVeri", ad: "Üst veri",
                           aciklama: "Başlık, yazar, konu ve anahtar sözcükleri düzenle ya da hepsini temizle.",
                           simge: "tag", kategori: .guvenlik, girdi: .tekPDF) {
        UstVeriEkrani(baglam: $0)
    }

    let baglam: AracBaglami
    @State private var baslik = ""
    @State private var yazar = ""
    @State private var konu = ""
    @State private var anahtar = ""
    @State private var temizle = false
    @State private var parola = ""
    @State private var xmpVar = false
    @State private var bilgi: String?
    @State private var okumaHatasi: String?

    var body: some View {
        AracSablonu(arac: Self.arac, girdiler: baglam.girdiler) {
            Section {
                SecureField("Parola (dosya parolalıysa)", text: $parola)
                    .onSubmit { Task { await oku() } }
                if let okumaHatasi {
                    Text(okumaHatasi).font(.footnote).foregroundStyle(.red)
                    Button("Üst veriyi oku") { Task { await oku() } }
                }
            }
            Section {
                TextField("Başlık", text: $baslik)
                TextField("Yazar", text: $yazar)
                TextField("Konu", text: $konu)
                TextField("Anahtar sözcükler (virgülle)", text: $anahtar)
            } header: {
                Text("Alanlar")
            } footer: {
                if xmpVar { Text("Belgede ayrıca XMP üst verisi var; kaydederken eski XMP temizlenir, yoksa eski değerleri taşırdı.") }
            }
            .disabled(temizle)
            Section {
                Toggle("Hepsini temizle", isOn: $temizle)
            } footer: {
                Text("Başlık, yazar, konu, anahtar sözcükler, oluşturan uygulama ve XMP üst verisi silinir.")
            }
            if let bilgi {
                Section("Sonuç") { Text(bilgi).font(.footnote) }
            }
        } calistir: { girdiler, _ in
            guard let u = girdiler.first else { return [] }
            let p = parola.isEmpty ? nil : parola
            let hepsi = temizle
            var uv = UstVeri()
            uv.baslik = baslik.trimmingCharacters(in: .whitespaces)
            uv.yazar = yazar.trimmingCharacters(in: .whitespaces)
            uv.konu = konu.trimmingCharacters(in: .whitespaces)
            uv.anahtarSozcukler = anahtar.split(whereSeparator: { ",;".contains($0) })
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let uvKopya = uv
            let sonuc = try await arkaplandaCalistir {
                let veri = try Data(contentsOf: u)
                let (c, rapor) = try hepsi ? UstVeriIslemleri.hepsiniTemizle(veri: veri, parola: p)
                                           : UstVeriIslemleri.yaz(veri: veri, parola: p, ustVeri: uvKopya)
                let h = Gecici.dosya("\(u.adSiz) (\(hepsi ? "temiz" : "üst veri")).pdf")
                try Belge.yaz(c, h, parola: p)
                return (h, rapor.aciklama)
            }
            bilgi = sonuc.1
            return [sonuc.0]
        }
        .task(id: baglam.girdiler.first) { await oku() }
    }

    private func oku() async {
        guard let u = baglam.girdiler.first else { return }
        let p = parola.isEmpty ? nil : parola
        okumaHatasi = nil
        do {
            let (uv, xmp) = try await arkaplandaCalistir {
                let veri = try Data(contentsOf: u)
                return (try UstVeriIslemleri.oku(veri: veri, parola: p), UstVeriIslemleri.xmpVarMi(veri))
            }
            baslik = uv.baslik
            yazar = uv.yazar
            konu = uv.konu
            anahtar = uv.anahtarSozcukler.joined(separator: ", ")
            xmpVar = xmp
        } catch {
            okumaHatasi = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
