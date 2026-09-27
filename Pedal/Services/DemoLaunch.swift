import Foundation

#if DEBUG
/// Debug-only launch arguments for taking App Store-style screenshots in the Simulator:
///   -demoEmail x -demoPassword y   sign in automatically
///   -demoTab N                     open on tab N (0 Ride, 1 Wallet, 2 My bikes, 3 Ask, 4 Events)
///   -demoAsk "q1|q2"               type these into Ask Pedal on open
///   -demoFinished                  show "Ride finished" for the last ride
///   -demoNoPrompts                 skip permission prompts
///   -demoOpenBike CODE             open that bike's sheet (with -demoExpandPrice: "Why this price" open)
///   -demoEventPass                 arm the event fare for the first event ("Tap your card" screen)
///   -demoStartRide CODE            start a ride on that bike (for the Live Activity)
/// Never compiled into release builds.
enum DemoLaunch {
    private static let args = ProcessInfo.processInfo.arguments
    static func value(_ key: String) -> String? {
        guard let i = args.firstIndex(of: key), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
    static func flag(_ key: String) -> Bool { args.contains(key) }
    static var tab: Int { Int(value("-demoTab") ?? "") ?? 0 }
    static var questions: [String] { (value("-demoAsk") ?? "").split(separator: "|").map(String.init) }
}
#endif
