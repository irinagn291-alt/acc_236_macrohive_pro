import XCTest

@MainActor
final class ScreenshotTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launch()
    }

    func testCaptureKeyScreens() {
        if app.buttons["Skip onboarding"].firstMatch.waitForExistence(timeout: 6) {
            ShotIO.save("09-onboarding")
            app.buttons["Skip onboarding"].firstMatch.tap()
        }
        _ = app.buttons["Today's Comb"].firstMatch.waitForExistence(timeout: 12)
        pause(2.2)
        tap("Today's Comb")
        pause(0.6)
        ShotIO.save("01-today")

        tap("Forage")
        pause(0.3)
        tap("Search the combs")
        typeField("Search products", "Whey")
        _ = app.staticTexts["Comb Whey Nectar"].waitForExistence(timeout: 6)
        ShotIO.save("02-search")

        tapContaining("Whey")
        pause(0.6)
        ShotIO.save("03-detail")
        tap("Assign forage")
        pause(0.5)
        ShotIO.save("04-assign")

        tap("Harvest Log")
        pause(0.5)
        ShotIO.save("05-daylog")

        tap("Horizon Plan")
        pause(0.5)
        ShotIO.save("06-plan")

        tap("Wish Comb")
        pause(0.5)
        ShotIO.save("07-wish")

        tap("Hive Goals")
        pause(0.5)
        ShotIO.save("08-goals")

        tap("Forage")
        pause(0.3)
        tap("Scan a comb")
        pause(0.6)
        ShotIO.save("10-scan")
    }

    @discardableResult
    func tap(_ label: String, timeout: TimeInterval = 4) -> Bool {
        let button = app.buttons[label].firstMatch
        if button.waitForExistence(timeout: timeout) {
            button.tap()
            return true
        }
        return false
    }

    func tapContaining(_ token: String) {
        let hit = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", token))
            .firstMatch
        if hit.waitForExistence(timeout: 5) { hit.tap() }
    }

    func typeField(_ label: String, _ text: String) {
        let field = app.textFields[label].firstMatch
        if field.waitForExistence(timeout: 4) {
            field.tap()
            field.typeText(text)
            pause(0.8)
        }
    }

    func pause(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }
}

enum ShotIO {
    @MainActor
    static func save(_ name: String) {
        let device = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? ""
        let idiom = device.localizedCaseInsensitiveContains("iPad") ? "ipad" : "iphone"
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("screenshots", isDirectory: true)
            .appendingPathComponent(idiom, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: dir.appendingPathComponent("\(name).png"))
    }
}
