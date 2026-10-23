import Foundation

/// Elige el icono de la página como lo hacen Arc y Safari (el de la pestaña, `rel="icon"`, en su
/// mejor tamaño; el `apple-touch-icon` solo si no hay otro) y avisa cuando la página lo cambia
/// (Gmail, Slack o WhatsApp lo cambian para mostrar mensajes sin leer).
enum FaviconScript {
    static let handlerName = "sunsetFavicon"

    static let source = """
    (() => {
      if (window.__sunsetFavicon) return;
      const handler = window.webkit?.messageHandlers?.\(handlerName);

      // Tamaño declarado ("32x32", "any" para SVG); sin declarar cuenta como 16.
      const size = link => {
        const sizes = (link.getAttribute('sizes') || '').toLowerCase();
        if (sizes === 'any' || (link.type || '').includes('svg') || /\\.svg($|\\?)/.test(link.href)) return 512;
        const values = sizes.split(/\\s+/).map(s => parseInt(s, 10)).filter(n => n > 0);
        return values.length ? Math.max(...values) : 16;
      };
      const best = () => {
        const all = [...document.querySelectorAll('link[rel]')].filter(l => l.href);
        const icons = all.filter(l => /(^|\\s)icon(\\s|$)/i.test(l.rel));
        if (icons.length) {
          // El más cercano a 32 px por arriba (nítido en Retina sin bajar uno enorme).
          const ranked = icons.map(l => ({ l, s: size(l) })).sort((a, b) => {
            const score = s => (s >= 32 ? s - 32 : 1000 + (32 - s));
            return score(a.s) - score(b.s);
          });
          // Si hay varios iguales, el último declarado: las páginas que cambian el icono lo añaden al final.
          const top = ranked.filter(r => r.s === ranked[0].s);
          return top[top.length - 1].l.href;
        }
        const touch = all.find(l => /apple-touch-icon/i.test(l.rel));
        return touch ? touch.href : null;
      };
      window.__sunsetFavicon = best;
      if (!handler) return;

      let last = best(), timer = null;
      const report = () => {
        clearTimeout(timer);
        timer = setTimeout(() => {
          const now = best();
          if (now && now !== last) { last = now; handler.postMessage(now); }
        }, 250);
      };
      new MutationObserver(mutations => {
        if (mutations.some(m => m.target.nodeName === 'LINK' ||
            [...m.addedNodes, ...m.removedNodes].some(n => n.nodeName === 'LINK'))) report();
      }).observe(document.head || document.documentElement, { subtree: true, childList: true, attributes: true, attributeFilter: ['href', 'rel', 'sizes'] });
    })();
    """
}
