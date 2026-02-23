#!/usr/bin/env swift

// App Icon Generator for GigWallet — v4
// Redesigned to match the wallet.bifold.fill SF Symbol used in the app.
//
// Design: Rich orange gradient background (#FF7338 → #E85426)
//         White bifold wallet icon — two overlapping rounded rectangles
//         mimicking the wallet.bifold.fill shape with a card and dollar bill peeking out
//
// The shape closely matches Apple's wallet.bifold.fill SF Symbol
// so the app icon is visually cohesive with the in-app branding.

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let scale = CGFloat(size)

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let context = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: 4 * size,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    print("Failed to create context")
    exit(1)
}

// --- Background: Brand orange gradient ---
let bgColors = [
    CGColor(red: 1.0, green: 0.45, blue: 0.22, alpha: 1.0),    // #FF7338 warm top
    CGColor(red: 0.91, green: 0.33, blue: 0.15, alpha: 1.0)     // #E85426 deep bottom
] as CFArray

guard let bgGradient = CGGradient(
    colorsSpace: colorSpace,
    colors: bgColors,
    locations: [0.0, 1.0]
) else { exit(1) }

context.drawLinearGradient(
    bgGradient,
    start: CGPoint(x: scale * 0.15, y: scale),
    end: CGPoint(x: scale * 0.85, y: 0),
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
)

// --- Subtle warm glow for depth ---
let glowColors = [
    CGColor(red: 1.0, green: 0.65, blue: 0.4, alpha: 0.3),
    CGColor(red: 1.0, green: 0.5, blue: 0.25, alpha: 0.0)
] as CFArray

if let glow = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0.0, 1.0]) {
    context.drawRadialGradient(
        glow,
        startCenter: CGPoint(x: scale * 0.7, y: scale * 0.7),
        startRadius: 0,
        endCenter: CGPoint(x: scale * 0.7, y: scale * 0.7),
        endRadius: scale * 0.45,
        options: []
    )
}

// --- White bifold wallet icon ---
// The wallet.bifold.fill shape is essentially:
// - A back panel (slightly larger rounded rect)
// - A front panel (overlapping rounded rect, offset down-right)
// - A card slot visible in the back panel
// - A small dollar bill peeking out the top

let white = CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
let whiteSubtle = CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.9)

let cx = scale * 0.5
let cy = scale * 0.5

// Back panel of bifold wallet (the one "behind")
let backW = scale * 0.48
let backH = scale * 0.34
let backR = scale * 0.035
let backX = cx - backW / 2 - scale * 0.02
let backY = cy - backH / 2 - scale * 0.03

let backRect = CGRect(x: backX, y: backY, width: backW, height: backH)
let backPath = CGPath(roundedRect: backRect, cornerWidth: backR, cornerHeight: backR, transform: nil)

context.setFillColor(whiteSubtle)
context.addPath(backPath)
context.fillPath()

// Card slot in back panel — a smaller rounded rect in upper portion
let cardW = backW * 0.55
let cardH = backH * 0.28
let cardR = scale * 0.018
let cardX = backX + backW * 0.08
let cardY = backY + backH * 0.14

let cardRect = CGRect(x: cardX, y: cardY, width: cardW, height: cardH)
let cardPath = CGPath(roundedRect: cardRect, cornerWidth: cardR, cornerHeight: cardR, transform: nil)

// Card is a slightly different shade (the orange background shows through)
context.setFillColor(CGColor(red: 1.0, green: 0.5, blue: 0.25, alpha: 0.3))
context.addPath(cardPath)
context.fillPath()

// Second card slot line below
let card2Y = backY + backH * 0.52
let card2Rect = CGRect(x: cardX, y: card2Y, width: cardW * 0.8, height: cardH * 0.6)
let card2Path = CGPath(roundedRect: card2Rect, cornerWidth: cardR, cornerHeight: cardR, transform: nil)

context.setFillColor(CGColor(red: 1.0, green: 0.5, blue: 0.25, alpha: 0.2))
context.addPath(card2Path)
context.fillPath()

// Front panel of bifold wallet (overlaps the back, offset to lower-right)
let frontW = scale * 0.48
let frontH = scale * 0.34
let frontR = scale * 0.035
let frontX = cx - frontW / 2 + scale * 0.02
let frontY = cy - frontH / 2 + scale * 0.03

