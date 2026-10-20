import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Scene

/// One frame of the promo loop: the notch expanding from compact
/// (wings: 18° / 94%) to the full dashboard, Sapphire-style spring.
struct GifScene: View {
    /// 0 = compact, 1 = fully expanded (may overshoot slightly mid-flight)
    let progress: Double
    let amber = Color(red: 0.96, green: 0.78, blue: 0.29)

    private func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }

    var body: some View {
        let p = progress
        let width = 291 + (1100 - 291) * p
        let height = 32 + (293 - 32) * p
        let wingsOpacity = 1 - clamp01((p - 0.15) / 0.3)
        let cardsOpacity = clamp01((p - 0.55) / 0.35)

        return ZStack(alignment: .top) {
            // wallpaper — deep blue-purple with diagonal aurora beams
            ZStack {
                LinearGradient(colors: [Color(red: 0.17, green: 0.09, blue: 0.40),
                                        Color(red: 0.24, green: 0.13, blue: 0.52),
                                        Color(red: 0.10, green: 0.05, blue: 0.28)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                beam(Color(red: 0.50, green: 0.88, blue: 0.75)).offset(x: -300, y: -40)
                beam(Color(red: 0.31, green: 0.66, blue: 0.94)).offset(x: -60, y: 80)
                beam(Color(red: 0.69, green: 0.56, blue: 0.94)).offset(x: 240, y: 40)
            }
            .frame(width: 1152, height: 560)

            // notch surface (fixed content, animated pill size + crossfades)
            VStack(spacing: 0) {
                HStack {
                    Text("18°").font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill").font(.system(size: 11)).foregroundStyle(.green)
                        Text("94%").font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, 20)
                .frame(width: 291, height: 36)
                .opacity(wingsOpacity)

                HStack(alignment: .top, spacing: 10) {
                    nowCard.frame(width: 148)
                    weatherCard
                    calendarCard.frame(width: 228)
                    countdownCard.frame(width: 208)
                    systemCard.frame(width: 192)
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 14)
                .frame(width: 1100, alignment: .top)
                .opacity(cardsOpacity)
            }
            .frame(width: 1100, height: 293, alignment: .top)
            .clipped()
            .background(GifPillShape(bottomRadius: 12 + 16 * clamp01(p)).fill(Color.black))
            .overlay(GifPillShape(bottomRadius: 12 + 16 * clamp01(p)).stroke(Color.white.opacity(0.14), lineWidth: 1))
            .frame(width: max(width, 80), height: max(height, 24), alignment: .top)
            .clipped()
            .compositingGroup()
            .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        }
        .frame(width: 1152, height: 560, alignment: .top)
    }

    private func beam(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 160, style: .continuous)
            .fill(LinearGradient(colors: [color.opacity(0), color.opacity(0.5), color.opacity(0)],
                                  startPoint: .top, endPoint: .bottom))
            .frame(width: 170, height: 700)
            .rotationEffect(.degrees(32))
            .blur(radius: 40)
    }

    private func card<Content: View>(_ content: Content) -> some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06)))
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.45))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(Color.white.opacity(0.09)))
    }

    private var nowCard: some View {
        card(VStack(alignment: .leading, spacing: 7) {
            label("现在")
            VStack(alignment: .leading, spacing: 1) {
                Text("14:32").font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(.white)
                Text("10月17日 星期六").font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.6))
            }
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                Image(systemName: "airpodspro").font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.5))
                Text("AirPods").font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.55))
                Spacer()
                Text("98%").font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(.white)
            }
            bar(0.98)
        })
    }

    private var weatherCard: some View {
        card(VStack(alignment: .leading, spacing: 7) {
            HStack { label("天气"); Spacer(); Text("上海").font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.45)) }
            HStack(spacing: 10) {
                Image(systemName: "cloud.sun.fill").font(.system(size: 26)).foregroundStyle(.white)
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("24").font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    Text("°").font(.system(size: 15)).foregroundStyle(Color.white.opacity(0.5))
                }
                .fixedSize()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("多云").font(.system(size: 11, weight: .medium)).foregroundStyle(Color.white.opacity(0.8)).fixedSize()
                    Text("H 27°  L 18°").font(.system(size: 10, design: .rounded)).foregroundStyle(Color.white.opacity(0.5)).fixedSize()
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
        })
    }

    private var calendarCard: some View {
        card(VStack(alignment: .leading, spacing: 7) {
            HStack { label("日历"); Spacer(); Text("10月").font(.system(size: 9)).foregroundStyle(Color.white.opacity(0.45)) }
            HStack(spacing: 4) {
                ForEach(Array(["日", "一", "二", "三", "四", "五", "六"].enumerated()), id: \.offset) { i, s in
                    VStack(spacing: 3) {
                        Text(s).font(.system(size: 8)).foregroundStyle(i == 2 ? amber : Color.white.opacity(0.4))
                        Text("\(11 + i)").font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.85))
                    }
                    .frame(maxWidth: .infinity)
                    .background(Capsule().fill(i == 6 ? Color.white.opacity(0.16) : .clear))
                    .padding(.vertical, 2)
                }
            }
            Rectangle().fill(Color.white.opacity(0.1)).frame(height: 0.5)
            schedule("10:00", "产品评审会")
            schedule("14:30", "健身房")
            Spacer(minLength: 0)
        })
    }

    private var countdownCard: some View {
        card(VStack(alignment: .leading, spacing: 6) {
            label("倒计时")
            countdownRow("12", "妈妈生日", highlight: true)
            countdownRow("48", "项目上线")
            countdownRow("113", "春节")
            Spacer(minLength: 0)
        })
    }

    private var systemCard: some View {
        card(VStack(alignment: .leading, spacing: 7) {
            label("系统")
            statRow("CPU", "23%")
            statRow("内存", "11G / 16G")
            statRow("网络", "↓1.2M ↑86K")
            statRow("电池健康", "93%")
            Spacer(minLength: 0)
        })
    }

    private func bar(_ fraction: Double) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.15))
                Capsule().fill(Color.white.opacity(0.85)).frame(width: proxy.size.width * fraction)
            }
        }
        .frame(height: 4)
    }

    private func schedule(_ time: String, _ title: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(amber).frame(width: 4, height: 4)
            Text(time).font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(Color.white.opacity(0.55))
                .frame(width: 34, alignment: .leading)
            Text(title).font(.system(size: 11)).foregroundStyle(.white)
            Spacer(minLength: 0)
        }
        .frame(height: 22)
    }

    private func countdownRow(_ days: String, _ title: String, highlight: Bool = false) -> some View {
        HStack(spacing: 6) {
            Text(days)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(highlight ? amber : .white)
                .frame(width: 36, alignment: .trailing)
            Text("天").font(.system(size: 9)).foregroundStyle(Color.white.opacity(0.4))
            Text(title).font(.system(size: 11)).foregroundStyle(.white.opacity(highlight ? 0.95 : 0.8))
            Spacer(minLength: 0)
        }
        .frame(height: 24)
    }

    private func statRow(_ name: String, _ value: String) -> some View {
        HStack {
            Text(name).font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.85))
            Spacer()
            Text(value).font(.system(size: 10, design: .rounded)).monospacedDigit().foregroundStyle(Color.white.opacity(0.5)).fixedSize()
        }
        .frame(height: 18)
    }
}

