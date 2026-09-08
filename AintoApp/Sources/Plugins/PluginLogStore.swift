import Foundation

struct PluginLogEntry: Codable, Equatable, Identifiable {
    let timestamp: Date
    let pluginID: String
    let event: String
    let details: [String: String]

    var id: String { "\(timestamp.timeIntervalSince1970)-\(pluginID)-\(event)" }
}

final class PluginLogStore {
    private let paths: PluginPaths
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(paths: PluginPaths = .applicationSupport, fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func append(pluginID: String, event: String, parameters: [String: String] = [:]) {
        let entry = PluginLogEntry(timestamp: Date(), pluginID: pluginID, event: event, details: sanitized(parameters))
        guard let data = try? encoder.encode(entry), let line = String(data: data, encoding: .utf8) else { return }
        do {
            try fileManager.createDirectory(at: paths.logsURL, withIntermediateDirectories: true)
            let url = paths.logURL(for: pluginID)
            if fileManager.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: Data((line + "\n").utf8))
            } else {
                try Data((line + "\n").utf8).write(to: url, options: .atomic)
            }
        } catch { }
    }

    func entries(for pluginID: String) -> [PluginLogEntry] {
        guard let text = try? String(contentsOf: paths.logURL(for: pluginID), encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { try? decoder.decode(PluginLogEntry.self, from: Data($0.utf8)) }
    }

    private func sanitized(_ parameters: [String: String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: parameters.map { key, value in
            let normalized = key.lowercased()
            let redacted = normalized.contains("text") || normalized.contains("content") || normalized.contains("file") || normalized.contains("token") || normalized.contains("secret")
            return (key, redacted ? "[redacted]" : String(value.prefix(256)))
        })
    }
}
