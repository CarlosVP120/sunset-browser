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
        .target(name: "SidebarFeature", dependencies: ["BrowserCore", "BrowserUI"]),
        // Barra superior con navegación y dirección.
        .target(name: "ToolbarFeature", dependencies: ["BrowserCore", "BrowserUI"]),
        // Command Bar (equivalente a ARC_CommandBar): buscar, abrir y ejecutar acciones.
        .target(name: "CommandBarFeature", dependencies: ["BrowserCore", "BrowserUI"]),
        // La app: ventana, menús y contenido web.
        .executableTarget(
            name: "MiNavegador",
            dependencies: [
                "BrowserEngine", "BrowserCore", "BrowserUI",
                "SidebarFeature", "ToolbarFeature", "CommandBarFeature",
            ]
        ),
        .testTarget(name: "BrowserCoreTests", dependencies: ["BrowserCore"]),
    ]
)
