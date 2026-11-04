import SwiftUI

// MARK: - Keys

enum KeyID: Hashable {
    case hdg, speed, required, up, wind, flight, wtbal, enter, conv, timer, clock, down
    case plusMinus, colon, clear, power
    case d0, d1, d2, d3, d4, d5, d6, d7, d8, d9, dot
    case divide, times, minus, plus, equals

    var digit: Character? {
        switch self {
        case .d0: return "0"; case .d1: return "1"; case .d2: return "2"; case .d3: return "3"
        case .d4: return "4"; case .d5: return "5"; case .d6: return "6"; case .d7: return "7"
        case .d8: return "8"; case .d9: return "9"
        default: return nil
        }
    }
}

// MARK: - LCD model

enum LabelStyle { case normal, star, blink }

struct RowText {
    var text: String
    var negative: Bool = false
}

struct LCDState {
    var on = false
    var rows: [RowText?] = Array(repeating: nil, count: 6)
    var labels: [LabelPos: (text: String, style: LabelStyle)] = [:]
    var menuVisible: Set<String> = []
    var menuActive: String? = nil
    var menuCursor: String? = nil
    var timerLabel = false
    var convArmed = false
    var calc = false
    var toast: String? = nil
}

// MARK: - Entry line

struct Entry {
    var raw = ""
    var negative = false
    var computed: Double? = nil
    var computedHMS = false
    var error = false

    var isEmpty: Bool { raw.isEmpty && computed == nil && !error }
    var isHMS: Bool { computedHMS || (computed == nil && raw.contains(":")) }

    var value: Double? {
        if error { return nil }
        if let c = computed { return c }
        if raw.isEmpty { return nil }
        var v: Double
        if raw.contains(":") {
            let segs = raw.split(separator: ":", omittingEmptySubsequences: false).map { Double($0) ?? 0 }
            v = 0
            let div: [Double] = [1, 60, 3600]
            for (i, s) in segs.prefix(3).enumerated() { v += s / div[i] }
        } else {
            v = Double(raw) ?? 0
        }
        return negative ? -v : v
    }

    var digitCount: Int { raw.filter { $0.isNumber }.count }
}

private enum Op { case add, sub, mul, div }

private enum ClockTarget: Int { case zulu = 0, home, local }

// MARK: - Computer

final class E6BComputer: ObservableObject {
    enum Mode { case off, menu, prompt, result, clock, timer }

    private(set) var mode: Mode = .menu
    private(set) var group: Group? = nil
    private var cursor: FuncDef = Functions.named("FUEL")
    private var fn: FuncDef? = nil
    private var step = 0
    private var vals: [Key: Double] = [:]
    private var failed = false

    private var entry = Entry()
    private var acc: Double? = nil
    private var accHMS = false
    private var pendingOp: Op? = nil
    private var operandFresh = false
    private var convArmed = false
    private var toastShown = false

    // Values the real unit carries from one function to the next.
    private var saved: [Key: Double] = [:]

    // Weight & balance running totals
    private var wbKind: BalanceKind? = nil
    private var wbCount = 0
    private var gw = 0.0, momTotal = 0.0, cg = 0.0, rf = 1.0

    // Clocks
    private var zuluAdjust: TimeInterval = 0
    private var homeOffsetH = 0.0
    private var localOffsetH = 0.0
    private var clockSetting = false
    private var clockTarget: ClockTarget = .zulu

    // Timer
    private var timerSecs = 0.0
    private var timerRunning = false
    private var timerDown = false
    private var timerRef = Date()
    private var timerSetting = false
    private var timerFields = ["", "", ""]
    private var timerFocus = 0

    // MARK: Key handling

    /// Hides the "enter the FROM value" message (any key press or LCD tap).
    func dismissToast() {
        guard toastShown else { return }
        toastShown = false
        objectWillChange.send()
    }

