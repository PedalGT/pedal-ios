import SwiftUI

// Shared brand pieces. Buzz and the interlocking GT are Georgia Tech marks, used
// unmodified for HackGT (organizers OK'd it). Only the bicycle is mirrored.

/// The official Buzz mark riding a bike.
struct BuzzOnBike: View {
    var width: CGFloat = 200

    var body: some View {
        let s = width / 200
        ZStack(alignment: .bottom) {
            Image(systemName: "bicycle")
                .resizable()
                .scaledToFit()
                .frame(width: 170 * s)
                .foregroundStyle(Theme.bikeLane)
                .scaleEffect(x: -1)          // mirror the bike, not Buzz, so he faces the handlebars
            Image("Buzz")
                .resizable()
                .scaledToFit()
                .frame(height: 122 * s)
                .offset(x: 16 * s, y: -52 * s)
        }
        .frame(width: width, height: 180 * s, alignment: .bottom)
        .accessibilityLabel("Buzz riding a bike")
    }
}

/// Pedal mark + wordmark for headers.
struct PedalLogo: View {
    var size: CGFloat = 28

    var body: some View {
        HStack(spacing: size * 0.25) {
            Image("PedalMark")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .foregroundStyle(Theme.bikeLane)
            Text("Pedal")
                .font(.system(size: size * 0.8, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.bikeLane)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Pedal")
    }
}

/// "Powered by Gemini" / "Picked by Muse". Always names the model that actually answered.
struct PoweredByBadge: View {
    let prefix: String
    let name: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkle")
            Text("\(prefix) \(Text(name).fontWeight(.semibold))")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(.tertiarySystemFill), in: Capsule())
    }
}

/// Credit line for the CO2 numbers (HackGT's Aramco "A Marina's Mission" track).
struct AramcoImpactNote: View {
    var body: some View {
        Label("Impact tracking for A Marina's Mission, presented by Aramco", systemImage: "leaf")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}
