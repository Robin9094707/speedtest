import XCTest

final class SpeedtestUITests: XCTestCase {
    func testLaunchAndAllFiveTabs() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["speedometer"].waitForExistence(timeout: 15))
        let dashboard = XCTAttachment(screenshot: app.screenshot())
        dashboard.name = "01-Speedtest-Liquid-Glass"; dashboard.lifetime = .keepAlways
        add(dashboard)
        for (tab, title) in [("Verlauf", "Dein Verlauf"), ("Karte", "Deine Orte"), ("Rekorde", "Deine Rekorde"), ("Einstellungen", "Einstellungen")] {
            app.tabBars.buttons[tab].tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 8))
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = tab; shot.lifetime = .keepAlways; add(shot)
        }
        app.tabBars.buttons["Speedtest"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["speedometer"].exists)
    }
}
