import SwiftUI
import UIKit

/// The whole flight computer: rubber body, LCD and keypad, drawn on a fixed
/// 360 x 740 canvas that ContentView scales to fit the screen.
struct DeviceView: View {
    @ObservedObject var computer: E6BComputer
    @State private var showSettings = false

    static let size = CGSize(width: 360, height: 690)

    var body: some View {
        ZStack(alignment: .topLeading) {
            body_
            lcdGlass
            functionKeys
            numericKeys
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    // MARK: Body shell

    private var body_: some View {
        Color(white: 0.13)
            .frame(width: Self.size.width, height: Self.size.height)
    }

    // MARK: LCD

    private var lcdGlass: some View {
        let lcd = computer.lcd()
        let bg = Color(red: 0.69, green: 0.72, blue: 0.67)
        return ZStack {
            // Extends far upward so it also fills the safe area above the device
            Rectangle()
                .fill(bg)
                .frame(width: Self.size.width, height: 322 + 600)
                .offset(y: -300)
            LCDView(computer: computer)
                .frame(width: LCDView.size.width, height: LCDView.size.height)
                .offset(y: 0)
        }
        .position(x: 180, y: 161)
    }

    // MARK: Function keys

    private struct FKey: Identifiable {
        let id: KeyID
        let title: String
        let note: String?
    }

    private var functionKeys: some View {
        let rows: [[FKey]] = [
            [FKey(id: .hdg, title: "HDG/GS\nP-D/ALT", note: nil), FKey(id: .speed, title: "SPEED", note: nil),
             FKey(id: .required, title: "REQUIRED", note: nil), FKey(id: .up, title: "▲", note: nil)],
            [FKey(id: .wind, title: "WIND", note: nil), FKey(id: .flight, title: "FLIGHT", note: nil),
             FKey(id: .wtbal, title: "WT/BAL", note: nil), FKey(id: .enter, title: "ENTER", note: nil)],
            [FKey(id: .conv, title: "CONV", note: nil), FKey(id: .timer, title: "TIMER", note: "RESET"),
             FKey(id: .clock, title: "CLOCK", note: "SET"), FKey(id: .down, title: "▼", note: nil)],
        ]
        return ZStack {
            ForEach(0..<3, id: \.self) { r in
                ForEach(0..<4, id: \.self) { c in
                    let k = rows[r][c]
                    VStack(spacing: 1) {
                        Text(k.note ?? " ")
                            .font(.system(size: 6.5, weight: .semibold))
                            .foregroundStyle(Color(white: 0.62))
                            .frame(height: 8)
                        KeyButton(computer: computer, id: k.id, shape: .pill) {
                            Text(k.title)
                                .font(.system(size: k.title.contains("\n") ? 8.8 : (k.title.count == 1 ? 12 : 10.5),
                                              weight: .heavy))
                                .multilineTextAlignment(.center)
                                .foregroundStyle(Color(white: 0.92))
                                .lineSpacing(-1)
                        }
                        .frame(width: 77, height: 29)
                    }
                    .position(x: 52.5 + CGFloat(c) * 85, y: 348 + CGFloat(r) * 42 + 4)
                }
            }
        }
    }

    // MARK: Numeric keypad

    private struct NKey: Identifiable {
        let id: KeyID
        let title: String
        let conv: String
        var symbol: String? = nil
    }

    /// The cog opens settings. While CONV is armed it still acts as the
    /// original keypad's °C→°F key.
    private func cogPressed() {
        if computer.lcd().convArmed { computer.press(.power) } else { showSettings = true }
    }

    private var numericKeys: some View {
        let rows: [[NKey]] = [
            [NKey(id: .plusMinus, title: "+/−", conv: "IN→MB"), NKey(id: .d7, title: "7", conv: "NM→SM"),
             NKey(id: .d8, title: "8", conv: "SM→NM"), NKey(id: .d9, title: "9", conv: "GAL→LIT"),
             NKey(id: .divide, title: "÷", conv: "LIT→GAL")],
            [NKey(id: .colon, title: ":", conv: "MB→IN"), NKey(id: .d4, title: "4", conv: "NM→KM"),
             NKey(id: .d5, title: "5", conv: "KM→NM"), NKey(id: .d6, title: "6", conv: "H→HMS"),
             NKey(id: .times, title: "x", conv: "HMS→H")],
            [NKey(id: .clear, title: "c", conv: "°F→°C"), NKey(id: .d1, title: "1", conv: "FT→M"),
             NKey(id: .d2, title: "2", conv: "M→FT"), NKey(id: .d3, title: "3", conv: "JET→LB"),
             NKey(id: .minus, title: "–", conv: "LB→JET")],
            [NKey(id: .power, title: "", conv: "°C→°F", symbol: "gearshape.fill"), NKey(id: .d0, title: "0", conv: "LB→KG"),
             NKey(id: .dot, title: "·", conv: "KG→LB"), NKey(id: .equals, title: "=", conv: "GAS→LB"),
             NKey(id: .plus, title: "+", conv: "LB→GAS")],
        ]
        return ZStack {
            ForEach(0..<4, id: \.self) { r in
                ForEach(0..<5, id: \.self) { c in
                    let k = rows[r][c]
                    VStack(spacing: 2) {
                        Text(k.conv)
                            .font(.system(size: 6.6, weight: .semibold))
                            .foregroundStyle(Color(white: 0.90))
                            .frame(height: 8)
                        KeyButton(computer: computer, id: k.id, shape: .oval, override: k.symbol == nil ? nil : cogPressed) {
                            if let sym = k.symbol {
                                Image(systemName: sym).font(.system(size: 15, weight: .heavy))
                                    .foregroundStyle(Color(white: 0.95))
                            } else {
                                Text(k.title)
                                    .font(.system(size: k.title.count > 1 ? 13 : 22, weight: .heavy, design: .rounded))
                                    .foregroundStyle(Color(white: 0.95))
                            }
                        }
                        .frame(width: 52, height: 34)
                    }
                    .position(x: 40 + CGFloat(c) * 70, y: 490 + CGFloat(r) * 50 + 22)
                }
            }
        }
    }
}

// MARK: - Key button

enum KeyShape { case pill, oval }

private struct KeyButton<Label: View>: View {
    @ObservedObject var computer: E6BComputer
    let id: KeyID
    let shape: KeyShape
    var override: (() -> Void)? = nil
    @ViewBuilder var label: () -> Label

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if let override { override() } else { computer.press(id) }
        } label: {
            label()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(KeyStyle(shape: shape))
    }
}

private struct KeyStyle: ButtonStyle {
    let shape: KeyShape

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let corner: CGFloat = shape == .pill ? 14 : 17
        return configuration.label
            .background(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(shape == .pill
                          ? Color(white: pressed ? 0.20 : 0.30)
                          : Color(white: pressed ? 0.30 : 0.22))
            )
            .contentShape(Rectangle())
    }
}
