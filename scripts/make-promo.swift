import AppKit
import SwiftUI

// MARK: - Shape: flat top, rounded bottom (the notch surface)

struct PromoNotchShape: Shape {
    var radius: CGFloat
    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.width / 2, rect.height)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.maxY), control: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY - r), control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Dashboard mock (static sample data)

struct PromoDashboard: View {
    let amber = Color(red: 0.96, green: 0.78, blue: 0.29)

    func card(_ content: some View) -> some View {
        content
            .padding(26)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Color.white.opacity(0.07)))
    }

    func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.45))
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(Capsule().fill(Color.white.opacity(0.09)))
    }

    var body: some View {
        VStack(spacing: 0) {
            // notch band with wings
            HStack {
                Text("18°").font(.system(size: 26, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill").font(.system(size: 18)).foregroundStyle(.green)
                    Text("94%").font(.system(size: 24, weight: .semibold, design: .rounded)).foregroundStyle(.white).fixedSize(horizontal: true, vertical: false).lineLimit(1)
                }
            }
            .padding(.horizontal, 32)
            .frame(height: 64)

            HStack(spacing: 16) {
                // 现在
                card(
                    VStack(alignment: .leading, spacing: 14) {
                        label("现在")
                        Text("14:32").font(.system(size: 54, weight: .bold, design: .rounded)).foregroundStyle(.white)
                        Text("10月17日 星期六").font(.system(size: 22)).foregroundStyle(.white.opacity(0.55))
                        Spacer()
                        HStack(spacing: 8) {
                            Image(systemName: "airpodspro").font(.system(size: 20)).foregroundStyle(.white.opacity(0.5))
                            Text("AirPods").font(.system(size: 20)).foregroundStyle(.white.opacity(0.55)).fixedSize(horizontal: true, vertical: false).lineLimit(1)
                            Spacer()
                            Text("98%").font(.system(size: 24, weight: .semibold, design: .rounded)).foregroundStyle(.white).fixedSize(horizontal: true, vertical: false).lineLimit(1)
                        }
                        bar(0.98, color: .white.opacity(0.85))
                        HStack(spacing: 8) {
                            Image(systemName: "battery.75").font(.system(size: 24)).foregroundStyle(.white.opacity(0.6))
                            Text("电池").font(.system(size: 20)).foregroundStyle(.white.opacity(0.55)).fixedSize(horizontal: true, vertical: false).lineLimit(1)
                            Spacer()
                            Text("94%").font(.system(size: 24, weight: .semibold, design: .rounded)).foregroundStyle(.white).fixedSize(horizontal: true, vertical: false).lineLimit(1)
                        }
                        bar(0.94, color: .white.opacity(0.85))
                    }
                ).frame(width: 230)

                // 天气
                card(
                    VStack(alignment: .leading, spacing: 14) {
                        HStack { label("天气"); Spacer(); Text("上海").font(.system(size: 20)).foregroundStyle(.white.opacity(0.45)) }
                        HStack(spacing: 16) {
                            Image(systemName: "cloud.sun.fill").font(.system(size: 54)).foregroundStyle(.white)
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text("24").font(.system(size: 58, weight: .bold, design: .rounded)).foregroundStyle(.white)
                                Text("°").font(.system(size: 32)).foregroundStyle(.white.opacity(0.5))
                            }
                            .fixedSize(horizontal: true, vertical: false)
                            Text("多云").font(.system(size: 24, weight: .medium)).foregroundStyle(.white.opacity(0.8)).fixedSize(horizontal: true, vertical: false).lineLimit(1)
                        }
                        Text("H 27°    L 18°").font(.system(size: 22, design: .rounded)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                        Spacer()
                        VStack(alignment: .leading, spacing: 10) {
                            Label("湿度 62%", systemImage: "humidity").font(.system(size: 21)).foregroundStyle(.white.opacity(0.5))
                            Label("东南风 3 级", systemImage: "wind").font(.system(size: 21)).foregroundStyle(.white.opacity(0.5))
                        }
                    }
                )

                // 日历
                card(
                    VStack(alignment: .leading, spacing: 14) {
                        label("日历")
                        HStack(spacing: 6) {
                            ForEach(Array(["日","一","二","三","四","五","六"].enumerated()), id: \.offset) { i, s in
                                VStack(spacing: 6) {
                                    Text(s).font(.system(size: 17)).foregroundStyle(i == 2 ? amber : .white.opacity(0.4))
                                    Text("\(11 + i)").font(.system(size: 24, weight: .semibold, design: .rounded))
                                        .foregroundStyle(i == 6 ? .white : (i == 2 ? .white : .white.opacity(0.8)))
                                }
                                .frame(maxWidth: .infinity)
                                .background(Capsule().fill(i == 6 ? Color.white.opacity(0.16) : .clear))
                            }
                        }
                        Divider().overlay(Color.white.opacity(0.1))
                        schedule("10:00", "产品评审会")
                        schedule("14:30", "健身房")
                        schedule("待办", "给家里打电话", circle: true)
                        Spacer()
                    }
                ).frame(width: 380)

                // 倒计时
                card(
                    VStack(alignment: .leading, spacing: 10) {
                        label("倒计时")
                        countdown("12", "妈妈生日", highlight: true)
                        countdown("48", "项目上线")
                        countdown("113", "春节")
                        Spacer()
                    }
                ).frame(width: 270)

                // 系统
                card(
                    VStack(alignment: .leading, spacing: 14) {
                        label("系统")
                        stat("CPU", "23%", 0.23)
                        stat("内存", "11G / 16G", 0.69)
                        stat("网络", "↓1.2M ↑86K", nil)
                        stat("电池健康", "93%", 0.93, color: .green)
                        Spacer()
                    }
                ).frame(width: 260)
            }
            .padding(.horizontal, 20).padding(.bottom, 20)
            .frame(height: 380)
        }
        .frame(width: 1548, height: 470)
        .background(PromoNotchShape(radius: 52).fill(Color.black))
        .overlay(PromoNotchShape(radius: 52).stroke(Color.white.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 40, y: 18)
    }

    func bar(_ fraction: Double, color: Color) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.15))
                Capsule().fill(color).frame(width: proxy.size.width * fraction)
            }
        }.frame(height: 7)
    }

    func schedule(_ time: String, _ title: String, circle: Bool = false) -> some View {
        HStack(spacing: 12) {
            if circle {
                Image(systemName: "circle").font(.system(size: 20)).foregroundStyle(.white.opacity(0.5))
            } else {
                Circle().fill(amber).frame(width: 8, height: 8)
            }
            Text(time).font(.system(size: 20, design: .rounded)).foregroundStyle(.white.opacity(0.5)).frame(width: 74, alignment: .leading)
            Text(title).font(.system(size: 23)).foregroundStyle(.white)
        }.frame(height: 44)
    }

    func countdown(_ days: String, _ title: String, highlight: Bool = false) -> some View {
        HStack(spacing: 12) {
            VStack(spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(days).font(.system(size: 33, weight: .bold, design: .rounded))
                        .foregroundStyle(highlight ? amber : .white)
                    Text("天").font(.system(size: 16)).foregroundStyle(.white.opacity(0.45))
                }
                Text("还剩").font(.system(size: 16)).foregroundStyle(.white.opacity(0.4))
            }.frame(width: 80)
            Rectangle().fill(Color.white.opacity(0.1)).frame(width: 1, height: 52)
            Text(title).font(.system(size: 22)).foregroundStyle(.white)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.white.opacity(0.05)))
    }

    func stat(_ name: String, _ value: String, _ fraction: Double?, color: Color = .white.opacity(0.85)) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text(name).font(.system(size: 20)).foregroundStyle(.white.opacity(0.8))
                Spacer()
                Text(value).font(.system(size: 18, design: .rounded)).foregroundStyle(.white.opacity(0.5))
            }
            if let fraction { bar(fraction, color: color) }
        }
    }
}

