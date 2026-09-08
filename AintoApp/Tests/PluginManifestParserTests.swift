import XCTest
@testable import AintoApp

final class PluginManifestParserTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PluginManifestParserTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil
    }

    func testParsesValidWebPluginAndRetainsFeaturesAndAintoFields() throws {
        let pluginURL = try makePlugin(
            manifest: """
            {
              "name": "color-tool",
              "version": "1.0.0",
              "description": "Color converter",
              "main": "index.html",
              "features": [{"code": "color", "explain": "Color Tool", "cmds": ["color", "颜色"]}],
              "ainto": {
                "permissions": ["clipboard.read", "clipboard.write", "storage"],
                "networkDomains": ["https://api.example.com"]
              }
            }
            """
        )

        let parsed = try PluginManifestParser().parse(at: pluginURL)

        XCTAssertEqual(parsed.manifest.name, "color-tool")
        XCTAssertEqual(parsed.manifest.features.map(\.code), ["color"])
        XCTAssertEqual(parsed.manifest.features.first?.cmds, ["color", "颜色"])
        XCTAssertEqual(parsed.manifest.ainto?.permissions, [.clipboardRead, .clipboardWrite, .storage])
        XCTAssertEqual(parsed.manifest.ainto?.networkDomains, ["api.example.com"])
        XCTAssertEqual(parsed.compatibility, .webCompatible)
    }

    func testRejectsManifestWithoutRequiredFields() throws {
        let pluginURL = try makePlugin(manifest: #"{"name":"missing-fields"}"#)

        XCTAssertThrowsError(try PluginManifestParser().parse(at: pluginURL)) { error in
            XCTAssertEqual(error as? PluginValidationError, .missingRequiredField("version"))
        }
    }

    func testRejectsMissingOrEscapingMainEntry() throws {
        let missingEntry = try makePlugin(
            manifest: #"{"name":"missing-entry","version":"1.0.0","main":"index.html","features":[]}"#,
            entry: false
        )
        XCTAssertThrowsError(try PluginManifestParser().parse(at: missingEntry)) { error in
            XCTAssertEqual(error as? PluginValidationError, .missingEntryFile("index.html"))
        }

        let escapingEntry = try makePlugin(manifest: #"{"name":"escaping-entry","version":"1.0.0","main":"../outside.html","features":[]}"#)
        XCTAssertThrowsError(try PluginManifestParser().parse(at: escapingEntry)) { error in
            XCTAssertEqual(error as? PluginValidationError, .pathEscapesPluginRoot("../outside.html"))
        }
    }

    func testRejectsUnsupportedPermissionsAndInvalidNetworkDomains() throws {
        let unsupportedPermission = try makePlugin(
            manifest: #"{"name":"unsupported","version":"1.0.0","main":"index.html","features":[],"ainto":{"permissions":["shell.execute"]}}"#,
            entry: true
        )
        XCTAssertThrowsError(try PluginManifestParser().parse(at: unsupportedPermission)) { error in
            XCTAssertEqual(error as? PluginValidationError, .unsupportedPermission("shell.execute"))
        }

        let invalidDomain = try makePlugin(
            manifest: #"{"name":"insecure","version":"1.0.0","main":"index.html","features":[],"ainto":{"networkDomains":["http://example.com"]}}"#,
            entry: true
        )
        XCTAssertThrowsError(try PluginManifestParser().parse(at: invalidDomain)) { error in
            XCTAssertEqual(error as? PluginValidationError, .invalidNetworkDomain("http://example.com"))
        }
    }

    func testMarksNodeOrElectronPreloadAsNeedingAdaptationWithoutExecutingIt() throws {
        let pluginURL = try makePlugin(
            manifest: #"{"name":"node-plugin","version":"1.0.0","main":"index.html","preload":"preload.js","features":[]}"#,
            entry: true,
            preload: "const electron = require('electron'); process.env.TEST = 'never execute';"
        )

        let parsed = try PluginManifestParser().parse(at: pluginURL)

        XCTAssertEqual(parsed.compatibility, .needsAdaptation(reason: .nodeOrElectronPreload))
    }

    private func makePlugin(manifest: String, entry: Bool = true, preload: String? = nil) throws -> URL {
        let pluginURL = temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: pluginURL, withIntermediateDirectories: true)
        try manifest.write(to: pluginURL.appendingPathComponent("plugin.json"), atomically: true, encoding: .utf8)
        if entry {
            try "<main>Plugin</main>".write(to: pluginURL.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        }
        if let preload {
            try preload.write(to: pluginURL.appendingPathComponent("preload.js"), atomically: true, encoding: .utf8)
        }
        return pluginURL
    }
}
