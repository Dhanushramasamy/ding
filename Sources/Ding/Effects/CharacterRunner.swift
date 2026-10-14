import AppKit
import Lottie
import SwiftUI

/// A Lottie animation in Characters/ that is one of the menu's choices.
struct Character: Identifiable, Hashable {
    let name: String
    let url: URL
    var id: String { name }

    /// Every JSON bundled in Contents/Resources/Characters, alphabetically.
    static var all: [Character] {
        guard let folder = Bundle.main.resourceURL?.appendingPathComponent("Characters"),
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
            return []
        }
        return files
            .filter { $0.pathExtension.lowercased() == "json" }
            .map { Character(name: $0.deletingPathExtension().lastPathComponent, url: $0) }
            .sorted { $0.name < $1.name }
    }
}

// MARK: - Measuring the artwork

/// Where the drawing actually sits inside a Lottie canvas, as fractions (y downward),
/// and which frame looks most like standing still. Characters are usually drawn
/// mid-canvas with empty space around them, so the canvas edge is not where their feet are.
struct ArtBounds {
    var top: CGFloat = 0.25
    var bottom: CGFloat = 0.75
    var centerX: CGFloat = 0.5
    /// The narrowest pose in the loop (legs together), used when it stops.
    var standFrame: CGFloat = 0

    @MainActor
    static func measure(_ animation: LottieAnimation) -> ArtBounds {
        let w = 160, h = 160
        let layer = LottieAnimationLayer(animation: animation, configuration: LottieConfiguration(renderingEngine: .mainThread))
        layer.frame = CGRect(origin: .zero, size: animation.size)
        var minRow = h, maxRow = -1, minCol = w, maxCol = -1
        var narrowest = (width: Int.max, frame: animation.startFrame)
        for progress in stride(from: 0.0, to: 1.0, by: 1.0 / 16) {
            layer.currentProgress = progress
            layer.forceDisplayUpdate()
            layer.display()
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                                             samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                             bytesPerRow: 0, bitsPerPixel: 0),
                  let ctx = NSGraphicsContext(bitmapImageRep: rep)?.cgContext else { continue }
            ctx.scaleBy(x: CGFloat(w) / animation.size.width, y: CGFloat(h) / animation.size.height)
            // render(in:) draws the layer around its centre point; shift it back into the bitmap.
            ctx.translateBy(x: animation.size.width / 2, y: animation.size.height / 2)
            layer.render(in: ctx)
            var frameMin = w, frameMax = -1
            for row in 0..<h {
                for col in 0..<w where rep.colorAt(x: col, y: row)!.alphaComponent > 0.08 {
                    minRow = min(minRow, row); maxRow = max(maxRow, row)
                    frameMin = min(frameMin, col); frameMax = max(frameMax, col)
                }
            }
            minCol = min(minCol, frameMin); maxCol = max(maxCol, frameMax)
            if frameMax >= 0 && frameMax - frameMin < narrowest.width {
                narrowest = (frameMax - frameMin, layer.currentFrame)
            }
        }
        guard maxRow >= 0 else { return ArtBounds(standFrame: animation.startFrame) }
        // render(in:) lands upside down in the bitmap: its top rows are the art's bottom.
        return ArtBounds(top: 1 - CGFloat(maxRow + 1) / CGFloat(h),
                         bottom: 1 - CGFloat(minRow) / CGFloat(h),
                         centerX: CGFloat(minCol + maxCol + 1) / 2 / CGFloat(w),
                         standFrame: narrowest.frame)
    }
}

// MARK: - Card

@MainActor
final class BubbleModel: ObservableObject {
    @Published var visible = false
    /// Set when Done or Snooze is clicked: the card slides up and away.
    @Published var leaving = false
    @Published var message = ""
    @Published var tip = CGPoint.zero
    @Published var hovering = false
    /// The card's rectangle on screen (top-left origin), for click-through decisions.
    var frame = CGRect.zero
    var onDone: () -> Void = {}
    var onSnooze: () -> Void = {}
}

