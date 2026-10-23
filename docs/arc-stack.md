# El stack de Arc (referencia)

Inventario de los módulos y componentes que trae **Arc 1.169.0** (binario universal x86_64 + arm64),
obtenido listando el contenido del bundle `/Applications/Arc.app`. Solo nombres y propósito: no
contiene código, recursos ni assets de Arc.

> **Ojo:** el propósito de los módulos propios de Arc (`ARC_*`, `ARCClients_*`, etc.) está **deducido
> de su nombre** y de cómo funciona Arc por fuera; no es documentación oficial.
>
> Los módulos propios de Arc son propiedad de The Browser Company y **no se pueden reutilizar**:
> sirven como lista de funcionalidades a reimplementar. Las librerías de terceros (sección 3) sí
> son open source y se pueden usar respetando su licencia.

---

## 1. Lenguaje, plataforma y frameworks de Apple

| Tecnología | Para qué |
|---|---|
| Swift (incl. Concurrency, RegexBuilder, Synchronization) | Lenguaje principal de la app |
| Objective-C / C++ (`libobjc`, `libc++`) | Puente con Chromium y APIs antiguas de macOS |
| SwiftUI | Gran parte de la interfaz |
| AppKit | Ventanas, menús, integración nativa con macOS |
| Combine | Programación reactiva / flujo de estado |
| Swift Package Manager | Modularización (cada `*.bundle` es el bundle de recursos de un paquete SPM) |
| CoreData | Persistencia local |
| CloudKit | Sincronización de la barra lateral entre dispositivos |
| WebKit | Vistas web auxiliares (no es el motor principal) |
| Metal / MetalKit / CoreImage / QuartzCore / CoreGraphics / CoreText | Gráficos, efectos, degradados y animaciones de la UI |
| SpriteKit / SceneKit / GameplayKit / ModelIO / Spatial | Efectos visuales y animaciones especiales |
| AVFoundation / AVKit / AVFAudio / CoreMedia / CoreVideo / CoreAudio / CoreMIDI | Multimedia, controles de reproducción, PiP, efectos de sonido |
| ScreenCaptureKit | Capturas de pantalla y grabación (Capture) |
| NaturalLanguage | Procesamiento de texto (funciones de IA / Ask Arc) |
| PDFKit | Visor de PDF |
| QuickLookUI / QuickLookThumbnailing | Vistas previas de archivos |
| CoreLocation / MapKit | Ubicación y mapas |
| UserNotifications | Notificaciones |
| CryptoKit / Security | Criptografía, llavero |
| SystemConfiguration / Network / CFNetwork | Estado de la red y conexiones |
| ScriptingBridge + `Arc.sdef` | Soporte de AppleScript |
| MetricKit | Métricas de rendimiento |
| Carbon / IOKit / XPC | Atajos de teclado globales, hardware, comunicación entre procesos |
| `libz`, `libxml2`, `libcompression` | Compresión y parseo de XML |

## 2. Motor del navegador (Chromium)

| Componente | Para qué |
|---|---|
| `ArcCore.framework` (v155.0.8059.80) | Chromium 155 compilado como framework: el motor que muestra las páginas web |
| `ADK_ADK.bundle` | "Arc Development Kit" (probable): la capa propia de Arc que conecta Swift con Chromium |
| `Browser Helper.app` | Proceso auxiliar general de Chromium |
| `Browser Helper (Renderer).app` | Proceso que renderiza cada página (aislado por sandbox) |
| `Browser Helper (GPU).app` | Proceso de aceleración gráfica |
| `Browser Helper (Alerts).app` | Notificaciones web |
| `Browser Helper (Aperitif…)` + `libaperitif.dylib` | Runtime interno de Arc con sus propios procesos (propósito no identificado) |
| `app_mode_loader` | Lanzador de web apps instaladas como apps |
| `libvk_swiftshader.dylib`, `libvulkan.dylib` | Renderizado gráfico por software (respaldo cuando no hay GPU) |
| `DevTools` | Herramientas para desarrolladores de Chromium |
| `MEIPreload` | Datos de reproducción automática de medios (Media Engagement Index) |
| `PrivacySandboxAttestationsPreloaded` | Lista de Privacy Sandbox de Chrome |
| `IwaKeyDistribution` | Claves de Isolated Web Apps |
| `chrome_100_percent.pak`, `chrome_200_percent.pak` | Recursos de Chromium |
| `*.lproj` | Traducciones de Chromium |

