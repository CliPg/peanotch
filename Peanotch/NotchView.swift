import AppKit
import Combine
import SwiftUI

/// The notch UI, drawn inside a fixed-size canvas window. The surface itself is
/// sized by `layout` and springs between compact (notch + wings) and expanded
/// (dashboard) — Sapphire uses .spring(response: 0.4, dampingFraction: 0.55).
struct NotchView: View {
    var onBandTap: () -> Void = {}
    var onEditCountdowns: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    var onOpenCalendar: () -> Void = {}
    var onCloseCalendar: () -> Void = {}

    @EnvironmentObject var layout: NotchLayoutState
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var weather: WeatherService
    @EnvironmentObject var calendarService: CalendarService
    @EnvironmentObject var battery: BatteryService
    @EnvironmentObject var countdowns: CountdownService
    @EnvironmentObject var reminderService: ReminderService
    @EnvironmentObject var systemStats: SystemStatsService
    @EnvironmentObject var airPods: AirPodsBatteryService

    @State private var now = Date()
    @State private var newReminderTitle = ""
    @State private var calendarMonthAnchor = Calendar.current.startOfDay(for: Date())
    @State private var calendarDayCounts: [Int: Int] = [:]
    @State private var calendarNewReminderTitle = ""
    @State private var editingCountdownId: UUID?
    @FocusState private var focusedCountdownId: UUID?
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// Sapphire's expansion curve: noticeable overshoot, quick settle.
    private static let expansionAnimation = Animation.spring(response: 0.4, dampingFraction: 0.55, blendDuration: 0)

