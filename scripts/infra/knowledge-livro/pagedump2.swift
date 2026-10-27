import Foundation
import PDFKit
// Usage: pagedump2 <pdf> <out.jsonl>
// One JSON line per page: {"page":n,"lines":[{"r":[["text",size],...],"y":top}]}
// Runs are consecutive characters sharing the same font size (rounded to 0.1pt).
// y = top of the line's first character bounds (PDF coordinates, larger = higher on page).
let args = CommandLine.arguments
guard args.count >= 3, let doc = PDFDocument(url: URL(fileURLWithPath: args[1])) else { print("usage/open error"); exit(1) }
FileManager.default.createFile(atPath: args[2], contents: nil)
let fh = FileHandle(forWritingAtPath: args[2])!
for i in 0..<doc.pageCount {
  guard let page = doc.page(at: i) else { continue }
  guard let attr = page.attributedString else { let e = try! JSONSerialization.data(withJSONObject: ["page": i + 1, "lines": [] as [Any]]); fh.write(e); fh.write("\n".data(using: .utf8)!); continue }
  let ns = attr.string as NSString
  var lines: [[String: Any]] = []
  var loc = 0
  while loc < ns.length {
    var end = 0, contentsEnd = 0
    ns.getLineStart(nil, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: loc, length: 0))
    var runs: [[Any]] = []
    var cur = "", curSize = -1.0
    var y = 0.0, x = -1.0, xr = 0.0
    var k = loc
    while k < contentsEnd {
      let r = ns.rangeOfComposedCharacterSequence(at: k)
      let ch = ns.substring(with: r)
      var size = curSize < 0 ? 0.0 : curSize
      if let f = attr.attribute(.font, at: k, effectiveRange: nil) as? NSFont { size = (Double(f.pointSize) * 10).rounded() / 10 }
      if ch.trimmingCharacters(in: .whitespaces).isEmpty && curSize >= 0 { size = curSize } // spaces keep current run
      if !ch.trimmingCharacters(in: .whitespaces).isEmpty {
        let b = page.characterBounds(at: k)
        if x < 0 { x = Double(b.minX); y = Double(b.maxY) }
        xr = max(xr, Double(b.maxX))
      }
      if size != curSize && !cur.isEmpty { runs.append([cur, curSize]); cur = "" }
      cur += ch; curSize = size
      k = r.location + r.length
    }
    if !cur.isEmpty { runs.append([cur, curSize]) }
    lines.append(["r": runs, "y": (y * 10).rounded() / 10, "x": (x * 10).rounded() / 10, "xr": (xr * 10).rounded() / 10])
    loc = end
  }
  let data = try! JSONSerialization.data(withJSONObject: ["page": i + 1, "lines": lines])
  fh.write(data); fh.write("\n".data(using: .utf8)!)
}
fh.closeFile()
print("pages", doc.pageCount)
