import SwiftUI

/// The liquid-crystal display: six rows of seven-segment digits surrounded by
/// printed labels, with the function menu along the bottom.
struct LCDView: View {
    @ObservedObject var computer: E6BComputer

    static let size = CGSize(width: 310, height: 306)

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1)) { timeline in
            let state = computer.lcd(at: timeline.date)
            let blink = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.0) < 0.6
            Canvas { ctx, size in
                LCDPainter(state: state, blinkOn: blink).paint(&ctx, size)
            }
            .frame(width: Self.size.width, height: Self.size.height)
        }
    }
}

// MARK: - Painter

private struct LCDPainter {
    let state: LCDState
    let blinkOn: Bool

    // Layout
    let rowPitch: CGFloat = 36
    let firstRowY: CGFloat = 22
    let cellW: CGFloat = 19
    let cellH: CGFloat = 29
    let cellGap: CGFloat = 3.5
    let digitsRight: CGFloat = 208
    let labelX: [CGFloat] = [2, 44, 218, 308]
    let menuTop: CGFloat = 233
    let menuPitch: CGFloat = 11
    let menuCenters: [CGFloat] = [34, 101, 164, 226, 278]

    var ink: Color { Color(red: 0.08, green: 0.09, blue: 0.08) }

    static let menuLayout: [(String, Int, Int)] = Functions.all.map { ($0.name, $0.col, $0.line) }

    func paint(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let ghost = ink.opacity(state.on ? 0.075 : 0.045)

        // Ghost segments (always faintly visible, like a real LCD)
        for r in 0..<6 {
            for c in 0..<6 {
                drawCell(&ctx, char: "8", row: r, index: c, color: ghost)
            }
        }

        guard state.on else { return }

        // Digit rows
        for r in 0..<6 {
            guard let row = state.rows[r] else { continue }
            drawRow(&ctx, row: r, text: row.text, negative: row.negative)
        }

        // Row labels
        for (pos, label) in state.labels {
            if label.style == .blink && !blinkOn { continue }
            guard !label.text.isEmpty else { continue }
            let text = label.style == .star ? "*\(label.text)*" : label.text
            let cy = firstRowY + CGFloat(pos.row) * rowPitch + (pos.line == 0 ? -7.5 : 7.5)
            let font = Font.system(size: 7.4, weight: label.style == .normal ? .medium : .bold, design: .default)
            let t = Text(text).font(font).foregroundColor(ink.opacity(0.92))
            let anchor: UnitPoint = pos.col == 3 ? .trailing : .leading
            ctx.draw(t, at: CGPoint(x: labelX[pos.col], y: cy), anchor: anchor)
        }

        drawMenu(&ctx)

        if state.convArmed {
            let badge = CGRect(x: 0, y: 0, width: 62, height: 16)
            ctx.fill(Path(roundedRect: badge, cornerRadius: 3), with: .color(ink))
            ctx.draw(Text("CONV").font(.system(size: 11, weight: .heavy))
                        .foregroundColor(Color(red: 0.69, green: 0.72, blue: 0.67)),
                     at: CGPoint(x: 31, y: 8.5), anchor: .center)
        }
        if let toast = state.toast {
            let box = CGRect(x: 8, y: 96, width: 294, height: 70)
            ctx.fill(Path(roundedRect: box, cornerRadius: 6), with: .color(ink))
            for (i, line) in toast.components(separatedBy: "\n").enumerated() {
                ctx.draw(Text(line).font(.system(size: 13, weight: .bold))
                            .foregroundColor(Color(red: 0.69, green: 0.72, blue: 0.67)),
                         at: CGPoint(x: box.midX, y: box.midY + (i == 0 ? -10 : 10)), anchor: .center)
            }
        }
        if state.calc {
            ctx.draw(Text("CALC").font(.system(size: 7.4, weight: .bold)).foregroundColor(ink),
                     at: CGPoint(x: 308, y: 4), anchor: .trailing)
        }
    }

    // MARK: Menu

    func drawMenu(_ ctx: inout GraphicsContext) {
        let all = state.menuVisible.count >= Functions.all.count
        for (name, col, line) in Self.menuLayout {
            let blinkedOut = name == state.menuCursor && !blinkOn
            let dimmed = blinkedOut || !(state.menuVisible.contains(name) || name == state.menuActive)
            let active = name == state.menuActive
            let text = active ? "*\(name)*" : name
            let font = Font.system(size: 7.6, weight: active || name == state.menuCursor ? .bold : .medium)
            ctx.draw(Text(text).font(font).foregroundColor(ink.opacity(dimmed ? 0.22 : 0.92)),
                     at: CGPoint(x: menuCenters[col], y: menuTop + CGFloat(line) * menuPitch + 5),
                     anchor: .center)
        }
        let timerDim = !all && !state.timerLabel
        do {
            let text = state.timerLabel ? "*TIMER*" : "TIMER"
            ctx.draw(Text(text).font(.system(size: 7.6, weight: state.timerLabel ? .bold : .medium))
                        .foregroundColor(ink.opacity(timerDim ? 0.22 : 0.92)),
                     at: CGPoint(x: menuCenters[4], y: menuTop + 5), anchor: .center)
        }
    }

