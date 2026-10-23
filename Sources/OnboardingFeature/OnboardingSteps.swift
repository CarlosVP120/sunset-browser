import SwiftUI
import BrowserCore
import BrowserImport
import BrowserUI

// MARK: - Bienvenida y final

/// El logo: los rayos salen uno a uno, como el sol asomando.
struct WelcomeArt: View {
    let isDone: Bool
    @State private var raysShown = 0

    var body: some View {
        VStack(spacing: 26) {
            ZStack {
                ForEach(0..<4, id: \.self) { ray in
                    SunsetLogo(ray: ray)
                        .fill(SunsetLogo.rayColors[ray])
                        .opacity(raysShown > ray ? 1 : 0)
                        .scaleEffect(raysShown > ray ? 1 : 0.6, anchor: .bottom)
                        .offset(y: raysShown > ray ? 0 : 14)
                }
            }
            .frame(width: 200, height: 100)
            .shadow(color: .black.opacity(0.12), radius: 12, y: 6)

            Text(isDone ? "Que empiece el atardecer" : "Sunset")
                .font(.system(size: isDone ? 24 : 44, weight: .semibold))
                .kerning(isDone ? 0 : -1)
                .foregroundStyle(.white)
                .opacity(raysShown >= 4 ? 1 : 0)
        }
        .task {
            for ray in 0...4 {
                try? await Task.sleep(for: .milliseconds(ray == 0 ? 250 : 140))
                withAnimation(.spring(response: 0.55, dampingFraction: 0.7)) { raysShown = ray + 1 }
            }
        }
    }
}

// MARK: - De qué navegador

struct SourcePicker: View {
    let model: Onboarding

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ForEach(model.availableSources) { source in
                    OptionCard(isSelected: model.source == source, action: { model.choose(source) }) {
                        Text(source.name)
                            .font(.system(size: 15, weight: .semibold))
                    } trailing: {
                        ZStack {
                            Color(source.tint)
                            if let icon = source.icon {
                                Image(nsImage: icon).resizable().frame(width: 46, height: 46)
                            }
                        }
                        .frame(width: 108)
                    }
                }
                OptionCard(isSelected: model.source == nil, action: { model.choose(nil) }) {
                    Text("No, quiero empezar de cero.")
                        .font(.system(size: 15, weight: .semibold))
                } trailing: {
                    EmptyView()
                }
            }
            .frame(maxWidth: 440)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.never)
        .frame(maxHeight: .infinity)
    }
}

/// Tarjeta blanca con un círculo de selección (como las de Arc).
struct OptionCard<Label: View, Trailing: View>: View {
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @ViewBuilder let trailing: () -> Trailing
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 18) {
                RadioDot(isOn: isSelected)
                    .padding(.leading, 22)
                label()
                    .foregroundStyle(Color(white: 0.2))
                    .frame(maxWidth: .infinity, alignment: .leading)
                trailing()
            }
            .frame(height: 78)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? Color(Sunset.coral) : .clear, lineWidth: 2)
            )
            .shadow(color: .black.opacity(isHovering ? 0.16 : 0.08), radius: isHovering ? 14 : 6, y: 4)
            .scaleEffect(isHovering ? 1.015 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(Theme.hoverIn) { isHovering = hovering } }
        .animation(Theme.pressSpring, value: isSelected)
    }
}

struct RadioDot: View {
    let isOn: Bool

    var body: some View {
        ZStack {
            Circle().strokeBorder(Color(white: isOn ? 0 : 0.75).opacity(isOn ? 0 : 1), lineWidth: 1.5)
            if isOn {
                Circle().fill(Color(Sunset.coral))
                Circle().fill(.white).frame(width: 8, height: 8)
            }
        }
        .frame(width: 22, height: 22)
    }
}

// MARK: - Qué traer

struct KindsPicker: View {
    @Bindable var model: Onboarding

