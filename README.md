<div align="center">

# 🥜 Peanotch

**一个极简的 macOS 刘海（Notch）小应用**

平时在刘海区域显示时钟，鼠标悬停自动展开显示日期等信息。

</div>

## 功能

- **刘海时钟** — 在屏幕顶部刘海区域显示一个黑色圆角胶囊，实时显示当前时间
- **悬停展开** — 鼠标移上去自动向下展开，显示日期；移开自动收回，带平滑动画
- **菜单栏控制** — 通过菜单栏的 🥜 图标可以显示/隐藏刘海、退出应用
- **常驻所有空间** — 跟随每个桌面空间与全屏应用显示

## 环境要求

- macOS 14.0 或更高版本
- Xcode 16 或更高版本（用于编译）

## 运行

**方式一：Xcode**

```bash
open Peanotch.xcodeproj   # 然后在 Xcode 中按 Cmd + R
```

**方式二：命令行**

```bash
xcodebuild -project Peanotch.xcodeproj -target Peanotch -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/Peanotch.app
```

## 工作原理

Peanotch 是一个 `LSUIElement` 应用（无 Dock 图标），核心只有一个无边框、透明背景的
`NSPanel`，固定在屏幕顶部中央（刘海位置），窗口层级为状态栏级别，并加入所有桌面空间。
窗口内容由 SwiftUI 渲染：一个底部圆角的黑色形状 + 时钟文字。鼠标悬停时通过
`NSAnimationContext` 动画改变窗口高度实现“展开”效果。

```
Peanotch/
├── App.swift                  # 应用入口，创建刘海窗口和菜单栏图标
├── NotchWindowController.swift # 管理 NSPanel 的位置、展开/收起动画
└── NotchView.swift            # SwiftUI 视图：时钟 + 日期
```

## 路线图（ Ideas ）

- [ ] 正在播放（Now Playing）媒体信息
- [ ] 电池状态
- [ ] 天气信息
- [ ] 文件暂存架（File Shelf）
- [ ] 拖拽调整宽度

## 致谢

Peanotch 的创意受 [Sapphire](https://github.com/cshariq/Sapphire) 启发（一个功能丰富的开源
macOS 刘海应用，AGPL-3.0 协议）。Peanotch 的所有代码均为原创实现，与本仓库无代码关联。

## 许可证

[MIT](LICENSE)
