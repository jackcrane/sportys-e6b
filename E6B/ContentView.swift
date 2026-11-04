import SwiftUI

struct ContentView: View {
    @StateObject private var computer = E6BComputer()
    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { safe in
          let top = safe.safeAreaInsets.top
          let bottom = safe.safeAreaInsets.bottom
          GeometryReader { geo in
            let scale = min(geo.size.width / DeviceView.size.width,
                            (geo.size.height - top - bottom) / DeviceView.size.height)
            let h = DeviceView.size.height * scale
            ZStack {
                theme.body
                DeviceView(computer: computer)
                    .scaleEffect(scale)
                    .frame(width: DeviceView.size.width * scale, height: h)
                    .position(x: geo.size.width / 2,
                              y: top + h / 2)
            }
            .frame(width: geo.size.width, height: geo.size.height)
          }
          .ignoresSafeArea()
        }
        .statusBarHidden(false)
    }
}

#Preview { ContentView() }