    var body: some View {
        let source = model.source ?? .chrome
        VStack(spacing: 12) {
            if source == .safari, !model.canReadSafari {
                Notice(symbol: "lock.shield", text: "Para leer Safari, macOS pide darle a Sunset «Acceso total al disco». Actívalo y vuelve aquí.",
                       button: "Abrir Ajustes", action: model.openFullDiskAccessSettings)
            }
            VStack(spacing: 0) {
                ForEach(rows(for: source), id: \.kind.rawValue) { row in
                    KindRow(symbol: row.symbol, title: row.title, detail: row.detail,
                            isOn: model.kinds.contains(row.kind)) {
                        if model.kinds.contains(row.kind) { model.kinds.remove(row.kind) } else { model.kinds.insert(row.kind) }
                    }
                    if row.kind == .passwords, source == .safari, model.kinds.contains(.passwords) {
                        SafariPasswordsHelp(model: model)
                    }
                    if row.kind != rows(for: source).last?.kind { Divider().padding(.leading, 60) }
                }
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
        }
        .frame(maxWidth: 470)
    }

    private struct Row {
        let kind: ImportKinds
        let symbol: String
        let title: String
        let detail: String
    }

    private func rows(for source: ImportSource) -> [Row] {
        var rows: [Row] = []
        if source == .arc {
            rows.append(Row(kind: .sidebar, symbol: "sidebar.left", title: "Espacios y pestañas",
                            detail: "Tus espacios, favoritos, carpetas y pestañas fijadas, con sus colores."))
        }
        rows += [
            Row(kind: .bookmarks, symbol: "bookmark", title: "Marcadores",
                detail: "Quedan en un espacio nuevo, con sus carpetas."),
            Row(kind: .history, symbol: "clock.arrow.circlepath", title: "Historial",
                detail: "Para que el Command Bar te sugiera tus sitios de siempre."),
            Row(kind: .passwords, symbol: "key", title: "Contraseñas",
                detail: source == .safari
                    ? "Safari las guarda en la app Contraseñas: hay que exportarlas a un archivo."
                    : "macOS te pedirá permiso para leer la clave de \(source.name). Se guardan cifradas."),
            Row(kind: .cookies, symbol: "person.badge.key", title: "Sesiones abiertas",
                detail: "Sigues con la sesión iniciada en tus sitios, sin volver a entrar."),
        ]
        return rows.filter { source.supportedKinds.contains($0.kind) }
    }
}

private struct KindRow: View {
    let symbol: String
    let title: String
    let detail: String
    let isOn: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 16) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color(Sunset.coral))
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color(white: 0.15))
                    Text(detail).font(.system(size: 12)).foregroundStyle(Color(white: 0.45))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isOn ? Color(Sunset.coral) : Color(white: 0.78))
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SafariPasswordsHelp: View {
    let model: Onboarding

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("En la app Contraseñas: Archivo › Exportar todas las contraseñas. Después elige ese archivo aquí y bórralo cuando termines.")
                .font(.system(size: 11.5))
                .foregroundStyle(Color(white: 0.4))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Abrir Contraseñas", action: model.openPasswordsApp)
                Button(model.passwordFile == nil ? "Elegir archivo…" : model.passwordFile!.lastPathComponent,
                       action: model.choosePasswordFile)
            }
            .controlSize(.small)
            .environment(\.colorScheme, .light)
        }
        .padding(.leading, 60)
        .padding(.trailing, 16)
        .padding(.bottom, 12)
    }
}

/// Aviso con un botón (permisos que faltan).
struct Notice: View {
    let symbol: String
    let text: String
    let button: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(Color(Sunset.orange))
            Text(text).font(.system(size: 12.5)).foregroundStyle(Color(white: 0.25))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(button, action: action)
                .controlSize(.small)
                .environment(\.colorScheme, .light)
        }
        .padding(14)
        .background(Color(red: 1, green: 0.95, blue: 0.9))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Importando y resumen

struct ImportProgress: View {
    let model: Onboarding
    @State private var pulse = false

