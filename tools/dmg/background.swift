import AppKit

struct Design: Decodable {
    let caption: String
    let accent: String
    let glow: String
    let arrow: String
    let motif: String?
    let width: CGFloat
    let height: CGFloat
    let iconSize: CGFloat
    let app: Array<CGFloat>
    let applications: Array<CGFloat>
    let captionY: CGFloat
}

struct RGB {
    let r: CGFloat
    let g: CGFloat
    let b: CGFloat

    init(r: CGFloat, g: CGFloat, b: CGFloat) {
        self.r = r
        self.g = g
        self.b = b
    }

    init(hex: String) {
        let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        r = CGFloat((value >> 16) & 0xFF) / 255
        g = CGFloat((value >> 8) & 0xFF) / 255
        b = CGFloat(value & 0xFF) / 255
    }

    static let white = RGB(r: 1, g: 1, b: 1)

    func mixed(with other: RGB, _ amount: CGFloat) -> RGB {
        RGB(r: r + (other.r - r) * amount, g: g + (other.g - g) * amount, b: b + (other.b - b) * amount)
    }

    func color(_ alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: r, green: g, blue: b, alpha: alpha)
    }
}

let directory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")
let design = try JSONDecoder().decode(Design.self, from: Data(contentsOf: directory.appending(path: "dmg.json")))
let accent = RGB(hex: design.accent)
let glow = RGB(hex: design.glow)
let ink = RGB(r: 0.16, g: 0.2, b: 0.22).mixed(with: accent, 0.12)
let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
let app = CGPoint(x: design.app[0], y: design.app[1])
let applications = CGPoint(x: design.applications[0], y: design.applications[1])

func radial(_ context: CGContext, at center: CGPoint, radius: CGFloat, _ color: RGB, _ alpha: CGFloat) {
    let colors = [color.color(alpha), color.color(alpha * 0.45), color.color(0)] as CFArray
    guard let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.45, 1]) else { return }
    context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
}

func backdrop(_ context: CGContext) {
    let top = RGB.white.mixed(with: accent, 0.015)
    let bottom = RGB.white.mixed(with: accent, 0.075)
    if let gradient = CGGradient(colorsSpace: space, colors: [top.color(), bottom.color()] as CFArray, locations: [0, 1]) {
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: design.height), options: [.drawsAfterEndLocation])
    }
    radial(context, at: CGPoint(x: design.width * 0.5, y: design.height + 90), radius: design.width * 0.62, accent, 0.11)
    radial(context, at: app, radius: design.iconSize * 1.7, glow, 0.26)
    radial(context, at: applications, radius: design.iconSize * 1.45, accent, 0.09)
    radial(context, at: CGPoint(x: design.width * 0.5, y: -40), radius: design.width * 0.5, .white, 0.7)
}

func waves(_ context: CGContext) {
    guard design.motif == "waves" else { return }
    context.setLineWidth(1.25)
    context.setLineCap(.round)
    for index in 0..<4 {
        let line = CGFloat(index)
        let baseline = design.height - 62 + line * 13
        let amplitude = 7 - line
        let length = design.width / (1.6 + line * 0.25)
        let phase = line * 0.9
        let path = CGMutablePath()
        var x: CGFloat = -10
        path.move(to: CGPoint(x: x, y: baseline + amplitude * sin(phase - x / length * 2 * .pi)))
        while x <= design.width + 10 {
            x += 2
            path.addLine(to: CGPoint(x: x, y: baseline + amplitude * sin(phase - x / length * 2 * .pi)))
        }
        context.addPath(path)
        context.setStrokeColor(accent.color(0.085 - line * 0.015))
        context.strokePath()
    }
}

