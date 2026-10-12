import Foundation
import CoreGraphics

/// Minimal SyncTeX reader for jumping between source lines and PDF positions.
/// Coordinates are PDF points measured from the top-left corner of the page.
final class SyncTeX {
    struct Record {
        let kind: Character
        let tag: Int
        let line: Int
        let page: Int      // 1-based
        let h: Double
        let v: Double
        let width: Double
        let height: Double
        let depth: Double
    }

    private(set) var inputs: [Int: String] = [:]
    private(set) var records: [Record] = []
    private var byPage: [Int: [Record]] = [:]
    private var unit: Double = 1
    private var mag: Double = 1000
    private var xOffset: Double = 0
    private var yOffset: Double = 0

    /// Loads `name.synctex` or `name.synctex.gz` next to the PDF.
    static func load(pdf: URL, root: URL) -> SyncTeX? {
        let base = pdf.deletingPathExtension()
        let plain = base.appendingPathExtension("synctex")
        let gz = URL(fileURLWithPath: base.path + ".synctex.gz")
        var text: String?
        if FileManager.default.fileExists(atPath: plain.path) {
            text = try? String(contentsOf: plain, encoding: .utf8)
                ?? String(contentsOf: plain, encoding: .isoLatin1)
        } else if FileManager.default.fileExists(atPath: gz.path) {
            let r = ProcessRunner.runSync("/usr/bin/gunzip", ["-c", gz.path])
            if r.ok { text = r.stdout }
        }
        guard let text else { return nil }
        let s = SyncTeX()
        s.parse(text, root: root)
        return s.records.isEmpty ? nil : s
    }

    private func toPoints(_ sp: Double) -> Double {
        sp * unit / 65536.0 / 72.27 * 72.0 * (mag / 1000.0)
    }

    func parse(_ text: String, root: URL) {
        var page = 0
        var inContent = false
        let rootPath = root.standardizedFileURL.path
        text.enumerateLines { line, _ in
            guard let first = line.first else { return }
            if !inContent {
                if line.hasPrefix("Input:") {
                    let parts = line.dropFirst(6).split(separator: ":", maxSplits: 1)
                    if parts.count == 2, let tag = Int(parts[0]) {
                        var p = String(parts[1])
                        let std = (p as NSString).standardizingPath
                        if std.hasPrefix(rootPath + "/") { p = String(std.dropFirst(rootPath.count + 1)) }
                        while p.hasPrefix("./") { p.removeFirst(2) }
                        self.inputs[tag] = p
                    }
                } else if line.hasPrefix("Unit:") { self.unit = Double(line.dropFirst(5)) ?? 1 }
                else if line.hasPrefix("Magnification:") { self.mag = Double(line.dropFirst(14)) ?? 1000 }
                else if line.hasPrefix("X Offset:") { self.xOffset = Double(line.dropFirst(9)) ?? 0 }
                else if line.hasPrefix("Y Offset:") { self.yOffset = Double(line.dropFirst(9)) ?? 0 }
                else if line.hasPrefix("Content:") { inContent = true }
                return
            }
            switch first {
            case "{":
                page = Int(line.dropFirst()) ?? page + 1
            case "}":
                break
            case "[", "(", "v", "h", "x", "k", "g", "$":
                if let r = self.parseRecord(line, kind: first, page: page) { self.records.append(r) }
            case "I":
                // Late "Input:" lines can appear inside content.
                if line.hasPrefix("Input:") {
                    let parts = line.dropFirst(6).split(separator: ":", maxSplits: 1)
                    if parts.count == 2, let tag = Int(parts[0]) {
                        var p = String(parts[1])
                        let std = (p as NSString).standardizingPath
                        if std.hasPrefix(rootPath + "/") { p = String(std.dropFirst(rootPath.count + 1)) }
                        while p.hasPrefix("./") { p.removeFirst(2) }
                        self.inputs[tag] = p
                    }
                }
            default:
                break
            }
        }
        for r in records { byPage[r.page, default: []].append(r) }
    }

