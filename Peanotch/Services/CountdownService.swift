import Combine
import Foundation

/// User-defined important days, persisted in UserDefaults as JSON.
struct Countdown: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var date: Date
}

final class CountdownService: ObservableObject {
    @Published var countdowns: [Countdown] = [] {
        didSet { persist() }
    }

    private static let storageKey = "peanotch.countdowns"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([Countdown].self, from: data) {
            countdowns = Self.sorted(decoded)
        }
    }

    func add(title: String, date: Date) {
        countdowns.append(Countdown(title: title, date: date))
    }

    /// Mutates one entry by id; persistence rides on the @Published didSet.
    func update(id: UUID, _ mutate: (inout Countdown) -> Void) {
        if let index = countdowns.firstIndex(where: { $0.id == id }) {
            mutate(&countdowns[index])
        }
    }

    func remove(_ countdown: Countdown) {
        countdowns.removeAll { $0.id == countdown.id }
    }

    /// Whole days between today and the target date; negative means past.
    func daysRemaining(for countdown: Countdown) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let target = calendar.startOfDay(for: countdown.date)
        return calendar.dateComponents([.day], from: today, to: target).day ?? 0
    }

    var sortedUpcoming: [Countdown] { Self.sorted(countdowns) }

    private static func sorted(_ list: [Countdown]) -> [Countdown] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return list.sorted {
            let aPast = $0.date < today, bPast = $1.date < today
            if aPast != bPast { return !aPast }       // upcoming first
            if !aPast { return $0.date < $1.date }    // soonest upcoming first
            return $0.date > $1.date                  // most recent past last
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(countdowns) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
