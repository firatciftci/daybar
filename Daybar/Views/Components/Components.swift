import AppKit
import SwiftUI

struct DayFingerprint: View {
    let occurrences: Array<Occurrence>
    var width: CGFloat = 20
    var height: CGFloat = 3.5

    private let windowStart: Double = 7 * 60
    private let windowEnd: Double = 22 * 60

    var body: some View {
        Canvas { context, size in
            guard !occurrences.isEmpty else { return }
            let track = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: size.height / 2)
            context.fill(track, with: .color(.primary.opacity(0.07)))
            context.clip(to: track)
            let span = windowEnd - windowStart
            for occurrence in occurrences {
                if occurrence.isAllDay || occurrence.spansMultipleDays {
                    context.fill(track, with: .color(occurrence.color.opacity(0.45)))
                    continue
                }
                let startMinutes = max(windowStart, occurrence.start.minutesIntoDay)
                let endMinutes = min(windowEnd, max(occurrence.end.minutesIntoDay, startMinutes + 20))
                guard endMinutes > windowStart, startMinutes < windowEnd else { continue }
                let x = (startMinutes - windowStart) / span * size.width
                let w = max(2, (endMinutes - startMinutes) / span * size.width)
                let rect = CGRect(x: x, y: 0, width: w, height: size.height)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: size.height / 2),
                    with: .color(occurrence.isDeclined ? occurrence.color.opacity(0.35) : occurrence.color))
            }
        }
        .frame(width: width, height: height)
        .opacity(occurrences.isEmpty ? 0 : 1)
        .accessibilityHidden(true)
    }
}

struct CalendarDot: View {
    let color: Color
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
    }
}

struct GlassCircleButton: View {
    let symbol: String
    let help: String
    var active = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12.5, weight: .semibold))
        }
        .buttonStyle(GlassCircleStyle(active: active))
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

enum Motion {
    static let select = Animation.snappy(duration: 0.3)
    static let lift = Animation.snappy(duration: 0.24)
    static let navigate = Animation.spring(duration: 0.42, bounce: 0)
    static let content = Animation.easeInOut(duration: 0.18)
    static let fade = Animation.easeOut(duration: 0.14)
}

struct GlassCircleStyle: ButtonStyle {
    var active = false

    func makeBody(configuration: Configuration) -> some View {
        GlassCircleBody(configuration: configuration, active: active)
    }
}

private struct GlassCircleBody: View {
    let configuration: ButtonStyleConfiguration
    let active: Bool

    var body: some View {
        let pressed = configuration.isPressed
        configuration.label
            .foregroundStyle(active ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary))
            .animation(Motion.fade, value: active)
            .frame(width: 30, height: 30)
            .background {
                Circle().fill(.primary.opacity(pressed ? 0.12 : 0))
            }
            .contentShape(.circle)
            .glassEffect(.regular.interactive(), in: .circle)
            .animation(pressed ? nil : Motion.fade, value: pressed)
    }
}

struct Metrics {
    let compact: Bool

    var titleSize: CGFloat { compact ? 12.5 : 14 }
    var metaSize: CGFloat { compact ? 11 : 12 }
    var timeSize: CGFloat { compact ? 10.5 : 11.5 }
    var timeWidth: CGFloat { compact ? 52 : 60 }
    var rowHeight: CGFloat { compact ? 26 : 48 }
    var rowPadding: CGFloat { compact ? 2 : 7 }
    var headerSize: CGFloat { compact ? 12 : 14 }
    var headerTop: CGFloat { compact ? 8 : 16 }
    var gridRow: CGFloat { compact ? 31 : 38 }
    var dayDiameter: CGFloat { compact ? 25 : 30 }
    var dayFont: CGFloat { compact ? 11.5 : 13 }
}

extension EnvironmentValues {
    @Entry var metrics = Metrics(compact: false)
}

struct RowButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 10
    var hoverable = true

    func makeBody(configuration: Configuration) -> some View {
        RowButtonBody(configuration: configuration, cornerRadius: cornerRadius, hoverable: hoverable)
    }
}

