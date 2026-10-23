import SwiftUI
import BrowserUI

/// Lista de atajos de teclado, agrupada como en las preferencias de Arc.
struct ShortcutsView: View {
    @Environment(\.dismiss) private var dismiss

    private static let groups: [(String, [(String, String)])] = [
        ("General", [
            ("Command Bar / nueva pestaña", "⌘T"),
            ("Editar la dirección", "⌘L"),
            ("Mostrar u ocultar barra lateral", "⌘S"),
            ("Mostrar u ocultar barra de herramientas", "⌥⌘T"),
            ("Buscar pestañas", "⇧⌘A"),
            ("Historial", "⌘Y"),
        ]),
        ("Página", [
            ("Recargar", "⌘R"),
            ("Recarga forzada", "⇧⌘R"),
            ("Detener", "⌘."),
            ("Atrás / Adelante", "⌘[ ⌘]"),
            ("Buscar en la página", "⌘F"),
            ("Siguiente / anterior coincidencia", "⌘G ⇧⌘G"),
            ("Acercar / Alejar / Tamaño real", "⌘+ ⌘- ⌘0"),
            ("Copiar URL", "⇧⌘C"),
            ("Copiar URL como Markdown", "⌥⇧⌘C"),
            ("Imprimir", "⌘P"),
        ]),
        ("Pestañas", [
            ("Cerrar pestaña", "⌘W"),
            ("Reabrir pestaña cerrada", "⇧⌘T"),
            ("Fijar o desfijar", "⌘D"),
            ("Pestaña siguiente / anterior", "⌥⌘↓ ⌥⌘↑"),
            ("Última pestaña usada", "⌃⇥"),
            ("Ir a la pestaña 1–8", "⌘1…8"),
            ("Ir a la última pestaña", "⌘9"),
            ("Nueva carpeta", "⌥⌘N"),
        ]),
        ("Espacios", [
            ("Espacio siguiente / anterior", "⌥⌘→ ⌥⌘←"),
            ("Ir al espacio 1–9", "⌃1…9"),
        ]),
        ("Desarrollo", [
            ("Entrar o salir del modo desarrollador", "⌃D"),
            ("Consola", "⌥⌘J"),
            ("Red", "⌥⌘E"),
            ("Inspeccionar elemento", "⌥⌘C"),
            ("Inspector web", "⌥⌘I"),
            ("Vista móvil", "⇧⌘M"),
        ]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Atajos de teclado")
                .font(.title2.weight(.semibold))
                .padding(20)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Self.groups, id: \.0) { group, shortcuts in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group)
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            ForEach(shortcuts, id: \.0) { title, keys in
                                HStack {
                                    Text(title)
                                    Spacer()
                                    HStack(spacing: 8) {
                                        ForEach(keys.split(separator: " ").map(String.init), id: \.self) { key in
                                            ShortcutKeys(key.replacingOccurrences(of: "…", with: "–"))
                                        }
                                    }
                                }
                                .padding(.vertical, 3)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }

            HStack {
                Spacer()
                Button("Listo") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 480, height: 600)
    }
}
