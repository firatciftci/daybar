import AppKit

enum MenuBarIcon {
    static let meetingWidth: CGFloat = 18
    static let gap: CGFloat = 6

    static func item(day: Int, meeting: MeetingLink.Service?, live: Bool) -> NSImage {
        let lead = meeting == nil ? 0 : meetingWidth + gap
        let size = NSSize(width: 20 + lead, height: 17)
        let glyph = meeting?.nsImage
        let image = NSImage(size: size, flipped: false) { _ in
            if meeting != nil {
                if let glyph {
                    let scale = min(17 / glyph.size.width, 16 / glyph.size.height)
                    let width = glyph.size.width * scale
                    let height = glyph.size.height * scale
                    let frame = NSRect(x: (meetingWidth - width) / 2, y: (size.height - height) / 2, width: width, height: height)
                    glyph.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1)
                }
                if live {
                    NSColor.black.setFill()
                    NSBezierPath(ovalIn: NSRect(x: 13.5, y: 12.5, width: 4.5, height: 4.5)).fill()
                }
            }
            drawDate(day: day, offset: lead)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Daybar"
        return image
    }

    private static func drawDate(day: Int, offset: CGFloat) {
        let body = NSRect(x: offset + 1.75, y: 1.25, width: 16.5, height: 13.75)
        let outline = NSBezierPath(roundedRect: body, xRadius: 4, yRadius: 4)
        NSColor.black.setStroke()
        NSColor.black.setFill()
        outline.lineWidth = 1.35
        outline.stroke()

        NSGraphicsContext.saveGraphicsState()
        outline.addClip()
        NSRect(x: body.minX, y: body.maxY - 3.4, width: body.width, height: 3.4).fill()
        NSGraphicsContext.restoreGraphicsState()

        for x in [body.minX + 4.25, body.maxX - 4.25] {
            let ring = NSBezierPath(
                roundedRect: NSRect(x: x - 0.8, y: body.maxY - 1.4, width: 1.6, height: 3.2), xRadius: 0.8, yRadius: 0.8)
            ring.fill()
        }

        let base = NSFont.systemFont(ofSize: 9.5, weight: .bold)
        let descriptor = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
        let font = NSFont(descriptor: descriptor, size: 9.5) ?? base
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black,
            .kern: -0.2,
        ]
        let text = NSAttributedString(string: "\(day)", attributes: attributes)
        let textSize = text.size()
        let area = NSRect(x: body.minX, y: body.minY, width: body.width, height: body.height - 3.4)
        let origin = NSPoint(x: area.midX - textSize.width / 2, y: area.midY - textSize.height / 2 + 0.3)
        text.draw(at: origin)
    }
}
