import SwiftUI
import MapKit

struct RideHomeView: View {
    var openWallet: () -> Void = {}

    @Environment(AppModel.self) private var model

    @State private var bikes: [Bike] = []
    @State private var codeEntry = ""
    @State private var selectedBike: Bike?
    @State private var lookupError: String?
    @State private var isLookingUp = false
    @State private var isScanning = false
    @State private var scanMessage: String?
    @State private var showSettings = false
    @FocusState private var codeFieldFocused: Bool

    @State private var camera = MapCameraPosition.region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: Config.campusLatitude, longitude: Config.campusLongitude),
            span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
        )
    )

    private var trimmedCode: String {
        codeEntry.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let ride = model.activeRide {
                    ActiveRideView(ride: ride)
                } else {
                    finder
                }
            }
            .navigationTitle(model.activeRide == nil ? "Ride" : "On a ride")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if model.activeRide == nil { PedalLogo(size: 22) } else { Text("On a ride").font(.headline) }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .tint(.secondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: openWallet) {
                        Text(model.balanceCents.asMoney)
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Theme.bikeLane.opacity(0.14), in: Capsule())
                            .foregroundStyle(Theme.bikeLane)
                    }
                }
            }
            .sheet(item: $selectedBike) { bike in
                BikeSheetView(bike: bike, openWallet: openWallet)
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $showSettings) { NavigationStack { SettingsView() } }
            .task(id: model.activeRide?.id) { await pollBikes() }
            #if DEBUG
            .task {
                if let code = DemoLaunch.value("-demoOpenBike") {
                    try? await Task.sleep(for: .seconds(1.2))
                    selectedBike = try? await model.api.bike(code: code)
                }
            }
            #endif
            .refreshable { await loadBikes() }
        }
    }

    // MARK: - Finder

    private var finder: some View {
        VStack(spacing: 0) {
            map
            controls
        }
        .background(Theme.screen)
    }

    private var map: some View {
        Map(position: $camera) {
            ForEach(bikes) { bike in
                if let coordinate = bike.coordinate {
                    Annotation(bike.name, coordinate: coordinate) {
                        BikePin(bike: bike)
                            .onTapGesture { selectedBike = bike }
                    }
                }
            }
            UserAnnotation()
        }
        .mapControls { MapUserLocationButton() }
        .overlay(alignment: .top) {
            if bikes.isEmpty {
                Text("No bikes nearby yet. List one in My bikes, or enter a code below.")
                    .font(.footnote)
                    .padding(10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 8)
            }
        }
        .onAppear { model.location.requestPermission() }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                BuzzOnBike(width: 96)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Ready to ride?").font(.title3.weight(.bold))
                    Text("Tap your card on any Pedal lock, or scan it here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            Button {
                scan()
            } label: {
                HStack(spacing: 10) {
                    if !isScanning { Image(systemName: "wave.3.right.circle.fill") }
                    LoadingLabel(title: "Scan lock", isLoading: isScanning)
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isScanning || isLookingUp)

            HStack(spacing: 10) {
                TextField("Enter code", text: $codeEntry)
                    .keyboardDoneButton()
                    .font(.system(.body, design: .monospaced))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($codeFieldFocused)
                    .submitLabel(.go)
                    .onSubmit { lookUp(code: trimmedCode) }
                    .onChange(of: codeEntry) { _, new in
                        let cleaned = new.uppercased().filter { $0.isLetter || $0.isNumber }
                        codeEntry = String(cleaned.prefix(8))
                        lookupError = nil
                    }
                    .padding(14)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))

                Button {
                    lookUp(code: trimmedCode)
                } label: {
                    LoadingLabel(title: "Find", isLoading: isLookingUp)
                        .frame(width: 58)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(trimmedCode.count < 4 || isLookingUp)
            }

            if let scanMessage {
                Text(scanMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let lookupError {
                Text(lookupError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(Theme.card.ignoresSafeArea(edges: .bottom))
    }

    // MARK: - Actions

    private func scan() {
        scanMessage = nil
        lookupError = nil

        guard NFCScanner.isAvailable else {
            // Simulator, an older iPhone, or a build without the NFC entitlement.
            // Typing the code is always available, so send the user there.
            scanMessage = ScanError.unavailable.errorDescription
            codeFieldFocused = true
            return
        }

        isScanning = true
        Task {
            defer { isScanning = false }
            do {
                let code = try await NFCScanner().scan()
                lookUp(code: code)
            } catch ScanError.cancelled {
                // Quiet no-op.
            } catch {
                scanMessage = error.localizedDescription
                codeFieldFocused = true
            }
        }
    }

    private func lookUp(code: String) {
        let code = code.uppercased().filter { $0.isLetter || $0.isNumber }
        guard code.count >= 4 else {
            lookupError = "Codes are 6 characters, like UEPDC4."
            return
        }
        isLookingUp = true
        lookupError = nil
        Task {
            defer { isLookingUp = false }
            do {
                selectedBike = try await model.api.bike(code: code)
                codeEntry = ""
                codeFieldFocused = false
            } catch {
                lookupError = error.localizedDescription
            }
        }
    }

    private func loadBikes() async {
        do { bikes = try await model.api.bikes() } catch { /* the map keeps the last good list */ }
    }

    /// Refresh the map while this tab is on screen. Also re-checks the account,
    /// so a ride started by tapping the linked card on the lock shows up here.
    private func pollBikes() async {
        guard model.activeRide == nil else { return }
        while !Task.isCancelled {
            await loadBikes()
            await model.refresh()
            if model.activeRide != nil { return }
            try? await Task.sleep(for: .seconds(Config.bikeRefreshInterval))
        }
    }
}

/// Green = available, gray = being ridden, outlined = yours.
private struct BikePin: View {
    let bike: Bike

    private var fill: Color {
        switch bike.status {
        case "available": return Theme.bikeLane
        case "in_use": return Color.gray
        default: return Color.gray.opacity(0.6)
        }
    }

    var body: some View {
        Image(systemName: bike.isScooter ? "scooter" : "bicycle")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.white)
            .padding(9)
            .background(fill, in: Circle())
            .overlay(
                Circle().strokeBorder(bike.isMine ? Theme.reflector : .clear, lineWidth: 3)
            )
            .shadow(radius: 2, y: 1)
    }
}
