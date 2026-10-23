import SwiftUI
import BrowserCore
import BrowserUI

/// "Gestionar espacios…": ordenar (arrastrando), renombrar, cambiar perfil y borrar espacios,
/// y crear o borrar perfiles.
public struct SpaceManagerView: View {
    let browser: Browser
    @Environment(\.dismiss) private var dismiss

    public init(browser: Browser) {
        self.browser = browser
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Espacios").font(.title2.weight(.semibold))
                Spacer()
                Button {
                    browser.addSpace(name: "Espacio \(browser.spaces.count + 1)")
                } label: {
                    Label("Nuevo espacio", systemImage: "plus")
                }
            }
            .padding([.horizontal, .top], 20)
            .padding(.bottom, 8)

            List {
                Section {
                    ForEach(browser.spaces) { space in
                        SpaceRow(browser: browser, space: space)
                    }
                    .onMove { browser.moveSpaces(fromOffsets: $0, toOffset: $1) }
                } footer: {
                    Text("Arrastra para cambiar el orden. ⌃1, ⌃2… siguen este orden.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Perfiles") {
                    HStack {
                        Label("Predeterminado", systemImage: "person.crop.circle")
                        Spacer()
                        Text(usage(of: nil)).foregroundStyle(.secondary).font(.caption)
                    }
                    ForEach(browser.profiles) { profile in
                        HStack {
                            Label(profile.name, systemImage: "person.crop.circle.fill")
                            Spacer()
                            Text(usage(of: profile.id)).foregroundStyle(.secondary).font(.caption)
                            Button(role: .destructive) {
                                if confirmDelete(profile) { browser.deleteProfile(profile) }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .tooltip("Borrar perfil y sus datos")
                        }
                    }
                    Button {
                        if let name = TextPrompt.ask(title: "Nuevo perfil",
                                                     message: "Cada perfil tiene sus propias cookies y sesiones.",
                                                     placeholder: "Trabajo") {
                            browser.addProfile(named: name)
                        }
                    } label: {
                        Label("Nuevo perfil", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .listStyle(.inset)

            HStack {
                Spacer()
                Button("Listo") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 520, height: 540)
    }

    private func usage(of profileID: UUID?) -> String {
        let count = browser.spaces.filter { $0.profileID == profileID }.count
        return count == 1 ? "1 espacio" : "\(count) espacios"
    }

    private func confirmDelete(_ profile: Profile) -> Bool {
        let alert = NSAlert()
        alert.messageText = "¿Borrar el perfil «\(profile.name)»?"
        alert.informativeText = "Se borrarán sus cookies y sesiones. Sus espacios pasarán al perfil predeterminado."
        alert.addButton(withTitle: "Borrar")
        alert.addButton(withTitle: "Cancelar")
        alert.buttons.first?.hasDestructiveAction = true
        return alert.runModal() == .alertFirstButtonReturn
    }
}

private struct SpaceRow: View {
    let browser: Browser
    let space: Space
    @State private var name = ""

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)

            ZStack {
                Circle()
                    .fill(LinearGradient(colors: space.theme.background.map { Color($0) } + [Color(space.theme.background[0])],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                SpaceIcon(space.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(space.theme.title))
            }
            .frame(width: 28, height: 28)

            TextField("Nombre", text: $name)
                .textFieldStyle(.plain)
                .font(.body.weight(.medium))
                .onAppear { name = space.name }
                .onSubmit { browser.rename(space, to: name) }

            Picker("", selection: Binding(
                get: { space.profileID },
                set: { browser.setProfile($0, for: space) }
            )) {
                Text("Predeterminado").tag(UUID?.none)
                ForEach(browser.profiles) { profile in
                    Text(profile.name).tag(UUID?.some(profile.id))
                }
            }
            .labelsHidden()
            .frame(width: 140)

            Button(role: .destructive) {
                withAnimation(Theme.spring) { browser.delete(space) }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(browser.spaces.count < 2)
            .tooltip("Borrar espacio")
        }
        .padding(.vertical, 4)
    }
}
