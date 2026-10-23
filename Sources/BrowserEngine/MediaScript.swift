import Foundation

/// Estado del audio/vídeo principal de una página (para PiP y el reproductor de la barra lateral).
public struct MediaState: Equatable, Sendable {
    public var isPlaying: Bool
    public var isMuted: Bool
    public var hasVideo: Bool
    public var isInPictureInPicture: Bool

    public init(isPlaying: Bool, isMuted: Bool, hasVideo: Bool, isInPictureInPicture: Bool) {
        self.isPlaying = isPlaying
        self.isMuted = isMuted
        self.hasVideo = hasVideo
        self.isInPictureInPicture = isInPictureInPicture
    }
}

/// Script que se inyecta en cada página: avisa de los cambios de sus medios y ofrece
/// controles (`window.__miNavegadorMedia`) que el navegador llama desde fuera.
enum MediaScript {
    static let handlerName = "miNavegadorMedia"

    static let source = """
    (() => {
      if (window.__miNavegadorMedia) return;
      const handler = window.webkit?.messageHandlers?.\(handlerName);
      if (!handler) return;

      // El medio "principal": el vídeo que suena más grande, o cualquier audio/vídeo sonando.
      const primary = () => {
        const media = [...document.querySelectorAll('video, audio')];
        const playing = media.filter(m => !m.paused && !m.ended && m.readyState > 2);
        const area = m => m.tagName === 'VIDEO' ? m.clientWidth * m.clientHeight : 0;
        const pick = list => list.sort((a, b) => area(b) - area(a))[0];
        return pick(playing) || pick(media.filter(m => m.webkitPresentationMode === 'picture-in-picture'))
          || pick(media.filter(m => m.currentTime > 0 && !m.ended));
      };

      let last = '';
      const report = () => {
        const m = primary();
        const state = m ? {
          playing: !m.paused && !m.ended,
          muted: m.muted || m.volume === 0,
          video: m.tagName === 'VIDEO' && m.videoWidth > 0,
          pip: m.webkitPresentationMode === 'picture-in-picture'
        } : null;
        const json = JSON.stringify(state);
        if (json !== last) { last = json; handler.postMessage(state); }
      };

      for (const type of ['play', 'playing', 'pause', 'ended', 'volumechange', 'emptied',
                          'webkitpresentationmodechanged', 'loadeddata']) {
        document.addEventListener(type, report, true);
      }

      // Estado inicial (también avisa si la página nueva ya no tiene medios).
      report();

      window.__miNavegadorMedia = {
        setPictureInPicture(on) {
          const m = primary();
          if (!m || m.tagName !== 'VIDEO' || !m.webkitSupportsPresentationMode?.('picture-in-picture')) return false;
          m.webkitSetPresentationMode(on ? 'picture-in-picture' : 'inline');
          return true;
        },
        togglePlayback() { const m = primary(); if (m) { m.paused ? m.play() : m.pause(); } },
        pause() { const m = primary(); if (m) m.pause(); },
        seek(seconds) { const m = primary(); if (m) m.currentTime = Math.max(0, m.currentTime + seconds); },
        toggleMute() { const m = primary(); if (m) m.muted = !m.muted; }
      };
    })();
    """
}