    func press(_ k: KeyID) {
        defer { objectWillChange.send() }
        toastShown = false

        if convArmed {
            convArmed = false
            handleConv(k)
            return
        }

        if mode == .timer && timerSetting && handleTimerEdit(k) { return }

        switch k {
        case .power: break
        case .conv: convArmed = true
        case .clear: handleClear()
        case .d0, .d1, .d2, .d3, .d4, .d5, .d6, .d7, .d8, .d9: typeChar(k.digit!)
        case .dot: typeChar(".")
        case .colon: typeChar(":")
        case .plusMinus: handleSign()
        case .plus: pressOp(.add)
        case .minus: pressOp(.sub)
        case .times: pressOp(.mul)
        case .divide: pressOp(.div)
        case .equals: pressEquals()
        case .enter: handleEnter()
        case .hdg: openGroup(.hdg)
        case .speed: openGroup(.speed)
        case .required: openGroup(.required)
        case .wind: openGroup(.wind)
        case .flight: openGroup(.flight)
        case .wtbal: openGroup(.wtbal)
        case .up: moveCursor(-1)
        case .down: moveCursor(1)
        case .timer: handleTimerKey()
        case .clock: handleClockKey()
        }
    }

    private func resetEntry() {
        entry = Entry()
        acc = nil
        accHMS = false
        pendingOp = nil
        operandFresh = false
    }

    // MARK: Menu

    private func openGroup(_ g: Group) {
        if mode != .menu { leaveFunction() }
        mode = .menu
        let items = Functions.items(in: g)
        if group == g, let i = items.firstIndex(where: { $0.name == cursor.name }) {
            cursor = items[(i + 1) % items.count]
        } else {
            group = g
            cursor = items[0]
        }
    }

    private func moveCursor(_ d: Int) {
        if mode == .clock && clockSetting {
            clockTarget = ClockTarget(rawValue: (clockTarget.rawValue + d + 3) % 3)!
            resetEntry()
            return
        }
        if mode == .prompt || mode == .result || mode == .clock || mode == .timer {
            leaveFunction()
            mode = .menu
        }
        guard mode == .menu else { return }
        let items = Functions.items(in: group)
        let i = items.firstIndex(where: { $0.name == cursor.name }) ?? 0
        cursor = items[(i + d + items.count) % items.count]
    }

    private func leaveFunction() {
        if let f = fn { cursor = f }
        fn = nil
        step = 0
        vals = [:]
        failed = false
        clockSetting = false
        timerSetting = false
        resetEntry()
    }

    // MARK: Function flow

    private func startFunction(_ f: FuncDef) {
        fn = f
        group = f.group
        cursor = f
        vals = [:]
        failed = false
        if let b = f.balance, wbKind != b {
            wbKind = b; wbCount = 0
            gw = 0; momTotal = 0; cg = 0; rf = 1
        }
        step = 0
        mode = .prompt
        beginPrompt()
    }

    private func currentInputs() -> [Field] {
        guard let f = fn else { return [] }
        if f.balance != nil {
            return wbCount == 0 ? f.inputs : Array(f.inputs.prefix(2))
        }
        return f.inputs
    }

    private func beginPrompt() {
        resetEntry()
        let inputs = currentInputs()
        guard step < inputs.count else { return }
        let fld = inputs[step]
        if let f = fn, f.balance == .arm, fld.key == .rf {
            entry.computed = 1
        } else if let s = saved[fld.key], [.gs, .tas, .time, .fph, .cg].contains(fld.key) {
            entry.computed = s
            entry.computedHMS = fld.kind == .time
        }
    }

    private func handleEnter() {
        switch mode {
        case .menu:
            startFunction(cursor)
        case .result:
            vals = [:]
            failed = false
            step = 0
            mode = .prompt
            beginPrompt()
        case .prompt:
            if pendingOp != nil { pressEquals() }
            guard let v = displayedValue() else { return }
            if entry.error { return }
            let inputs = currentInputs()
            vals[inputs[step].key] = v
            step += 1
            if step >= inputs.count {
                finish()
            } else {
                beginPrompt()
            }
        case .clock:
            break
        case .timer:
            if timerSetting { commitTimerSetting() }
        case .off:
            break
        }
    }

