import Foundation
import Observation
import BrowserEngine

@MainActor
@Observable
public final class BrowserTab: Identifiable {
    public let id = UUID()
    public private(set) var title = "Nueva pestaña"
    public private(set) var url: URL?
    public private(set) var isLoading = false
    public private(set) var canGoBack = false
    public private(set) var canGoForward = false

    @ObservationIgnored public let page: WebPage

    init(page: WebPage, url: URL?) {
        self.page = page
        self.url = url
        page.onChange = { [weak self] snapshot in self?.apply(snapshot) }
        if let url { page.load(url) }
    }

    /// Texto a mostrar en la barra lateral.
    public var displayTitle: String {
        if !title.isEmpty { return title }
        return url?.host() ?? "Nueva pestaña"
    }

    public func load(_ url: URL) { page.load(url) }

    private func apply(_ snapshot: WebPageSnapshot) {
        if !snapshot.title.isEmpty { title = snapshot.title }
        url = snapshot.url ?? url
        isLoading = snapshot.isLoading
        canGoBack = snapshot.canGoBack
        canGoForward = snapshot.canGoForward
    }
}
