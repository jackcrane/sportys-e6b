import XCTest
@testable import E6B

/// Direct tests of the pure math in `Calc`.
final class CalcTests: XCTestCase {

    // MARK: helpers
    func testNorm360() {
        XCTAssertEqual(Calc.norm360(0), 360)
        XCTAssertEqual(Calc.norm360(360), 360)
        XCTAssertEqual(Calc.norm360(361), 1)
        XCTAssertEqual(Calc.norm360(-10), 350)
        XCTAssertEqual(Calc.norm360(720), 360)
        XCTAssertEqual(Calc.norm360(90), 90)
    }

    func testRadDeg() {
        XCTAssertEqual(Calc.rad(180), .pi, accuracy: 1e-12)
        XCTAssertEqual(Calc.deg(.pi / 2), 90, accuracy: 1e-12)
    }

    // MARK: atmosphere
    func testPressureAltitude() {
        // Standard setting: PALT == indicated altitude.
        XCTAssertEqual(Calc.pressureAltitude(indicated: 5000, baro: 29.92), 5000, accuracy: 1e-6)
        // Manual: 10000 ft @ 30.00 -> 9926.
        XCTAssertEqual(Calc.pressureAltitude(indicated: 10000, baro: 30.00), 9926, accuracy: 0.5)
        // Roughly 900-1000 ft per inch of mercury; lower pressure -> higher PALT.
        XCTAssertEqual(Calc.pressureAltitude(indicated: 0, baro: 28.92), 937.6, accuracy: 1)
        XCTAssertGreaterThan(Calc.pressureAltitude(indicated: 0, baro: 29.00), 0)
    }

    func testPressureRatio() {
        XCTAssertEqual(Calc.pressureRatio(0), 1, accuracy: 1e-12)
        XCTAssertEqual(Calc.pressureRatio(18_000), 0.5, accuracy: 0.01)   // ~half at 18,000 ft
        XCTAssertEqual(Calc.pressureRatio(36_000), 0.2234, accuracy: 0.005)
        XCTAssertEqual(Calc.pressureRatio(1_000_000), 0)                   // clamped, never NaN
    }

    func testDensityAltitude() {
        // Manual: PALT 9926, 5 C -> 11028.
        XCTAssertEqual(Calc.densityAltitude(pressureAlt: 9926, tempC: 5), 11028, accuracy: 2)
        // At sea level on a standard day DALT is ~0.
        XCTAssertEqual(Calc.densityAltitude(pressureAlt: 0, tempC: 15), 0, accuracy: 25)
        // Hotter -> higher density altitude.
        XCTAssertGreaterThan(Calc.densityAltitude(pressureAlt: 5000, tempC: 30),
                             Calc.densityAltitude(pressureAlt: 5000, tempC: 10))
    }

    func testSpeedOfSound() {
        XCTAssertEqual(Calc.speedOfSound(tempC: 15), 661.5, accuracy: 0.5)   // kt at ISA SL
        XCTAssertEqual(Calc.speedOfSound(tempC: -273), 0)                     // clamped at absolute zero
        XCTAssertEqual(Calc.speedOfSound(tempC: -300), 0)
    }

    func testTrueTemp() {
        XCTAssertEqual(Calc.trueTemp(indicatedC: 15, mach: 0), 15, accuracy: 1e-12)
        // Ram rise: indicated is warmer than true.
        XCTAssertLessThan(Calc.trueTemp(indicatedC: -52, mach: 0.82), -52)
        // Manual ACT M#: I C -52 at M .82 gives TAS 445.6 (app is within 0.7 kt).
        let t = Calc.trueTemp(indicatedC: -52, mach: 0.82)
        XCTAssertEqual(0.82 * Calc.speedOfSound(tempC: t), 445.6, accuracy: 0.7)
    }

    func testMachCASRoundTrip() {
        for alt in stride(from: 0.0, through: 30_000, by: 5_000) {
            for cas in [100.0, 195, 250] {
                let m = Calc.machFromCAS(cas: cas, pressureAlt: alt)
                XCTAssertEqual(Calc.casFromMach(mach: m, pressureAlt: alt), cas, accuracy: 1e-6,
                               "alt \(alt) cas \(cas)")
            }
        }
        // At sea level CAS == a0 gives Mach 1.
        XCTAssertEqual(Calc.machFromCAS(cas: Calc.a0, pressureAlt: 0), 1, accuracy: 1e-9)
    }

    // MARK: wind triangle
    func testHdgGS_manual() throws {
        let r = try XCTUnwrap(Calc.hdgGS(wdir: 270, wspd: 20, crs: 355, tas: 195))
        XCTAssertEqual(r.gs, 192.2, accuracy: 0.05)
        XCTAssertEqual(r.hdg, 349, accuracy: 0.5)
        XCTAssertEqual(r.wca, -6, accuracy: 0.5)
    }

