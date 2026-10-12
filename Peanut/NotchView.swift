import AppKit
import Combine
import SwiftUI

/// The notch UI, drawn inside a fixed-size canvas window. The surface itself is
/// sized by `layout` and springs between compact (notch + wings) and expanded
/// (dashboard) — Sapphire uses .spring(response: 0.4, dampingFraction: 0.55).
struct NotchView: View {
    var onBandTap: () -> Void = {}

    @EnvironmentObject var layout: NotchLayoutState
    @EnvironmentObject var weather: WeatherService
    @EnvironmentObject var calendarService: CalendarService
    @EnvironmentObject var battery: BatteryService

    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// Sapphire's expansion curve: noticeable overshoot, quick settle.
    private static let expansionAnimation = Animation.spring(response: 0.4, dampingFraction: 0.55, blendDuration: 0)

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
            // Always-tappable strip across the notch band; the wing content
            // (which fades out when expanded) sits on top of it.
            ZStack(alignment: .top) {
                Color.clear.frame(height: layout.compactHeight)
                notchBand
            }
            .frame(height: layout.compactHeight)
            .contentShape(Rectangle())
            .onTapGesture { onBandTap() }
            if layout.expanded {
                expandedCards
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 16)
                    .transition(.opacity)
            }
        }
        .clipped()
        .frame(width: layout.expanded ? layout.expandedWidth : layout.compactWidth,
               height: layout.expanded ? layout.expandedHeight : layout.compactHeight)
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                NotchPillShape(bottomRadius: layout.expanded ? 28 : 12).fill(Color.black)
                NotchPillShape(bottomRadius: layout.expanded ? 28 : 12).stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            }
            .ignoresSafeArea()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(Self.expansionAnimation, value: layout.expanded)
        .onReceive(timer) { now = $0 }
    }

    // MARK: - Compact band (side wings beside the notch)

    /// The notch center is the camera housing; all band content lives in the
    /// narrow wings flanking it — temperature on the left, battery on the right.
    private var notchBand: some View {
        HStack(spacing: 0) {
            temperatureWing
                .frame(width: layout.sideInset)
            Spacer(minLength: 0)
            batteryWing
                .frame(width: layout.sideInset)
        }
        .padding(.horizontal, 2)
        .frame(height: layout.compactHeight)
        .opacity(bandOpacity)
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

    /// Wings vanish (crossfade) once the dashboard takes over the surface.
    private var bandOpacity: Double { layout.expanded ? 0 : 1 }

    // MARK: - Expanded dashboard

    private var expandedCards: some View {
        HStack(alignment: .top, spacing: 12) {
            clockCard
                .frame(width: 150)
            weatherCard
            calendarCard
                .frame(width: 230)
        }
        .frame(height: 150)
    }

    private var clockCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("现在")
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.timeFormatter.string(from: now))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white)
                Text(Self.dateLongFormatter.string(from: now))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.6))
            }
            Spacer(minLength: 6)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: batterySymbol)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(battery.charging ? Color.green : Color.white.opacity(0.85))
                    Text(battery.level.map { "\($0)%" } ?? "--")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.white)
                    if battery.charging {
                        Text("充电中")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.green)
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
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.06)))
    }

    private var weatherCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionLabel("天气")
                Spacer()
                Text(weather.place ?? "—")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .lineLimit(1)
            }
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: weather.snapshot?.conditionSymbol ?? "cloud.sun")
                    .font(.system(size: 30))
                    .foregroundStyle(Color.white)
                    .frame(width: 40)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(weather.snapshot.map { "\($0.temperature)" } ?? "--")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("°")
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.6))
                }
                .fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(weather.snapshot?.conditionText ?? weather.state.stateText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.8))
                        .fixedSize(horizontal: true, vertical: false)
                    if let snapshot = weather.snapshot {
                        HStack(spacing: 8) {
                            Text("H \(snapshot.high)°").foregroundStyle(Color.white.opacity(0.55))
                            Text("L \(snapshot.low)°").foregroundStyle(Color.white.opacity(0.55))
                        }
                        .font(.system(size: 11, design: .rounded))
                        .monospacedDigit()
                        .fixedSize(horizontal: true, vertical: false)
                    }
                }
                Spacer(minLength: 0)
            }
            if weather.state == .failed || weather.state == .denied {
                HStack {
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
                    .foregroundStyle(Color.white.opacity(0.7))
                    .buttonStyle(.plain)
                    Spacer()
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.06)))
    }

    private var calendarCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("日历")
            if calendarService.authorized == true {
                if calendarService.events.isEmpty {
                    Text("今天没有更多安排")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .padding(.top, 4)
                    Spacer(minLength: 0)
                } else {
                    VStack(spacing: 0) {
                        ForEach(calendarService.events.prefix(3)) { event in
                            HStack(spacing: 8) {
                                Text(event.isAllDay ? "全天" : Self.eventTimeFormatter.string(from: event.start))
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(Color.white.opacity(0.55))
                                    .frame(width: 40, alignment: .leading)
                                Circle().fill(Color(red: 0.96, green: 0.78, blue: 0.29)).frame(width: 5, height: 5)
                                Text(event.title)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.white)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .frame(height: 28)
                        }
                    }
                    Spacer(minLength: 0)
                }
            } else if calendarService.authorized == false {
                Button("点击授权日历访问") { calendarService.requestAndLoad() }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                Spacer(minLength: 0)
            } else {
                Text("正在请求日历权限…")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .padding(.top, 4)
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.06)))
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.45))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.white.opacity(0.08)))
    }

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

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

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