    // MARK: Digits

    struct Cell { var char: Character; var dot = false; var colon = false }

    func parse(_ text: String) -> [Cell] {
        var cells: [Cell] = []
        for ch in text {
            if ch == "." { if !cells.isEmpty { cells[cells.count - 1].dot = true }; continue }
            if ch == ":" { if !cells.isEmpty { cells[cells.count - 1].colon = true }; continue }
            cells.append(Cell(char: ch))
        }
        return cells
    }

    func drawRow(_ ctx: inout GraphicsContext, row: Int, text: String, negative: Bool) {
        var cells = parse(text)
        if cells.count > 6 { cells = Array(cells.suffix(6)) }
        let start = 6 - cells.count
        for (i, cell) in cells.enumerated() {
            let idx = start + i
            drawCell(&ctx, char: cell.char, row: row, index: idx, color: ink)
            let x = cellX(idx), y = cellY(row)
            if cell.dot {
                let r = CGRect(x: x + cellW + 0.2, y: y + cellH - 3.4, width: 3, height: 3.4)
                ctx.fill(Path(r), with: .color(ink))
            }
            if cell.colon {
                let cx = x + cellW + cellGap / 2 + 0.6
                for dy in [cellH * 0.30, cellH * 0.70] {
                    ctx.fill(Path(CGRect(x: cx - 1.5, y: y + dy - 1.5, width: 3, height: 3)), with: .color(ink))
                }
            }
        }
        if negative {
            let x = digitsRight + 3.5, y = cellY(row) + 3
            ctx.fill(Path(CGRect(x: x, y: y, width: 6, height: 2.2)), with: .color(ink))
        }
    }

    func cellX(_ idx: Int) -> CGFloat {
        let total = 6 * cellW + 5 * cellGap
        return digitsRight - total + CGFloat(idx) * (cellW + cellGap)
    }

    func cellY(_ row: Int) -> CGFloat { firstRowY + CGFloat(row) * rowPitch - cellH / 2 }

    func drawCell(_ ctx: inout GraphicsContext, char: Character, row: Int, index: Int, color: Color) {
        let segs = Self.segments(for: char)
        guard !segs.isEmpty else { return }
        let x = cellX(index), y = cellY(row)
        let t: CGFloat = 3.3   // segment thickness
        let w = cellW, h = cellH
        let lean: CGFloat = 0.11
        let midY = h / 2

        func pt(_ px: CGFloat, _ py: CGFloat) -> CGPoint {
            CGPoint(x: x + px + (h - py) * lean - h * lean / 2, y: y + py)
        }
        func horiz(_ cy: CGFloat) -> Path {
            var p = Path()
            let l = t * 0.55, r = w - t * 0.55
            p.move(to: pt(l, cy)); p.addLine(to: pt(l + t * 0.6, cy - t / 2))
            p.addLine(to: pt(r - t * 0.6, cy - t / 2)); p.addLine(to: pt(r, cy))
            p.addLine(to: pt(r - t * 0.6, cy + t / 2)); p.addLine(to: pt(l + t * 0.6, cy + t / 2))
            p.closeSubpath()
            return p
        }
        func vert(_ cx: CGFloat, _ y0: CGFloat, _ y1: CGFloat) -> Path {
            var p = Path()
            p.move(to: pt(cx, y0)); p.addLine(to: pt(cx + t / 2, y0 + t * 0.6))
            p.addLine(to: pt(cx + t / 2, y1 - t * 0.6)); p.addLine(to: pt(cx, y1))
            p.addLine(to: pt(cx - t / 2, y1 - t * 0.6)); p.addLine(to: pt(cx - t / 2, y0 + t * 0.6))
            p.closeSubpath()
            return p
        }
        let inset: CGFloat = t * 0.5
        let paths: [Character: Path] = [
            "a": horiz(inset),
            "g": horiz(midY),
            "d": horiz(h - inset),
            "f": vert(inset, inset + 1, midY - 1),
            "b": vert(w - inset, inset + 1, midY - 1),
            "e": vert(inset, midY + 1, h - inset - 1),
            "c": vert(w - inset, midY + 1, h - inset - 1),
        ]
        for s in segs { if let p = paths[s] { ctx.fill(p, with: .color(color)) } }
    }

    static func segments(for c: Character) -> [Character] {
        switch c {
        case "0": return Array("abcdef")
        case "1": return Array("bc")
        case "2": return Array("abged")
        case "3": return Array("abgcd")
        case "4": return Array("fgbc")
        case "5": return Array("afgcd")
        case "6": return Array("afgedc")
        case "7": return Array("abc")
        case "8": return Array("abcdefg")
        case "9": return Array("abcdfg")
        case "-": return Array("g")
        case "E": return Array("adefg")
        case "r": return Array("eg")
        case "o": return Array("cdeg")
        default: return []
        }
    }
}
