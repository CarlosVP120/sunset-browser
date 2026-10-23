import SwiftUI
import BrowserCore
import BrowserUI

/// Menú contextual de un espacio, con las mismas opciones que Arc.
struct SpaceMenu: View {
    let browser: Browser
    let space: Space

    var body: some View {
        Button("Cambiar icono…") { open(.icon) }
        Button("Renombrar espacio…") { open(.rename) }
        Button("Editar color del tema…") { open(.theme) }
        Menu("Perfil") {
            Toggle("Predeterminado", isOn: Binding(
                get: { space.profileID == nil },
                set: { if $0 { browser.setProfile(nil, for: space) } }
            ))
            ForEach(browser.profiles) { profile in
                Toggle(profile.name, isOn: Binding(
                    get: { space.profileID == profile.id },
                    set: { if $0 { browser.setProfile(profile.id, for: space) } }
                ))
            }
            Divider()
            Button("Nuevo perfil…") {
                if let name = TextPrompt.ask(title: "Nuevo perfil",
                                             message: "Cada perfil tiene sus propias cookies y sesiones.",
                                             placeholder: "Trabajo") {
                    let profile = browser.addProfile(named: name)
                    browser.setProfile(profile.id, for: space)
                }
            }
        }

        Divider()

        Button("Nueva carpeta") {
            browser.activate(space)
            withAnimation(Theme.spring) { _ = browser.newFolder() }
        }

        Divider()

        Menu("Exportar «\(space.name)» a una carpeta") {
            ForEach(browser.spaces.filter { $0.id != space.id }) { target in
                Button(target.name) { browser.export(space, intoFolderIn: target) }
            }
        }
        .disabled(browser.spaces.count < 2)

        Divider()

        Button("Gestionar espacios…") { browser.showsSpaceManager = true }

        Divider()

        Button("Borrar espacio", role: .destructive) {
            if confirmDelete() { withAnimation(Theme.spring) { browser.delete(space) } }
        }
        .disabled(browser.spaces.count < 2)
    }

    private func open(_ kind: SpaceEditorRequest.Kind) {
        browser.activate(space)
        // Se abre en el siguiente ciclo para que el menú contextual termine de cerrarse.
        DispatchQueue.main.async {
            browser.spaceEditor = SpaceEditorRequest(spaceID: space.id, kind: kind)
        }
    }

    private func confirmDelete() -> Bool {
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
    @State private var newName = ""
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
            Button { browser.spaceEditor = SpaceEditorRequest(spaceID: space.id, kind: .icon) } label: {
                SpaceIcon(space.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 16)
            }
            .buttonStyle(.plain)
            .tooltip("Cambiar icono")
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
                    .onTapGesture(count: 2) { browser.spaceEditor = SpaceEditorRequest(spaceID: space.id, kind: .rename) }
            }
            Spacer()
        }
        .foregroundStyle(Color(theme.subtitle).opacity(1.4))
        .padding(.horizontal, 10)
        .frame(height: 28)
        .contentShape(Rectangle())
        .contextMenu { SpaceMenu(browser: browser, space: space) }
        .popover(isPresented: binding(.theme), arrowEdge: .trailing) {
            ThemeEditor(browser: browser, space: space)
        }
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
