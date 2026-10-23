import Foundation

/// Un mensaje de la consola de la página (modo desarrollador).
public struct ConsoleMessage: Equatable, Sendable, Identifiable {
    public enum Level: String, Sendable {
        case log, info, warn, error, debug
        /// Resultado de algo escrito en la consola de Sunset.
        case result
    }

    public let id: UUID
    public let level: Level
    public let text: String
    /// "app.js:42", si se sabe.
    public let source: String?
    public let date: Date

    public init(id: UUID = UUID(), level: Level, text: String, source: String? = nil, date: Date = Date()) {
        self.id = id
        self.level = level
        self.text = text
        self.source = source
        self.date = date
    }
}

/// Una petición de red de la página (panel Red del modo desarrollador).
public struct NetworkRequest: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable, CaseIterable {
        case document, fetch, xhr, js, css, img, font, other
    }

    public let id: UUID
    public let method: String
    public let url: String
    /// Código HTTP; 0 si no hubo respuesta (o el navegador no lo da).
    public let status: Int
    public let kind: Kind
    /// Milisegundos.
    public let duration: Double
    /// Bytes (0 si no se sabe).
    public let size: Int
    public let mimeType: String?
    public let isCached: Bool
    public let error: String?
    /// Empieza una página nueva (el panel se limpia, como en las DevTools).
    public let isNewDocument: Bool
    public let date: Date

    public init(id: UUID = UUID(), method: String, url: String, status: Int, kind: Kind, duration: Double, size: Int,
                mimeType: String? = nil, isCached: Bool = false, error: String? = nil, isNewDocument: Bool = false,
                date: Date = Date()) {
        self.id = id
        self.method = method
        self.url = url
        self.status = status
        self.kind = kind
        self.duration = duration
        self.size = size
        self.mimeType = mimeType
        self.isCached = isCached
        self.error = error
        self.isNewDocument = isNewDocument
        self.date = date
    }

    /// Falló: sin respuesta o con un código de error.
    public var isFailure: Bool { error != nil || status >= 400 || (status == 0 && (kind == .fetch || kind == .xhr)) }

    /// El nombre del archivo o la ruta (lo que se ve en la lista).
    public var name: String {
        guard let components = URLComponents(string: url) else { return url }
        let last = components.path.split(separator: "/").last.map(String.init) ?? ""
        let query = components.query.map { "?" + $0 } ?? ""
        return last.isEmpty ? (components.host ?? url) + "/" : last + query
    }
}

/// Recoge lo que la página escribe en la consola, sus errores sin capturar y las peticiones de
/// red que fallan. Se instala en todas las páginas pero no envía nada hasta que la pestaña entra
/// en modo desarrollador: mientras, guarda los últimos mensajes para mostrarlos al activarlo.
enum ConsoleScript {
    static let handlerName = "sunsetConsole"

