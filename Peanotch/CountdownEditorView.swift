import SwiftUI

/// Modern card-based editor for the countdown list: large title header with a
/// summary, one card per important day (nearest upcoming highlighted), and a
/// dashed composer at the bottom.
struct CountdownEditorView: View {
    @ObservedObject var service: CountdownService
    @ObservedObject private var settings = AppSettings.shared
    var onDone: () -> Void

    @State private var newTitle = ""
    @State private var newDate = Date()

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 12)

            ScrollView {
                VStack(spacing: 10) {
                    if service.countdowns.isEmpty {
                        emptyState
                    } else {
                        ForEach(service.sortedUpcoming) { countdown in
                            countdownCard(countdown)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }

            composer
                .padding(20)
        }
        .frame(minWidth: 480, minHeight: 540)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.t("重要日子", "Important Days"))
                    .font(.system(size: 20, weight: .bold))
                Text(summaryText)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary)
            }
            Spacer()
            Button(L10n.t("完成", "Done"), action: onDone)
                .buttonStyle(.bordered)
        }
    }

    private var summaryText: String {
        let count = service.countdowns.count
        guard count > 0 else { return L10n.t("记录值得期待的日子", "Days worth looking forward to") }
        if let nearest = service.sortedUpcoming.first(where: { service.daysRemaining(for: $0) >= 0 }) {
            let days = service.daysRemaining(for: nearest)
            return L10n.t("\(count) 个日子 · 最近还有 \(days) 天",
                          "\(count) days · next in \(days) days")
        }
        return L10n.t("\(count) 个日子", "\(count) days")
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 34))
                .foregroundStyle(Color.secondary.opacity(0.7))
            Text(L10n.t("还没有重要日子", "No important days yet"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.secondary)
            Text(L10n.t("在下方添加一个吧", "Add one below"))
                .font(.system(size: 11))
                .foregroundStyle(Color.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    // MARK: - Countdown card

    private func countdownCard(_ countdown: Countdown) -> some View {
        let days = service.daysRemaining(for: countdown)
        let isPast = days < 0
        let nearestUpcomingId = service.sortedUpcoming.first { service.daysRemaining(for: $0) >= 0 }?.id
        let isNearest = countdown.id == nearestUpcomingId
        let accent = Color(red: 1.00, green: 0.72, blue: 0.30)

        return HStack(spacing: 14) {
            VStack(spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(abs(days))")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(isPast ? Color.secondary
                                         : (isNearest ? accent : Color.primary))
                    Text(L10n.t("天", "d"))
                        .font(.system(size: 10))
                        .foregroundStyle(Color.secondary)
                }
                Text(isPast ? L10n.t("已过", "ago") : L10n.t("还剩", "left"))
                    .font(.system(size: 9))
                    .foregroundStyle(Color.secondary)
            }
            .frame(width: 64)

            Rectangle()
                .fill(Color.primary.opacity(0.10))
                .frame(width: 1, height: 32)

            TextField(L10n.t("名称", "Title"), text: titleBinding(countdown))
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))

            DatePicker("", selection: dateBinding(countdown), displayedComponents: .date)
                .labelsHidden()
                .font(.system(size: 11))

            Button {
                service.remove(countdown)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondary.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isNearest ? accent.opacity(0.09) : Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isNearest ? accent.opacity(0.45) : Color.clear, lineWidth: 1)
        )
    }

    // MARK: - Composer

    private var composer: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(Color.secondary.opacity(0.7))
            TextField(L10n.t("名称（如：生日、考试）", "Name (e.g. Birthday, Exam)"), text: $newTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .onSubmit(addCountdown)
            DatePicker("", selection: $newDate, displayedComponents: .date)
                .labelsHidden()
                .font(.system(size: 11))
            Button(L10n.t("添加", "Add"), action: addCountdown)
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

    private func addCountdown() {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        service.add(title: trimmed, date: newDate)
        newTitle = ""
    }

    // MARK: - Bindings

    private func titleBinding(_ countdown: Countdown) -> Binding<String> {
        Binding(
            get: { self.service.countdowns.first(where: { $0.id == countdown.id })?.title ?? "" },
            set: { newValue in self.service.update(id: countdown.id) { $0.title = newValue } }
        )
    }

    private func dateBinding(_ countdown: Countdown) -> Binding<Date> {
        Binding(
            get: { self.service.countdowns.first(where: { $0.id == countdown.id })?.date ?? Date() },
            set: { newValue in self.service.update(id: countdown.id) { $0.date = newValue } }
        )
    }
}
