import SwiftUI

/// The app icon on Apple's 1024 grid: an indigo-violet squircle holding a white message
/// card with a small clock, i.e. a reminder being delivered. `Scripts/make-icon.sh`
/// renders it to `Resources/AppIcon.icns`; the menu header shows it live.
struct AppIconArtwork: View {
    var body: some View {
        Canvas { context, size in
            let s = size.width / 1024
            context.scaleBy(x: s, y: s)

            let tile = Path(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerRadius: 185, style: .continuous)
            var shadowed = context
            shadowed.addFilter(.shadow(color: .black.opacity(0.3), radius: 18, x: 0, y: 12))
            shadowed.fill(tile, with: .linearGradient(
                Gradient(colors: Brand.gradient),
                startPoint: CGPoint(x: 160, y: 120), endPoint: CGPoint(x: 880, y: 920)
            ))

            context.drawLayer { layer in
                layer.clip(to: tile)
                // Soft light from the top.
                layer.fill(tile, with: .radialGradient(Gradient(colors: [.white.opacity(0.22), .clear]),
                                                      center: CGPoint(x: 360, y: 160), startRadius: 0, endRadius: 620))

                // The message card, with a speech tail at its lower left.
                let card = Path(roundedRect: CGRect(x: 232, y: 262, width: 560, height: 420), cornerRadius: 96, style: .continuous)
                var tail = Path()
                tail.move(to: CGPoint(x: 312, y: 600))
                tail.addLine(to: CGPoint(x: 296, y: 778))
                tail.addLine(to: CGPoint(x: 452, y: 640))
                tail.closeSubpath()
                var lifted = layer
                lifted.addFilter(.shadow(color: Color(red: 0.12, green: 0.08, blue: 0.4).opacity(0.35), radius: 30, x: 0, y: 18))
                // Card and tail drawn as one layer so the shadow and fill merge cleanly.
                lifted.drawLayer { shape in
                    shape.fill(card, with: .color(.white))
                    shape.fill(tail, with: .color(.white))
                }

                // A clock inside the card.
                let center = CGPoint(x: 512, y: 472)
                let face = Path(ellipseIn: CGRect(x: center.x - 118, y: center.y - 118, width: 236, height: 236))
                layer.stroke(face, with: .linearGradient(Gradient(colors: Brand.gradient),
                                                         startPoint: CGPoint(x: 400, y: 360), endPoint: CGPoint(x: 620, y: 590)),
                             lineWidth: 30)
                var hands = Path()
                hands.move(to: CGPoint(x: center.x, y: center.y - 70))
                hands.addLine(to: center)
                hands.addLine(to: CGPoint(x: center.x + 56, y: center.y + 34))
                layer.stroke(hands, with: .color(Brand.gradient[0]),
                             style: StrokeStyle(lineWidth: 30, lineCap: .round, lineJoin: .round))
            }
            context.stroke(tile, with: .color(.white.opacity(0.12)), lineWidth: 3)
        }
    }
}
