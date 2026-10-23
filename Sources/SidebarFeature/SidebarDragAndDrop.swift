import SwiftUI
import UniformTypeIdentifiers
import BrowserCore
import BrowserUI

/// Lo que se arrastra: una pestaña, una carpeta, o un enlace desde fuera de la app.
enum DragPayload {
    case tab(UUID)
    case folder(UUID)
    case url(URL)

    private static let tabPrefix = "minavegador-tab:"
    private static let folderPrefix = "minavegador-folder:"

    @MainActor
    static func provider(for tab: BrowserTab) -> NSItemProvider {
        let provider = NSItemProvider(object: "\(tabPrefix)\(tab.id.uuidString)" as NSString)
        // Al soltarla en otra app (Notas, Mail…) llega como enlace.
        if let url = tab.url { provider.registerObject(url as NSURL, visibility: .all) }
        return provider
    }

    static func provider(for folder: Folder.ID) -> NSItemProvider {
        NSItemProvider(object: "\(folderPrefix)\(folder.uuidString)" as NSString)
    }

    static func parse(_ string: String) -> DragPayload? {
        if string.hasPrefix(tabPrefix) { return UUID(uuidString: String(string.dropFirst(tabPrefix.count))).map { .tab($0) } }
        if string.hasPrefix(folderPrefix) {
            return UUID(uuidString: String(string.dropFirst(folderPrefix.count))).map { .folder($0) }
        }
        if let url = URL(string: string), url.scheme == "http" || url.scheme == "https" { return .url(url) }
        return nil
    }

    static func load(from info: DropInfo, completion: @escaping @MainActor (DragPayload) -> Void) {
        if let provider = info.itemProviders(for: [.text]).first {
            _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let string = object as? String, let payload = parse(string) else { return }
                DispatchQueue.main.async { MainActor.assumeIsolated { completion(payload) } }
            }
        } else if let provider = info.itemProviders(for: [.url]).first {
            _ = provider.loadObject(ofClass: NSURL.self) { object, _ in
                guard let url = object as? URL else { return }
                DispatchQueue.main.async { MainActor.assumeIsolated { completion(.url(url)) } }
            }
        }
    }
}

/// En qué parte de una fila está el cursor al arrastrar.
enum DropZone: Equatable {
    case before, inside, after
}

