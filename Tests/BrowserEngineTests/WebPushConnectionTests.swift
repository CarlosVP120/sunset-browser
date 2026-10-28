import Network
import XCTest
@testable import BrowserEngine

@MainActor
final class WebPushConnectionTests: XCTestCase {
    /// Tras dormir el Mac, la conexión puede seguir "abierta" sin que llegue nada ni dé error:
    /// si el servidor deja de contestar a los pings, Sunset abre otra.
    func testReconnectsWhenTheServerStopsAnswering() async throws {
        let server = try SilentWebSocketServer()
        let port = try await server.start()

        let file = FileManager.default.temporaryDirectory.appending(path: "push-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let keys = try JSONSerialization.jsonObject(with: JSONEncoder().encode(WebPushKeys.generate()))
        let state: [String: Any] = ["uaid": "test", "subscriptions": [[
            "channelID": "c1", "scope": "https://mail.example/", "endpoint": "https://push.example/c1", "keys": keys,
        ]]]
        try JSONSerialization.data(withJSONObject: state).write(to: file)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "push-\(UUID().uuidString)"))
        defaults.set("ws://127.0.0.1:\(port)/", forKey: "pushServerURL")

        let push = WebPushService(fileURL: file, defaults: defaults)
        push.pingInterval = .milliseconds(300)
        push.pongTimeout = .milliseconds(300)
        push.start()

        for _ in 0..<50 where server.connections < 2 {
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertGreaterThanOrEqual(server.connections, 2)
        server.stop()
    }
}

/// Acepta conexiones WebSocket y nunca contesta (ni a los pings): una conexión muerta.
@MainActor
private final class SilentWebSocketServer {
    private let listener: NWListener
    private var open: [NWConnection] = []
    private(set) var connections = 0

    init() throws {
        let options = NWProtocolWebSocket.Options()
        options.autoReplyPing = false
        let parameters = NWParameters.tcp
        parameters.defaultProtocolStack.applicationProtocols.insert(options, at: 0)
        listener = try NWListener(using: parameters, on: .any)
    }

    func start() async throws -> UInt16 {
        listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated {
                self?.connections += 1
                self?.open.append(connection)
                connection.start(queue: .main)
            }
        }
        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [listener] state in
                switch state {
                case .ready: continuation.resume(returning: listener.port?.rawValue ?? 0)
                case .failed(let error): continuation.resume(throwing: error)
                default: break
                }
            }
            listener.start(queue: .main)
        }
    }

    func stop() {
        open.forEach { $0.cancel() }
        listener.cancel()
    }
}
