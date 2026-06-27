#!/bin/bash
# Generates AppIcon.icns (a gradient rounded-square with a white gear glyph)
# using AppKit. Output: build/AppIcon.icns
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build

cat > build/_gen_icon.swift <<'SWIFT'
import AppKit

let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()

let rect = NSRect(x: 0, y: 0, width: size, height: size)
let clip = NSBezierPath(roundedRect: rect, xRadius: size * 0.225, yRadius: size * 0.225)
clip.addClip()

let grad = NSGradient(colors: [
    NSColor(srgbRed: 0.36, green: 0.42, blue: 0.96, alpha: 1),
    NSColor(srgbRed: 0.55, green: 0.30, blue: 0.86, alpha: 1)
])!
grad.draw(in: rect, angle: -90)

func whiteSymbol(_ name: String, point: CGFloat) -> NSImage? {
    let cfg = NSImage.SymbolConfiguration(pointSize: point, weight: .semibold)
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) else { return nil }
    let out = NSImage(size: base.size)
    out.lockFocus()
    let r = NSRect(origin: .zero, size: base.size)
    base.draw(in: r)
    NSColor.white.set()
    r.fill(using: .sourceAtop)
    out.unlockFocus()
    return out
}

if let gear = whiteSymbol("gearshape.2.fill", point: size * 0.5) {
    let s = gear.size
    let origin = NSPoint(x: (size - s.width) / 2, y: (size - s.height) / 2)
    gear.draw(in: NSRect(origin: origin, size: s), from: .zero, operation: .sourceOver, fraction: 1)
}

img.unlockFocus()

let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: "build/icon_1024.png"))
SWIFT

echo "▸ Rendering 1024px master…"
swift build/_gen_icon.swift

echo "▸ Building iconset…"
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for spec in "16:16x16" "32:16x16@2x" "32:32x32" "64:32x32@2x" \
            "128:128x128" "256:128x128@2x" "256:256x256" "512:256x256@2x" \
            "512:512x512" "1024:512x512@2x"; do
    px="${spec%%:*}"; name="${spec##*:}"
    sips -z "$px" "$px" build/icon_1024.png --out "$ICONSET/icon_${name}.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o build/AppIcon.icns
rm -rf "$ICONSET" build/icon_1024.png build/_gen_icon.swift
echo "✓ Built build/AppIcon.icns"
