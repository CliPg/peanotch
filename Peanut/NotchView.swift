import Combine
import SwiftUI

struct NotchView: View {
    var onHoverChange: (Bool) -> Void

    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            // The clock sits within the menu-bar band (32pt on notch MacBooks).
            Text(Self.timeFormatter.string(from: now))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(height: 32)

            // Extra content revealed when the window expands on hover.
            VStack(spacing: 6) {
                Text(Self.dateFormatter.string(from: now))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.75))
                Text("🥜 Peanut")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(.top, 8)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(alignment: .top) {
            UnevenRoundedRectangle(bottomLeadingRadius: 16, bottomTrailingRadius: 16, style: .continuous)
                .fill(Color.black)
                .overlay(
                    UnevenRoundedRectangle(bottomLeadingRadius: 16, bottomTrailingRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                )
                .ignoresSafeArea()
        }
        .onReceive(timer) { now = $0 }
        .onHover { hovering in onHoverChange(hovering) }
    }
}
