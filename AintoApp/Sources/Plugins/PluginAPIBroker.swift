import AppKit
import Foundation
import UserNotifications

enum PluginBridgeResponseStatus: String, Codable, Equatable { case success, authorizationRequired, rejected }
enum PluginBridgeResponseCode: String, Codable, Equatable { case none, unknownAPI, pluginSessionMismatch, crossPluginAccess, permissionNotDeclared, authorizationRequired, networkNotAllowed, unsupported }
struct PluginBridgeResponse: Codable, Equatable {
    let status: PluginBridgeResponseStatus
    let code: PluginBridgeResponseCode
    let value: String?
    init(status: PluginBridgeResponseStatus, code: PluginBridgeResponseCode, value: String? = nil) { self.status = status; self.code = code; self.value = value }
    static let success = PluginBridgeResponse(status: .success, code: .none)
}

protocol PluginCapabilityProviding {
    func clipboardText() -> String?
    func writeClipboard(_ text: String)
    func showNotification(title: String, body: String)
    func openURL(_ url: URL)
    func theme() -> String
    func language() -> String
    func resizeWindow(width: CGFloat, height: CGFloat) -> PluginHostSize
    func fetch(url: URL, completion: @escaping (Result<String, Error>) -> Void)
}

final class SystemPluginCapabilities: PluginCapabilityProviding {
    func clipboardText() -> String? { NSPasteboard.general.string(forType: .string) }
    func writeClipboard(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
    func showNotification(title: String, body: String) { let content = UNMutableNotificationContent(); content.title = title; content.body = body; UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) }
    func openURL(_ url: URL) { NSWorkspace.shared.open(url) }
    func theme() -> String { NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? "dark" : "light" }
    func language() -> String { Locale.current.identifier }
    func resizeWindow(width: CGFloat, height: CGFloat) -> PluginHostSize { PluginHostSession(pluginID: "", featureCode: "", query: "").requestedSize(width: width, height: height) }
    func fetch(url: URL, completion: @escaping (Result<String, Error>) -> Void) { URLSession.shared.dataTask(with: url) { data, _, error in if let error { completion(.failure(error)) } else { completion(.success(String(data: data ?? Data(), encoding: .utf8) ?? "")) } }.resume() }
}

final class PluginAPIBroker {
    private let permissionStore: PluginPermissionStore
    private let networkDomains: [String: Set<String>]
    private let paths: PluginPaths
    private let capabilities: PluginCapabilityProviding
    private let logStore: PluginLogStore?

    init(permissionStore: PluginPermissionStore, networkDomains: [String: [String]] = [:], paths: PluginPaths = .applicationSupport, capabilities: PluginCapabilityProviding = SystemPluginCapabilities(), logStore: PluginLogStore? = nil) {
        self.permissionStore = permissionStore
        self.networkDomains = networkDomains.mapValues { Set($0.map { $0.lowercased() }) }
        self.paths = paths
        self.capabilities = capabilities
        self.logStore = logStore
    }

    func handle(_ request: PluginBridgeRequest, sessionPluginID: String) -> PluginBridgeResponse {
        let response: PluginBridgeResponse
        if request.pluginID != sessionPluginID { response = PluginBridgeResponse(status: .rejected, code: .crossPluginAccess) }
        else if request.version != PluginBridgeRequest.currentVersion { response = PluginBridgeResponse(status: .rejected, code: .unknownAPI) }
        else if let permission = permission(for: request.api) {
            if !permissionStore.isDeclared(permission, for: sessionPluginID) { response = PluginBridgeResponse(status: .rejected, code: .permissionNotDeclared) }
            else if !permissionStore.isGranted(permission, for: sessionPluginID) {
                let requested = permissionStore.request(permission, for: sessionPluginID)
                response = PluginBridgeResponse(status: .authorizationRequired, code: .authorizationRequired)
                if requested { logStore?.append(pluginID: sessionPluginID, event: "authorization-requested", parameters: ["api": request.api.rawValue]) }
            } else if request.api == .networkFetch && !isAllowedNetworkRequest(request, pluginID: sessionPluginID) { response = PluginBridgeResponse(status: .rejected, code: .networkNotAllowed) }
            else { response = dispatch(request, pluginID: sessionPluginID) }
        } else if case .unknown = request.api { response = PluginBridgeResponse(status: .rejected, code: .unknownAPI) }
        else { response = dispatch(request, pluginID: sessionPluginID) }
        logStore?.append(pluginID: sessionPluginID, event: response.status == .success ? "bridge-request-success" : "bridge-rejected", parameters: ["api": request.api.rawValue, "code": response.code.rawValue])
        return response
    }

