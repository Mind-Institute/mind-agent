import Foundation
import PDFKit
// Prints the PDF outline (bookmarks) with depth and 1-based page index, then page count.
for path in CommandLine.arguments.dropFirst() {
  guard let doc = PDFDocument(url: URL(fileURLWithPath: path)) else { print("ERR open", path); continue }
  print("## \((path as NSString).lastPathComponent) pages=\(doc.pageCount)")
  func walk(_ o: PDFOutline, _ depth: Int) {
    for i in 0..<o.numberOfChildren {
      guard let c = o.child(at: i) else { continue }
      var p = -1
      if let d = c.destination, let pg = d.page { p = doc.index(for: pg) + 1 }
      print(String(repeating: "  ", count: depth) + "- [\(p)] " + (c.label ?? ""))
      walk(c, depth + 1)
    }
  }
  if let root = doc.outlineRoot { walk(root, 0) } else { print("  (no outline)") }
}
