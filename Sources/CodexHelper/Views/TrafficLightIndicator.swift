import SwiftUI

/// 竖排 LED 质感交通灯指示器（固定高度，与右侧额度区对齐）
struct TrafficLightIndicator: View {
    let active: CodexRunStatus

    /// 与右侧「当前 + 双额度条」区域匹配的固定高度
    static let fixedHeight: CGFloat = 140

    private let cellSize: CGFloat = 36
    private let lensSize: CGFloat = 28
    private let bezelSize: CGFloat = 32

    var body: some View {
        VStack(spacing: 0) {
            LEDTrafficLightCell(color: .red, isActive: active == .waiting, cellSize: cellSize, lensSize: lensSize, bezelSize: bezelSize)
            housingDivider
            LEDTrafficLightCell(color: .amber, isActive: active == .running, cellSize: cellSize, lensSize: lensSize, bezelSize: bezelSize)
            housingDivider
            LEDTrafficLightCell(color: .green, isActive: active == .idle, cellSize: cellSize, lensSize: lensSize, bezelSize: bezelSize)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 15)
        .frame(height: Self.fixedHeight)
        .background(housingBackground)
        .overlay(alignment: .trailing) {
            VStack(spacing: cellSize + 2) {
                ForEach(0..<3, id: \.self) { _ in
                    HousingScrewView(size: 4)
                }
            }
            .padding(.trailing, 3)
        }
        .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
    }

    private var housingDivider: some View {
        Rectangle()
            .fill(Color.black.opacity(0.55))
            .frame(width: cellSize - 6, height: 1)
    }

    private var housingBackground: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.20, green: 0.20, blue: 0.22),
                        Color(red: 0.10, green: 0.10, blue: 0.11)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.black.opacity(0.35), lineWidth: 0.8)
            )
    }
}

// MARK: - 单颗 LED 灯珠

private struct LEDTrafficLightCell: View {
    let color: LEDTrafficColor
    let isActive: Bool
    let cellSize: CGFloat
    let lensSize: CGFloat
    let bezelSize: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.black.opacity(0.95),
                            Color(white: 0.06)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: bezelSize / 2
                    )
                )
                .frame(width: bezelSize, height: bezelSize)
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(0.8), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.6), radius: 1.5, x: 0, y: 1)

            LEDLensView(color: color, isActive: isActive)
                .frame(width: lensSize, height: lensSize)

            if isActive {
                Circle()
                    .fill(color.glowColor.opacity(0.35))
                    .frame(width: cellSize + 4, height: cellSize + 4)
                    .blur(radius: 6)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: cellSize, height: cellSize)
    }
}

// MARK: - LED 网格灯罩

struct LEDLensView: View {
    let color: LEDTrafficColor
    let isActive: Bool

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2

            let baseRect = CGRect(origin: .zero, size: size)
            context.fill(
                Path(ellipseIn: baseRect),
                with: .radialGradient(
                    Gradient(colors: color.lensGradient(isActive: isActive)),
                    center: center,
                    startRadius: 0,
                    endRadius: radius
                )
            )

            let dotRadius: CGFloat = isActive ? 0.55 : 0.45
            let positions = ledDotPositions(in: size, isActive: isActive)

            for point in positions {
                let dotRect = CGRect(
                    x: point.x - dotRadius,
                    y: point.y - dotRadius,
                    width: dotRadius * 2,
                    height: dotRadius * 2
                )
                context.fill(
                    Path(ellipseIn: dotRect),
                    with: .color(
                        color.dotColor(
                            isActive: isActive,
                            distance: distance(from: center, to: point),
                            maxRadius: radius
                        )
                    )
                )

                if isActive {
                    let highlightRect = dotRect.insetBy(dx: dotRadius * 0.35, dy: dotRadius * 0.35)
                    context.fill(
                        Path(ellipseIn: highlightRect),
                        with: .color(Color.white.opacity(0.45))
                    )
                }
            }

