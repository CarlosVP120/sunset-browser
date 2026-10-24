import SwiftUI
import UniformTypeIdentifiers
import WebKit
import BrowserCore
import BrowserEngine
import BrowserUI

/// Botones de las extensiones activas y el botón de gestión (la pieza de puzle).
@available(macOS 15.4, *)
public struct ExtensionsToolbar: View {
    let browser: Browser
    let host: WebExtensionsHost

    public init(browser: Browser, host: WebExtensionsHost) {
        self.browser = browser
        self.host = host
    }

    public var body: some View {
        // Leerlo hace que la barra se redibuje cuando cambia un icono o una insignia.
        let _ = host.actionsRevision

        HStack(spacing: 2) {
            ForEach(host.installed.filter(\.isEnabled)) { installed in
                ExtensionActionButton(host: host, id: installed.id)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            ExtensionsMenuButton(browser: browser, host: host)
        }
        .buttonStyle(ChromeButtonStyle())
        .animation(Theme.spring, value: host.installed)
    }
}

@available(macOS 15.4, *)
private struct ExtensionActionButton: View {
    let host: WebExtensionsHost
    let id: UUID
    @State private var frame: CGRect = .zero

    var body: some View {
        let action = host.action(for: id)

        Button { host.performAction(for: id, anchor: frame) } label: {
            Group {
                if let icon = action?.icon(for: CGSize(width: 16, height: 16)) {
                    Image(nsImage: icon).resizable().interpolation(.high)
                } else {
                    Image(systemName: "puzzlepiece.extension")
                }
            }
            .frame(width: 16, height: 16)
            .opacity(action?.isEnabled == false ? 0.45 : 1)
            .overlay(alignment: .bottomTrailing) {
                if let badge = action?.badgeText, !badge.isEmpty {
                    Text(badge)
                        .font(.system(size: 8.5, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 3)
                        .frame(minWidth: 12, minHeight: 11)
                        .background(Capsule().fill(Color(red: 0.86, green: 0.2, blue: 0.2)))
                        .offset(x: 7, y: 5)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .tooltip(action?.label ?? "Extensión")
        .background(GeometryReader { proxy in
            Color.clear
                .onAppear { frame = proxy.frame(in: .global) }
                .onChange(of: proxy.frame(in: .global)) { _, newFrame in frame = newFrame }
        })
        .contextMenu {
            if host.context(for: id)?.optionsPageURL != nil {
                Button("Opciones") { host.openOptions(for: id) }
            }
            Button("Desactivar") { Task { await host.setEnabled(false, for: id) } }
        }
    }
}

/// La pieza de puzle: lista de extensiones, activar/desactivar, quitar e instalar.
@available(macOS 15.4, *)
private struct ExtensionsMenuButton: View {
    let browser: Browser
    let host: WebExtensionsHost
    @State private var showsPanel = false
    @Environment(\.spaceTheme) private var theme

    var body: some View {
        let storeID = WebExtensionsHost.chromeWebStoreID(from: browser.selectedTab?.url)
        let canInstallFromStore = storeID != nil && !host.installed.contains { $0.source == "chrome-web-store:\(storeID!)" }

        Button { showsPanel.toggle() } label: {
            Image(systemName: "puzzlepiece.extension")
                .overlay(alignment: .topTrailing) {
                    // Aviso: estás en la ficha de una extensión que se puede instalar.
                    if canInstallFromStore {
                        Circle().fill(Color(theme.accent)).frame(width: 6, height: 6).offset(x: 3, y: -2)
                    }
                }
        }
        .tooltip("Extensiones")
        .popover(isPresented: $showsPanel, arrowEdge: .bottom) {
            ExtensionsPanel(browser: browser, host: host, storeID: canInstallFromStore ? storeID : nil)
        }
    }
}

@available(macOS 15.4, *)
struct ExtensionsPanel: View {
    let browser: Browser
    let host: WebExtensionsHost
    let storeID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Extensiones")
                .font(.headline)
                .padding([.horizontal, .top], 14)
                .padding(.bottom, 10)

            if let storeID {
                Button {
                    Task { await host.installFromChromeWebStore(id: storeID) }
                } label: {
                    Label("Añadir esta extensión a Sunset", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(host.isInstalling)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }

            if host.isInstalling {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Instalando…").foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }

            if let error = host.lastError, !error.isEmpty {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                    .onTapGesture { host.lastError = nil }
            }

            Divider()

            if host.installed.isEmpty {
                Text("Aún no tienes extensiones. Instálalas desde Chrome Web Store o desde un archivo .zip o .crx.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(14)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(host.installed) { installed in
                            ExtensionRow(host: host, installed: installed)
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 320)
            }

            Divider()

            HStack {
                Button("Chrome Web Store") {
                    browser.openTab(URL(string: "https://chromewebstore.google.com/")!)
                }
                Spacer()
                Button("Instalar desde archivo…") { ExtensionInstaller.chooseFile(host: host) }
            }
            .padding(12)
        }
        .frame(width: 340)
    }
}

@available(macOS 15.4, *)
private struct ExtensionRow: View {
    let host: WebExtensionsHost
    let installed: InstalledExtension
    @State private var isHovering = false

    var body: some View {
        let context = host.context(for: installed.id)

        HStack(spacing: 10) {
            Group {
                if let icon = context?.webExtension.icon(for: CGSize(width: 28, height: 28)) {
                    Image(nsImage: icon).resizable()
                } else {
                    Image(systemName: "puzzlepiece.extension.fill").resizable().scaledToFit().foregroundStyle(.secondary)
                }
            }
            .frame(width: 28, height: 28)
            .opacity(installed.isEnabled ? 1 : 0.4)

            VStack(alignment: .leading, spacing: 1) {
                Text(installed.name).lineLimit(1)
                Text(installed.version).font(.caption).foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Menu {
                if context?.optionsPageURL != nil {
                    Button("Opciones") { host.openOptions(for: installed.id) }
                }
                Button("Quitar extensión", role: .destructive) { host.uninstall(installed.id) }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .opacity(isHovering ? 1 : 0.4)

            Toggle("", isOn: Binding(
                get: { installed.isEnabled },
                set: { enabled in Task { await host.setEnabled(enabled, for: installed.id) } }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(.primary.opacity(isHovering ? 0.06 : 0)))
        .onHover { isHovering = $0 }
    }
}

/// Selector de archivo para instalar una extensión descargada.
@available(macOS 15.4, *)
@MainActor
public enum ExtensionInstaller {
    public static func chooseFile(host: WebExtensionsHost) {
        let panel = NSOpenPanel()
        panel.title = "Instalar extensión"
        panel.message = "Elige una carpeta con manifest.json, o un archivo .zip o .crx"
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        var types: [UTType] = [.zip, .folder]
        if let crx = UTType(filenameExtension: "crx") { types.append(crx) }
        panel.allowedContentTypes = types
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await host.install(from: url) }
    }
}