    private func finish() {
        guard let f = fn else { return }
        failed = false
        if let b = f.balance {
            let wt = vals[.wt] ?? 0
            if wbCount == 0 { rf = vals[.rf] ?? 1 }
            if rf == 0 { rf = 1 }
            let moment = b == .arm ? wt * (vals[.arm] ?? 0) / rf : (vals[.mom] ?? 0)
            gw += wt
            momTotal += moment
            wbCount += 1
            if gw != 0 { cg = momTotal * rf / gw } else { cg = 0 }
            vals[.mom] = momTotal; vals[.cg] = cg; vals[.gw] = gw; vals[.rf] = rf
            saved[.cg] = cg
        } else if let c = f.compute {
            if let out = c(vals) {
                for (k, v) in out { vals[k] = v }
                for k in [Key.gs, .tas, .time, .fph] { if let v = out[k] { saved[k] = v } }
                if out.values.contains(where: { !$0.isFinite }) { failed = true }
            } else {
                failed = true
            }
        }
        mode = .result
        resetEntry()
    }

    // MARK: Entry editing

    private func typeChar(_ c: Character) {
        guard mode == .menu || mode == .prompt || (mode == .clock && clockSetting)
                || (mode == .timer && timerSetting) else { return }
        if entry.computed != nil || entry.error || (pendingOp != nil && !operandFresh) {
            let keepAcc = pendingOp != nil && !operandFresh
            let a = acc, h = accHMS, op = pendingOp
            entry = Entry()
            if keepAcc { acc = a; accHMS = h; pendingOp = op }
            else { acc = nil; pendingOp = nil }
        }
        if pendingOp != nil { operandFresh = true }

        switch c {
        case ".":
            let lastSeg = entry.raw.split(separator: ":", omittingEmptySubsequences: false).last.map(String.init) ?? ""
            if lastSeg.contains(".") { return }
            if entry.raw.isEmpty || entry.raw.hasSuffix(":") { entry.raw += "0" }
            entry.raw.append(".")
        case ":":
            if entry.raw.filter({ $0 == ":" }).count >= 2 { return }
            if entry.raw.contains(".") { return }
            if entry.raw.isEmpty { entry.raw = "0" }
            entry.raw.append(":")
        default:
            if entry.digitCount >= 6 { return }
            if entry.raw == "0" { entry.raw = "" }  // no leading zeros
            entry.raw.append(c)
        }
    }

    private func handleSign() {
        switch mode {
        case .timer:
            let v = timerValue(at: Date())
            timerSecs = v
            timerRef = Date()
            timerDown.toggle()
            return
        case .menu, .prompt: break
        case .clock where clockSetting: break
        default: return
        }
        if entry.error { return }
        if let c = entry.computed {
            entry.computed = -c
        } else {
            entry.negative.toggle()
        }
    }

    private func handleClear() {
        convArmed = false
        if !entry.isEmpty || pendingOp != nil || acc != nil {
            resetEntry()
            return
        }
        switch mode {
        case .prompt:
            if step > 0 {
                step -= 1
                beginPrompt()
            } else {
                leaveFunction(); mode = .menu
            }
        case .result, .clock, .timer:
            leaveFunction(); mode = .menu
        default:
            break
        }
    }

    // MARK: Calculator

    private func displayedValue() -> Double? {
        if pendingOp != nil && !operandFresh { return acc }
        return entry.value
    }

