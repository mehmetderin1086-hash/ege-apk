import KagitKit
import SwiftUI

/// Tarama sonrası düzenleme: sayfa şeridi, filtreler, döndürme, kırpma, kaydetme.
struct TaramaDuzenleyici: View {
    @Bindable var model: TaramaModeli
    let kameraAc: (UUID?) -> Void
    let fotoSec: () -> Void
    let bitti: () -> Void

    @State private var kirpilan: UUID?
    @State private var kaydetAcik = false

    private var sayfa: TaramaSayfasi? { model.sayfalar.first { $0.id == model.secili } ?? model.sayfalar.first }

    var body: some View {
        VStack(spacing: 0) {
            onizleme
            sayfaSeridi
            filtreCubugu
            islemCubugu
        }
        .background(Color(.systemGroupedBackground))
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Kaydet…") { kaydetAcik = true }.disabled(model.sayfalar.isEmpty)
            }
        }
        .sheet(item: Binding(get: { kirpilan.map { KirpmaIstegi(id: $0) } }, set: { kirpilan = $0?.id })) { istek in
            KirpmaGorunumu(model: model, sayfaID: istek.id)
        }
        .sheet(isPresented: $kaydetAcik) {
            TaramaKayitFormu(model: model, bitti: bitti)
        }
    }

    // MARK: - Önizleme

    private var onizleme: some View {
        ZStack {
            Color(.secondarySystemGroupedBackground)
            if let s = sayfa {
                Image(decorative: s.onizleme ?? s.kucuk, scale: 1)
                    .resizable().scaledToFit()
                    .shadow(radius: 3)
                    .padding(12)
                    .id(s.id)
                if s.onizleme == nil { ProgressView() }
            }
        }
        .frame(maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            if let i = model.seciliIndeks {
                Text("\(i + 1) / \(model.sayfalar.count)")
                    .font(.caption.bold()).padding(.horizontal, 10).padding(.vertical, 4)
                    .background(.regularMaterial, in: Capsule()).padding(10)
            }
        }
    }

    // MARK: - Sayfa şeridi

    private var sayfaSeridi: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(model.sayfalar.enumerated()), id: \.element.id) { sira, s in
                    kucukResim(s, sira: sira)
                }
                Menu {
                    Button { kameraAc(nil) } label: { Label("Kamerayla tara", systemImage: "camera") }
                    Button { fotoSec() } label: { Label("Fotoğraflardan ekle", systemImage: "photo.on.rectangle") }
                } label: {
                    Image(systemName: "plus").font(.title3)
                        .frame(width: 52, height: 72)
                        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .frame(height: 92)
        .background(.bar)
    }

    private func kucukResim(_ s: TaramaSayfasi, sira: Int) -> some View {
        let secili = s.id == model.secili
        return Image(decorative: s.onizleme ?? s.kucuk, scale: 1)
            .resizable().scaledToFit()
            .frame(width: 52, height: 72)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(secili ? Tema.vurgu : Color.secondary.opacity(0.3), lineWidth: secili ? 2.5 : 1))
            .overlay(alignment: .bottomTrailing) {
                Text("\(sira + 1)").font(.caption2.bold()).padding(3)
                    .background(.regularMaterial, in: Circle()).padding(2)
            }
            .onTapGesture { model.secili = s.id }
            .draggable(s.id.uuidString)
            .dropDestination(for: String.self) { ogeler, _ in
                guard let k = ogeler.first, let id = UUID(uuidString: k) else { return false }
                model.tasi(id, hedef: s.id)
                return true
            }
            .contextMenu {
                Button { kameraAc(s.id) } label: { Label("Yeniden tara", systemImage: "camera.viewfinder") }
                Button { model.kaydir(s.id, adim: -1) } label: { Label("Sola taşı", systemImage: "arrow.left") }
                    .disabled(sira == 0)
                Button { model.kaydir(s.id, adim: 1) } label: { Label("Sağa taşı", systemImage: "arrow.right") }
                    .disabled(sira == model.sayfalar.count - 1)
                Button(role: .destructive) { model.sil(s.id) } label: { Label("Sil", systemImage: "trash") }
            }
            .accessibilityLabel("Sayfa \(sira + 1)")
    }

    // MARK: - Filtreler

    private var filtreCubugu: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TaramaFiltresi.allCases) { f in
                    let secili = sayfa?.filtre == f
                    Button {
                        if let id = sayfa?.id { model.guncelle(id) { $0.filtre = f } }
                    } label: {
                        Text(f.ad).font(.subheadline.weight(secili ? .semibold : .regular))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(secili ? Tema.vurgu : Color(.tertiarySystemFill), in: Capsule())
                            .foregroundStyle(secili ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
                Divider().frame(height: 22)
                Toggle(isOn: Binding(get: { sayfa?.golgeTemizle ?? false },
                                     set: { v in if let id = sayfa?.id { model.guncelle(id) { $0.golgeTemizle = v } } })) {
                    Text("Gölgeyi temizle").font(.subheadline)
                }
                .toggleStyle(.button)
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .background(.bar)
    }

    // MARK: - İşlemler

    private var islemCubugu: some View {
        HStack {
            eylem("rotate.left", "Sola döndür") { if let id = sayfa?.id { model.dondur(id, saatYonunde: false) } }
            Spacer()
            eylem("rotate.right", "Sağa döndür") { if let id = sayfa?.id { model.dondur(id) } }
            Spacer()
            eylem("crop", "Kırp") { kirpilan = sayfa?.id }
            Spacer()
            eylem("camera.viewfinder", "Yeniden tara") { kameraAc(sayfa?.id) }
                .disabled(!BelgeKamerasi.desteklenir)
            Spacer()
            eylem("square.on.square", "Filtreyi tümüne uygula") { if let id = sayfa?.id { model.filtreyiHepsineUygula(id) } }
                .disabled(model.sayfalar.count < 2)
            Spacer()
            eylem("trash", "Sil", rol: .destructive) { if let id = sayfa?.id { model.sil(id) } }
        }
        .padding(.horizontal, 24).padding(.vertical, 10)
        .background(.bar)
    }

    private func eylem(_ simge: String, _ ad: String, rol: ButtonRole? = nil, _ yap: @escaping () -> Void) -> some View {
        Button(role: rol, action: yap) {
            Image(systemName: simge).font(.title3).frame(width: 36, height: 36)
        }
        .accessibilityLabel(ad)
    }
}

private struct KirpmaIstegi: Identifiable { let id: UUID }
