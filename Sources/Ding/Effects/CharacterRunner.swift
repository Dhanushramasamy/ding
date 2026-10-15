import AppKit
import Lottie
import SwiftUI

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
        // Grows up out of the character; slides up and away when dismissed.
        .scaleEffect(model.visible && !model.leaving ? 1 : (model.leaving ? 0.97 : 0.4), anchor: .bottom)
        .opacity(model.visible && !model.leaving ? 1 : 0)
        .offset(y: model.leaving ? -50 : (model.visible ? 0 : 20))
        .animation(.easeOut(duration: 0.35), value: model.visible)
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

/// Delivers a reminder with the chosen character:
/// - a Lottie character runs in from a random point on any edge and brakes to a stop in
///   the middle of the screen, timed so its legs land on the standing pose as it arrives;
/// - your own image hop-runs in the same way (a still picture has no legs to animate);
/// The card then grows out of the character. Done or Snooze slides it away and everyone
/// leaves toward another edge.
@MainActor
final class CharacterRunner: NSObject {
    private enum Phase { case runIn, present, runOut, done }

    private enum Actor {
        case lottie(LottieAnimationView, LottieAnimation)
        case image(FlippedView, CALayer, CGSize)
        case none
    }

    private enum Edge: CaseIterable { case left, right, top, bottom }

    let view: NSView
    /// Called with true while the cursor is over the card, so the panel takes clicks there.
    var setInteractive: (Bool) -> Void = { _ in }
    var onSnooze: () -> Void = {}
    var onFinished: () -> Void = {}

    private let screenFrame: CGRect
    private let size: CGSize
    private let stage: FlippedView
    private let actor: Actor
    private var art = ArtBounds()
    private let bubble = BubbleModel()
    private let drawnTarget: CGFloat

    private var phase = Phase.done
    private var lastTimestamp: CFTimeInterval = 0
    /// The character's feet, in screen coordinates (top-left origin).
    private var position = CGPoint.zero
    private var direction = CGVector(dx: 1, dy: 0)
    private var facing: CGFloat = 1
    private var entryEdge = Edge.left
    private var exitPoint = CGPoint.zero
    private var velocity: CGFloat = 0
    private var hopPhase: Double = 0
    private var interactive = false
    private var finished = false
    private var displayLink: CADisplayLink?

    private static let runSpeed: CGFloat = 560
    private static let braking: CGFloat = 700        // points/s², a gentle, even slow-down
    private static let acceleration: CGFloat = 1200

    init(character: Character?, reminder: Reminder, screen: NSScreen, drawnHeight: CGFloat = 190) {
        screenFrame = screen.frame
        size = screen.frame.size
        drawnTarget = drawnHeight
        view = NSView(frame: CGRect(origin: .zero, size: size))
        stage = FlippedView(frame: view.bounds)
        stage.wantsLayer = true

        switch character?.kind {
        case .lottie?:
            if let url = character?.url, let animation = LottieAnimation.filepath(url.path) {
                art = ArtBounds.measure(animation)
                let lottie = LottieAnimationView(animation: animation)
                lottie.contentMode = .scaleAspectFit
                lottie.loopMode = .loop
                lottie.backgroundBehavior = .continuePlaying
                actor = .lottie(lottie, animation)
            } else {
                actor = .none
            }
        case .image?:
            if let url = character?.url,
               let image = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                // Fit the picture to the character height, capping very wide images.
                let aspect = CGFloat(image.width) / CGFloat(max(image.height, 1))
                var drawn = CGSize(width: drawnHeight * aspect, height: drawnHeight)
                if drawn.width > 300 { drawn = CGSize(width: 300, height: 300 / aspect) }
                let container = FlippedView(frame: CGRect(origin: .zero, size: drawn))
                container.wantsLayer = true
                let layer = CALayer()
                layer.contents = image
                layer.contentsGravity = .resizeAspect
                layer.contentsScale = screen.backingScaleFactor
                // Pivot at the feet, so tilting and squashing keep it on the ground.
                layer.anchorPoint = CGPoint(x: 0.5, y: 1)
                layer.bounds = CGRect(origin: .zero, size: drawn)
                layer.position = CGPoint(x: drawn.width / 2, y: drawn.height)
                container.layer?.addSublayer(layer)
                actor = .image(container, layer, drawn)
            } else {
                actor = .none
            }
        case nil:
            actor = .none
        }
        super.init()

        view.addSubview(stage)
        switch actor {
        case .lottie(let lottie, _):
            stage.addSubview(lottie)
        case .image(let container, _, _):
            stage.addSubview(container)
        case .none:
            break
        }
        let bubbleView = FirstClickHostingView(rootView: BubbleOverlay(model: bubble))
        bubbleView.frame = view.bounds
        view.addSubview(bubbleView)

