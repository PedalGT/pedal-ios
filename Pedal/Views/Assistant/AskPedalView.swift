import SwiftUI

/// Chat with Ask Pedal about prices, balance, spending and CO2. The server does
/// all the math; the assistant explains it and can suggest a top-up or a ride,
/// which only happens when the rider taps the suggestion.
struct AskPedalView: View {
    @Environment(AppModel.self) private var model

    @State private var messages: [ChatMessage] = []
    @State private var draft = ""
    @State private var isThinking = false
    @State private var runningAction: UUID?
    /// Which model answered last ("Gemini" until told otherwise).
    @State private var poweredBy: String? = "Gemini"
    @FocusState private var inputFocused: Bool

    private let suggestions = [
        "Why is the price what it is right now?",
        "How much have I spent this week?",
        "How much CO2 have I saved?",
        "Top up $5",
        "The brakes on my last bike felt loose"
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            if messages.isEmpty { intro }
                            ForEach(messages) { message in
                                bubble(message).id(message.id)
                            }
                            if isThinking {
                                ProgressView().padding(.leading, 8).id("thinking")
                            }
                        }
                        .padding(16)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: messages.count) { _, _ in
                        withAnimation { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
                    }
                }
                inputBar
            }
            .background(Theme.screen)
            #if DEBUG
            .task {
                for q in DemoLaunch.questions {
                    send(q)
                    while isThinking { try? await Task.sleep(for: .milliseconds(200)) }
                }
            }
            #endif
            .navigationTitle("Ask Pedal")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top) {
                if let poweredBy {
                    PoweredByBadge(prefix: "Powered by", name: poweredBy)
                        .padding(.vertical, 6)
                }
            }
        }
    }

    // MARK: - Pieces

    private var intro: some View {
        VStack(alignment: .leading, spacing: 10) {
            BuzzOnBike(width: 150)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 4)
            Text("Ask about prices, your balance, what you've spent, or how much CO2 you've saved. Something wrong with a bike? Tell me and I'll let the owner know.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ForEach(suggestions, id: \.self) { text in
                Button(text) { send(text) }
                    .font(.subheadline)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.background, in: Capsule())
            }
        }
    }

    private func bubble(_ message: ChatMessage) -> some View {
        VStack(alignment: message.fromRider ? .trailing : .leading, spacing: 8) {
            Text(message.text)
                .font(.body)
                .padding(12)
                .foregroundStyle(message.fromRider ? Color.white : Color.primary)
                .background(message.fromRider ? Theme.bikeLane : Color(.secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 16))
                .accessibilityIdentifier(message.fromRider ? "riderMessage" : "pedalMessage")

            if let action = message.action {
                if message.actionDone {
                    Label("Done", systemImage: "checkmark.circle.fill")
                        .font(.footnote).foregroundStyle(Theme.bikeLane)
                } else {
                    Button { run(action, for: message.id) } label: {
                        LoadingLabel(title: action.label, isLoading: runningAction == message.id)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(runningAction != nil)
                }
            }
            if let note = message.note {
                Text(note).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.fromRider ? .trailing : .leading)
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask Pedal", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .focused($inputFocused)
                .accessibilityIdentifier("askField")
                .onSubmit { send(draft) }
                .keyboardDoneButton()
            Button { send(draft) } label: {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 30))
            }
            .accessibilityLabel("Send")
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || isThinking)
        }
        .padding(12)
        .background(.bar)
    }

    // MARK: - Actions

    private func send(_ text: String) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isThinking else { return }
        draft = ""
        messages.append(ChatMessage(fromRider: true, text: question))
        isThinking = true
        Task {
            defer { isThinking = false }
            let history = messages.map { (role: $0.fromRider ? "user" : "assistant", text: $0.text) }
            do {
                let response = try await model.api.askPedal(history)
                poweredBy = response.poweredBy
                messages.append(ChatMessage(fromRider: false, text: response.reply, action: response.action,
                                            note: response.source == "built-in" ? "Built-in answer (no AI key set on the server)" : nil))
            } catch {
                messages.append(ChatMessage(fromRider: false, text: "Couldn't reach Ask Pedal. \(error.localizedDescription)"))
            }
        }
    }

    private func run(_ action: AssistantAction, for id: UUID) {
        runningAction = id
        Task {
            defer { runningAction = nil }
            do {
                switch action.type {
                case "topup":
                    // BuzzCard funds, same as the Wallet (demo: nothing is charged).
                    _ = try await model.api.topUp(amountCents: action.amountCents ?? 0, method: "buzzcard")
                    await model.refresh()
                    reply("Added \((action.amountCents ?? 0).asMoney). Your balance is \(model.balanceCents.asMoney).")
                case "report_issue":
                    guard let code = action.bikeCode, let summary = action.summary else { return }
                    _ = try await model.api.reportIssue(bikeCode: code, summary: summary, unsafe: action.unsafe ?? false)
                    reply("Sent to the owner of bike \(code). Thanks for looking out for the next rider.")
                case "start_ride":
                    guard let code = action.bikeCode else { return }
                    try await model.startRide(bikeCode: code)
                    reply("Ride started on bike \(code). The lock is opening. End it from the Ride tab.")
                default:
                    return
                }
                if let index = messages.firstIndex(where: { $0.id == id }) { messages[index].actionDone = true }
            } catch {
                reply("That didn't work. \(error.localizedDescription)")
            }
        }
    }

    private func reply(_ text: String) {
        messages.append(ChatMessage(fromRider: false, text: text))
    }
}

struct ChatMessage: Identifiable {
    let id = UUID()
    let fromRider: Bool
    let text: String
    var action: AssistantAction? = nil
    var note: String? = nil
    var actionDone = false
}
