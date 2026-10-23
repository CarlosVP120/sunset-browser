import SwiftUI
import BrowserCore
import BrowserUI

/// Editor del tema de un espacio, como el de Arc (y un poco más):
/// apariencia, panel de color con hasta 3 colores (degradado), muestras, grano e intensidad.
/// Todos los cambios se ven al instante en la ventana.
struct ThemeEditor: View {
    let browser: Browser
    let space: Space

    @State private var original: SpaceTheme?
    @State private var selected = 0
    @State private var page = 0

    private var theme: SpaceTheme { space.theme }
    private static let maxColors = 3
    private static let swatchesPerPage = 8

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                ColorPad(
                    seeds: theme.seeds,
                    rendered: renderedTheme.background,
                    selected: $selected,
                    onChange: { index, color in update(seedAt: index, to: color) },
                    onAdd: { color in addSeed(color) }
                )
                VStack {
                    AppearancePicker(appearance: theme.appearance) { apply(appearance: $0) }
                    Spacer()
                    HStack(spacing: 14) {
                        Button { removeSeed() } label: { Image(systemName: "minus") }
                            .disabled(theme.seeds.count <= 1)
                            .tooltip("Quitar color")
                        Button { addSeed(nil) } label: { Image(systemName: "plus") }
                            .disabled(theme.seeds.count >= Self.maxColors)
                            .tooltip("Añadir color (o doble clic en el panel)")
                    }
                    .buttonStyle(ChromeButtonStyle(size: 28))
                }
                .padding(12)
            }
            .frame(height: 300)

            PaletteRow(page: $page, perPage: Self.swatchesPerPage, current: theme.seeds) { seeds in
                apply(seeds: seeds)
                selected = 0
            }

            HStack(spacing: 18) {
                GrainSlider(value: Binding(get: { theme.grain }, set: { apply(grain: $0) }))
                    .tooltip("Grano")
                IntensityDial(value: Binding(get: { theme.intensity }, set: { apply(intensity: $0) }))
                    .tooltip("Intensidad del color")
            }
            .padding(.horizontal, 4)

            HStack {
                Button {
                    if let original { browser.setTheme(original, for: space) }
                } label: {
                    Label("Restablecer", systemImage: "arrow.uturn.backward")
                }
                .disabled(original == nil || original == theme)
                Spacer()
                Button { shuffle() } label: {
                    Label("Aleatorio", systemImage: "dice")
                }
            }
            .buttonStyle(.borderless)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.75))
        }
        .padding(14)
        .frame(width: 340)
        .environment(\.colorScheme, .dark)
        .onAppear { if original == nil { original = theme } }
    }

    // MARK: - Cambios

    private var systemIsDark: Bool {
        NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private var renderedTheme: SpaceTheme { theme.resolved(systemIsDark: systemIsDark) }

    private func apply(
        seeds: [SpaceColor]? = nil,
        appearance: SpaceTheme.Appearance? = nil,
        intensity: Double? = nil,
        grain: Double? = nil
    ) {
        let newTheme = SpaceTheme.make(
            seeds: seeds ?? theme.seeds,
            appearance: appearance ?? theme.appearance,
            intensity: intensity ?? theme.intensity,
            grain: grain ?? theme.grain,
            systemIsDark: systemIsDark
        )
        browser.setTheme(newTheme, for: space)
    }

    private func update(seedAt index: Int, to color: SpaceColor) {
        var seeds = theme.seeds
        guard seeds.indices.contains(index) else { return }
        seeds[index] = color
        apply(seeds: seeds)
    }

    private func addSeed(_ color: SpaceColor?) {
        guard theme.seeds.count < Self.maxColors else { return }
        // Sin posición: un color armónico, desplazado en el círculo cromático.
        let last = theme.seeds.last?.hsb ?? (hue: 0.6, saturation: 0.6, brightness: 1)
        let new = color ?? SpaceColor(hue: last.hue + 0.12, saturation: max(0.4, last.saturation), brightness: 1)
        withAnimation(Theme.spring) { apply(seeds: theme.seeds + [new]) }
        selected = theme.seeds.count - 1
    }

    private func removeSeed() {
        guard theme.seeds.count > 1 else { return }
        var seeds = theme.seeds
        seeds.remove(at: min(selected, seeds.count - 1))
        withAnimation(Theme.spring) { apply(seeds: seeds) }
        selected = max(0, min(selected, seeds.count - 1))
    }

    private func shuffle() {
        let hue = Double.random(in: 0...1)
        let count = Int.random(in: 1...2)
        let seeds = (0..<count).map { index in
            SpaceColor(hue: hue + Double(index) * Double.random(in: 0.08...0.25),
                       saturation: Double.random(in: 0.45...0.9), brightness: 1)
        }
        withAnimation(Theme.spring) {
            apply(seeds: seeds, intensity: Double.random(in: 0.3...0.75), grain: Double.random(in: 0.15...0.5))
        }
        selected = 0
    }
}

