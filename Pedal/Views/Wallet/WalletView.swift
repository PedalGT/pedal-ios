import SwiftUI

struct WalletView: View {
    @Environment(AppModel.self) private var model

    @State private var txns: [Transaction] = []
    @State private var isLoading = false
    @State private var busyAmount: Int?
    @State private var errorMessage: String?
    @State private var showTestCard = false

    private let amounts = [500, 1000, 2000]
    @State private var selectedAmount = 1000

    var body: some View {
        NavigationStack {
            List {
                balanceSection
                impactSection
                topUpSection
                RideCardSection()
                activitySection
            }
            .navigationTitle("Wallet")
            .background(Theme.screen)
            .refreshable { await load() }
            .task { await load() }
            .sheet(isPresented: $showTestCard) {
                NavigationStack {
                    TestCardView { amount, number in
                        try await topUp(amountCents: amount, method: "card", cardNumber: number)
                    }
                }
                .presentationDetents([.medium])
            }
        }
    }

    // MARK: - Sections

    private var balanceSection: some View {
        Section {
            VStack(spacing: 6) {
                Text("Balance")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(model.balanceCents.asMoney)
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if !model.canAffordRide {
                    Text("Add at least \(model.pricing.minBalanceToStartCents.asMoney) to start a ride.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private var impactSection: some View {
        if let impact = model.impact, impact.rides > 0 {
            Section {
                LabeledContent("CO₂ saved vs driving", value: impact.co2SavedGrams.asCO2)
                LabeledContent("Distance", value: String(format: "%.1f km", impact.distanceKm))
                LabeledContent("Rides", value: "\(impact.rides)")
            } header: {
                Text("Your impact")
            } footer: {
                AramcoImpactNote()
            }
        }
    }

    private var topUpSection: some View {
        Section {
            Picker("Amount", selection: $selectedAmount) {
                ForEach(amounts, id: \.self) { Text($0.asMoney).tag($0) }
            }
            .pickerStyle(.segmented)

            Button {
                Task { await buzzCardTopUp() }
            } label: {
                BuzzCardButtonLabel(amountCents: selectedAmount, isLoading: busyAmount != nil)
            }
            .buttonStyle(.plain)
            .disabled(busyAmount != nil)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))

            Button("Use a test card instead") { showTestCard = true }
                .font(.subheadline)

            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.red)
            }
        } header: {
            Text("Add funds")
        } footer: {
            Text("Demo: BuzzCard isn't connected, so nothing is charged. The server credits your Pedal balance.")
        }
    }

    private var activitySection: some View {
        Section("Activity") {
            if txns.isEmpty {
                if isLoading {
                    HStack { ProgressView(); Text("Loading…").foregroundStyle(.secondary) }
                } else {
                    EmptyStateView(icon: "list.bullet.rectangle",
                                   title: "Nothing here yet",
                                   message: "Add funds or take a ride and it will show up here.")
                    .listRowBackground(Color.clear)
                }
            } else {
                ForEach(txns) { txn in
                    HStack(spacing: 12) {
                        Image(systemName: txn.icon)
                            .foregroundStyle(txn.isCredit ? Theme.bikeLane : .secondary)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(txn.note ?? txn.type.capitalized)
                                .font(.subheadline)
                            Text(txn.date, format: .dateTime.month().day().hour().minute())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(txn.amountCents.asSignedMoney)
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(txn.isCredit ? Theme.bikeLane : .primary)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func buzzCardTopUp() async {
        errorMessage = nil
        do {
            try await topUp(amountCents: selectedAmount, method: "buzzcard")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    private func topUp(amountCents: Int, method: String, cardNumber: String? = nil, paymentToken: String? = nil) async throws -> Int {
        busyAmount = amountCents
        defer { busyAmount = nil }
        errorMessage = nil
        do {
            let response = try await model.api.topUp(amountCents: amountCents, method: method,
                                                     cardNumber: cardNumber, paymentToken: paymentToken)
            model.balanceCents = response.balanceCents
            await load()
            await model.refresh()
            return response.balanceCents
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await model.api.transactions()
            txns = response.txns
            model.balanceCents = response.balanceCents
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Test card form

struct TestCardView: View {
    /// Throws so the caller's error lands back in the wallet's error line.
    let onSubmit: (Int, String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var cardNumber = "4242 4242 4242 4242"
    @State private var expiry = "12/29"
    @State private var cvc = "123"
    @State private var amountText = "10.00"
    @State private var isBusy = false
    @State private var errorMessage: String?

    private var amountCents: Int {
        Int((Double(amountText.replacingOccurrences(of: "$", with: "")) ?? 0) * 100)
    }

    var body: some View {
        Form {
            Section("Card") {
                TextField("Card number", text: $cardNumber).keyboardType(.numberPad)
                    .keyboardDoneButton()
                HStack {
                    TextField("MM/YY", text: $expiry)
                    Divider()
                    TextField("CVC", text: $cvc).keyboardType(.numberPad)
                }
            }
            Section("Amount") {
                HStack {
                    Text("$")
                    TextField("10.00", text: $amountText).keyboardType(.decimalPad)
                }
            }
            if let errorMessage {
                Section { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
            }
            Section {
                Button {
                    submit()
                } label: {
                    LoadingLabel(title: "Add \(amountCents.asMoney)", isLoading: isBusy)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isBusy || amountCents < 100 || amountCents > 10000)
                .listRowBackground(Color.clear)
            } footer: {
                Text("Test mode: no card is charged. Amounts run from $1 to $100.")
            }
        }
        .navigationTitle("Test card")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        }
    }

    private func submit() {
        errorMessage = nil
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                try await onSubmit(amountCents, cardNumber.replacingOccurrences(of: " ", with: ""))
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Georgia Tech navy with the interlocking GT: "Top up with BuzzCard funds".
struct BuzzCardButtonLabel: View {
    let amountCents: Int
    let isLoading: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image("GTMarkWhite")
                .resizable()
                .scaledToFit()
                .frame(height: 22)
            Text("Top up with BuzzCard funds")
                .font(.headline)
            Spacer()
            if isLoading {
                ProgressView().tint(.white)
            } else {
                Text(amountCents.asMoney).font(.headline.monospacedDigit())
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Theme.gtNavy, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.techGold, lineWidth: 1.5))
    }
}
