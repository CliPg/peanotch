import SwiftUI

enum SettingsSection: Hashable {
    case general, notch, countdown, about
}

/// Two-column System Settings style: sidebar navigation on the left
/// (colored rounded-square icons, native selection capsule) and grouped
/// rounded cards on the right.
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    var onDone: () -> Void
    var onOpenCountdowns: () -> Void = {}

    @State private var section: SettingsSection = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $section) {
                navLabel(L10n.t("通用", "General"), icon: "gearshape", color: Color(white: 0.45), tag: .general)
                navLabel(L10n.t("刘海", "Notch"), icon: "macwindow.on.rectangle", color: Color(red: 0.20, green: 0.47, blue: 1.00), tag: .notch)
                navLabel(L10n.t("倒计时", "Countdowns"), icon: "calendar.badge.clock", color: Color(red: 1.00, green: 0.42, blue: 0.24), tag: .countdown)
                navLabel(L10n.t("关于", "About"), icon: "info.circle", color: Color(red: 0.35, green: 0.60, blue: 0.95), tag: .about)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(200)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch section {
                    case .general: generalPane
                    case .notch: notchPane
                    case .countdown: countdownPane
                    case .about: aboutPane
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 640, minHeight: 440)
    }

    // MARK: - Sidebar row

    private func navLabel(_ title: String, icon: String, color: Color, tag: SettingsSection) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(color))
            Text(title)
        }
        .tag(tag)
    }

    // MARK: - Panes

    private var generalPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            paneTitle(L10n.t("通用", "General"))
            settingsGroup {
                settingsRow(L10n.t("语言", "Language")) {
                    Picker("", selection: $settings.language) {
                        Text(L10n.t("跟随系统", "System")).tag("system")
                        Text("中文").tag("zh")
                        Text("English").tag("en")
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 190)
                }
                rowDivider
                settingsRow(L10n.t("24 小时制时钟", "24-hour clock")) {
                    Toggle("", isOn: $settings.clock24h)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                rowDivider
                settingsRow(L10n.t("震动反馈", "Haptic feedback")) {
                    Toggle("", isOn: $settings.hapticFeedback)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
            footnote(L10n.t("仪表盘展开时在触控板上产生轻微震动（需要 Force Touch 触控板，鼠标操作无效）。",
                            "Subtle trackpad tick when the dashboard opens (Force Touch trackpad required; no effect with a mouse)."))
        }
    }

    private var notchPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            paneTitle(L10n.t("刘海", "Notch"))
            settingsGroup {
                settingsRow(L10n.t("展开方式", "Open by")) {
                    Picker("", selection: $settings.openMode) {
                        Text(L10n.t("点击", "Click")).tag("click")
                        Text(L10n.t("靠近", "Hover")).tag("hover")
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 190)
                }
                rowDivider
                settingsRow(L10n.t("温度单位", "Temperature unit")) {
                    Picker("", selection: $settings.tempUnit) {
                        Text("°C").tag("c")
                        Text("°F").tag("f")
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 190)
                }
            }
            footnote(L10n.t("靠近展开：鼠标移入刘海区域自动弹出，移开 0.25 秒后收起。",
                            "Hover: the dashboard opens when the pointer reaches the notch and closes 0.25s after leaving."))
        }
    }

    private var countdownPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            paneTitle(L10n.t("倒计时", "Countdowns"))
            settingsGroup {
                settingsRow(L10n.t("管理重要日子", "Manage important days")) {
                    Button(L10n.t("打开倒计时设置…", "Open Countdowns…"), action: onOpenCountdowns)
                }
            }
            footnote(L10n.t("在仪表盘的倒计时卡片上点 ＋ 也能打开管理窗口。",
                            "The + button on the dashboard countdown card opens the same manager."))
        }
    }

    private var aboutPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            paneTitle(L10n.t("关于", "About"))
            settingsGroup {
                HStack(spacing: 12) {
                    Text("🥜")
                        .font(.system(size: 34))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Peanotch")
                            .font(.system(size: 14, weight: .semibold))
                        Text(L10n.t("重新定义你的刘海", "Redefine your notch"))
                            .font(.system(size: 11))
                            .foregroundStyle(Color.secondary)
                    }
                    Spacer()
                    Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                rowDivider
                settingsRow(L10n.t("致谢", "Credits")) {
                    Text(L10n.t("灵感来自 Sapphire", "Inspired by Sapphire"))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.secondary)
                }
            }
        }
    }

    // MARK: - System Settings building blocks

    private func paneTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 17, weight: .bold))
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

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Color.secondary)
            .padding(.horizontal, 4)
    }
}
