import SwiftUI

/// Settings window content styled after macOS System Settings: grouped
/// rounded cards, label on the left, control on the right.
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.t("设置", "Settings"))
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 6) {
                groupCaption(L10n.t("通用", "General"))
                settingsGroup {
                    settingsRow(L10n.t("语言", "Language")) {
                        Picker("", selection: $settings.language) {
                            Text(L10n.t("跟随系统", "System")).tag("system")
                            Text("中文").tag("zh")
                            Text("English").tag("en")
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 176)
                    }
                    rowDivider
                    settingsRow(L10n.t("24 小时制时钟", "24-hour clock")) {
                        Toggle("", isOn: $settings.clock24h)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                groupCaption(L10n.t("刘海", "Notch"))
                settingsGroup {
                    settingsRow(L10n.t("展开方式", "Open by")) {
                        Picker("", selection: $settings.openMode) {
                            Text(L10n.t("点击", "Click")).tag("click")
                            Text(L10n.t("靠近", "Hover")).tag("hover")
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 176)
                    }
                    rowDivider
                    settingsRow(L10n.t("温度单位", "Temperature unit")) {
                        Picker("", selection: $settings.tempUnit) {
                            Text("°C").tag("c")
                            Text("°F").tag("f")
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 176)
                    }
                }
            }

            HStack {
                Spacer()
                Button(L10n.t("完成", "Done"), action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    // MARK: - System Settings building blocks

    private func groupCaption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.secondary)
            .padding(.horizontal, 4)
    }

    private func settingsGroup<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.06)))
    }

    private func settingsRow<Control: View>(_ label: String, @ViewBuilder control: () -> Control) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
            Spacer(minLength: 12)
            control()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private var rowDivider: some View {
        Divider()
            .padding(.leading, 12)
    }
}
