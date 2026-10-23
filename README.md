# Sunset Browser

Navegador para macOS inspirado en Arc, construido con el mismo stack: Swift, SwiftUI, AppKit
y Swift Package Manager. Ver [docs/arc-stack.md](docs/arc-stack.md) para el inventario completo.

## Ejecutar

```bash
./scripts/bundle.sh && open "build/Sunset Browser.app"
```

O abrir una URL directamente:

```bash
open -a "build/Sunset Browser.app" https://www.apple.com
```

Tests: `swift test`

## Estructura

| Módulo | Qué contiene |
|---|---|
| `BrowserEngine` | Protocolos `WebEngine` / `WebPage` y el motor provisional `WebKitEngine` |
| `BrowserCore` | Modelo: `Browser`, `Space`, `BrowserTab`, `URLInput` |
| `SidebarFeature` | Barra lateral: campo de URL, pestañas fijadas, pestañas y espacios |
| `MiNavegador` | La app: ventana, contenido web y atajos de teclado |

## Atajos

| Atajo | Acción |
|---|---|
| ⌘T | Nueva pestaña |
| ⌘L | Ir al campo de URL |
| ⌘W | Cerrar pestaña |
| ⌘D | Fijar / desfijar pestaña |
| ⌘[ / ⌘] | Atrás / adelante |
| ⌘R | Recargar |
| ⌃1…⌃9 | Cambiar de espacio |

## Siguiente paso: Chromium

Hoy las páginas se renderizan con WebKit. Para usar Chromium (como Arc) añadiremos un
`CEFEngine` que implemente `WebEngine`. Chromium está escrito en C++, así que esa pieza
necesitará un puente en Objective-C++ (`.mm`) o la interoperabilidad de Swift con C++.
El resto de la app no cambia.

## Instalador

```bash
./scripts/make-dmg.sh
```

Crea `build/Sunset-Browser.dmg` (versión optimizada, con la ventana de "Arrastra Sunset a Aplicaciones").

## Migrar desde otro navegador

La primera vez que se abre, Sunset muestra una bienvenida que trae espacios, marcadores, historial,
contraseñas y sesiones abiertas desde Arc, Chrome, Safari, Brave o Edge (solo lee: el otro navegador
no cambia). Después, desde **Archivo › Importar de otro navegador…**.
