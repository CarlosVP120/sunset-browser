import Foundation

/// La API `Notification` de las páginas, hecha por Sunset. La de WKWebView existe pero no hace nada:
/// el permiso se queda en "default" y nunca se muestra un aviso (Safari usa funciones privadas de
/// WebKit para las suyas). Este script la sustituye por una que pasa cada notificación a
/// `WebNotifications`, que la enseña como notificación de macOS. Cubre `new Notification(…)`,
/// `Notification.requestPermission()`, `navigator.permissions.query({ name: 'notifications' })` y
/// `registration.pushManager` (Web Push, ver `WebPushService`).
///
/// El permiso se lee de forma síncrona (`Notification.permission` no es una promesa) con un
/// `prompt()` especial que Sunset contesta al momento sin mostrar nada; así es correcto desde el
/// primer script de la página. Después, Sunset avisa de los cambios con `setPermission`.
enum NotificationScript {
    static let handlerName = "sunsetNotifications"
    /// El texto del `prompt()` con el que el script pregunta el permiso del sitio.
    static let permissionQuery = "\u{1}sunset-notification-permission"

    static let source = """
    (() => {
      if (window.__sunsetNotifications || window.top !== window) return;
      const handler = window.webkit?.messageHandlers?.\(handlerName);
      if (!handler) return;

      let permission = null;
      const current = () => permission ??= (window.prompt('\\u0001sunset-notification-permission') || 'default');
      const statuses = new Set();
      const live = new Map();
      const absolute = url => { try { return url ? new URL(url, location.href).href : ''; } catch { return ''; } };

      function fire(target, type) {
        const event = new Event(type, { cancelable: type === 'click' });
        try { target['on' + type]?.call(target, event); } catch (error) { setTimeout(() => { throw error; }); }
        target.dispatchEvent(event);
      }

      function post(title, options) {
        return handler.postMessage({
          type: 'show', title: String(title), body: String(options.body ?? ''), tag: String(options.tag ?? ''),
          icon: absolute(options.icon || options.image), silent: !!options.silent,
        });
      }

      class Notification extends EventTarget {
        #id = null;
        constructor(title, options = {}) {
          super();
          if (arguments.length === 0) throw new TypeError("Failed to construct 'Notification': 1 argument required.");
          Object.assign(this, {
            title: String(title), body: String(options.body ?? ''), tag: String(options.tag ?? ''),
            icon: absolute(options.icon), image: absolute(options.image), badge: absolute(options.badge),
            data: options.data ?? null, dir: options.dir ?? 'auto', lang: options.lang ?? '',
            silent: !!options.silent, requireInteraction: !!options.requireInteraction, renotify: !!options.renotify,
            actions: [], timestamp: options.timestamp ?? Date.now(),
            onclick: null, onshow: null, onclose: null, onerror: null,
          });
          if (current() !== 'granted') { setTimeout(() => fire(this, 'error')); return; }
          post(title, options).then(id => {
            if (!id) return fire(this, 'error');
            this.#id = id;
            for (const [other, n] of live) if (n.tag && n.tag === this.tag && n !== this) live.delete(other);
            live.set(id, this);
            fire(this, 'show');
          });
        }
        close() {
          if (!this.#id || !live.has(this.#id)) return;
          live.delete(this.#id);
          handler.postMessage({ type: 'close', id: this.#id });
          fire(this, 'close');
        }
        static get permission() { return current(); }
        static get maxActions() { return 0; }
        static requestPermission(callback) {
          return handler.postMessage({ type: 'request' }).then(result => {
            setPermission(result || 'default');
            if (typeof callback === 'function') callback(permission);
            return permission;
          });
        }
      }

      function setPermission(value) {
        if (value === permission) return;
        permission = value;
        for (const status of statuses) fire(status, 'change');
      }

      Object.defineProperty(window, 'Notification', { value: Notification, writable: true, configurable: true });

      // Web Push: WebKit solo sabe suscribirse con el servicio de Safari (exclusivo de Apple), así
      // que `pushManager` de cada registro pide las suscripciones a Sunset (ver `WebPushService`).
      // Los mensajes y `registration.showNotification` sí los lleva WebKit hasta el service worker.
      if (window.ServiceWorkerRegistration && window.PushManager) {
        const toBase64URL = key => {
          if (key == null) return null;
          if (typeof key === 'string') return key.replace(/=+$/, '');
          const bytes = new Uint8Array(ArrayBuffer.isView(key) ? key.buffer.slice(key.byteOffset, key.byteOffset + key.byteLength) : key);
          return btoa(String.fromCharCode(...bytes)).replace(/\\+/g, '-').replace(/\\//g, '_').replace(/=+$/, '');
        };
        const fromBase64URL = text => Uint8Array.from(atob(text.replace(/-/g, '+').replace(/_/g, '/')), c => c.charCodeAt(0)).buffer;
        const subscriptionFrom = (info, scope, options) => {
          if (!info) return null;
          const subscription = Object.create(PushSubscription.prototype);
          const keys = { p256dh: info.p256dh, auth: info.auth };
          Object.defineProperties(subscription, {
            endpoint: { value: info.endpoint, enumerable: true },
            expirationTime: { value: null, enumerable: true },
            options: { value: Object.freeze({ userVisibleOnly: true, applicationServerKey: info.key ? fromBase64URL(info.key) : null }), enumerable: true },
            getKey: { value: name => keys[name] ? fromBase64URL(keys[name]) : null },
            toJSON: { value: () => ({ endpoint: info.endpoint, expirationTime: null, keys }) },
            unsubscribe: { value: () => handler.postMessage({ type: 'unsubscribe', scope }).then(Boolean) },
          });
          return subscription;
        };
        const managers = new WeakMap();
        const pushManagerFor = registration => {
          if (managers.has(registration)) return managers.get(registration);
          const scope = registration.scope;
          const manager = Object.create(PushManager.prototype);
          Object.defineProperties(manager, {
            subscribe: { value: async (options = {}) => {
              const key = toBase64URL(options.applicationServerKey);
              const result = await handler.postMessage({ type: 'subscribe', scope, key });
              if (!result || result.error) throw new DOMException(result?.error || 'Push subscription failed', result?.name || 'AbortError');
              setPermission('granted');
              return subscriptionFrom(result, scope, options);
            } },
            getSubscription: { value: async () => subscriptionFrom(await handler.postMessage({ type: 'getSubscription', scope }), scope) },
            permissionState: { value: async () => current() === 'default' ? 'prompt' : current() },
          });
          managers.set(registration, manager);
          return manager;
        };
        Object.defineProperty(ServiceWorkerRegistration.prototype, 'pushManager', {
          get() { return pushManagerFor(this); }, configurable: true, enumerable: true,
        });
      }

      const query = navigator.permissions?.query?.bind(navigator.permissions);
      if (query) {
        const state = () => current() === 'default' ? 'prompt' : current();
        navigator.permissions.query = function (descriptor) {
          if (descriptor?.name !== 'notifications') return query(descriptor);
          const status = new EventTarget();
          Object.defineProperty(status, 'state', { get: state, enumerable: true });
          Object.defineProperty(status, 'name', { value: descriptor.name, enumerable: true });
          status.onchange = null;
          statuses.add(status);
          return Promise.resolve(status);
        };
      }

      window.__sunsetNotifications = {
        setPermission,
        click(id) { const n = live.get(id); if (n) { window.focus(); fire(n, 'click'); } },
        closed(id) { const n = live.get(id); if (n) { live.delete(id); fire(n, 'close'); } },
      };
    })();
    """
}
