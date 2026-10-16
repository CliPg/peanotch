import SwiftUI

/// Full month calendar: navigable grid with event/reminder dots, the selected
/// day's schedule, and an inline composer that creates a reminder on the
/// selected day.
struct CalendarFullView: View {
    @EnvironmentObject var calendarService: CalendarService
    @EnvironmentObject var reminderService: ReminderService

    var onDone: () -> Void

    @State private var monthAnchor = Calendar.current.startOfDay(for: Date())
    @State private var dayCounts: [Int: Int] = [:]
    @State private var newReminderTitle = ""

    private var calendar: Calendar { Calendar.current }

    var body: some View {
        VStack(spacing: 12) {
            header
            weekdayHeader
            monthGrid
            Divider()
            scheduleList
            composer
        }
        .padding(20)
        .frame(minWidth: 400, minHeight: 640)
        .onAppear { selectDay(Date()); loadMarkers() }
        .onChange(of: monthAnchor) { _ in loadMarkers() }
    }

    // MARK: - Header + navigation

    private var header: some View {
        HStack(spacing: 6) {
            Button {
                shiftMonth(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(monthTitle)
                .font(.system(size: 15, weight: .bold))
                .frame(width: 140)

            Button {
                shiftMonth(1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()
            Button(L10n.t("完成", "Done"), action: onDone)
                .buttonStyle(.bordered)
        }
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: AppSettings.shared.resolvedLanguage == "en" ? "en_US" : "zh_CN")
        formatter.dateFormat = AppSettings.shared.resolvedLanguage == "en" ? "MMMM yyyy" : "yyyy年M月"
        return formatter.string(from: monthAnchor)
    }

    private func shiftMonth(_ delta: Int) {
        if let shifted = calendar.date(byAdding: .month, value: delta, to: monthAnchor) {
            monthAnchor = calendar.startOfDay(for: shifted)
        }
    }

    // MARK: - Grid

    private var weekdayHeader: some View {
        let symbols = AppSettings.shared.resolvedLanguage == "en"
            ? ["S", "M", "T", "W", "T", "F", "S"]
            : ["日", "一", "二", "三", "四", "五", "六"]
        return HStack(spacing: 4) {
            ForEach(Array(symbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var monthCells: [Date?] {
        let components = calendar.dateComponents([.year, .month], from: monthAnchor)
        guard let first = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: first) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: first) // 1 = Sunday
        var cells: [Date?] = Array(repeating: nil, count: firstWeekday - 1)
        for day in range {
            cells.append(calendar.date(byAdding: .day, value: day - 1, to: first))
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }

    private var monthGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
            ForEach(Array(monthCells.enumerated()), id: \.offset) { _, date in
                if let date {
                    dayCell(date)
                } else {
                    Color.clear.frame(minHeight: 40)
                }
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let isToday = calendar.isDateInToday(date)
        let isSelected = calendar.isDate(date, inSameDayAs: calendarService.selectedDate)
        let hasItems = (dayCounts[calendar.component(.day, from: date)] ?? 0) > 0
        return Button(action: { selectDay(date) }) {
            VStack(spacing: 3) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 13, weight: isSelected || isToday ? .semibold : .regular, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isToday ? Color(red: 0.96, green: 0.78, blue: 0.29)
                                             : (isSelected ? Color.white : Color.primary))
                Circle()
                    .fill(hasItems ? Color(red: 0.96, green: 0.78, blue: 0.29) : Color.clear)
                    .frame(width: 3, height: 3)
            }
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(Capsule().fill(isSelected ? Color.primary.opacity(0.12) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Selection & markers

    private func selectDay(_ date: Date) {
        calendarService.selectDay(date)
        reminderService.load(for: date)
    }

    private func loadMarkers() {
        let components = calendar.dateComponents([.year, .month], from: monthAnchor)
        guard let monthStart = calendar.date(from: components) else { return }
        var counts = calendarService.eventDayCounts(monthStart: monthStart)
        reminderService.reminderDayCounts(monthStart: monthStart) { reminderCounts in
            for (day, count) in reminderCounts {
                counts[day, default: 0] += count
            }
            self.dayCounts = counts
        }
    }

    // MARK: - Schedule + composer

    private struct ScheduleItem: Identifiable {
        let id: String
        let title: String
        let time: Date?
        let untimed: Bool
        let reminder: ReminderService.Reminder?
    }

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

    private var scheduleList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(dayTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.secondary)
            if calendarService.authorized == nil {
                Text(L10n.t("正在请求日历权限…", "Requesting calendar access…"))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondary)
            } else if scheduleItems.isEmpty {
                Text(L10n.t("这天没有安排", "Nothing scheduled"))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondary)
            } else {
                ForEach(scheduleItems) { item in
                    HStack(spacing: 8) {
                        if let reminder = item.reminder {
                            Button {
                                reminderService.toggleComplete(reminder)
                            } label: {
                                Image(systemName: "circle")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.secondary)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Circle().fill(Color(red: 0.96, green: 0.78, blue: 0.29)).frame(width: 5, height: 5)
                        }
                        Group {
                            if item.untimed {
                                Text(item.reminder != nil ? L10n.t("待办", "To-do") : L10n.t("全天", "All-day"))
                            } else if let time = item.time {
                                Text(Self.timeFormatter.string(from: time))
                            } else {
                                Text("")
                            }
                        }
                        .font(.system(size: 11, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.secondary)
                        .frame(width: 44, alignment: .leading)
                        Text(item.title)
                            .font(.system(size: 12))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .frame(height: 24)
                }
            }
        }
    }

    private var dayTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: AppSettings.shared.resolvedLanguage == "en" ? "en_US" : "zh_CN")
        formatter.dateFormat = AppSettings.shared.resolvedLanguage == "en" ? "EEEE, MMM d" : "M月d日 EEEE"
        return formatter.string(from: calendarService.selectedDate)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = AppSettings.shared.clock24h ? "HH:mm" : "h:mm a"
        return formatter
    }()

    private var composer: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(Color.secondary.opacity(0.7))
            TextField(composerPlaceholder, text: $newReminderTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .onSubmit(createReminder)
            Button(L10n.t("添加", "Add"), action: createReminder)
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.35),
                              style: StrokeStyle(lineWidth: 1, dash: [5]))
        )
    }

    private var composerPlaceholder: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: AppSettings.shared.resolvedLanguage == "en" ? "en_US" : "zh_CN")
        formatter.dateFormat = AppSettings.shared.resolvedLanguage == "en" ? "MMM d" : "M月d日"
        let day = formatter.string(from: calendarService.selectedDate)
        return L10n.t("在\(day)新建提醒…", "New reminder on \(day)…")
    }

    private func createReminder() {
        let trimmed = newReminderTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        reminderService.create(title: trimmed, for: calendarService.selectedDate)
        newReminderTitle = ""
        loadMarkers()
    }
}
