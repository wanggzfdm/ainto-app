import XCTest
@testable import AintoApp

final class PluginPermissionStoreTests: XCTestCase {
    func testOnlyDeclaredPermissionsCanBeGrantedAndRevoked() {
        let store = PluginPermissionStore()
        let pluginID = "color-tool"
        store.setDeclared([.clipboardRead, .storage], for: pluginID)

        XCTAssertTrue(store.grant(.clipboardRead, to: pluginID))
        XCTAssertTrue(store.isGranted(.clipboardRead, for: pluginID))
        XCTAssertFalse(store.grant(.network, to: pluginID))
        XCTAssertFalse(store.isGranted(.network, for: pluginID))

        store.revoke(.clipboardRead, from: pluginID)
        XCTAssertFalse(store.isGranted(.clipboardRead, for: pluginID))
    }

    func testPermissionsAreIsolatedByPluginID() {
        let store = PluginPermissionStore()
        store.setDeclared([.storage], for: "first")
        store.setDeclared([.storage], for: "second")
        XCTAssertTrue(store.grant(.storage, to: "first"))

        XCTAssertTrue(store.isGranted(.storage, for: "first"))
        XCTAssertFalse(store.isGranted(.storage, for: "second"))
    }
}
