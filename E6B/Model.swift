import Foundation

// MARK: - LCD label table

/// Position of a label on the LCD: 6 rows, 4 label columns (two left of the
/// digits, two right) and 2 stacked lines per column.
struct LabelPos: Hashable {
    let row: Int   // 0...5
    let col: Int   // 0,1 = left of digits; 2,3 = right of digits
    let line: Int  // 0 = upper, 1 = lower
}

enum LabelTable {
    /// [row][column][line]
    static let table: [[[String]]] = [
        [["T-DCN", "WT"],   ["WDIR", "PALT"], ["LEMAC", "DIST"], ["MCLM", "OAT°C"]],
        [["I°C", "WSPD"],   ["ARM", "T°C"],   ["GS", "ZULU"],    ["RATE", "DEW°C"]],
        [["MOM", "RWY"],    ["CAS", "CRS"],   ["%MAC", "HOME"],  ["RQ/DN", "TIME"]],
        [["CG", "CLOUD"],   ["TAS", "AGL"],   ["FPH", "IALT"],   ["", "MROC"]],
        [["X-WIND", "GS"],  ["RF", "MACH#"],  ["MAC", "BARO"],   ["SPRNG", "CRALT"]],
        [["H-WIND", "HDG"], ["GW", "DALT"],   ["FUEL", "LOCAL"], ["FXDIS", "WCA %"]],
    ]

    static func pos(row: Int, label: String) -> LabelPos {
        let r = row - 1
        for c in 0..<4 {
            for l in 0..<2 where table[r][c][l] == label {
                return LabelPos(row: r, col: c, line: l)
            }
        }
        preconditionFailure("No label \(label) in row \(row)")
    }
}

// MARK: - Values

enum Key: Hashable {
    case wt, arm, mom, rf, cg, gw
    case wdir, wspd, crs, tas, gs, hdg, wca
    case palt, ialt, baro, tc, ic, cas, mach, dalt
    case dist, time, fuel, fph
    case mclm, mroc, pct, rqdn, cralt, fxdis, rate, tdcn
    case oat, dew, cloud, xwind, hwind, rwy
    case lemac, mac, pmac, sprng
}

enum FieldKind { case number, time }
enum RowPart { case full, left, right }

struct Field {
    let key: Key
    let row: Int
    let label: String
    var label2: String? = nil
    var shown: String? = nil
    var dec: Int = 1
    var kind: FieldKind = .number
    var part: RowPart = .full

    var pos: LabelPos { LabelTable.pos(row: row, label: label) }
    var pos2: LabelPos? { label2.map { LabelTable.pos(row: row, label: $0) } }
    var text: String { shown ?? label }
}

private func f(_ k: Key, _ row: Int, _ label: String, label2: String? = nil, shown: String? = nil,
               dec: Int = 1, time: Bool = false, part: RowPart = .full) -> Field {
    Field(key: k, row: row, label: label, label2: label2, shown: shown, dec: dec,
          kind: time ? .time : .number, part: part)
}

// MARK: - Functions

enum Group: Int, CaseIterable {
    case hdg, speed, required, wind, flight, wtbal
}

enum BalanceKind { case arm, mom }

struct FuncDef: Identifiable {
    let name: String
    let group: Group
    let col: Int       // menu grid column 0...4
    let line: Int      // menu grid line 0...5
    let inputs: [Field]
    let outputs: [Field]
    var balance: BalanceKind? = nil
    var compute: (([Key: Double]) -> [Key: Double]?)? = nil

    var id: String { name }
}

