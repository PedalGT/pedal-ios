import ActivityKit
import SwiftUI
import WidgetKit

@main
struct PedalWidgetsBundle: WidgetBundle {
    var body: some Widget {
        RideLiveActivity()
    }
}

/// Ride in progress on the lock screen and in the Dynamic Island. The timer counts
/// up on-device from the start time; the fare updates whenever the app refreshes.
struct RideLiveActivity: Widget {
    private let gold = Color(red: 0xEA / 255, green: 0xAA / 255, blue: 0x00 / 255)   // Buzz Gold

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RideActivityAttributes.self) { context in
            lockScreen(context)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                // The leading region is narrow, so the bike name sits in the bottom row.
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "bicycle")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(gold)
                        .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    timer(context).font(.title2.weight(.semibold)).frame(maxWidth: 96, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.attributes.bikeName)
                            .font(.headline)
                            .lineLimit(1)
                        HStack {
                            Text(rateText(context)).foregroundStyle(.secondary)
                            Spacer()
                            Text(fareText(context)).fontWeight(.semibold).foregroundStyle(gold)
                        }
                        .font(.subheadline)
                    }
                    .padding(.horizontal, 6)
                }
            } compactLeading: {
                Image(systemName: "bicycle").foregroundStyle(gold)
            } compactTrailing: {
                timer(context)
                    .frame(maxWidth: 52)
                    .font(.caption.weight(.semibold))
            } minimal: {
                Image(systemName: "bicycle").foregroundStyle(gold)
            }
            .keylineTint(gold)
        }
    }

    private func lockScreen(_ context: ActivityViewContext<RideActivityAttributes>) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "bicycle")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(gold)
            VStack(alignment: .leading, spacing: 3) {
                Text(context.state.isEnded ? "Ride finished" : context.attributes.bikeName)
                    .font(.headline)
                Text(rateText(context))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                if context.state.isEnded {
                    Text(context.state.fareCents.asMoney).font(.title2.weight(.bold))
                } else {
                    timer(context).font(.title2.weight(.bold))
                    Text(fareText(context)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(16)
    }

    private func timer(_ context: ActivityViewContext<RideActivityAttributes>) -> some View {
        Text(timerInterval: context.attributes.startDate...Date.distantFuture, countsDown: false)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
    }

    private func rateText(_ context: ActivityViewContext<RideActivityAttributes>) -> String {
        let a = context.attributes
        if a.isOwnBike { return "Your bike, free" }
        if let event = a.eventName, let flat = a.eventFlatFareCents { return "To \(event): \(flat.asMoney) flat" }
        return "\(a.centsPerMinute)¢/min, locked"
    }

    private func fareText(_ context: ActivityViewContext<RideActivityAttributes>) -> String {
        context.attributes.isOwnBike ? "Free" : "\(context.state.fareCents.asMoney) so far"
    }
}

private extension Int {
    var asMoney: String { String(format: "$%.2f", Double(self) / 100) }
}