    var body: some View {
        if model.isImporting || model.summary == nil {
            VStack(spacing: 22) {
                ZStack {
                    ForEach(0..<4, id: \.self) { ray in
                        SunsetLogo(ray: ray)
                            .fill(SunsetLogo.rayColors[ray])
                            .opacity(pulse ? 1 : 0.35)
                            .animation(.easeInOut(duration: 0.7).repeatForever().delay(Double(ray) * 0.15), value: pulse)
                    }
                }
                .frame(width: 140, height: 70)
                Text("Copiando desde \(model.source?.name ?? "")…")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .onAppear { pulse = true }
        } else if let summary = model.summary {
            SummaryList(model: model, summary: summary)
        }
    }
}

private struct SummaryList: View {
    let model: Onboarding
    let summary: ImportSummary

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 0) {
                ForEach(lines, id: \.title) { line in
                    HStack(spacing: 14) {
                        Image(systemName: line.ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(line.ok ? Color(red: 0.2, green: 0.7, blue: 0.4) : Color(Sunset.orange))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color(white: 0.15))
                            if let detail = line.detail {
                                Text(detail).font(.system(size: 12)).foregroundStyle(Color(white: 0.45))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    if line.title != lines.last?.title { Divider().padding(.leading, 48) }
                }
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 8, y: 4)

            if summary.problems.values.contains(.keychainDenied) {
                Notice(symbol: "key", text: "No se dio permiso para leer la clave de \(model.source?.name ?? "tu navegador"). Puedes intentarlo otra vez y elegir «Permitir».",
                       button: "Reintentar", action: model.retryImport)
            } else if summary.problems.values.contains(.needsFullDiskAccess) {
                Notice(symbol: "lock.shield", text: "Falta «Acceso total al disco» para leer Safari. Actívalo y reintenta.",
                       button: "Abrir Ajustes", action: model.openFullDiskAccessSettings)
            }
        }
        .frame(maxWidth: 470)
    }

    private struct Line {
        let title: String
        let detail: String?
        let ok: Bool
    }

    private var lines: [Line] {
        var lines: [Line] = []
        func number(_ value: Int) -> String { value.formatted(.number.locale(Locale(identifier: "es_MX"))) }
        if summary.spaces > 0 {
            lines.append(Line(title: "\(summary.spaces) espacios y \(number(summary.tabs)) pestañas", detail: nil, ok: true))
        }
        if summary.bookmarks > 0 {
            lines.append(Line(title: "\(number(summary.bookmarks)) marcadores", detail: "En el espacio «\(model.source == .arc ? "Marcadores de Arc" : model.source?.name ?? "")».", ok: true))
        }
        if summary.history > 0 { lines.append(Line(title: "\(number(summary.history)) páginas del historial", detail: nil, ok: true)) }
        if summary.passwords > 0 {
            lines.append(Line(title: "\(number(summary.passwords)) contraseñas", detail: "Guardadas cifradas. Aparecerán al iniciar sesión en cada sitio.", ok: true))
        }
        if summary.cookies > 0 {
            lines.append(Line(title: "\(number(summary.cookies)) sesiones abiertas", detail: "Sigues con la sesión iniciada en tus sitios.", ok: true))
        }
        for (kind, problem) in summary.problems.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            lines.append(Line(title: Self.name(of: kind), detail: Self.explain(problem), ok: false))
        }
        if lines.isEmpty { lines.append(Line(title: "No había nada que traer", detail: nil, ok: true)) }
        return lines
    }

    static func name(of kind: ImportKinds) -> String {
        switch kind {
        case .sidebar: "Espacios y pestañas"
        case .bookmarks: "Marcadores"
        case .history: "Historial"
        case .passwords: "Contraseñas"
        default: "Sesiones abiertas"
        }
    }

    static func explain(_ problem: ImportProblem) -> String {
        switch problem {
        case .needsFullDiskAccess: "macOS no dejó leerlos: falta «Acceso total al disco»."
        case .keychainDenied: "No se dio permiso para leer la clave del Llavero."
        case .needsPasswordExport: "Exporta tus contraseñas desde la app Contraseñas y elige el archivo."
        case .unavailable: "No encontramos datos de este tipo."
        }
    }
}

// MARK: - Apps favoritas

struct AppsPicker: View {
    let model: Onboarding

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 7) {
                ForEach(0..<3, id: \.self) { _ in Circle().fill(Color(white: 0.88)).frame(width: 11, height: 11) }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(96), spacing: 14), count: 4), spacing: 14) {
                ForEach(Onboarding.apps) { app in
                    AppTile(app: app, isSelected: model.selectedApps.contains(app.id)) { model.toggle(app) }
                }
            }
        }
        .padding(26)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 14, y: 6)
    }
}

