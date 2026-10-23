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
        DragPayload.load(from: info) { payload in
            withAnimation(Theme.spring) {
                switch payload {
                case .tab(let id):
                    guard let tab = browser.tab(withID: id), let target = location(zone) else { return }
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
        return true
    }

    private func update(_ info: DropInfo) {
        let newZone = currentZone(info)
        if newZone != zone { withAnimation(Theme.hoverIn) { zone = newZone } }
    }

    private func currentZone(_ info: DropInfo) -> DropZone {
        let position = horizontal ? info.location.x / max(size.width, 1) : info.location.y / max(size.height, 1)
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
    @State private var size: CGSize = .zero

    func body(content: Content) -> some View {
        content
            .background(GeometryReader { proxy in
                Color.clear
                    .onAppear { size = proxy.size }
                    .onChange(of: proxy.size) { size = proxy.size }
            })
            .overlay(DropIndicator(zone: zone, horizontal: horizontal))
            .onDrop(of: [.text, .url], delegate: makeDelegate(size, $zone))
    }
}
