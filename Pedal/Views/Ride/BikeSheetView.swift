import SwiftUI

struct BikeSheetView: View {
    let bike: Bike
    var openWallet: () -> Void = {}

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var isUnlocking = false
    @State private var errorMessage: String?
    @State private var errorIsBalance = false
    #if DEBUG
    @State private var priceExpanded = DemoLaunch.flag("-demoExpandPrice")
    #else
    @State private var priceExpanded = false
    #endif

    private var canRide: Bool { bike.status == "available" }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(bike.name)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text(bike.code)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: bike.isScooter ? "scooter" : "bicycle")
                    .font(.system(size: 28))
                    .foregroundStyle(Theme.bikeLane)
            }

            VStack(alignment: .leading, spacing: 10) {
                row(icon: "tag", text: bike.priceLabel)
                if let price = bike.price, !bike.isMine {
                    DisclosureGroup("Why this price", isExpanded: $priceExpanded) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Base \(price.baseCentsPerMinute ?? 12)¢/min, adjusted for:")
                            ForEach(price.factors, id: \.key) { factor in
                                HStack {
                                    Text(factor.label)
                                    Spacer()
                                    Text("×\(factor.multiplier, specifier: "%.2f")").monospacedDigit()
                                }
                            }
                            Text("Always \(price.minRateCents ?? 8)–\(price.maxRateCents ?? 20)¢/min. Billed by the second, \((price.minFareCents ?? 50).asMoney) minimum. The rate is locked when you unlock.")
                                .foregroundStyle(.secondary)
                        }
                        .font(.footnote)
                        .padding(.top, 4)
                    }
                    .font(.subheadline)
                }
                if let owner = bike.ownerName, !bike.isMine {
                    row(icon: "person", text: "Listed by \(owner)")
                }
                row(icon: canRide ? "checkmark.circle" : "clock", text: bike.statusLabel)
                if let issues = bike.openIssues, issues > 0 {
                    row(icon: "exclamationmark.triangle",
                        text: "\(issues) reported problem\(issues == 1 ? "" : "s") the owner hasn't fixed yet",
                        tint: .orange)
                }
                row(icon: bike.isOnline ? "wifi" : "wifi.slash",
                    text: bike.isOnline ? "Lock is online" : "Lock is offline — it may not open until it reconnects",
                    tint: bike.isOnline ? .secondary : .orange)
            }

            if let errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                    if errorIsBalance {
                        Button("Add funds") {
                            dismiss()
                            openWallet()
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                }
            }

            Spacer()

            Button(action: unlock) {
                LoadingLabel(title: canRide ? "Unlock and ride" : "Not available", isLoading: isUnlocking)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!canRide || isUnlocking)
        }
        .padding(22)
        .background(Theme.screen)
    }

    private func row(icon: String, text: String, tint: Color = .secondary) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).frame(width: 20).foregroundStyle(tint)
            Text(text).font(.subheadline).foregroundStyle(tint == .secondary ? .primary : tint)
            Spacer()
        }
    }

    private func unlock() {
        errorMessage = nil
        errorIsBalance = false
        isUnlocking = true
        Task {
            defer { isUnlocking = false }
            do {
                try await model.startRide(bikeCode: bike.code)
                dismiss()
            } catch {
                let message = error.localizedDescription
                errorMessage = message
                // The server's low-balance message is the one worth a shortcut.
                errorIsBalance = message.localizedCaseInsensitiveContains("add funds")
            }
        }
    }
}
