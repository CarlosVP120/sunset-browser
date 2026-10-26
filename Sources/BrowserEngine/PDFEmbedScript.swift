import Foundation

/// PDFs en un `<iframe>`/`<embed>` con un `blob:` que WebKit deja en blanco y Chrome sí muestra.
/// Webmails como el de Stalwart enseñan así los adjuntos, y en WebKit fallan por la CSP de la página:
/// el documento `blob:` hereda `frame-ancestors 'none'` (se bloquea el marco) y el visor de PDF de
/// WebKit lee el `blob:` como una conexión que `connect-src` no permite. Safari falla igual.
/// Como hace Chrome con su propio visor, Sunset lo muestra con un visor nativo (PDFKit) encima del
/// marco: este script apunta qué `Blob` hay detrás de cada `URL.createObjectURL`, y si es un PDF
/// (empieza por `%PDF-`) lo pasa a Sunset leyéndolo en memoria (sin conexión, así que la CSP no
/// interviene) junto con la posición del marco, que sigue mientras exista. Nada que no sea un PDF se toca.
/// Va al empezar el documento, antes que el código de la página.
enum PDFEmbedScript {
    static let handlerName = "sunsetPDF"

    static let source = """
    (() => {
      if (window.__sunsetPDFEmbeds) return;
      window.__sunsetPDFEmbeds = true;
      const handler = window.webkit?.messageHandlers?.\(handlerName);
      if (!handler) return;

      // Qué Blob hay detrás de cada dirección blob: que crea la página.
      const blobs = new Map();
      const create = URL.createObjectURL.bind(URL), revoke = URL.revokeObjectURL.bind(URL);
      URL.createObjectURL = function (object) {
        const url = create(object);
        if (object instanceof Blob) blobs.set(url, object);
        return url;
      };
      URL.revokeObjectURL = function (url) { blobs.delete(url); return revoke(url); };

      function base64(buffer) {
        const bytes = new Uint8Array(buffer);
        let binary = '';
        for (let i = 0; i < bytes.length; i += 0x8000) binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
        return btoa(binary);
      }

      let nextID = 1;
      const handled = new WeakMap();
      async function show(el) {
        const name = el.tagName === 'OBJECT' ? 'data' : 'src';
        const url = el.getAttribute(name) || '';
        if (!url.startsWith('blob:') || handled.get(el)?.url === url) return;
        const blob = blobs.get(url);
        if (!blob) return;
        const buffer = await blob.arrayBuffer();
        if (String.fromCharCode(...new Uint8Array(buffer, 0, 5)) !== '%PDF-') return;
        handled.get(el)?.stop();

        const id = nextID++;
        let last = '', running = true;
        handler.postMessage({ type: 'show', id, data: base64(buffer) });
        // Sigue la posición del marco mientras exista; si la página lo quita o lo oculta, se avisa.
        const track = () => {
          if (!running) return;
          const r = el.getBoundingClientRect();
          const visible = el.isConnected && r.width > 0 && r.height > 0 && el.getAttribute(name) === url;
          const frame = visible ? [r.left, r.top, r.width, r.height].map(Math.round).join(',') : 'hidden';
          if (frame !== last) {
            last = frame;
            handler.postMessage(visible ? { type: 'frame', id, x: r.left, y: r.top, width: r.width, height: r.height }
                                        : { type: 'frame', id, x: 0, y: 0, width: 0, height: 0 });
          }
          if (!el.isConnected || el.getAttribute(name) !== url) { stop(); return; }
          requestAnimationFrame(track);
        };
        const stop = () => { if (running) { running = false; handler.postMessage({ type: 'remove', id }); } };
        handled.set(el, { url, stop });
        track();
      }

      const start = () => {
        new MutationObserver(mutations => {
          for (const m of mutations) {
            if (m.type === 'attributes') { if (/^(IFRAME|EMBED|OBJECT)$/.test(m.target.tagName)) show(m.target); continue; }
            m.addedNodes.forEach(node => {
              if (node.nodeType !== 1) return;
              if (/^(IFRAME|EMBED|OBJECT)$/.test(node.tagName)) show(node);
              node.querySelectorAll?.('iframe, embed, object').forEach(show);
            });
          }
        }).observe(document.documentElement, { subtree: true, childList: true, attributes: true, attributeFilter: ['src', 'data'] });
        document.querySelectorAll('iframe, embed, object').forEach(show);
      };
      if (document.documentElement) start(); else document.addEventListener('DOMContentLoaded', start, { once: true });
    })();
    """
}
