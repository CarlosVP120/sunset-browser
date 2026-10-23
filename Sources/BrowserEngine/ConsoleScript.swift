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

      // Peticiones que fallan (fetch y XMLHttpRequest).
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
