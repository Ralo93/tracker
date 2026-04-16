#!/usr/bin/swift
import AppKit

func renderIcon(size: Int) -> Data {
    let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        // Dark rounded background
        let bg = NSColor(red: 0.10, green: 0.12, blue: 0.18, alpha: 1.0)
        bg.setFill()
        NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.22, yRadius: rect.height * 0.22).fill()

        // "WL" text
        let fontSize = rect.width * 0.38
        let font = NSFont.boldSystemFont(ofSize: fontSize)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let str = NSAttributedString(string: "WL", attributes: attrs)
        let sz = str.size()
        str.draw(at: NSPoint(x: (rect.width - sz.width) / 2, y: (rect.height - sz.height) / 2))
        return true
    }
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconset = "/tmp/WorkLogger.iconset"
try? fm.removeItem(atPath: iconset)
try! fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)

let specs: [(Int, String)] = [
    (16,   "icon_16x16"),
    (32,   "icon_16x16@2x"),
    (32,   "icon_32x32"),
    (64,   "icon_32x32@2x"),
    (128,  "icon_128x128"),
    (256,  "icon_128x128@2x"),
    (256,  "icon_256x256"),
    (512,  "icon_256x256@2x"),
    (512,  "icon_512x512"),
    (1024, "icon_512x512@2x")
]

for (size, name) in specs {
    let data = renderIcon(size: size)
    try! data.write(to: URL(fileURLWithPath: "\(iconset)/\(name).png"))
}

let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset, "-o", "/tmp/WorkLogger.icns"]
try! p.run()
p.waitUntilExit()

print("Icon generated at /tmp/WorkLogger.icns")