    private func parseRecord(_ line: String, kind: Character, page: Int) -> Record? {
        // e.g. (1,10:4736286,7133680:25771212,30785692,0   or   x1,12:4736286,7133680
        let body = line.dropFirst()
        let parts = body.split(separator: ":")
        guard parts.count >= 2 else { return nil }
        let tl = parts[0].split(separator: ",")
        let hv = parts[1].split(separator: ",")
        guard tl.count >= 2, hv.count >= 2, let tag = Int(tl[0]), let ln = Int(tl[1]),
              let h = Double(hv[0]), let v = Double(hv[1]) else { return nil }
        var w = 0.0, ht = 0.0, d = 0.0
        if parts.count >= 3 {
            let whd = parts[2].split(separator: ",")
            if whd.count >= 1 { w = Double(whd[0]) ?? 0 }
            if whd.count >= 2 { ht = Double(whd[1]) ?? 0 }
            if whd.count >= 3 { d = Double(whd[2]) ?? 0 }
        }
        return Record(kind: kind, tag: tag, line: ln, page: page,
                      h: toPoints(h + xOffset), v: toPoints(v + yOffset),
                      width: toPoints(w), height: toPoints(ht), depth: toPoints(d))
    }

    // MARK: Queries

    /// Source line → (page index 0-based, rect in top-left page coordinates).
    func forward(file: String, line: Int) -> (page: Int, rect: CGRect)? {
        let tags = inputs.filter { $0.value == file || ($0.value as NSString).standardizingPath == file }.map(\.key)
        guard !tags.isEmpty else { return nil }
        let tagSet = Set(tags)
        let inFile = records.filter { tagSet.contains($0.tag) && $0.line > 0 }
        guard !inFile.isEmpty else { return nil }
        // Exact line, else the closest following line, else the closest preceding one.
        var target = inFile.filter { $0.line == line }
        if target.isEmpty {
            let after = inFile.filter { $0.line > line }.map(\.line).min()
            let before = inFile.filter { $0.line < line }.map(\.line).max()
            if let a = after, a - line <= 8 { target = inFile.filter { $0.line == a } }
            else if let b = before { target = inFile.filter { $0.line == b } }
            else if let a = after { target = inFile.filter { $0.line == a } }
        }
        guard let first = target.first else { return nil }
        let onPage = target.filter { $0.page == first.page }
        var rect = CGRect.null
        for r in onPage {
            if r.kind == "(" || r.kind == "h" {
                rect = rect.union(CGRect(x: r.h, y: r.v - r.height, width: max(r.width, 4), height: max(r.height + r.depth, 4)))
            } else {
                rect = rect.union(CGRect(x: r.h, y: r.v - 9, width: 12, height: 12))
            }
        }
        if rect.isNull { rect = CGRect(x: first.h, y: first.v - 10, width: 40, height: 12) }
        return (first.page - 1, rect)
    }

    /// PDF point (top-left page coordinates, page 0-based) → source file and line.
    func inverse(page: Int, point: CGPoint) -> (file: String, line: Int)? {
        guard let recs = byPage[page + 1], !recs.isEmpty else { return nil }
        // Smallest horizontal box containing the point.
        var best: Record?
        var bestArea = Double.infinity
        for r in recs where r.kind == "(" || r.kind == "h" {
            let rect = CGRect(x: r.h, y: r.v - r.height, width: r.width, height: r.height + r.depth)
            if rect.insetBy(dx: -1, dy: -2).contains(point) {
                let area = Double(rect.width * rect.height)
                if area < bestArea { bestArea = area; best = r }
            }
        }
        if let box = best {
            // Prefer the nearest glyph-level record on the same baseline, to the left of the point.
            let sameLine = recs.filter { ($0.kind == "x" || $0.kind == "k" || $0.kind == "g" || $0.kind == "$")
                && abs($0.v - box.v) < 1.5 && $0.h <= point.x + 1 && $0.line > 0 }
            if let r = sameLine.max(by: { $0.h < $1.h }), let f = inputs[r.tag] { return (f, r.line) }
            if box.line > 0, let f = inputs[box.tag] { return (f, box.line) }
        }
        // Fall back to the nearest record of any kind.
        let nearest = recs.filter { $0.line > 0 }.min { a, b in
            hypot(a.h - point.x, (a.v - point.y) * 2) < hypot(b.h - point.x, (b.v - point.y) * 2)
        }
        if let n = nearest, let f = inputs[n.tag] { return (f, n.line) }
        return nil
    }
}