func arrowPath() -> CGPath {
    let gap = design.iconSize / 2 + 24
    let start = CGPoint(x: app.x + gap, y: app.y)
    let end = CGPoint(x: applications.x - gap, y: applications.y)
    let path = CGMutablePath()
    var tangent = CGPoint(x: 1, y: 0)
    if design.arrow == "wave" {
        let amplitude: CGFloat = 9
        func point(_ t: CGFloat) -> CGPoint {
            CGPoint(x: start.x + (end.x - start.x) * t, y: start.y - amplitude * sin(t * 3 * .pi) * sin(t * .pi))
        }
        path.move(to: point(0))
        for step in 1...120 {
            path.addLine(to: point(CGFloat(step) / 120))
        }
    } else {
        let control = CGPoint(x: (start.x + end.x) / 2, y: start.y - 30)
        path.move(to: start)
        path.addQuadCurve(to: end, control: control)
        let dx = end.x - control.x
        let dy = end.y - control.y
        let length = (dx * dx + dy * dy).squareRoot()
        tangent = CGPoint(x: dx / length, y: dy / length)
    }
    let head: CGFloat = 10
    for side in [CGFloat(-1), 1] {
        let angle = atan2(tangent.y, tangent.x) + .pi + side * 0.72
        path.move(to: end)
        path.addLine(to: CGPoint(x: end.x + head * cos(angle), y: end.y + head * sin(angle)))
    }
    return path
}

func arrow(_ context: CGContext) {
    let stroked = arrowPath().copy(strokingWithWidth: 3.25, lineCap: .round, lineJoin: .round, miterLimit: 10)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: 1), blur: 3, color: accent.mixed(with: RGB(r: 0, g: 0, b: 0), 0.5).color(0.18))
    context.addPath(stroked)
    context.setFillColor(accent.color())
    context.fillPath()
    context.restoreGState()
    context.saveGState()
    context.addPath(stroked)
    context.clip()
    let from = glow.mixed(with: accent, 0.35)
    let to = accent.mixed(with: RGB(r: 0, g: 0, b: 0), 0.08)
    if let gradient = CGGradient(colorsSpace: space, colors: [from.color(), to.color()] as CFArray, locations: [0, 1]) {
        let box = stroked.boundingBox
        context.drawLinearGradient(gradient, start: CGPoint(x: box.minX, y: 0), end: CGPoint(x: box.maxX, y: 0), options: [])
    }
    context.restoreGState()
}

func caption() {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attributes: Dictionary<NSAttributedString.Key, Any> = [
        .font: NSFont.systemFont(ofSize: 13, weight: .medium),
        .foregroundColor: NSColor(cgColor: ink.color(0.78)) ?? .secondaryLabelColor,
        .paragraphStyle: paragraph,
        .kern: 0.1,
    ]
    let text = NSAttributedString(string: design.caption, attributes: attributes)
    let height = text.size().height
    text.draw(in: CGRect(x: 0, y: design.captionY - height / 2, width: design.width, height: height))
}

func grain(_ context: CGContext) {
    guard let data = context.data else { return }
    let pixels = data.bindMemory(to: UInt8.self, capacity: context.bytesPerRow * context.height)
    var generator = SystemRandomNumberGenerator()
    for row in 0..<context.height {
        for column in 0..<context.width {
            let offset = row * context.bytesPerRow + column * 4
            let noise = Int.random(in: -2...2, using: &generator)
            for channel in 0..<3 {
                pixels[offset + channel] = UInt8(max(0, min(255, Int(pixels[offset + channel]) + noise)))
            }
        }
    }
}

func render(scale: CGFloat, to url: URL) throws {
    let width = Int(design.width * scale)
    let height = Int(design.height * scale)
    guard
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { throw CocoaError(.featureUnsupported) }
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: scale, y: -scale)
    context.interpolationQuality = .high
    context.setShouldAntialias(true)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
    backdrop(context)
    waves(context)
    arrow(context)
    caption()
    NSGraphicsContext.current = nil
    grain(context)
    guard let image = context.makeImage() else { throw CocoaError(.featureUnsupported) }
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: design.width, height: design.height)
    guard let png = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.featureUnsupported) }
    try png.write(to: url)
}

let work = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: work) }
let standard = work.appending(path: "background.png")
let retina = work.appending(path: "background@2x.png")
try render(scale: 1, to: standard)
try render(scale: 2, to: retina)
let tiffutil = Process()
tiffutil.executableURL = URL(fileURLWithPath: "/usr/bin/tiffutil")
tiffutil.arguments = ["-cathidpicheck", standard.path, retina.path, "-out", directory.appending(path: "background.tiff").path]
try tiffutil.run()
tiffutil.waitUntilExit()
guard tiffutil.terminationStatus == 0 else { exit(tiffutil.terminationStatus) }
print("Wrote \(directory.appending(path: "background.tiff").path)")