/// Recibe lo que se suelta sobre una fila y lo coloca antes, después o dentro.
struct SidebarDropDelegate: DropDelegate {
    let browser: Browser
    /// Si la fila acepta cosas dentro (carpetas).
    var acceptsInside = false
    /// Si la fila es horizontal (favoritos): antes/después según la x.
    var horizontal = false
    var size: CGSize
    /// Dónde va una pestaña o un enlace según la zona.
    let location: @MainActor (DropZone) -> DropLocation?
    /// Índice en la sección fijada para una carpeta arrastrada (nil si aquí no caben carpetas).
    var folderIndex: @MainActor (DropZone) -> Int? = { _ in nil }
    /// En vez de colocarla en una posición, hace algo con la pestaña (soltarla en el icono de un espacio).
    var onTab: (@MainActor (BrowserTab) -> Void)? = nil
    @Binding var zone: DropZone?

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.text, .url])
    }

    func dropEntered(info: DropInfo) {
        update(info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        update(info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        withAnimation(Theme.hoverOut) { zone = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        let zone = currentZone(info)
        withAnimation(Theme.hoverOut) { self.zone = nil }
        DragPayload.load(from: info) { payload in apply(payload, zone: zone) }
        return true
    }

    /// ¿Esta fila acepta lo que se arrastra? (Las carpetas solo caben entre las fijadas.)
    @MainActor
    func accepts(_ payload: DragPayload, zone: DropZone) -> Bool {
        if case .folder = payload { return folderIndex(zone) != nil }
        if onTab != nil, case .tab = payload { return true }
        return location(zone) != nil
    }

    /// Coloca lo soltado según la zona.
    @MainActor
    func apply(_ payload: DragPayload, zone: DropZone) {
        withAnimation(Theme.spring) {
            switch payload {
            case .tab(let id):
                guard let tab = browser.tab(withID: id) else { return }
                if let onTab { return onTab(tab) }
                guard let target = location(zone) else { return }
                browser.move(tab, to: target)
            case .folder(let id):
                guard let folder = browser.folder(withID: id), let index = folderIndex(zone) else { return }
                browser.move(folder, toPinnedIndex: index)
            case .url(let url):
                guard let target = location(zone) else { return }
                browser.open(url, at: target)
            }
        }
    }

    private func update(_ info: DropInfo) {
        let newZone = currentZone(info)
        if newZone != zone { withAnimation(Theme.hoverIn) { zone = newZone } }
    }

    private func currentZone(_ info: DropInfo) -> DropZone {
        zone(at: info.location)
    }

    /// Zona según un punto dentro de la fila.
    func zone(at point: CGPoint) -> DropZone {
        let position = horizontal ? point.x / max(size.width, 1) : point.y / max(size.height, 1)
        if acceptsInside {
            if position < 0.28 { return .before }
            if position > 0.72 { return .after }
            return .inside
        }
        return position < 0.5 ? .before : .after
    }
}

/// Línea de inserción o resaltado que se ve al arrastrar sobre una fila.
struct DropIndicator: View {
    let zone: DropZone?
    var horizontal = false
    @Environment(\.spaceTheme) private var theme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .fill(Color(theme.accent).opacity(0.25))
                .opacity(zone == .inside ? 1 : 0)
            if zone == .before || zone == .after {
                Capsule()
                    .fill(Color(theme.accent))
                    .frame(width: horizontal ? 2.5 : nil, height: horizontal ? nil : 2.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: horizontal ? (zone == .before ? .leading : .trailing)
                                                 : (zone == .before ? .top : .bottom))
                    .offset(x: horizontal ? (zone == .before ? -4 : 4) : 0,
                            y: horizontal ? 0 : (zone == .before ? -1.5 : 1.5))
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
    }
}

extension View {
    /// Hace la vista arrastrable y receptora de soltados en la barra lateral.
    func sidebarDropTarget(_ delegate: @escaping (CGSize, Binding<DropZone?>) -> SidebarDropDelegate,
                           horizontal: Bool = false) -> some View {
        modifier(SidebarDropTargetModifier(makeDelegate: delegate, horizontal: horizontal))
    }
}

private struct SidebarDropTargetModifier: ViewModifier {
    let makeDelegate: (CGSize, Binding<DropZone?>) -> SidebarDropDelegate
    let horizontal: Bool
    @State private var zone: DropZone?
    /// Tamaño y posición en una caja, no en @State: cambian en cada fotograma mientras la barra
    /// se anima, y como @State obligaban a redibujar cada fila en cada fotograma.
    @State private var box = SizeBox()
    @State private var id = UUID()
    @Environment(SidebarDrag.self) private var drag

    final class SizeBox {
        var size: CGSize = .zero
    }

    func body(content: Content) -> some View {
        let dragZone = drag.hovered?.id == id ? drag.hovered?.zone : nil
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(SidebarDrag.space)) } action: { register($0) }
            .overlay(DropIndicator(zone: zone ?? dragZone, horizontal: horizontal))
            // Lo que llega desde fuera de la app (enlaces de otras apps).
            .onDrop(of: [.text, .url], delegate: LiveDropDelegate(box: box, zone: $zone, make: makeDelegate))
            .onDisappear { drag.unregister(id) }
    }

    private func register(_ frame: CGRect) {
        box.size = frame.size
        let makeDelegate = makeDelegate
        drag.register(id, frame: frame) { size in makeDelegate(size, .constant(nil)) }
    }
}

/// Crea el delegado con el tamaño actual en cada evento (el tamaño vive en una caja que no redibuja).
private struct LiveDropDelegate: DropDelegate {
    let box: SidebarDropTargetModifier.SizeBox
    @Binding var zone: DropZone?
    let make: (CGSize, Binding<DropZone?>) -> SidebarDropDelegate

    private var current: SidebarDropDelegate { make(box.size, $zone) }

    func validateDrop(info: DropInfo) -> Bool { current.validateDrop(info: info) }
    func dropEntered(info: DropInfo) { current.dropEntered(info: info) }
    func dropUpdated(info: DropInfo) -> DropProposal? { current.dropUpdated(info: info) }
    func dropExited(info: DropInfo) { current.dropExited(info: info) }
    func performDrop(info: DropInfo) -> Bool { current.performDrop(info: info) }
}

// MARK: - Arrastre dentro de la barra lateral

/// Arrastrar pestañas y carpetas dentro de la barra lateral, como en Arc: lo que arrastras
/// sigue al cursor y una línea marca dónde caerá (favoritos, fijadas, carpetas, Hoy o los
/// iconos de espacios). Funciona con el gesto del ratón (no con el portapapeles de arrastre),
/// así responde al instante y no depende de dónde empiece el clic.
@MainActor
@Observable
final class SidebarDrag {
    static let space = "sidebar-drag"

