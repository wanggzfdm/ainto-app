import Foundation
import WebKit

enum PluginBridgeRequestError: Error, Equatable {
    case invalidJSON
    case unsupportedVersion(Int)
    case missingField(String)
}

enum PluginBridgeAPI: Equatable {
    case pluginOut
    case clipboardRead
    case clipboardWrite
    case storageGet
    case storageSet
    case fileOpen
    case fileReveal
    case notification
    case urlOpen
    case networkFetch
    case themeRead
    case languageRead
    case windowResize
    case unknown(String)

    init(rawValue: String) {
        switch rawValue {
        case "plugin.out": self = .pluginOut
        case "clipboard.read": self = .clipboardRead
        case "clipboard.write": self = .clipboardWrite
        case "storage.get": self = .storageGet
        case "storage.set": self = .storageSet
        case "file.open": self = .fileOpen
        case "file.reveal": self = .fileReveal
        case "notification.show": self = .notification
        case "url.open": self = .urlOpen
        case "network.fetch": self = .networkFetch
        case "theme.read": self = .themeRead
        case "language.read": self = .languageRead
        case "window.resize": self = .windowResize
        default: self = .unknown(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .pluginOut: return "plugin.out"
        case .clipboardRead: return "clipboard.read"
        case .clipboardWrite: return "clipboard.write"
        case .storageGet: return "storage.get"
        case .storageSet: return "storage.set"
        case .fileOpen: return "file.open"
        case .fileReveal: return "file.reveal"
        case .notification: return "notification.show"
        case .urlOpen: return "url.open"
        case .networkFetch: return "network.fetch"
        case .themeRead: return "theme.read"
        case .languageRead: return "language.read"
        case .windowResize: return "window.resize"
        case let .unknown(value): return value
        }
    }
}

struct PluginBridgeRequest: Equatable {
    static let currentVersion = 1

    let version: Int
    let id: String
    let api: PluginBridgeAPI
    let pluginID: String
    let payload: [String: String]

    init(version: Int = PluginBridgeRequest.currentVersion, id: String, api: PluginBridgeAPI, pluginID: String, payload: [String: String] = [:]) {
        self.version = version
        self.id = id
        self.api = api
        self.pluginID = pluginID
        self.payload = payload
    }

    static func decode(from data: Data) throws -> PluginBridgeRequest {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PluginBridgeRequestError.invalidJSON
        }
        guard let version = object["version"] as? Int else { throw PluginBridgeRequestError.missingField("version") }
        guard version == currentVersion else { throw PluginBridgeRequestError.unsupportedVersion(version) }
        guard let id = object["id"] as? String else { throw PluginBridgeRequestError.missingField("id") }
        guard let api = object["api"] as? String else { throw PluginBridgeRequestError.missingField("api") }
        guard let pluginID = object["pluginID"] as? String else { throw PluginBridgeRequestError.missingField("pluginID") }
        let payload = object["payload"] as? [String: String] ?? [:]
        return PluginBridgeRequest(version: version, id: id, api: PluginBridgeAPI(rawValue: api), pluginID: pluginID, payload: payload)
    }
}

final class PluginBridge: NSObject, WKScriptMessageHandler {
    static let messageHandlerName = "aintoBridge"

    private let broker: PluginAPIBroker
    private let sessionPluginID: String
    private let onExit: () -> Void

    init(broker: PluginAPIBroker, sessionPluginID: String, onExit: @escaping () -> Void) {
        self.broker = broker
        self.sessionPluginID = sessionPluginID
        self.onExit = onExit
    }

    static func injectionScript(pluginID: String, contextJSON: String) -> String {
        """
        (() => {
          const context = \(contextJSON);
          const pending = new Map();
          window.addEventListener('ainto-bridge-response', (event) => { const response = event.detail; const handler = pending.get(response.id); if (!handler) return; pending.delete(response.id); response.status === 'success' ? handler.resolve(response.value) : handler.reject(Object.assign(new Error(response.code), response)); });
          const send = (api, payload = {}) => new Promise((resolve, reject) => { const id = crypto.randomUUID(); pending.set(id, {resolve, reject}); window.webkit.messageHandlers.aintoBridge.postMessage(JSON.stringify({version: 1, id, api, pluginID: \(jsonString(pluginID)), payload})); });
          const api = Object.freeze({
            onPluginEnter: (handler) => { if (typeof handler === 'function') handler(context); },
            onPluginOut: (handler) => { if (typeof handler === 'function') window.addEventListener('ainto-plugin-out', handler, {once: true}); },
            outPlugin: () => send('plugin.out'),
            clipboard: Object.freeze({readText: () => send('clipboard.read'), writeText: (text) => send('clipboard.write', {text: String(text)})}),
            storage: Object.freeze({get: (key) => send('storage.get', {key: String(key)}), set: (key, value) => send('storage.set', {key: String(key), value: String(value)})}),
            selectFile: () => send('file.open'),
            showItemInFolder: (path) => send('file.reveal', {path: String(path)}),
            showNotification: (title, body) => send('notification.show', {title: String(title), body: String(body)}),
            openURL: (url) => send('url.open', {url: String(url)}),
            getTheme: () => send('theme.read'),
            getLanguage: () => send('language.read'),
            setExpendHeight: (height) => send('window.resize', {height: String(height)}),
            fetch: (url) => send('network.fetch', {url: String(url)})
          });
          Object.defineProperty(window, 'ainto', {value: api, configurable: false, writable: false});
          Object.defineProperty(window, 'utools', {value: api, configurable: false, writable: false});
          Object.defineProperty(window, 'ztools', {value: api, configurable: false, writable: false});
        })();
        """
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.messageHandlerName,
              let data = bridgeData(from: message.body),
              let request = try? PluginBridgeRequest.decode(from: data)
        else { return }
        broker.handle(request, sessionPluginID: sessionPluginID) { [weak self, weak webView = message.webView] response in
            guard let self else { return }
            var callback: [String: Any] = ["id": request.id, "status": response.status.rawValue, "code": response.code.rawValue]
            if let value = response.value { callback["value"] = value }
            guard let data = try? JSONSerialization.data(withJSONObject: callback), let json = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                webView?.evaluateJavaScript(Self.responseDispatcher(responseJSON: json))
                if response.status == .success, request.api == .pluginOut { self.onExit() }
            }
        }
    }

    static func responseDispatcher(responseJSON: String) -> String {
        "window.dispatchEvent(new CustomEvent('ainto-bridge-response', {detail: \(responseJSON)}));"
    }

    private static func jsonString(_ value: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [value])
        let array = data.flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
        return String(array.dropFirst().dropLast())
    }

    private func bridgeData(from body: Any) -> Data? {
        if let string = body as? String { return Data(string.utf8) }
        guard JSONSerialization.isValidJSONObject(body) else { return nil }
        return try? JSONSerialization.data(withJSONObject: body)
    }
}