    static let source = """
    (() => {
      if (window.__sunsetConsole) return;
      const handler = window.webkit?.messageHandlers?.\(handlerName);
      if (!handler) return;

      let enabled = false;
      const buffer = [];
      const send = message => {
        if (enabled) { try { handler.postMessage(message); } catch (_) {} }
        else { buffer.push(message); if (buffer.length > 200) buffer.shift(); }
      };

      const describe = value => {
        if (value instanceof Error) {
          // WebKit no pone el mensaje en "stack": se escribe "Tipo: mensaje" y debajo dónde ocurrió.
          const where = (value.stack || '').split('\\n').filter(Boolean).slice(0, 3).map(l => '    at ' + l).join('\\n');
          return `${value.name}: ${value.message}` + (where ? '\\n' + where : '');
        }
        if (typeof value === 'string') return value;
        if (value === undefined) return 'undefined';
        if (typeof value === 'function') return `ƒ ${value.name || '(anónima)'}()`;
        if (value instanceof Element) return `<${value.tagName.toLowerCase()}${value.id ? '#' + value.id : ''}${value.className && typeof value.className === 'string' ? '.' + value.className.trim().split(/\\s+/).join('.') : ''}>`;
        try {
          const seen = new WeakSet();
          return JSON.stringify(value, (key, v) => {
            if (typeof v === 'object' && v !== null) { if (seen.has(v)) return '[Circular]'; seen.add(v); }
            return typeof v === 'bigint' ? v.toString() + 'n' : v;
          });
        } catch (_) { return String(value); }
      };
      const caller = () => {
        const line = (new Error().stack || '').split('\\n').slice(3).find(l => l.includes('/')) || '';
        const match = line.match(/([^\\/\\s()]+:\\d+)(?::\\d+)?\\)?$/);
        return match ? match[1] : null;
      };

      for (const level of ['log', 'info', 'warn', 'error', 'debug']) {
        const original = console[level].bind(console);
        console[level] = (...args) => {
          send({ level, text: args.map(describe).join(' ').slice(0, 5000), source: caller() });
          return original(...args);
        };
      }
      addEventListener('error', event => {
        const where = event.filename ? `${event.filename.split('/').pop()}:${event.lineno}` : null;
        send({ level: 'error', text: event.error ? describe(event.error) : event.message, source: where });
      });
      addEventListener('unhandledrejection', event => {
        send({ level: 'error', text: 'Promesa rechazada sin capturar: ' + describe(event.reason), source: null });
      });

      // Red: cada petición va al panel Red; las que fallan, además, a la consola.
      const absolute = url => { try { return new URL(url, location.href).href; } catch (_) { return String(url); } };
      const net = entry => send(Object.assign({ kind: 'net' }, entry));
      const originalFetch = window.fetch;
      if (originalFetch) {
        window.fetch = async (...args) => {
          const request = args[0];
          const target = absolute(request instanceof Request ? request.url : request);
          const method = ((args[1] && args[1].method) || (request instanceof Request && request.method) || 'GET').toUpperCase();
          const start = performance.now();
          try {
            const response = await originalFetch(...args);
            const size = Number(response.headers.get('content-length')) || 0;
            net({ method, url: target, status: response.status, type: 'fetch', duration: performance.now() - start,
                  size, mime: response.headers.get('content-type') || '' });
            if (!response.ok) send({ level: 'warn', text: `fetch ${response.status} ${response.statusText} · ${target}`, source: 'red' });
            return response;
          } catch (error) {
            net({ method, url: target, status: 0, type: 'fetch', duration: performance.now() - start, size: 0, error: String(error) });
            send({ level: 'error', text: `fetch falló · ${target} · ${error}`, source: 'red' });
            throw error;
          }
        };
      }
      const open = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function (method, url, ...rest) {
        const target = absolute(url);
        let start = 0;
        this.addEventListener('loadstart', () => { start = performance.now(); });
        this.addEventListener('loadend', () => {
          const size = Number(this.getResponseHeader && this.getResponseHeader('content-length')) || 0;
          net({ method: String(method).toUpperCase(), url: target, status: this.status, type: 'xhr',
                duration: performance.now() - start, size, mime: (this.getResponseHeader && this.getResponseHeader('content-type')) || '' });
          if (this.status === 0 || this.status >= 400) {
            send({ level: this.status === 0 ? 'error' : 'warn', text: `XHR ${method} ${this.status || 'sin respuesta'} · ${url}`, source: 'red' });
          }
        });
        return open.call(this, method, url, ...rest);
      };

      // El documento y los recursos (scripts, estilos, imágenes, fuentes…), con sus tiempos.
      const resourceType = entry => {
        const kind = entry.initiatorType;
        if (kind === 'fetch' || kind === 'xmlhttprequest') return null; // ya vienen de arriba
        if (kind === 'script') return 'js';
        if (kind === 'link' || kind === 'css') return /\\.css(\\?|$)/.test(entry.name) || kind === 'css' ? 'css' : 'other';
        if (kind === 'img' || kind === 'image' || /\\.(png|jpe?g|gif|webp|avif|svg|ico)(\\?|$)/i.test(entry.name)) return 'img';
        if (/\\.(woff2?|ttf|otf)(\\?|$)/i.test(entry.name)) return 'font';
        return 'other';
      };
      const fromTiming = (entry, type) => ({
        method: 'GET', url: entry.name, status: entry.responseStatus || 0, type,
        duration: entry.duration, size: entry.transferSize || entry.encodedBodySize || 0,
        cached: entry.transferSize === 0 && entry.encodedBodySize > 0,
      });
      const navigation = performance.getEntriesByType('navigation')[0];
      net(Object.assign(fromTiming(navigation || { name: location.href, duration: 0 }, 'document'),
                        { status: (navigation && navigation.responseStatus) || 200, newDocument: true }));
      try {
        new PerformanceObserver(list => {
          for (const entry of list.getEntries()) {
            const type = resourceType(entry);
            if (type) net(fromTiming(entry, type));
          }
        }).observe({ type: 'resource', buffered: true });
      } catch (_) {}

      window.__sunsetConsole = {
        enable(on) {
          enabled = on;
          if (on) { while (buffer.length) { try { handler.postMessage(buffer.shift()); } catch (_) {} } }
        },
        describe,
      };
    })();
    """

    /// Cuerpo de función para `callAsyncJavaScript`: ejecuta lo escrito en la consola de Sunset
    /// (llega como el argumento `code`, sin tener que escaparlo) y devuelve el resultado como texto.
    static let evaluationBody = """
    try {
      const value = await (0, eval)(code);
      return window.__sunsetConsole ? window.__sunsetConsole.describe(value) : String(value);
    } catch (error) {
      return '⚠︎ ' + (error && error.stack ? error.stack.split('\\n')[0] : String(error));
    }
    """
}
