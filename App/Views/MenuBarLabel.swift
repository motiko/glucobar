import AppKit
import SwiftUI

/// The text next to the clock. MenuBarExtra renders labels as monochrome templates,
/// so coloured text (out of range, Stale) is drawn into a non-template image.
struct MenuBarLabel: View {
    let text: String
    let color: NSColor?

    var body: some View {
        if let color {
            Image(nsImage: Self.render(text, color: color))
        } else {
            Text(text)
        }
    }

    /// The app icon's gauge as a monochrome template, shown while there is no Reading (signed out,
    /// first fetch). Thick arc = target range, as in the icon.
    static let gauge: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 16), flipped: false) { _ in
            let c = NSPoint(x: 9, y: 4.5), r: CGFloat = 7
            func arc(_ from: CGFloat, _ to: CGFloat, width: CGFloat) {
                let p = NSBezierPath()
                p.appendArc(withCenter: c, radius: r, startAngle: from, endAngle: to, clockwise: true)
                p.lineWidth = width
                p.stroke()
            }
            NSColor.black.setStroke()
            arc(200, 152, width: 1.2)
            arc(148, 32, width: 2.6)
            arc(28, -20, width: 1.2)
            let needle = NSBezierPath()
            needle.move(to: c)
            needle.line(to: NSPoint(x: c.x + 5.6 * cos(.pi * 70 / 180), y: c.y + 5.6 * sin(.pi * 70 / 180)))
            needle.lineWidth = 1.8
            needle.lineCapStyle = .round
            needle.stroke()
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: c.x - 2, y: c.y - 2, width: 4, height: 4)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }()

    static func render(_ text: String, color: NSColor) -> NSImage {
        let attributed = NSAttributedString(string: text, attributes: [
            .font: NSFont.menuBarFont(ofSize: 0),
            .foregroundColor: color,
        ])
        let size = attributed.size()
        let image = NSImage(size: NSSize(width: ceil(size.width), height: ceil(size.height)), flipped: false) { rect in
            attributed.draw(in: rect)
            return true
        }
        image.isTemplate = false
        return image
    }
}
