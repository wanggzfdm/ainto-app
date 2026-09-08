import XCTest
@testable import AintoApp

final class PluginBridgeTests: XCTestCase {
    private let pluginID = "color-tool"

    func testVersionedRequestParsingRejectsUnsupportedVersionsAndUnknownAPIs() throws {
        let request = try PluginBridgeRequest.decode(from: Data("""
        {"version":1,"id":"request-1","api":"unknown.api","pluginID":"color-tool","payload":{}}
        """.utf8))
        XCTAssertEqual(request.version, PluginBridgeRequest.currentVersion)

        let broker = makeBroker(declared: [])
        XCTAssertEqual(broker.handle(request, sessionPluginID: pluginID).status, .rejected)
        XCTAssertEqual(broker.handle(request, sessionPluginID: pluginID).code, .unknownAPI)

        XCTAssertThrowsError(try PluginBridgeRequest.decode(from: Data("""
        {"version":2,"id":"request-1","api":"storage.get","pluginID":"color-tool","payload":{}}
        """.utf8)))
    }

    func testUndeclaredAndRevokedPermissionsAreRejectedWhileDeclaredUnauthorizedRequestsNeedAuthorization() {
        let store = PluginPermissionStore()
        store.setDeclared([.clipboardRead], for: pluginID)
        let broker = PluginAPIBroker(permissionStore: store)
        let clipboard = PluginBridgeRequest(id: "read", api: .clipboardRead, pluginID: pluginID)

        XCTAssertEqual(broker.handle(clipboard, sessionPluginID: pluginID).status, .authorizationRequired)
        XCTAssertTrue(store.grant(.clipboardRead, to: pluginID))
        XCTAssertEqual(broker.handle(clipboard, sessionPluginID: pluginID).status, .success)
        store.revoke(.clipboardRead, from: pluginID)
        XCTAssertEqual(broker.handle(clipboard, sessionPluginID: pluginID).status, .authorizationRequired)

        let storage = PluginBridgeRequest(id: "storage", api: .storageGet, pluginID: pluginID)
        XCTAssertEqual(broker.handle(storage, sessionPluginID: pluginID).code, .permissionNotDeclared)
    }

    func testCrossPluginStorageAndDisallowedNetworkURLsAreRejected() {
        let store = PluginPermissionStore()
        store.setDeclared([.storage, .network], for: pluginID)
        XCTAssertTrue(store.grant(.storage, to: pluginID))
        XCTAssertTrue(store.grant(.network, to: pluginID))
        let broker = PluginAPIBroker(permissionStore: store, networkDomains: [pluginID: ["api.example.com"]])

        let crossPluginStorage = PluginBridgeRequest(id: "cross", api: .storageGet, pluginID: "other", payload: ["key": "theme"])
        XCTAssertEqual(broker.handle(crossPluginStorage, sessionPluginID: pluginID).code, .crossPluginAccess)

        for url in ["http://api.example.com/data", "https://other.example.com/data"] {
            let request = PluginBridgeRequest(id: url, api: .networkFetch, pluginID: pluginID, payload: ["url": url])
            XCTAssertEqual(broker.handle(request, sessionPluginID: pluginID).code, .networkNotAllowed)
        }
    }

    @MainActor
    func testInjectionReturnsPromisesAndUsesOnlyFixedResponseDispatcher() {
        let script = PluginBridge.injectionScript(pluginID: pluginID, contextJSON: "{}")
        XCTAssertTrue(script.contains("new Promise"))
        XCTAssertTrue(script.contains("ainto-bridge-response"))
        XCTAssertFalse(script.contains("evaluateJavaScript"))
    }

