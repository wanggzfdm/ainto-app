import XCTest
@testable import AintoApp

final class PluginCenterTests: XCTestCase {
    private var rootURL: URL!

    override func setUpWithError() throws {
        rootURL = FileManager.default.temporaryDirectory.appendingPathComponent("PluginCenterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: rootURL)
    }

    @MainActor
    func testGroupsOperationsErrorsPermissionsAndReload() throws {
        let paths = PluginPaths(rootURL: rootURL)
        let registry = PluginRegistry(paths: paths)
        let permissions = PluginPermissionStore()
        let installer = PluginInstaller(paths: paths, registry: registry)
        let model = PluginCenterModel(registry: registry, installer: installer, permissionStore: permissions)
        let installedURL = try createPlugin(name: "Installed Tool", directory: "installed-source")
        let developmentURL = try createPlugin(name: "Development Tool", directory: "development-source")

        XCTAssertNotNil(model.importPlugin(at: installedURL))
        XCTAssertNotNil(model.addDevelopmentPlugin(at: developmentURL))
        XCTAssertEqual(model.installedPlugins.map(\.id), ["installed-tool"])
        XCTAssertEqual(model.developmentPlugins.map(\.id), ["development-tool"])

        model.setEnabled(false, pluginID: "installed-tool")
        XCTAssertFalse(try XCTUnwrap(model.installedPlugins.first).isEnabled)

        XCTAssertTrue(permissions.grant(.clipboardRead, to: "installed-tool"))
        model.revoke(.clipboardRead, pluginID: "installed-tool")
        XCTAssertFalse(permissions.isGranted(.clipboardRead, for: "installed-tool"))

        model.removeDevelopmentPlugin(id: "development-tool")
        XCTAssertTrue(FileManager.default.fileExists(atPath: developmentURL.path))
        XCTAssertTrue(model.developmentPlugins.isEmpty)

        let invalidURL = rootURL.appendingPathComponent("invalid", isDirectory: true)
        try FileManager.default.createDirectory(at: invalidURL, withIntermediateDirectories: true)
        XCTAssertNil(model.importPlugin(at: invalidURL))
        XCTAssertFalse(try XCTUnwrap(model.importError).message.isEmpty)

        let reloaded = PluginCenterModel(registry: PluginRegistry(paths: paths), installer: PluginInstaller(paths: paths, registry: PluginRegistry(paths: paths)), permissionStore: permissions)
        reloaded.reload()
        XCTAssertEqual(reloaded.installedPlugins.first?.id, "installed-tool")
        XCTAssertFalse(reloaded.installedPlugins.first?.isEnabled ?? true)
    }

    @MainActor
    func testPendingPermissionCanBeGrantedOrDeniedFromCenter() throws {
        let paths = PluginPaths(rootURL: rootURL)
        let registry = PluginRegistry(paths: paths)
        let permissions = PluginPermissionStore(paths: paths)
        let installer = PluginInstaller(paths: paths, registry: registry)
        let model = PluginCenterModel(registry: registry, installer: installer, permissionStore: permissions)
        let pluginURL = try createPlugin(name: "Permission Tool", directory: "permission-source")
        let plugin = try XCTUnwrap(model.importPlugin(at: pluginURL))

        XCTAssertTrue(permissions.request(.clipboardRead, for: plugin.id))
        XCTAssertEqual(model.pendingPermissions(for: plugin.id), [.clipboardRead])
        model.grantPending(.clipboardRead, pluginID: plugin.id)
        XCTAssertTrue(permissions.isGranted(.clipboardRead, for: plugin.id))
        model.revoke(.clipboardRead, pluginID: plugin.id)
        XCTAssertTrue(permissions.request(.clipboardRead, for: plugin.id))
        model.denyPending(.clipboardRead, pluginID: plugin.id)
        XCTAssertFalse(permissions.isGranted(.clipboardRead, for: plugin.id))
        XCTAssertFalse(permissions.request(.clipboardRead, for: plugin.id))
        let reloadedPermissions = PluginPermissionStore(paths: paths)
        reloadedPermissions.setDeclared([.clipboardRead], for: plugin.id)
        XCTAssertFalse(reloadedPermissions.request(.clipboardRead, for: plugin.id))
    }

    @MainActor
    func testSharedStoreAuthorizationGrantedByCenterIsVisibleToBroker() {
        let paths = PluginPaths(rootURL: rootURL)
        let permissions = PluginPermissionStore(paths: paths)
        let registry = PluginRegistry(paths: paths)
        let model = PluginCenterModel(registry: registry, permissionStore: permissions)
        permissions.setDeclared([.clipboardRead], for: pluginID)
        let broker = PluginAPIBroker(permissionStore: permissions, paths: paths)
        let request = PluginBridgeRequest(id: "read", api: .clipboardRead, pluginID: pluginID)
        XCTAssertEqual(broker.handle(request, sessionPluginID: pluginID).status, .authorizationRequired)
        model.grantPending(.clipboardRead, pluginID: pluginID)
        XCTAssertEqual(broker.handle(request, sessionPluginID: pluginID).status, .success)
    }

    func testLogStoreRedactsSensitiveParameters() throws {
        let store = PluginLogStore(paths: PluginPaths(rootURL: rootURL))
        store.append(pluginID: "example", event: "bridge-rejected", parameters: ["token": "secret", "text": "private text", "reason": "denied"])

        let entry = try XCTUnwrap(store.entries(for: "example").first)
        XCTAssertEqual(entry.pluginID, "example")
        XCTAssertEqual(entry.event, "bridge-rejected")
        XCTAssertEqual(entry.details["token"], "[redacted]")
        XCTAssertEqual(entry.details["text"], "[redacted]")
        XCTAssertEqual(entry.details["reason"], "denied")
    }

    private let pluginID = "shared-plugin"

    private func createPlugin(name: String, directory: String) throws -> URL {
        let url = rootURL.appendingPathComponent(directory, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let manifest = """
        {"name":"\(name)","version":"1.0.0","main":"index.html","features":[{"code":"open","explain":"Open","cmds":["open"]}],"ainto":{"permissions":["clipboard.read"]}}
        """
        try manifest.write(to: url.appendingPathComponent("plugin.json"), atomically: true, encoding: .utf8)
        try "<html></html>".write(to: url.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        return url
    }
}
