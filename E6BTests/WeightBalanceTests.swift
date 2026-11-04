import XCTest
@testable import E6B

/// WT/ARM and WT/MOM running-total problems from Appendix A.
final class WeightBalanceTests: XCTestCase {

    /// Adds one load item, returning after the totals are displayed.
    private func add(_ pad: Pad, _ vals: [String]) {
        for v in vals { pad.type(v); pad.c.press(.enter) }
    }

    func testWTARM_manual() {
        let pad = Pad()
        pad.select("WT/ARM"); pad.c.press(.enter)
        add(pad, ["2467", "76.7", "1"])                       // empty (RF = 1)
        XCTAssertEqual(pad.row(6), "2467")
        XCTAssertEqual(pad.row(3), "189218")
        pad.c.press(.enter); add(pad, ["444", "75"])           // fuel
        XCTAssertEqual(pad.row(6), "2911")
        XCTAssertEqual(pad.row(3), "222518")
        pad.c.press(.enter); add(pad, ["340", "75"])           // front seat
        XCTAssertEqual(pad.row(6), "3251")
        XCTAssertEqual(pad.row(3), "248018")
        pad.c.press(.enter); add(pad, ["0", "115"])            // 2nd row (empty)
        pad.c.press(.enter); add(pad, ["0", "148"])            // 3rd row (empty)
        XCTAssertEqual(pad.row(6), "3251")
        pad.c.press(.enter); add(pad, ["100", "164"])          // baggage
        XCTAssertEqual(pad.row(6), "3351")
        XCTAssertEqual(pad.row(3), "264418")
        XCTAssertEqual(pad.row(4), "78.91")                    // CG
    }

    func testWTARM_defaultsRFToOne() {
        let pad = Pad()
        pad.select("WT/ARM"); pad.c.press(.enter)
        add(pad, ["100", "50"])
        pad.c.press(.enter)                                     // accept the pre-filled RF of 1
        XCTAssertEqual(pad.row(3), "5000")
        XCTAssertEqual(pad.row(4), "50")
        XCTAssertEqual(pad.row(6), "100")
    }

    func testWTARM_withReductionFactor() {
        let pad = Pad()
        pad.select("WT/ARM"); pad.c.press(.enter)
        add(pad, ["100", "50", "100"])                          // moment/100
        XCTAssertEqual(pad.row(3), "50")                        // 100*50/100
        XCTAssertEqual(pad.row(4), "50")                        // CG unaffected by RF
    }

    /// Payload table, WT/MOM with moments in thousands (RF = 1000).
    func testWTMOM_manual() {
        let pad = Pad()
        pad.select("WT/MOM"); pad.c.press(.enter)
        add(pad, ["8916", "2809.0", "1000"])                    // basic operating weight
        func next(_ w: String, _ m: String) { pad.c.press(.enter); add(pad, [w, m]) }
        next("170", "37.7"); next("160", "35.5"); next("190", "50.5"); next("110", "29.3")
        next("60", "4.4");   next("110", "50.8")
        XCTAssertEqual(pad.row(6), "9716")                      // zero fuel weight
        XCTAssertEqual(pad.row(3), "3017.2")
        next("5424", "1644.1")
        XCTAssertEqual(pad.row(6), "15140")                     // ramp weight
        XCTAssertEqual(pad.row(3), "4661.3")
        next("-200", "-61.8")
        XCTAssertEqual(pad.row(6), "14940")                     // takeoff gross weight
        XCTAssertEqual(pad.row(3), "4599.5")
        next("-2000", "-612.9")
        XCTAssertEqual(pad.row(6), "12940")                     // landing weight
        XCTAssertEqual(pad.row(3), "3986.6")
        XCTAssertEqual(pad.row(4), "308.08")                    // CG
    }

    func testWTMOMCGCarriesIntoPercentMAC_manual() {
        let pad = Pad()
        pad.select("WT/MOM"); pad.c.press(.enter)
        add(pad, ["12940", "3986.6", "1000"])
        XCTAssertEqual(pad.row(4), "308.08")
        pad.run("%MAC", ["285.6", "", "81"].map { $0 })          // CG prompt: ENTER accepts carried CG
        XCTAssertEqual(pad.row(3), "27.8")
    }

    func testSwitchingBetweenARMAndMOMResetsTotals() {
        let pad = Pad()
        pad.select("WT/ARM"); pad.c.press(.enter)
        add(pad, ["100", "50", "1"])
        pad.select("WT/MOM"); pad.c.press(.enter)
        add(pad, ["200", "10000", "1"])
        XCTAssertEqual(pad.row(6), "200")                       // not 300
        XCTAssertEqual(pad.row(4), "50")
    }

    func testClearingStepBackKeepsRunningTotals() {
        let pad = Pad()
        pad.select("WT/ARM"); pad.c.press(.enter)
        add(pad, ["100", "50", "1"])
        pad.c.press(.enter)                                     // start next item
        pad.type("30"); pad.c.press(.enter)                     // WT entered
        pad.c.press(.clear)                                     // clear the (empty) ARM prompt -> back to WT
        pad.type("25"); pad.c.press(.enter); pad.type("90"); pad.c.press(.enter)
        XCTAssertEqual(pad.row(6), "125")
        XCTAssertEqual(pad.row(3), "7250")                      // 5000 + 25*90
    }
}
