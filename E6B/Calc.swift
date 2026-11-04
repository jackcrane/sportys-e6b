import Foundation

/// Pure aviation math used by the E6B. Formulas were calibrated against the
/// sample problems in Appendix A of the Sporty's E6B manual.
enum Calc {
    // MARK: Helpers
    static func rad(_ d: Double) -> Double { d * .pi / 180 }
    static func deg(_ r: Double) -> Double { r * 180 / .pi }

    /// Normalises to 1...360 (a heading of 0 reads 360).
    static func norm360(_ d: Double) -> Double {
        var x = d.truncatingRemainder(dividingBy: 360)
        if x <= 0 { x += 360 }
        return x
    }

    // MARK: Atmosphere
    static let a0 = 661.4786            // kt, speed of sound at ISA sea level
    static let tempOffset = 273.0       // the E6B uses 273 for Celsius -> Kelvin
    static let speedCoef = 38.99        // a = coef * sqrt(T) in knots

    static func pressureRatio(_ altFt: Double) -> Double {
        pow(max(0, 1 - 6.8755856e-6 * altFt), 5.2559)
    }

    static func pressureAltitude(indicated: Double, baro: Double) -> Double {
        indicated + 145442.16 * (1 - pow(baro / 29.92, 0.190263))
    }

    static func densityAltitude(pressureAlt: Double, tempC: Double) -> Double {
        let theta = (tempC + tempOffset) / 288.16
        let sigma = pressureRatio(pressureAlt) / theta
        return (1 - pow(sigma, 1 / 4.256)) / 6.8755856e-6
    }

    static func machFromCAS(cas: Double, pressureAlt: Double) -> Double {
        let qc = pow(1 + 0.2 * pow(cas / a0, 2), 3.5) - 1
        let ratio = qc / pressureRatio(pressureAlt)
        return sqrt(5 * (pow(ratio + 1, 2.0 / 7.0) - 1))
    }

    static func casFromMach(mach: Double, pressureAlt: Double) -> Double {
        let qcOverP = pow(1 + 0.2 * mach * mach, 3.5) - 1
        let qc = qcOverP * pressureRatio(pressureAlt)
        return a0 * sqrt(5 * (pow(qc + 1, 2.0 / 7.0) - 1))
    }

    static func speedOfSound(tempC: Double) -> Double {
        speedCoef * sqrt(max(0, tempC + tempOffset))
    }

    /// Converts indicated (ram-heated) temperature to true temperature.
    static func trueTemp(indicatedC: Double, mach: Double) -> Double {
        (indicatedC + tempOffset) / (1 + 0.2 * mach * mach) - tempOffset
    }

    // MARK: Wind triangle
    /// Heading, groundspeed and WCA for a given wind, course and TAS.
    static func hdgGS(wdir: Double, wspd: Double, crs: Double, tas: Double)
        -> (gs: Double, hdg: Double, wca: Double)? {
        guard tas > 0 else { return nil }
        let rel = rad(wdir - crs)
        let s = wspd * sin(rel) / tas
        guard abs(s) <= 1 else { return nil }
        let wca = asin(s)
        let gs = tas * cos(wca) - wspd * cos(rel)
        return (gs, norm360(crs + deg(wca)), deg(wca))
    }

    /// TAS and heading required to make good a course at a given groundspeed.
    static func requiredTAS(wdir: Double, wspd: Double, crs: Double, gs: Double)
        -> (tas: Double, hdg: Double) {
        let toward = rad(wdir + 180)
        let wE = wspd * sin(toward), wN = wspd * cos(toward)
        let gE = gs * sin(rad(crs)), gN = gs * cos(rad(crs))
        let aE = gE - wE, aN = gN - wN
        return (hypot(aE, aN), norm360(deg(atan2(aE, aN))))
    }

    /// Wind from course, TAS, groundspeed and heading.
    static func windFrom(crs: Double, tas: Double, gs: Double, hdg: Double)
        -> (wdir: Double, wspd: Double) {
        let wE = gs * sin(rad(crs)) - tas * sin(rad(hdg))
        let wN = gs * cos(rad(crs)) - tas * cos(rad(hdg))
        return (norm360(deg(atan2(wE, wN)) + 180), hypot(wE, wN))
    }

    /// Right crosswind positive; tailwind positive (headwind negative).
    static func crossHead(wdir: Double, wspd: Double, runway: Double)
        -> (x: Double, h: Double) {
        let angle = rad(wdir - runway * 10)
        return (wspd * sin(angle), -wspd * cos(angle))
    }

    // MARK: Conversions
    static let nmPerSM = 1.15078
    static let kmPerNM = 1.852
    static let kgPerLb = 0.45359237
    static let litersPerGal = 3.785411784
    static let mbPerInHg = 33.8639
    static let avgasLbPerGal = 6.0
    static let jetLbPerGal = 6.7
}

// MARK: - Display formatting

enum Fmt {
    /// Formats a value for the six digit LCD. Trailing zeros are dropped and
    /// extra decimals are truncated when the digits would not fit.
    static func number(_ v: Double, decimals: Int) -> (text: String, negative: Bool) {
        guard v.isFinite else { return ("Error", false) }
        let neg = v < 0
        let a = abs(v)
        let intDigits = a < 1 ? 1 : String(Int(a)).count
        if intDigits > 6 { return ("Error", false) }
        let d = max(0, min(decimals, 6 - intDigits))
        let f = pow(10.0, Double(d))
        let scaled = d < decimals ? (a * f).rounded(.towardZero) / f : (a * f).rounded() / f
        var s = String(format: "%.\(d)f", scaled)
        if s.contains(".") {
            while s.hasSuffix("0") { s.removeLast() }
        } else {
            s += "."
        }
        if s == "0." || s == "-0." { return ("0.", false) }
        return (s, neg && scaled != 0)
    }

    /// hh:mm:ss from decimal hours (rounded to the nearest second).
    static func hms(hours: Double) -> (text: String, negative: Bool) {
        guard hours.isFinite else { return ("Error", false) }
        let total = Int((abs(hours) * 3600).rounded())
        return (hmsString(total), hours < 0 && total != 0)
    }

    static func hmsString(_ totalSeconds: Int) -> String {
        let h = totalSeconds / 3600, m = (totalSeconds / 60) % 60, s = totalSeconds % 60
        if h > 99 { return "Error" }
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}
