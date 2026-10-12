import Combine
import SwiftUI

/// The compact band: the physical notch stays pure black; the glanceable
/// values (temperature / battery) live in the narrow wings flanking it.
struct NotchView: View {
    @EnvironmentObject var layout: NotchLayoutState
    @EnvironmentObject var weather: WeatherService
    @EnvironmentObject var battery: BatteryService

    var body: some View {
        HStack(spacing: 0) {
            temperatureWing
                .frame(width: layout.sideInset)
            Spacer(minLength: 0)
            batteryWing
                .frame(width: layout.sideInset)
        }
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                NotchPillShape(bottomRadius: 12).fill(Color.black)
                NotchPillShape(bottomRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            }
            .ignoresSafeArea()
        }
    }

    private var temperatureWing: some View {
        HStack(spacing: 2) {
            Spacer(minLength: 0)
            if let snapshot = weather.snapshot {
                Text("\(snapshot.temperature)°")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.92))
                    .fixedSize(horizontal: true, vertical: false)
            } else {
                Image(systemName: weather.state == .denied ? "location.slash" : "location")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.white.opacity(0.3))
            }
        }
        .padding(.trailing, 8)
    }

    private var batteryWing: some View {
        HStack(spacing: 2) {
            if battery.charging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.green)
            }
            Text(battery.level.map { "\($0)%" } ?? "--%")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(0.92))
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 0)
        }
        .padding(.leading, 10)
    }
}

/// Sapphire-style notch silhouette: flat top edge, generously rounded bottom.
struct NotchPillShape: Shape {
    var bottomRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(bottomRadius, rect.width / 2, rect.height)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.maxY),
                          control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY - radius),
                          control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