    func testHdgGS_basics() throws {
        // No wind: heading == course, GS == TAS.
        let calm = try XCTUnwrap(Calc.hdgGS(wdir: 0, wspd: 0, crs: 90, tas: 120))
        XCTAssertEqual(calm.gs, 120, accuracy: 1e-9)
        XCTAssertEqual(calm.hdg, 90, accuracy: 1e-9)
        // Direct headwind / tailwind.
        XCTAssertEqual(try XCTUnwrap(Calc.hdgGS(wdir: 90, wspd: 20, crs: 90, tas: 100)).gs, 80, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(Calc.hdgGS(wdir: 270, wspd: 20, crs: 90, tas: 100)).gs, 120, accuracy: 1e-9)
        // Heading of north reads 360, not 0.
        XCTAssertEqual(try XCTUnwrap(Calc.hdgGS(wdir: 0, wspd: 0, crs: 360, tas: 100)).hdg, 360)
        // Wind from the right requires a right-hand correction (positive WCA) when
        // it blows from the left: wind from 270, course north -> crab left.
        XCTAssertLessThan(try XCTUnwrap(Calc.hdgGS(wdir: 270, wspd: 30, crs: 360, tas: 120)).wca, 0)
        XCTAssertGreaterThan(try XCTUnwrap(Calc.hdgGS(wdir: 90, wspd: 30, crs: 360, tas: 120)).wca, 0)
    }

    func testHdgGS_impossible() {
        XCTAssertNil(Calc.hdgGS(wdir: 90, wspd: 200, crs: 360, tas: 100))   // crosswind > TAS
        XCTAssertNil(Calc.hdgGS(wdir: 90, wspd: 10, crs: 360, tas: 0))
        XCTAssertNil(Calc.hdgGS(wdir: 90, wspd: 10, crs: 360, tas: -5))
    }

    func testRequiredTAS_manual() {
        let r = Calc.requiredTAS(wdir: 270, wspd: 20, crs: 355, gs: 192)
        XCTAssertEqual(r.tas, 194.8, accuracy: 0.05)
        XCTAssertEqual(r.hdg, 349, accuracy: 0.5)
    }

    func testWindFrom_manual() {
        let r = Calc.windFrom(crs: 355, tas: 195, gs: 175, hdg: 349)
        XCTAssertEqual(r.wdir, 307.9, accuracy: 0.05)
        XCTAssertEqual(r.wspd, 27.8, accuracy: 0.05)
    }

    func testWindTriangleRoundTrip() throws {
        for (wd, ws, crs, tas) in [(270.0, 20.0, 355.0, 195.0), (45, 35, 180, 140), (310, 15, 20, 110), (180, 25, 90, 250)] {
            let a = try XCTUnwrap(Calc.hdgGS(wdir: wd, wspd: ws, crs: crs, tas: tas))
            let w = Calc.windFrom(crs: crs, tas: tas, gs: a.gs, hdg: a.hdg)
            XCTAssertEqual(w.wspd, ws, accuracy: 1e-6)
            let diff = abs(w.wdir - wd).truncatingRemainder(dividingBy: 360)
            XCTAssertEqual(min(diff, 360 - diff), 0, accuracy: 1e-6, "wdir \(wd)")
            let t = Calc.requiredTAS(wdir: wd, wspd: ws, crs: crs, gs: a.gs)
            XCTAssertEqual(t.tas, tas, accuracy: 1e-6)
            XCTAssertEqual(t.hdg, a.hdg, accuracy: 1e-6)
        }
    }

    func testCrossHead_manual() {
        let r = Calc.crossHead(wdir: 200, wspd: 17, runway: 22)
        XCTAssertEqual(r.x, -5.8, accuracy: 0.05)
        XCTAssertEqual(r.h, -16, accuracy: 0.05)
    }

    func testCrossHead_basics() {
        // Wind straight down the runway: pure headwind (negative H-WIND), zero crosswind.
        let head = Calc.crossHead(wdir: 220, wspd: 10, runway: 22)
        XCTAssertEqual(head.x, 0, accuracy: 1e-9)
        XCTAssertEqual(head.h, -10, accuracy: 1e-9)
        // Wind from behind: tailwind positive.
        XCTAssertEqual(Calc.crossHead(wdir: 40, wspd: 10, runway: 22).h, 10, accuracy: 1e-9)
        // Wind from the right of the runway heading (runway 36, wind 090): right crosswind positive.
        let right = Calc.crossHead(wdir: 90, wspd: 10, runway: 36)
        XCTAssertEqual(right.x, 10, accuracy: 1e-9)
        XCTAssertEqual(right.h, 0, accuracy: 1e-9)
        XCTAssertEqual(Calc.crossHead(wdir: 270, wspd: 10, runway: 36).x, -10, accuracy: 1e-9)
    }

    // MARK: constants
    func testConversionConstants() {
        XCTAssertEqual(Calc.kmPerNM, 1.852)
        XCTAssertEqual(Calc.nmPerSM, 1.15078, accuracy: 1e-5)
        XCTAssertEqual(Calc.mbPerInHg, 33.8639, accuracy: 1e-4)
        XCTAssertEqual(Calc.litersPerGal, 3.785, accuracy: 1e-3)
        XCTAssertEqual(Calc.kgPerLb, 0.4536, accuracy: 1e-4)
        XCTAssertEqual(Calc.avgasLbPerGal, 6.0)
        XCTAssertEqual(Calc.jetLbPerGal, 6.7)
    }
}
