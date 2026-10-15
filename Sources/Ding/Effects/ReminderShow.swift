import AppKit

/// Plays a reminder on the screen under the mouse: the chosen character runs in and
/// delivers it (see `CharacterRunner`). The panel is click-through except over the
/// speech bubble, so it never gets in the way of your work.
@MainActor
final class ReminderShowController {
    var onSnooze: (Reminder) -> Void = { _ in }

    private var panels: [ReminderPanel] = []
    private var runners: [CharacterRunner] = []

    func show(_ reminder: Reminder, character: Character?) {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
            ?? NSScreen.main else { return }

        let panel = ReminderPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                                  backing: .buffered, defer: false)
        panel.setFrame(screen.frame, display: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        // Above the Hide Everything cover, so a reminder still gets through.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none

        let runner = CharacterRunner(character: character, reminder: reminder, screen: screen)
        runner.setInteractive = { [weak panel] on in
            panel?.ignoresMouseEvents = !on
            // Key (without activating Ding) so the card's buttons respond to the first click.
            if on { panel?.makeKey() }
        }
        runner.onSnooze = { [weak self] in self?.onSnooze(reminder) }
        runner.onFinished = { [weak self, weak panel, weak runner] in
            panel?.orderOut(nil)
            self?.panels.removeAll { $0 === panel }
            self?.runners.removeAll { $0 === runner }
        }
        panel.contentView = runner.view
        panel.orderFrontRegardless()
        panels.append(panel)
        runners.append(runner)

        runner.play()
        NSSound(named: "Glass")?.play()
    }
}

/// Borderless panels can't normally become key; this one can, so its buttons work.
final class ReminderPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
