import SwiftUI
import BrowserCore
import BrowserEngine
import BrowserUI

/// Botón de la Librería (abajo a la izquierda). Al pasar el ratón muestra las últimas descargas;
/// mientras hay descargas en curso, un anillo de progreso rodea el icono.
public struct LibraryButton: View {
    let browser: Browser
    let downloads: DownloadManager

    @State private var isHoveringButton = false
    @State private var isHoveringPanel = false
    @State private var showsRecent = false
    @State private var hoverTask: Task<Void, Never>?
    @Environment(\.spaceTheme) private var theme

    public init(browser: Browser, downloads: DownloadManager) {
        self.browser = browser
        self.downloads = downloads
    }

    private var recent: [DownloadRecord] {
        Array(downloads.items.filter { $0.state != .cancelled }.prefix(4))
    }

    public var body: some View {
        Button {
            withAnimation(Theme.spring) {
                showsRecent = false
                browser.showsLibrary.toggle()
            }
        } label: {
            Image(systemName: "books.vertical")
                .symbolVariant(browser.showsLibrary ? .fill : .none)
                .overlay {
                    if let progress = downloads.overallProgress {
                        ZStack {
                            Circle().stroke(Color(theme.title).opacity(0.15), lineWidth: 2)
                            Circle()
                                .trim(from: 0, to: max(0.05, progress))
                                .stroke(Color(theme.accent), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                        }
                        .frame(width: 24, height: 24)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.9), value: downloads.overallProgress)
        }
        .tooltip(downloads.activeCount > 0 ? "Librería · \(downloads.activeCount) descargando" : "Librería")
        .onHover { hovering in
            isHoveringButton = hovering
            updateRecentVisibility()
        }
        .overlay(alignment: .bottomLeading) {
            if showsRecent && !recent.isEmpty && !browser.showsLibrary {
                RecentDownloadsPanel(browser: browser, downloads: downloads, records: recent) {
                    showsRecent = false
                }
                .onHover { hovering in
                    isHoveringPanel = hovering
                    updateRecentVisibility()
                }
                .offset(x: -4, y: -36)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.92, anchor: .bottomLeading).combined(with: .opacity),
                    removal: .opacity
                ))
                .zIndex(10)
            }
        }
        .animation(Theme.spring, value: showsRecent)
    }

    /// Aparece tras una pequeña pausa; se queda mientras el ratón está en el botón o en el panel.
    private func updateRecentVisibility() {
        hoverTask?.cancel()
        let wantsVisible = isHoveringButton || isHoveringPanel
        hoverTask = Task {
            try? await Task.sleep(for: .milliseconds(wantsVisible ? (showsRecent ? 0 : 350) : 180))
            guard !Task.isCancelled else { return }
            showsRecent = isHoveringButton || isHoveringPanel
        }
    }
}

/// Las últimas descargas, con miniatura y fecha relativa.
private struct RecentDownloadsPanel: View {
    let browser: Browser
    let downloads: DownloadManager
    let records: [DownloadRecord]
    let dismiss: () -> Void
    @Environment(\.spaceTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(records) { record in
                RecentRow(downloads: downloads, record: record)
            }
            Divider().padding(.vertical, 4)
            Button {
                dismiss()
                browser.librarySection = .downloads
                withAnimation(Theme.spring) { browser.showsLibrary = true }
            } label: {
                HStack {
                    Text("Ver todas las descargas")
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Color(theme.title).opacity(0.85))
                .padding(.horizontal, 8)
                .frame(height: 28)
            }
            .buttonStyle(PillButtonStyle(cornerRadius: 8))
        }
        .padding(8)
        .frame(width: 230)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(theme.background.first ?? .navy).opacity(0.9))
                .background(VisualEffectBlur(isDark: theme.isDark).clipShape(RoundedRectangle(cornerRadius: 14)))
        )
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
    }

    private struct RecentRow: View {
        let downloads: DownloadManager
        let record: DownloadRecord
        @State private var isHovering = false
        @Environment(\.spaceTheme) private var theme

        var body: some View {
            Button { downloads.open(record) } label: {
                HStack(spacing: 10) {
                    FileThumbnail(record: record, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.filename)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(theme.title))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if record.state == .inProgress {
                            ProgressView(value: downloads.progress[record.id] ?? 0)
                                .controlSize(.mini)
                                .tint(Color(theme.accent))
                        } else {
                            Text(record.date.formatted(.relative(presentation: .named)))
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(Color(theme.subtitle).opacity(1.6))
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color(theme.hover))
                        .opacity(isHovering ? 1 : 0)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in withAnimation(hovering ? Theme.hoverIn : Theme.hoverOut) { isHovering = hovering } }
            .onDrag {
                guard let url = record.fileURL, record.fileExists else { return NSItemProvider() }
                return NSItemProvider(contentsOf: url) ?? NSItemProvider()
            }
            .contextMenu {
                Button("Mostrar en Finder") { downloads.revealInFinder(record) }
            }
        }
    }
}
