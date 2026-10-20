import Combine
import EventKit
import Foundation

/// Reminders (待办事项) via EventKit, loaded for a selected day.
/// Today also surfaces overdue incomplete reminders.
final class ReminderService: ObservableObject {
    struct Reminder: Identifiable, Equatable {
        let id: String
        let title: String
        let due: Date?
        let hasTime: Bool
    }

    @Published var reminders: [Reminder] = []
    @Published var authorized: Bool?

    private let store = EKEventStore()
    private var currentDay = Calendar.current.startOfDay(for: Date())

    func requestAccess() {
        store.requestFullAccessToReminders { [weak self] granted, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.authorized = granted
                if granted { self.load(for: self.currentDay) }
            }
        }
    }

    /// Day-number -> incomplete-reminder count for the month (async).
    func reminderDayCounts(monthStart: Date, completion: @escaping ([Int: Int]) -> Void) {
        guard authorized == true else {
            completion([:])
            return
        }
        let calendar = Calendar.current
        guard let end = calendar.date(byAdding: .month, value: 1, to: monthStart) else {
            completion([:])
            return
        }
        // Same inclusive/exclusive bounds as load(_:): date-only reminders sit
        // exactly on the month's midnight edges.
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: monthStart.addingTimeInterval(-1),
                                                               ending: end.addingTimeInterval(-1),
                                                               calendars: nil)
        store.fetchReminders(matching: predicate) { reminders in
            var counts: [Int: Int] = [:]
            for reminder in reminders ?? [] {
                if let due = reminder.dueDateComponents?.date {
                    counts[calendar.component(.day, from: due), default: 0] += 1
                }
            }
            DispatchQueue.main.async { completion(counts) }
        }
    }

    /// Re-fetches the current day (periodic auto-refresh).
    func refresh() {
        load(for: currentDay)
    }

    func load(for date: Date) {
        let day = Calendar.current.startOfDay(for: date)
        currentDay = day
        let calendar = Calendar.current
        // For today, a nil start also picks up overdue incomplete reminders.
        // The predicate's start bound is EXCLUSIVE and its end bound is
        // INCLUSIVE, while date-only reminders are due exactly at midnight —
        // nudge both bounds one second inside the day so a reminder set for
        // the 25th doesn't also surface on the 24th.
        let start: Date? = calendar.isDateInToday(day) ? nil : day.addingTimeInterval(-1)
        let end = calendar.date(byAdding: .day, value: 1, to: day)!.addingTimeInterval(-1)
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: start,
                                                               ending: end,
                                                               calendars: nil)
        store.fetchReminders(matching: predicate) { [weak self] ekReminders in
            let items = (ekReminders ?? []).compactMap { ek -> Reminder? in
                let title = ek.title ?? ""
                guard !title.isEmpty else { return nil }
                return Reminder(id: ek.calendarItemIdentifier,
                                title: title,
                                due: ek.dueDateComponents?.date,
                                hasTime: ek.dueDateComponents?.hour != nil)
            }
            // Selected-day items first (newly created ones surface on top),
            // overdue below (most recent first) — otherwise old overdue items
            // crowd the cap and fresh reminders never appear.
            let sorted = items.sorted { a, b in
                let aOnDay = a.due.map { calendar.isDate($0, inSameDayAs: day) } ?? true
                let bOnDay = b.due.map { calendar.isDate($0, inSameDayAs: day) } ?? true
                if aOnDay != bOnDay { return aOnDay }
                if aOnDay { return (a.due ?? .distantFuture) < (b.due ?? .distantFuture) }
                return (a.due ?? .distantPast) > (b.due ?? .distantPast)
            }
            let shown = Array(sorted.prefix(4))
            DispatchQueue.main.async {
                self?.reminders = shown
                Diagnostics.record("reminders: day \(day) fetched=\(items.count) shown=\(shown.count)")
            }
        }
    }

    /// Creates a new day-level reminder (no specific time) and reloads.
    func create(title: String, for date: Date) {
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = store.defaultCalendarForNewReminders()
            ?? store.calendars(for: .reminder).first
        reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day], from: date)
        do {
            try store.save(reminder, commit: true)
            load(for: date)
        } catch {
            Diagnostics.record("reminder create failed: \(error.localizedDescription)")
        }
    }

    /// Marks the reminder complete and reloads the day.
    func toggleComplete(_ reminder: Reminder) {
        guard let ek = store.calendarItem(withIdentifier: reminder.id) as? EKReminder else { return }
        ek.isCompleted = true
        try? store.save(ek, commit: true)
        load(for: currentDay)
    }
}
