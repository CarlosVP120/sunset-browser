import AppKit
import SwiftUI
import BrowserCore
import BrowserUI

/// Menú de un espacio, con las mismas opciones que Arc. Es un menú nativo de AppKit (ver
/// `MenuEntry`): se construye al abrirlo, así SwiftUI no puede romperlo mientras está abierto.
@MainActor
enum SpaceMenu {
    static func entries(browser: Browser, space: Space) -> [MenuEntry] {
        var profiles: [MenuEntry] = [
            .button("Predeterminado", checked: space.profileID == nil) { browser.setProfile(nil, for: space) },
        ]
        profiles += browser.profiles.map { profile in
            .button(profile.name, checked: space.profileID == profile.id) { browser.setProfile(profile.id, for: space) }
        }
        profiles += [
            .separator,
            .button("Nuevo perfil…") {
                if let name = TextPrompt.ask(title: "Nuevo perfil",
                                             message: "Cada perfil tiene sus propias cookies y sesiones.",
                                             placeholder: "Trabajo") {
                    let profile = browser.addProfile(named: name)
                    browser.setProfile(profile.id, for: space)
                }
            },
        ]
        let others = browser.spaces.filter { $0.id != space.id }

        return [
            .button("Cambiar icono…") { open(.icon, browser: browser, space: space) },
            .button("Renombrar espacio…") { open(.rename, browser: browser, space: space) },
            .button("Editar color del tema…") { open(.theme, browser: browser, space: space) },
            .menu("Perfil", profiles),
            .separator,
            .button("Nueva carpeta") {
                browser.activate(space)
                withAnimation(Theme.spring) { _ = browser.newFolder() }
            },
            .separator,
            .menu("Exportar «\(space.name)» a una carpeta", others.map { target in
                .button(target.name) { browser.export(space, intoFolderIn: target) }
            }),
            .separator,
            .button("Gestionar espacios…") { browser.showsSpaceManager = true },
            .separator,
            .button("Borrar espacio", enabled: browser.spaces.count > 1, destructive: true) {
                if confirmDelete(space) { withAnimation(Theme.spring) { browser.delete(space) } }
            },
        ]
    }

    private static func open(_ kind: SpaceEditorRequest.Kind, browser: Browser, space: Space) {
        browser.activate(space)
        // Se abre en el siguiente ciclo para que la barra lateral ya muestre este espacio.
        DispatchQueue.main.async {
            browser.spaceEditor = SpaceEditorRequest(spaceID: space.id, kind: kind)
        }
    }

    private static func confirmDelete(_ space: Space) -> Bool {
        let alert = NSAlert()
        alert.messageText = "¿Borrar el espacio «\(space.name)»?"
        alert.informativeText = "Sus \(space.allTabs.count) pestañas irán al archivo, donde puedes recuperarlas."
        alert.addButton(withTitle: "Borrar")
        alert.addButton(withTitle: "Cancelar")
        alert.buttons.first?.hasDestructiveAction = true
        return alert.runModal() == .alertFirstButtonReturn
    }
}

/// Cabecera del espacio en la barra lateral: icono y nombre. Aquí se anclan los editores
/// (icono, tema) y aquí se renombra.
struct SpaceHeader: View {
    let browser: Browser
    let space: Space
    /// Dentro de la lista nativa: la propia tabla se encarga de soltar cosas y del menú contextual.
    var inList = false
    @State private var newName = ""
    @State private var isHovering = false
    @State private var isMenuHovering = false
    @FocusState private var isNameFocused: Bool
    @Environment(\.spaceTheme) private var theme

    private func isEditing(_ kind: SpaceEditorRequest.Kind) -> Bool {
        browser.spaceEditor?.spaceID == space.id && browser.spaceEditor?.kind == kind
    }

    private func binding(_ kind: SpaceEditorRequest.Kind) -> Binding<Bool> {
        Binding(
            get: { isEditing(kind) },
            set: { if !$0, isEditing(kind) { browser.spaceEditor = nil } }
        )
    }

