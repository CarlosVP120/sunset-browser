import SwiftUI
import BrowserCore
import BrowserUI

/// El Command Bar de Arc: un panel flotante para abrir, buscar, cambiar de pestaña y ejecutar acciones.
/// ⌘T lo abre para una pestaña nueva; ⌘L o un clic en la dirección, sobre la pestaña actual.
public struct CommandBarView: View {
    let browser: Browser
    let mode: CommandBarMode
    /// La zona de la página (en las coordenadas de la vista): el panel se centra ahí, no en la ventana.
    let area: CGRect?

    @State private var query = ""
    @State private var selection = 0
    @State private var searchSuggestions: [String] = []
    @FocusState private var isFocused: Bool
    @Namespace private var selectionNamespace
    @Environment(\.spaceTheme) private var theme

    public init(browser: Browser, mode: CommandBarMode, area: CGRect? = nil) {
        self.browser = browser
        self.mode = mode
        self.area = area
    }

    public var body: some View {
        let suggestions = browser.suggestions(for: query, mode: mode, searchSuggestions: searchSuggestions)

        GeometryReader { geometry in
            let zone = area.flatMap { $0.isEmpty ? nil : $0 } ?? CGRect(origin: .zero, size: geometry.size)
            ZStack {
                // Un clic fuera del panel lo cierra.
                Color.black.opacity(0.001)
                    .onTapGesture { close() }

                // Centrado (en horizontal y vertical) en la zona de la página.
                panel(suggestions)
                    .frame(width: min(720, zone.width - 80))
                    .position(x: zone.midX, y: zone.midY)
                    .animation(Theme.spring, value: suggestions.count)
            }
        }
        .environment(\.colorScheme, .dark)
        .onAppear {
            if mode == .currentTab, let tab = browser.selectedTab, !tab.isHome, let url = tab.url {
                query = url.absoluteString
            }
            isFocused = true
        }
        .task {
            // Si se abrió con un clic, el botón pulsado retiene el foco durante ese ciclo:
            // se pide de nuevo cuando termina, y otra vez por si la página lo recupera.
            for delay in [0, 80] {
                try? await Task.sleep(for: .milliseconds(delay))
                guard delay == 0 || !isFocused else { continue }
                NSApp.keyWindow?.makeFirstResponder(nil)
                isFocused = true
            }
        }
        .onChange(of: query) { selection = 0 }
        .task(id: query) { await loadSearchSuggestions() }
    }

    private func panel(_ suggestions: [Suggestion]) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                leadingIcon
                    .frame(width: 22, height: 22)
                TextField("Buscar o escribir una URL", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(.white)
                    .focused($isFocused)
                    .onSubmit { run(suggestions) }
                    .onExitCommand { close() }
                    .onKeyPress(.upArrow) { moveSelection(-1, count: suggestions.count) }
                    .onKeyPress(.downArrow) { moveSelection(1, count: suggestions.count) }
                    .onKeyPress(.tab) { moveSelection(1, count: suggestions.count) }
            }
            .padding(.horizontal, 22)
            .frame(height: 64)

