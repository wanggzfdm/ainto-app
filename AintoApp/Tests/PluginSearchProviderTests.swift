import XCTest
@testable import AintoApp

final class PluginSearchProviderTests: XCTestCase {
    func testMatchesFeatureCodeExplainAndCommandsAndExcludesDisabledPlugins() {
        let enabled = registration(id: "color", enabled: true, feature: PluginFeature(code: "color-tool", explain: "Color Converter", cmds: ["hex", "颜色"]))
        let disabled = registration(id: "hidden", enabled: false, feature: PluginFeature(code: "hidden", explain: "Hidden Tool", cmds: ["hidden"]))
        let provider = PluginSearchProvider()
        let candidates = provider.candidates(from: [enabled, disabled])

        XCTAssertEqual(candidates.map(\.pluginID), ["color"])
        XCTAssertTrue(provider.matches(query: "color-tool", candidate: candidates[0]))
        XCTAssertTrue(provider.matches(query: "converter", candidate: candidates[0]))
        XCTAssertTrue(provider.matches(query: "颜色", candidate: candidates[0]))
    }

    private func registration(id: String, enabled: Bool, feature: PluginFeature) -> PluginRegistration {
        PluginRegistration(
            id: id,
            source: .installed,
            rootURL: URL(fileURLWithPath: "/tmp/\(id)", isDirectory: true),
            manifest: PluginManifest(name: id, version: "1.0.0", description: nil, main: "index.html", preload: nil, features: [feature], ainto: nil),
            compatibility: .webCompatible,
            isEnabled: enabled
        )
    }
}
