import AppKit
import SwiftUI

/// Puts one opaque panel over every connected display and removes them on demand.
/// Apps underneath keep running untouched; they are only covered, never hidden or quit.
@MainActor
final class CoverController {
    private var panels: [CoverPanel] = []
    private var screenObserver: NSObjectProtocol?
    private var keyMonitor: Any?

    var isShowing: Bool { !panels.isEmpty }

    func toggle() {
        isShowing ? hide() : show()
    }

    func show() {
        guard !isShowing else { return }
        buildPanels()

        // Re-cover if a display is plugged in, removed or rearranged while hidden.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        }

        // Esc reveals everything again.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.hide()
            return nil
        }
    }

    func hide() {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        screenObserver = nil
        keyMonitor = nil
        removePanels()
    }

    private func rebuild() {
        removePanels()
        buildPanels()
    }

    private func buildPanels() {
        for screen in NSScreen.screens {
            let panel = CoverPanel(screen: screen) { [weak self] in self?.hide() }
            panel.orderFrontRegardless()
            panels.append(panel)
        }
        // Activate so the cover receives Esc instead of the app underneath.
        NSApp.activate()
        panels.first?.makeKey()
    }

    private func removePanels() {
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
    }
}

/// Borderless black panel sized to one screen, above the menu bar, Dock and full-screen apps.
final class CoverPanel: NSPanel {
    init(screen: NSScreen, onShow: @escaping () -> Void) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        setFrame(screen.frame, display: false)

        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .black
        isOpaque = true
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none

        contentView = FirstClickHostingView(rootView: CoverView(onShow: onShow))
    }

    override var canBecomeKey: Bool { true }
}

/// Lets the "Show Everything" button work on the first click, even on a panel that isn't key.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct CoverView: View {
    let onShow: () -> Void

    var body: some View {
        ZStack {
            // Solid, so nothing underneath can show through.
            LinearGradient(colors: [Color(white: 0.09), Color(white: 0.03)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 28) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(spacing: 4) {
                        Text(context.date, format: .dateTime.hour().minute())
                            .font(.system(size: 104, weight: .thin))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                        Text(context.date, format: .dateTime.weekday(.wide).day().month(.wide))
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
                Button("Show Everything", action: onShow)
                    .buttonStyle(PillButtonStyle(prominent: true))
                    .controlSize(.large)
                Text("Esc or ⌃⌥H")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .environment(\.colorScheme, .dark)
    }
}