    var body: some View {
        HStack(spacing: 8) {
            // Al pasar el ratón el icono se convierte en la flecha de plegar (como en Arc).
            ZStack {
                SpaceIcon(space.icon)
                    .opacity(isHovering ? 0 : 1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .rotationEffect(.degrees(space.isPinnedCollapsed ? 0 : 90))
                    .opacity(isHovering ? 1 : 0)
            }
            .font(.system(size: 12, weight: .semibold))
            .frame(width: 16)
            .popover(isPresented: binding(.icon), arrowEdge: .trailing) {
                IconPicker(selected: space.icon) { icon in
                    browser.setIcon(icon, for: space)
                    browser.spaceEditor = nil
                }
            }

            if isEditing(.rename) {
                TextField("Nombre", text: $newName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(theme.title))
                    .focused($isNameFocused)
                    .onAppear {
                        newName = space.name
                        isNameFocused = true
                    }
                    .onSubmit { finishRename() }
                    .onExitCommand { browser.spaceEditor = nil }
                    .onChange(of: isNameFocused) { if !isNameFocused { finishRename() } }
            } else {
                Text(space.name)
                    .font(.system(size: 13, weight: .semibold))
            }
            Spacer(minLength: 0)

            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .bold))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
                .nativeMenuOnClick { SpaceMenu.entries(browser: browser, space: space) }
                .tooltip("Opciones del espacio")
                .opacity(isHovering || isMenuHovering ? 1 : 0)
            .onHover { isMenuHovering = $0 }
        }
        .foregroundStyle(Color(theme.subtitle).opacity(1.4))
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .fill(Color(theme.hover))
                .opacity(isHovering ? 0.7 : 0)
        )
        .contentShape(Rectangle())
        .onHover { hovering in withAnimation(hovering ? Theme.hoverIn : Theme.hoverOut) { isHovering = hovering } }
        // Un solo gesto: con `onTapGesture(count: 2)` SwiftUI retrasa el clic simple hasta
        // descartar el doble y plegar tardaba. El primer clic pliega al instante; el segundo lo
        // deshace y renombra.
        .onTapGesture {
            withAnimation(Theme.spring) { browser.togglePinnedSection(space) }
            if NSApp.currentEvent?.clickCount == 2 {
                browser.spaceEditor = SpaceEditorRequest(spaceID: space.id, kind: .rename)
            }
        }
        .tooltip(space.isPinnedCollapsed ? "Mostrar fijadas" : "Plegar fijadas")
        .modifier(SpaceHeaderMenu(browser: browser, space: space, isEnabled: !inList))
        .popover(isPresented: binding(.theme), arrowEdge: .trailing) {
            ThemeEditor(browser: browser, space: space)
        }
        .animation(Theme.spring, value: space.isPinnedCollapsed)
    }

    private func finishRename() {
        guard isEditing(.rename) else { return }
        browser.rename(space, to: newName)
        browser.spaceEditor = nil
    }
}

/// Elegir el icono del espacio: símbolos o emoji.
struct IconPicker: View {
    let selected: String
    let onPick: (String) -> Void
    @State private var showsEmoji = false

    private static let symbols = [
        "house", "briefcase", "chevron.left.forwardslash.chevron.right", "globe.americas", "star", "heart",
        "bolt", "book", "graduationcap", "cart", "creditcard", "chart.line.uptrend.xyaxis", "paintbrush",
        "paintpalette", "camera", "music.note", "film", "gamecontroller", "airplane", "car", "leaf",
        "flame", "drop", "moon", "sun.max", "cloud", "sparkles", "wand.and.stars", "brain", "cpu",
        "hammer", "wrench.and.screwdriver", "terminal", "server.rack", "building.2", "person", "person.2",
        "figure.run", "dumbbell", "fork.knife", "cup.and.saucer", "gift", "flag", "bookmark", "tag",
        "tray", "folder", "doc.text", "newspaper", "bubble.left", "envelope", "phone", "calendar",
        "map", "pawprint", "atom", "globe", "circle.grid.2x2",
    ]

    private static let emoji = Array(
        "😀😎🤓🥳🤩😴🤖👾👻🔥⚡️🌈☀️🌙⭐️✨🌸🌵🍀🍁🌊🍕🍔🍣🍩☕️🍷🎂⚽️🏀🎾🎮🎧🎸🎨🎬📷📚✏️💼💻🖥️📱⌚️💡🔧🔨🧪🧠❤️🧡💛💚💙💜🖤🤍🏠🏢🏝️✈️🚀🚗🚲🗺️🎯🏆💰💎🛒🎁📦📌📎🔒🗂️📝📅🐶🐱🦊🐼🐸🦄🐙🦋🌍"
    ).map(String.init)

    var body: some View {
        VStack(spacing: 10) {
            Picker("", selection: $showsEmoji) {
                Text("Iconos").tag(false)
                Text("Emoji").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 4), count: 8), spacing: 4) {
                    ForEach(showsEmoji ? Self.emoji : Self.symbols, id: \.self) { icon in
                        IconCell(icon: icon, isSelected: icon == selected) { onPick(icon) }
                    }
                }
            }
            .frame(height: 220)
        }
        .padding(12)
        .frame(width: 290)
    }

    private struct IconCell: View {
        let icon: String
        let isSelected: Bool
        let action: () -> Void
        @State private var isHovering = false

        var body: some View {
            Button(action: action) {
                SpaceIcon(icon)
                    .font(.system(size: 15))
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(isSelected ? Color.accentColor.opacity(0.25) : .primary.opacity(isHovering ? 0.08 : 0))
                    )
                    .scaleEffect(isHovering ? 1.12 : 1)
                    .animation(Theme.pressSpring, value: isHovering)
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
        }
    }
}

/// Pregunta un texto con una alerta (p. ej. el nombre de un perfil nuevo).
@MainActor
enum TextPrompt {
    static func ask(title: String, message: String, placeholder: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = placeholder
        alert.accessoryView = field
        alert.addButton(withTitle: "Crear")
        alert.addButton(withTitle: "Cancelar")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }
}

/// El menú contextual de la cabecera (fuera de la lista nativa, que pone el suyo).
private struct SpaceHeaderMenu: ViewModifier {
    let browser: Browser
    let space: Space
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.nativeContextMenu { SpaceMenu.entries(browser: browser, space: space) }
        } else {
            content
        }
    }
}
