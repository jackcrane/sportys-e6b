import XCTest
@testable import E6B

/// CONV + key conversions, from the "Conversions" list in Appendix A.
final class ConversionTests: XCTestCase {

    struct Conv { let input: String; let key: KeyID; let expected: String; let label: String }

    static let all: [Conv] = [
        Conv(input: "25",      key: .d0,        expected: "11.34",    label: "lb -> kg"),
        Conv(input: "12",      key: .dot,       expected: "26.46",    label: "kg -> lb"),
        Conv(input: "25",      key: .equals,    expected: "150",      label: "gal AvGas -> lb"),
        Conv(input: "87.1",    key: .plus,      expected: "14.52",    label: "lb AvGas -> gal"),
        Conv(input: "30",      key: .d1,        expected: "9.14",     label: "ft -> m"),
        Conv(input: "100",     key: .d2,        expected: "328.08",   label: "m -> ft"),
        Conv(input: "250",     key: .d3,        expected: "1675",     label: "gal jet -> lb"),
        Conv(input: "3025",    key: .minus,     expected: "451.49",   label: "lb jet -> gal"),
        Conv(input: "32",      key: .clear,     expected: "0",        label: "F -> C"),
        Conv(input: "100",     key: .power,     expected: "212",      label: "C -> F"),
        Conv(input: "100",     key: .d4,        expected: "185.2",    label: "NM -> km"),
        Conv(input: "50",      key: .d5,        expected: "27",       label: "km -> NM"),
        Conv(input: "9.5125",  key: .d6,        expected: "09:30:45", label: "decimal hrs -> hms"),
        Conv(input: "12:30:30", key: .times,    expected: "12.5083",  label: "hms -> decimal hrs"),
        Conv(input: "87",      key: .d7,        expected: "100.12",   label: "NM -> SM"),
        Conv(input: "115",     key: .d8,        expected: "99.93",    label: "SM -> NM"),
        Conv(input: "1",       key: .d9,        expected: "3.79",     label: "US gal -> L"),
        Conv(input: "10",      key: .divide,    expected: "2.64",     label: "L -> US gal"),
        Conv(input: "1",       key: .plusMinus, expected: "33.86",    label: "inHg -> mb"),
        Conv(input: "1024",    key: .colon,     expected: "30.24",    label: "mb -> inHg"),
    ]

    func testAppendixConversions() {
        for c in Self.all {
            let pad = Pad()
            pad.type(c.input)
            pad.press(.conv, c.key)
            XCTAssertEqual(pad.entryLine, c.expected, "\(c.label): \(c.input)")
        }
    }

    func testConversionsAlsoWorkInsideAFunctionPrompt() {
        let pad = Pad()
        pad.select("FUEL"); pad.c.press(.enter)   // TIME prompt
        pad.type("2:45:00"); pad.c.press(.enter)  // FPH prompt
        pad.type("25"); pad.press(.conv, .equals) // 25 US gal AvGas -> 150 lb
        XCTAssertEqual(pad.row(4), "150")
        pad.c.press(.enter)
        XCTAssertEqual(pad.row(6), "412.5")       // 2.75 h * 150
    }

    func testInverseConversionsRoundTrip() {
        let pairs: [(KeyID, KeyID, Double)] = [
            (.d0, .dot, 250), (.equals, .plus, 40), (.d1, .d2, 5000), (.d3, .minus, 100),
            (.clear, .power, 90), (.d4, .d5, 500), (.d7, .d8, 300), (.d9, .divide, 20),
            (.plusMinus, .colon, 29.92),
        ]
        for (a, b, v) in pairs {
            let pad = Pad()
            pad.type(String(v))
            pad.press(.conv, a)
            pad.press(.conv, b)
            let shown = Double(pad.entryLine!)!
            // two display roundings -> allow a small relative error
            XCTAssertEqual(shown, v, accuracy: max(0.05, v * 0.001), "\(a)/\(b)")
        }
    }

    func testNegativeFahrenheitToCelsius() {
        let pad = Pad()
        pad.type("-40")
        pad.press(.conv, .clear)
        XCTAssertEqual(pad.entryLine, "-40")
    }

    func testConvWithNoValueShowsHintAndDoesNotChangeEntry() {
        let pad = Pad()
        pad.press(.conv, .d0)
        XCTAssertNotNil(pad.c.lcd().toast)
        XCTAssertNil(pad.entryLine)
    }
}
