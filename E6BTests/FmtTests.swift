import XCTest
@testable import E6B

final class FmtTests: XCTestCase {
    func testNumber() {
        XCTAssertEqual(Fmt.number(192.2, decimals: 1).text, "192.2")
        XCTAssertEqual(Fmt.number(150, decimals: 2).text, "150.")        // trailing zeros dropped
        XCTAssertEqual(Fmt.number(0, decimals: 2).text, "0.")
        XCTAssertEqual(Fmt.number(0.37, decimals: 2).text, "0.37")
        XCTAssertEqual(Fmt.number(11028.4, decimals: 0).text, "11028.")
        XCTAssertEqual(Fmt.number(11028.6, decimals: 0).text, "11029.")   // output rounds
        XCTAssertEqual(Fmt.number(-5.83, decimals: 1).text, "5.8")
        XCTAssertTrue(Fmt.number(-5.83, decimals: 1).negative)
        XCTAssertFalse(Fmt.number(5.83, decimals: 1).negative)
    }

    func testNumberSixDigitLimit() {
        XCTAssertEqual(Fmt.number(123456, decimals: 2).text, "123456.")
        XCTAssertEqual(Fmt.number(1234.5678, decimals: 6).text, "1234.56")   // truncated to fit 6 digits
        XCTAssertEqual(Fmt.number(1234567, decimals: 1).text, "Error")
        XCTAssertEqual(Fmt.number(.infinity, decimals: 1).text, "Error")
        XCTAssertEqual(Fmt.number(.nan, decimals: 1).text, "Error")
    }

    func testNegativeZero() {
        let r = Fmt.number(-0.0004, decimals: 1)
        XCTAssertEqual(r.text, "0.")
        XCTAssertFalse(r.negative)
    }

    func testHMS() {
        XCTAssertEqual(Fmt.hms(hours: 9.5125).text, "09:30:45")
        XCTAssertEqual(Fmt.hms(hours: 5).text, "05:00:00")
        XCTAssertEqual(Fmt.hms(hours: 25.0 / 195.0).text, "00:07:42")
        XCTAssertEqual(Fmt.hms(hours: 0).text, "00:00:00")
        XCTAssertTrue(Fmt.hms(hours: -1.5).negative)
        XCTAssertEqual(Fmt.hms(hours: -1.5).text, "01:30:00")
        XCTAssertEqual(Fmt.hms(hours: 100).text, "Error")
        XCTAssertEqual(Fmt.hms(hours: .nan).text, "Error")
        XCTAssertEqual(Fmt.hmsString(3661), "01:01:01")
    }
}