// MARK: - Panel de color

/// Panel cuadrado: el ángulo alrededor del centro es el tono y la distancia, la saturación.
/// Los puntos de la rejilla se tiñen con su color, para ver el resultado antes de arrastrar.
private struct ColorPad: View {
    let seeds: [SpaceColor]
    let rendered: [SpaceColor]
    @Binding var selected: Int
    let onChange: (Int, SpaceColor) -> Void
    let onAdd: (SpaceColor) -> Void

    @State private var dragging: Int?

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                Canvas { context, canvasSize in
                    let spacing: CGFloat = 12
                    var y = spacing / 2
                    while y < canvasSize.height {
                        var x = spacing / 2
                        while x < canvasSize.width {
                            let color = Self.color(at: CGPoint(x: x, y: y), in: canvasSize)
                            let rect = CGRect(x: x - 1.1, y: y - 1.1, width: 2.2, height: 2.2)
                            context.fill(Path(ellipseIn: rect), with: .color(Color(color).opacity(0.55)))
                            x += spacing
                        }
                        y += spacing
                    }
                }
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.06)))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .onTapGesture(count: 2, coordinateSpace: .local) { location in
                    onAdd(Self.color(at: location, in: size))
                }

                ForEach(Array(seeds.enumerated()), id: \.offset) { index, seed in
                    let isSelected = index == selected
                    Circle()
                        .fill(Color(rendered.indices.contains(index) ? rendered[index] : seed))
                        .frame(width: 34, height: 34)
                        .overlay(Circle().strokeBorder(.white, lineWidth: isSelected ? 4.5 : 3))
                        .shadow(color: .black.opacity(0.35), radius: dragging == index ? 10 : 5, y: 2)
                        .scaleEffect(dragging == index ? 1.15 : (isSelected ? 1.05 : 0.95))
                        .position(Self.point(for: seed, in: size))
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { drag in
                                    if dragging != index {
                                        dragging = index
                                        selected = index
                                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                                    }
                                    onChange(index, Self.color(at: drag.location, in: size))
                                }
                                .onEnded { _ in dragging = nil }
                        )
                        .animation(Theme.pressSpring, value: dragging)
                        .animation(Theme.spring, value: isSelected)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
    }

    private static func radius(in size: CGSize) -> CGFloat {
        min(size.width, size.height) / 2 - 22
    }

    static func color(at point: CGPoint, in size: CGSize) -> SpaceColor {
        let dx = point.x - size.width / 2
        let dy = point.y - size.height / 2
        let hue = (atan2(-dy, dx) / (2 * .pi) + 1).truncatingRemainder(dividingBy: 1)
        let saturation = min(1, hypot(dx, dy) / radius(in: size))
        return SpaceColor(hue: hue, saturation: saturation, brightness: 1)
    }

    static func point(for color: SpaceColor, in size: CGSize) -> CGPoint {
        let hsb = color.hsb
        let angle = hsb.hue * 2 * .pi
        let distance = hsb.saturation * radius(in: size)
        return CGPoint(x: size.width / 2 + cos(angle) * distance, y: size.height / 2 - sin(angle) * distance)
    }
}

// MARK: - Apariencia

private struct AppearancePicker: View {
    let appearance: SpaceTheme.Appearance
    let onSelect: (SpaceTheme.Appearance) -> Void

    var body: some View {
        HStack(spacing: 6) {
            option(.auto, symbol: "sparkles", label: "Automático")
            option(.light, symbol: "sun.max.fill", label: "Claro")
            option(.dark, symbol: "moon.stars.fill", label: "Oscuro")
        }
    }

    private func option(_ value: SpaceTheme.Appearance, symbol: String, label: String) -> some View {
        Button { withAnimation(Theme.spring) { onSelect(value) } } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 40, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.white.opacity(appearance == value ? 0.12 : 0))
                )
                .foregroundStyle(.white.opacity(appearance == value ? 0.95 : 0.5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tooltip(label)
    }
}

// MARK: - Muestras

private struct PaletteRow: View {
    @Binding var page: Int
    let perPage: Int
    let current: [SpaceColor]
    let onPick: ([SpaceColor]) -> Void

