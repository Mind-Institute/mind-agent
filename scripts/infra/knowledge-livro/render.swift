import Foundation
import PDFKit
import AppKit
// Usage: render <pdf> <outdir> <page> [page...]  (1-based pages) -> <outdir>/p<page>.png
let a = CommandLine.arguments
let doc = PDFDocument(url: URL(fileURLWithPath: a[1]))!
for s in a.dropFirst(3) {
  let n = Int(s)!
  guard let page = doc.page(at: n - 1) else { continue }
  let box = page.bounds(for: .mediaBox)
  let img = page.thumbnail(of: NSSize(width: box.width * 1.6, height: box.height * 1.6), for: .mediaBox)
  guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else { continue }
  try! png.write(to: URL(fileURLWithPath: "\(a[2])/p\(n).png"))
}