private struct AppTile: View {
    let app: Onboarding.App
    let isSelected: Bool
    let toggle: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: toggle) {
            VStack(spacing: 8) {
                FaviconView(pageURL: app.url, size: 30)
                Text(app.name).font(.system(size: 11, weight: .medium)).foregroundStyle(Color(white: 0.35))
            }
            .frame(width: 96, height: 86)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color(Sunset.coral).opacity(0.12) : Color(white: 0.96))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? Color(Sunset.coral) : .clear, lineWidth: 2)
            )
            .scaleEffect(isHovering ? 1.05 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(Theme.pressSpring) { isHovering = hovering } }
        .animation(Theme.pressSpring, value: isSelected)
        .task {
            // Si ya tienes el icono (porque usas el sitio), se queda; si no, se pide el del sitio.
            guard FaviconCache.shared.image(for: app.url.host() ?? "") == nil else { return }
            await FaviconCache.shared.load(pageURL: app.url, iconURL: app.icon)
        }
    }
}

// MARK: - Tema

struct ThemePicker: View {
    @Bindable var model: Onboarding

    var body: some View {
        let theme = model.previewTheme
        VStack(spacing: 22) {
            // Vista previa: una barra lateral con el color elegido.
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 6) {
                        ForEach(0..<3, id: \.self) { _ in Circle().fill(Color(theme.subtitle).opacity(0.5)).frame(width: 9, height: 9) }
                    }
                    .padding(.bottom, 8)
                    ForEach(["Inicio", "Correo", "Calendario", "Música"], id: \.self) { name in
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 4).fill(Color(theme.subtitle).opacity(0.6)).frame(width: 14, height: 14)
                            Text(name).font(.system(size: 12, weight: .medium)).foregroundStyle(Color(theme.title))
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(name == "Inicio" ? Color(theme.focus) : .clear, in: RoundedRectangle(cornerRadius: 7))
                    }
                    Spacer()
                }
                .padding(14)
                .frame(width: 170)
                RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(theme.isDark ? 0.9 : 1))
                    .padding(8)
            }
            .frame(width: 400, height: 230)
            .background(
                LinearGradient(colors: theme.background.map { Color($0) } + [Color(theme.background.last ?? .navy)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .overlay(GrainOverlay(intensity: theme.grain))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
            .animation(.easeInOut(duration: 0.35), value: theme)

            HStack(spacing: 10) {
                ForEach(Array(Onboarding.colors.enumerated()), id: \.offset) { index, color in
                    Button { model.colorIndex = index } label: {
                        Circle()
                            .fill(Color(color))
                            .frame(width: 26, height: 26)
                            .overlay(Circle().strokeBorder(.white, lineWidth: model.colorIndex == index ? 3 : 0))
                            .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                            .scaleEffect(model.colorIndex == index ? 1.15 : 1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .animation(Theme.pressSpring, value: model.colorIndex)

            Picker("", selection: $model.appearance) {
                Image(systemName: "sparkles").tag(SpaceTheme.Appearance.auto)
                Image(systemName: "sun.max").tag(SpaceTheme.Appearance.light)
                Image(systemName: "moon").tag(SpaceTheme.Appearance.dark)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 160)
            .disabled(model.colorIndex == nil)
        }
    }
}

// MARK: - Navegador predeterminado

struct DefaultBrowserPicker: View {
    let model: Onboarding

    var body: some View {
        VStack(spacing: 14) {
            choice(true, bold: "SÍ,", rest: " que Sunset sea mi navegador.")
            choice(false, bold: "AÚN NO,", rest: " sigo explorando.")
        }
        .frame(maxWidth: 460)
    }

    private func choice(_ value: Bool, bold: String, rest: String) -> some View {
        Button { withAnimation(Theme.pressSpring) { model.makeDefault = value } } label: {
            HStack(spacing: 16) {
                Circle()
                    .strokeBorder(.white.opacity(0.7), lineWidth: 1.5)
                    .background(Circle().fill(model.makeDefault == value ? Color.white : .clear).padding(5))
                    .frame(width: 22, height: 22)
                (Text(bold).fontWeight(.bold) + Text(rest))
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                Spacer()
            }
            .padding(.horizontal, 22)
            .frame(height: 70)
            .background(.white.opacity(model.makeDefault == value ? 0.22 : 0.1),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(model.makeDefault == value ? 0.6 : 0.15), lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
