import SwiftUI
import BrowserCore
import BrowserUI
import HomeFeature

/// Bienvenida de Sunset (como la de Arc): una tarjeta sobre el cielo de la hora actual. A la
/// izquierda, el texto y los botones; a la derecha, donde eliges.
public struct OnboardingView: View {
    let model: Onboarding

    public init(model: Onboarding) {
        self.model = model
    }

    public var body: some View {
        ZStack {
            SunsetSky()
                .ignoresSafeArea()

            HStack(spacing: 0) {
                LeftPanel(model: model)
                    .frame(width: 390)
                    .overlay(alignment: .trailing) { Perforation() }
                    .zIndex(1)
                RightPanel(model: model)
            }
            .frame(maxWidth: 1060, maxHeight: 620)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(.white.opacity(0.08)))
            .shadow(color: .black.opacity(0.35), radius: 40, y: 20)
            .padding(.horizontal, 56)
            .padding(.vertical, 48)
        }
        .environment(\.colorScheme, .dark)
        .animation(.spring(response: 0.5, dampingFraction: 0.86), value: model.step)
    }
}

// MARK: - Panel izquierdo

private struct LeftPanel: View {
    let model: Onboarding

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: model.back) {
                Label("Atrás", systemImage: "arrow.left")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.55))
            .opacity(model.canGoBack ? 1 : 0)
            .disabled(!model.canGoBack)
            .padding(.bottom, 26)

            Group {
                Text(title)
                    .font(.system(size: 40, weight: .bold))
                    .kerning(-0.8)
                    .lineSpacing(-4)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(message)
                    .font(.system(size: 15.5))
                    .lineSpacing(4)
                    .foregroundStyle(.white.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 20)
            }
            .id(model.step)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .offset(x: model.movingForward ? 24 : -24)),
                removal: .opacity
            ))

            Spacer(minLength: 20)

            Button(action: model.next) {
                Text(model.nextTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!model.canContinue)
            .keyboardShortcut(.defaultAction)

            Button("Saltar por ahora", action: model.skip)
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
                .opacity(model.isSkippable ? 1 : 0)
                .disabled(!model.isSkippable)
        }
        .padding(.horizontal, 44)
        .padding(.top, 40)
        .padding(.bottom, 32)
        .frame(maxHeight: .infinity)
        .background(Color(red: 0.12, green: 0.11, blue: 0.14))
    }

    private var title: String {
        switch model.step {
        case .welcome: "Hola, esto\nes Sunset."
        case .importSource: "Trae todo\ncontigo."
        case .importKinds: "¿Qué traemos\nde \(model.source?.name ?? "tu navegador")?"
        case .importing: model.isImporting ? "Mudando tus\ncosas…" : "Bienvenido\na casa."
        case .apps: "Elige las apps\nque más usas."
        case .theme: "Ponle tu\ncolor."
        case .defaultBrowser: "¿Sunset como\ntu navegador?"
        case .done: "Todo listo."
        }
    }

    private var message: String {
        switch model.step {
        case .welcome:
            "Un navegador tranquilo, rápido y hecho a tu medida. Vamos a dejarlo listo en un minuto."
        case .importSource:
            "Tus pestañas, marcadores, historial, contraseñas y sesiones abiertas. Se copian: tu navegador anterior se queda exactamente como está."
        case .importKinds:
            "Elige lo que quieras traer. Puedes volver a importar cuando quieras desde el menú Archivo."
        case .importing:
            model.isImporting
                ? "Estamos copiando tus datos. Tu otro navegador no cambia nada."
                : "Esto es lo que trajimos. Si algo faltó, a la derecha te decimos cómo arreglarlo."
        case .apps:
            "Quedarán a mano como favoritos, arriba en tu barra lateral."
        case .theme:
            "Elige un color para tu espacio. Cada espacio puede tener el suyo."
        case .defaultBrowser:
            "Así, los enlaces que abras desde otras apps se abrirán aquí."
        case .done:
            "⌘T abre el Command Bar, ⌘S muestra u oculta la barra lateral y ⌃1–9 cambia de espacio. Que disfrutes el atardecer."
        }
    }
}

/// El borde troquelado entre los dos paneles (como un boleto).
private struct Perforation: View {
    var body: some View {
        GeometryReader { geometry in
            let spacing: CGFloat = 13
            let count = Int(geometry.size.height / spacing)
            VStack(spacing: spacing - 6) {
                ForEach(0..<count, id: \.self) { _ in
                    Circle().frame(width: 6, height: 6)
                }
            }
            .frame(maxHeight: .infinity)
            .foregroundStyle(Color(red: 0.12, green: 0.11, blue: 0.14))
            .offset(x: 3)
        }
        .frame(width: 6)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(Sunset.coral.mixed(with: Sunset.orange, by: 0.45)))
                    .brightness(configuration.isPressed ? -0.08 : 0)
            )
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(Theme.pressSpring, value: configuration.isPressed)
    }
}

// MARK: - Panel derecho

private struct RightPanel: View {
    let model: Onboarding

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Rectangle().fill(Color(white: 0.55).opacity(0.35))
            GrainOverlay(intensity: 0.45)

            content
                .id(model.step)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.97)).combined(with: .offset(x: model.movingForward ? 30 : -30)),
                    removal: .opacity
                ))
                .padding(48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        switch model.step {
        case .welcome, .done: WelcomeArt(isDone: model.step == .done)
        case .importSource: SourcePicker(model: model)
        case .importKinds: KindsPicker(model: model)
        case .importing: ImportProgress(model: model)
        case .apps: AppsPicker(model: model)
        case .theme: ThemePicker(model: model)
        case .defaultBrowser: DefaultBrowserPicker(model: model)
        }
    }
}