// MARK: - MacBook screen

struct PromoScreen: View {
    var body: some View {
        VStack(spacing: 0) {
            display
            base
        }
    }

    private var base: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.78), Color(white: 0.66)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 1560 + 130, height: 36)
            Capsule()
                .fill(LinearGradient(colors: [Color(white: 0.55), Color(white: 0.68)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 240, height: 13)
                .offset(y: 5)
        }
        .shadow(color: .black.opacity(0.16), radius: 40, y: 26)
    }

    private var display: some View {
        ZStack(alignment: .top) {
            // wallpaper
            ZStack {
                LinearGradient(colors: [Color(red: 0.98, green: 0.44, blue: 0.36),
                                        Color(red: 0.94, green: 0.63, blue: 0.44),
                                        Color(red: 0.22, green: 0.32, blue: 0.55)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().fill(Color.purple.opacity(0.4)).blur(radius: 120).frame(width: 600).offset(x: 340, y: 320)
                Circle().fill(Color.orange.opacity(0.35)).blur(radius: 130).frame(width: 520).offset(x: -420, y: 420)
                Circle().fill(Color.blue.opacity(0.3)).blur(radius: 130).frame(width: 480).offset(x: 120, y: 640)
            }

            // dashboard hanging from the notch
            PromoDashboard().offset(y: 8)
        }
        .frame(width: 1560, height: 980)
        .clipShape(RoundedRectangle(cornerRadius: 44, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 44, style: .continuous)
                .strokeBorder(Color(white: 0.55), lineWidth: 2)
        )
        .padding(26)
        .background(
            RoundedRectangle(cornerRadius: 62, style: .continuous).fill(Color(white: 0.1))
        )
        .shadow(color: .black.opacity(0.22), radius: 90, y: 50)
    }
}

// MARK: - Full promo canvas

struct PromoView: View {
    let features = ["实时天气", "日历与提醒事项", "重要日子倒计时", "系统监测", "AirPods 电量"]

    var body: some View {
        VStack(spacing: 110) {
            PromoScreen()

            VStack(spacing: 40) {
                Text("Peanotch")
                    .font(.system(size: 150, weight: .bold))
                    .foregroundStyle(Color(white: 0.1))

                Text("重新定义你的刘海。Redefine your notch.")
                    .font(.system(size: 54, weight: .medium))
                    .foregroundStyle(Color(white: 0.45))

                HStack(spacing: 20) {
                    ForEach(features, id: \.self) { feature in
                        Text(feature)
                            .font(.system(size: 30, weight: .medium))
                            .foregroundStyle(Color(white: 0.35))
                            .padding(.horizontal, 34).padding(.vertical, 16)
                            .background(Capsule().fill(Color(white: 0.91)))
                    }
                }
            }
        }
        .padding(140)
        .frame(width: 2560, height: 2200)
        .background(Color(red: 0.96, green: 0.96, blue: 0.97))
    }
}

// MARK: - Render to PNG

let size = NSSize(width: 2560, height: 2200)
let hosting = NSHostingView(rootView: PromoView())
hosting.setFrameSize(size)

guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
    fatalError("no rep")
}
hosting.cacheDisplay(in: hosting.bounds, to: rep)
guard let cgImage = rep.cgImage else { fatalError("no cgImage") }
let bitmap = NSBitmapImageRep(cgImage: cgImage)
guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("no data") }

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "promo.png"
try! data.write(to: URL(fileURLWithPath: output))
print("written \(output) \(data.count) bytes")
