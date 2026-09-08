import Foundation

struct PluginPaths {
    let rootURL: URL

    init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL
    }

    static var applicationSupport: PluginPaths {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return PluginPaths(rootURL: applicationSupport.appendingPathComponent("Ainto/Plugins", isDirectory: true))
    }

    var installedURL: URL { rootURL.appendingPathComponent("installed", isDirectory: true) }
    var developmentURL: URL { rootURL.appendingPathComponent("development", isDirectory: true) }
    var dataURL: URL { rootURL.appendingPathComponent("data", isDirectory: true) }
    var logsURL: URL { rootURL.appendingPathComponent("logs", isDirectory: true) }
    var registryURL: URL { rootURL.appendingPathComponent("registry.json", isDirectory: false) }

    func installedPluginURL(id: String) -> URL {
        installedURL.appendingPathComponent(id, isDirectory: true)
    }

    func dataURL(for pluginID: String) -> URL {
        dataURL.appendingPathComponent(pluginID, isDirectory: true)
    }

    func logURL(for pluginID: String) -> URL {
        logsURL.appendingPathComponent("\(pluginID).log", isDirectory: false)
    }

    func containedURL(for relativePath: String, in pluginRoot: URL) throws -> URL {
        let pathComponents = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !relativePath.hasPrefix("/"),
              !pathComponents.contains(".."),
              !pathComponents.contains("~")
        else {
            throw PluginValidationError.pathEscapesPluginRoot(relativePath)
        }

        let root = pluginRoot.standardizedFileURL
        let candidate = root.appendingPathComponent(relativePath).standardizedFileURL
        guard candidate.path == root.path || candidate.path.hasPrefix(root.path + "/") else {
            throw PluginValidationError.pathEscapesPluginRoot(relativePath)
        }
        return candidate
    }
}
