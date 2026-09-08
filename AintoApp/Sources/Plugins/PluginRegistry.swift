import Foundation

enum PluginSource: String, Codable {
    case installed
    case development
}

struct PluginRegistration: Codable, Equatable {
    let id: String
    let source: PluginSource
    let rootPath: String
    let manifest: PersistedPluginManifest
    let compatibility: PersistedPluginCompatibility
    var isEnabled: Bool
    var validationMessage: String?

    init(id: String, source: PluginSource, rootURL: URL, manifest: PluginManifest, compatibility: PluginCompatibility, isEnabled: Bool, validationMessage: String? = nil) {
        self.id = id
        self.source = source
        rootPath = rootURL.standardizedFileURL.path
        self.manifest = PersistedPluginManifest(manifest)
        self.compatibility = PersistedPluginCompatibility(compatibility)
        self.isEnabled = isEnabled
        self.validationMessage = validationMessage
    }

    var rootURL: URL { URL(fileURLWithPath: rootPath, isDirectory: true) }
}

struct PersistedPluginManifest: Codable, Equatable {
    let name: String
    let version: String
    let description: String?
    let main: String
    let preload: String?
    let features: [PluginFeature]
    let ainto: PersistedAintoPluginConfiguration?
    init(_ manifest: PluginManifest) {
        name = manifest.name; version = manifest.version; description = manifest.description
        main = manifest.main; preload = manifest.preload; features = manifest.features
        ainto = manifest.ainto.map(PersistedAintoPluginConfiguration.init)
    }
}

struct PersistedAintoPluginConfiguration: Codable, Equatable {
    let permissions: [PluginPermission]
    let networkDomains: [String]
    let minimumHostVersion: String?
    let compatibility: String?

    init(_ configuration: AintoPluginConfiguration) {
        permissions = configuration.permissions
        networkDomains = configuration.networkDomains
        minimumHostVersion = configuration.minimumHostVersion
        compatibility = configuration.compatibility
    }
}
enum PersistedPluginCompatibility: String, Codable {
    case webCompatible
    case nodeOrElectronPreload
    case unreadablePreload

    init(_ value: PluginCompatibility) {
        switch value {
        case .webCompatible: self = .webCompatible
        case .needsAdaptation(reason: .nodeOrElectronPreload): self = .nodeOrElectronPreload
        case .needsAdaptation(reason: .unreadablePreload): self = .unreadablePreload
        }
    }
}

final class PluginRegistry {
    private let paths: PluginPaths
    private let fileManager: FileManager
    private(set) var plugins: [PluginRegistration] = []

    init(paths: PluginPaths = .applicationSupport, fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    func load() throws {
        guard fileManager.fileExists(atPath: paths.registryURL.path) else { plugins = []; return }
        plugins = try JSONDecoder().decode([PluginRegistration].self, from: Data(contentsOf: paths.registryURL))
    }

    func register(_ registration: PluginRegistration) throws {
        plugins.removeAll { $0.id == registration.id }
        var normalized = registration
        if registration.compatibility != .webCompatible { normalized.isEnabled = false }
        plugins.append(normalized)
        try save()
    }

    func plugin(id: String) -> PluginRegistration? { plugins.first { $0.id == id } }
    func remove(id: String) throws {
        plugins.removeAll { $0.id == id }
        try save()
    }
    func setEnabled(_ enabled: Bool, id: String) throws {
        guard let index = plugins.firstIndex(where: { $0.id == id }) else { return }
        plugins[index].isEnabled = enabled && plugins[index].compatibility == .webCompatible
        try save()
    }

    func refreshDevelopmentPlugins() throws {
        for index in plugins.indices where plugins[index].source == .development {
            if !fileManager.fileExists(atPath: plugins[index].rootPath) {
                plugins[index].isEnabled = false
                plugins[index].validationMessage = "Development directory is unavailable."
            }
        }
        try save()
    }

    private func save() throws {
        try fileManager.createDirectory(at: paths.rootURL, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(plugins)
        try data.write(to: paths.registryURL, options: .atomic)
    }
}