    var body: some View {
        let presets = SpaceTheme.presetSeeds
        let pages = (presets.count + perPage - 1) / perPage
        let visible = presets.dropFirst(page * perPage).prefix(perPage)

        HStack(spacing: 4) {
            Button { withAnimation(Theme.spring) { page = max(0, page - 1) } } label: { Image(systemName: "chevron.left") }
                .disabled(page == 0)
            HStack(spacing: 6) {
                ForEach(Array(visible.enumerated()), id: \.offset) { _, seeds in
                    Swatch(seeds: seeds, isSelected: seeds == current) { onPick(seeds) }
                }
            }
            .frame(maxWidth: .infinity)
            .id(page)
            .transition(.push(from: .trailing))
            Button { withAnimation(Theme.spring) { page = min(pages - 1, page + 1) } } label: { Image(systemName: "chevron.right") }
                .disabled(page >= pages - 1)
        }
        .buttonStyle(ChromeButtonStyle(size: 24))
    }

    private struct Swatch: View {
        let seeds: [SpaceColor]
        let isSelected: Bool
        let action: () -> Void
        @State private var isHovering = false

        var body: some View {
            Button(action: action) {
                Circle()
                    .fill(seeds.count > 1
                          ? AnyShapeStyle(LinearGradient(colors: seeds.map { Color($0) }, startPoint: .topLeading, endPoint: .bottomTrailing))
                          : AnyShapeStyle(Color(seeds[0])))
                    .frame(width: 28, height: 28)
                    .overlay(Circle().strokeBorder(.black.opacity(0.15), lineWidth: 1))
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2).padding(-4).opacity(isSelected ? 1 : 0))
                    .scaleEffect(isHovering ? 1.12 : 1)
                    .animation(Theme.pressSpring, value: isHovering)
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
        }
    }
}

// MARK: - Grano (deslizador ondulado)

/// Cuanto más grano, más amplitud tiene la onda.
private struct GrainSlider: View {
    @Binding var value: Double

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let thumbX = 10 + (width - 20) * value

            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.07)).frame(height: 30)
                wave(width: width, height: height)
                    .stroke(.white.opacity(0.25), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                wave(width: width, height: height)
                    .stroke(.white.opacity(0.85), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .mask(Rectangle().frame(width: thumbX).frame(maxWidth: .infinity, alignment: .leading))
                Capsule()
                    .fill(.white)
                    .frame(width: 20, height: 46)
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                    .offset(x: thumbX - 10)
            }
            .frame(height: height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                value = min(1, max(0, (drag.location.x - 10) / (width - 20)))
            })
        }
        .frame(height: 50)
    }

    private func wave(width: CGFloat, height: CGFloat) -> Path {
        var path = Path()
        let amplitude = 1.5 + value * 8
        let cycles = 5.0
        let inset: CGFloat = 12
        for step in 0...120 {
            let progress = Double(step) / 120
            let x = inset + (width - inset * 2) * progress
            let y = height / 2 + sin(progress * cycles * 2 * .pi) * amplitude
            if step == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        return path
    }
}

// MARK: - Intensidad (rueda)

/// Rueda con puntos alrededor: se gira arrastrando (arriba/derecha sube).
/// Vibra al pasar por cada punto.
private struct IntensityDial: View {
    @Binding var value: Double
    @State private var startValue: Double?

    private static let ticks = 24
    private static let sweep = 300.0

    var body: some View {
        let litTicks = Int((value * Double(Self.ticks - 1)).rounded())

        ZStack {
            ForEach(0..<Self.ticks, id: \.self) { tick in
                let angle = Angle.degrees(-Self.sweep / 2 + Self.sweep * Double(tick) / Double(Self.ticks - 1))
                Circle()
                    .fill(.white.opacity(tick <= litTicks ? 0.9 : 0.22))
                    .frame(width: 4, height: 4)
                    .offset(y: -34)
                    .rotationEffect(angle)
            }
            Circle()
                .fill(RadialGradient(colors: [Color(white: 0.32), Color(white: 0.16)],
                                     center: .topLeading, startRadius: 2, endRadius: 50))
                .frame(width: 48, height: 48)
                .overlay(Circle().strokeBorder(.white.opacity(0.1), lineWidth: 1))
                .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                .overlay(
                    Capsule().fill(.white).frame(width: 4, height: 12).offset(y: -15)
                        .rotationEffect(.degrees(-Self.sweep / 2 + Self.sweep * value))
                )
        }
        .frame(width: 80, height: 80)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { drag in
                let start = startValue ?? value
                if startValue == nil { startValue = value }
                let delta = (drag.translation.width - drag.translation.height) / 160
                let newValue = min(1, max(0, start + delta))
                let oldTick = Int((value * Double(Self.ticks - 1)).rounded())
                let newTick = Int((newValue * Double(Self.ticks - 1)).rounded())
                if oldTick != newTick {
                    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                }
                value = newValue
            }
            .onEnded { _ in startValue = nil })
        .animation(Theme.pressSpring, value: value)
    }
}