        bubble.message = reminder.message
        bubble.onDone = { [weak self] in self?.dismiss(snooze: false) }
        bubble.onSnooze = { [weak self] in self?.dismiss(snooze: true) }
    }

    /// Where the character stops: its feet a little below the middle of the screen.
    private var stopPoint: CGPoint { CGPoint(x: size.width / 2, y: size.height * 0.62) }
    /// Side of the square a Lottie animation is fitted into, so the drawing itself (not
    /// the empty canvas around it) is `drawnTarget` tall.
    private var boxSide: CGFloat { drawnTarget / max(art.bottom - art.top, 0.2) }

    /// Height of the character on screen; zero when there isn't one standing there.
    private var actorHeight: CGFloat {
        switch actor {
        case .lottie: return (art.bottom - art.top) * boxSide
        case .image(_, _, let drawn): return drawn.height
        case .none: return 0
        }
    }

    private var actorWidth: CGFloat {
        switch actor {
        case .lottie: return boxSide
        case .image(_, _, let drawn): return drawn.width
        case .none: return 0
        }
    }

    func play() {
        velocity = Self.runSpeed
        switch actor {
        case .lottie, .image:
            entryEdge = Edge.allCases.randomElement()!
            position = point(on: entryEdge)
            aim(at: stopPoint)
            if case .lottie(let lottie, _) = actor { lottie.play() }
            phase = .runIn
        case .none:
            position = stopPoint
            showCard()
        }
        place()
        let link = view.displayLink(target: self, selector: #selector(tick(_:)))
        // As smooth as the display allows (120 Hz on ProMotion screens).
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    /// A random spot just beyond an edge, far enough out that the character starts unseen.
    private func point(on edge: Edge) -> CGPoint {
        let margin = actorWidth / 2 + 20
        switch edge {
        case .left: return CGPoint(x: -margin, y: .random(in: size.height * 0.3...size.height * 0.85))
        case .right: return CGPoint(x: size.width + margin, y: .random(in: size.height * 0.3...size.height * 0.85))
        case .top: return CGPoint(x: .random(in: size.width * 0.15...size.width * 0.85), y: -20)
        case .bottom: return CGPoint(x: .random(in: size.width * 0.15...size.width * 0.85), y: size.height + actorHeight + 20)
        }
    }

    private func aim(at target: CGPoint) {
        let dx = target.x - position.x, dy = target.y - position.y
        let length = max(hypot(dx, dy), 0.001)
        direction = CGVector(dx: dx / length, dy: dy / length)
        // Face the way it's going; straight up or down keeps the current facing.
        if direction.dx < -0.2 { facing = -1 } else if direction.dx > 0.2 { facing = 1 }
    }

    private func showCard() {
        phase = .present
        switch actor {
        case .lottie, .image:
            bubble.tip = CGPoint(x: position.x, y: position.y - actorHeight - 18)
        case .none:
            bubble.tip = CGPoint(x: size.width / 2, y: size.height * 0.58)
        }
        // Place it first, then reveal it, so it grows from the character rather than
        // sliding in from wherever it was before.
        DispatchQueue.main.async { self.bubble.visible = true }
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
        switch actor {
        case .lottie(let lottie, _):
            lottie.play()
            leaveTowardAnotherEdge()
        case .image:
            leaveTowardAnotherEdge()
        case .none:
            break
        }
        phase = .runOut
    }

    private func leaveTowardAnotherEdge() {
        let exitEdge = Edge.allCases.filter { $0 != entryEdge }.randomElement()!
        exitPoint = point(on: exitEdge)
        aim(at: exitPoint)
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        displayLink?.invalidate()
        displayLink = nil
        if case .lottie(let lottie, _) = actor { lottie.stop() }
        DispatchQueue.main.async { self.onFinished() }
    }

    @objc private func tick(_ link: CADisplayLink) {
        let dt = lastTimestamp == 0 ? 1.0 / 120 : min(link.timestamp - lastTimestamp, 1.0 / 30)
        lastTimestamp = link.timestamp

        switch phase {
        case .runIn:
            switch actor {
            case .lottie(let lottie, let animation): runIn(dt, lottie: lottie, animation: animation)
            case .image: runInImage(dt)
            case .none: break
            }
        case .present:
            updateHover()
        case .runOut:
            switch actor {
            case .none:
                complete()
            case .lottie(let lottie, _):
                runOut(dt)
                lottie.animationSpeed = max(0.4, velocity / Self.runSpeed)
            case .image:
                runOut(dt)
            }
        case .done:
            break
        }

        place()
    }

    private func runOut(_ dt: Double) {
        velocity = min(Self.runSpeed, velocity + Self.acceleration * CGFloat(dt))
        move(dt)
        let margin = actorWidth + actorHeight
        if !CGRect(origin: .zero, size: size).insetBy(dx: -margin, dy: -margin).contains(position) { complete() }
    }

    private func move(_ dt: Double) {
        let step = velocity * CGFloat(dt)
        position.x += direction.dx * step
        position.y += direction.dy * step
        hopPhase += Double(step) / 110 * .pi
    }

    private func complete() {
        guard phase != .done else { return }
        phase = .done
        // Let the card finish sliding away before the panel closes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.finish() }
    }

    /// How far is left to the stop point, and the speed to have there given even braking.
    private func brake() -> CGFloat {
        let remaining = hypot(stopPoint.x - position.x, stopPoint.y - position.y)
        let brakeFrom = sqrt(2 * Self.braking * remaining)
        velocity = brakeFrom < velocity ? max(0, brakeFrom) : Self.runSpeed
        return remaining
    }

    /// Full speed, then an even brake that ends exactly at the centre. While braking,
    /// the leg cycle is paced so the standing pose comes up at the moment it stops.
    private func runIn(_ dt: Double, lottie: LottieAnimationView, animation: LottieAnimation) {
        let wasRunning = velocity >= Self.runSpeed
        let remaining = brake()
        if velocity < Self.runSpeed || !wasRunning {
            let timeLeft = Double(velocity / Self.braking)
            let cycle = animation.endFrame - animation.startFrame
            var framesLeft = (art.standFrame - lottie.realtimeAnimationFrame).truncatingRemainder(dividingBy: cycle)
            if framesLeft < 0 { framesLeft += cycle }
            if timeLeft > 0.05 {
                let natural = Double(velocity / Self.runSpeed)
                let needed = Double(framesLeft) / (animation.framerate * timeLeft)
                // Stay close to the natural pace; only nudge it to line the pose up.
                lottie.animationSpeed = CGFloat(max(natural * 0.6, min(natural * 1.6 + 0.2, needed)))
            }
        } else {
            lottie.animationSpeed = 1
        }
        move(dt)

        if remaining < 0.5 || velocity < 1 {
            position = stopPoint
            velocity = 0
            lottie.pause()
            lottie.currentFrame = art.standFrame
            showCard()
        }
    }

    /// Same run and brake for a still image, which hops along instead of moving its legs.
    private func runInImage(_ dt: Double) {
        let remaining = brake()
        move(dt)
        if remaining < 0.5 || velocity < 1 {
            position = stopPoint
            velocity = 0
            hopPhase = 0
            showCard()
        }
    }

    private func cursorInStage() -> CGPoint {
        let mouse = NSEvent.mouseLocation
        return CGPoint(x: mouse.x - screenFrame.minX, y: screenFrame.maxY - mouse.y)
    }

    private func updateHover() {
        let over = bubble.frame.insetBy(dx: -4, dy: -4).contains(cursorInStage())
        guard over != interactive else { return }
        interactive = over
        setInteractive(over)
        if over { NSCursor.pointingHand.push() } else { NSCursor.pop() }
    }

    private func place() {
        switch actor {
        case .lottie(let lottie, _):
            let box = boxSide
            // The drawing's feet (bottom, horizontal centre) land on the position.
            lottie.frame = CGRect(x: position.x - art.centerX * box, y: position.y - art.bottom * box, width: box, height: box)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            lottie.layer?.sublayerTransform = CATransform3DMakeScale(facing, 1, 1)
            CATransaction.commit()
        case .image(let container, let layer, let drawn):
            // Hop with the stride, lean into the run, squash a little on each landing.
            let pace = min(1, Double(velocity / Self.runSpeed) * 1.5)
            let bounce = abs(sin(hopPhase))
            let lift = CGFloat(bounce * 18 * pace)
            let tilt = CGFloat((0.07 + 0.05 * sin(hopPhase * 2)) * pace) * facing
            let squash = CGFloat((1 - bounce) * 0.06 * pace)
            container.frame = CGRect(x: position.x - drawn.width / 2, y: position.y - drawn.height - lift,
                                     width: drawn.width, height: drawn.height)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.transform = CATransform3DScale(CATransform3DMakeRotation(tilt, 0, 0, 1), 1 + squash, 1 - squash, 1)
            CATransaction.commit()
        case .none:
            break
        }
    }
}
