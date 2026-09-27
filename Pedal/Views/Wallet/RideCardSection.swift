import SwiftUI

/// Linking a physical NFC card to the rider, so they can unlock without opening
/// the app. The lock's PN532 reads the card's UID and the server matches it to a
/// user. Needs no Apple entitlement, so it works on any account.
struct RideCardSection: View {
    @Environment(AppModel.self) private var model

    @State private var linkState = LinkState.idle
    @State private var secondsLeft = Int(Config.cardLinkWindow)
    @State private var errorMessage: String?
    @State private var isUnlinking = false
    @State private var linkTask: Task<Void, Never>?

    private enum LinkState: Equatable {
        case idle, waiting, linked
    }

    private var cardUid: String? { model.me?.cardUid }

    var body: some View {
        Section {
            if let cardUid {
                LabeledContent("Card linked") {
                    Text(cardUid).font(.system(.subheadline, design: .monospaced))
                }
                Button(role: .destructive) {
                    unlink()
                } label: {
                    LoadingLabel(title: "Unlink card", isLoading: isUnlinking)
                        .foregroundStyle(.red)
                }
                .disabled(isUnlinking)
            } else {
                switch linkState {
                case .idle, .linked:
                    Text("No card linked")
                        .foregroundStyle(.secondary)
                    Button("Link a card") { startLink() }
                        .font(.headline)
                        .foregroundStyle(Theme.bikeLane)
                case .waiting:
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            ProgressView()
                            Text("Tap your card on any lock")
                                .font(.subheadline.weight(.semibold))
                        }
                        Text("\(secondsLeft)s left")
                            .font(.system(.title3, design: .rounded).monospacedDigit())
                            .foregroundStyle(Theme.bikeLane)
                        ProgressView(value: Double(secondsLeft), total: Config.cardLinkWindow)
                            .tint(Theme.bikeLane)
                        Button("Cancel") { cancelLink() }
                            .font(.subheadline)
                    }
                    .padding(.vertical, 4)
                }
            }

            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.red)
            }
        } header: {
            Text("Tap to ride")
        } footer: {
            Text(cardUid == nil
                 ? "Link any NFC card or fob — a BuzzCard, a hotel key, a transit card. Tap it on a Pedal lock to unlock and tap again to end the ride."
                 : "Tap this card on a lock to start a ride, and tap again to end it.")
        }
        .onDisappear { linkTask?.cancel() }
    }

    // MARK: - Keycard linking

    private func startLink() {
        errorMessage = nil
        linkTask?.cancel()
        linkTask = Task {
            do {
                let response = try await model.api.startCardLink()
                linkState = .waiting

                // Poll /api/me every 2 s until the lock reports the tap or the
                // 60-second window closes.
                while !Task.isCancelled {
                    let remaining = response.expiryDate.timeIntervalSinceNow
                    secondsLeft = max(0, Int(remaining.rounded()))
                    if remaining <= 0 { break }

                    try? await Task.sleep(for: .seconds(Config.cardLinkPollInterval))
                    guard !Task.isCancelled else { return }

                    await model.refresh()
                    if model.me?.cardUid != nil {
                        linkState = .linked
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        return
                    }
                }

                if model.me?.cardUid == nil {
                    linkState = .idle
                    errorMessage = "No card was tapped in time. Press \"Link a card\" and tap the card on a lock within 60 seconds."
                }
            } catch {
                linkState = .idle
                errorMessage = error.localizedDescription
            }
        }
    }

    private func cancelLink() {
        linkTask?.cancel()
        linkTask = nil
        linkState = .idle
        // The server's pending link simply expires on its own.
    }

    private func unlink() {
        errorMessage = nil
        isUnlinking = true
        Task {
            defer { isUnlinking = false }
            do {
                let user = try await model.api.unlinkCard()
                model.me = user
                model.auth.update(user: user)
                linkState = .idle
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
