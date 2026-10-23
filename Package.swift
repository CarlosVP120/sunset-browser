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
        // Modelo: espacios, pestañas y estado del navegador.
        .target(name: "BrowserCore", dependencies: ["BrowserEngine"]),
        // Barra lateral (equivalente a ARC_StorableSidebar / ARC_SidebarPlusButton).
        .target(name: "SidebarFeature", dependencies: ["BrowserCore"]),
        // La app: ventana, menús y contenido web.
        .executableTarget(
            name: "MiNavegador",
            dependencies: ["BrowserEngine", "BrowserCore", "SidebarFeature"]
        ),
        .testTarget(name: "BrowserCoreTests", dependencies: ["BrowserCore"]),
    ]
)
