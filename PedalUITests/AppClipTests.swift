import XCTest

/// Drives the app like a rider for the feature screen recordings in video/app-clips.
/// The Simulator is recorded for the whole run; each test prints CLIPMARK lines that
/// say where its clip starts and ends, and the clips are cut from the recording after.
/// Tests run in name order, which matters: the ride starts in test05 and ends in test11.
final class AppClipTests: XCTestCase {
    static var rideStartedAt: Date?
    let app = XCUIApplication()
    private var currentClip = ""

    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    private func launch(tab: Int, _ extra: [String] = []) {
        app.launchArguments = ["-demoEmail", "test@pedal.app", "-demoPassword", "pedal123",
                               "-demoNoPrompts", "-demoTab", String(tab)] + extra
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))
        pause(1.5)
    }

    private func mark(_ clip: String, _ edge: String) {
        currentClip = clip
        print(String(format: "CLIPMARK %@ %@ %.3f", clip, edge, Date().timeIntervalSince1970))
    }

    private func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func tab(_ name: String) {
        app.tabBars.buttons[name].tap()
    }

    private func button(containing text: String) -> XCUIElement {
        app.buttons.containing(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    /// Types a few letters at a time so it reads like someone typing.
    private func type(_ text: String, into field: XCUIElement) {
        var chunk = ""
        for ch in text {
            chunk.append(ch)
            if chunk.count == 3 || ch == " " {
                field.typeText(chunk)
                chunk = ""
            }
        }
        if !chunk.isEmpty { field.typeText(chunk) }
    }

    private var askField: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "askField").firstMatch
    }

    private func pedalReplies() -> Int {
        app.staticTexts.matching(identifier: "pedalMessage").count
    }

    private func waitForReplies(_ n: Int, timeout: TimeInterval = 45) {
        let end = Date().addingTimeInterval(timeout)
        while pedalReplies() < n && Date() < end { pause(0.25) }
        XCTAssertGreaterThanOrEqual(pedalReplies(), n, "Ask Pedal didn't answer")
    }

    private func ask(_ question: String) {
        let field = askField
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        pause(0.8)
        type(question, into: field)
        pause(0.6)
        app.buttons["Send"].tap()
        mark(currentClip, "sent")
        waitForReplies(1)
        mark(currentClip, "answered")
        pause(0.4)
    }

    // MARK: - Clips (before the ride)

    func test01_rideMap() {
        launch(tab: 0)
        pause(1.5)
        mark("01-ride-map", "start")
        let map = app.maps.firstMatch
        let center = map.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        center.press(forDuration: 0.05, thenDragTo: map.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.28)),
                     withVelocity: .slow, thenHoldForDuration: 0.2)
        pause(0.8)
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.28))
            .press(forDuration: 0.05, thenDragTo: center, withVelocity: .slow, thenHoldForDuration: 0.2)
        pause(1.2)
        mark("01-ride-map", "end")
    }

    func test02_whyThisPrice() {
        launch(tab: 0, ["-demoOpenBike", "NM69B2"])
        mark("02-why-this-price", "start")
        let why = app.buttons["Why this price"]
        XCTAssertTrue(why.waitForExistence(timeout: 10))
        pause(1.2)
        why.tap()
        pause(3.5)
        mark("02-why-this-price", "end")
    }

    func test03_events() {
        launch(tab: 0)
        mark("07-events", "start")
        tab("Events")
        XCTAssertTrue(button(containing: "Get the event fare").waitForExistence(timeout: 30))
        pause(1.5)
        app.collectionViews.firstMatch.swipeUp(velocity: .slow)
        pause(1.2)
        app.collectionViews.firstMatch.swipeDown(velocity: .slow)
        pause(1.0)
        mark("07-events", "end")
    }

    func test04_eventFare() {
        launch(tab: 4)
        let get = button(containing: "Get the event fare")
        XCTAssertTrue(get.waitForExistence(timeout: 30))
        pause(0.8)
        mark("08-event-fare", "start")
        get.tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 15))
        pause(3.5)
        app.buttons["Cancel"].tap()
        pause(1.2)
        mark("08-event-fare", "end")
    }

    // MARK: - The ride (runs through the remaining tests)

    func test05_startRide() {
        launch(tab: 0)
        mark("11-start-ride", "start")
        let code = app.textFields["Enter code"]
        XCTAssertTrue(code.waitForExistence(timeout: 10))
        code.tap()
        pause(0.6)
        type("Z7G5BL", into: code)
        pause(0.5)
        app.buttons["Find"].tap()
        let unlock = button(containing: "Unlock and ride")
        XCTAssertTrue(unlock.waitForExistence(timeout: 15))
        pause(1.5)
        unlock.tap()
        XCTAssertTrue(button(containing: "End ride and lock").waitForExistence(timeout: 20))
        Self.rideStartedAt = Date()
        pause(2.5)
        mark("11-start-ride", "end")
    }

    func test06_askPrice() {
        launch(tab: 3)
        mark("03-ask-price", "start")
        ask("Why is it this price right now?")
        pause(3.5)
        mark("03-ask-price", "end")
    }

    func test07_askTopUp() {
        launch(tab: 3)
        mark("04-ask-topup", "start")
        ask("Top up $10")
        let add = button(containing: "BuzzCard funds")
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        pause(1.5)
        add.tap()
        waitForReplies(2)
        pause(2.5)
        mark("04-ask-topup", "end")
    }

    func test08_askReport() {
        launch(tab: 3)
        mark("05-ask-report", "start")
        ask("The brakes on my last bike felt loose")
        let send = button(containing: "owner")
        XCTAssertTrue(send.waitForExistence(timeout: 10))
        pause(1.5)
        send.tap()
        waitForReplies(2)
        pause(2.5)
        mark("05-ask-report", "end")
    }

    func test09_wallet() {
        launch(tab: 0)
        mark("06-wallet", "start")
        tab("Wallet")
        pause(1.5)
        app.buttons["$10.00"].firstMatch.tap()
        pause(0.8)
        button(containing: "BuzzCard").tap()
        pause(2.0)
        app.collectionViews.firstMatch.swipeUp(velocity: .slow)
        pause(1.5)
        mark("06-wallet", "end")
    }

    func test10_dynamicIsland() {
        launch(tab: 0)
        pause(1.0)
        mark("10-dynamic-island", "start")
        XCUIDevice.shared.press(.home)
        pause(2.5)
        // Long-press the Dynamic Island to open the expanded Live Activity.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let island = springboard.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 201, dy: 30))
        island.press(forDuration: 1.0)
        pause(4.0)
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7)).tap()
        pause(1.5)
        mark("10-dynamic-island", "end")
    }

    func test11_endRide() {
        // Let the ride run at least five minutes so the CO2 number means something.
        if let started = Self.rideStartedAt {
            let wait = 300 - Date().timeIntervalSince(started)
            if wait > 0 { pause(wait) }
        }
        launch(tab: 0)
        let end = button(containing: "End ride and lock")
        XCTAssertTrue(end.waitForExistence(timeout: 15))
        end.tap()
        let skip = button(containing: "End ride without photo")
        XCTAssertTrue(skip.waitForExistence(timeout: 10))
        pause(1.0)
        skip.tap()
        // The clip starts once the photo sheet (with its testing-only button) is gone.
        let gone = Date().addingTimeInterval(15)
        while skip.exists && Date() < gone { pause(0.1) }
        mark("09-ride-finished", "start")
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 20))
        pause(4.0)
        mark("09-ride-finished", "end")
    }
}