    private func pressOp(_ op: Op) {
        guard mode == .menu || mode == .prompt || (mode == .clock && clockSetting) else { return }
        if pendingOp != nil && operandFresh {
            guard let l = acc, let r = entry.value else { return }
            applyPending(l, r)
        } else if pendingOp == nil {
            guard let v = entry.value else { return }
            acc = v
            accHMS = entry.isHMS
        } else if pendingOp != nil && acc == nil {
            return
        }
        guard acc != nil || entry.error else { return }
        pendingOp = op
        operandFresh = false
        entry = Entry()
        if acc == nil { entry.error = true; pendingOp = nil }
    }

    private func applyPending(_ l: Double, _ r: Double) {
        guard let op = pendingOp else { return }
        var result: Double
        switch op {
        case .add: result = l + r
        case .sub: result = l - r
        case .mul: result = l * r
        case .div:
            if r == 0 { acc = nil; pendingOp = nil; operandFresh = false; entry = Entry(); entry.error = true; return }
            result = l / r
        }
        accHMS = accHMS || entry.isHMS
        acc = result
    }

    private func pressEquals() {
        guard let op = pendingOp, operandFresh, let l = acc, let r = entry.value else { return }
        _ = op
        applyPending(l, r)
        guard let res = acc else { return }
        let hms = accHMS
        pendingOp = nil; operandFresh = false; acc = nil; accHMS = false
        entry = Entry()
        entry.computed = res
        entry.computedHMS = hms
    }

    // MARK: Conversions

    private static let conversions: [KeyID: (Double) -> (Double, Bool)] = [
        .plusMinus: { ($0 * Calc.mbPerInHg, false) },
        .d7: { ($0 * Calc.nmPerSM, false) },
        .d8: { ($0 / Calc.nmPerSM, false) },
        .d9: { ($0 * Calc.litersPerGal, false) },
        .divide: { ($0 / Calc.litersPerGal, false) },
        .colon: { ($0 / Calc.mbPerInHg, false) },
        .d4: { ($0 * Calc.kmPerNM, false) },
        .d5: { ($0 / Calc.kmPerNM, false) },
        .d6: { ($0, true) },
        .times: { ($0, false) },
        .clear: { (($0 - 32) * 5 / 9, false) },
        .d1: { ($0 * 0.3048, false) },
        .d2: { ($0 / 0.3048, false) },
        .d3: { ($0 * Calc.jetLbPerGal, false) },
        .minus: { ($0 / Calc.jetLbPerGal, false) },
        .power: { ($0 * 9 / 5 + 32, false) },
        .d0: { ($0 * Calc.kgPerLb, false) },
        .dot: { ($0 / Calc.kgPerLb, false) },
        .equals: { ($0 * Calc.avgasLbPerGal, false) },
        .plus: { ($0 / Calc.avgasLbPerGal, false) },
    ]

    private func handleConv(_ k: KeyID) {
        switch k {
        case .clock:
            enterClockSetting()
            return
        case .timer:
            enterTimerSetting()
            return
        default: break
        }
        guard mode == .menu || mode == .prompt else { return }
        guard let conv = Self.conversions[k] else { return }
        guard let v = displayedValue(), !entry.error else {
            toastShown = true
            return
        }
        let (raw, hms) = conv(v)
        // The unit shows conversions to 2 decimals (4 for HMS -> decimal hours).
        let places = k == .times ? 4.0 : 2.0
        let r = (raw * pow(10, places)).rounded() / pow(10, places)
        resetEntry()
        entry.computed = r
        entry.computedHMS = hms
    }

    // MARK: Clock

    private func zuluSeconds(_ now: Date) -> Double {
        let t = now.timeIntervalSince1970 + zuluAdjust
        let d = t.truncatingRemainder(dividingBy: 86400)
        return d < 0 ? d + 86400 : d
    }

    private func clockSeconds(_ t: ClockTarget, _ now: Date) -> Double {
        let z = zuluSeconds(now)
        var s: Double
        switch t {
        case .zulu: s = z
        case .home: s = z + homeOffsetH * 3600
        case .local: s = z + localOffsetH * 3600
        }
        s = s.truncatingRemainder(dividingBy: 86400)
        return s < 0 ? s + 86400 : s
    }

