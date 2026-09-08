import XCTest
@testable import AintoApp

final class PluginHostSessionTests: XCTestCase {
    func testSessionEntersOnceExitsOnceAndClampsRequestedSize() {
        var session = PluginHostSession(pluginID: "color-tool", featureCode: "color", query: "#fff")
        XCTAssertEqual(session.enterContext.featureCode, "color")
        XCTAssertEqual(session.requestedSize(width: 20, height: 2_000), PluginHostSize(width: 360, height: 720))
        XCTAssertTrue(session.exit())
        XCTAssertFalse(session.exit())
    }
}
