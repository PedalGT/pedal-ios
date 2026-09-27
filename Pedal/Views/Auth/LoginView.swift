import SwiftUI

struct LoginView: View {
    @Environment(AppModel.self) private var model

    @State private var isSignUp = false
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isBusy = false
    @State private var showSettings = false

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty
            && password.count >= 6
            && (!isSignUp || !name.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    header

                    VStack(spacing: 12) {
                        if isSignUp {
                            field("Name", text: $name, icon: "person")
                                .textContentType(.name)
                        }
                        field("Email", text: $email, icon: "envelope")
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        secureField("Password", text: $password)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button(action: submit) {
                        LoadingLabel(title: isSignUp ? "Create account" : "Log in", isLoading: isBusy)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!canSubmit || isBusy)

                    Button(isSignUp ? "I already have an account" : "Create an account") {
                        withAnimation { isSignUp.toggle(); errorMessage = nil }
                    }
                    .font(.subheadline)
                    .foregroundStyle(Theme.bikeLane)

                    Divider().padding(.vertical, 4)

                    Button {
                        showSettings = true
                    } label: {
                        Label("Server settings", systemImage: "gearshape")
                            .font(.footnote)
                    }
                    .foregroundStyle(.secondary)

                    Text(model.auth.baseURL)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                }
                .padding(24)
            }
            .scrollDismissesKeyboard(.interactively)
            .keyboardDoneButton()
            .background(Theme.screen)
            .scrollDismissesKeyboard(.interactively)
            .sheet(isPresented: $showSettings) {
                NavigationStack { SettingsView() }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            BuzzOnBike(width: 200)
            PedalLogo(size: 36)
            Text("Borrow a classmate's bike. Cheaper than Lime.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 30)
        .padding(.bottom, 8)
    }

    private func field(_ title: String, text: Binding<String>, icon: String) -> some View {
        HStack {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 22)
            TextField(title, text: text)
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private func secureField(_ title: String, text: Binding<String>) -> some View {
        HStack {
            Image(systemName: "lock").foregroundStyle(.secondary).frame(width: 22)
            SecureField(title, text: text)
                .textContentType(isSignUp ? .newPassword : .password)
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private func submit() {
        errorMessage = nil
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                let response = isSignUp
                    ? try await model.api.signUp(name: name, email: email, password: password)
                    : try await model.api.logIn(email: email, password: password)
                await model.signedIn(token: response.token, user: response.user)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