    func handle(_ request: PluginBridgeRequest, sessionPluginID: String, completion: @escaping (PluginBridgeResponse) -> Void) {
        if request.api == .networkFetch,
           request.pluginID == sessionPluginID,
           permissionStore.isDeclared(.network, for: sessionPluginID),
           permissionStore.isGranted(.network, for: sessionPluginID),
           isAllowedNetworkRequest(request, pluginID: sessionPluginID),
           let raw = request.payload["url"], let url = URL(string: raw) {
            capabilities.fetch(url: url) { [weak self] result in
                let response: PluginBridgeResponse
                switch result {
                case let .success(body): response = PluginBridgeResponse(status: .success, code: .none, value: body)
                case .failure: response = PluginBridgeResponse(status: .rejected, code: .unsupported)
                }
                self?.logStore?.append(pluginID: sessionPluginID, event: response.status == .success ? "bridge-request-success" : "bridge-rejected", parameters: ["api": request.api.rawValue, "code": response.code.rawValue])
                completion(response)
            }
            return
        }
        completion(handle(request, sessionPluginID: sessionPluginID))
    }

    private func dispatch(_ request: PluginBridgeRequest, pluginID: String) -> PluginBridgeResponse {
        switch request.api {
        case .storageSet:
            guard let key = request.payload["key"], let value = request.payload["value"] else { return unsupported }
            var values = storage(for: pluginID); values[key] = value
            return saveStorage(values, pluginID: pluginID) ? PluginBridgeResponse(status: .success, code: .none, value: value) : unsupported
        case .storageGet:
            guard let key = request.payload["key"] else { return unsupported }
            return PluginBridgeResponse(status: .success, code: .none, value: storage(for: pluginID)[key])
        case .clipboardRead: return PluginBridgeResponse(status: .success, code: .none, value: capabilities.clipboardText())
        case .clipboardWrite: guard let text = request.payload["text"] else { return unsupported }; capabilities.writeClipboard(text); return .success
        case .notification: capabilities.showNotification(title: request.payload["title"] ?? "", body: request.payload["body"] ?? ""); return .success
        case .urlOpen: guard let raw = request.payload["url"], let url = URL(string: raw), let scheme = url.scheme, ["https", "http"].contains(scheme.lowercased()) else { return unsupported }; capabilities.openURL(url); return .success
        case .themeRead: return PluginBridgeResponse(status: .success, code: .none, value: capabilities.theme())
        case .languageRead: return PluginBridgeResponse(status: .success, code: .none, value: capabilities.language())
        case .windowResize:
            let size = capabilities.resizeWindow(width: CGFloat(Double(request.payload["width"] ?? "360") ?? 360), height: CGFloat(Double(request.payload["height"] ?? "240") ?? 240))
            return PluginBridgeResponse(status: .success, code: .none, value: "\(Int(size.width))x\(Int(size.height))")
        case .networkFetch:
            return unsupported
        case .fileOpen, .fileReveal: return unsupported
        case .pluginOut: return .success
        case .unknown: return PluginBridgeResponse(status: .rejected, code: .unknownAPI)
        }
    }

    private var unsupported: PluginBridgeResponse { PluginBridgeResponse(status: .rejected, code: .unsupported) }
    private func storage(for pluginID: String) -> [String: String] { guard validPluginID(pluginID), let data = try? Data(contentsOf: storageURL(for: pluginID)), let values = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }; return values }
    private func saveStorage(_ values: [String: String], pluginID: String) -> Bool { guard validPluginID(pluginID), let data = try? JSONEncoder().encode(values) else { return false }; do { try FileManager.default.createDirectory(at: paths.dataURL(for: pluginID), withIntermediateDirectories: true); try data.write(to: storageURL(for: pluginID), options: .atomic); return true } catch { return false } }
    private func storageURL(for pluginID: String) -> URL { paths.dataURL(for: pluginID).appendingPathComponent("storage.json") }
    private func validPluginID(_ pluginID: String) -> Bool { !pluginID.isEmpty && !pluginID.contains("/") && !pluginID.contains("\\") && !pluginID.contains("..") }
    private func permission(for api: PluginBridgeAPI) -> PluginPermission? { switch api { case .pluginOut, .windowResize: nil; case .clipboardRead: .clipboardRead; case .clipboardWrite: .clipboardWrite; case .storageGet, .storageSet: .storage; case .fileOpen: .fileOpen; case .fileReveal: .fileReveal; case .notification: .notification; case .urlOpen: .urlOpen; case .networkFetch: .network; case .themeRead: .themeRead; case .languageRead: .languageRead; case .unknown: nil } }
    private func isAllowedNetworkRequest(_ request: PluginBridgeRequest, pluginID: String) -> Bool { guard let rawURL = request.payload["url"], let url = URL(string: rawURL), url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }; return networkDomains[pluginID, default: []].contains(host) }
}
