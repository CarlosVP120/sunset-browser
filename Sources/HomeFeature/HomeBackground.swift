import SwiftUI
import QuartzCore
import BrowserCore
import BrowserUI

/// Fondo de Inicio: el cielo justo después de la puesta de sol. Arriba es de noche, con estrellas
/// que titilan y alguna estrella fugaz de vez en cuando; abajo queda el resplandor del atardecer
/// (con los colores de Sunset y del espacio). Encima, el grano del tema.
///
/// Todo se anima con Core Animation: lo mueve el compositor del sistema y la app no trabaja en
/// cada fotograma (con SwiftUI costaba ~40 % de CPU en reposo).
struct HomeBackground: View {
    let theme: SpaceTheme

    var body: some View {
        ZStack {
            SkyLayerView(palette: SkyPalette(theme: theme))
            // Un poco de grano siempre: es lo que hace que el degradado se sienta "material".
            GrainOverlay(intensity: max(theme.grain, 0.22))
        }
    }
}

/// Colores del cielo, derivados del tema del espacio para que cada espacio tenga su noche.
struct SkyPalette: Equatable {
    var zenith: SpaceColor
    var horizon: SpaceColor
    var glow: SpaceColor
    var sun: SpaceColor

    init(theme: SpaceTheme) {
        let seed = (theme.seeds.first ?? theme.accent).hsb
        // Si el tema casi no tiene color, el cielo usa el índigo de Sunset.
        let hue = seed.saturation < 0.12 ? Sunset.indigo.hsb.hue : seed.hue
        zenith = SpaceColor(hue: hue, saturation: 0.55, brightness: 0.07)
        horizon = SpaceColor(hue: hue, saturation: 0.6, brightness: 0.2)
        glow = SpaceColor(hue: hue, saturation: 0.65, brightness: 0.85).mixed(with: Sunset.rose, by: 0.6)
        sun = Sunset.orange
    }
}

private struct SkyLayerView: NSViewRepresentable {
    let palette: SkyPalette

    func makeNSView(context: Context) -> SkyView {
        SkyView()
    }

    func updateNSView(_ view: SkyView, context: Context) {
        view.apply(palette)
    }
}

final class SkyView: NSView {
    private let sky = CAGradientLayer()
    private let glow = CAGradientLayer()
    private let sun = CAGradientLayer()
    private let stars = CALayer()
    private let twinkles = CALayer()
    private let shootingStars = CALayer()
    private var palette: SkyPalette?
    private var spawnTimer: Timer?

    /// Las estrellas se generan una vez para una superficie grande y la vista las recorta: así
    /// no se recolocan (ni parpadean) al cambiar el tamaño de la ventana o de la barra lateral.
    private static let field = CGSize(width: 3200, height: 2000)
    private static let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true

        sky.startPoint = CGPoint(x: 0.5, y: 1)
        sky.endPoint = CGPoint(x: 0.5, y: 0)
        glow.type = .radial
        glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        glow.endPoint = CGPoint(x: 1, y: 1)
        sun.type = .radial
        sun.startPoint = CGPoint(x: 0.5, y: 0.5)
        sun.endPoint = CGPoint(x: 1, y: 1)

        [sky, stars, twinkles, glow, sun, shootingStars].forEach { layer?.addSublayer($0) }
        makeStars()

