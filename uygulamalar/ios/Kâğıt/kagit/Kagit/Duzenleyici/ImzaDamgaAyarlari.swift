import KagitKit
import SwiftUI

/// Ayarlar: kayıtlı imzalar ve özel damgalar.
struct ImzaDamgaAyarlari: View {
    var body: some View {
        Section("İmzalar ve damgalar") {
            NavigationLink {
                ImzaYonetimi()
            } label: {
                Label("Kayıtlı imzalar ve baş harfler", systemImage: "signature")
            }
            NavigationLink {
                DamgaYonetimi()
            } label: {
                Label("Özel damgalar", systemImage: "seal")
            }
        }
    }
}

private struct ImzaYonetimi: View {
    @State private var depo = ImzaDeposu.paylasilan
    @State private var cizimAcik = false
    @State private var adDegisecek: KayitliImza?
    @State private var yeniAd = ""

    var body: some View {
        List {
            if depo.imzalar.isEmpty {
                ContentUnavailableView("Kayıtlı imza yok", systemImage: "signature",
                                       description: Text("Yeni bir imza ya da baş harf çizerek başla."))
            }
            ForEach(depo.imzalar) { i in
                HStack(spacing: 12) {
                    if let v = depo.png(i), let r = UIImage(data: v) {
                        Image(uiImage: r).resizable().scaledToFit().frame(width: 90, height: 44)
                            .padding(4).background(Color.white, in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.secondary.opacity(0.3)))
                    }
                    VStack(alignment: .leading) {
                        Text(i.ad)
                        Text(i.basHarf ? "Baş harf" : "İmza").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .swipeActions {
                    Button("Sil", role: .destructive) { depo.sil(i) }
                    Button("Adlandır") { adDegisecek = i; yeniAd = i.ad }.tint(.blue)
                }
            }
        }
        .navigationTitle("İmzalar")
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button { cizimAcik = true } label: { Image(systemName: "plus") } }
        }
        .sheet(isPresented: $cizimAcik) { ImzaCizimSayfasi() }
        .alert("İmzayı adlandır", isPresented: Binding(get: { adDegisecek != nil }, set: { if !$0 { adDegisecek = nil } })) {
            TextField("Ad", text: $yeniAd)
            Button("Kaydet") { if let i = adDegisecek { depo.adDegistir(i, yeniAd) } }
            Button("Vazgeç", role: .cancel) {}
        }
    }
}

private struct DamgaYonetimi: View {
    @State private var depo = DamgaDeposu.paylasilan
    @State private var yeniAcik = false

    var body: some View {
        List {
            Section {
                ForEach(depo.ozel) { t in
                    DamgaOnizleme(tanim: t).frame(height: 48).frame(maxWidth: .infinity)
                        .swipeActions { Button("Sil", role: .destructive) { depo.sil(t) } }
                }
                if depo.ozel.isEmpty { Text("Henüz özel damga yok.").foregroundStyle(.secondary) }
            } footer: {
                Text("Hazır damgalar (ONAYLANDI, TASLAK, GİZLİ, ÖRNEK, CEVAP ANAHTARI, İNCELENDİ) her zaman kullanılabilir.")
            }
        }
        .navigationTitle("Özel damgalar")
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button { yeniAcik = true } label: { Image(systemName: "plus") } }
        }
        .sheet(isPresented: $yeniAcik) { OzelDamgaSayfasi() }
    }
}
