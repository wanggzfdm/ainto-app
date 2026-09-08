import XCTest
@testable import AintoApp

final class PluginRegistryTests: XCTestCase {
    private var rootURL: URL!

    override func setUpWithError() throws {
        rootURL = FileManager.default.temporaryDirectory.appendingPathComponent("PluginRegistryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func testRegistryPersistsEnabledStateAndDisablesMissingDevelopmentPath() throws {
        let paths = PluginPaths(rootURL: rootURL)
        let pluginRoot = rootURL.appendingPathComponent("development-color", isDirectory: true)
        try FileManager.default.createDirectory(at: pluginRoot, withIntermediateDirectories: true)
        let record = PluginRegistration(
            id: "color-tool",
            source: .development,
            rootURL: pluginRoot,
            manifest: PluginManifest(name: "Color", version: "1.0.0", description: nil, main: "index.html", preload: nil, features: [], ainto: nil),
            compatibility: .webCompatible,
            isEnabled: true
        )

        let registry = PluginRegistry(paths: paths)
        try registry.register(record)
        try registry.setEnabled(false, id: "color-tool")

        let restored = PluginRegistry(paths: paths)
        try restored.load()
        XCTAssertFalse(try XCTUnwrap(restored.plugin(id: "color-tool")).isEnabled)

        try FileManager.default.removeItem(at: pluginRoot)
        try restored.refreshDevelopmentPlugins()
        XCTAssertFalse(try XCTUnwrap(restored.plugin(id: "color-tool")).isEnabled)
        XCTAssertEqual(restored.plugin(id: "color-tool")?.validationMessage, "Development directory is unavailable.")
    }
}
