import Foundation
import ZIPFoundation

enum PluginInstallError: Error, Equatable, LocalizedError {
    case pluginAlreadyInstalled(String)
    case invalidArchive
    case unsafeArchiveEntry(String)
    case archiveContainsMultiplePluginRoots

    var errorDescription: String? {
        switch self {
        case let .pluginAlreadyInstalled(id): return "Plugin \(id) is already installed."
        case .invalidArchive: return "The ZIP archive does not contain a valid plugin."
        case let .unsafeArchiveEntry(path): return "The ZIP archive contains an unsafe entry: \(path)."
        case .archiveContainsMultiplePluginRoots: return "The ZIP archive contains multiple plugin roots."
        }
    }
}

final class PluginInstaller {
    private let paths: PluginPaths
    private let registry: PluginRegistry
    private let parser: PluginManifestParser
    private let fileManager: FileManager

    init(paths: PluginPaths, registry: PluginRegistry, parser: PluginManifestParser = PluginManifestParser(), fileManager: FileManager = .default) {
        self.paths = paths
        self.registry = registry
        self.parser = parser
        self.fileManager = fileManager
    }

    func importDirectory(_ sourceURL: URL) throws -> PluginRegistration {
        let parsed = try parser.parse(at: sourceURL)
        let pluginID = pluginID(for: parsed.manifest)
        try ensureAvailable(pluginID)

        let temporaryURL = fileManager.temporaryDirectory.appendingPathComponent("AintoPlugin-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: temporaryURL) }
        try fileManager.copyItem(at: sourceURL, to: temporaryURL)
        _ = try parser.parse(at: temporaryURL)

        let destinationURL = paths.installedPluginURL(id: pluginID)
        try fileManager.createDirectory(at: paths.installedURL, withIntermediateDirectories: true)
        try fileManager.moveItem(at: temporaryURL, to: destinationURL)

        let installed = try parser.parse(at: destinationURL)
        let registration = PluginRegistration(id: pluginID, source: .installed, rootURL: destinationURL, manifest: installed.manifest, compatibility: installed.compatibility, isEnabled: true)
        try registry.register(registration)
        return registration
    }

    func registerDevelopmentDirectory(_ sourceURL: URL) throws -> PluginRegistration {
        let parsed = try parser.parse(at: sourceURL)
        let pluginID = pluginID(for: parsed.manifest)
        try ensureAvailable(pluginID)
        let registration = PluginRegistration(id: pluginID, source: .development, rootURL: sourceURL, manifest: parsed.manifest, compatibility: parsed.compatibility, isEnabled: true)
        try registry.register(registration)
        return registration
    }

    func importArchive(_ archiveURL: URL) throws -> PluginRegistration {
        guard let archive = Archive(url: archiveURL, accessMode: .read) else {
            throw PluginInstallError.invalidArchive
        }
        let stagingURL = fileManager.temporaryDirectory.appendingPathComponent("AintoPluginArchive-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: stagingURL) }
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)

        var pluginRoots = Set<String>()
        for entry in archive {
            let components = entry.path.split(separator: "/", omittingEmptySubsequences: true)
            guard !entry.path.hasPrefix("/"), !components.contains(".."), entry.type != .symlink else {
                throw PluginInstallError.unsafeArchiveEntry(entry.path)
            }
            if components.last == "plugin.json" {
                pluginRoots.insert(components.dropLast().joined(separator: "/"))
            }
        }
        guard pluginRoots.count == 1, let root = pluginRoots.first else {
            throw pluginRoots.isEmpty ? PluginInstallError.invalidArchive : PluginInstallError.archiveContainsMultiplePluginRoots
        }

        for entry in archive {
            let destination = stagingURL.appendingPathComponent(entry.path).standardizedFileURL
            guard destination.path.hasPrefix(stagingURL.standardizedFileURL.path + "/") else {
                throw PluginInstallError.unsafeArchiveEntry(entry.path)
            }
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            _ = try archive.extract(entry, to: destination)
        }

        return try importDirectory(stagingURL.appendingPathComponent(root, isDirectory: true))
    }

    func uninstall(id: String) throws {
        guard let registration = registry.plugin(id: id) else { return }
        if registration.source == .installed, fileManager.fileExists(atPath: registration.rootURL.path) {
            try fileManager.removeItem(at: registration.rootURL)
        }
        let dataURL = paths.dataURL(for: id)
        if fileManager.fileExists(atPath: dataURL.path) {
            try fileManager.removeItem(at: dataURL)
        }
        try registry.remove(id: id)
    }

    private func ensureAvailable(_ pluginID: String) throws {
        guard registry.plugin(id: pluginID) == nil else { throw PluginInstallError.pluginAlreadyInstalled(pluginID) }
    }

    private func pluginID(for manifest: PluginManifest) -> String {
        let normalized = manifest.name.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        let slug = String(normalized).split(separator: "-").joined(separator: "-")
        return slug.isEmpty ? UUID().uuidString : slug
    }
}
