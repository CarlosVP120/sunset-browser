import AppKit
import PDFKit
import WebKit

/// El visor nativo de los PDFs que la página no puede mostrar (ver `PDFEmbedScript`): un `PDFView`
/// encima del marco de la página, en su misma posición y tamaño.
extension WebKitPage {
    func receivePDFMessage(_ body: Any) {
        guard let message = body as? [String: Any], let type = message["type"] as? String,
              let id = (message["id"] as? NSNumber)?.intValue else { return }
        switch type {
        case "show":
            guard let base64 = message["data"] as? String, let data = Data(base64Encoded: base64),
                  let document = PDFDocument(data: data) else { return }
            pdfOverlays[id]?.removeFromSuperview()
            let view = PDFView()
            view.document = document
            view.autoScales = true
            view.displayMode = .singlePageContinuous
            view.backgroundColor = NSColor(white: 0.32, alpha: 1)
            view.isHidden = true
            webView.addSubview(view)
            pdfOverlays[id] = view
        case "frame":
            guard let view = pdfOverlays[id] else { return }
            let number = { (key: String) in CGFloat((message[key] as? NSNumber)?.doubleValue ?? 0) }
            // Coordenadas CSS de la página → puntos de la vista (zoom de la página y ampliación).
            let scale = webView.pageZoom * webView.magnification
            let width = number("width") * scale, height = number("height") * scale
            let x = number("x") * scale, top = number("y") * scale
            let y = webView.isFlipped ? top : webView.bounds.height - top - height
            view.frame = CGRect(x: x, y: y, width: width, height: height)
            view.isHidden = width < 1 || height < 1
        case "remove":
            pdfOverlays.removeValue(forKey: id)?.removeFromSuperview()
        default:
            break
        }
    }

    /// Al cambiar de página, fuera los visores de la anterior (su script ya no puede avisar).
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        removePDFOverlays()
    }

    func removePDFOverlays() {
        pdfOverlays.values.forEach { $0.removeFromSuperview() }
        pdfOverlays.removeAll()
    }
}
