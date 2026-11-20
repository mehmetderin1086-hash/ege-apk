import SwiftUI
import ProxyKit

struct DurumView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var m = model
        List {
            Section {
                HStack(spacing: 14) {
                    Circle().fill(statusColor).frame(width: 14, height: 14)
                        .shadow(color: statusColor.opacity(0.6), radius: model.isRunning ? 6 : 0)
                    VStack(alignment: .leading) {
                        Text(statusText).font(.headline)
                        Text("\(model.server.connections) açık bağlantı").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(get: { model.isRunning }, set: { $0 ? model.startServer() : model.stopServer() }))
                        .labelsHidden()
                }
                CopyRow(title: "Bu cihazdan (OpenAI / Anthropic taban adresi)", value: model.localBase)
                if model.lanAccess, let lan = model.lanBase {
                    CopyRow(title: "Aynı Wi-Fi'daki bilgisayardan", value: lan)
                }
                CopyRow(title: "Yerel API anahtarı", value: model.state.localKey, secret: true)
            } header: { Text("Vekil sunucusu") } footer: {
                Text("Sunucudaki CLI Proxy API ile aynı uçlar: /v1/chat/completions, /v1/messages, /v1/responses, /v1/models, Gemini /v1beta. Sunucudan taşınan istemci anahtarları da geçerlidir.")
            }

            Section("Hesaplar") {
                let s = model.state
                LabeledContent("OAuth hesapları", value: "\(s.oauth.filter(\.enabled).count) açık / \(s.oauth.count)")
                LabeledContent("API sağlayıcıları", value: "\(s.apiProviders.filter(\.enabled).count)")
                LabeledContent("İstemci anahtarları", value: "\(s.clientKeys.count + 1)")
                LabeledContent("Yönlendirme kuralları", value: "\(s.routing.count)")
                if let d = s.importedAt { LabeledContent("Sunucudan taşındı", value: d.kisaGoreli) }
            }

            Section {
                LabeledContent("Sunucu bağlantısı", value: model.state.remote.isUsable ? "Açık" : "Kapalı")
                if let d = model.lastSync { LabeledContent("Son eşitleme", value: d.kisaGoreli) }
                Button {
                    Task { await model.syncNow() }
                } label: {
                    HStack { Text("Erişim belirteçlerini sunucudan güncelle"); Spacer(); if model.syncing { ProgressView() } }
                }.disabled(model.state.remote.syncToken.isEmpty || model.syncing)
            } header: { Text("Sunucu") } footer: {
                Text("Antigravity, Gemini Pro hesabı köprüsü, Qwen matematik modeli ve görsel üretim sunucuda çalışmaya devam eder; bu modeller oraya yönlendirilir. Telefondaki bir yol hata verirse istek otomatik olarak sunucuya düşer.")
            }

            Section {
                Toggle("Açılışta başlat", isOn: $m.autoStart)
                Toggle("Wi-Fi ağına aç", isOn: $m.lanAccess)
                Toggle("Arka planda çalışmaya devam et", isOn: $m.keepAwakeInBackground)
                Stepper("Port: \(model.port)", value: $m.port, in: 1024...65000)
                    .onChange(of: model.port) { if model.isRunning { model.startServer() } }
            } header: { Text("Çalışma") } footer: {
                Text("Arka plan seçeneği sessiz ses oturumuyla uygulamayı uyanık tutar; ekran kilitliyken de istek karşılanır ama pil tüketir. Wi-Fi seçeneği açıkken istemciler yine API anahtarı göstermek zorundadır.")
            }

            Section("Bugün") {
                let today = model.records.filter { Calendar.current.isDateInToday($0.date) }
                LabeledContent("İstek", value: "\(today.count)")
                LabeledContent("Telefonda karşılanan", value: "\(today.filter { $0.route != "Sunucu" && $0.status < 400 }.count)")
                LabeledContent("Sunucuya giden", value: "\(today.filter { $0.route == "Sunucu" }.count)")
                LabeledContent("Token (girdi / çıktı)", value: "\(today.reduce(0) { $0 + $1.inputTokens }) / \(today.reduce(0) { $0 + $1.outputTokens })")
            }
        }
        .navigationTitle("CLI Proxy")
        .refreshable { await model.syncNow() }
    }

    var statusColor: Color {
        switch model.serverState {
        case .running: .green
        case .starting: .orange
        case .failed: .red
        case .stopped: .gray
        }
    }

    var statusText: String {
        switch model.serverState {
        case .running(let p): "Çalışıyor · port \(p)"
        case .starting: "Başlatılıyor…"
        case .failed(let e): "Hata: \(e)"
        case .stopped: "Durdu"
        }
    }
}
