// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MiNavegador",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MiNavegador", targets: ["MiNavegador"]),
    ],
    targets: [
        // Abstracción del motor web. Hoy: WebKit. Mañana: Chromium vía CEF.
        .target(name: "BrowserEngine"),
        // Modelo: espacios, pestañas, carpetas, hibernación y guardado.
        .target(name: "BrowserCore", dependencies: ["BrowserEngine"]),
        // Sistema de diseño compartido (equivalente a ARCUI): colores, vidrio, iconos.
        .target(name: "BrowserUI", dependencies: ["BrowserCore"]),
        // Barra lateral (equivalente a ARC_StorableSidebar / ARC_SidebarPlusButton).
        .target(name: "SidebarFeature", dependencies: ["BrowserEngine", "BrowserCore", "BrowserUI"]),
        // Barra superior con navegación y dirección.
        .target(name: "ToolbarFeature", dependencies: ["BrowserCore", "BrowserUI"]),
        // Command Bar (equivalente a ARC_CommandBar): buscar, abrir y ejecutar acciones.
        .target(name: "CommandBarFeature", dependencies: ["BrowserCore", "BrowserUI"]),
        // Extensiones: botones en la barra, panel de gestión e instalación (Chrome Web Store, .zip, .crx).
        .target(name: "ExtensionsFeature", dependencies: ["BrowserEngine", "BrowserCore", "BrowserUI"]),
        // Librería (equivalente a la Library de Arc): descargas, media, espacios y pestañas archivadas.
        .target(name: "LibraryFeature", dependencies: ["BrowserEngine", "BrowserCore", "BrowserUI"]),
        // Migración desde Arc, Chrome, Safari, Brave y Edge: marcadores, historial, contraseñas y cookies.
        .target(name: "BrowserImport", dependencies: ["BrowserEngine", "BrowserCore"], linkerSettings: [.linkedLibrary("sqlite3")]),
        // Bienvenida del primer arranque (como la de Arc): migrar, apps favoritas, tema y navegador predeterminado.
        .target(name: "OnboardingFeature", dependencies: ["BrowserCore", "BrowserEngine", "BrowserImport", "BrowserUI", "HomeFeature"]),
        // Inicio: reloj, buscador y favoritos; también el modo pantalla compartida.
        .target(name: "HomeFeature", dependencies: ["BrowserCore", "BrowserUI"]),
        // La app: ventana, menús y contenido web.
        .executableTarget(
            name: "MiNavegador",
            dependencies: [
                "BrowserEngine", "BrowserCore", "BrowserUI",
                "SidebarFeature", "ToolbarFeature", "CommandBarFeature", "ExtensionsFeature", "LibraryFeature", "HomeFeature",
                "BrowserImport", "OnboardingFeature",
            ]
        ),
        .testTarget(name: "BrowserCoreTests", dependencies: ["BrowserCore", "BrowserImport"]),
        // Renderiza vistas a PNG para revisarlas sin abrir la app.
        .testTarget(
            name: "UISnapshotTests",
            dependencies: ["BrowserCore", "BrowserEngine", "BrowserUI", "SidebarFeature", "LibraryFeature", "HomeFeature"]
        ),
    ]
)