private struct RowButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let cornerRadius: CGFloat
    let hoverable: Bool
    @State private var hovering = false
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        let pressed = configuration.isPressed
        configuration.label
            .contentShape(.rect(cornerRadius: cornerRadius))
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.primary.opacity(pressed ? 0.17 : (hoverable && hovering && enabled ? 0.1 : 0)))
            }
            .onHover { hovering = $0 }
            .animation(pressed ? nil : Motion.fade, value: pressed)
            .animation(Motion.fade, value: hovering)
    }
}

struct ContactAvatar: View {
    let card: ContactCard?
    let name: String
    var size: CGFloat = 24

    private var initials: String {
        let source = card?.name ?? name
        if source.contains("@") { return source.first.map { String($0).uppercased() } ?? "?" }
        let words = source.split(whereSeparator: { !$0.isLetter }).prefix(2)
        let letters = words.compactMap(\.first).map { String($0).uppercased() }.joined()
        return letters.isEmpty ? "?" : letters
    }

    var body: some View {
        Group {
            if let data = card?.thumbnail, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(initials)
                    .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(LinearGradient(colors: [Color(white: 0.66), Color(white: 0.48)], startPoint: .top, endPoint: .bottom))
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}

enum Party {
    static let colors: Array<Color> = [.pink, .yellow, .mint, .cyan, .purple, .orange]
    static let accent = Color.pink
}

struct BirthdayGlyph: View {
    var size: CGFloat = 13
    var bounce = 0

    var body: some View {
        Image(systemName: "birthday.cake.fill")
            .accessibilityHidden(true)
            .symbolRenderingMode(.palette)
            .foregroundStyle(Party.accent, Color.yellow)
            .font(.system(size: size, weight: .semibold))
            .symbolEffect(.bounce.up, value: bounce)
    }
}

struct SprinkleBar: View {
    var width: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            let count = max(3, Int(proxy.size.height / (width + 2.5)))
            VStack(spacing: 0) {
                ForEach(0..<count, id: \.self) { index in
                    Capsule()
                        .fill(Party.colors[index % Party.colors.count])
                        .frame(width: width, height: width)
                        .frame(maxHeight: .infinity)
                }
            }
        }
        .frame(width: width)
        .accessibilityHidden(true)
    }
}

struct SprinkleField: View {
    @State private var sprinkles = (0..<38).map { _ in Sprinkle() }

