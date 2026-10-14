import AppKit
import SwiftUI

/// Ding's look: native macOS materials, SF Pro, and the user's system accent colour,
/// so everything feels at home in light and dark mode alike.
enum Brand {
    static let name = "Ding"
    static let tagline = "Reminders that come running."
    /// Used where the system accent can't be (the app icon).
    static let gradient = [Color(red: 0.35, green: 0.42, blue: 1.0), Color(red: 0.58, green: 0.32, blue: 0.98)]
}

/// Real behind-window blur (frosted glass), the material macOS uses for popovers and HUDs.
struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

/// Capsule buttons: a filled accent one for the main action, a quiet tinted one otherwise.
struct PillButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, prominent ? 18 : 14)
            .padding(.vertical, 7)
            .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .background(
                Capsule().fill(prominent ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary.opacity(0.08)))
            )
            .overlay(Capsule().strokeBorder(.primary.opacity(prominent ? 0 : 0.06), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Capsule())
    }
}

/// A softly filled rounded group, like the sections in Control Center.
struct PanelGroup<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 2)
            }
            VStack(alignment: .leading, spacing: 10) { content }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.primary.opacity(0.05)))
        }
    }
}
