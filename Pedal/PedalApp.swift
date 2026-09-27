import SwiftUI

@main
struct PedalApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task {
                    #if DEBUG
                    await model.demoSignInIfAsked()
                    #endif
                    await model.refresh()
                    await model.loadEvents()   // schedules "bike to events" reminders
                    #if DEBUG
                    if let code = DemoLaunch.value("-demoStartRide"), model.activeRide == nil {
                        try? await model.startRide(bikeCode: code)
                    }
                    if DemoLaunch.flag("-demoFinished"), let last = try? await model.api.rideHistory().first {
                        model.finishedRide = last
                    }
                    #endif
                }
                // Ride links: pedal://ride/CODE, or https://<siteHost>/ride/CODE once
                // the site is published (Universal Links arrive here too).
                .onOpenURL { model.handleRideLink($0) }
                // NFC stickers and other Universal Links can arrive as a web
                // browsing activity instead of a URL, so catch that too.
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { model.handleRideLink(url) }
                }
                .alert("Ride link", isPresented: Binding(
                    get: { model.rideLinkMessage != nil },
                    set: { if !$0 { model.rideLinkMessage = nil } }
                )) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(model.rideLinkMessage ?? "")
                }
                .onChange(of: scenePhase) { _, phase in
                    // Coming back from the Home screen: a ride may have been
                    // started by a card tap on the lock while the app was away.
                    if phase == .active {
                        Task { await model.refresh() }
                    }
                }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.isLoggedIn {
                MainTabView()
            } else {
                LoginView()
            }
        }
        .animation(.default, value: model.isLoggedIn)
    }
}

struct MainTabView: View {
    @Environment(AppModel.self) private var model
    #if DEBUG
    @State private var selection = DemoLaunch.tab
    #else
    @State private var selection = 0
    #endif

    var body: some View {
        TabView(selection: $selection) {
            RideHomeView(openWallet: { selection = 1 })
                .tabItem { Label("Ride", systemImage: "bicycle") }
                .tag(0)

            WalletView()
                .tabItem { Label("Wallet", systemImage: "creditcard") }
                .tag(1)

            OwnerView()
                .tabItem { Label("My bikes", systemImage: "key.horizontal") }
                .tag(2)

            EventsView()
                .tabItem { Label("Events", systemImage: "calendar") }
                .tag(4)

            AskPedalView()
                .tabItem { Label("Ask", systemImage: "sparkles") }
                .tag(3)
        }
        .tint(Theme.bikeLane)
        .sheet(item: Binding(get: { model.finishedRide }, set: { model.finishedRide = $0 })) { ride in
            RideFinishedView(ride: ride)
                .presentationDetents([.large])
        }
    }
}
