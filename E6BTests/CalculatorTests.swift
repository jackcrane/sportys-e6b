import XCTest
@testable import E6B

/// The built-in four function calculator (menu mode) and entry-line behaviour.
final class CalculatorTests: XCTestCase {

    func testHMSAddition_manual() {
        let pad = Pad()
        pad.type("4:45:00"); pad.press(.plus)
        pad.type("2:15:30"); pad.press(.equals)
        XCTAssertEqual(pad.entryLine, "07:00:30")
    }

    func testDecimalMinusHMS_manual() {
        let pad = Pad()
        pad.type("6.7"); pad.press(.minus)
        pad.type("5:20:00"); pad.press(.equals)
        XCTAssertEqual(pad.entryLine, "01:22:00")
    }

    func testBasicArithmetic() {
        for (a, op, b, expected) in [("12", KeyID.plus, "30", "42"), ("50", .minus, "8", "42"),
                                     ("6", .times, "7", "42"), ("84", .divide, "2", "42"),
                                     ("1", .divide, "8", "0.125"), ("2.5", .times, "4", "10"),
                                     ("5", .minus, "8", "-3")] {
            let pad = Pad()
            pad.type(a); pad.press(op); pad.type(b); pad.press(.equals)
            XCTAssertEqual(pad.entryLine, expected, "\(a) \(op) \(b)")
        }
    }

    func testChainedOperations() {
        let pad = Pad()
        pad.type("10"); pad.press(.plus); pad.type("5"); pad.press(.times)
        pad.type("2"); pad.press(.equals)
        XCTAssertEqual(pad.entryLine, "30")      // left-to-right, like a basic calculator
    }

    func testDivideByZeroShowsError() {
        let pad = Pad()
        pad.type("5"); pad.press(.divide); pad.type("0"); pad.press(.equals)
        XCTAssertEqual(pad.entryLine, "Error")
    }

    func testEntryLimits() {
        let pad = Pad()
        pad.type("1234567")                       // 7th digit ignored
        XCTAssertEqual(pad.entryLine, "123456")
        pad.press(.clear)
        pad.type("1.2.3")                         // second decimal point ignored
        XCTAssertEqual(pad.entryLine, "1.23")
    }

    func testSignToggleAndClear() {
        let pad = Pad()
        pad.type("12"); pad.press(.plusMinus)
        XCTAssertEqual(pad.entryLine, "-12")
        pad.press(.plusMinus)
        XCTAssertEqual(pad.entryLine, "12")
        pad.press(.clear)
        XCTAssertNil(pad.entryLine)
    }

    func testLeadingZerosAreDropped() {
        let pad = Pad()
        pad.type("007")
        XCTAssertEqual(pad.entryLine, "7")
    }

    func testColonEntryParsing() {
        // h:mm:ss entry is stored as decimal hours.
        var e = Entry(); e.raw = "2:45:00"
        XCTAssertEqual(e.value!, 2.75, accuracy: 1e-12)
        e.raw = "0:07:42"
        XCTAssertEqual(e.value!, 7.7 / 60, accuracy: 1e-12)
        e.raw = "1:30"                            // h:mm
        XCTAssertEqual(e.value!, 1.5, accuracy: 1e-12)
        e.raw = "2:00:00"; e.negative = true
        XCTAssertEqual(e.value!, -2, accuracy: 1e-12)
    }
}
