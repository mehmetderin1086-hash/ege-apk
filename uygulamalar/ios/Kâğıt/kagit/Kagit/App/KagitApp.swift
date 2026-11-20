import KagitKit
import SwiftUI

@main
struct KagitApp: App {
    @State private var kitaplik = Kitaplik.paylasilan
    @State private var ayarlar = Ayarlar.paylasilan
    @State private var yon = Yonlendirici()
    @Environment(\.scenePhase) private var evre

    var body: some Scene {
        WindowGroup {
            AnaGorunum()
                .onOpenURL { url in
                    Task { await yon.disaridanAc(url, kitaplik: kitaplik) }
                }
                .task {
                    Gizli.ilkAcilisAktarimi()
                    Gecici.temizle()
                    await kitaplik.tara()
                    await kitaplik.paylasimGelenleriniAl()
                }
                .onChange(of: evre) { _, yeni in
                    if yeni == .active {
                        Task {
                            await kitaplik.tara()
                            await kitaplik.paylasimGelenleriniAl()
                        }
                    }
                }
                .sistemKurulumu(kitaplik: kitaplik, yon: yon)
                .kilitKatmani()
                .tint(Tema.vurgu)
                // En dışta: kilit katmanı ve sistem kurulumu da bu nesneleri okuyabilsin.
                .environment(kitaplik)
                .environment(ayarlar)
                .environment(yon)
        }
    }
}
