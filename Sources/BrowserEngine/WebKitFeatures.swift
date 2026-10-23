import WebKit

/// Ajustes internos de WebKit (los "Feature Flags" del menú Desarrollo de Safari) para que el
/// scroll se sienta como en Chromium/Arc. Si una versión de macOS no los tiene, no se hace nada.
enum WebKitFeatures {
    /// Medido en un monitor de 144 Hz: con el valor por defecto la página se dibuja a ~68 fps;
    /// desactivándolo, a 144 fps (la frecuencia de la pantalla, como Chromium).
    static let preferNear60FPS = "PreferPageRenderingUpdatesNear60FPSEnabled"
    /// Anima cada paso de la rueda del ratón en vez de saltar línea a línea (como Chromium).
    static let scrollAnimator = "ScrollAnimatorEnabled"

    /// Aplica los ajustes de fluidez a unas preferencias de WebKit.
    @MainActor
    static func applySmoothScrolling(to preferences: WKPreferences) {
        set(preferNear60FPS, enabled: false, on: preferences)
        set(scrollAnimator, enabled: true, on: preferences)
    }

    @MainActor
    @discardableResult
    static func set(_ key: String, enabled: Bool, on preferences: WKPreferences) -> Bool {
        guard let feature = features.first(where: { ($0.value(forKey: "key") as? String) == key }) else { return false }
        let selector = NSSelectorFromString("_setEnabled:forFeature:")
        guard let method = class_getInstanceMethod(WKPreferences.self, selector) else { return false }
        typealias Setter = @convention(c) (AnyObject, Selector, Bool, AnyObject) -> Void
        unsafeBitCast(method_getImplementation(method), to: Setter.self)(preferences, selector, enabled, feature)
        return true
    }

    @MainActor
    private static let features: [NSObject] = {
        let selector = NSSelectorFromString("_features")
        guard (WKPreferences.self as AnyObject).responds(to: selector) else { return [] }
        return (WKPreferences.self as AnyObject).perform(selector)?.takeUnretainedValue() as? [NSObject] ?? []
    }()
}