## 3. Librerías de terceros (open source)

| Librería | Versión | Para qué | Licencia |
|---|---|---|---|
| Sparkle | 2.9.4 | Actualizaciones automáticas | MIT |
| Lottie | — | Animaciones vectoriales | Apache-2.0 |
| Sentry | 8.53.1 | Reporte de fallos y errores | MIT |
| Datadog (DatadogCore) | — | Monitorización y telemetría | Apache-2.0 |
| LaunchDarkly | — | Feature flags (activar funciones de forma remota) | Apache-2.0 |
| Firebase Core / Auth / Firestore | Firestore 10.27.0 | Cuentas de usuario y base de datos en la nube | Apache-2.0 |
| gRPC / gRPC++ | 1.62.1 | Comunicación con Firestore | Apache-2.0 |
| abseil (absl) | 20240116.2 | Librería base de C++ (dependencia de gRPC) | Apache-2.0 |
| openssl_grpc (BoringSSL) | 0.0.32 | TLS para gRPC | OpenSSL / ISC |
| leveldb | — | Caché local de Firestore | BSD-3 |
| nanopb | — | Protocol Buffers ligeros (dependencia de Firebase) | zlib |
| Promises (FBLPromises) | — | Promesas (dependencia de Firebase) | Apache-2.0 |
| GoogleUtilities | — | Utilidades de Firebase (red, logger, entorno…) | Apache-2.0 |
| GTMSessionFetcher | — | Peticiones HTTP (dependencia de Firebase Auth) | Apache-2.0 |
| SDWebImage | — | Descarga y caché de imágenes | MIT |
| YouTubePlayerKit | — | Reproductor de YouTube embebido | MIT |
| ZIPFoundation | — | Comprimir y descomprimir ZIP | MIT |
| DomainParser | — | Analizar dominios (Public Suffix List) | MIT |
| swift-crypto | — | Criptografía | Apache-2.0 |
| Settings | — | Ventana de preferencias (probablemente `sindresorhus/Settings`) | MIT |

## 4. Módulos base de Arc

| Módulo | Para qué |
|---|---|
| `ARCFoundation_ARCFoundationBase` | Utilidades base compartidas por toda la app |
| `ARCUI_ARCUI` | Sistema de diseño: componentes visuales reutilizables |
| `ARCClients_AppRestartClient` | Reiniciar la app (por ejemplo, tras actualizar) |
| `ARCClients_BaseAssets` | Recursos gráficos comunes |
| `ARCClients_BlockListClient` | Listas de bloqueo (anuncios / rastreadores) |
| `ARCClients_FontsManager` | Gestión de tipografías |
| `ARCClients_Icons` | Catálogo de iconos |

## 5. Funcionalidades de Arc (`ARC_*`)

### Barra lateral y espacios
| Módulo | Para qué |
|---|---|
| `ARC_StorableSidebar` | Modelo y guardado de la barra lateral (pestañas, carpetas, fijadas) |
| `ARC_SidebarSyncCloudKit` | Sincronización de la barra lateral vía CloudKit |
| `ARC_SidebarPlusButton` | Botón "+" de la barra lateral |
| `ARC_SidebarBanner` | Avisos y banners dentro de la barra lateral |
| `ARC_SpaceCreation` | Crear espacios |
| `ARC_SpaceStyleEditor` | Personalizar colores, degradados e icono de cada espacio |
| `ARC_ProfilesUI` | Perfiles (cookies y sesiones separadas por espacio) |
| `ARC_HomeButton` | Botón de inicio |
| `ARC_BaseHomeComponents` | Componentes de la página de inicio |
| `ARC_TopDomains` | Sitios más visitados (también `popularDomains.json`) |
| `ARC_Favicons` | Iconos de los sitios |

### Navegación y búsqueda
| Módulo | Para qué |
|---|---|
| `ARC_CommandBar` | Barra de comandos (Cmd+T / Cmd+L): buscar, abrir y ejecutar acciones |
| `ARC_URLInputter` | Campo de URL y autocompletado |
| `ARC_LittleBrowser` | Mini navegador emergente para abrir enlaces rápidos |
| `ARC_ContentPanel` | Panel de contenido / vista dividida |
| `ARC_ContextMenus` | Menús contextuales (clic derecho) |
| `ARC_ArcMenu` | Menú principal de Arc |
| `ARC_SadTab` | Pantalla cuando una pestaña falla |
| `ARC_GlowProgressLoadingIndicator` | Indicador de carga con brillo |
| `ARC_WindowThemeUI` | Tema y color de la ventana |

