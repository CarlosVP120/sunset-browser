import SwiftUI
import BrowserCore

/// Barra lateral vertical: campo de URL, pestañas fijadas, pestañas y espacios.
public struct SidebarView: View {
    @Bindable private var browser: Browser
    @State private var urlText = ""
    @FocusState private var urlFieldFocused: Bool

    public init(browser: Browser) {
        self.browser = browser
    }

    public var body: some View {
        let space = browser.activeSpace

        VStack(alignment: .leading, spacing: 10) {
            NavigationButtons(tab: browser.selectedTab)
                .padding(.leading, 70) // deja sitio a los botones de la ventana

            urlField

            if !space.pinnedTabs.isEmpty {
                PinnedTabsGrid(browser: browser, space: space)
            }

            HStack {
                Text(space.name)
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 6)
            .padding(.top, 4)

            Button {
                browser.newTab()
            } label: {
                Label("Nueva pestaña", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(space.tabs) { tab in
                        TabRow(browser: browser, tab: tab, isSelected: tab.id == space.selectedTabID)
                    }
                }
            }

            SpaceSwitcher(browser: browser)
        }
        .padding(10)
        .onChange(of: browser.urlFocusRequests) {
            urlText = ""
            urlFieldFocused = true
        }
        .onChange(of: browser.selectedTab?.url, initial: true) {
            if !urlFieldFocused { syncURLText() }
        }
        .onChange(of: browser.activeSpaceID) { syncURLText() }
    }

    private var urlField: some View {
        TextField("Buscar o escribir una URL", text: $urlText)
            .textFieldStyle(.plain)
            .focused($urlFieldFocused)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.white.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            .onSubmit {
                browser.navigate(to: urlText)
                urlFieldFocused = false
            }
            .onExitCommand {
                urlFieldFocused = false
                syncURLText()
            }
    }

    private func syncURLText() {
        urlText = browser.selectedTab?.url?.absoluteString ?? ""
    }
}

private struct NavigationButtons: View {
    let tab: BrowserTab?

    var body: some View {
        HStack(spacing: 14) {
            Button { tab?.page.goBack() } label: { Image(systemName: "chevron.left") }
                .disabled(!(tab?.canGoBack ?? false))
            Button { tab?.page.goForward() } label: { Image(systemName: "chevron.right") }
                .disabled(!(tab?.canGoForward ?? false))
            Button {
                if tab?.isLoading == true { tab?.page.stopLoading() } else { tab?.page.reload() }
            } label: {
                Image(systemName: tab?.isLoading == true ? "xmark" : "arrow.clockwise")
            }
            .disabled(tab == nil)
            Spacer()
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .frame(height: 22)
    }
}

private struct TabRow: View {
    let browser: Browser
    let tab: BrowserTab
    let isSelected: Bool
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            FaviconView(tab: tab)
            Text(tab.displayTitle)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if isHovering {
                Button { browser.close(tab) } label: {
                    Image(systemName: "xmark").font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.white.opacity(isSelected ? 0.6 : (isHovering ? 0.25 : 0)))
        )
        .contentShape(Rectangle())
        .onTapGesture { browser.select(tab) }
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Fijar pestaña") { browser.togglePin(tab) }
            Button("Cerrar pestaña") { browser.close(tab) }
        }
    }
}

private struct PinnedTabsGrid: View {
    let browser: Browser
    let space: Space

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 6)], spacing: 6) {
            ForEach(space.pinnedTabs) { tab in
                FaviconView(tab: tab, size: 18)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.white.opacity(tab.id == space.selectedTabID ? 0.6 : 0.25))
                    )
                    .help(tab.displayTitle)
                    .onTapGesture { browser.select(tab) }
                    .contextMenu {
                        Button("Desfijar pestaña") { browser.togglePin(tab) }
                        Button("Cerrar pestaña") { browser.close(tab) }
                    }
            }
        }
    }
}

private struct SpaceSwitcher: View {
    let browser: Browser

    var body: some View {
        HStack(spacing: 12) {
            ForEach(browser.spaces) { space in
                Button { browser.activate(space) } label: {
                    Image(systemName: space.icon)
                        .symbolVariant(space.id == browser.activeSpaceID ? .fill : .none)
                }
                .buttonStyle(.plain)
                .help(space.name)
            }
            Spacer()
            Button {
                browser.addSpace(name: "Espacio \(browser.spaces.count + 1)")
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .help("Nuevo espacio")
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }
}

/// Icono del sitio, usando el favicon del dominio.
struct FaviconView: View {
    let tab: BrowserTab
    var size: CGFloat = 16

    var body: some View {
        Group {
            if let host = tab.url?.host(),
               let url = URL(string: "https://\(host)/favicon.ico") {
                AsyncImage(url: url) { image in
                    image.resizable().interpolation(.high)
                } placeholder: {
                    Image(systemName: "globe").resizable().foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "globe").resizable().foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}
