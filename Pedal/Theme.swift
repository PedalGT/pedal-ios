import SwiftUI

/// Georgia Tech palette (brand.gatech.edu): Navy, Tech Gold, Buzz Gold.
enum Theme {
    static let gtNavy = Color(red: 0x00 / 255, green: 0x30 / 255, blue: 0x57 / 255)
    static let techGold = Color(red: 0xB3 / 255, green: 0xA3 / 255, blue: 0x69 / 255)
    static let buzzGold = Color(red: 0xEA / 255, green: 0xAA / 255, blue: 0x00 / 255)

    static let asphalt = gtNavy
    /// Primary accent (buttons, icons). GT Navy; GT Bold Blue in Dark Mode so it still reads.
    static let bikeLane = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x5B / 255, green: 0x7F / 255, blue: 0xD1 / 255, alpha: 1)
            : UIColor(red: 0x00 / 255, green: 0x30 / 255, blue: 0x57 / 255, alpha: 1)
    })
    /// The one bold element on a screen (the ride timer card).
    static let reflector = buzzGold
    static let paper = Color(red: 0xF5 / 255, green: 0xF7 / 255, blue: 0xF6 / 255)

    /// Backgrounds flip in Dark Mode; the accent colours stay put so signage still reads.
    static var screen: Color { Color(uiColor: .systemGroupedBackground) }
    static var card: Color { Color(uiColor: .secondarySystemGroupedBackground) }
}

/// The one big green button on a screen.
struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.bikeLane
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(isEnabled ? tint : Color.gray.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(.white)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.bikeLane.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(Theme.bikeLane)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Spinner that replaces a button's label while a request is in flight,
/// so every server call has a visible loading state.
struct LoadingLabel: View {
    let title: String
    let isLoading: Bool

    var body: some View {
        ZStack {
            Text(title).opacity(isLoading ? 0 : 1)
            if isLoading {
                ProgressView().tint(.white)
            }
        }
    }
}

/// Used by empty states: says what happened and what to do next.
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 34))
                .foregroundStyle(Theme.bikeLane.opacity(0.7))
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

/// A "Done" button above the keyboard. Apply once per screen that has text fields
/// (inside its NavigationStack), since number pads have no return key.
struct KeyboardDoneButton: ViewModifier {
    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                .fontWeight(.semibold)
            }
        }
    }
}

extension View {
    func keyboardDoneButton() -> some View { modifier(KeyboardDoneButton()) }
}