enum Functions {
    static let all: [FuncDef] = [
        // HDG/GS · P-D/ALT
        FuncDef(name: "HDG/GS", group: .hdg, col: 0, line: 0,
                inputs: [f(.wdir, 1, "WDIR"), f(.wspd, 2, "WSPD"), f(.crs, 3, "CRS"), f(.tas, 4, "TAS")],
                outputs: [f(.gs, 5, "GS"), f(.hdg, 6, "HDG", dec: 0, part: .left),
                          f(.wca, 6, "WCA %", shown: "WCA", dec: 0, part: .right)],
                compute: { v in
                    guard let r = Calc.hdgGS(wdir: v[.wdir]!, wspd: v[.wspd]!, crs: v[.crs]!, tas: v[.tas]!)
                    else { return nil }
                    return [.gs: r.gs, .hdg: r.hdg, .wca: r.wca]
                }),
        FuncDef(name: "P-D/ALT", group: .hdg, col: 0, line: 1,
                inputs: [f(.ialt, 4, "IALT"), f(.baro, 5, "BARO"), f(.tc, 2, "T°C")],
                outputs: [f(.palt, 1, "PALT", dec: 0), f(.dalt, 6, "DALT", dec: 0)],
                compute: { v in
                    let p = Calc.pressureAltitude(indicated: v[.ialt]!, baro: v[.baro]!)
                    return [.palt: p, .dalt: Calc.densityAltitude(pressureAlt: p, tempC: v[.tc]!)]
                }),

        // SPEED
        FuncDef(name: "GS", group: .speed, col: 1, line: 0,
                inputs: [f(.dist, 1, "DIST"), f(.time, 3, "TIME", time: true)],
                outputs: [f(.gs, 2, "GS")],
                compute: { v in
                    guard v[.time]! != 0 else { return nil }
                    return [.gs: v[.dist]! / v[.time]!]
                }),
        FuncDef(name: "PLAN TAS", group: .speed, col: 1, line: 1,
                inputs: [f(.palt, 1, "PALT"), f(.tc, 2, "T°C"), f(.cas, 3, "CAS")],
                outputs: [f(.tas, 4, "TAS"), f(.mach, 5, "MACH#", dec: 2), f(.dalt, 6, "DALT", dec: 0)],
                compute: { v in
                    let m = Calc.machFromCAS(cas: v[.cas]!, pressureAlt: v[.palt]!)
                    guard m.isFinite else { return nil }
                    return [.tas: m * Calc.speedOfSound(tempC: v[.tc]!), .mach: m,
                            .dalt: Calc.densityAltitude(pressureAlt: v[.palt]!, tempC: v[.tc]!)]
                }),
        FuncDef(name: "ACT TAS", group: .speed, col: 1, line: 2,
                inputs: [f(.palt, 1, "PALT"), f(.ic, 2, "I°C"), f(.cas, 3, "CAS")],
                outputs: [f(.tas, 4, "TAS"), f(.mach, 5, "MACH#", dec: 2), f(.dalt, 6, "DALT", dec: 0)],
                compute: { v in
                    let m = Calc.machFromCAS(cas: v[.cas]!, pressureAlt: v[.palt]!)
                    guard m.isFinite else { return nil }
                    let t = Calc.trueTemp(indicatedC: v[.ic]!, mach: m)
                    return [.tas: m * Calc.speedOfSound(tempC: t), .mach: m,
                            .dalt: Calc.densityAltitude(pressureAlt: v[.palt]!, tempC: t)]
                }),
        FuncDef(name: "PLAN M#", group: .speed, col: 1, line: 3,
                inputs: [f(.tc, 2, "T°C"), f(.mach, 5, "MACH#", dec: 2)],
                outputs: [f(.tas, 4, "TAS")],
                compute: { v in [.tas: v[.mach]! * Calc.speedOfSound(tempC: v[.tc]!)] }),
        FuncDef(name: "ACT M#", group: .speed, col: 1, line: 4,
                inputs: [f(.ic, 2, "I°C"), f(.mach, 5, "MACH#", dec: 2)],
                outputs: [f(.tas, 4, "TAS")],
                compute: { v in
                    let t = Calc.trueTemp(indicatedC: v[.ic]!, mach: v[.mach]!)
                    return [.tas: v[.mach]! * Calc.speedOfSound(tempC: t)]
                }),

        // REQUIRED
        FuncDef(name: "FUEL", group: .required, col: 3, line: 0,
                inputs: [f(.time, 3, "TIME", time: true), f(.fph, 4, "FPH")],
                outputs: [f(.fuel, 6, "FUEL")],
                compute: { v in [.fuel: v[.time]! * v[.fph]!] }),
        FuncDef(name: "CLIMB", group: .required, col: 3, line: 1,
                inputs: [f(.mclm, 1, "MCLM"), f(.gs, 2, "GS")],
                outputs: [f(.mroc, 4, "MROC"), f(.pct, 6, "WCA %", shown: "%")],
                compute: { v in [.mroc: v[.mclm]! * v[.gs]! / 60, .pct: v[.mclm]! / 6076.12 * 100] }),
        FuncDef(name: "DESCENT", group: .required, col: 3, line: 2,
                inputs: [f(.gs, 2, "GS"), f(.ialt, 4, "IALT"), f(.cralt, 5, "CRALT"), f(.fxdis, 6, "FXDIS")],
                outputs: [f(.rqdn, 3, "RQ/DN")],
                compute: { v in
                    guard v[.fxdis]! != 0 else { return nil }
                    return [.rqdn: (v[.ialt]! - v[.cralt]!) / (v[.fxdis]! / v[.gs]! * 60)]
                }),
        FuncDef(name: "TAS", group: .required, col: 3, line: 3,
                inputs: [f(.wdir, 1, "WDIR"), f(.wspd, 2, "WSPD"), f(.crs, 3, "CRS"), f(.gs, 5, "GS")],
                outputs: [f(.tas, 4, "TAS"), f(.hdg, 6, "HDG", dec: 0)],
                compute: { v in
                    let r = Calc.requiredTAS(wdir: v[.wdir]!, wspd: v[.wspd]!, crs: v[.crs]!, gs: v[.gs]!)
                    return [.tas: r.tas, .hdg: r.hdg]
                }),
        FuncDef(name: "CAS", group: .required, col: 3, line: 4,
                inputs: [f(.palt, 1, "PALT"), f(.tc, 2, "T°C"), f(.tas, 4, "TAS")],
                outputs: [f(.cas, 3, "CAS"), f(.mach, 5, "MACH#", dec: 2), f(.dalt, 6, "DALT")],
                compute: { v in
                    let a = Calc.speedOfSound(tempC: v[.tc]!)
                    guard a > 0 else { return nil }
                    let m = v[.tas]! / a
                    return [.cas: Calc.casFromMach(mach: m, pressureAlt: v[.palt]!), .mach: m,
                            .dalt: Calc.densityAltitude(pressureAlt: v[.palt]!, tempC: v[.tc]!)]
                }),

        // WIND
        FuncDef(name: "WIND", group: .wind, col: 0, line: 2,
                inputs: [f(.crs, 3, "CRS"), f(.tas, 4, "TAS"), f(.gs, 5, "GS"), f(.hdg, 6, "HDG")],
                outputs: [f(.wdir, 1, "WDIR"), f(.wspd, 2, "WSPD")],
                compute: { v in
                    let r = Calc.windFrom(crs: v[.crs]!, tas: v[.tas]!, gs: v[.gs]!, hdg: v[.hdg]!)
                    return [.wdir: r.wdir, .wspd: r.wspd]
                }),
        FuncDef(name: "X/H-WIND", group: .wind, col: 0, line: 3,
                inputs: [f(.wdir, 1, "WDIR"), f(.wspd, 2, "WSPD"), f(.rwy, 3, "RWY")],
                outputs: [f(.xwind, 5, "X-WIND"), f(.hwind, 6, "H-WIND")],
                compute: { v in
                    let r = Calc.crossHead(wdir: v[.wdir]!, wspd: v[.wspd]!, runway: v[.rwy]!)
                    return [.xwind: r.x, .hwind: r.h]
                }),
        FuncDef(name: "CLD BASE", group: .wind, col: 0, line: 4,
                inputs: [f(.oat, 1, "OAT°C"), f(.dew, 2, "DEW°C")],
                outputs: [f(.cloud, 4, "CLOUD", label2: "AGL")],
                compute: { v in [.cloud: (v[.oat]! - v[.dew]!) * 409.1] }),

        // FLIGHT
        FuncDef(name: "DIST FLN", group: .flight, col: 2, line: 0,
                inputs: [f(.gs, 2, "GS"), f(.time, 3, "TIME", time: true)],
                outputs: [f(.dist, 1, "DIST")],
                compute: { v in [.dist: v[.gs]! * v[.time]!] }),
        FuncDef(name: "TOP DSCN", group: .flight, col: 2, line: 1,
                inputs: [f(.gs, 5, "GS"), f(.ialt, 4, "IALT"), f(.dalt, 6, "DALT"), f(.rate, 2, "RATE")],
                outputs: [f(.tdcn, 1, "T-DCN")],
                compute: { v in
                    guard v[.rate]! != 0 else { return nil }
                    return [.tdcn: (v[.ialt]! - v[.dalt]!) / v[.rate]! * v[.gs]! / 60]
                }),
        FuncDef(name: "ENDUR", group: .flight, col: 2, line: 2,
                inputs: [f(.fuel, 6, "FUEL"), f(.fph, 4, "FPH")],
                outputs: [f(.time, 3, "TIME", time: true)],
                compute: { v in
                    guard v[.fph]! != 0 else { return nil }
                    return [.time: v[.fuel]! / v[.fph]!]
                }),
        FuncDef(name: "LEG TIME", group: .flight, col: 2, line: 3,
                inputs: [f(.dist, 1, "DIST"), f(.gs, 2, "GS")],
                outputs: [f(.time, 3, "TIME", time: true)],
                compute: { v in
                    guard v[.gs]! != 0 else { return nil }
                    return [.time: v[.dist]! / v[.gs]!]
                }),
        FuncDef(name: "SPC RANGE", group: .flight, col: 2, line: 4,
                inputs: [f(.fuel, 6, "FUEL"), f(.gs, 2, "GS"), f(.fph, 4, "FPH")],
                outputs: [f(.sprng, 5, "SPRNG")],
                compute: { v in
                    guard v[.fph]! != 0 else { return nil }
                    return [.sprng: v[.fuel]! / v[.fph]! * v[.gs]!]
                }),
        FuncDef(name: "FPH", group: .flight, col: 2, line: 5,
                inputs: [f(.fuel, 6, "FUEL"), f(.time, 3, "TIME", time: true)],
                outputs: [f(.fph, 4, "FPH")],
                compute: { v in
                    guard v[.time]! != 0 else { return nil }
                    return [.fph: v[.fuel]! / v[.time]!]
                }),

        // WT/BAL
        FuncDef(name: "WT/ARM", group: .wtbal, col: 4, line: 2,
                inputs: [f(.wt, 1, "WT"), f(.arm, 2, "ARM"), f(.rf, 5, "RF")],
                outputs: [f(.mom, 3, "MOM", dec: 2), f(.cg, 4, "CG", dec: 2), f(.gw, 6, "GW")],
                balance: .arm),
        FuncDef(name: "WT/MOM", group: .wtbal, col: 4, line: 3,
                inputs: [f(.wt, 1, "WT"), f(.mom, 3, "MOM"), f(.rf, 5, "RF")],
                outputs: [f(.mom, 3, "MOM", dec: 2), f(.cg, 4, "CG", dec: 2), f(.gw, 6, "GW")],
                balance: .mom),
        FuncDef(name: "%MAC", group: .wtbal, col: 4, line: 4,
                inputs: [f(.lemac, 1, "LEMAC"), f(.cg, 4, "CG"), f(.mac, 5, "MAC")],
                outputs: [f(.pmac, 3, "%MAC")],
                compute: { v in
                    guard v[.mac]! != 0 else { return nil }
                    return [.pmac: (v[.cg]! - v[.lemac]!) / v[.mac]! * 100]
                }),
    ]

    static func items(in group: Group?) -> [FuncDef] {
        guard let g = group else { return all }
        return all.filter { $0.group == g }
    }

    static func named(_ n: String) -> FuncDef { all.first { $0.name == n }! }
}
