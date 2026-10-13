import SwiftUI

/// Standalone editor window content for the countdown list: add, review, delete.
struct CountdownEditorView: View {
    @ObservedObject var service: CountdownService
    var onDone: () -> Void

    @State private var newTitle = ""
    @State private var newDate = Date()

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter
    }()

    var body: some View {
        VStack(spacing: 12) {
            Text("重要日子倒计时")
                .font(.system(size: 14, weight: .semibold))

            Divider()

            ScrollView {
                VStack(spacing: 8) {
                    if service.countdowns.isEmpty {
                        Text("还没有添加重要日子")
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
                                    Text("天")
                                        .font(.system(size: 9))
                                        .foregroundStyle(Color.secondary)
                                }
                                Text(service.daysRemaining(for: countdown) >= 0 ? "还剩" : "已过")
                                    .font(.system(size: 9))
                                    .foregroundStyle(Color.secondary)
                            }
                            .frame(width: 52, alignment: .trailing)
                            Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 0.5, height: 26)
                            Text(countdown.title)
                                .font(.system(size: 12))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Text(Self.displayFormatter.string(from: countdown.date))
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
                TextField("名称（如：生日、考试）", text: $newTitle)
                    .textFieldStyle(.roundedBorder)
                DatePicker("", selection: $newDate, displayedComponents: .date)
                    .labelsHidden()
                Button("添加") {
                    let trimmed = newTitle.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    service.add(title: trimmed, date: newDate)
                    newTitle = ""
                }
            }

            HStack {
                Spacer()
                Button("完成", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(minWidth: 400, minHeight: 420)
    }
}