let frontRect = CGRect(x: frontX, y: frontY, width: frontW, height: frontH)
let frontPath = CGPath(roundedRect: frontRect, cornerWidth: frontR, cornerHeight: frontR, transform: nil)

context.setFillColor(white)
context.addPath(frontPath)
context.fillPath()

// Clasp / snap button on the front panel — a small circle near the right edge
let claspR = scale * 0.025
let claspCX = frontX + frontW - scale * 0.07
let claspCY = frontY + frontH * 0.5
let claspRect = CGRect(x: claspCX - claspR, y: claspCY - claspR, width: claspR * 2, height: claspR * 2)

context.setFillColor(CGColor(red: 1.0, green: 0.5, blue: 0.25, alpha: 0.35))
context.fillEllipse(in: claspRect)

// Inner clasp circle (smaller)
let innerClaspR = claspR * 0.55
let innerClaspRect = CGRect(x: claspCX - innerClaspR, y: claspCY - innerClaspR, width: innerClaspR * 2, height: innerClaspR * 2)
context.setFillColor(CGColor(red: 1.0, green: 0.5, blue: 0.25, alpha: 0.2))
context.fillEllipse(in: innerClaspRect)

// Fold line / spine — the vertical fold between back and front
let foldX = backX + scale * 0.015
context.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.5))
context.setLineWidth(scale * 0.006)
context.move(to: CGPoint(x: foldX, y: backY + backR))
context.addLine(to: CGPoint(x: foldX, y: frontY + frontH - frontR))
context.strokePath()

// Dollar bill peeking out the top of the back panel
let billW = scale * 0.22
let billH = scale * 0.05
let billX = cx - billW / 2 + scale * 0.05
let billY = backY - billH * 0.55
let billR = scale * 0.01

let billColor = CGColor(red: 0.95, green: 1.0, blue: 0.9, alpha: 0.85)
let billRect = CGRect(x: billX, y: billY, width: billW, height: billH)
let billPath = CGPath(roundedRect: billRect, cornerWidth: billR, cornerHeight: billR, transform: nil)

context.setFillColor(billColor)
context.addPath(billPath)
context.fillPath()

// Tiny $ symbol on the bill
let dollarCX = billX + billW * 0.5
let dollarCY = billY + billH * 0.5
let dSize = billH * 0.5

context.setStrokeColor(CGColor(red: 0.3, green: 0.6, blue: 0.3, alpha: 0.4))
context.setLineWidth(scale * 0.004)
context.setLineCap(.round)

// Vertical line of $
context.move(to: CGPoint(x: dollarCX, y: dollarCY - dSize))
context.addLine(to: CGPoint(x: dollarCX, y: dollarCY + dSize))
context.strokePath()

// S-curve (simplified as two small arcs)
context.move(to: CGPoint(x: dollarCX + dSize * 0.5, y: dollarCY - dSize * 0.6))
context.addArc(center: CGPoint(x: dollarCX, y: dollarCY - dSize * 0.3),
               radius: dSize * 0.5, startAngle: -0.3, endAngle: .pi + 0.3, clockwise: true)
context.strokePath()

context.move(to: CGPoint(x: dollarCX - dSize * 0.5, y: dollarCY + dSize * 0.6))
context.addArc(center: CGPoint(x: dollarCX, y: dollarCY + dSize * 0.3),
               radius: dSize * 0.5, startAngle: .pi - 0.3, endAngle: 0.3, clockwise: true)
context.strokePath()

// --- Save as PNG ---
guard let image = context.makeImage() else {
    print("Failed to create image")
    exit(1)
}

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "GigWallet/Assets.xcassets/AppIcon.appiconset/AppIcon_1024.png"

let url = URL(fileURLWithPath: outputPath)

guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    print("Failed to create image destination")
    exit(1)
}

CGImageDestinationAddImage(destination, image, nil)

if CGImageDestinationFinalize(destination) {
    print("✅ App icon v4 saved to: \(outputPath)")
    print("   Size: 1024x1024")
    print("   Design: Orange gradient + white bifold wallet (matches wallet.bifold.fill)")
} else {
    print("❌ Failed to save image")
    exit(1)
}
