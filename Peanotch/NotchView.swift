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
    @EnvironmentObject var sports: SportsService

    @State private var now = Date()
    @State private var newReminderTitle = ""
    @State private var calendarMonthAnchor = Calendar.current.startOfDay(for: Date())
    @State private var lastMonthDirection = 1
    @State private var calendarDayCounts: [Int: Int] = [:]
    @State private var calendarNewReminderTitle = ""
    @State private var countdownNewTitle = ""
    @State private var countdownNewDate = Date()
    @State private var editingCountdownId: UUID?
    @FocusState private var focusedCountdownId: UUID?
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// Sapphire's expansion curve: noticeable overshoot, quick settle.
    private static let expansionAnimation = Animation.spring(response: 0.4, dampingFraction: 0.55, blendDuration: 0)

    /// One highlight color per team (brand colors, tuned to stay readable on
    /// the black surface) — used to mark days when a favorite team plays.
    /// NBA teams by their Chinese data names, CS2 teams by 5E's names.
    private static let nbaTeamColors: [String: Color] = [
        // NBA East
        "凯尔特人": Color(red: 0.00, green: 0.65, blue: 0.32),
        "篮网": Color(red: 0.62, green: 0.63, blue: 0.64),
        "尼克斯": Color(red: 0.96, green: 0.52, blue: 0.15),
        "76人": Color(red: 0.13, green: 0.50, blue: 0.90),
        "猛龙": Color(red: 0.88, green: 0.12, blue: 0.30),
        "公牛": Color(red: 0.90, green: 0.14, blue: 0.22),
        "骑士": Color(red: 0.75, green: 0.10, blue: 0.31),
        "活塞": Color(red: 0.29, green: 0.45, blue: 0.90),
        "步行者": Color(red: 0.99, green: 0.73, blue: 0.19),
        "雄鹿": Color(red: 0.20, green: 0.66, blue: 0.33),
        "老鹰": Color(red: 0.76, green: 0.83, blue: 0.18),
        "黄蜂": Color(red: 0.12, green: 0.70, blue: 0.77),
        "热火": Color(red: 0.88, green: 0.24, blue: 0.37),
        "魔术": Color(red: 0.24, green: 0.61, blue: 0.91),
        "奇才": Color(red: 0.29, green: 0.37, blue: 0.85),
        // NBA West
        "独行侠": Color(red: 0.18, green: 0.53, blue: 0.84),
        "火箭": Color(red: 0.89, green: 0.27, blue: 0.36),
        "灰熊": Color(red: 0.51, green: 0.60, blue: 0.79),
        "鹈鹕": Color(red: 0.79, green: 0.60, blue: 0.27),
        "马刺": Color(red: 0.77, green: 0.81, blue: 0.83),
        "掘金": Color(red: 1.00, green: 0.77, blue: 0.14),
        "森林狼": Color(red: 0.24, green: 0.50, blue: 0.76),
        "雷霆": Color(red: 0.18, green: 0.64, blue: 0.91),
        "开拓者": Color(red: 0.89, green: 0.27, blue: 0.27),
        "爵士": Color(red: 0.98, green: 0.63, blue: 0.11),
        "勇士": Color(red: 0.18, green: 0.37, blue: 0.79),
        "快船": Color(red: 0.84, green: 0.27, blue: 0.38),
        "湖人": Color(red: 0.99, green: 0.73, blue: 0.15),
        "太阳": Color(red: 0.94, green: 0.45, blue: 0.16),
        "国王": Color(red: 0.54, green: 0.33, blue: 0.74),
        // CS2 (5E names)
        "Vitality": Color(red: 0.98, green: 0.92, blue: 0.10),
        "MOUZ": Color(red: 0.90, green: 0.05, blue: 0.12),
        "Spirit": Color(red: 1.00, green: 0.50, blue: 0.00),
        "Falcons": Color(red: 0.00, green: 0.65, blue: 0.35),
        "Mongolz": Color(red: 0.15, green: 0.50, blue: 0.90),
        "Aurora": Color(red: 0.48, green: 0.30, blue: 0.75),
        "G2": Color(red: 0.95, green: 0.35, blue: 0.30),
        "NAVI": Color(red: 1.00, green: 0.72, blue: 0.05),
        "FURIA": Color(red: 0.90, green: 0.90, blue: 0.92),
        "Liquid": Color(red: 0.25, green: 0.40, blue: 0.95),
        "FaZe": Color(red: 0.85, green: 0.35, blue: 0.45),
        "Virtus.pro": Color(red: 0.95, green: 0.44, blue: 0.13),
        "Astralis": Color(red: 0.88, green: 0.10, blue: 0.18),
        "TYLOO": Color(red: 0.90, green: 0.15, blue: 0.25),
        "Legacy": Color(red: 0.00, green: 0.64, blue: 0.88),
        "Nemiga": Color(red: 0.60, green: 0.85, blue: 1.00),
        "MIBR": Color(red: 0.94, green: 0.30, blue: 0.20),
        "Ninjas in Pyjamas": Color(red: 0.55, green: 0.65, blue: 1.00),
        "9z": Color(red: 0.10, green: 0.70, blue: 0.75),
        "FUT": Color(red: 0.85, green: 0.45, blue: 0.55),
    ]

    private static func nbaTeamColor(_ team: String) -> Color {
        nbaTeamColors[team] ?? Color.white.opacity(0.6)
    }

    /// Favorite teams playing on `day`, in tip-off order (unique).
    private func favoriteTeamsPlaying(on day: Date) -> [String] {
        guard settings.showSportsCard, !settings.favoriteTeams.isEmpty else { return [] }
        let calendar = Calendar.current
        var seen: Set<String> = []
        var ordered: [String] = []
        for game in sports.games where calendar.isDate(game.startTime, inSameDayAs: day) {
            for team in [game.homeTeam, game.awayTeam] where settings.favoriteTeams.contains(team) {
                if seen.insert(team).inserted { ordered.append(team) }
            }
        }
        return ordered
    }

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
                if layout.expanded && !layout.calendarMode && !layout.countdownMode {
                    Button(action: onOpenSettings) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.white.opacity(0.45))
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 10)
                    .padding(.top, 9)
                } else if layout.expanded && (layout.calendarMode || layout.countdownMode) {
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
                } else if layout.countdownMode {
                    fullCountdownSection
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
        .animation(Self.expansionAnimation, value: layout.countdownMode)
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
        return (layout.calendarMode || layout.countdownMode) ? layout.calendarWidth : layout.expandedWidth
    }

    private var surfaceHeight: CGFloat {
        if !layout.expanded { return layout.compactHeight }
        return (layout.calendarMode || layout.countdownMode) ? layout.calendarHeight : layout.expandedHeight
    }

    // MARK: - Full countdown manager (in-notch)

    private var fullCountdownSection: some View {
        VStack(spacing: 10) {
            fullCountdownHeader
            ScrollView {
                VStack(spacing: 8) {
                    if countdowns.countdowns.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "calendar.badge.clock")
                                .font(.system(size: 26))
                                .foregroundStyle(Color.white.opacity(0.35))
                            Text(L10n.t("还没有重要日子", "No important days yet"))
                                .font(.system(size: 12))
                                .foregroundStyle(Color.white.opacity(0.5))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                    } else {
                        ForEach(countdowns.sortedUpcoming) { countdown in
                            fullCountdownCard(countdown)
                        }
                    }
                }
            }
            countdownComposer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var fullCountdownHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("重要日子", "Important Days"))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.white)
                Text(countdownSummary)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.45))
            }
            Spacer()
        }
    }

    private var countdownSummary: String {
        let count = countdowns.countdowns.count
        guard count > 0 else { return L10n.t("记录值得期待的日子", "Days worth looking forward to") }
        if let nearest = countdowns.sortedUpcoming.first(where: { countdowns.daysRemaining(for: $0) >= 0 }) {
            let days = countdowns.daysRemaining(for: nearest)
            return L10n.t("\(count) 个日子 · 最近还有 \(days) 天", "\(count) days · next in \(days) days")
        }
        return L10n.t("\(count) 个日子", "\(count) days")
    }

    private func fullCountdownCard(_ countdown: Countdown) -> some View {
        let days = countdowns.daysRemaining(for: countdown)
        let isPast = days < 0
        let nearestId = countdowns.sortedUpcoming.first { countdowns.daysRemaining(for: $0) >= 0 }?.id
        let isNearest = countdown.id == nearestId
        let accent = Color(red: 1.00, green: 0.72, blue: 0.30)

        return HStack(spacing: 12) {
            VStack(spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(abs(days))")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(isPast ? Color.white.opacity(0.4)
                                         : (isNearest ? accent : Color.white))
                    Text(L10n.t("天", "d"))
                        .font(.system(size: 9))
                        .foregroundStyle(Color.white.opacity(0.45))
                }
                Text(isPast ? L10n.t("已过", "ago") : L10n.t("还剩", "left"))
                    .font(.system(size: 9))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
            .frame(width: 58)

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 0.5, height: 30)

            TextField(L10n.t("名称", "Title"), text: countdownTitleBinding(countdown))
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Color.white)

            DatePicker("", selection: countdownDateBinding(countdown), displayedComponents: .date)
                .labelsHidden()
                .font(.system(size: 10))

            Button {
                countdowns.remove(countdown)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isNearest ? accent.opacity(0.09) : Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isNearest ? accent.opacity(0.45) : Color.clear, lineWidth: 1)
        )
    }

    private func countdownDateBinding(_ countdown: Countdown) -> Binding<Date> {
        Binding(
            get: { countdowns.countdowns.first(where: { $0.id == countdown.id })?.date ?? Date() },
            set: { newValue in countdowns.update(id: countdown.id) { $0.date = newValue } }
        )
    }

    private var countdownComposer: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.45))
            TextField(L10n.t("名称（如：生日、考试）", "Name (e.g. Birthday, Exam)"), text: $countdownNewTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Color.white)
                .onSubmit(addFullCountdown)
            DatePicker("", selection: $countdownNewDate, displayedComponents: .date)
                .labelsHidden()
                .font(.system(size: 10))
            Button(L10n.t("添加", "Add"), action: addFullCountdown)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.06)))
    }

    private func addFullCountdown() {
        let trimmed = countdownNewTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        countdowns.add(title: trimmed, date: countdownNewDate)
        countdownNewTitle = ""
    }

    // MARK: - Full calendar (in-notch)

    private var calendarCalculator: Calendar { Calendar.current }

    private var fullCalendarSection: some View {
        VStack(spacing: 8) {
            calendarNav
            calendarWeekdayRow
            ZStack {
                calendarGrid
                    .id(calendarMonthAnchor)
                    .transition(monthSlideTransition)
            }
            .clipped()
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
            lastMonthDirection = delta
            withAnimation(.easeInOut(duration: 0.32)) {
                calendarMonthAnchor = calendarCalculator.startOfDay(for: shifted)
            }
            loadCalendarMarkers()
            Diagnostics.record("calendar: month shift \(delta) -> \(calendarMonthAnchor)")
        }
    }

    /// Short-travel slide fused with a fade — full-width rigid slides read as
    /// cheap, so content travels ~1/8 of the width while crossfading.
    private var monthSlideTransition: AnyTransition {
        .asymmetric(
            insertion: .slideFade(offset: lastMonthDirection > 0 ? 64 : -64),
            removal: .slideFade(offset: lastMonthDirection > 0 ? -40 : 40))
    }

    private var monthTitleTransition: AnyTransition {
        .asymmetric(
            insertion: .slideFade(offset: lastMonthDirection > 0 ? 18 : -18),
            removal: .slideFade(offset: lastMonthDirection > 0 ? -12 : 12))
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
                .id(calendarMonthAnchor)
                .transition(monthTitleTransition)
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
        let favoriteTeams = favoriteTeamsPlaying(on: date)
        // A day with a single favorite team takes that team's color for the
        // date number (selection white still wins for readability).
        let numberColor: Color = isSelected ? Color.white
            : favoriteTeams.count == 1 ? Self.nbaTeamColor(favoriteTeams[0])
            : isToday ? Color(red: 0.96, green: 0.78, blue: 0.29)
            : Color.white.opacity(0.8)
        return Button(action: { calendarSelectDay(date) }) {
            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 12, weight: isSelected || isToday ? .semibold : .regular, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(numberColor)
                HStack(spacing: 2) {
                    if hasItems {
                        Circle().fill(Color(red: 0.96, green: 0.78, blue: 0.29)).frame(width: 3, height: 3)
                    }
                    ForEach(favoriteTeams.prefix(hasItems ? 2 : 3), id: \.self) { team in
                        Circle().fill(Self.nbaTeamColor(team)).frame(width: 3, height: 3)
                    }
                }
                .frame(height: 3)
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
                // Takes the space left by the fixed grid and composer; long
                // days scroll here instead of pushing the composer away.
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(scheduleItems) { item in
                            scheduleRowContent(item, compact: true)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
                    // Bounded, scrollable — a busy day never stretches the card.
                    ScrollView(.vertical) {
                        VStack(spacing: 0) {
                            ForEach(scheduleItems) { item in
                                scheduleRow(item)
                            }
                        }
                    }
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
        var game: SportsService.Game? = nil
    }

    /// Events, reminders and (if enabled) NBA games for the selected day,
    /// merged and time-sorted (untimed items last), like Sapphire's calendar
    /// detail. Games live wherever that day's schedule shows.
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
        if settings.showSportsCard {
            for game in sports.games
            where Calendar.current.isDate(game.startTime, inSameDayAs: calendarService.selectedDate)
                  && (!settings.onlyFavorites(for: game.sport) || isFavoriteGame(game)) {
                items.append(ScheduleItem(id: "game:\(game.id)", title: gameText(game),
                                          time: game.startTime, untimed: false, reminder: nil, game: game))
            }
        }
        // To-dos and events stay above games; within each group, by time.
        items.sort {
            let aIsGame = $0.game != nil
            let bIsGame = $1.game != nil
            if aIsGame != bIsGame { return !aIsGame }
            switch ($0.time, $1.time) {
            case let (a?, b?): return a < b
            case (_?, nil): return true
            case (nil, _?): return false
            default: return false
            }
        }
        // The lists scroll, so allow more than a screenful of rows.
        return Array(items.prefix(12))
    }

    /// NBA: "客队 @ 主队" / "客队 88-91 主队"; CS2: "NiP vs MIBR" / "NiP 2-0 MIBR".
    private func gameText(_ game: SportsService.Game) -> String {
        let separator = game.sport == .cs2 ? "vs" : "@"
        if let home = game.homeScore, let away = game.awayScore {
            return "\(game.awayTeam) \(away)-\(home) \(game.homeTeam)"
        }
        return "\(game.awayTeam) \(separator) \(game.homeTeam)"
    }

    private func isFavoriteGame(_ game: SportsService.Game) -> Bool {
        settings.favoriteTeams.contains(game.homeTeam) || settings.favoriteTeams.contains(game.awayTeam)
    }

    /// Row content shared by both schedule lists (dashboard card + full
    /// calendar): live games trade the time column for a red LIVE tag, and
    /// favorite-team games get the amber accent.
    @ViewBuilder
    private func scheduleRowContent(_ item: ScheduleItem, compact: Bool) -> some View {
        HStack(spacing: 8) {
            if let reminder = item.reminder {
                Button {
                    reminderService.toggleComplete(reminder)
                } label: {
                    Image(systemName: "circle")
                        .font(.system(size: compact ? 10 : 11))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
                .buttonStyle(.plain)
            } else if let game = item.game {
                Image(systemName: game.sport == .cs2 ? "gamecontroller.fill" : "sportscourt.fill")
                    .font(.system(size: compact ? 8 : 9))
                    .foregroundStyle(isFavoriteGame(game)
                                     ? Color(red: 0.96, green: 0.78, blue: 0.29)
                                     : Color.white.opacity(0.4))
            } else {
                Circle().fill(Color(red: 0.96, green: 0.78, blue: 0.29)).frame(width: 5, height: 5)
            }
            Group {
                if let game = item.game, game.status == .live {
                    Text("LIVE")
                        .font(.system(size: compact ? 8 : 9, weight: .heavy))
                        .foregroundStyle(Color.red)
                } else if item.untimed {
                    Text(item.reminder != nil ? L10n.t("待办", "To-do") : L10n.t("全天", "All-day"))
                } else if let time = item.time {
                    Text(formattedTime(time))
                } else {
                    Text("")
                }
            }
            .font(.system(size: compact ? 10 : 11, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Color.white.opacity(0.55))
            .frame(width: 40, alignment: .leading)
            Text(item.title)
                .font(.system(size: compact ? 11 : 12))
                .foregroundStyle(item.game.map(isFavoriteGame) == true
                                 ? Color(red: 0.96, green: 0.78, blue: 0.29) : Color.white)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(height: compact ? 22 : 26)
    }

    private func scheduleRow(_ item: ScheduleItem) -> some View {
        scheduleRowContent(item, compact: false)
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
            HStack(spacing: 2) {
                ForEach(favoriteTeamsPlaying(on: day).prefix(2), id: \.self) { team in
                    Circle().fill(Self.nbaTeamColor(team)).frame(width: 3, height: 3)
                }
            }
            .frame(height: 3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
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

/// Offset + opacity pair used for the short-travel slide/fade transitions.
private struct SlideFadeModifier: ViewModifier {
    let offset: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content.offset(x: offset).opacity(opacity)
    }
}

extension AnyTransition {
    static func slideFade(offset: CGFloat) -> AnyTransition {
        .modifier(active: SlideFadeModifier(offset: offset, opacity: 0),
                  identity: SlideFadeModifier(offset: 0, opacity: 1))
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