        // El resplandor "respira" muy despacio.
        if !Self.reduceMotion {
            for (layer, duration) in [(glow, 9.0), (sun, 7.0)] {
                let breathe = CABasicAnimation(keyPath: "opacity")
                breathe.fromValue = 0.82
                breathe.toValue = 1
                breathe.duration = duration
                breathe.autoreverses = true
                breathe.repeatCount = .infinity
                breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                layer.add(breathe, forKey: "breathe")
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("No se usa desde Interface Builder") }

    // Solo dibuja: no recibe clics.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func apply(_ palette: SkyPalette) {
        guard palette != self.palette else { return }
        let animated = self.palette != nil
        self.palette = palette
        CATransaction.begin()
        CATransaction.setAnimationDuration(animated ? 0.6 : 0)
        CATransaction.setDisableActions(!animated)
        sky.colors = [palette.zenith, palette.zenith, palette.horizon].map(\.cgColor)
        sky.locations = [0, 0.45, 1]
        glow.colors = [palette.glow.with(alpha: 0.8), palette.glow.with(alpha: 0.3), palette.glow.with(alpha: 0)]
        glow.locations = [0, 0.45, 1]
        sun.colors = [Sunset.gold.with(alpha: 0.85), palette.sun.with(alpha: 0.5), palette.sun.with(alpha: 0)]
        sun.locations = [0, 0.4, 1]
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let bounds = self.bounds
        sky.frame = bounds
        // El resplandor nace bajo el borde inferior: solo asoma su mitad superior.
        glow.bounds = CGRect(x: 0, y: 0, width: bounds.width * 1.6, height: bounds.height * 1.05)
        glow.position = CGPoint(x: bounds.midX, y: bounds.minY - bounds.height * 0.08)
        sun.bounds = CGRect(x: 0, y: 0, width: bounds.width * 0.75, height: bounds.height * 0.42)
        sun.position = CGPoint(x: bounds.midX, y: bounds.minY - bounds.height * 0.04)
        // Estrellas ancladas arriba (en AppKit el origen está abajo).
        let field = CGRect(x: bounds.midX - Self.field.width / 2, y: bounds.maxY - Self.field.height,
                           width: Self.field.width, height: Self.field.height)
        stars.frame = field
        twinkles.frame = field
        shootingStars.frame = bounds
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        spawnTimer?.invalidate()
        spawnTimer = nil
        if window != nil, !Self.reduceMotion { scheduleShootingStar() }
    }

    // MARK: Estrellas

    private func makeStars() {
        var generator = SeededGenerator(seed: 0x5375_6E73_6574)
        let size = Self.field
        let scale: CGFloat = 2

        // Las estrellas fijas van en una sola imagen (cientos de estrellas, una sola capa).
        let width = Int(size.width * scale), height = Int(size.height * scale)
        if let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                   space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            context.scaleBy(x: scale, y: scale)
            for _ in 0..<900 {
                let point = Self.starPoint(in: size, using: &generator)
                let radius = CGFloat.random(in: 0.3...0.95, using: &generator)
                let alpha = CGFloat.random(in: 0.15...0.75, using: &generator) * Self.fade(point.y, height: size.height)
                context.setFillColor(CGColor(red: 1, green: 0.97, blue: 0.94, alpha: alpha))
                context.fillEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
            }
            stars.contents = context.makeImage()
            stars.contentsScale = scale
        }

