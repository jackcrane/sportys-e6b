import XCTest
@testable import E6B

/// One test per E6B function, using the sample problems in Appendix A of the
/// Sporty's E6B manual (e6bmanual2016.pdf, pages 42-46).
///
/// Each case is checked twice:
///  1. at the math level - `FuncDef.compute` against the manual's answer within
///     half a unit of the precision the manual prints; and
///  2. end to end - the keys a pilot would press, and the exact text the LCD shows.
final class AppendixFunctionTests: XCTestCase {

    struct Case {
        let fn: String
        /// Typed keystrokes for each input, in the unit's prompt order.
        let keys: [String]
        /// Inputs for `compute`, in base units (time in decimal hours).
        let inputs: [Key: Double]
        /// Manual answers: key, value, LCD row, LCD text, tolerance.
        let outputs: [(key: Key, value: Double, row: Int, text: String?, tol: Double)]
    }

    static let hour = 1.0 / 3600

    // Outputs whose `text` is nil are ones where the app's atmosphere model is
    // not bit-identical to the real unit. They are checked against the manual
    // within the explicit (loose) tolerance given, and as numbers on the LCD,
    // rather than as exact strings. Tighten these if the model is refined.

    static let cases: [Case] = [
        Case(fn: "HDG/GS", keys: ["270", "20", "355", "195"],
             inputs: [.wdir: 270, .wspd: 20, .crs: 355, .tas: 195],
             outputs: [(.gs, 192.2, 5, "192.2", 0.05), (.hdg, 349, 6, "349", 0.5), (.wca, -6, 6, "-6", 0.5)]),
        Case(fn: "P-D/ALT", keys: ["10000", "30.00", "5"],
             inputs: [.ialt: 10000, .baro: 30.00, .tc: 5],
             outputs: [(.palt, 9926, 1, "9926", 0.5), (.dalt, 11028, 6, nil, 2)]),
        Case(fn: "GS", keys: ["32", "0:15:00"],
             inputs: [.dist: 32, .time: 0.25],
             outputs: [(.gs, 128, 2, "128", 0.05)]),
        Case(fn: "PLAN TAS", keys: ["12000", "2", "195"],
             inputs: [.palt: 12000, .tc: 2, .cas: 195],
             outputs: [(.tas, 237.7, 4, nil, 0.15), (.mach, 0.37, 5, "0.37", 0.005), (.dalt, 13226, 6, nil, 3)]),
        Case(fn: "ACT TAS", keys: ["12000", "2", "195"],
             inputs: [.palt: 12000, .ic: 2, .cas: 195],
             outputs: [(.tas, 234.5, 4, nil, 0.1), (.mach, 0.37, 5, "0.37", 0.005), (.dalt, 12375, 6, nil, 25)]),
        Case(fn: "PLAN M#", keys: ["-45", ".82"],
             inputs: [.tc: -45, .mach: 0.82],
             outputs: [(.tas, 482.8, 4, "482.8", 0.05)]),
        Case(fn: "ACT M#", keys: ["-52", ".82"],
             inputs: [.ic: -52, .mach: 0.82],
             outputs: [(.tas, 445.6, 4, nil, 0.7)]),
        Case(fn: "FUEL", keys: ["2:45:00", "14"],
             inputs: [.time: 2.75, .fph: 14],
             outputs: [(.fuel, 38.5, 6, "38.5", 0.05)]),
        Case(fn: "CLIMB", keys: ["400", "80"],
             inputs: [.mclm: 400, .gs: 80],
             outputs: [(.mroc, 533.3, 4, "533.3", 0.05), (.pct, 6.6, 6, "6.6", 0.05)]),
        Case(fn: "DESCENT", keys: ["220", "20000", "11000", "25"],
             inputs: [.gs: 220, .ialt: 20000, .cralt: 11000, .fxdis: 25],
             outputs: [(.rqdn, 1320, 3, "1320", 0.5)]),
        Case(fn: "TAS", keys: ["270", "20", "355", "192"],
             inputs: [.wdir: 270, .wspd: 20, .crs: 355, .gs: 192],
             outputs: [(.tas, 194.8, 4, "194.8", 0.05), (.hdg, 349, 6, "349", 0.5)]),
        Case(fn: "CAS", keys: ["8000", "12", "185"],
             inputs: [.palt: 8000, .tc: 12, .tas: 185],
             outputs: [(.cas, 160.7, 3, nil, 0.1), (.mach, 0.28, 5, "0.28", 0.005), (.dalt, 9461.9, 6, nil, 1.5)]),
        Case(fn: "WIND", keys: ["355", "195", "175", "349"],
             inputs: [.crs: 355, .tas: 195, .gs: 175, .hdg: 349],
             outputs: [(.wdir, 307.9, 1, "307.9", 0.05), (.wspd, 27.8, 2, "27.8", 0.05)]),
        Case(fn: "X/H-WIND", keys: ["200", "17", "22"],
             inputs: [.wdir: 200, .wspd: 17, .rwy: 22],
             outputs: [(.xwind, -5.8, 5, "-5.8", 0.05), (.hwind, -16, 6, "-16", 0.05)]),
        Case(fn: "CLD BASE", keys: ["15", "10"],
             inputs: [.oat: 15, .dew: 10],
             outputs: [(.cloud, 2045.5, 4, "2045.5", 0.05)]),
        Case(fn: "DIST FLN", keys: ["220", "2:10:00"],
             inputs: [.gs: 220, .time: 2 + 10.0 / 60],
             outputs: [(.dist, 476.7, 1, "476.7", 0.05)]),
        Case(fn: "TOP DSCN", keys: ["230", "22000", "1000", "1500"],
             inputs: [.gs: 230, .ialt: 22000, .dalt: 1000, .rate: 1500],
             outputs: [(.tdcn, 53.7, 1, "53.7", 0.05)]),
        Case(fn: "ENDUR", keys: ["70", "14"],
             inputs: [.fuel: 70, .fph: 14],
             outputs: [(.time, 5.0, 3, "05:00:00", 0.5 * hour)]),
        Case(fn: "LEG TIME", keys: ["25", "195"],
             inputs: [.dist: 25, .gs: 195],
             outputs: [(.time, 7.7 / 60, 3, "00:07:42", 0.5 * hour + 0.5 / 60)]),
        Case(fn: "SPC RANGE", keys: ["2500", "280", "700"],
             inputs: [.fuel: 2500, .gs: 280, .fph: 700],
             outputs: [(.sprng, 1000, 5, "1000", 0.05)]),
        Case(fn: "FPH", keys: ["33", "2:45:00"],
             inputs: [.fuel: 33, .time: 2.75],
             outputs: [(.fph, 12, 4, "12", 0.05)]),
        Case(fn: "%MAC", keys: ["285.6", "308.08", "81"],
             inputs: [.lemac: 285.6, .cg: 308.08, .mac: 81],
             outputs: [(.pmac, 27.8, 3, "27.8", 0.05)]),
    ]

