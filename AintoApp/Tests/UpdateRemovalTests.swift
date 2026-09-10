import Foundation
import XCTest

final class UpdateRemovalTests: XCTestCase {
    func testDistributionAndApplicationSourcesDoNotReferenceSparkleUpdates() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let files = [
            "AintoApp/Package.swift",
            "AintoApp/project.yml",
            "AintoApp/Resources/Info.plist",
            "AintoApp/Sources/App/AppDelegate.swift",
            "AintoApp/Sources/Views/SettingsView.swift",
            ".github/workflows/release.yml",
        ]
        let forbiddenTerms = ["Spark" + "le", "checkFor" + "Updates"]

        for file in files {
            let contents = try String(contentsOf: projectRoot.appendingPathComponent(file), encoding: .utf8)
            for forbiddenTerm in forbiddenTerms {
                XCTAssertFalse(contents.contains(forbiddenTerm), "\(file) still contains \(forbiddenTerm)")
            }
        }
    }
}
