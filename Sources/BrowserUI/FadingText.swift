import SwiftUI

/// Texto de una línea que usa todo el ancho disponible y, si no cabe, se desvanece al final
/// en lugar de cortarse con "…" (como los títulos de pestañas en Arc).
public struct FadingText: View {
    let text: String
    var fade: CGFloat
    /// Espacio al final donde el texto ya no se ve nada (p. ej. bajo el botón de cerrar).
    var trailingClear: CGFloat

    public init(_ text: String, fade: CGFloat = 16, trailingClear: CGFloat = 0) {
        self.text = text
        self.fade = fade
        self.trailingClear = trailingClear
    }

    public var body: some View {
        // Un texto oculto da la altura de la línea; su ancho ideal es 0, así que nunca ensancha
        // la fila. Encima va el texto completo, recortado y desvanecido al final.
        Text(text)
            .lineLimit(1)
            .hidden()
            .frame(minWidth: 0, idealWidth: 0, maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                Text(text)
                    .lineLimit(1)
                    .fixedSize()
            }
            .clipped()
            .mask(
                HStack(spacing: 0) {
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: fade)
                    Color.clear.frame(width: trailingClear)
                }
            )
    }
}
