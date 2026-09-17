import Foundation

struct FinderPathResult: Equatable {
    let url: URL

    var title: String {
        url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
    }

    var subtitle: String { "在访达中打开" }

    static func resolve(_ query: String, fileManager: FileManager = .default) -> FinderPathResult? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") || trimmed == "~" || trimmed.hasPrefix("~/") else {
            return nil
        }

        let path: String
        if trimmed == "~" {
            path = NSHomeDirectory()
        } else if trimmed.hasPrefix("~/") {
            path = (NSHomeDirectory() as NSString).appendingPathComponent(String(trimmed.dropFirst(2)))
        } else {
            path = trimmed
        }

        let url = URL(fileURLWithPath: path).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              fileManager.isReadableFile(atPath: url.path) else {
            return nil
        }
        return FinderPathResult(url: url)
    }
}
