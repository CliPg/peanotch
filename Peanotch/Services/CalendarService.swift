import Combine
import EventKit
import Foundation

/// Today's upcoming calendar events via EventKit.
final class CalendarService: ObservableObject {
    struct Event: Identifiable, Equatable {
        let id: String
        let title: String
        let start: Date
        let isAllDay: Bool
    }

    @Published var events: [Event] = []
    @Published var authorized: Bool?

    private let store = EKEventStore()

    func requestAndLoad() {
        store.requestFullAccessToEvents { [weak self] granted, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.authorized = granted
                if granted { self.loadEvents() }
            }
        }
    }

    private func loadEvents() {
        let calendar = Calendar.current
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))!
        let predicate = store.predicateForEvents(withStart: Date(), end: end, calendars: nil)
        let upcoming = store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .prefix(4)
            .map { Event(id: $0.eventIdentifier ?? UUID().uuidString,
                         title: $0.title ?? "（无标题）",
                         start: $0.startDate,
                         isAllDay: $0.isAllDay) }
        DispatchQueue.main.async { self.events = Array(upcoming) }
    }
}
