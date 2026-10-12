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
        VStack(spacing: 12) {
            Text(Self.timeFormatter.string(from: now))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)

            VStack(spacing: 6) {
                Text(Self.dateFormatter.string(from: now))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.75))
                Text("🥜 Peanut")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 9)
        .background(alignment: .top) {
            UnevenRoundedRectangle(bottomLeadingRadius: 14, bottomTrailingRadius: 14, style: .continuous)
                .fill(Color.black)
                .ignoresSafeArea()
        }
        .onReceive(timer) { now = $0 }
        .onHover { hovering in onHoverChange(hovering) }
    }
}