### Personalización de sitios
| Módulo | Para qué |
|---|---|
| `ARC_BoostsEditor` | Editor de Boosts (CSS/JS propio por sitio) |
| `ARC_BoostsDialog` | Diálogo para crear y gestionar Boosts |
| `ARC_SiteControlCenter` | Panel de permisos y ajustes por sitio |
| `ARC_WebContentBehaviorConfigurationClient` | Configuración remota del comportamiento con ciertos sitios |
| `ARC_AdBlocking` | Bloqueo de anuncios |
| `ARC_Translation` | Traducción de páginas |

### Medios
| Módulo | Para qué |
|---|---|
| `ARC_MediaControlsFeature` | Controles de reproducción en la barra lateral |
| `ARC_PictureInPicture` | Vídeo flotante (imagen en imagen) |
| `ARC_SoundEffects` | Efectos de sonido de la interfaz |

### Creación y notas
| Módulo | Para qué |
|---|---|
| `ARC_EaselUI` | Easels: lienzos para combinar capturas, texto y dibujos |
| `ARC_Capture` | Capturas de pantalla de páginas |
| `ARC_TextEditor` | Editor de texto (Notas) |
| `ARC_ArcRichTextEditor` | Editor de texto enriquecido |
| `ARC_Emojis` | Selector de emojis (iconos de espacios y carpetas) |
| `ARC_SharableObjectsFeature` | Compartir espacios, carpetas y Easels |

### IA
| Módulo | Para qué |
|---|---|
| `ARC_AskArc` | Funciones de IA ("Ask Arc": preguntar a la página, resúmenes) |

### Cuenta, ajustes y app
| Módulo | Para qué |
|---|---|
| `ARC_AuthFeature` | Inicio de sesión con cuenta de Arc |
| `ARC_DeleteAccountFeature` | Borrar la cuenta |
| `ARC_MembershipCard` | Tarjeta de miembro de Arc |
| `ARC_ReferralCodeFeature` | Códigos de invitación |
| `ARC_PreferencesFeature` | Ventana de preferencias |
| `ARC_CustomInfoPicker` | Selector de información personalizada (ajustes) |
| `ARC_ImportFeature` | Importar datos de otros navegadores |
| `ARC_ImportMenuFeature` | Menú de importación |
| `ARC_WelcomeToArcFeature` | Bienvenida y onboarding |
| `ARC_AboutWindow` | Ventana "Acerca de" |
| `ARC_AppTray` | Icono / menú en la barra de menús |
| `ARC_SoftwareUpdaterClient` | Cliente de actualizaciones (sobre Sparkle) |

## 6. Otros archivos del bundle

| Archivo | Para qué |
|---|---|
| `PlugIns/DockTilePlugIn.plugin` | Personalizar el icono del Dock |
| `Arc.sdef` | Definición de la API de AppleScript |
| `GoogleService-Info.plist` | Configuración de Firebase |
| `popularDomains.json` | Lista de dominios populares para autocompletar |
| `Assets.car`, `AppIcon.icns` | Catálogo de imágenes e icono de la app |
| `embedded.provisionprofile` | Perfil de aprovisionamiento de Apple (firma y permisos) |

---

## Equivalente para nuestro navegador

| Pieza de Arc | Qué usamos nosotros |
|---|---|
| Swift + SwiftUI + AppKit + SPM | Igual |
| `ArcCore` + `ADK` (Chromium embebido, privado) | Chromium compilado por nosotros, o **CEF** (Chromium Embedded Framework, BSD) como atajo |
| Sparkle, Lottie, Sentry, SDWebImage, ZIPFoundation, DomainParser, swift-crypto | Igual (open source) |
| Firebase (cuentas + Firestore) | Firebase con **nuestro propio** proyecto, o solo sincronización con CloudKit |
| LaunchDarkly / Datadog | Opcionales (de pago); se pueden dejar para más adelante |
| Módulos `ARC_*` | Reimplementar desde cero con nuestro propio diseño |