    var body: some View {
        Canvas { context, size in
            for sprinkle in sprinkles {
                var layer = context
                layer.opacity = sprinkle.opacity
                layer.translateBy(x: sprinkle.x * size.width, y: sprinkle.y * size.height)
                layer.rotate(by: .degrees(sprinkle.angle))
                let rect = CGRect(x: -sprinkle.length / 2, y: -1.6, width: sprinkle.length, height: 3.2)
                layer.fill(Path(roundedRect: rect, cornerRadius: 1.6), with: .color(sprinkle.color))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct Sprinkle {
    let x = Double.random(in: 0.03...0.97)
    let y = Double.random(in: 0.03...0.97)
    let angle = Double.random(in: 0...180)
    let length = Double.random(in: 7...12)
    let opacity = Double.random(in: 0.35...0.7)
    let color = Party.colors.randomElement() ?? .pink
}

struct ConfettiBurst: View {
    let trigger: Int
    @State private var start: Date?
    @State private var pieces = (0..<54).map { _ in ConfettiPiece() }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let lifetime = 2.4

    var body: some View {
        TimelineView(.animation(paused: start == nil)) { timeline in
            Canvas { context, size in
                guard let start else { return }
                let t = timeline.date.timeIntervalSince(start)
                guard t < lifetime else { return }
                let origin = CGPoint(x: size.width / 2, y: size.height * 0.42)
                for piece in pieces {
                    let drag = 1 - min(0.6, t * 0.35)
                    let x = origin.x + piece.vx * t * drag + sin(t * piece.wobble) * 6
                    let y = origin.y + piece.vy * t * drag + 0.5 * 560 * t * t
                    var layer = context
                    layer.opacity = max(0, 1 - pow(t / lifetime, 2.2))
                    layer.translateBy(x: x, y: y)
                    layer.rotate(by: .radians(piece.spin * t))
                    layer.scaleBy(x: 1, y: abs(cos(t * piece.flip)) * 0.8 + 0.2)
                    let rect = CGRect(x: -piece.width / 2, y: -piece.height / 2, width: piece.width, height: piece.height)
                    let shape = piece.round ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: 1)
                    layer.fill(shape, with: .color(piece.color))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: trigger) {
            guard trigger > 0, !reduceMotion else { return }
            pieces = (0..<54).map { _ in ConfettiPiece() }
            start = .now
            try? await Task.sleep(for: .seconds(lifetime))
            start = nil
        }
    }
}

struct ConfettiPiece {
    let vx = Double.random(in: -190...190)
    let vy = Double.random(in: -430 ... -170)
    let spin = Double.random(in: -9...9)
    let flip = Double.random(in: 4...11)
    let wobble = Double.random(in: 3...8)
    let width = Double.random(in: 4...7)
    let height = Double.random(in: 7...11)
    let round = Bool.random() && Bool.random()
    let color = Party.colors.randomElement() ?? .pink
}

extension View {
    func inputCapsule(in namespace: Namespace.ID) -> some View {
        padding(.horizontal, 12)
            .frame(height: 34)
            .glassEffect(.regular.interactive(), in: .capsule)
            .glassEffectID("input", in: namespace)
    }

    func onHorizontalSwipe(_ action: @escaping (Int) -> Void) -> some View {
        background(SwipeCatcher(action: action))
    }
}

private struct SwipeCatcher: NSViewRepresentable {
    let action: (Int) -> Void

    func makeNSView(context _: Context) -> SwipeCatcherView {
        let view = SwipeCatcherView()
        view.action = action
        return view
    }

    func updateNSView(_ nsView: SwipeCatcherView, context _: Context) {
        nsView.action = action
    }
}

final class SwipeCatcherView: NSView {
    var action: ((Int) -> Void)?
    private var monitor: Any?
    private var accumulatedX: CGFloat = 0
    private var accumulatedY: CGFloat = 0
    private var fired = false

    override func hitTest(_: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let sample = ScrollSample(
                windowNumber: event.windowNumber,
                location: event.locationInWindow,
                precise: event.hasPreciseScrollingDeltas,
                phase: event.phase,
                momentum: event.momentumPhase,
                dx: event.scrollingDeltaX,
                dy: event.scrollingDeltaY
            )
            MainActor.assumeIsolated {
                self?.handle(sample)
            }
            return event
        }
    }

    private struct ScrollSample: Sendable {
        let windowNumber: Int
        let location: NSPoint
        let precise: Bool
        let phase: NSEvent.Phase
        let momentum: NSEvent.Phase
        let dx: CGFloat
        let dy: CGFloat
    }

    private func handle(_ event: ScrollSample) {
        guard let window, event.windowNumber == window.windowNumber, event.precise else { return }
        let point = convert(event.location, from: nil)
        guard bounds.contains(point) else { return }
        if event.phase == .began {
            accumulatedX = 0
            accumulatedY = 0
            fired = false
        }
        guard event.momentum.isEmpty else { return }
        accumulatedX += event.dx
        accumulatedY += event.dy
        if !fired, abs(accumulatedX) > 36, abs(accumulatedX) > abs(accumulatedY) * 1.6 {
            fired = true
            action?(accumulatedX < 0 ? 1 : -1)
        }
        if event.phase == .ended || event.phase == .cancelled {
            accumulatedX = 0
            accumulatedY = 0
        }
    }
}

struct MeetingGlyph: View {
    let service: MeetingLink.Service
    var size: CGFloat = 12

    var body: some View {
        service.image
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: size, height: size)
    }
}