    private var isEnglish: Bool { settings.resolvedLanguage == "en" }
    private var localeIdentifier: String { isEnglish ? "en_US" : "zh_CN" }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: localeIdentifier)
        formatter.dateFormat = settings.clock24h ? "HH:mm" : "h:mm a"
        return formatter.string(from: date)
    }

    private var longDateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: localeIdentifier)
        formatter.dateFormat = isEnglish ? "EEE, MMM d" : "M月d日 EEEE"
        return formatter.string(from: now)
    }

    /// Celsius -> display unit.
    private func displayTemp(_ celsius: Int) -> Int {
        settings.tempUnit == "f" ? Int((Double(celsius) * 9 / 5 + 32).rounded()) : celsius
    }

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
            .overlay(alignment: .topLeading) {
                if layout.expanded && !layout.calendarMode {
                    Button(action: onOpenSettings) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.white.opacity(0.45))
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 10)
                    .padding(.top, 9)
                } else if layout.expanded && layout.calendarMode {
                    Button(action: onCloseCalendar) {
                        Image(systemName: "chevron.left.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 10)
                    .padding(.top, 8)
                }
            }
            if layout.expanded {
                if layout.calendarMode {
                    fullCalendarSection
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, 14)
                        .transition(.opacity)
                } else {
                    expandedCards
                        .padding(.horizontal, 14)
                        .padding(.top, 10)
                        .padding(.bottom, 16)
                        .transition(.opacity)
                }
            }
        }
        .clipped()
        .frame(width: surfaceWidth, height: surfaceHeight)
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                NotchPillShape(bottomRadius: layout.expanded ? 28 : 12).fill(Color.black)
                NotchPillShape(bottomRadius: layout.expanded ? 28 : 12).stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            }
            .ignoresSafeArea()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(Self.expansionAnimation, value: layout.expanded)
        .animation(Self.expansionAnimation, value: layout.calendarMode)
        .onReceive(timer) { now = $0 }
        .onChange(of: calendarService.selectedDate) { newDate in
            reminderService.load(for: newDate)
        }
        .onChange(of: focusedCountdownId) { focused in
            if focused == nil { editingCountdownId = nil }
        }
        .onChange(of: layout.expanded) { expanded in
            if !expanded { editingCountdownId = nil }
        }
        .onChange(of: layout.calendarMode) { on in
            if on { loadCalendarMarkers() }
        }
        .onChange(of: layout.monthShift) { shift in
            guard shift != 0 else { return }
            calendarShiftMonth(shift)
            layout.monthShift = 0
        }
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
                Text("\(displayTemp(snapshot.temperature))°")
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

    private var surfaceWidth: CGFloat {
        if !layout.expanded { return layout.compactWidth }
        return layout.calendarMode ? layout.calendarWidth : layout.expandedWidth
    }

    private var surfaceHeight: CGFloat {
        if !layout.expanded { return layout.compactHeight }
        return layout.calendarMode ? layout.calendarHeight : layout.expandedHeight
    }

    // MARK: - Full calendar (in-notch)

    private var calendarCalculator: Calendar { Calendar.current }

    private var fullCalendarSection: some View {
        VStack(spacing: 8) {
            calendarNav
            calendarWeekdayRow
            calendarGrid
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5)
            calendarSchedule
            calendarComposer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var calendarMonthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: isEnglish ? "en_US" : "zh_CN")
        formatter.dateFormat = isEnglish ? "MMMM yyyy" : "yyyy年M月"
        return formatter.string(from: calendarMonthAnchor)
    }

    private func calendarShiftMonth(_ delta: Int) {
        if let shifted = calendarCalculator.date(byAdding: .month, value: delta, to: calendarMonthAnchor) {
            calendarMonthAnchor = calendarCalculator.startOfDay(for: shifted)
            loadCalendarMarkers()
            Diagnostics.record("calendar: month shift \(delta) -> \(calendarMonthAnchor)")
        }
    }

    private var calendarNav: some View {
        HStack(spacing: 4) {
            Button { calendarShiftMonth(-1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Text(calendarMonthTitle)
                .font(.system(size: 13, weight: .bold))
                .frame(width: 120)
            Button { calendarShiftMonth(1) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer()
            Text(Self.dayTitleFormatter.string(from: calendarService.selectedDate))
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.4))
        }
    }

    private static let dayTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter
    }()

    private var calendarWeekdayRow: some View {
        let symbols = isEnglish ? ["S", "M", "T", "W", "T", "F", "S"] : ["日", "一", "二", "三", "四", "五", "六"]
        return HStack(spacing: 3) {
            ForEach(Array(symbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.system(size: 9))
                    .foregroundStyle(Color.white.opacity(0.4))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var calendarCells: [Date?] {
        let calendar = calendarCalculator
        let components = calendar.dateComponents([.year, .month], from: calendarMonthAnchor)
        guard let first = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: first) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: first)
        var cells: [Date?] = Array(repeating: nil, count: firstWeekday - 1)
        for day in range {
            cells.append(calendar.date(byAdding: .day, value: day - 1, to: first))
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }

    private var calendarGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7), spacing: 2) {
            ForEach(Array(calendarCells.enumerated()), id: \.offset) { _, date in
                if let date {
                    calendarDayCell(date)
                } else {
                    Color.clear.frame(minHeight: 34)
                }
            }
        }
    }

    private func calendarDayCell(_ date: Date) -> some View {
        let calendar = calendarCalculator
        let isToday = calendar.isDateInToday(date)
        let isSelected = calendar.isDate(date, inSameDayAs: calendarService.selectedDate)
        let hasItems = (calendarDayCounts[calendar.component(.day, from: date)] ?? 0) > 0
        return Button(action: { calendarSelectDay(date) }) {
            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 12, weight: isSelected || isToday ? .semibold : .regular, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isToday ? Color(red: 0.96, green: 0.78, blue: 0.29)
                                             : (isSelected ? Color.white : Color.white.opacity(0.8)))
                Circle()
                    .fill(hasItems ? Color(red: 0.96, green: 0.78, blue: 0.29) : Color.clear)
                    .frame(width: 3, height: 3)
            }
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(Capsule().fill(isSelected ? Color.white.opacity(0.16) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func calendarSelectDay(_ date: Date) {
        calendarService.selectDay(date)
        reminderService.load(for: date)
    }

    private func loadCalendarMarkers() {
        let calendar = calendarCalculator
        let components = calendar.dateComponents([.year, .month], from: calendarMonthAnchor)
        guard let monthStart = calendar.date(from: components) else { return }
        var counts = calendarService.eventDayCounts(monthStart: monthStart)
        reminderService.reminderDayCounts(monthStart: monthStart) { reminderCounts in
            for (day, count) in reminderCounts {
                counts[day, default: 0] += count
            }
            self.calendarDayCounts = counts
        }
    }

    private var calendarSchedule: some View {
        VStack(alignment: .leading, spacing: 4) {
            if scheduleItems.isEmpty {
                Text(calendarCalculator.isDateInToday(calendarService.selectedDate)
                     ? L10n.t("今天没有安排", "Nothing scheduled today")
                     : L10n.t("这天没有安排", "Nothing scheduled"))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .padding(.vertical, 2)
            } else {
                ForEach(scheduleItems) { item in
                    HStack(spacing: 8) {
                        if let reminder = item.reminder {
                            Button {
                                reminderService.toggleComplete(reminder)
                            } label: {
                                Image(systemName: "circle")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.white.opacity(0.55))
                            }
                            .buttonStyle(.plain)
                        } else {
                            Circle().fill(Color(red: 0.96, green: 0.78, blue: 0.29)).frame(width: 5, height: 5)
                        }
                        Group {
                            if item.untimed {
                                Text(item.reminder != nil ? L10n.t("待办", "To-do") : L10n.t("全天", "All-day"))
                            } else if let time = item.time {
                                Text(formattedTime(time))
                            } else {
                                Text("")
                            }
                        }
                        .font(.system(size: 10, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.white.opacity(0.5))
                        .frame(width: 40, alignment: .leading)
                        Text(item.title)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.white)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .frame(height: 22)
                }
            }
        }
    }

    private var calendarComposer: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.45))
            TextField(calendarComposerPlaceholder, text: $calendarNewReminderTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Color.white)
                .onSubmit(createCalendarReminder)
            Button(L10n.t("添加", "Add"), action: createCalendarReminder)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.06)))
    }

    private var calendarComposerPlaceholder: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: isEnglish ? "en_US" : "zh_CN")
        formatter.dateFormat = isEnglish ? "MMM d" : "M月d日"
        let day = formatter.string(from: calendarService.selectedDate)
        return L10n.t("在\(day)新建提醒…", "New reminder on \(day)…")
    }

    private func createCalendarReminder() {
        let trimmed = calendarNewReminderTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        reminderService.create(title: trimmed, for: calendarService.selectedDate)
        calendarNewReminderTitle = ""
        loadCalendarMarkers()
    }

    // MARK: - Expanded dashboard

    private var expandedCards: some View {
        HStack(alignment: .top, spacing: 12) {
            clockCard
                .frame(width: 150)
            weatherCard
            calendarCard
                .frame(width: 230)
            countdownCard
                .frame(width: 210)
            systemCard
                .frame(width: 195)
        }
        .frame(height: 235)
    }

    // MARK: - System card (内存 / 硬盘)

    private var systemCard: some View {
        let snapshot = systemStats.snapshot
        return VStack(alignment: .leading, spacing: 8) {
            sectionLabel(L10n.t("系统", "System"))
            statRow(icon: "cpu",
                    label: "CPU",
                    value: "\(Int(snapshot.cpuUsage * 100))%",
                    fraction: snapshot.cpuUsage)
            statRow(icon: "memorychip",
                    label: L10n.t("内存", "Memory"),
                    value: "\(Self.gigabytes(snapshot.memoryUsedBytes)) / \(Self.gigabytes(snapshot.memoryTotalBytes))",
                    fraction: Self.fraction(snapshot.memoryUsedBytes, total: snapshot.memoryTotalBytes))
            statRow(icon: "internaldrive",
                    label: L10n.t("硬盘", "Disk"),
                    value: "\(Self.gigabytes(snapshot.diskUsedBytes)) / \(Self.gigabytes(snapshot.diskTotalBytes))",
                    fraction: Self.fraction(snapshot.diskUsedBytes, total: snapshot.diskTotalBytes))
            statRow(icon: "arrow.up.arrow.down",
                    label: L10n.t("网络", "Network"),
                    value: "↓\(Self.speed(snapshot.netDownBytesPerSec)) ↑\(Self.speed(snapshot.netUpBytesPerSec))",
                    fraction: nil)
            if snapshot.batteryHealthPercent > 0 {
                statRow(icon: "bolt.batteryblock",
                        label: L10n.t("电池健康", "Battery Health"),
                        value: snapshot.batteryCycleCount > 0
                            ? "\(snapshot.batteryHealthPercent)% · \(snapshot.batteryCycleCount)\(L10n.t("循环", " cycles"))"
                            : "\(snapshot.batteryHealthPercent)%",
                        fraction: Double(snapshot.batteryHealthPercent) / 100,
                        barColor: snapshot.batteryHealthPercent >= 80 ? Color.green
                            : (snapshot.batteryHealthPercent >= 60 ? Color(red: 0.96, green: 0.78, blue: 0.29)
                                                                  : Color(red: 1.0, green: 0.42, blue: 0.24)))
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.06)))
    }

    private func statRow(icon: String, label: String, value: String, fraction: Double?, barColor: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.7))
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.85))
                Spacer(minLength: 4)
                Text(value)
                    .font(.system(size: 10, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.5))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            if let fraction {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.15))
                        Capsule()
                            .fill(barColor ?? Self.usageColor(fraction))
                            .frame(width: proxy.size.width * fraction)
                    }
                }
                .frame(height: 4)
            }
        }
    }

    private static func fraction(_ used: Int64, total: Int64) -> Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(used) / Double(total)))
    }

    private static func usageColor(_ ratio: Double) -> Color {
        if ratio > 0.9 { return Color(red: 1.0, green: 0.42, blue: 0.24) }
        if ratio > 0.75 { return Color(red: 0.96, green: 0.78, blue: 0.29) }
        return Color.white.opacity(0.85)
    }

    private static func speed(_ bytesPerSec: Int64) -> String {
        let bytes = Double(bytesPerSec)
        if bytes >= 1_000_000 { return String(format: "%.1fM", bytes / 1_000_000) }
        if bytes >= 1_000 { return String(format: "%.0fK", bytes / 1_000) }
        return String(format: "%.0fB", bytes)
    }

    private static func gigabytes(_ bytes: Int64) -> String {
        String(format: "%.0fG", Double(bytes) / 1_000_000_000)
    }

    private var clockCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(L10n.t("现在", "Now"))
            VStack(alignment: .leading, spacing: 2) {
                Text(formattedTime(now))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white)
                Text(longDateText)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.6))
            }
            Spacer(minLength: 6)
            airPodsRows
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: batterySymbol)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(battery.charging ? Color.green : Color.white.opacity(0.5))
                    Text(L10n.t("电池", "Battery"))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.55))
                    Spacer(minLength: 2)
                    Text(battery.level.map { "\($0)%" } ?? "--")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.white)
                    if battery.charging {
                        Text(L10n.t("充电中", "Charging"))
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

    // MARK: AirPods battery (single row + bar)

    @ViewBuilder
    private var airPodsRows: some View {
        if let device = airPods.device {
            let level = device.left.flatMap { left in device.right.map { min(left, $0) } }
                ?? device.left ?? device.right ?? device.single
            if let level {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Image(systemName: "airpodspro")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.white.opacity(0.5))
                        Text("AirPods")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.white.opacity(0.55))
                        Spacer(minLength: 2)
                        Text("\(level)%")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Color.white)
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.15))
                            Capsule()
                                .fill(Self.batteryLevelColor(level))
                                .frame(width: proxy.size.width * Double(level) / 100)
                        }
                    }
                    .frame(height: 4)
                }
                .padding(.bottom, 5)
            }
        }
    }

    /// Low charge warns: white normally, amber <= 25%, red <= 15%.
    private static func batteryLevelColor(_ level: Int) -> Color {
        if level <= 15 { return Color(red: 1.0, green: 0.42, blue: 0.24) }
        if level <= 25 { return Color(red: 0.96, green: 0.78, blue: 0.29) }
        return Color.white.opacity(0.85)
    }

    private var weatherCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionLabel(L10n.t("天气", "Weather"))
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
                    Text(weather.snapshot.map { String(displayTemp($0.temperature)) } ?? "--")
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
                            Text("H \(displayTemp(snapshot.high))°").foregroundStyle(Color.white.opacity(0.55))
                            Text("L \(displayTemp(snapshot.low))°").foregroundStyle(Color.white.opacity(0.55))
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
                    Button(weather.state == .denied ? L10n.t("去系统设置开启定位", "Enable location in Settings") : L10n.t("重试", "Retry")) {
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
            Button(action: onOpenCalendar) {
                HStack {
                    sectionLabel(L10n.t("日历", "Calendar"))
                    Spacer()
                    Text(monthText)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.white.opacity(0.45))
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 8))
                        .foregroundStyle(Color.white.opacity(0.35))
                }
            }
            .buttonStyle(.plain)
            dayStrip
            if calendarService.authorized == true {
                if scheduleItems.isEmpty {
                    Text(Calendar.current.isDateInToday(calendarService.selectedDate) ? L10n.t("今天没有安排", "Nothing scheduled today") : L10n.t("这天没有安排", "Nothing scheduled"))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .padding(.top, 2)
                    Spacer(minLength: 0)
                } else {
                    VStack(spacing: 0) {
                        ForEach(scheduleItems) { item in
                            scheduleRow(item)
                        }
                    }
                    Spacer(minLength: 0)
                }
            } else if calendarService.authorized == false {
                Button(L10n.t("点击授权日历访问", "Grant calendar access")) { calendarService.requestAndLoad() }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                Spacer(minLength: 0)
            } else {
                Text(L10n.t("正在请求日历权限…", "Requesting calendar access…"))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .padding(.top, 2)
                Spacer(minLength: 0)
            }
            if reminderService.authorized == true {
                newReminderRow
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.06)))
    }

    /// Inline composer: type a title, hit Return, creates a reminder for the
    /// selected day.
    private var newReminderRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus.circle")
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.4))
            TextField(L10n.t("新建待办…", "New to-do…"), text: $newReminderTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Color.white)
                .onSubmit(createReminder)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.06)))
    }

    private func createReminder() {
        let trimmed = newReminderTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        reminderService.create(title: trimmed, for: calendarService.selectedDate)
        newReminderTitle = ""
    }

    // MARK: Unified day schedule (events + reminders, Sapphire-style)

    private struct ScheduleItem: Identifiable {
        let id: String
        let title: String
        let time: Date?
        let untimed: Bool
        let reminder: ReminderService.Reminder?
    }

    /// Events and reminders for the selected day, merged and time-sorted
    /// (untimed items last), like Sapphire's calendar detail.
    private var scheduleItems: [ScheduleItem] {
        var items: [ScheduleItem] = []
        for event in calendarService.events.prefix(3) {
            items.append(ScheduleItem(id: "event:\(event.id)", title: event.title,
                                      time: event.start, untimed: event.isAllDay, reminder: nil))
        }
        if reminderService.authorized == true {
            for reminder in reminderService.reminders {
                items.append(ScheduleItem(id: "reminder:\(reminder.id)", title: reminder.title,
                                          time: reminder.due, untimed: !reminder.hasTime, reminder: reminder))
            }
        }
        items.sort {
            switch ($0.time, $1.time) {
            case let (a?, b?): return a < b
            case (_?, nil): return true
            case (nil, _?): return false
            default: return false
            }
        }
        return Array(items.prefix(4))
    }

    private func scheduleRow(_ item: ScheduleItem) -> some View {
        HStack(spacing: 8) {
            if let reminder = item.reminder {
                Button {
                    reminderService.toggleComplete(reminder)
                } label: {
                    Image(systemName: "circle")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
                .buttonStyle(.plain)
            } else {
                Circle().fill(Color(red: 0.96, green: 0.78, blue: 0.29)).frame(width: 5, height: 5)
            }
            Group {
                if item.untimed {
                    Text(item.reminder != nil ? L10n.t("待办", "To-do") : L10n.t("全天", "All-day"))
                } else if let time = item.time {
                    Text(formattedTime(time))
                } else {
                    Text("")
                }
            }
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Color.white.opacity(0.55))
            .frame(width: 40, alignment: .leading)
            Text(item.title)
                .font(.system(size: 12))
                .foregroundStyle(Color.white)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(height: 26)
    }

    // MARK: Day strip (最近几天 + 星期几, 可点选)

    private var monthText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: localeIdentifier)
        formatter.dateFormat = isEnglish ? "MMM" : "M月"
        return formatter.string(from: calendarService.selectedDate)
    }

    private var weekdaySymbols: [String] { isEnglish ? ["S", "M", "T", "W", "T", "F", "S"] : ["日", "一", "二", "三", "四", "五", "六"] }

    /// Fixed Sun→Sat order: the calendar week containing today.
    private var upcomingDays: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today) // 1 = Sunday
        let sunday = calendar.date(byAdding: .day, value: -(weekday - 1), to: today) ?? today
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: sunday) }
    }

    private var dayStrip: some View {
        HStack(spacing: 3) {
            ForEach(upcomingDays, id: \.self) { day in
                dayChip(day)
            }
        }
    }

    private func dayChip(_ day: Date) -> some View {
        let calendar = Calendar.current
        let weekdayIndex = calendar.component(.weekday, from: day) - 1
        let isSelected = calendar.isDate(day, inSameDayAs: calendarService.selectedDate)
        let isToday = calendar.isDateInToday(day)
        let isPast = day < calendar.startOfDay(for: Date())
        let numberColor: Color = isPast ? Color.white.opacity(0.3)
            : (isSelected ? Color.white : Color.white.opacity(0.85))
        return VStack(spacing: 1) {
            Text(weekdaySymbols[weekdayIndex])
                .font(.system(size: 9))
                .foregroundStyle(isToday ? Color(red: 0.96, green: 0.78, blue: 0.29)
                                         : Color.white.opacity(isSelected ? 0.75 : (isPast ? 0.25 : 0.4)))
            Text("\(calendar.component(.day, from: day))")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(numberColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(Capsule().fill(isSelected ? Color.white.opacity(0.16) : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture { calendarService.selectDay(day) }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.45))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.white.opacity(0.08)))
    }

    // MARK: - Countdown card (重要日子倒计时)

    private var countdownCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionLabel(L10n.t("倒计时", "Countdown"))
                Spacer()
                Button(action: onEditCountdowns) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            if countdowns.sortedUpcoming.isEmpty {
                Button(L10n.t("添加重要日子", "Add important days")) { onEditCountdowns() }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                Spacer(minLength: 0)
            } else {
                VStack(spacing: 0) {
                    let nearestUpcomingId = countdowns.sortedUpcoming
                        .first { countdowns.daysRemaining(for: $0) >= 0 }?.id
                    ForEach(countdowns.sortedUpcoming.prefix(3)) { countdown in
                        countdownRow(countdown, highlight: countdown.id == nearestUpcomingId)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.06)))
    }

    /// Live-saving title binding for inline editing in the dashboard card.
    private func countdownTitleBinding(_ countdown: Countdown) -> Binding<String> {
        Binding(
            get: { countdowns.countdowns.first(where: { $0.id == countdown.id })?.title ?? "" },
            set: { newValue in countdowns.update(id: countdown.id) { $0.title = newValue } }
        )
    }

    private func countdownRow(_ countdown: Countdown, highlight: Bool) -> some View {
        let days = countdowns.daysRemaining(for: countdown)
        let isPast = days < 0
        let numberColor: Color = isPast ? Color.white.opacity(0.35)
            : (highlight ? Color(red: 0.96, green: 0.78, blue: 0.29) : Color.white)
        return HStack(spacing: 10) {
            VStack(alignment: .trailing, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(abs(days))")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(numberColor)
                    Text("天")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.white.opacity(0.45))
                }
                Text(isPast ? L10n.t("已过", "ago") : L10n.t("还剩", "left"))
                    .font(.system(size: 9))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
            .frame(width: 56, alignment: .trailing)
            Rectangle().fill(Color.white.opacity(0.08)).frame(width: 0.5, height: 28)
            if editingCountdownId == countdown.id {
                TextField("", text: countdownTitleBinding(countdown))
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white)
                    .focused($focusedCountdownId, equals: countdown.id)
                    .onSubmit { editingCountdownId = nil }
            } else {
                Text(countdown.title)
                    .font(.system(size: 12))
                    .foregroundStyle(isPast ? Color.white.opacity(0.5) : Color.white)
                    .lineLimit(1)
                    .onTapGesture(count: 2) {
                        editingCountdownId = countdown.id
                        DispatchQueue.main.async { focusedCountdownId = countdown.id }
                    }
            }
            Spacer(minLength: 0)
        }
        .frame(height: 38)
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
        case .idle, .locating: return L10n.t("定位中…", "Locating…")
        case .loading: return L10n.t("加载中…", "Loading…")
        case .ready: return ""
        case .denied: return L10n.t("未授权", "Denied")
        case .failed: return L10n.t("获取失败", "Failed")
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