            if isActive {
                let highlight = CGRect(
                    x: size.width * 0.22,
                    y: size.height * 0.12,
                    width: size.width * 0.35,
                    height: size.height * 0.22
                )
                context.fill(
                    Path(ellipseIn: highlight),
                    with: .color(Color.white.opacity(0.18))
                )
            }
        }
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(
                    isActive ? Color.white.opacity(0.15) : color.inactiveRingColor,
                    lineWidth: isActive ? 0.4 : 1.0
                )
        )
        .shadow(
            color: color.glowColor.opacity(isActive ? 0.75 : 0.22),
            radius: isActive ? 7 : 2
        )
    }

    private func ledDotPositions(in size: CGSize, isActive: Bool) -> [CGPoint] {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let maxR = min(size.width, size.height) / 2 - 1.2
        var points: [CGPoint] = [center]

        let ringCount = isActive ? 3 : 2
        let spokes = 6
        for ring in 1...ringCount {
            let ringRadius = maxR * CGFloat(ring) / CGFloat(ringCount + 1)
            for spoke in 0..<spokes {
                let angle = CGFloat(spoke) * (.pi * 2 / CGFloat(spokes)) - .pi / 2
                points.append(
                    CGPoint(
                        x: center.x + cos(angle) * ringRadius,
                        y: center.y + sin(angle) * ringRadius
                    )
                )
            }
        }

        return points
    }

    private func distance(from: CGPoint, to: CGPoint) -> CGFloat {
        hypot(from.x - to.x, from.y - to.y)
    }
}

// MARK: - 外壳螺丝

private struct HousingScrewView: View {
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Color(white: 0.42),
                        Color(white: 0.18)
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: size / 2
                )
            )
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .stroke(Color.black.opacity(0.35), lineWidth: 0.3)
            )
    }
}

// MARK: - 颜色定义

enum LEDTrafficColor {
    case red
    case amber
    case green

    var glowColor: Color {
        switch self {
        case .red: return Color(red: 0.95, green: 0.12, blue: 0.12)
        case .amber: return Color(red: 1.0, green: 0.62, blue: 0.08)
        case .green: return Color(red: 0.12, green: 0.88, blue: 0.38)
        }
    }

    /// 熄灭时的彩色描边，便于区分红 / 黄 / 绿
    var inactiveRingColor: Color {
        switch self {
        case .red: return Color(red: 0.82, green: 0.18, blue: 0.16).opacity(0.85)
        case .amber: return Color(red: 0.88, green: 0.58, blue: 0.08).opacity(0.85)
        case .green: return Color(red: 0.18, green: 0.72, blue: 0.34).opacity(0.85)
        }
    }

    func lensGradient(isActive: Bool) -> [Color] {
        switch self {
        case .red:
            return isActive
                ? [Color(red: 1.0, green: 0.28, blue: 0.22), Color(red: 0.55, green: 0.04, blue: 0.06)]
                : [Color(red: 0.62, green: 0.14, blue: 0.13), Color(red: 0.34, green: 0.07, blue: 0.07)]
        case .amber:
            return isActive
                ? [Color(red: 1.0, green: 0.72, blue: 0.18), Color(red: 0.72, green: 0.38, blue: 0.02)]
                : [Color(red: 0.66, green: 0.44, blue: 0.08), Color(red: 0.38, green: 0.24, blue: 0.04)]
        case .green:
            return isActive
                ? [Color(red: 0.28, green: 0.98, blue: 0.48), Color(red: 0.04, green: 0.52, blue: 0.18)]
                : [Color(red: 0.16, green: 0.48, blue: 0.22), Color(red: 0.08, green: 0.28, blue: 0.12)]
        }
    }

    func dotColor(isActive: Bool, distance: CGFloat, maxRadius: CGFloat) -> Color {
        let falloff = 1 - min(distance / maxRadius, 1) * 0.25
        if isActive {
            return glowColor.opacity(0.55 + falloff * 0.45)
        }
        return glowColor.opacity(0.30 + falloff * 0.25)
    }
}

/// 任务行内的小型 LED 状态点
struct LEDStatusDotView: View {
    let state: CodexTaskState

    var body: some View {
        LEDLensView(
            color: ledColor,
            isActive: state == .running || state == .waiting
        )
        .frame(width: 9, height: 9)
    }

    private var ledColor: LEDTrafficColor {
        switch state {
        case .running: return .amber
        case .waiting, .failed: return .red
        case .completed, .idle: return .green
        }
    }
}
