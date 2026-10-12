import Combine
import SwiftUI

/// The notch UI: a compact pill (temp · clock · battery) that expands into a
/// Sapphire-style dashboard (weather / battery / calendar) on hover.
struct NotchView: View {
    var onHoverChange: (Bool) -> Void

    @EnvironmentObject var weather: WeatherService
    @EnvironmentObject var calendarService: CalendarService
    @EnvironmentObject var battery: BatteryService

    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let dateLongFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter
    }()

    private static let eventTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            compactBar
                .frame(height: 32)

            expandedContent
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                NotchPillShape(bottomRadius: 26).fill(Color.black)
                NotchPillShape(bottomRadius: 26).stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            }
            .ignoresSafeArea()
        }
        .onReceive(timer) { now = $0 }
        .onHover { hovering in onHoverChange(hovering) }
    }

    // MARK: - Compact (inside the menu-bar band)

    private var compactBar: some View {
        HStack(spacing: 0) {
            // Weather teaser on the left of the notch
            Group {
                if let snapshot = weather.snapshot {
                    Image(systemName: snapshot.conditionSymbol)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.85))
                    Text("\(snapshot.temperature)°")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.white.opacity(0.85))
                        .padding(.leading, 3)
                } else {
                    Image(systemName: "location")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.white.opacity(0.35))
                }
            }
            .frame(width: 56, alignment: .trailing)

            Spacer()

            Text(Self.timeFormatter.string(from: now))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)

            Spacer()

            // Battery teaser on the right of the notch
            Group {
                Text(battery.level.map { "\($0)" } ?? "--")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.85))
                Image(systemName: batterySymbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(battery.charging ? Color.green : Color.white.opacity(0.85))
                    .padding(.leading, 3)
            }
            .frame(width: 56, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .opacity(compactBarOpacity)
    }

    /// The compact bar content sits beside the physical notch; hide it while
    /// expanded so the dashboard owns the whole surface.
    private var compactBarOpacity: Double { 1 }

    private var batterySymbol: String {
        guard let level = battery.level else { return "battery.0" }
        if battery.charging { return "battery.100.bolt" }
        switch level {
        case 90...: return "battery.100"
        case 65...: return "battery.75"
        case 40...: return "battery.50"
        case 15...: return "battery.25"
        default: return "battery.0"
        }
    }

    // MARK: - Expanded dashboard

    private var expandedContent: some View {
        VStack(spacing: 12) {
            header
            weatherCard
            batteryCard
            calendarCard
        }
    }

    private var header: some View {
        HStack {
            Text(Self.dateLongFormatter.string(from: now))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            Text(weather.place ?? (weather.state == .denied ? "未授权定位" : "定位中…"))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
        }
        .padding(.horizontal, 2)
    }

    private var weatherCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("天气")
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: weather.snapshot?.conditionSymbol ?? "cloud.sun")
                    .font(.system(size: 34, weight: .regular))
                    .foregroundStyle(.white)
                    .frame(width: 44)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(weather.snapshot.map { "\($0.temperature)" } ?? "--")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text("°")
                            .font(.system(size: 20, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(weather.snapshot?.conditionText ?? weather.state.stateText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                    if let snapshot = weather.snapshot {
                        HStack(spacing: 8) {
                            Text("H \(snapshot.high)°").foregroundStyle(.white.opacity(0.55))
                            Text("L \(snapshot.low)°").foregroundStyle(.white.opacity(0.55))
                        }
                        .font(.system(size: 11, design: .rounded))
                        .monospacedDigit()
                    }
                }
            }
            if weather.state == .failed || weather.state == .denied {
                Button(weather.state == .denied ? "去系统设置开启定位" : "重试") {
                    if weather.state == .denied {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Location") {
                            NSWorkspace.shared.open(url)
                        }
                    } else {
                        weather.retry()
                    }
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.06)))
    }

    private var batteryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("电量")
            HStack(spacing: 10) {
                Image(systemName: batterySymbol)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(battery.charging ? Color.green : .white)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(battery.level.map { "\($0)" } ?? "--")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text("%")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.5))
                        if battery.charging {
                            Text("· 正在充电")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.green)
                        }
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.15))
                            Capsule()
                                .fill(battery.charging ? Color.green : Color.white.opacity(0.85))
                                .frame(width: proxy.size.width * (battery.level.map { Double($0) / 100 } ?? 0))
                        }
                    }
                    .frame(height: 4)
                }
                Spacer()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.06)))
    }

    private var calendarCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("日历")
            if calendarService.authorized == true {
                if calendarService.events.isEmpty {
                    Text("今天没有更多安排")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.vertical, 4)
                } else {
                    VStack(spacing: 0) {
                        ForEach(calendarService.events) { event in
                            HStack(spacing: 10) {
                                Text(event.isAllDay ? "全天" : Self.eventTimeFormatter.string(from: event.start))
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(.white.opacity(0.55))
                                    .frame(width: 44, alignment: .leading)
                                Circle().fill(Color(red: 0.96, green: 0.78, blue: 0.29)).frame(width: 5, height: 5)
                                Text(event.title)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(.vertical, 5)
                            if event.id != calendarService.events.last?.id {
                                Rectangle().fill(Color.white.opacity(0.07)).frame(height: 0.5)
                            }
                        }
                    }
                }
            } else if calendarService.authorized == false {
                Button("点击授权日历访问") { calendarService.requestAndLoad() }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
            } else {
                Text("正在请求日历权限…")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.vertical, 4)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.06)))
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white.opacity(0.45))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.white.opacity(0.08)))
    }
}

extension WeatherService.LoadState {
    var stateText: String {
        switch self {
        case .idle, .locating: return "定位中…"
        case .loading: return "加载中…"
        case .ready: return ""
        case .denied: return "未授权"
        case .failed: return "获取失败"
        }
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