/// Pill with square top edge (screen edge) and rounded bottom.
struct GifPillShape: Shape {
    var bottomRadius: CGFloat
    func path(in rect: CGRect) -> Path {
        let radius = min(bottomRadius, rect.width / 2, rect.height / 2)
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 0, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: radius, y: rect.maxY),
                          control: CGPoint(x: 0, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY - radius),
                          control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: 0))
        path.closeSubpath()
        return path
    }
}

// MARK: - Timeline

/// Under-damped spring settling 0 -> 1 (~12% overshoot, like the app's
/// .spring(response: 0.4, dampingFraction: 0.55)).
func spring(_ u: Double) -> Double {
    let sigma = 6.0, omega = 9.0
    return 1 - exp(-sigma * u) * (cos(omega * u) + (sigma / omega) * sin(omega * u))
}

/// Loop timeline: expand (0-0.9s), hold open (0.9-2.8s), collapse (2.8-3.7s),
/// hold compact (3.7-4.3s). Total 4.3s.
func timeline(_ t: Double) -> Double {
    switch t {
    case ..<0.9: return spring(t / 0.75)
    case ..<2.8: return 1
    case ..<3.7: return 1 - spring((t - 2.8) / 0.75)
    default: return 0
    }
}

// MARK: - Render + GIF encode

let fps = 15.0
let total = 4.3
let frameCount = Int(fps * total)
let size = NSSize(width: 1152, height: 560)

func renderFrame(_ index: Int) -> CGImage {
    let t = Double(index) / fps
    let p = timeline(t)
    let hosting = NSHostingView(rootView: GifScene(progress: p))
    hosting.setFrameSize(size)
    hosting.sizingOptions = []
    hosting.layoutSubtreeIfNeeded()
    let rect = CGRect(origin: .zero, size: size)
    let bitmap = hosting.bitmapImageRepForCachingDisplay(in: rect)!
    bitmap.size = size
    hosting.cacheDisplay(in: rect, to: bitmap)
    return bitmap.cgImage!
}

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/peanotch_promo.gif"
let gifURL = URL(fileURLWithPath: outPath) as CFURL
guard let dest = CGImageDestinationCreateWithURL(gifURL, UTType.gif.identifier as CFString, frameCount, nil) else {
    FileHandle.standardError.write("cannot create gif destination\n".data(using: .utf8)!)
    exit(1)
}

let frameProps: [CFString: Any] = [kCGImagePropertyGIFDelayTime: 1 / fps]
let gifProps: [CFString: Any] = [kCGImagePropertyGIFLoopCount: 0]
CGImageDestinationSetProperties(dest, gifProps as CFDictionary)

// also export a few frames as PNGs for review (0=compact, 3=mid-flight overshoot, 30=open, 52=compact)
let reviewIndices = [0, 3, 30, 52]
for i in 0..<frameCount {
    let image = renderFrame(i)
    CGImageDestinationAddImage(dest, image, frameProps as CFDictionary)
    if reviewIndices.contains(i) {
        let rep = NSBitmapImageRep(cgImage: image)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: "/tmp/gif_frame_\(i).png"))
        }
    }
}

guard CGImageDestinationFinalize(dest) else {
    FileHandle.standardError.write("gif finalize failed\n".data(using: .utf8)!)
    exit(1)
}
print("written \(outPath), frames=\(frameCount)")
