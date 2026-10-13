import Combine
import EventKit
import Foundation

/// Upcoming calendar events via EventKit, for a selected day (default: today).
final class CalendarService: ObservableObject {
    struct Event: Identifiable, Equatable {
        let id: String
        let title: String
        let start: Date
        let isAllDay: Bool
    }

    @Published var events: [Event] = []
    @Published var authorized: Bool?
    @Published private(set) var selectedDate = Calendar.current.startOfDay(for: Date())

    private let store = EKEventStore()

    func requestAndLoad() {
        store.requestFullAccessToEvents { [weak self] granted, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.authorized = granted
                if granted { self.loadEvents(for: self.selectedDate) }
            }
        }
    }

    func selectDay(_ date: Date) {
        selectedDate = Calendar.current.startOfDay(for: date)
        if authorized == true {
            loadEvents(for: selectedDate)
        }
    }

    private func loadEvents(for day: Date) {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let upcoming = store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .prefix(3)
            .map { Event(id: $0.eventIdentifier ?? UUID().uuidString,
                         title: $0.title ?? "（无标题）",
                         start: $0.startDate,
                         isAllDay: $0.isAllDay) }
        DispatchQueue.main.async { self.events = Array(upcoming) }
    }
}