    struct Ghost {
        let pageURL: URL?
        let faviconURL: URL?
        let title: String
        let symbol: String?
    }

    private(set) var payload: DragPayload?
    private(set) var ghost: Ghost?
    private(set) var location: CGPoint = .zero
    private(set) var hovered: (id: UUID, zone: DropZone)?

    @ObservationIgnored private var targets: [UUID: (frame: CGRect, make: (CGSize) -> SidebarDropDelegate)] = [:]

    var isDragging: Bool { payload != nil }

    func register(_ id: UUID, frame: CGRect, make: @escaping (CGSize) -> SidebarDropDelegate) {
        targets[id] = (frame, make)
    }

    func unregister(_ id: UUID) {
        targets[id] = nil
    }

    func move(_ payload: DragPayload, ghost: Ghost, to point: CGPoint) {
        if self.payload == nil {
            withAnimation(Theme.pressSpring) {
                self.payload = payload
                self.ghost = ghost
            }
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        location = point
        updateHovered()
    }

    func end() {
        defer {
            withAnimation(Theme.spring) {
                payload = nil
                ghost = nil
                hovered = nil
            }
        }
        guard let payload, let hovered, let target = targets[hovered.id] else { return }
        target.make(target.frame.size).apply(payload, zone: hovered.zone)
    }

    private func updateHovered() {
        guard let payload else { return }
        // La fila más pequeña bajo el cursor (una pestaña dentro de una carpeta antes que la carpeta).
        let candidates = targets.filter { $0.value.frame.insetBy(dx: -2, dy: -2).contains(location) }
            .sorted { $0.value.frame.width * $0.value.frame.height < $1.value.frame.width * $1.value.frame.height }
        var next: (id: UUID, zone: DropZone)?
        for (id, target) in candidates {
            let delegate = target.make(target.frame.size)
            let zone = delegate.zone(at: CGPoint(x: location.x - target.frame.minX, y: location.y - target.frame.minY))
            if delegate.accepts(payload, zone: zone) {
                next = (id, zone)
                break
            }
        }
        if next?.id != hovered?.id || next?.zone != hovered?.zone {
            if next != nil { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
            withAnimation(Theme.hoverIn) { hovered = next }
        }
    }
}

extension View {
    /// Permite arrastrar esta fila dentro de la barra lateral.
    func sidebarDraggable(_ payload: DragPayload, ghost: @escaping () -> SidebarDrag.Ghost) -> some View {
        modifier(SidebarDraggableModifier(payload: payload, ghost: ghost))
    }
}

private struct SidebarDraggableModifier: ViewModifier {
    let payload: DragPayload
    let ghost: () -> SidebarDrag.Ghost
    @Environment(SidebarDrag.self) private var drag

    private var isBeingDragged: Bool {
        switch (drag.payload, payload) {
        case (.tab(let a), .tab(let b)), (.folder(let a), .folder(let b)): a == b
        default: false
        }
    }

    func body(content: Content) -> some View {
        content
            .opacity(isBeingDragged ? 0.35 : 1)
            .scaleEffect(isBeingDragged ? 0.97 : 1)
            .animation(Theme.pressSpring, value: isBeingDragged)
            .simultaneousGesture(
                DragGesture(minimumDistance: 5, coordinateSpace: .named(SidebarDrag.space))
                    .onChanged { value in drag.move(payload, ghost: ghost(), to: value.location) }
                    .onEnded { _ in drag.end() }
            )
    }
}

/// Lo que se ve bajo el cursor mientras arrastras: la pestaña "levantada", con sombra.
struct DragGhost: View {
    let ghost: SidebarDrag.Ghost
    @Environment(\.spaceTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            if let symbol = ghost.symbol {
                Image(systemName: symbol).font(.system(size: 12)).frame(width: 16)
            } else {
                FaviconView(pageURL: ghost.pageURL, faviconURL: ghost.faviconURL, size: 16)
            }
            Text(ghost.title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(Color(theme.title))
        .padding(.horizontal, 10)
        .frame(height: 34)
        .frame(maxWidth: 220, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .fill(Color(theme.focus))
                .shadow(color: .black.opacity(0.28), radius: 14, y: 8)
        )
        .rotationEffect(.degrees(-1.5))
        .allowsHitTesting(false)
    }
}