    private func handleClockKey() {
        if mode == .clock && clockSetting {
            commitClock()
            return
        }
        if mode == .prompt || mode == .result { leaveFunction() }
        mode = .clock
        resetEntry()
        clockSetting = false
        timerSetting = false
    }

    private func enterClockSetting() {
        if mode == .prompt || mode == .result { leaveFunction() }
        mode = .clock
        clockSetting = true
        clockTarget = .zulu
        resetEntry()
    }

    private func commitClock() {
        guard let v = displayedValue(), v >= 0 else { clockSetting = false; return }
        let now = Date()
        switch clockTarget {
        case .zulu:
            let target = v.truncatingRemainder(dividingBy: 24) * 3600
            let t = now.timeIntervalSince1970
            let dayStart = (t / 86400).rounded(.down) * 86400
            zuluAdjust = dayStart + target - t
        case .home, .local:
            let z = zuluSeconds(now) / 3600
            var off = (v.rounded() - z.rounded(.down)).truncatingRemainder(dividingBy: 24)
            if off > 12 { off -= 24 }
            if off < -12 { off += 24 }
            if clockTarget == .home { homeOffsetH = off } else { localOffsetH = off }
        }
        clockSetting = false
        resetEntry()
    }

    // MARK: Timer

    private func timerValue(at now: Date) -> Double {
        guard timerRunning else { return timerSecs }
        let e = now.timeIntervalSince(timerRef)
        return timerDown ? timerSecs - e : timerSecs + e
    }

    private func handleTimerKey() {
        // While prompted for TIME, TIMER copies the timer reading into the entry.
        if mode == .prompt, let f = fn, currentInputs()[step].kind == .time, f.balance == nil {
            let secs = abs(timerValue(at: Date()))
            resetEntry()
            entry.computed = secs / 3600
            entry.computedHMS = true
            return
        }
        if mode != .timer {
            if mode == .prompt || mode == .result { leaveFunction() }
            mode = .timer
            resetEntry()
            timerSetting = false
            return
        }
        if timerSetting {
            commitTimerSetting()
            return
        }
        let now = Date()
        timerSecs = timerValue(at: now)
        timerRef = now
        timerRunning.toggle()
    }

    /// Keys while the timer is being edited (hh blinking, : moves to the next
    /// field, ENTER starts the countdown). Returns true when the key was used.
    private func handleTimerEdit(_ k: KeyID) -> Bool {
        switch k {
        case .d0, .d1, .d2, .d3, .d4, .d5, .d6, .d7, .d8, .d9:
            if timerFields[timerFocus].count < 2 { timerFields[timerFocus].append(k.digit!) }
            return true
        case .colon:
            timerFocus = min(2, timerFocus + 1)
            return true
        case .clear:
            if timerFields[timerFocus].isEmpty {
                timerFocus = max(0, timerFocus - 1)
            } else {
                timerFields[timerFocus] = ""
            }
            return true
        case .plusMinus:
            timerDown.toggle()
            return true
        case .enter, .timer:
            commitTimerSetting()
            return true
        case .dot, .plus, .minus, .times, .divide, .equals:
            return true
        default:
            return false
        }
    }

    /// Stores the entered hh:mm:ss and starts it running immediately.
    private func commitTimerSetting() {
        let n = timerFields.map { Double($0) ?? 0 }
        let secs = n[0] * 3600 + n[1] * 60 + n[2]
        timerSecs = secs
        if secs == 0 { timerDown = false }
        timerRef = Date()
        timerRunning = true
        timerSetting = false
        timerFields = ["", "", ""]
        timerFocus = 0
        resetEntry()
    }

