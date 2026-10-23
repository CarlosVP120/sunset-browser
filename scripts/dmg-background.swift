// Dibuja el fondo del instalador (DMG): cielo de atardecer con grano, una tarjeta clara donde
// Finder pone los iconos, una flecha ondulada y el texto "Arrastra Sunset a Aplicaciones".
// Uso: swift scripts/dmg-background.swift <salida.png> <escala>
import AppKit

let arguments = CommandLine.arguments
let output = URL(fileURLWithPath: arguments.count > 1 ? arguments[1] : "background.png")
let scale = arguments.count > 2 ? Double(arguments[2]) ?? 1 : 1

// Tamaño de la ventana del DMG, en puntos (debe coincidir con make-dmg.sh).
let size = CGSize(width: 640, height: 420)
let card = CGRect(x: 36, y: 36, width: 568, height: 264)
let appCenter = CGPoint(x: 176, y: 158)
let applicationsCenter = CGPoint(x: 464, y: 158)

func color(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}

let pixels = NSSize(width: size.width * scale, height: size.height * scale)
guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(pixels.width), pixelsHigh: Int(pixels.height),
                                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
bitmap.size = NSSize(width: size.width, height: size.height)
NSGraphicsContext.saveGraphicsState()
let context = NSGraphicsContext(bitmapImageRep: bitmap)!
NSGraphicsContext.current = context
let cg = context.cgContext
// Coordenadas con origen arriba a la izquierda, como las de Finder.
cg.translateBy(x: 0, y: size.height)
cg.scaleBy(x: 1, y: -1)

// Cielo: índigo arriba, rosa y naranja en el horizonte.
let sky = NSGradient(colors: [color(0.20, 0.12, 0.42), color(0.55, 0.22, 0.52), color(0.93, 0.38, 0.45), color(1.0, 0.60, 0.38)],
                     atLocations: [0, 0.45, 0.78, 1], colorSpace: .sRGB)!
sky.draw(in: CGRect(origin: .zero, size: size), angle: 90)

// Unas estrellas arriba.
srand48(7)
for _ in 0..<70 {
    let point = CGPoint(x: drand48() * size.width, y: drand48() * 34)
    let radius = 0.4 + drand48() * 0.9
    color(1, 0.97, 0.92, 0.3 + drand48() * 0.6).setFill()
    NSBezierPath(ovalIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)).fill()
}

// Grano.
for _ in 0..<Int(size.width * size.height * 0.35) {
    let x = drand48() * size.width, y = drand48() * size.height
    color(drand48() > 0.5 ? 1 : 0, drand48() > 0.5 ? 1 : 0, 1, 0.045).setFill()
    CGRect(x: x, y: y, width: 0.6, height: 0.6).fill()
}

// Tarjeta clara con sombra suave.
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = color(0.15, 0.05, 0.2, 0.35)
shadow.shadowBlurRadius = 22
shadow.shadowOffset = NSSize(width: 0, height: -8)
shadow.set()
color(1.0, 0.975, 0.95).setFill()
NSBezierPath(roundedRect: card, xRadius: 26, yRadius: 26).fill()
NSGraphicsContext.restoreGraphicsState()

// Flecha ondulada (como la de Arc), en coral.
let arrow = NSBezierPath()
let start = CGPoint(x: appCenter.x + 92, y: appCenter.y)
let end = CGPoint(x: applicationsCenter.x - 96, y: appCenter.y)
arrow.move(to: start)
let waves = 4
let step = (end.x - start.x) / CGFloat(waves)
for index in 0..<waves {
    let x = start.x + CGFloat(index) * step
    arrow.curve(to: CGPoint(x: x + step, y: start.y),
                controlPoint1: CGPoint(x: x + step * 0.3, y: start.y - 11),
                controlPoint2: CGPoint(x: x + step * 0.7, y: start.y + 11))
}
arrow.move(to: CGPoint(x: end.x - 14, y: end.y - 14))
arrow.line(to: end)
arrow.line(to: CGPoint(x: end.x - 14, y: end.y + 14))
arrow.lineWidth = 4.5
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
color(0.98, 0.36, 0.40).setStroke()
arrow.stroke()

// Texto.
let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let title = NSAttributedString(string: "Arrastra Sunset a Aplicaciones", attributes: [
    .font: NSFont.systemFont(ofSize: 27, weight: .bold),
    .foregroundColor: NSColor.white,
    .kern: -0.4,
    .paragraphStyle: paragraph,
])
// En un contexto volteado, el texto se dibuja con su propio contexto sin voltear.
NSGraphicsContext.saveGraphicsState()
cg.translateBy(x: 0, y: size.height)
cg.scaleBy(x: 1, y: -1)
title.draw(in: CGRect(x: 0, y: size.height - 366, width: size.width, height: 40))
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: output)
print("Fondo: \(output.path)")
