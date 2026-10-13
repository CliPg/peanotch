import SwiftUI

/// Standalone editor window content for the countdown list: add, review, delete.
struct CountdownEditorView: View {
    @ObservedObject var service: CountdownService
    @ObservedObject private var settings = AppSettings.shared
    var onDone: () -> Void

    @State private var newTitle = ""
    @State private var newDate = Date()

    private var displayFormatter: DateFormatter {
        let formatter = DateFormatter()
        let english = settings.resolvedLanguage == "en"
        formatter.locale = Locale(identifier: english ? "en_US" : "zh_CN")
        formatter.dateFormat = english ? "MMM d, yyyy" : "yyyy年M月d日"
        return formatter
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(L10n.t("重要日子倒计时", "Important Days"))
                .font(.system(size: 14, weight: .semibold))

            Divider()

            ScrollView {
                VStack(spacing: 8) {
                    if service.countdowns.isEmpty {
                        Text(L10n.t("还没有添加重要日子", "No important days yet"))
                            .font(.system(size: 12))
                            .foregroundStyle(Color.secondary)
                            .padding(.vertical, 16)
                    }
                    ForEach(service.sortedUpcoming) { countdown in
                        HStack(spacing: 10) {
                            VStack(alignment: .trailing, spacing: 1) {
                                HStack(alignment: .firstTextBaseline, spacing: 1) {
                                    Text("\(abs(service.daysRemaining(for: countdown)))")
                                        .font(.system(size: 16, weight: .bold, design: .rounded))
                                        .monospacedDigit()
                                    Text(L10n.t("天", "d"))
                                        .font(.system(size: 9))
                                        .foregroundStyle(Color.secondary)
                                }
                                Text(service.daysRemaining(for: countdown) >= 0 ? L10n.t("还剩", "left") : L10n.t("已过", "ago"))
                                    .font(.system(size: 9))
                                    .foregroundStyle(Color.secondary)
                            }
                            .frame(width: 52, alignment: .trailing)
                            Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 0.5, height: 26)
                            Text(countdown.title)
                                .font(.system(size: 12))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Text(displayFormatter.string(from: countdown.date))
                                .font(.system(size: 11))
                                .foregroundStyle(Color.secondary)
                            Button {
                                service.remove(countdown)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.red.opacity(0.8))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
                    }
                }
            }

            Divider()

            HStack(spacing: 8) {
                TextField(L10n.t("名称（如：生日、考试）", "Name (e.g. Birthday, Exam)"), text: $newTitle)
                    .textFieldStyle(.roundedBorder)
                DatePicker("", selection: $newDate, displayedComponents: .date)
                    .labelsHidden()
                Button(L10n.t("添加", "Add")) {
                    let trimmed = newTitle.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    service.add(title: trimmed, date: newDate)
                    newTitle = ""
                }
            }

            HStack {
                Spacer()
                Button(L10n.t("完成", "Done"), action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(minWidth: 400, minHeight: 420)
    }
}
