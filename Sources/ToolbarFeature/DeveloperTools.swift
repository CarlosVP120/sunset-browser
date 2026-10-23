import SwiftUI
import AppKit
import BrowserCore
import BrowserEngine
import BrowserUI

// MARK: - Barra en modo desarrollador

public extension DeveloperMode {
    /// Amarillo de obra (el de Arc): la etiqueta DEV y el borde de las pestañas.
    static let color = Color(red: 1.0, green: 0.82, blue: 0.22)
}

/// Rayas diagonales de la barra en modo desarrollador (como en Arc): se nota de un vistazo
/// que estás en tu sitio local y no en producción.
struct DeveloperStripes: View {
    @Environment(\.spaceTheme) private var theme

    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 14
            var path = Path()
            var x: CGFloat = -size.height
            while x < size.width + size.height {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += spacing
            }
            context.stroke(path, with: .color(Color(theme.title).opacity(theme.isDark ? 0.07 : 0.06)), lineWidth: 5)
        }
        .allowsHitTesting(false)
    }
}

/// La dirección completa (con puerto y ruta), alineada a la izquierda y en monoespaciada.
struct DeveloperAddress: View {
    let browser: Browser
    let tab: BrowserTab
    @State private var isHovering = false
    @Environment(\.spaceTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Button { browser.perform(.toggleDeveloperMode) } label: {
                Text("DEV")
                    .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                    .kerning(0.6)
                    .foregroundStyle(Color(red: 0.16, green: 0.12, blue: 0.0))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(DeveloperMode.color))
            }
            .buttonStyle(.plain)
            .tooltip("Salir del modo desarrollador en este sitio")

            Button { browser.editCurrentTab() } label: {
                Text(tab.url?.absoluteString ?? "")
                    .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(theme.title).opacity(isHovering ? 1 : 0.85))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .tooltip("Editar dirección", shortcut: "⌘L")
        }
    }
}

/// Herramientas del modo desarrollador, a la derecha de la barra.
struct DeveloperToolbarButtons: View {
    let browser: Browser
    let tab: BrowserTab

    var body: some View {
        HStack(spacing: 2) {
            Button { browser.perform(.copyURL) } label: { Image(systemName: "link") }
                .tooltip("Copiar URL", shortcut: "⇧⌘C")

            Divider().frame(height: 16).padding(.horizontal, 4)

            Button { browser.perform(.forceReload) } label: { Image(systemName: "arrow.clockwise.circle") }
                .tooltip("Recarga forzada (sin caché)", shortcut: "⇧⌘R")
            Button { browser.perform(.capturePage) } label: { Image(systemName: "camera") }
                .tooltip("Capturar página")

            Divider().frame(height: 16).padding(.horizontal, 4)

            Image(systemName: browser.responsiveWidth == nil ? "iphone" : "iphone.gen3")
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.primary.opacity(browser.responsiveWidth == nil ? 0 : 0.12)))
                .contentShape(Rectangle())
                .nativeMenuOnClick { responsiveMenu }
                .tooltip("Vista móvil")

            Button { browser.showsConsole.toggle() } label: {
                Image(systemName: "terminal")
                    .overlay(alignment: .topTrailing) {
                        if tab.console.unseenErrors > 0 {
                            Text("\(min(tab.console.unseenErrors, 99))")
                                .font(.system(size: 8.5, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 3.5)
                                .frame(minWidth: 13, minHeight: 13)
                                .background(Capsule().fill(Color.red))
                                .offset(x: 8, y: -7)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
            }
            .tooltip(browser.showsConsole ? "Ocultar consola" : "Consola", shortcut: "⌥⌘J")

            Image(systemName: "globe")
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
                .nativeMenuOnClick { otherBrowsersMenu }
                .tooltip("Abrir en otro navegador")

            Button { tab.page?.showInspector(selectingElement: true) } label: { Image(systemName: "scope") }
                .tooltip("Inspeccionar elemento", shortcut: "⌥⌘C")
        }
        .animation(Theme.pressSpring, value: tab.console.unseenErrors)
    }

    private var responsiveMenu: [MenuEntry] {
        let sizes: [(String, Double?)] = [("iPhone (390 px)", 390), ("iPhone Pro Max (430 px)", 430), ("iPad (820 px)", 820),
                                          ("Portátil (1280 px)", 1280), ("Ancho completo", nil)]
        return sizes.map { name, width in
            .button(name, checked: browser.responsiveWidth == width) {
                withAnimation(Theme.spring) { browser.responsiveWidth = width }
            }
        }
    }

    /// Navegadores instalados, para probar el sitio en ellos.
    private var otherBrowsersMenu: [MenuEntry] {
        guard let url = tab.url else { return [] }
        let candidates = ["com.apple.Safari", "com.google.Chrome", "org.mozilla.firefox", "company.thebrowser.Browser",
                          "com.brave.Browser", "com.microsoft.edgemac", "com.apple.SafariTechnologyPreview"]
        let apps = candidates.compactMap { id in NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) }
        guard !apps.isEmpty else { return [.button("No hay otros navegadores instalados", enabled: false) {}] }
        return apps.map { app in
            .button(FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")) {
                NSWorkspace.shared.open([url], withApplicationAt: app, configuration: .init())
            }
        }
    }
}

