import Foundation

/// PDFs incrustados que WebKit deja en blanco y Chrome sí muestra (su visor detecta el PDF por su
/// contenido y funciona en marcos con `sandbox`). Webmails como el de Stalwart o Roundcube muestran
/// el adjunto en un `<iframe sandbox>` con un `blob:` sin tipo: en Safari se queda en blanco.
/// Si el `blob:` es de verdad un PDF (empieza por `%PDF-`), se vuelve a crear como
/// `application/pdf` y sin `sandbox`. Es seguro: un PDF no ejecuta scripts de la página, y nada que
/// no sea un PDF se toca.
enum PDFEmbedScript {
    static let source = """
    (() => {
      if (window.__sunsetPDFEmbeds) return;
      window.__sunsetPDFEmbeds = true;
      const attribute = el => (el.tagName === 'OBJECT' ? 'data' : 'src');

      async function fix(el) {
        const url = el.getAttribute(attribute(el)) || '';
        if (!url.startsWith('blob:') || el.dataset.sunsetPdf === url) return;
        const sandboxed = el.tagName === 'IFRAME' && el.hasAttribute('sandbox');
        let blob;
        try { blob = await (await fetch(url)).blob(); } catch { return; }
        if (blob.type === 'application/pdf' && !sandboxed) return;
        const head = new Uint8Array(await blob.slice(0, 5).arrayBuffer());
        if (String.fromCharCode(...head) !== '%PDF-') return;
        const pdfURL = URL.createObjectURL(new Blob([blob], { type: 'application/pdf' }));
        el.dataset.sunsetPdf = pdfURL;
        if (sandboxed) el.removeAttribute('sandbox');
        if (el.tagName === 'OBJECT' || el.tagName === 'EMBED') el.setAttribute('type', 'application/pdf');
        el.setAttribute(attribute(el), pdfURL);
      }

      const scan = root => root.querySelectorAll?.('iframe[src^="blob:"], embed[src^="blob:"], object[data^="blob:"]').forEach(fix);
      new MutationObserver(mutations => {
        for (const m of mutations) {
          if (m.type === 'attributes') fix(m.target);
          else m.addedNodes.forEach(node => {
            if (node.nodeType !== 1) return;
            if (/^(IFRAME|EMBED|OBJECT)$/.test(node.tagName)) fix(node);
            scan(node);
          });
        }
      }).observe(document.documentElement, { subtree: true, childList: true, attributes: true, attributeFilter: ['src', 'data'] });
      scan(document);
    })();
    """
}