        // Unas cuantas, más brillantes, titilan cada una a su ritmo.
        for _ in 0..<70 {
            let point = Self.starPoint(in: size, using: &generator)
            let radius = CGFloat.random(in: 0.8...1.5, using: &generator)
            let star = CALayer()
            star.frame = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
            star.cornerRadius = radius
            star.backgroundColor = CGColor(red: 1, green: 0.96, blue: 0.9, alpha: 1)
            star.shadowColor = CGColor(red: 1, green: 0.9, blue: 0.8, alpha: 1)
            star.shadowRadius = radius * 2
            star.shadowOpacity = 0.8
            star.shadowOffset = .zero
            let peak = Float(Self.fade(point.y, height: size.height)) * Float.random(in: 0.6...1, using: &generator)
            star.opacity = peak
            if !Self.reduceMotion {
                let twinkle = CABasicAnimation(keyPath: "opacity")
                twinkle.fromValue = peak
                twinkle.toValue = peak * 0.15
                twinkle.duration = .random(in: 1.8...4.5, using: &generator)
                twinkle.autoreverses = true
                twinkle.repeatCount = .infinity
                twinkle.timeOffset = .random(in: 0...6, using: &generator)
                twinkle.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                star.add(twinkle, forKey: "twinkle")
            }
            twinkles.addSublayer(star)
        }
    }

    /// Un punto al azar, con más estrellas arriba que cerca del horizonte.
    private static func starPoint(in size: CGSize, using generator: inout SeededGenerator) -> CGPoint {
        let depth = pow(CGFloat.random(in: 0...1, using: &generator), 1.6) // 0 = arriba
        return CGPoint(x: .random(in: 0...size.width, using: &generator), y: size.height * (1 - depth))
    }

    /// Las estrellas se apagan al acercarse al resplandor del horizonte.
    private static func fade(_ y: CGFloat, height: CGFloat) -> CGFloat {
        let fromTop = (height - y) / 1100 // en puntos desde arriba; la ventana suele medir < 1100
        return max(0, min(1, 1.25 - fromTop))
    }

    // MARK: Estrellas fugaces

    private func scheduleShootingStar() {
        spawnTimer = Timer.scheduledTimer(withTimeInterval: .random(in: 1.4...4.2), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.window != nil else { return }
                // Solo si la ventana se ve: en segundo plano no gasta nada.
                if self.window?.occlusionState.contains(.visible) == true { self.launchShootingStar() }
                self.scheduleShootingStar()
            }
        }
    }

    private func launchShootingStar() {
        let bounds = self.bounds
        guard bounds.width > 200, bounds.height > 200 else { return }

        // Cruza en diagonal hacia abajo, a veces de izquierda a derecha y a veces al revés.
        let leftToRight = Bool.random()
        let angle = CGFloat.random(in: 0.18...0.42) // radianes bajo la horizontal
        let distance = CGFloat.random(in: 0.45...0.8) * hypot(bounds.width, bounds.height)
        let start = CGPoint(x: .random(in: bounds.width * 0.05...bounds.width * 0.95),
                            y: .random(in: bounds.height * 0.55...bounds.height * 1.02))
        let direction = CGVector(dx: (leftToRight ? 1 : -1) * cos(angle), dy: -sin(angle))
        let end = CGPoint(x: start.x + direction.dx * distance, y: start.y + direction.dy * distance)

        let length = CGFloat.random(in: 90...170)
        let star = CAGradientLayer()
        star.bounds = CGRect(x: 0, y: 0, width: length, height: 1.6)
        star.cornerRadius = 0.8
        // La cabeza (blanca) va delante; la estela se tiñe de los colores del atardecer.
        star.anchorPoint = CGPoint(x: 1, y: 0.5)
        star.startPoint = CGPoint(x: 0, y: 0.5)
        star.endPoint = CGPoint(x: 1, y: 0.5)
        star.colors = [Sunset.rose.with(alpha: 0), Sunset.coral.with(alpha: 0.45), Sunset.gold.with(alpha: 0.85),
                       CGColor(red: 1, green: 1, blue: 1, alpha: 1)]
        star.locations = [0, 0.5, 0.88, 1]
        star.shadowColor = Sunset.gold.cgColor
        star.shadowRadius = 3
        star.shadowOpacity = 0.9
        star.shadowOffset = .zero
        star.position = start
        star.transform = CATransform3DMakeRotation(atan2(direction.dy, direction.dx), 0, 0, 1)
        star.opacity = 0

        let duration = CFTimeInterval.random(in: 0.9...1.5)
        let move = CABasicAnimation(keyPath: "position")
        move.fromValue = NSValue(point: start)
        move.toValue = NSValue(point: end)
        move.timingFunction = CAMediaTimingFunction(controlPoints: 0.3, 0.1, 0.6, 1)

        // La estela crece al arrancar y se encoge al apagarse.
        let stretch = CAKeyframeAnimation(keyPath: "bounds.size.width")
        stretch.values = [length * 0.1, length, length * 0.6]
        stretch.keyTimes = [0, 0.45, 1]

        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 1, 0]
        fade.keyTimes = [0, 0.12, 0.7, 1]

        let group = CAAnimationGroup()
        group.animations = [move, stretch, fade]
        group.duration = duration

        CATransaction.begin()
        CATransaction.setCompletionBlock { star.removeFromSuperlayer() }
        shootingStars.addSublayer(star)
        star.add(group, forKey: "shoot")
        CATransaction.commit()
    }
}

private extension SpaceColor {
    var cgColor: CGColor { CGColor(red: red, green: green, blue: blue, alpha: alpha) }
    func with(alpha: Double) -> CGColor { CGColor(red: red, green: green, blue: blue, alpha: alpha) }
}

/// Azar repetible: las estrellas quedan siempre en el mismo sitio (el cielo "es el mismo").
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        // SplitMix64
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
