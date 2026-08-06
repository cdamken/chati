//==============================================================================
// ocr_vision.swift — Apple Vision OCR helper for chati/docr
//==============================================================================
// A tiny, self-contained CLI that runs macOS's native Vision text recognition
// (the same engine as Live Text). Reads images (incl. HEIC/WEBP/AVIF) and PDFs
// directly — no ImageMagick conversion, no Python — and prints the recognized
// text to stdout, errors to stderr. On real-world photos (angle, glare, low
// light) it vastly outperforms tesseract, and it reads HEIC natively.
//
// Build (once):   swiftc -O ocr_vision.swift -o ocrvision
// Use:            ocrvision <file> [lang ...]      e.g. ocrvision scan.heic es-ES en-US
//==============================================================================
import Vision
import AppKit
import PDFKit
import Foundation

func errOut(_ s: String) {
    FileHandle.standardError.write((s + "\n").data(using: .utf8)!)
}

// Recognize text in one CGImage and print each line to stdout. Vision's
// perform() runs the completion handler synchronously, so prints land in order.
func recognize(_ cg: CGImage, _ languages: [String]) {
    let request = VNRecognizeTextRequest { (req, _) in
        guard let obs = req.results as? [VNRecognizedTextObservation] else { return }
        for o in obs {
            if let top = o.topCandidates(1).first { print(top.string) }
        }
    }
    request.recognitionLevel = .accurate       // best quality (vs .fast)
    request.usesLanguageCorrection = true
    if !languages.isEmpty { request.recognitionLanguages = languages }
    do {
        try VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])
    } catch {
        errOut("error: recognition failed: \(error)")
    }
}

let args = CommandLine.arguments
guard args.count > 1 else {
    errOut("usage: ocrvision <file> [lang ...]   (e.g. ocrvision scan.heic es-ES en-US)")
    exit(2)
}
let path = args[1]
let languages = Array(args.dropFirst(2))
let url = URL(fileURLWithPath: path)

guard FileManager.default.fileExists(atPath: path) else {
    errOut("error: file not found: \(path)")
    exit(1)
}

if url.pathExtension.lowercased() == "pdf" {
    // Render each page to a bitmap, then OCR it. Covers scanned/image-only PDFs;
    // for digital PDFs the caller should prefer pdftotext (instant + exact).
    guard let doc = PDFDocument(url: url) else {
        errOut("error: cannot open PDF: \(path)")
        exit(1)
    }
    let scale: CGFloat = 2.5   // ~180 dpi from the 72pt/inch base — good for OCR
    for i in 0 ..< doc.pageCount {
        guard let page = doc.page(at: i) else { continue }
        let bounds = page.bounds(for: .mediaBox)
        let w = Int(bounds.width * scale), h = Int(bounds.height * scale)
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { continue }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: ctx)
        if doc.pageCount > 1 { print("=== page \(i + 1) ===") }
        if let cg = ctx.makeImage() { recognize(cg, languages) }
    }
} else {
    // Any image format AppKit can decode: PNG/JPG/TIFF/BMP/GIF/WEBP/HEIC/AVIF…
    guard let image = NSImage(contentsOf: url),
          let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        errOut("error: cannot load image: \(path)")
        exit(1)
    }
    recognize(cg, languages)
}