    private func enterTimerSetting() {
        // After LEG TIME (or any TIME result) CONV TIMER starts a countdown from it.
        if mode == .result, let t = vals[.time], fn?.outputs.contains(where: { $0.key == .time }) == true {
            leaveFunction()
            mode = .timer
            timerSecs = t * 3600
            timerDown = true
            timerRef = Date()
            timerRunning = true
            timerSetting = false
            return
        }
        if mode == .prompt || mode == .result { leaveFunction() }
        mode = .timer
        resetEntry()
        timerSecs = 0
        timerRunning = false
        timerDown = true
        timerFields = ["", "", ""]
        timerFocus = 0
        timerSetting = true
    }

    // MARK: - LCD rendering

    func lcd(at now: Date = Date()) -> LCDState {
        var s = LCDState()
        guard mode != .off else { return s }
        s.on = true
        s.convArmed = convArmed
        if toastShown { s.toast = "Enter the FROM value first,\nTHEN press CONV + the tool" }

        func set(_ p: LabelPos, _ text: String, _ style: LabelStyle) {
            s.labels[p] = (text, style)
        }

        switch mode {
        case .off:
            break

        case .menu:
            let items = Functions.items(in: group)
            s.menuVisible = Set(items.map(\.name))
            s.menuCursor = cursor.name
            let (text, neg) = entryText()
            if !entry.isEmpty || acc != nil {
                s.rows[0] = RowText(text: text, negative: neg)
                s.calc = true
            }

        case .prompt, .result:
            guard let f = fn else { break }
            s.menuVisible = Set(Functions.all.map(\.name))
            s.menuActive = f.name
            let inputs = (mode == .result && f.balance == nil) ? f.inputs : currentInputs()
            let showTotals = f.balance != nil && wbCount > 0

            for (i, fld) in inputs.enumerated() {
                if mode == .prompt && i == step {
                    let (t, n) = entryText()
                    putRow(&s, fld, t, n)
                    set(fld.pos, fld.text, .blink)
                } else if i < step || mode == .result {
                    guard let v = vals[fld.key] else { continue }
                    if f.balance != nil && showTotals && fld.key == .mom { continue }
                    let (t, n) = format(v, fld, input: true)
                    putRow(&s, fld, t, n)
                    set(fld.pos, fld.text, .normal)
                }
            }

            if f.balance != nil {
                if showTotals {
                    let rfShown = wbCount > 0
                    put(&s, row: 5, text: Fmt.number(rf, decimals: 4))
                    if rfShown { set(LabelTable.pos(row: 5, label: "RF"), "RF", .normal) }
                    put(&s, row: 3, text: Fmt.number(momTotal, decimals: 2))
                    set(LabelTable.pos(row: 3, label: "MOM"), "MOM", .star)
                    put(&s, row: 4, text: Fmt.number(cg, decimals: 2))
                    set(LabelTable.pos(row: 4, label: "CG"), "CG", .star)
                    put(&s, row: 6, text: Fmt.number(gw, decimals: 2))
                    set(LabelTable.pos(row: 6, label: "GW"), "GW", .star)
                }
            } else if mode == .result {
                for fld in f.outputs {
                    if failed {
                        putRow(&s, fld, "Error", false)
                    } else if let v = vals[fld.key] {
                        let (t, n) = format(v, fld, input: false)
                        putRow(&s, fld, t, n)
                    }
                    set(fld.pos, fld.text, .star)
                    if let p2 = fld.pos2, let l2 = fld.label2 { set(p2, l2, .star) }
                }
            }

        case .clock:
            s.menuVisible = Set(Functions.all.map(\.name))
            let targets: [(ClockTarget, Int, String)] = [(.zulu, 2, "ZULU"), (.home, 3, "HOME"), (.local, 6, "LOCAL")]
            for (t, row, name) in targets {
                let pos = LabelTable.pos(row: row, label: name)
                if clockSetting && clockTarget == t {
                    if entry.isEmpty {
                        let (txt, _) = Fmt.hms(hours: clockSeconds(t, now) / 3600)
                        s.rows[row - 1] = RowText(text: txt)
                    } else {
                        let (txt, n) = entryText()
                        s.rows[row - 1] = RowText(text: txt, negative: n)
                    }
                    set(pos, name, .blink)
                } else {
                    let (txt, _) = Fmt.hms(hours: clockSeconds(t, now) / 3600)
                    s.rows[row - 1] = RowText(text: txt)
                    set(pos, name, .normal)
                }
            }

        case .timer:
            s.menuVisible = Set(Functions.all.map(\.name))
            s.timerLabel = true
            let pos = LabelTable.pos(row: 3, label: "TIME")
            if timerSetting {
                let blinkOn = now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.0) < 0.6
                let parts: [String] = (0..<3).map { i in
                    if i == timerFocus && !blinkOn { return "  " }
                    return String(repeating: "0", count: 2 - timerFields[i].count) + timerFields[i]
                }
                s.rows[2] = RowText(text: parts.joined(separator: ":"), negative: false)
                set(pos, "TIME", .normal)
            } else {
                let v = timerValue(at: now)
                let total = Int(abs(v).rounded(.down))
                s.rows[2] = RowText(text: Fmt.hmsString(total), negative: v < 0 && total >= 0 && v <= -0.0001)
                set(pos, "TIME", .normal)
            }
        }
        return s
    }

    private func put(_ s: inout LCDState, row: Int, text: (text: String, negative: Bool)) {
        s.rows[row - 1] = RowText(text: text.text, negative: text.negative)
    }

    private func format(_ v: Double, _ fld: Field, input: Bool) -> (String, Bool) {
        if fld.kind == .time {
            let r = Fmt.hms(hours: v)
            return (r.text, r.negative)
        }
        let r = Fmt.number(v, decimals: input ? 6 : fld.dec)
        return (r.text, r.negative)
    }

    /// Places text in a row, merging "left" and "right" parts that share a row.
    private func putRow(_ s: inout LCDState, _ fld: Field, _ text: String, _ neg: Bool) {
        let idx = fld.row - 1
        switch fld.part {
        case .full:
            s.rows[idx] = RowText(text: text, negative: neg)
        case .left:
            let right = s.rows[idx]?.text ?? ""
            s.rows[idx] = RowText(text: mergeRow(left: text, right: right), negative: s.rows[idx]?.negative ?? false)
        case .right:
            let left = s.rows[idx]?.text ?? ""
            s.rows[idx] = RowText(text: mergeRow(left: left, right: text), negative: neg)
        }
    }

    private func mergeRow(left: String, right: String) -> String {
        if right.isEmpty { return left }
        if left.isEmpty { return right }
        let left = left.hasSuffix(".") ? String(left.dropLast()) : left
        let ld = left.filter { $0 != "." }.count
        let rd = right.filter { $0 != "." }.count
        let gap = max(1, 6 - ld - rd)
        return left + String(repeating: " ", count: gap) + right
    }

    /// Current entry line as LCD text.
    private func entryText() -> (String, Bool) {
        if entry.error { return ("Error", false) }
        if pendingOp != nil && !operandFresh, let a = acc {
            if accHMS { let r = Fmt.hms(hours: a); return (r.text, r.negative) }
            let r = Fmt.number(a, decimals: 6)
            return (r.text, r.negative)
        }
        if let c = entry.computed {
            if entry.computedHMS { let r = Fmt.hms(hours: c); return (r.text, r.negative) }
            let r = Fmt.number(c, decimals: 6)
            return (r.text, r.negative)
        }
        if entry.raw.isEmpty { return ("0.", entry.negative) }
        if entry.raw.contains(":") {
            var segs = entry.raw.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            for i in 0..<(segs.count - 1) where segs[i].isEmpty { segs[i] = "0" }
            return (segs.joined(separator: ":"), entry.negative)
        }
        return (entry.raw.contains(".") ? entry.raw : entry.raw + ".", entry.negative)
    }
}