// MARK: - Consola

/// Consola bajo la página: lo que escribe la página, sus errores, las peticiones que fallan, y
/// una línea para ejecutar JavaScript. Para todo lo demás (Elementos, Red…), el inspector web.
public struct ConsolePanel: View {
    let browser: Browser
    let tab: BrowserTab
    @State private var input = ""
    @State private var filter: Filter = .all
    @State private var history: [String] = []
    @State private var historyIndex: Int?
    @FocusState private var isInputFocused: Bool

    enum Filter: String, CaseIterable {
        case all = "Todo", errors = "Errores", warnings = "Avisos", logs = "Logs"
    }

    public init(browser: Browser, tab: BrowserTab) {
        self.browser = browser
        self.tab = tab
    }

    private var messages: [ConsoleMessage] {
        tab.console.messages.filter { message in
            switch filter {
            case .all: true
            case .errors: message.level == .error
            case .warnings: message.level == .warn
            case .logs: [.log, .info, .debug, .result].contains(message.level)
            }
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if messages.isEmpty {
                            Text(tab.console.messages.isEmpty ? "La consola está vacía. Lo que la página escriba con console.log aparecerá aquí."
                                                              : "Nada con este filtro.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .padding(12)
                        }
                        ForEach(messages) { message in
                            ConsoleRow(message: message)
                                .id(message.id)
                        }
                    }
                }
                .onChange(of: tab.console.messages.last?.id) { _, last in
                    if let last { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(last, anchor: .bottom) } }
                }
            }
            Divider().opacity(0.5)
            prompt
        }
        .background(Color(white: 0.11))
        .environment(\.colorScheme, .dark)
        .onAppear {
            tab.markConsoleSeen()
            isInputFocused = true
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "terminal").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            Text("Consola").font(.system(size: 12, weight: .semibold))
            Picker("", selection: $filter) {
                ForEach(Filter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 240)
            Spacer()
            Button("Limpiar") { tab.clearConsole() }
                .buttonStyle(.borderless)
                .font(.system(size: 11.5))
                .keyboardShortcut("k", modifiers: .command)
            Button("Inspector web") { tab.page?.showInspector(selectingElement: false) }
                .buttonStyle(.borderless)
                .font(.system(size: 11.5))
            Button { withAnimation(Theme.spring) { browser.showsConsole = false } } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.borderless)
            .tooltip("Cerrar consola", shortcut: "⌥⌘J")
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
    }

    private var prompt: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Color(red: 0.4, green: 0.7, blue: 1))
            TextField("Escribe JavaScript y pulsa ↩︎ (p. ej. document.title)", text: $input)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .focused($isInputFocused)
                .onSubmit(run)
                .onKeyPress(.upArrow) { stepHistory(-1); return .handled }
                .onKeyPress(.downArrow) { stepHistory(1); return .handled }
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
    }

    private func run() {
        let code = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        history.append(code)
        historyIndex = nil
        input = ""
        Task { await tab.runInConsole(code) }
    }

    private func stepHistory(_ step: Int) {
        guard !history.isEmpty else { return }
        let next = (historyIndex ?? history.count) + step
        guard next >= 0 else { return }
        if next >= history.count {
            historyIndex = nil
            input = ""
        } else {
            historyIndex = next
            input = history[next]
        }
    }
}

private struct ConsoleRow: View {
    let message: ConsoleMessage

    private var color: Color {
        switch message.level {
        case .error: Color(red: 1, green: 0.45, blue: 0.45)
        case .warn: Color(red: 1, green: 0.8, blue: 0.35)
        case .info: Color(red: 0.55, green: 0.78, blue: 1)
        case .debug: Color.white.opacity(0.55)
        case .result: Color(red: 0.6, green: 0.9, blue: 0.65)
        case .log: Color.white.opacity(0.88)
        }
    }

    private var symbol: String? {
        switch message.level {
        case .error: "xmark.octagon.fill"
        case .warn: "exclamationmark.triangle.fill"
        case .info: "info.circle.fill"
        case .result: "arrow.turn.down.left"
        default: nil
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol ?? "circle")
                .font(.system(size: 9.5))
                .opacity(symbol == nil ? 0 : 1)
                .frame(width: 12)
            Text(message.text)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let source = message.source {
                Text(source).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.secondary)
            }
            Text(message.date, format: .dateTime.hour().minute().second())
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(message.level == .error ? Color.red.opacity(0.08) : message.level == .warn ? Color.yellow.opacity(0.06) : .clear)
        .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.05)).frame(height: 1) }
    }
}
