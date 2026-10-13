import SwiftUI

/// Basic settings window content: language, open mode, temperature unit, clock.
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text(L10n.t("设置", "Settings"))
                .font(.system(size: 14, weight: .semibold))
            Divider()
            Form {
                Picker(L10n.t("语言", "Language"), selection: $settings.language) {
                    Text(L10n.t("跟随系统", "System")).tag("system")
                    Text("中文").tag("zh")
                    Text("English").tag("en")
                }
                Picker(L10n.t("展开方式", "Open by"), selection: $settings.openMode) {
                    Text(L10n.t("点击刘海展开", "Click")).tag("click")
                    Text(L10n.t("靠近刘海展开", "Hover")).tag("hover")
                }
                Picker(L10n.t("温度单位", "Temperature unit"), selection: $settings.tempUnit) {
                    Text("°C").tag("c")
                    Text("°F").tag("f")
                }
                Toggle(L10n.t("24 小时制时钟", "24-hour clock"), isOn: $settings.clock24h)
            }
            .frame(maxWidth: .infinity)
            HStack {
                Spacer()
                Button(L10n.t("完成", "Done"), action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(minWidth: 340, minHeight: 320)
    }
}