/// The reminder: the message and two buttons on frosted glass that blurs whatever is
/// behind it, like a macOS popover. Adapts to light and dark mode.
struct ReminderBubble: View {
    @ObservedObject var model: BubbleModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(model.message)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(.primary)
                .lineSpacing(2)
                .frame(maxWidth: 380, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button("Snooze", action: model.onSnooze)
                    .buttonStyle(PillButtonStyle())
                Button("Done", action: model.onDone)
                    .buttonStyle(PillButtonStyle(prominent: true))
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .frame(minWidth: 280, alignment: .leading)
        .background(VisualEffect(material: .popover))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.primary.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.22), radius: 28, y: 14)
        .shadow(color: .black.opacity(0.10), radius: 3, y: 1)
        // Fade in where it stands; slide up and away when dismissed.
        .opacity(model.visible && !model.leaving ? 1 : 0)
        .offset(y: model.leaving ? -50 : (model.visible ? 0 : 8))
        .animation(.easeOut(duration: 0.3), value: model.visible)
        .animation(.easeIn(duration: 0.3), value: model.leaving)
    }
}

/// Places the card so its tail tip sits on `model.tip`, and reports where it is.
struct BubbleOverlay: View {
    @ObservedObject var model: BubbleModel

    var body: some View {
        ReminderBubble(model: model)
            .fixedSize()
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { frame in
                model.frame = frame
            }
            .frame(width: 0, height: 0, alignment: .bottom)
            .position(model.tip)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A top-left-origin container, so the character and the SwiftUI bubble share one
/// coordinate system.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - Runner

/// Delivers a reminder: the character runs in from the left and brakes to a stop in
/// the middle of the screen, timed so its legs land on the standing pose just as it
/// arrives. The card then fades in above it. Done or Snooze slides the card away and
/// the character runs on and off the right edge.
@MainActor
final class CharacterRunner: NSObject {
    private enum Phase { case runIn, present, runOut, done }

    let view: NSView
    /// Called with true while the cursor is over the card, so the panel takes clicks there.
    var setInteractive: (Bool) -> Void = { _ in }
    var onSnooze: () -> Void = {}
    var onFinished: () -> Void = {}

    private let screenFrame: CGRect
    private let size: CGSize
    private let stage: FlippedView
    private let character: LottieAnimationView?
    private let animation: LottieAnimation?
    private let art: ArtBounds
    private let bubble = BubbleModel()
    private let drawnTarget: CGFloat

    private var phase = Phase.done
    private var lastTimestamp: CFTimeInterval = 0
    private var x: CGFloat = 0
    private var velocity: CGFloat = 0
    private var interactive = false
    private var finished = false
    private var displayLink: CADisplayLink?

    private static let runSpeed: CGFloat = 560
    private static let braking: CGFloat = 700        // points/s², a gentle, even slow-down
    private static let acceleration: CGFloat = 1200

    init(animation: LottieAnimation?, reminder: Reminder, screen: NSScreen, drawnHeight: CGFloat = 190) {
        screenFrame = screen.frame
        size = screen.frame.size
        drawnTarget = drawnHeight
        self.animation = animation
        view = NSView(frame: CGRect(origin: .zero, size: size))
        stage = FlippedView(frame: view.bounds)
        stage.wantsLayer = true

        if let animation {
            art = ArtBounds.measure(animation)
            let lottie = LottieAnimationView(animation: animation)
            lottie.contentMode = .scaleAspectFit
            lottie.loopMode = .loop
            lottie.backgroundBehavior = .continuePlaying
            character = lottie
        } else {
            art = ArtBounds()
            character = nil
        }
        super.init()

        view.addSubview(stage)
        if let character { stage.addSubview(character) }
        let bubbleView = FirstClickHostingView(rootView: BubbleOverlay(model: bubble))
        bubbleView.frame = view.bounds
        view.addSubview(bubbleView)

        bubble.message = reminder.message
        bubble.onDone = { [weak self] in self?.dismiss(snooze: false) }
        bubble.onSnooze = { [weak self] in self?.dismiss(snooze: true) }
    }

    private var groundY: CGFloat { size.height * 0.68 }
    /// Side of the square the animation is fitted into, so the drawing itself (not the
    /// empty canvas around it) is `drawnTarget` tall.
    private var boxSide: CGFloat { drawnTarget / max(art.bottom - art.top, 0.2) }
    private var drawnHeight: CGFloat { character == nil ? 0 : (art.bottom - art.top) * boxSide }

    func play() {
        x = character == nil ? size.width / 2 : -boxSide
        velocity = Self.runSpeed
        place()
        if let character {
            character.play()
            phase = .runIn
        } else {
            showCard()
        }
        let link = view.displayLink(target: self, selector: #selector(tick(_:)))
        // As smooth as the display allows (120 Hz on ProMotion screens).
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func showCard() {
        phase = .present
        bubble.tip = CGPoint(x: x, y: groundY - drawnHeight - 18)
        bubble.visible = true
    }

    private func dismiss(snooze: Bool) {
        guard phase == .present else { return }
        if snooze { onSnooze() }
        bubble.leaving = true
        if interactive {
            interactive = false
            setInteractive(false)
            NSCursor.pop()
        }
        velocity = 0
        character?.play()
        phase = .runOut
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        displayLink?.invalidate()
        displayLink = nil
        character?.stop()
        DispatchQueue.main.async { self.onFinished() }
    }

    @objc private func tick(_ link: CADisplayLink) {
        let dt = lastTimestamp == 0 ? 1.0 / 120 : min(link.timestamp - lastTimestamp, 1.0 / 30)
        lastTimestamp = link.timestamp

        switch phase {
        case .runIn:
            runIn(dt)
        case .present:
            updateHover()
        case .runOut:
            velocity = min(Self.runSpeed, velocity + Self.acceleration * CGFloat(dt))
            x += velocity * CGFloat(dt)
            character?.animationSpeed = max(0.4, velocity / Self.runSpeed)
            if x > size.width + boxSide || character == nil {
                phase = .done
                // Let the card finish sliding away before the panel closes.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.finish() }
            }
        case .done:
            break
        }
        place()
    }

    /// Full speed, then an even brake that ends exactly at the centre. While braking,
    /// the leg cycle is paced so the standing pose comes up at the moment it stops.
    private func runIn(_ dt: Double) {
        guard let character, let animation else { return }
        let center = size.width / 2
        let remaining = max(0, center - x)
        let brakeFrom = sqrt(2 * Self.braking * remaining)

        if brakeFrom < velocity {
            velocity = max(0, brakeFrom)
            let timeLeft = Double(velocity / Self.braking)
            let cycle = animation.endFrame - animation.startFrame
            var framesLeft = (art.standFrame - character.realtimeAnimationFrame).truncatingRemainder(dividingBy: cycle)
            if framesLeft < 0 { framesLeft += cycle }
            if timeLeft > 0.05 {
                let natural = Double(velocity / Self.runSpeed)
                let needed = Double(framesLeft) / (animation.framerate * timeLeft)
                // Stay close to the natural pace; only nudge it to line the pose up.
                character.animationSpeed = CGFloat(max(natural * 0.6, min(natural * 1.6 + 0.2, needed)))
            }
        } else {
            velocity = Self.runSpeed
            character.animationSpeed = 1
        }
        x += velocity * CGFloat(dt)

        if remaining < 0.5 || velocity < 1 {
            x = center
            velocity = 0
            character.pause()
            character.currentFrame = art.standFrame
            showCard()
        }
    }

    private func updateHover() {
        let mouse = NSEvent.mouseLocation
        let cursor = CGPoint(x: mouse.x - screenFrame.minX, y: screenFrame.maxY - mouse.y)
        let over = bubble.frame.insetBy(dx: -4, dy: -4).contains(cursor)
        guard over != interactive else { return }
        interactive = over
        setInteractive(over)
        if over { NSCursor.pointingHand.push() } else { NSCursor.pop() }
    }

    private func place() {
        guard let character else { return }
        let box = boxSide
        // The drawing's feet (bottom, horizontal centre) land on (x, ground).
        character.frame = CGRect(x: x - art.centerX * box, y: groundY - art.bottom * box, width: box, height: box)
    }
}
