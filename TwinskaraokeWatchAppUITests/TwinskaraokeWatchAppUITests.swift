import XCTest

final class TwinskaraokeWatchAppUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  func testWatchAppLaunches() throws {
    let app = XCUIApplication()
    app.launchArguments += ["-UITestMode", "1"]
    app.launch()

    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
  }
}
