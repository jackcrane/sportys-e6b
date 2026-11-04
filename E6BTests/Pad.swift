import XCTest
@testable import E6B

/// Drives an `E6BComputer` through its keypad exactly like a user would, and
/// reads back what the LCD shows.
final class Pad {
    let c = E6BComputer()

    private static let groupKey: [Group: KeyID] = [
        .hdg: .hdg, .speed: .speed, .required: .required,
        .wind: .wind, .flight: .flight, .wtbal: .wtbal,
    ]

    /// Presses the keys for a literal such as "-45", "0:15:00" or ".82".
    func type(_ s: String) {
        var negative = false
        for ch in s {
            switch ch {
            case "-": negative = true
            case ".": c.press(.dot)
            case ":": c.press(.colon)
            default:
                let key: KeyID = [
                    "0": .d0, "1": .d1, "2": .d2, "3": .d3, "4": .d4,
                    "5": .d5, "6": .d6, "7": .d7, "8": .d8, "9": .d9,
                ][ch]!
                c.press(key)
            }
        }
        if negative { c.press(.plusMinus) }
    }

    func press(_ keys: KeyID...) { keys.forEach { c.press($0) } }

    /// Moves the menu cursor to a function (without starting it).
    func select(_ name: String, file: StaticString = #filePath, line: UInt = #line) {
        let f = Functions.named(name)
        c.press(Pad.groupKey[f.group]!)
        for _ in 0..<12 where c.lcd().menuCursor != name { c.press(.down) }
        XCTAssertEqual(c.lcd().menuCursor, name, "could not select \(name)", file: file, line: line)
    }

    /// Selects a function, enters every input (each followed by ENTER).
    func run(_ name: String, _ inputs: [String]) {
        select(name)
        c.press(.enter)
        for i in inputs {
            type(i)
            c.press(.enter)
        }
    }

    /// LCD text of a 1-based row, with the trailing "." of whole numbers removed.
    func row(_ n: Int) -> String? {
        guard var t = c.lcd().rows[n - 1]?.text else { return nil }
        let neg = c.lcd().rows[n - 1]?.negative ?? false
        if t.hasSuffix(".") { t.removeLast() }
        return (neg ? "-" : "") + t
    }

    /// Entry line shown while in the menu (e.g. conversion or calculator result).
    var entryLine: String? { row(1) }
}
