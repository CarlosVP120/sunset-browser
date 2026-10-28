import AppKit
import Network

/// Una suscripción push de un sitio (lo que devuelve `pushManager.subscribe()`).
struct WebPushSubscription: Codable, Equatable {
    /// El canal en el servidor de push.
    var channelID: String
    /// El ámbito del service worker que recibe los mensajes.
    var scope: URL
    /// El perfil (almacén de datos web) del service worker; `nil` es el principal.
    var profile: UUID?
    /// La dirección a la que el sitio envía los mensajes.
    var endpoint: String
    var keys: WebPushKeys
    /// La clave VAPID del sitio, en base64 url (para saber si una nueva suscripción es la misma).
    var applicationServerKey: String?
}

/// Web Push para Sunset con el servicio de push de Mozilla (el de Firefox, "autopush"): WebKit solo
/// sabe hablar con el de Safari, que es exclusivo de Apple. Sunset mantiene abierta una conexión
/// WebSocket mientras está abierto; los sitios envían sus mensajes cifrados a la dirección de cada
/// suscripción y el servidor los reenvía por esa conexión (si Sunset está cerrado, los guarda hasta
/// que vuelve, según la caducidad que pida el sitio). Sunset los descifra (`WebPushKeys`) y se los
/// entrega al service worker del sitio.
///
/// El servidor se puede cambiar con `defaults write com.carlosvp.minavegador pushServerURL wss://…`
/// (por ejemplo, un autopush propio).
@MainActor
final class WebPushService {
    /// Entrega un mensaje (ya descifrado; `nil` si vino vacío) al service worker de la suscripción.
    var deliver: (@MainActor (WebPushSubscription, Data?) -> Void)?

    private struct State: Codable {
        var uaid: String?
        var subscriptions: [WebPushSubscription] = []
    }

    private var state: State
    private let fileURL: URL?
    private let serverURL: URL

    private var socket: URLSessionWebSocketTask?
    private var isReady = false
    private var reconnectDelay: TimeInterval = 1
    private var reconnectTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var pathMonitor: NWPathMonitor?
    private var wakeObserver: NSObjectProtocol?
    /// Cada cuánto se comprueba la conexión, y cuánto se espera la respuesta (más cortos en los tests).
    var pingInterval: Duration = .seconds(120)
    var pongTimeout: Duration = .seconds(20)
    /// Altas pedidas que esperan la respuesta del servidor (por canal).
    private var pendingRegistrations: [String: CheckedContinuation<String, Error>] = [:]
    /// Esperando a que la conexión esté lista para mandar algo.
    private var readyWaiters: [CheckedContinuation<Void, Error>] = []

    enum PushError: LocalizedError {
        case unavailable(String)
        var errorDescription: String? {
            switch self { case .unavailable(let reason): reason }
        }
    }

