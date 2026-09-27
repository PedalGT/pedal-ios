import SwiftUI

/// Real upcoming GT events (GT Engage) picked by the AI. "Get the event fare" arms a
/// one-time pass: the rider's next card tap on any Pedal lock starts a flat-fare
/// ride to that event.
struct EventsView: View {
    @Environment(AppModel.self) private var model

    @State private var armingEventId: String?
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Bike to campus events for a flat \(model.eventFlatFareCents.asMoney). Pick one, then tap your card on any Pedal lock.")
                            .font(.subheadline)
                        if let poweredBy = model.eventsPoweredBy {
                            PoweredByBadge(prefix: "Picked by", name: poweredBy)
                        }
                    }
                    .listRowBackground(Color.clear)
                }

                if model.events.isEmpty {
                    Section {
                        Text(model.eventsError ?? "Looking for events…").foregroundStyle(.secondary)
                    }
                }
                ForEach(model.events) { event in
                    Section { row(event) }
                }
                if let first = model.events.first {
                    Section {
                        Button("Send a test reminder") { Task { await EventNotifier.sendTest(first) } }
                            .font(.footnote)
                        Text("Events from GT Engage. The flat fare applies when the ride ends within 300 m of the venue, from an hour before the event until it ends.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .navigationTitle("Bike to events")
            .refreshable { await model.loadEvents() }
            .task {
                await model.loadEvents()
                #if DEBUG
                if DemoLaunch.flag("-demoEventPass"), let first = model.events.first {
                    try? await Task.sleep(for: .seconds(1))
                    try? await model.armEventPass(for: first)
                }
                #endif
            }
            .sheet(item: Binding(get: { model.eventPass }, set: { if $0 == nil { Task { await model.cancelEventPass() } } })) { pass in
                EventPassView(pass: pass)
                    .presentationDetents([.medium])
                    .interactiveDismissDisabled()
            }
            .alert("Bike to events", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(message ?? "")
            }
        }
    }

    private func row(_ event: CampusEvent) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(event.name).font(.headline)
                Spacer()
                if event.freeFood {
                    Text("Free food").font(.caption.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Theme.buzzGold.opacity(0.35), in: Capsule())
                }
            }
            Text(event.invite).font(.subheadline)
            Label("\(event.startDate.formatted(.dateTime.weekday(.abbreviated).hour().minute())) · \(event.location)",
                  systemImage: "mappin.and.ellipse")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\((event.flatFareCents ?? model.eventFlatFareCents).asMoney) flat")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.bikeLane)
                if let usual = event.usualFareCents, usual > (event.flatFareCents ?? model.eventFlatFareCents) {
                    Text("usually about \(usual.asMoney)")
                        .font(.subheadline)
                        .strikethrough()
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                arm(event)
            } label: {
                LoadingLabel(title: "Get the event fare", isLoading: armingEventId == event.id)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(armingEventId != nil || model.activeRide != nil)
        }
        .padding(.vertical, 4)
    }

    private func arm(_ event: CampusEvent) {
        armingEventId = event.id
        Task {
            defer { armingEventId = nil }
            do {
                try await model.armEventPass(for: event)
            } catch {
                message = error.localizedDescription
            }
        }
    }
}

/// Waiting for the rider's card tap on any lock. Polls until the ride starts.
struct EventPassView: View {
    let pass: EventPass
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "wave.3.right.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Theme.bikeLane)
                .symbolEffect(.pulse, options: .repeating)

            Text("Tap your card on any Pedal lock")
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)

            Text("Your next ride goes to \(pass.eventName) for \(pass.flatFareCents.asMoney) flat. End it at \(pass.location ?? "the venue").")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 4) {
                Text("Offer expires in")
                Text(timerInterval: Date()...pass.expiresDate, countsDown: true)
                    .monospacedDigit()
            }
            .font(.footnote)
            .foregroundStyle(.secondary)

            Button("Cancel", role: .cancel) {
                Task { await model.cancelEventPass() }
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding(24)
        .task {
            // The card tap happens on the lock; watch for the ride it starts.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                await model.refresh()
                if model.activeRide != nil || model.eventPass == nil || Date() > pass.expiresDate {
                    if Date() > pass.expiresDate { await model.cancelEventPass() }
                    dismiss()
                    return
                }
            }
        }
    }
}
