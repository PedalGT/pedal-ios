import SwiftUI

struct ActiveRideView: View {
    let ride: Ride

    @Environment(AppModel.self) private var model

    @State private var now = Date()
    @State private var isEnding = false
    @State private var errorMessage: String?
    @State private var showPhotoCheck = false

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                rideCard

                VStack(spacing: 6) {
                    Text("Put the lock back in place, then end the ride.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Text("Rides end here in the app, not by tapping your card.")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button { showPhotoCheck = true } label: {
                    LoadingLabel(title: "End ride and lock", isLoading: isEnding)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isEnding)
            }
            .padding(20)
        }
        .background(Theme.screen)
        .onReceive(tick) { now = $0 }
        .sheet(isPresented: $showPhotoCheck) {
            BikePhotoCheckView(bikeName: ride.bikeName, expectedColor: ride.bikeColor) { result in
                // The "Ride finished" screen is shown app-wide from model.finishedRide.
                _ = try await model.endRide(photoCheck: result)
                showPhotoCheck = false
            }
        }
    }

    /// The one bold element on this screen: reflector yellow, big monospaced digits.
    private var rideCard: some View {
        VStack(spacing: 14) {
            Text(ride.bikeName ?? "Your ride")
                .font(.headline)
                .foregroundStyle(Theme.asphalt)

            Text(timerText)
                .font(.system(size: 62, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.asphalt)
                .contentTransition(.numericText())

            HStack(spacing: 24) {
                stat(label: "Fare", value: ride.isFree ? "Free" : ride.fareCents(at: now).asMoney)
                stat(label: "Rate", value: ride.isFree ? "Your bike" : "\((ride.perMinuteCents ?? 10).asMoney)/min")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(Theme.reflector, in: RoundedRectangle(cornerRadius: 22))
    }

    private func stat(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption).foregroundStyle(Theme.asphalt.opacity(0.7))
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.asphalt)
        }
    }

    private var timerText: String {
        let seconds = Int(ride.elapsed(at: now))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

/// Shown after every ride (presented from MainTabView via model.finishedRide):
/// fare, time and the CO2 saved, with Buzz on a bike.
struct RideFinishedView: View {
    let ride: Ride
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                BuzzOnBike(width: 240)
                    .padding(.top, 8)

                Text("Ride finished")
                    .font(.title.weight(.bold))
                if let name = ride.bikeName {
                    Text("Thanks for riding \(name).")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 0) {
                    stat(ride.costCents.asMoney, ride.isFree ? "your bike" : "charged")
                    Divider().frame(height: 40)
                    stat("\(ride.minutes)", ride.minutes == 1 ? "minute" : "minutes")
                    if let km = ride.distanceKm {
                        Divider().frame(height: 40)
                        stat(String(format: "%.1f", km), "km (est.)")
                    }
                }
                .padding(.vertical, 12)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))

                if ride.eventFareApplied == true, let event = ride.event {
                    Label("Flat event fare to \(event.name)", systemImage: "calendar.badge.checkmark")
                        .font(.subheadline.weight(.medium))
                } else if let event = ride.event {
                    Text("No event fare: the ride didn't end at \(event.location ?? event.name) during the event.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                co2Card

                Button("Done") { dismiss() }
                    .buttonStyle(PrimaryButtonStyle())
            }
            .padding(22)
        }
        .background(Theme.screen)
    }

    private var co2Card: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "leaf.fill").foregroundStyle(Theme.bikeLane)
                Text((ride.co2SavedGrams ?? 0).asCO2)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            Text("of CO₂ saved compared with driving the same distance")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("Estimate: ride time at bike speed, vs an average car at about 250 g CO₂ per km (US EPA).")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            AramcoImpactNote().padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(Theme.techGold.opacity(0.14), in: RoundedRectangle(cornerRadius: 16))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title2.weight(.bold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