    init(fileURL: URL? = WebPushService.standardFileURL, defaults: UserDefaults = .standard) {
        self.fileURL = fileURL
        serverURL = defaults.string(forKey: "pushServerURL").flatMap(URL.init(string:))
            ?? URL(string: "wss://push.services.mozilla.com/")!
        state = fileURL.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode(State.self, from: $0) } ?? State()
    }

    nonisolated static var standardFileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: "MiNavegador/PushSubscriptions.json")
    }

    /// Conecta al arrancar si hay suscripciones: así llegan los mensajes guardados mientras estaba cerrado.
    func start() {
        guard !state.subscriptions.isEmpty else { return }
        connect()
        watchNetwork()
    }

    // MARK: Suscripciones

    func subscription(forScope scope: URL, profile: UUID?) -> WebPushSubscription? {
        state.subscriptions.first { $0.scope == scope && $0.profile == profile }
    }

    func subscribe(scope: URL, profile: UUID?, applicationServerKey: String?) async throws -> WebPushSubscription {
        if let existing = subscription(forScope: scope, profile: profile) {
            if existing.applicationServerKey == applicationServerKey { return existing }
            // Otra clave del sitio: la suscripción anterior deja de valer (como en Chrome).
            unsubscribe(scope: scope, profile: profile)
        }
        connect()
        watchNetwork()
        try await waitUntilReady()
        let channelID = UUID().uuidString.lowercased()
        var message: [String: Any] = ["messageType": "register", "channelID": channelID]
        if let applicationServerKey { message["key"] = applicationServerKey }
        let endpoint = try await withCheckedThrowingContinuation { continuation in
            pendingRegistrations[channelID] = continuation
            send(message)
        }
        let subscription = WebPushSubscription(channelID: channelID, scope: scope, profile: profile, endpoint: endpoint,
                                               keys: .generate(), applicationServerKey: applicationServerKey)
        state.subscriptions.append(subscription)
        save()
        return subscription
    }

    @discardableResult
    func unsubscribe(scope: URL, profile: UUID?) -> Bool {
        guard let index = state.subscriptions.firstIndex(where: { $0.scope == scope && $0.profile == profile }) else { return false }
        let subscription = state.subscriptions.remove(at: index)
        save()
        if isReady { send(["messageType": "unregister", "channelID": subscription.channelID]) }
        return true
    }

    /// Al bloquear un sitio o borrar sus datos: fuera sus suscripciones.
    func unsubscribe(origin: String) {
        for subscription in state.subscriptions where WebNotifications.origin(subscription.scope) == origin {
            unsubscribe(scope: subscription.scope, profile: subscription.profile)
        }
    }

    private func save() {
        guard let fileURL, let data = try? JSONEncoder().encode(state) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Contiene las claves privadas de las suscripciones: solo legible por el usuario.
        FileManager.default.createFile(atPath: fileURL.path, contents: data, attributes: [.posixPermissions: 0o600])
    }

    // MARK: Conexión

    private func connect() {
        guard socket == nil else { return }
        reconnectTask?.cancel()
        let socket = URLSession.shared.webSocketTask(with: serverURL)
        self.socket = socket
        socket.resume()
        var hello: [String: Any] = ["messageType": "hello", "use_webpush": true]
        if let uaid = state.uaid { hello["uaid"] = uaid }
        send(hello)
        receive(on: socket)
        pingTask?.cancel()
        // Un ping cada pocos minutos mantiene viva la conexión (y detecta si se cayó sin avisar).
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let interval = self?.pingInterval else { return }
                try? await Task.sleep(for: interval)
                guard let self, self.socket === socket else { return }
                await self.checkAlive(socket)
            }
        }
    }

    /// Un ping que no contesta en 20 segundos es una conexión muerta: tras dormir el Mac o cambiar
    /// de red, el WebSocket puede seguir "abierto" sin recibir nada ni dar error nunca.
    private func checkAlive(_ socket: URLSessionWebSocketTask) async {
        let answered = Flag()
        socket.sendPing { [weak self] error in
            Task { @MainActor in
                answered.value = true
                if error != nil { self?.disconnected(socket) }
            }
        }
        try? await Task.sleep(for: pongTimeout)
        if !answered.value { disconnected(socket) }
    }

    @MainActor private final class Flag { var value = false }

    private func send(_ message: [String: Any]) {
        guard let socket, let data = try? JSONSerialization.data(withJSONObject: message),
              let text = String(data: data, encoding: .utf8) else { return }
        socket.send(.string(text)) { [weak self] error in
            if error != nil { Task { @MainActor in self?.disconnected(socket) } }
        }
    }

    private func receive(on socket: URLSessionWebSocketTask) {
        socket.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.socket === socket else { return }
                switch result {
                case .success(.string(let text)):
                    self.handle(text)
                    self.receive(on: socket)
                case .success:
                    self.receive(on: socket)
                case .failure:
                    self.disconnected(socket)
                }
            }
        }
    }

    private func handle(_ text: String) {
        guard let message = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any],
              let type = message["messageType"] as? String else { return }
        switch type {
        case "hello":
            guard message["status"] as? Int == 200, let uaid = message["uaid"] as? String else { return failAll("El servidor de push no respondió") }
            if state.uaid != uaid {
                // Identidad nueva: las suscripciones anteriores ya no reciben nada.
                if state.uaid != nil { state.subscriptions.removeAll() }
                state.uaid = uaid
                save()
            }
            isReady = true
            reconnectDelay = 1
            readyWaiters.forEach { $0.resume() }
            readyWaiters.removeAll()
        case "register":
            guard let channelID = message["channelID"] as? String,
                  let continuation = pendingRegistrations.removeValue(forKey: channelID) else { return }
            if message["status"] as? Int == 200, let endpoint = message["pushEndpoint"] as? String {
                continuation.resume(returning: endpoint)
            } else {
                continuation.resume(throwing: PushError.unavailable("El servidor de push rechazó la suscripción"))
            }
        case "notification":
            guard let channelID = message["channelID"] as? String, let version = message["version"] else { return }
            send(["messageType": "ack", "updates": [["channelID": channelID, "version": version]]])
            guard let subscription = state.subscriptions.first(where: { $0.channelID == channelID }) else {
                // Un canal que ya no es de nadie: que el servidor deje de enviarlo.
                return send(["messageType": "unregister", "channelID": channelID])
            }
            if let encoded = message["data"] as? String {
                // Solo "aes128gcm" (el estándar actual); el antiguo "aesgcm" no se descifra.
                guard let body = Data(base64URLEncoded: encoded), let data = try? subscription.keys.decrypt(body) else { return }
                deliver?(subscription, data)
            } else {
                deliver?(subscription, nil)
            }
        default:
            break
        }
    }

    private func waitUntilReady() async throws {
        if isReady { return }
        try await withCheckedThrowingContinuation { readyWaiters.append($0) }
    }

    private func failAll(_ reason: String) {
        readyWaiters.forEach { $0.resume(throwing: PushError.unavailable(reason)) }
        readyWaiters.removeAll()
        pendingRegistrations.values.forEach { $0.resume(throwing: PushError.unavailable(reason)) }
        pendingRegistrations.removeAll()
    }

    /// Se cayó la conexión: se reintenta con esperas crecientes (hasta 5 minutos).
    private func disconnected(_ socket: URLSessionWebSocketTask) {
        guard self.socket === socket else { return }
        socket.cancel(with: .goingAway, reason: nil)
        self.socket = nil
        isReady = false
        failAll("Sin conexión con el servidor de push")
        guard !state.subscriptions.isEmpty else { return }
        let delay = reconnectDelay
        reconnectDelay = min(reconnectDelay * 2, 300)
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.connect()
        }
    }

    /// Al volver o cambiar la red, o al despertar el Mac, reconecta enseguida en vez de esperar al
    /// reintento, o comprueba que la conexión que hay sigue viva.
    private func watchNetwork() {
        guard pathMonitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in self?.networkMayHaveChanged() }
        }
        monitor.start(queue: .main)
        pathMonitor = monitor
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.networkMayHaveChanged() }
        }
    }

    private func networkMayHaveChanged() {
        guard !state.subscriptions.isEmpty else { return }
        reconnectDelay = 1
        if let socket {
            Task { await checkAlive(socket) }
        } else {
            connect()
        }
    }
}
