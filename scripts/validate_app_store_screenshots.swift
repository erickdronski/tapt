#!/usr/bin/env swift

import AppKit
import Foundation
import Vision

let expectedPhrases: [String: [String]] = [
    "01-home.png": ["Explore", "Scan a beer"],
    "02-beer-detail.png": ["Guinness Draught"],
    "03-catalog.png": ["Catalog", "Sierra Nevada"],
    "04-beer-radar.png": ["Tapt beer radar", "beer spots"],
    "05-discover.png": ["Discover", "Tapt Dispatch"],
    "06-games.png": ["Games", "Beer Pong", "Flip Cup"],
]
let forbiddenPhrases = [
    "details unavailable",
    "could not refresh",
    "radar could not refresh",
    "try again",
]

let paths = Array(CommandLine.arguments.dropFirst())
guard paths.count == expectedPhrases.count else {
    fputs("Expected \(expectedPhrases.count) screenshots, received \(paths.count).\n", stderr)
    exit(1)
}

func averageLuminance(_ bitmap: NSBitmapImageRep, rows: Range<Int>) -> Double {
    var total = 0.0
    var samples = 0
    for y in stride(from: rows.lowerBound, to: rows.upperBound, by: 12) {
        for x in stride(from: 0, to: bitmap.pixelsWide, by: 12) {
            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
            total += 0.2126 * color.redComponent
                + 0.7152 * color.greenComponent
                + 0.0722 * color.blueComponent
            samples += 1
        }
    }
    return samples == 0 ? 0 : total / Double(samples)
}

var failed = false
for path in paths.sorted() {
    let name = URL(fileURLWithPath: path).lastPathComponent
    guard let expected = expectedPhrases[name] else {
        fputs("Unexpected screenshot: \(name)\n", stderr)
        failed = true
        continue
    }
    guard let image = NSImage(contentsOfFile: path) else {
        fputs("Could not load \(name).\n", stderr)
        failed = true
        continue
    }

    var proposedRect = NSRect(origin: .zero, size: image.size)
    guard let cgImage = image.cgImage(
        forProposedRect: &proposedRect,
        context: nil,
        hints: nil
    ) else {
        fputs("Could not decode \(name).\n", stderr)
        failed = true
        continue
    }
    guard cgImage.width == 1320, cgImage.height == 2868 else {
        fputs("\(name) is \(cgImage.width)x\(cgImage.height), expected 1320x2868.\n", stderr)
        failed = true
        continue
    }

    // Sheets can expose an unpainted host window above the rounded presentation.
    // Check both bitmap edges because AppKit's row orientation is format-dependent.
    let bitmap = NSBitmapImageRep(cgImage: cgImage)
    let edgeRows = 160
    let firstEdge = averageLuminance(bitmap, rows: 0..<edgeRows)
    let lastEdge = averageLuminance(
        bitmap,
        rows: (bitmap.pixelsHigh - edgeRows)..<bitmap.pixelsHigh
    )
    if min(firstEdge, lastEdge) < 0.04 {
        fputs("\(name) has a nearly black edge band; the status bar or host background may be unreadable.\n", stderr)
        failed = true
    }

    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    do {
        try VNImageRequestHandler(cgImage: cgImage).perform([request])
    } catch {
        fputs("Text recognition failed for \(name): \(error.localizedDescription)\n", stderr)
        failed = true
        continue
    }

    let text = (request.results ?? [])
        .compactMap { $0.topCandidates(1).first?.string }
        .joined(separator: "\n")
        .lowercased()

    for phrase in expected where !text.contains(phrase.lowercased()) {
        fputs("\(name) is missing required text: \(phrase)\n", stderr)
        failed = true
    }
    for phrase in forbiddenPhrases where text.contains(phrase) {
        fputs("\(name) contains release-blocking text: \(phrase)\n", stderr)
        failed = true
    }

    if !failed {
        print("Validated \(name)")
    }
}

exit(failed ? 1 : 0)
