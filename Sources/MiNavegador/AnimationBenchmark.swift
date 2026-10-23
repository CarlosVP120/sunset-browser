import AppKit
import QuartzCore
import SwiftUI
import BrowserCore
import BrowserUI

/// Prueba de fluidez (solo con `SUNSET_BENCH=folders`): abre y cierra la primera carpeta del
/// espacio 10 veces, como al hacer clic, y cuenta los fotogramas que llegan tarde respecto al
/// refresco de la pantalla. Escribe el resultado en la consola del sistema y en
/// /tmp/sunset-bench.txt. Sirve para comparar cambios sin el ruido de otras herramientas.
@MainActor
enum AnimationBenchmark {
    static func startIfRequested(browser: Browser) {
        guard ProcessInfo.processInfo.environment["SUNSET_BENCH"] == "folders" else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
                  let folder = browser.activeSpace.folders.first else { return }
            // Primero 2 s en reposo (referencia), luego la animación.
            let idle = FrameRecorder(screen: window.screen ?? NSScreen.main!)
            idle.start(in: window)
            let idleStart = CACurrentMediaTime()
            try? await Task.sleep(for: .seconds(2))
            let idleReport = idle.stop(duration: CACurrentMediaTime() - idleStart)
            let recorder = FrameRecorder(screen: window.screen ?? NSScreen.main!)
            recorder.start(in: window)
            let start = CACurrentMediaTime()
            for _ in 0..<10 {
                withAnimation(Theme.spring) { browser.toggle(folder) }
                try? await Task.sleep(for: .milliseconds(700))
            }
            let report = "reposo: " + idleReport + "\n    carpetas: " + recorder.stop(duration: CACurrentMediaTime() - start)
            NSLog("[bench] %@", report)
            try? report.write(toFile: "/tmp/sunset-bench.txt", atomically: true, encoding: .utf8)
        }
    }
}

/// Registra el intervalo entre fotogramas con el display link de la ventana.
@MainActor
private final class FrameRecorder: NSObject {
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var intervals: [Double] = []
    private let refresh: Double

    init(screen: NSScreen) {
        refresh = Double(screen.maximumFramesPerSecond)
    }

    func start(in window: NSWindow) {
        guard let view = window.contentView else { return }
        let link = view.displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        if last > 0 { intervals.append(link.timestamp - last) }
        last = link.timestamp
    }

    func stop(duration: Double) -> String {
        link?.invalidate()
        let budget = 1 / refresh
        let late = intervals.filter { $0 > budget * 1.5 }
        let worst = (intervals.max() ?? 0) * 1000
        let fps = Double(intervals.count) / duration
        return String(format: "pantalla %.0f Hz · %d fotogramas · %.0f fps de media · %d tarde (%.1f %%) · peor %.1f ms",
                      refresh, intervals.count, fps, late.count, 100 * Double(late.count) / Double(max(intervals.count, 1)), worst)
    }
}
