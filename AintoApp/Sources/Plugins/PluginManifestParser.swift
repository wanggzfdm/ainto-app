import Foundation

struct PluginManifestParser {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func parse(at pluginRoot: URL) throws -> ParsedPlugin {
        let rootURL = pluginRoot.standardizedFileURL
        let manifestURL = rootURL.appendingPathComponent("plugin.json", isDirectory: false)
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw PluginValidationError.missingManifest
        }

        let data: Data
        do {
            data = try Data(contentsOf: manifestURL)
        } catch {
            throw PluginValidationError.invalidManifest
        }

        let document: ManifestDocument
        do {
            document = try JSONDecoder().decode(ManifestDocument.self, from: data)
        } catch {
            throw PluginValidationError.invalidManifest
        }

        let name = try required(document.name, field: "name")
        let version = try required(document.version, field: "version")
        let main = try required(document.main, field: "main")
        let features = document.features ?? []

        let paths = PluginPaths(rootURL: rootURL)
        let entryURL = try paths.containedURL(for: main, in: rootURL)
        guard fileManager.fileExists(atPath: entryURL.path) else {
            throw PluginValidationError.missingEntryFile(main)
        }

        let ainto = try parseAintoConfiguration(document.ainto)
        let compatibility = try preloadCompatibility(path: document.preload, rootURL: rootURL, paths: paths)

        return ParsedPlugin(
            manifest: PluginManifest(
                name: name,
                version: version,
                description: document.description,
                main: main,
                preload: document.preload,
                features: features,
                ainto: ainto
            ),
            rootURL: rootURL,
            entryURL: entryURL,
            compatibility: compatibility
        )
    }

    private func required(_ value: String?, field: String) throws -> String {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            throw PluginValidationError.missingRequiredField(field)
        }
        return value
    }

    private func parseAintoConfiguration(_ raw: RawAintoConfiguration?) throws -> AintoPluginConfiguration? {
        guard let raw else { return nil }
        var permissions: [PluginPermission] = []
        for permission in raw.permissions ?? [] {
            guard let value = PluginPermission(rawValue: permission) else {
                throw PluginValidationError.unsupportedPermission(permission)
            }
            permissions.append(value)
        }

        var domains: [String] = []
        for rawDomain in raw.networkDomains ?? [] {
            guard let url = URL(string: rawDomain),
                  url.scheme?.lowercased() == "https",
                  let host = url.host?.lowercased(),
                  url.path.isEmpty || url.path == "/",
                  url.query == nil,
                  url.fragment == nil
            else {
                throw PluginValidationError.invalidNetworkDomain(rawDomain)
            }
            domains.append(host)
        }

        return AintoPluginConfiguration(
            permissions: permissions,
            networkDomains: domains,
            minimumHostVersion: raw.minimumHostVersion,
            compatibility: raw.compatibility
        )
    }

    private func preloadCompatibility(path: String?, rootURL: URL, paths: PluginPaths) throws -> PluginCompatibility {
        guard let path, !path.isEmpty else { return .webCompatible }
        let preloadURL = try paths.containedURL(for: path, in: rootURL)
        guard let source = try? String(contentsOf: preloadURL, encoding: .utf8) else {
            return .needsAdaptation(reason: .unreadablePreload)
        }
        let lowercased = source.lowercased()
        if lowercased.contains("require(") || lowercased.contains("process.") || lowercased.contains("electron") {
            return .needsAdaptation(reason: .nodeOrElectronPreload)
        }
        return .webCompatible
    }
}

private struct ManifestDocument: Decodable {
    let name: String?
    let version: String?
    let description: String?
    let main: String?
    let preload: String?
    let features: [PluginFeature]?
    let ainto: RawAintoConfiguration?
}

private struct RawAintoConfiguration: Decodable {
    let permissions: [String]?
    let networkDomains: [String]?
    let minimumHostVersion: String?
    let compatibility: String?
}
