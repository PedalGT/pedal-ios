import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var urlText = ""
    @State private var showPhotoTest = false
    @State private var photoTestColor = "black"
    @State private var testResult: TestResult?
    @State private var isTesting = false
    @State private var showLogOutConfirm = false

    private enum TestResult {
        case ok(String)
        case failed(String)
    }

    var body: some View {
        Form {
            Section {
                TextField("http://192.168.1.10:3000", text: $urlText)
                    .keyboardDoneButton()
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: urlText) { _, _ in testResult = nil }

                Button {
                    testConnection()
                } label: {
                    HStack {
                        Text("Test connection")
                        Spacer()
                        if isTesting { ProgressView() }
                    }
                }
                .disabled(isTesting || urlText.trimmingCharacters(in: .whitespaces).isEmpty)

                if let testResult {
                    switch testResult {
                    case .ok(let detail):
                        Label(detail, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Theme.bikeLane)
                            .font(.footnote)
                    case .failed(let detail):
                        Label(detail, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            } header: {
                Text("Server")
            } footer: {
                Text("On a real iPhone use your laptop's address on the shared network, such as http://192.168.1.10:3000. \"localhost\" only works in the Simulator.")
            }

            Section {
                Picker("Bike color", selection: $photoTestColor) {
                    ForEach(BikeColors.all, id: \.self) { Text($0.capitalized).tag($0) }
                }
                Button("Test bike photo check") { showPhotoTest = true }
            } header: {
                Text("Bike photo check")
            } footer: {
                Text("Try the end-of-ride photo check without a ride. Pick the color the bike should be, then take or choose a photo.")
            }
            .sheet(isPresented: $showPhotoTest) {
                BikePhotoCheckView(bikeName: "The test bike", expectedColor: photoTestColor)
            }

            if let user = model.me {
                Section("Account") {
                    LabeledContent("Name", value: user.name)
                    LabeledContent("Email", value: user.email)
                    LabeledContent("GTID", value: user.gtid ?? "Not set")
                    LabeledContent("Keycard", value: user.cardUid ?? "None linked")
                }
            }

            Section("App") {
                LabeledContent("Version", value: Config.appVersion)
            }

            if model.isLoggedIn {
                Section {
                    Button("Log out", role: .destructive) { showLogOutConfirm = true }
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { save(); dismiss() }
            }
        }
        .onAppear { urlText = model.auth.baseURL }
        .onDisappear { save() }
        .confirmationDialog("Log out of Pedal?", isPresented: $showLogOutConfirm, titleVisibility: .visible) {
            Button("Log out", role: .destructive) {
                model.logOut()
                dismiss()
            }
        }
    }

    private func save() {
        let trimmed = urlText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        model.auth.baseURL = trimmed
        urlText = model.auth.baseURL
    }

    private func testConnection() {
        let candidate = AuthStore.normalize(urlText)
        guard URL(string: candidate)?.host != nil else {
            testResult = .failed("That isn't a valid address. Try http://192.168.1.10:3000")
            return
        }
        isTesting = true
        testResult = nil
        Task {
            defer { isTesting = false }
            do {
                let health = try await model.api.health(baseURLOverride: candidate)
                testResult = health.ok
                    ? .ok("Connected to \(health.name ?? "the server").")
                    : .failed("The server answered but reported a problem.")
                save()
            } catch {
                testResult = .failed(error.localizedDescription)
            }
        }
    }
}
