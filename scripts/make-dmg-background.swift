#!/usr/bin/env swift
//
// Renders the DMG window background (arrow + "drag to Applications" hint).
//
// Produces 1x and 2x PNGs, then combine them into an HiDPI .tiff with:
//   tiffutil -cathidpicheck bg-1x.png bg-2x.png -out dmg-background.tiff
//
// Coordinates match the create-dmg layout in scripts/release.sh:
//   --window-size 640 400  --icon "BrowserPicker.app" 170 190
//   --app-drop-link 470 190  --icon-size 128
//
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let width: CGFloat = 640
let height: CGFloat = 400

// Finder icon coordinates have their origin at the window's TOP-left; convert
// to CoreGraphics' bottom-left origin.
func cgY(_ topY: CGFloat) -> CGFloat { height - topY }

func makeContext(scale: CGFloat) -> CGContext {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(
        data: nil,
        width: Int(width * scale),
        height: Int(height * scale),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.scaleBy(x: scale, y: scale)
    return ctx
}

func drawBackground(_ ctx: CGContext) {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let colors = [
        CGColor(colorSpace: cs, components: [0.98, 0.98, 0.99, 1])!,
        CGColor(colorSpace: cs, components: [0.93, 0.94, 0.96, 1])!
    ] as CFArray
    let gradient = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: height),
        end: CGPoint(x: 0, y: 0),
        options: []
    )
}

func drawArrow(_ ctx: CGContext) {
    let blue = CGColor(red: 0.18, green: 0.49, blue: 0.96, alpha: 1)
    let y = cgY(190)
    let shaftStart: CGFloat = 258
    let shaftEnd: CGFloat = 372
    let tipX: CGFloat = 394
    let headHalf: CGFloat = 15

    ctx.setStrokeColor(blue)
    ctx.setLineWidth(9)
    ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: shaftStart, y: y))
    ctx.addLine(to: CGPoint(x: shaftEnd, y: y))
    ctx.strokePath()

    ctx.setFillColor(blue)
    ctx.move(to: CGPoint(x: tipX, y: y))
    ctx.addLine(to: CGPoint(x: shaftEnd - 2, y: y + headHalf))
    ctx.addLine(to: CGPoint(x: shaftEnd - 2, y: y - headHalf))
    ctx.closePath()
    ctx.fillPath()
}

func drawCenteredText(_ ctx: CGContext, _ string: String, fontName: String,
                      size: CGFloat, color: CGColor, topY: CGFloat) {
    let font = CTFontCreateWithName(fontName as CFString, size, nil)
    let attrs: [CFString: Any] = [
        kCTFontAttributeName: font,
        kCTForegroundColorAttributeName: color
    ]
    let attributed = CFAttributedStringCreate(nil, string as CFString, attrs as CFDictionary)!
    let line = CTLineCreateWithAttributedString(attributed)
    let textWidth = CTLineGetTypographicBounds(line, nil, nil, nil)
    let x = (width - CGFloat(textWidth)) / 2

    ctx.textMatrix = .identity
    ctx.textPosition = CGPoint(x: x, y: cgY(topY))
    CTLineDraw(line, ctx)
}

func render(scale: CGFloat) -> CGImage {
    let ctx = makeContext(scale: scale)
    drawBackground(ctx)
    drawArrow(ctx)

    let titleColor = CGColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
    let hintColor = CGColor(red: 0.36, green: 0.36, blue: 0.39, alpha: 1)

    drawCenteredText(ctx, "Install Browser Picker",
                     fontName: "HelveticaNeue-Bold", size: 22,
                     color: titleColor, topY: 60)
    drawCenteredText(ctx, "Drag BrowserPicker onto the Applications folder",
                     fontName: "HelveticaNeue", size: 13,
                     color: hintColor, topY: 350)

    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath
writePNG(render(scale: 1), to: "\(outDir)/dmg-background-1x.png")
writePNG(render(scale: 2), to: "\(outDir)/dmg-background-2x.png")
print("Wrote dmg-background-1x.png and dmg-background-2x.png to \(outDir)")
