import SwiftUI

enum SettingsSection: Hashable {
    case general, notch, sports, countdown, about
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
        // Plain HStack split — NavigationSplitView drags in a blurred toolbar
        // strip at the top of the detail column on macOS.
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
        }
        .frame(minWidth: 640, minHeight: 440)
    }

    // MARK: - Sidebar

    private struct SidebarItem {
        let tag: SettingsSection
        let title: String
        let icon: String
        let color: Color
    }

    private var sidebarItems: [SidebarItem] {
        [
            SidebarItem(tag: .general, title: L10n.t("通用", "General"), icon: "gearshape", color: Color(white: 0.45)),
            SidebarItem(tag: .notch, title: L10n.t("刘海", "Notch"), icon: "macwindow.on.rectangle", color: Color(red: 0.20, green: 0.47, blue: 1.00)),
            SidebarItem(tag: .sports, title: L10n.t("比赛日程", "Sports"), icon: "sportscourt.fill", color: Color(red: 0.30, green: 0.69, blue: 0.35)),
            SidebarItem(tag: .countdown, title: L10n.t("倒计时", "Countdowns"), icon: "calendar.badge.clock", color: Color(red: 1.00, green: 0.42, blue: 0.24)),
            SidebarItem(tag: .about, title: L10n.t("关于", "About"), icon: "info.circle", color: Color(red: 0.35, green: 0.60, blue: 0.95)),
        ]
    }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(sidebarItems, id: \.tag) { item in
                    sidebarButton(item)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
        }
        .frame(width: 200)
        .background(.regularMaterial)
    }

    private func sidebarButton(_ item: SidebarItem) -> some View {
        let selected = section == item.tag
        return Button {
            section = item.tag
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 24, height: 24)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(item.color))
                Text(item.title)
                    .font(.system(size: 13))
                    .foregroundStyle(selected ? Color.white : Color.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.accentColor)
            }
        }
    }

    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                switch section {
                case .general: generalPane
                case .notch: notchPane
                case .sports: sportsPane
                case .countdown: countdownPane
                case .about: aboutPane
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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

    // MARK: - Sports pane

    private var sportsPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            paneTitle(L10n.t("比赛日程", "Sports"))
            settingsGroup {
                settingsRow(L10n.t("显示赛程卡片", "Show schedule card")) {
                    Toggle("", isOn: $settings.showSportsCard)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
            settingsGroup {
                settingsRow(L10n.t("运动项目", "Sport")) {
                    HStack(spacing: 8) {
                        sportChip(L10n.t("篮球 · NBA", "Basketball · NBA"), selected: true)
                        sportChip(L10n.t("足球", "Soccer"), selected: false, disabled: true)
                    }
                }
                rowDivider
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.t("主队（可多选，比赛进行时高频刷新）", "Favorite teams (select any; live games refresh faster)"))
                        .font(.system(size: 13))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 6)], spacing: 6) {
                        ForEach(SportsService.nbaTeamsEast + SportsService.nbaTeamsWest, id: \.self) { team in
                            teamChip(team)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            footnote(L10n.t("赛程数据来自虎扑。每天更新一次；主队比赛进行中时每 2 分钟刷新比分。更多运动项目后续支持。",
                            "Schedule data from Hupu. Refreshed daily; scores refresh every 2 minutes while a favorite team is playing. More sports coming later."))
        }
    }

    private func sportChip(_ text: String, selected: Bool, disabled: Bool = false) -> some View {
        HStack(spacing: 4) {
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
            }
            Text(text)
                .font(.system(size: 12))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(selected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.08)))
        .foregroundStyle(disabled ? Color.secondary : Color.primary)
        .opacity(disabled ? 0.55 : 1)
    }

    private func teamChip(_ team: String) -> some View {
        let selected = settings.favoriteTeams.contains(team)
        return Button {
            if selected {
                settings.favoriteTeams.removeAll { $0 == team }
            } else {
                settings.favoriteTeams.append(team)
            }
        } label: {
            HStack(spacing: 4) {
                if selected {
                    Image(systemName: "star.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(Color(red: 0.96, green: 0.78, blue: 0.29))
                }
                Text(team)
                    .font(.system(size: 12))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(Capsule().fill(selected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.07)))
            .foregroundStyle(Color.primary)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
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
