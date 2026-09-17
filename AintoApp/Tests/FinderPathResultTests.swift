import Foundation
import Testing
@testable import AintoApp

@Test func resolvesExistingDirectoryAfterTrimmingWhitespace() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }

    let result = FinderPathResult.resolve("  \(directory.path)  ")
    #expect(result?.url == directory.standardizedFileURL)
}

@Test func expandsTildeDirectory() {
    let result = FinderPathResult.resolve("~")
    #expect(result?.url == URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL)
}

@Test func rejectsEmptyMissingAndRegularFilePaths() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    FileManager.default.createFile(atPath: file.path, contents: Data())
    defer { try? FileManager.default.removeItem(at: file) }

    #expect(FinderPathResult.resolve("   ") == nil)
    #expect(FinderPathResult.resolve("/path/that/does/not/exist") == nil)
    #expect(FinderPathResult.resolve(file.path) == nil)
}

@Test func providesFinderPresentationText() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ExampleFolder-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }

    let result = FinderPathResult.resolve(directory.path)
    #expect(result?.title == directory.lastPathComponent)
    #expect(result?.subtitle == "在访达中打开")
}