    // MARK: 1. math level

    func testComputeMatchesManual() throws {
        for c in Self.cases {
            let def = Functions.named(c.fn)
            let out = try XCTUnwrap(def.compute?(c.inputs), "\(c.fn): compute returned nil")
            for o in c.outputs {
                let got = try XCTUnwrap(out[o.key], "\(c.fn): missing output \(o.key)")
                XCTAssertEqual(got, o.value, accuracy: o.tol, "\(c.fn) \(o.key)")
            }
        }
    }

    // MARK: 2. keypad -> LCD

    func testKeypadShowsManualAnswers() {
        for c in Self.cases {
            let pad = Pad()
            pad.run(c.fn, c.keys)
            XCTAssertEqual(pad.c.mode, .result, "\(c.fn) did not reach a result")
            for o in c.outputs {
                // HDG/WCA share LCD row 6, so they are compared above, not here.
                if c.fn == "HDG/GS" && o.row == 6 { continue }
                if let text = o.text {
                    XCTAssertEqual(pad.row(o.row), text, "\(c.fn) \(o.key) (row \(o.row))")
                } else {
                    let shown = Double(pad.row(o.row) ?? "")
                    XCTAssertNotNil(shown, "\(c.fn) \(o.key) not numeric")
                    XCTAssertEqual(shown ?? .nan, o.value, accuracy: o.tol + 0.05, "\(c.fn) \(o.key) (row \(o.row))")
                }
            }
        }
    }

    func testHdgGSRow6ShowsHeadingAndWCA() {
        let pad = Pad()
        pad.run("HDG/GS", ["270", "20", "355", "195"])
        let row6 = pad.c.lcd().rows[5]?.text ?? ""
        let parts = row6.split(separator: " ").map(String.init)
        XCTAssertEqual(parts.first, "349")
        XCTAssertEqual(parts.last, "6.")                     // WCA magnitude
        XCTAssertTrue(pad.c.lcd().rows[5]?.negative ?? false) // sign flag for the negative WCA
    }

    // MARK: Coverage guard

    func testEveryNonBalanceFunctionHasAppendixCase() {
        let covered = Set(Self.cases.map(\.fn))
        for f in Functions.all where f.balance == nil {
            XCTAssertTrue(covered.contains(f.name), "No Appendix A test for \(f.name)")
        }
        // Weight & balance functions are covered in WeightBalanceTests.
        XCTAssertEqual(Functions.all.filter { $0.balance != nil }.map(\.name).sorted(), ["WT/ARM", "WT/MOM"])
    }

    // MARK: Degenerate inputs show Error instead of crashing

    func testDivisionByZeroFunctionsFail() {
        for (fn, keys) in [("LEG TIME", ["25", "0"]), ("GS", ["32", "0"]), ("FPH", ["33", "0"]),
                           ("ENDUR", ["70", "0"]), ("SPC RANGE", ["2500", "280", "0"]),
                           ("%MAC", ["285.6", "308.08", "0"]), ("TOP DSCN", ["230", "22000", "1000", "0"]),
                           ("DESCENT", ["220", "20000", "11000", "0"])] {
            let pad = Pad()
            pad.run(fn, keys)
            let outRows = Functions.named(fn).outputs.map(\.row)
            XCTAssertTrue(outRows.contains { pad.row($0) == "Error" }, "\(fn) should display Error")
        }
    }

    func testImpossibleWindShowsError() {
        let pad = Pad()
        pad.run("HDG/GS", ["90", "200", "360", "100"])   // wind faster than TAS
        XCTAssertEqual(pad.row(5), "Error")
    }

    // MARK: Value carry-over between functions

    func testGroundSpeedCarriesIntoNextFunction() {
        let pad = Pad()
        pad.run("HDG/GS", ["270", "20", "355", "195"])    // GS 192.2...
        pad.select("LEG TIME")
        pad.c.press(.enter)
        pad.type("25"); pad.c.press(.enter)               // DIST
        pad.c.press(.enter)                               // accept carried GS
        XCTAssertEqual(pad.row(3), Fmt.hms(hours: 25 / 192.2158).text)
    }
}
