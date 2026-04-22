// vision_ocr.swift — Apple Vision OCR for markitdown-automator (Tier 2)
// Compiled to a binary by setup.sh. Takes a single file path argument,
// writes recognized text as Markdown to stdout.
//
// Supported input types:
//   PDF  — each page rendered at 150 DPI via PDFKit, OCR'd via Vision
//   Images — JPEG, PNG, GIF (first frame), TIFF, HEIC, WebP, BMP via CGImageSource
//
// Exit codes: 0 = at least one page/image succeeded, 1 = all failed or bad input

import Foundation
import Vision
import PDFKit
import AppKit

// ── CLI argument validation ───────────────────────────────────────────────────

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: vision_ocr <path-to-pdf-or-image>\n", stderr)
    exit(1)
}

let inputPath = CommandLine.arguments[1]
let fileURL = URL(fileURLWithPath: inputPath)

guard FileManager.default.fileExists(atPath: inputPath) else {
    fputs("Error: file not found: \(inputPath)\n", stderr)
    exit(1)
}

// ── OCR a single CGImage → recognized text string ────────────────────────────
// VNImageRequestHandler.perform() is synchronous: the completion handler is
// called before perform() returns, so no DispatchSemaphore is needed.

func ocrCGImage(_ cgImage: CGImage) -> String {
    var recognizedText = ""
    let request = VNRecognizeTextRequest { req, _ in
        recognizedText = (req.results as? [VNRecognizedTextObservation])?
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n") ?? ""
    }
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    try? handler.perform([request])
    return recognizedText
}

// ── PDF: render each page at 150 DPI, OCR, print with --- separators ─────────

func processPDF(url: URL) -> Int32 {
    guard let pdfDoc = PDFDocument(url: url), pdfDoc.pageCount > 0 else {
        fputs("Error: could not open PDF: \(url.path)\n", stderr)
        return 1
    }

    // PDFKit uses 72 pt/inch; scale to 150 DPI for good OCR quality
    let scale: CGFloat = 150.0 / 72.0
    var anySuccess = false

    for i in 0..<pdfDoc.pageCount {
        guard let page = pdfDoc.page(at: i) else {
            fputs("<!-- OCR failed for page \(i + 1): could not load page -->\n", stderr)
            print("<!-- OCR failed for page \(i + 1): could not load page -->")
            continue
        }

        let bounds = page.bounds(for: .mediaBox)
        let renderSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let nsImage = page.thumbnail(of: renderSize, for: .mediaBox)

        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            fputs("<!-- OCR failed for page \(i + 1): could not render to CGImage -->\n", stderr)
            print("<!-- OCR failed for page \(i + 1): could not render to CGImage -->")
            continue
        }

        if i > 0 { print("\n\n---\n") }
        let text = ocrCGImage(cgImage)
        print(text)
        anySuccess = true
    }

    return anySuccess ? 0 : 1
}

// ── Image: load via CGImageSource (handles GIF frame 0 automatically) ─────────

func processImage(url: URL) -> Int32 {
    guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
        fputs("Error: could not load image: \(url.path)\n", stderr)
        return 1
    }

    let text = ocrCGImage(cgImage)
    print(text)
    return 0
}

// ── Dispatch by file extension ────────────────────────────────────────────────

let ext = fileURL.pathExtension.lowercased()

let exitCode: Int32
switch ext {
case "pdf":
    exitCode = processPDF(url: fileURL)
case "jpg", "jpeg", "png", "gif", "tiff", "tif", "heic", "heif", "webp", "bmp":
    exitCode = processImage(url: fileURL)
default:
    fputs("Error: unsupported file type: .\(ext)\n", stderr)
    fputs("Supported: pdf, jpg, jpeg, png, gif, tiff, tif, heic, heif, webp, bmp\n", stderr)
    exitCode = 1
}

exit(exitCode)
