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

    /// Re-fetches the current day (periodic auto-refresh).
    func refresh() {
        load(for: currentDay)
    }

    func load(for date: Date) {
        let day = Calendar.current.startOfDay(for: date)
        currentDay = day
        let calendar = Calendar.current
        let end = calendar.date(byAdding: .day, value: 1, to: day)!
        // For today, a nil start also picks up overdue incomplete reminders.
        let start: Date? = calendar.isDateInToday(day) ? nil : day
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
            DispatchQueue.main.async { self?.reminders = Array(items.prefix(3)) }
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
