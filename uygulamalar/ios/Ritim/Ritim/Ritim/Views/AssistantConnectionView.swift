import SwiftUI

struct AssistantConnectionView: View {
    @EnvironmentObject private var assistant: AIAssistantStore
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var token = ""
    @State private var authentication = "Authorization"
    @State private var error: String?
    @State private var checking = false
    @State private var connected = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Doğrudan iPhone bağlantısı", systemImage: "iphone.radiowaves.left.and.right")
                        .foregroundStyle(RitimTheme.mint)
                    Text("Asistan iPhone’dan CLIProxy’ye internet üzerinden bağlanır. Mac’in açık olması gerekmez.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Section("CLIProxy bağlantısı") {
                    TextField("https://sunucun/v1", text: $address)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        .accessibilityLabel("Asistan HTTPS adresi").accessibilityIdentifier("ai.connection.url")
                    Picker("Erişim biçimi", selection: $authentication) {
                        Text("Bearer anahtarı").tag("Authorization")
                        Text("Kişisel geçit anahtarı").tag("X-Personal-Token")
                    }
                    SecureField(assistant.hasAccessToken ? "Kayıtlı anahtarı değiştirmek için gir" : "Erişim anahtarı", text: $token)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("ai.connection.token")
                    if assistant.hasAccessToken {
                        Label("Anahtar iPhone’un güvenli alanında kayıtlı", systemImage: "lock.shield")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Button {
                        Task { await saveAndCheck() }
                    } label: {
                        HStack {
                            Text(checking ? "Bağlantı sınanıyor…" : "Kaydet ve bağlantıyı sına")
                            Spacer()
                            if checking { ProgressView() }
                        }
                    }.disabled(checking || address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("ai.connection.check")
                    if connected {
                        Label("Bağlı · \(assistant.models.count) model", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(RitimTheme.mint).accessibilityIdentifier("ai.connection.success")
                    }
                    if let error { Text(error).foregroundStyle(.orange).font(.subheadline) }
                } footer: {
                    Text("Parça bilgileri ve mesajların seçtiğin modele gönderilir. Ses ve video dosyaları gönderilmez. Asistan için internet gerekir; indirilmiş müzik ve videolar çevrimdışı oynar.")
                }
            }
            .navigationTitle("Asistan bağlantısı").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } } }
            .onAppear {
                address = assistant.connection.baseURL
                authentication = assistant.connection.authHeader
            }
        }.preferredColorScheme(.dark)
    }

    @MainActor
    private func saveAndCheck() async {
        checking = true; connected = false; error = nil
        defer { checking = false }
        do {
            var connection = assistant.connection
            connection.baseURL = address.trimmingCharacters(in: .whitespacesAndNewlines)
            connection.authHeader = authentication
            connection.authScheme = authentication == "Authorization" ? "Bearer" : ""
            if connection.credentialAccount != assistant.connection.credentialAccount {
                connection.models = []
                connection.defaultModelID = nil
            }
            try assistant.updateConnection(connection, token: token.isEmpty ? nil : token)
            token = ""
            await assistant.loadModels()
            connected = !assistant.models.isEmpty
            if !connected { error = assistant.errorMessage ?? "Bu bağlantıda kullanılabilir model bulunamadı." }
        } catch { self.error = error.localizedDescription }
    }
}