    func testGrantedStorageIsPersistedAndLogsBrokerEvents() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = PluginPaths(rootURL: root)
        let store = PluginPermissionStore(paths: paths)
        let logs = PluginLogStore(paths: paths)
        store.setDeclared([.storage], for: pluginID)
        XCTAssertTrue(store.grant(.storage, to: pluginID))
        let set = PluginBridgeRequest(id: "set", api: .storageSet, pluginID: pluginID, payload: ["key": "theme", "value": "dark"])
        let get = PluginBridgeRequest(id: "get", api: .storageGet, pluginID: pluginID, payload: ["key": "theme"])
        XCTAssertEqual(PluginAPIBroker(permissionStore: store, paths: paths, logStore: logs).handle(set, sessionPluginID: pluginID).value, "dark")
        XCTAssertEqual(PluginAPIBroker(permissionStore: store, paths: paths, logStore: logs).handle(get, sessionPluginID: pluginID).value, "dark")
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.dataURL(for: pluginID).appendingPathComponent("storage.json").path))
        XCTAssertTrue(logs.entries(for: pluginID).contains { $0.event == "bridge-request-success" })
    }

    @MainActor
    func testResponseDispatcherUsesFlatEventDetailContractForEveryStatus() throws {
        for response in [
            PluginBridgeResponse(status: .success, code: .none, value: "value"),
            PluginBridgeResponse(status: .rejected, code: .permissionNotDeclared),
            PluginBridgeResponse(status: .authorizationRequired, code: .authorizationRequired)
        ] {
            let data = try JSONEncoder().encode(response)
            var detail = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            detail["id"] = "request-42"
            let json = String(data: try JSONSerialization.data(withJSONObject: detail), encoding: .utf8)!
            let dispatcher = PluginBridge.responseDispatcher(responseJSON: json)
            XCTAssertTrue(dispatcher.contains("request-42"))
            XCTAssertTrue(dispatcher.contains("ainto-bridge-response"))
            XCTAssertFalse(dispatcher.contains("\"response\":"))
            XCTAssertTrue(dispatcher.contains("\"status\":\"\(response.status.rawValue)\""))
            XCTAssertTrue(dispatcher.contains("\"code\":\"\(response.code.rawValue)\""))
        }
    }

    func testNetworkFetchReturnsAsyncSuccessAndPreservesRequestID() {
        let store = PluginPermissionStore()
        store.setDeclared([.network], for: pluginID)
        XCTAssertTrue(store.grant(.network, to: pluginID))
        let capability = FetchCapability(result: .success("network body"))
        let broker = PluginAPIBroker(permissionStore: store, networkDomains: [pluginID: ["api.example.com"]], capabilities: capability)
        let expectation = expectation(description: "network response")
        let request = PluginBridgeRequest(id: "network-request", api: .networkFetch, pluginID: pluginID, payload: ["url": "https://api.example.com/data"])
        broker.handle(request, sessionPluginID: pluginID) { response in
            XCTAssertEqual(request.id, "network-request")
            XCTAssertEqual(response, PluginBridgeResponse(status: .success, code: .none, value: "network body"))
            expectation.fulfill()
        }
        XCTAssertTrue(capability.didStartFetch)
        wait(for: [expectation], timeout: 1)
    }

    func testNetworkFetchReturnsAsyncTransportFailure() {
        let store = PluginPermissionStore()
        store.setDeclared([.network], for: pluginID)
        XCTAssertTrue(store.grant(.network, to: pluginID))
        let broker = PluginAPIBroker(permissionStore: store, networkDomains: [pluginID: ["api.example.com"]], capabilities: FetchCapability(result: .failure(TestError.failed)))
        let expectation = expectation(description: "network failure")
        let request = PluginBridgeRequest(id: "network-request", api: .networkFetch, pluginID: pluginID, payload: ["url": "https://api.example.com/data"])
        broker.handle(request, sessionPluginID: pluginID) { response in
            XCTAssertEqual(response.status, .rejected)
            XCTAssertEqual(response.code, .unsupported)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
    }

    private enum TestError: Error { case failed }

    private final class FetchCapability: PluginCapabilityProviding {
        let result: Result<String, Error>
        private(set) var didStartFetch = false
        init(result: Result<String, Error>) { self.result = result }
        func clipboardText() -> String? { nil }
        func writeClipboard(_ text: String) {}
        func showNotification(title: String, body: String) {}
        func openURL(_ url: URL) {}
        func theme() -> String { "light" }
        func language() -> String { "en" }
        func resizeWindow(width: CGFloat, height: CGFloat) -> PluginHostSize { PluginHostSize(width: width, height: height) }
        func fetch(url: URL, completion: @escaping (Result<String, Error>) -> Void) {
            didStartFetch = true
            completion(result)
        }
    }

    private func makeBroker(declared: [PluginPermission]) -> PluginAPIBroker {
        let store = PluginPermissionStore()
        store.setDeclared(declared, for: pluginID)
        return PluginAPIBroker(permissionStore: store)
    }
}
