import Foundation

enum PluginPermission: String, Codable, CaseIterable, Hashable {
    case clipboardRead = "clipboard.read"
    case clipboardWrite = "clipboard.write"
    case storage
    case fileOpen = "file.open"
    case fileReveal = "file.reveal"
    case notification
    case urlOpen = "url.open"
    case network
    case themeRead = "theme.read"
    case languageRead = "language.read"
}

struct PluginManifest: Equatable {
    let name: String
    let version: String
    let description: String?
    let main: String
    let preload: String?
    let features: [PluginFeature]
    let ainto: AintoPluginConfiguration?
}

struct PluginFeature: Codable, Equatable, Hashable {
    let code: String
    let explain: String
    let cmds: [String]
}

struct AintoPluginConfiguration: Equatable {
    let permissions: [PluginPermission]
    let networkDomains: [String]
    let minimumHostVersion: String?
    let compatibility: String?
}

enum PluginCompatibility: Equatable {
    case webCompatible
    case needsAdaptation(reason: PluginAdaptationReason)
}

enum PluginAdaptationReason: Equatable {
    case nodeOrElectronPreload
    case unreadablePreload
}

struct ParsedPlugin {
    let manifest: PluginManifest
    let rootURL: URL
    let entryURL: URL
    let compatibility: PluginCompatibility
}

enum PluginValidationError: Error, Equatable, LocalizedError {
    case missingManifest
    case invalidManifest
    case missingRequiredField(String)
    case missingEntryFile(String)
    case pathEscapesPluginRoot(String)
    case unsupportedPermission(String)
    case invalidNetworkDomain(String)

    var errorDescription: String? {
        switch self {
        case .missingManifest: return "plugin.json is missing."
        case .invalidManifest: return "plugin.json is not valid JSON."
        case let .missingRequiredField(field): return "plugin.json is missing \(field)."
        case let .missingEntryFile(path): return "Plugin entry file is missing: \(path)."
        case let .pathEscapesPluginRoot(path): return "Plugin path escapes its root: \(path)."
        case let .unsupportedPermission(permission): return "Unsupported plugin permission: \(permission)."
        case let .invalidNetworkDomain(domain): return "Invalid HTTPS network domain: \(domain)."
        }
    }
}
