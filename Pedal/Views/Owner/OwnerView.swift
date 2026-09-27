import SwiftUI

struct OwnerView: View {
    @Environment(AppModel.self) private var model

    @State private var bikes: [Bike] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showAddForm = false

    var body: some View {
        NavigationStack {
            List {
                if bikes.isEmpty && !isLoading {
                    Section {
                        EmptyStateView(icon: "bicycle",
                                       title: "No bikes listed yet",
                                       message: "List a bike or scooter and classmates nearby can rent it. You keep 80% of every fare.")
                        .listRowBackground(Color.clear)
                        Button("List a bike") { showAddForm = true }
                            .buttonStyle(PrimaryButtonStyle())
                            .listRowBackground(Color.clear)
                    }
                } else {
                    Section {
                        ForEach(bikes) { bike in
                            NavigationLink {
                                BikeDetailView(bike: bike) { await load() }
                            } label: {
                                BikeRow(bike: bike)
                            }
                        }
                    } header: {
                        Text("Your fleet")
                    } footer: {
                        Text(totalsLine)
                    }
                }

                if let errorMessage {
                    Section { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
                }
            }
            .navigationTitle("My bikes")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddForm = true } label: { Image(systemName: "plus") }
                }
            }
            .refreshable { await load() }
            .task { await load() }
            .sheet(isPresented: $showAddForm) {
                NavigationStack {
                    AddBikeView { await load() }
                }
            }
        }
    }

    private var totalsLine: String {
        let earned = bikes.reduce(0) { $0 + ($1.earnedCents ?? 0) }
        let rides = bikes.reduce(0) { $0 + ($1.rideCount ?? 0) }
        return "\(rides) \(rides == 1 ? "ride" : "rides") · \(earned.asMoney) earned"
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            bikes = try await model.api.ownerBikes()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct BikeRow: View {
    let bike: Bike

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: bike.isScooter ? "scooter" : "bicycle")
                .font(.title3)
                .foregroundStyle(Theme.bikeLane)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(bike.name).font(.headline)
                HStack(spacing: 6) {
                    Text(bike.code).font(.system(.caption, design: .monospaced))
                    Text("·").foregroundStyle(.tertiary)
                    Text(bike.statusLabel).font(.caption)
                    if bike.isOnline {
                        Image(systemName: "wifi").font(.caption2).foregroundStyle(Theme.bikeLane)
                    } else {
                        Image(systemName: "wifi.slash").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text((bike.earnedCents ?? 0).asMoney)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.bikeLane)
                Text("\(bike.rideCount ?? 0) \((bike.rideCount ?? 0) == 1 ? "ride" : "rides")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Add a bike

struct AddBikeView: View {
    let onDone: () async -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var kind = "bike"
    @State private var color = "black"
    @State private var perMinuteCents = 10
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var created: Bike?

    private let priceOptions = [5, 10, 15, 20]

    var body: some View {
        Form {
            Section("What are you listing?") {
                TextField("Name, like Blue Trek", text: $name)
                    .keyboardDoneButton()
                Picker("Type", selection: $kind) {
                    Text("Bike").tag("bike")
                    Text("Scooter").tag("scooter")
                }
                .pickerStyle(.segmented)
                Picker("Color", selection: $color) {
                    ForEach(BikeColors.all, id: \.self) { Text($0.capitalized).tag($0) }
                }
            }

            Section {
                LabeledContent("Price", value: "Automatic")
            } header: {
                Text("Price")
            } footer: {
                Text("Pedal sets the price: \(model.pricing.minRateCents ?? 8)–\(model.pricing.maxRateCents ?? 20)¢/min depending on bikes nearby, time of day and weather, with no unlock fee. You keep 80%.")
            }

            if let errorMessage {
                Section { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
            }

            Section {
                Button {
                    submit()
                } label: {
                    LoadingLabel(title: "List it", isLoading: isBusy)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isBusy || name.trimmingCharacters(in: .whitespaces).isEmpty)
                .listRowBackground(Color.clear)
            } footer: {
                Text("Your phone's current location is saved as where the bike is parked.")
            }
        }
        .navigationTitle("List a bike")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        }
        .sheet(item: $created) { bike in
            NavigationStack {
                NewBikeSetupView(bike: bike) {
                    created = nil
                    dismiss()
                }
            }
        }
    }

    private func submit() {
        errorMessage = nil
        isBusy = true
        Task {
            defer { isBusy = false }
            let coordinate = await model.location.currentLocation()
            do {
                created = try await model.api.listBike(
                    name: name, kind: kind, color: color, perMinuteCents: perMinuteCents,
                    lat: coordinate?.latitude, lng: coordinate?.longitude
                )
                await onDone()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Shown once, right after listing: the two values the Arduino needs.
struct NewBikeSetupView: View {
    let bike: Bike
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.bikeLane)
                Text("\(bike.name) is listed")
                    .font(.title2.weight(.bold))
                Text("Put these two values into arduino/pedal_lock/pedal_lock.ino, then power up the lock.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                LockCredentialsView(bike: bike)

                Button("Done", action: onDone)
                    .buttonStyle(PrimaryButtonStyle())
            }
            .padding(20)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}
