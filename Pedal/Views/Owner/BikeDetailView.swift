import SwiftUI
import MapKit

struct BikeDetailView: View {
    let bike: Bike
    let onChange: () async -> Void

    @Environment(AppModel.self) private var model

    @State private var isHidden: Bool
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var resolvedIssueIds: Set<String> = []

    init(bike: Bike, onChange: @escaping () async -> Void) {
        self.bike = bike
        self.onChange = onChange
        _isHidden = State(initialValue: bike.status == "offline")
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Status", value: bike.statusLabel)
                LabeledContent("Lock") {
                    Label(bike.isOnline ? "Online" : "Offline",
                          systemImage: bike.isOnline ? "wifi" : "wifi.slash")
                        .foregroundStyle(bike.isOnline ? Theme.bikeLane : .secondary)
                }
                LabeledContent("Price right now", value: "\(bike.price?.centsPerMinute ?? bike.perMinuteCents ?? 12)¢/min")
                LabeledContent("Rides", value: "\(bike.rideCount ?? 0)")
                LabeledContent("Earned", value: (bike.earnedCents ?? 0).asMoney)
            }

            let open = (bike.issues ?? []).filter { $0.status == "open" && !resolvedIssueIds.contains($0.id) }
            if !open.isEmpty {
                Section {
                    ForEach(open) { issue in
                        VStack(alignment: .leading, spacing: 6) {
                            Label(issue.summary, systemImage: issue.unsafe == true ? "exclamationmark.octagon.fill" : "wrench.and.screwdriver")
                                .foregroundStyle(issue.unsafe == true ? .red : .primary)
                            Text("\(issue.reporterName ?? "A rider") · \(issue.date.formatted(.dateTime.month().day().hour().minute()))")
                                .font(.caption).foregroundStyle(.secondary)
                            Button("Mark fixed") { resolve(issue) }
                                .font(.subheadline)
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("Reported problems")
                } footer: {
                    Text("Riders report these through Ask Pedal. Consider hiding the bike until it's fixed.")
                }
            }

            Section {
                Toggle("Hide from riders", isOn: $isHidden)
                    .disabled(isSaving || bike.status == "in_use")
                    .onChange(of: isHidden) { _, hide in setHidden(hide) }
                if bike.status == "in_use" {
                    Text("You can't hide a bike while someone is riding it.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } footer: {
                Text("A hidden bike stays yours but stops showing on the rider map.")
            }

            if let coordinate = bike.coordinate {
                Section {
                    Map(initialPosition: .region(MKCoordinateRegion(
                        center: coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.004, longitudeDelta: 0.004)
                    ))) {
                        Marker(bike.name, systemImage: bike.isScooter ? "scooter" : "bicycle",
                               coordinate: coordinate)
                            .tint(Theme.bikeLane)
                    }
                    .frame(height: 190)
                    .listRowInsets(EdgeInsets())
                    .allowsHitTesting(false)
                } header: {
                    Text("Last left here")
                } footer: {
                    if let date = bike.lastLocationDate {
                        Text(date, format: .relative(presentation: .named))
                    }
                }
            } else {
                Section("Last left here") {
                    Text("No location yet. It gets saved when a rider ends a ride.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }

            Section {
                LockCredentialsView(bike: bike)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            } header: {
                Text("Lock setup")
            } footer: {
                Text("Paste LOCK_ID and DEVICE_KEY into the Arduino sketch. Write NFC TEXT to an NTAG sticker on the lock so an iPhone can scan it.")
            }

            if let errorMessage {
                Section { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
            }
        }
        .navigationTitle(bike.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func setHidden(_ hide: Bool) {
        guard hide != (bike.status == "offline") else { return }
        isSaving = true
        errorMessage = nil
        Task {
            defer { isSaving = false }
            do {
                _ = try await model.api.updateBike(id: bike.id, status: hide ? "offline" : "available")
                await onChange()
            } catch {
                errorMessage = error.localizedDescription
                isHidden = (bike.status == "offline")   // put the switch back
            }
        }
    }

    private func resolve(_ issue: BikeIssue) {
        Task {
            do {
                _ = try await model.api.resolveIssue(bikeId: bike.id, issueId: issue.id)
                resolvedIssueIds.insert(issue.id)
                await onChange()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Lock credentials

/// The three values an owner copies into the CONFIG block of the sketch.
struct LockCredentialsView: View {
    let bike: Bike
    @State private var copied: String?

    /// What the lock puts on the air in target mode, shown so the owner can
    /// confirm what their phone should be reading.
    private var nfcText: String { "PEDAL:\(bike.code)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            credential("LOCK_ID", value: bike.id)
            credential("DEVICE_KEY", value: bike.deviceKey ?? "—")
            credential("BIKE_CODE", value: bike.code)

            Divider().padding(.vertical, 2)

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "wave.3.right")
                    .foregroundStyle(Theme.bikeLane)
                Text("The lock broadcasts \(nfcText) over NFC. Hold an iPhone against it and tap Scan lock, or type \(bike.code).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func credential(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack {
                Text(value)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(2)
                Spacer()
                Button {
                    UIPasteboard.general.string = value
                    copied = label
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        if copied == label { copied = nil }
                    }
                } label: {
                    Image(systemName: copied == label ? "checkmark" : "doc.on.doc")
                        .foregroundStyle(copied == label ? Theme.bikeLane : .accentColor)
                }
                .buttonStyle(.borderless)
            }
        }
    }}
