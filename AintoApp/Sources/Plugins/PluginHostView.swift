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
    let session: PluginHostSession
    let onExit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onExit: onExit) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        let contextJSON = """
        window.aintoPluginContext = \(encodedContext());
        window.utools = window.utools || {};
        window.ztools = window.ztools || {};
        """
        contentController.addUserScript(WKUserScript(source: contextJSON, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        configuration.userContentController = contentController
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.loadFileURL(entryURL, allowingReadAccessTo: entryURL.deletingLastPathComponent())
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}

    private func encodedContext() -> String {
        let dictionary = ["pluginID": session.enterContext.pluginID, "featureCode": session.enterContext.featureCode, "query": session.enterContext.query]
        let data = try? JSONSerialization.data(withJSONObject: dictionary)
        return String(data: data ?? Data("{}".utf8), encoding: .utf8) ?? "{}"
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let onExit: () -> Void

        init(onExit: @escaping () -> Void) { self.onExit = onExit }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard navigationAction.navigationType == .other || navigationAction.request.url?.isFileURL == true else {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
