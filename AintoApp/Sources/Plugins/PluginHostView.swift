import SwiftUI
import WebKit

struct PluginEnterContext: Equatable {
    let pluginID: String
    let featureCode: String
    let query: String
}

struct PluginHostSize: Equatable {
    let width: CGFloat
    let height: CGFloat
}

struct PluginPanelSizeLifecycle {
    private(set) var previousSize: PluginHostSize?

    mutating func enter(pluginFrom size: PluginHostSize) -> PluginHostSize {
        previousSize = size
        return size
    }

    mutating func resize(width: CGFloat, height: CGFloat) -> PluginHostSize {
        PluginHostSession(pluginID: "", featureCode: "", query: "").requestedSize(width: width, height: height)
    }

    mutating func exit() -> PluginHostSize? {
        defer { previousSize = nil }
        return previousSize
    }
}

struct PluginHostSession {
    let enterContext: PluginEnterContext
    private(set) var hasExited = false

    init(pluginID: String, featureCode: String, query: String) {
        enterContext = PluginEnterContext(pluginID: pluginID, featureCode: featureCode, query: query)
    }

    mutating func exit() -> Bool {
        guard !hasExited else { return false }
        hasExited = true
        return true
    }

    func requestedSize(width: CGFloat, height: CGFloat) -> PluginHostSize {
        PluginHostSize(width: min(max(width, 360), 800), height: min(max(height, 240), 720))
    }
}

struct PluginHostView: NSViewRepresentable {
    let entryURL: URL
    let pluginRootURL: URL
    let session: PluginHostSession
    let onExit: () -> Void
    let onResize: (PluginHostSize) -> PluginHostSize
    let permissionStore: PluginPermissionStore
    let networkDomains: [String]
    let paths: PluginPaths
    let logStore: PluginLogStore

    init(entryURL: URL, pluginRootURL: URL? = nil, session: PluginHostSession, onExit: @escaping () -> Void, onResize: @escaping (PluginHostSize) -> PluginHostSize = { $0 }, permissionStore: PluginPermissionStore = PluginPermissionStore(), networkDomains: [String] = [], paths: PluginPaths = .applicationSupport, logStore: PluginLogStore = PluginLogStore()) {
        self.entryURL = entryURL
        self.pluginRootURL = (pluginRootURL ?? entryURL.deletingLastPathComponent()).standardizedFileURL
        self.session = session
        self.onExit = onExit
        self.onResize = onResize
        self.permissionStore = permissionStore
        self.networkDomains = networkDomains
        self.paths = paths
        self.logStore = logStore
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onExit: onExit,
            broker: PluginAPIBroker(permissionStore: permissionStore, networkDomains: [session.enterContext.pluginID: networkDomains], paths: paths, capabilities: HostCapabilities(onResize: onResize), logStore: logStore),
            sessionPluginID: session.enterContext.pluginID,
            pluginRootURL: pluginRootURL
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        contentController.add(context.coordinator.bridge, name: PluginBridge.messageHandlerName)
        contentController.addUserScript(WKUserScript(
            source: PluginBridge.injectionScript(pluginID: session.enterContext.pluginID, contextJSON: encodedContext()),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        configuration.userContentController = contentController
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        logStore.append(pluginID: session.enterContext.pluginID, event: "host-load")
        webView.loadFileURL(entryURL, allowingReadAccessTo: pluginRootURL)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}

    private func encodedContext() -> String {
        let dictionary = ["pluginID": session.enterContext.pluginID, "featureCode": session.enterContext.featureCode, "query": session.enterContext.query]
        let data = try? JSONSerialization.data(withJSONObject: dictionary)
        return String(data: data ?? Data("{}".utf8), encoding: .utf8) ?? "{}"
    }

    private final class HostCapabilities: PluginCapabilityProviding {
        private let system = SystemPluginCapabilities()
        private let onResize: (PluginHostSize) -> PluginHostSize
        init(onResize: @escaping (PluginHostSize) -> PluginHostSize) { self.onResize = onResize }
        func clipboardText() -> String? { system.clipboardText() }
        func writeClipboard(_ text: String) { system.writeClipboard(text) }
        func showNotification(title: String, body: String) { system.showNotification(title: title, body: body) }
        func openURL(_ url: URL) { system.openURL(url) }
        func theme() -> String { system.theme() }
        func language() -> String { system.language() }
        func resizeWindow(width: CGFloat, height: CGFloat) -> PluginHostSize { onResize(PluginHostSession(pluginID: "", featureCode: "", query: "").requestedSize(width: width, height: height)) }
        func fetch(url: URL, completion: @escaping (Result<String, Error>) -> Void) { system.fetch(url: url, completion: completion) }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let onExit: () -> Void
        let bridge: PluginBridge

        private let pluginRootURL: URL

        init(onExit: @escaping () -> Void, broker: PluginAPIBroker, sessionPluginID: String, pluginRootURL: URL) {
            self.onExit = onExit
            self.pluginRootURL = pluginRootURL.standardizedFileURL
            bridge = PluginBridge(broker: broker, sessionPluginID: sessionPluginID, onExit: onExit)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url, url.isFileURL else { decisionHandler(.cancel); return }
            let candidate = url.standardizedFileURL
            guard candidate.path == pluginRootURL.path || candidate.path.hasPrefix(pluginRootURL.path + "/") else { decisionHandler(.cancel); return }
            decisionHandler(.allow)
        }
    }
}