            if !suggestions.isEmpty {
                Rectangle()
                    .fill(.white.opacity(0.08))
                    .frame(height: 1)
                    .padding(.horizontal, 14)

                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 2) {
                            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                                SuggestionRow(
                                    suggestion: suggestion,
                                    isSelected: index == selection,
                                    namespace: selectionNamespace
                                )
                                .id(index)
                                .onHover { if $0 { selection = index } }
                                .onTapGesture { browser.perform(suggestion, mode: mode) }
                            }
                        }
                        .padding(8)
                    }
                    // Hasta 9 filas a la vista; el resto con scroll.
                    .frame(maxHeight: 9 * 48 + 16)
                    .fixedSize(horizontal: false, vertical: suggestions.count <= 9)
                    .onChange(of: selection) { withAnimation(Theme.hoverOut) { proxy.scrollTo(selection) } }
                }
                .animation(.spring(response: 0.22, dampingFraction: 0.9), value: selection)
            }
        }
        .background(PanelBackground(theme: theme))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 40, y: 18)
        .shadow(color: .black.opacity(0.2), radius: 4, y: 1)
        .animation(Theme.spring, value: suggestions.map(\.id))
    }

    @ViewBuilder
    private var leadingIcon: some View {
        if mode == .currentTab, let tab = browser.selectedTab, query == tab.url?.absoluteString {
            FaviconView(tab: tab, size: 20)
        } else {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    private func moveSelection(_ delta: Int, count: Int) -> KeyPress.Result {
        guard count > 0 else { return .handled }
        selection = (selection + delta + count) % count
        return .handled
    }

    private func run(_ suggestions: [Suggestion]) {
        if suggestions.indices.contains(selection) {
            browser.perform(suggestions[selection], mode: mode)
        } else if !query.isEmpty {
            browser.commandBar = nil
            browser.navigate(to: query)
        }
    }

    private func close() {
        browser.commandBar = nil
    }

    private func loadSearchSuggestions() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, text != browser.selectedTab?.url?.absoluteString, !text.contains("://") else {
            searchSuggestions = []
            return
        }
        try? await Task.sleep(for: .milliseconds(120))
        guard !Task.isCancelled else { return }
        searchSuggestions = await SearchSuggestionsClient.fetch(text)
    }
}

private struct PanelBackground: View {
    let theme: SpaceTheme

    var body: some View {
        ZStack {
            VisualEffectBlur(material: .hudWindow, isDark: true)
            Color.black.opacity(0.42)
            Color(theme.background.first ?? .navy).opacity(0.22)
            GrainOverlay(intensity: theme.grain * 0.5)
        }
    }
}

private struct SuggestionRow: View {
    let suggestion: Suggestion
    let isSelected: Bool
    let namespace: Namespace.ID
    @Environment(\.spaceTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            icon
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(.white)
                        .opacity(isSelected ? 1 : 0)
                )
                .environment(\.colorScheme, isSelected ? .light : .dark)

            HStack(spacing: 0) {
                Text(suggestion.title)
                    .foregroundStyle(.white.opacity(0.95))
                if let detail = suggestion.detail {
                    Text(" — \(detail)")
                        .foregroundStyle(.white.opacity(0.42))
                }
            }
            .font(.system(size: 15, weight: .medium))
            .lineLimit(1)
            .truncationMode(.tail)

            Spacer(minLength: 0)

            if let shortcut = suggestion.shortcut {
                ShortcutKeys(shortcut, onLightBackground: true)
                    .opacity(isSelected ? 1 : 0.6)
            }
            if isSelected {
                Image(systemName: "return")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 46)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(theme.focus).opacity(1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(.white.opacity(0.06), lineWidth: 1)
                    )
                    .matchedGeometryEffect(id: "selection", in: namespace)
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var icon: some View {
        if let pageURL = suggestion.pageURL {
            FaviconView(pageURL: pageURL, faviconURL: suggestion.faviconURL, size: 18)
        } else {
            Image(systemName: suggestion.symbol ?? "globe")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isSelected ? .black.opacity(0.75) : .white.opacity(0.6))
        }
    }
}

/// Sugerencias de búsqueda de Google mientras escribes.
enum SearchSuggestionsClient {
    static func fetch(_ query: String) async -> [String] {
        var components = URLComponents(string: "https://suggestqueries.google.com/complete/search")!
        components.queryItems = [
            URLQueryItem(name: "client", value: "firefox"),
            URLQueryItem(name: "ie", value: "utf-8"),
            URLQueryItem(name: "oe", value: "utf-8"),
            URLQueryItem(name: "hl", value: Locale.current.language.languageCode?.identifier ?? "es"),
            URLQueryItem(name: "q", value: query),
        ]
        guard let url = components.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
              json.count > 1, let terms = json[1] as? [String]
        else { return [] }
        return terms
    }
}
