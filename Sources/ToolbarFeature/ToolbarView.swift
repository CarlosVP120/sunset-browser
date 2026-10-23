import SwiftUI
import BrowserCore
import BrowserUI

/// Barra superior (la opción "Show Toolbar" de Arc): navegación, dirección centrada y acciones.
public struct ToolbarView: View {
    let browser: Browser

    public init(browser: Browser) {
        self.browser = browser
    }

    public var body: some View {
        let tab = browser.selectedTab

        ZStack {
            HStack(spacing: 2) {
                if !browser.showsSidebar {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { browser.showsSidebar = true }
                    } label: {
                        Image(systemName: "sidebar.left")
                    }
                    .help("Mostrar la barra lateral (⌘S)")
                }
                NavigationButtons(tab: tab)
                Spacer()
                Button {
                    if let url = tab?.url {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url.absoluteString, forType: .string)
                    }
                } label: {
                    Image(systemName: "link")
                }
                .disabled(tab?.url == nil)
                .help("Copiar enlace (⇧⌘C)")
            }
            .buttonStyle(ChromeButtonStyle())

            AddressPill(browser: browser)
                .frame(maxWidth: 460)
                .padding(.horizontal, 110)
        }
        .padding(.leading, browser.showsSidebar ? 2 : Theme.windowButtonsInset)
        .padding(.trailing, 6)
        .frame(height: Theme.toolbarHeight)
    }
}

/// Dirección de la página: muestra el dominio y al hacer clic se convierte en campo editable.
struct AddressPill: View {
    let browser: Browser
    @State private var isEditing = false
    @State private var isHovering = false
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        let tab = browser.selectedTab

        Group {
            if isEditing {
                TextField("Buscar o escribir una URL", text: $text)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .onSubmit {
                        browser.navigate(to: text)
                        isEditing = false
                    }
                    .onExitCommand { isEditing = false }
                    .padding(.horizontal, 10)
            } else {
                HStack(spacing: 6) {
                    if let url = tab?.url {
                        Image(systemName: url.scheme == "https" ? "lock" : "link")
                            .font(.system(size: 10, weight: .semibold))
                        Text(Self.displayHost(url))
                            .lineLimit(1)
                    } else {
                        Text("Buscar o escribir una URL")
                    }
                }
                .foregroundStyle(tab?.url == nil ? Theme.secondaryText : Theme.primaryText.opacity(0.8))
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { startEditing() }
            }
        }
        .font(.system(size: 12, weight: .medium))
        .frame(height: 22)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isEditing ? Color.black.opacity(0.25) : (isHovering ? Theme.hover : .clear))
        )
        .onHover { isHovering = $0 }
        .onChange(of: browser.urlFocusRequests) { startEditing(clear: true) }
        .onChange(of: isFocused) { if !isFocused { isEditing = false } }
    }

    private func startEditing(clear: Bool = false) {
        text = clear ? "" : (browser.selectedTab?.url?.absoluteString ?? "")
        isEditing = true
        DispatchQueue.main.async { isFocused = true }
    }

    static func displayHost(_ url: URL) -> String {
        guard let host = url.host() else { return url.absoluteString }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
