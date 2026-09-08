import XCTest
import ZIPFoundation
@testable import AintoApp

final class PluginInstallerTests: XCTestCase {
    private var rootURL: URL!
    private var sourceURL: URL!

    override func setUpWithError() throws {
        rootURL = FileManager.default.temporaryDirectory.appendingPathComponent("PluginInstallerTests-\(UUID().uuidString)", isDirectory: true)
        sourceURL = rootURL.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try writePlugin(at: sourceURL, name: "color-tool")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func testImportsRegularDirectoryAsManagedCopyAndUninstallsData() throws {
        let paths = PluginPaths(rootURL: rootURL.appendingPathComponent("plugins", isDirectory: true))
        let registry = PluginRegistry(paths: paths)
        let installer = PluginInstaller(paths: paths, registry: registry)

        let installed = try installer.importDirectory(sourceURL)
        let managedURL = paths.installedPluginURL(id: installed.id)
        XCTAssertEqual(installed.source, .installed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: managedURL.path))
        XCTAssertNotEqual(installed.rootURL.standardizedFileURL, sourceURL.standardizedFileURL)

        try FileManager.default.createDirectory(at: paths.dataURL(for: installed.id), withIntermediateDirectories: true)
        try installer.uninstall(id: installed.id)

        XCTAssertFalse(FileManager.default.fileExists(atPath: managedURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.dataURL(for: installed.id).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
    }

    func testRegistersDevelopmentDirectoryWithoutCopyingAndRemovalKeepsSource() throws {
        let paths = PluginPaths(rootURL: rootURL.appendingPathComponent("plugins", isDirectory: true))
        let registry = PluginRegistry(paths: paths)
        let installer = PluginInstaller(paths: paths, registry: registry)

        let development = try installer.registerDevelopmentDirectory(sourceURL)
        XCTAssertEqual(development.source, .development)
        XCTAssertEqual(development.rootURL.standardizedFileURL, sourceURL.standardizedFileURL)

        try installer.uninstall(id: development.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertNil(registry.plugin(id: development.id))
    }

    func testRefusesToOverwriteExistingPluginID() throws {
        let paths = PluginPaths(rootURL: rootURL.appendingPathComponent("plugins", isDirectory: true))
        let registry = PluginRegistry(paths: paths)
        let installer = PluginInstaller(paths: paths, registry: registry)
        _ = try installer.importDirectory(sourceURL)

        XCTAssertThrowsError(try installer.importDirectory(sourceURL)) { error in
            XCTAssertEqual(error as? PluginInstallError, .pluginAlreadyInstalled("color-tool"))
        }
    }
    func testImportsSingleRootArchive() throws {
        let archiveURL = rootURL.appendingPathComponent("color-tool.zip")
        guard let archive = Archive(url: archiveURL, accessMode: .create) else {
            return XCTFail("Unable to create test archive.")
        }
        let manifest = """
        {"name":"zip-color","version":"1.0.0","main":"index.html","features":[]}
        """
        try archive.addEntry(with: "zip-color/plugin.json", type: .file, uncompressedSize: UInt32(manifest.utf8.count), provider: { position, size in
            let data = Data(manifest.utf8)
            return data.subdata(in: Int(position)..<Int(position + size))
        })
        let html = "<main>ZIP Plugin</main>"
        try archive.addEntry(with: "zip-color/index.html", type: .file, uncompressedSize: UInt32(html.utf8.count), provider: { position, size in
            let data = Data(html.utf8)
            return data.subdata(in: Int(position)..<Int(position + size))
        })

        let paths = PluginPaths(rootURL: rootURL.appendingPathComponent("plugins", isDirectory: true))
        let registry = PluginRegistry(paths: paths)
        let installed = try PluginInstaller(paths: paths, registry: registry).importArchive(archiveURL)

        XCTAssertEqual(installed.id, "zip-color")
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.installedPluginURL(id: "zip-color").path))
    }

    private func writePlugin(at directory: URL, name: String) throws {
        let manifest = """
        {"name":"\(name)","version":"1.0.0","main":"index.html","features":[{"code":"\(name)","explain":"\(name)","cmds":["\(name)"]}]}
        """
        try manifest.write(to: directory.appendingPathComponent("plugin.json"), atomically: true, encoding: .utf8)
        try "<main>Plugin</main>".write(to: directory.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
    }
}
