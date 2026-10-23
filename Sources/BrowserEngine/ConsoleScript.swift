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

/// Cuenta los errores de la página (consola, errores sin capturar, promesas rechazadas y
/// peticiones que fallan) para el globo rojo del botón de consola en modo desarrollador. La
/// consola y la red de verdad son las del inspector web de WebKit.
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

      // Peticiones que fallan (fetch y XMLHttpRequest): cuentan como avisos o errores.
      const originalFetch = window.fetch;
      if (originalFetch) {
        window.fetch = async (...args) => {
          const target = args[0] instanceof Request ? args[0].url : String(args[0]);
          try {
            const response = await originalFetch(...args);
            if (!response.ok) send({ level: 'warn', text: `fetch ${response.status} ${response.statusText} · ${target}`, source: 'red' });
            return response;
          } catch (error) {
            send({ level: 'error', text: `fetch falló · ${target} · ${error}`, source: 'red' });
            throw error;
          }
        };
      }
      const open = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function (method, url, ...rest) {
        this.addEventListener('loadend', () => {
          if (this.status === 0 || this.status >= 400) {
            send({ level: this.status === 0 ? 'error' : 'warn', text: `XHR ${method} ${this.status || 'sin respuesta'} · ${url}`, source: 'red' });
          }
        });
        return open.call(this, method, url, ...rest);
      };

      window.__sunsetConsole = {
        enable(on) {
          enabled = on;
          if (on) { while (buffer.length) { try { handler.postMessage(buffer.shift()); } catch (_) {} } }
        },
        describe,
      };
    })();
    """
}
