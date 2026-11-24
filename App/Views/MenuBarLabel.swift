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
