import SwiftUI
import BrowserCore
import BrowserEngine
import BrowserUI

/// Reproductor de la barra lateral (como el de Arc) para el audio/vídeo de otras pestañas.
/// Siempre se ven los controles; al pasar el ratón aparecen el título (clic → vuelve a la
/// pestaña), el botón de imagen en imagen y el de cerrar.
struct MediaPlayerCard: View {
    let browser: Browser
    let tab: BrowserTab
    @State private var isHovering = false

    var body: some View {
        let media = tab.media

        VStack(spacing: 6) {
            if isHovering {
                HStack(spacing: 6) {
                    Button { withAnimation(Theme.spring) { browser.reveal(tab) } } label: {
                        HStack(spacing: 7) {
                            FaviconView(tab: tab, size: 14)
                            FadingText(tab.displayTitle)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.92))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .tooltip("Volver a la pestaña")

                    if media?.hasVideo == true {
                        let inPictureInPicture = media?.isInPictureInPicture == true
                        Button { browser.setPictureInPicture(!inPictureInPicture, for: tab) } label: {
                            Image(systemName: inPictureInPicture ? "pip.exit" : "pip.enter")
                        }
                        .tooltip(inPictureInPicture ? "Quitar imagen en imagen" : "Imagen en imagen")
                    }
                    Button { withAnimation(Theme.spring) { browser.dismissMedia(of: tab) } } label: {
                        Image(systemName: "xmark")
                    }
                    .tooltip("Cerrar reproductor")
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            HStack(spacing: 0) {
                control("gobackward.15", tooltip: "Retroceder 15 s") { browser.mediaCommand(.seek(-15), for: tab) }
                control(media?.isPlaying == true ? "pause.fill" : "play.fill",
                        tooltip: media?.isPlaying == true ? "Pausa" : "Reproducir") {
                    browser.mediaCommand(.togglePlayback, for: tab)
                }
                .contentTransition(.symbolEffect(.replace))
                control("goforward.15", tooltip: "Avanzar 15 s") { browser.mediaCommand(.seek(15), for: tab) }
                control(media?.isMuted == true ? "speaker.slash.fill" : "speaker.wave.2.fill",
                        tooltip: media?.isMuted == true ? "Activar sonido" : "Silenciar") {
                    browser.mediaCommand(.toggleMute, for: tab)
                }
                .contentTransition(.symbolEffect(.replace))
            }
        }
        .buttonStyle(ChromeButtonStyle(size: 28))
        .environment(\.colorScheme, .dark)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.78))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.08)))
                .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
        )
        .onHover { hovering in withAnimation(Theme.spring) { isHovering = hovering } }
        .animation(Theme.spring, value: media)
    }

    private func control(_ symbol: String, tooltip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity)
        }
        .tooltip(tooltip)
    }
}
