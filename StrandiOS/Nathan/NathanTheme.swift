//  NathanTheme.swift
//  Nathan's redesign: shared look for the custom Today / Sleep / Body screens.
//  Colours resolve through StrandPalette tokens (the dark palette is set in NoopVisualStyle), so the
//  screens follow the app theme instead of carrying their own hex values.

import SwiftUI
import StrandDesign

enum NathanStyle {
    static let page: CGFloat = 20
    static let gap: CGFloat = 12
    static let sectionGap: CGFloat = 22
    static let cardRadius: CGFloat = 20
    static let tileRadius: CGFloat = 18

    static var canvas: Color { StrandPalette.surfaceBase }
    static var card: Color { StrandPalette.surfaceRaised }
    static var inset: Color { StrandPalette.surfaceInset }
    static var line: Color { StrandPalette.hairline }
    static var text: Color { StrandPalette.textPrimary }
    static var text2: Color { StrandPalette.textSecondary }
    static var text3: Color { StrandPalette.textTertiary }
    static var accent: Color { StrandPalette.accent }
    static var good: Color { StrandPalette.statusPositive }
    static var bad: Color { StrandPalette.statusCritical }
    static var warn: Color { StrandPalette.statusWarning }

    /// Fixed identity colours for the three daily scores.
    static var sleepColor: Color { StrandPalette.sleepLight }
    static var strainColor: Color { StrandPalette.metricPurple }

    /// WHOOP-style recovery colour: green 67+, yellow 34–66, red below.
    static func recoveryColor(_ pct: Double?) -> Color {
        guard let pct else { return text3 }
        if pct >= 67 { return good }
        if pct >= 34 { return warn }
        return bad
    }

    static func recoveryLabel(_ pct: Double?) -> String {
        guard let pct else { return "Calibrating" }
        if pct >= 67 { return "Recovered" }
        if pct >= 34 { return "Moderate" }
        return "Low"
    }

    static func number(_ size: CGFloat) -> Font { StrandFont.number(size, weight: .bold) }
    static let label = Font.system(size: 12, weight: .semibold, design: .rounded)
}

// MARK: - Trend direction → colour

/// Which way is "better" for a metric. Colour follows good/bad, not up/down: a falling resting heart rate
/// is green, falling steps are red.
enum NathanBetter { case up, down, neither }

struct NathanDelta {
    let text: String
    let color: Color

    /// `current` vs `baseline`. Changes smaller than `deadband` read as neutral grey.
    static func make(current: Double?, baseline: Double?, better: NathanBetter,
                     format: (Double) -> String, suffix: String = "", deadband: Double = 0) -> NathanDelta? {
        guard let current, let baseline else { return nil }
        let diff = current - baseline
        if abs(diff) <= deadband || diff == 0 {
            return NathanDelta(text: "— steady\(suffix)", color: NathanStyle.text3)
        }
        let arrow = diff > 0 ? "▲" : "▼"
        let improving: Bool
        switch better {
        case .up: improving = diff > 0
        case .down: improving = diff < 0
        case .neither: return NathanDelta(text: "\(arrow) \(format(abs(diff)))\(suffix)", color: NathanStyle.text3)
        }
        return NathanDelta(text: "\(arrow) \(format(abs(diff)))\(suffix)",
                           color: improving ? NathanStyle.good : NathanStyle.bad)
    }
}

enum NathanFormat {
    static func int(_ v: Double) -> String { String(Int(v.rounded())) }
    static func one(_ v: Double) -> String { String(format: "%.1f", v) }
    static func grouped(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v.rounded())) ?? int(v)
    }
    /// Minutes → "7:41".
    static func hm(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        return "\(m / 60):" + String(format: "%02d", m % 60)
    }
    /// Minutes → "7h 41m".
    static func hmLong(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        return "\(m / 60)h " + String(format: "%02dm", m % 60)
    }
    static func clock(_ ts: Int) -> String {
        let f = DateFormatter(); f.dateFormat = "h:mm a"
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }
    static func mean(_ xs: [Double]) -> Double? {
        xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count)
    }
}

// MARK: - Building blocks

struct NathanCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NathanStyle.card, in: RoundedRectangle(cornerRadius: NathanStyle.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NathanStyle.cardRadius, style: .continuous)
                .stroke(NathanStyle.line, lineWidth: 1))
    }
}

struct NathanSectionHeader: View {
    let title: String
    var trailing: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(NathanStyle.text)
            Spacer()
            if let trailing {
                if let action {
                    Button(trailing, action: action)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(NathanStyle.text2)
                } else {
                    Text(trailing).font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(NathanStyle.text3)
                }
            }
        }
    }
}

/// A small stat tile: label, big number + unit, one footer line (usually a coloured delta).
struct NathanTile: View {
    let label: String
    let value: String
    var unit: String = ""
    var footer: String? = nil
    var footerColor: Color = NathanStyle.text3
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).font(NathanStyle.label).tracking(0.6).foregroundStyle(NathanStyle.text3)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(NathanStyle.number(32)).foregroundStyle(NathanStyle.text)
                    .lineLimit(1).minimumScaleFactor(0.6)
                if !unit.isEmpty {
                    Text(unit).font(.system(size: 15, weight: .medium, design: .rounded)).foregroundStyle(NathanStyle.text3)
                }
            }
            Text(footer ?? " ").font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(footerColor).lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NathanStyle.card, in: RoundedRectangle(cornerRadius: NathanStyle.tileRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NathanStyle.tileRadius, style: .continuous).stroke(NathanStyle.line, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// Score ring. `fraction` 0…1 fills clockwise from 12 o'clock. `target` (0…1 range) draws a faint
/// band plus a tick at its start — the strain ring's "aim for at least this much today" marker.
struct NathanRing<Center: View>: View {
    let fraction: Double?
    let color: Color
    var size: CGFloat = 104
    var lineWidth: CGFloat = 8
    var target: ClosedRange<Double>? = nil
    @ViewBuilder var center: () -> Center

    var body: some View {
        ZStack {
            Circle().stroke(NathanStyle.inset, lineWidth: lineWidth)
            if let target {
                Circle()
                    .trim(from: max(0, target.lowerBound), to: min(1, target.upperBound))
                    .stroke(color.opacity(0.28), style: StrokeStyle(lineWidth: lineWidth))
                    .rotationEffect(.degrees(-90))
            }
            if let fraction, fraction > 0 {
                Circle()
                    .trim(from: 0, to: min(1, fraction))
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            if let target {
                Capsule()
                    .fill(NathanStyle.text)
                    .frame(width: 3, height: lineWidth + 6)
                    .offset(y: -size / 2 + lineWidth / 2)
                    .rotationEffect(.degrees(360 * max(0, min(1, target.lowerBound))))
            }
            center()
        }
        .frame(width: size, height: size)
    }
}

/// One point of a small index-based trend line.
struct NathanPoint: Identifiable {
    let x: Int
    let y: Double
    var id: Int { x }
}

/// Lets the custom screens switch tabs (e.g. Today's "next lift" row opens the Lift tab).
private struct NathanSelectTabKey: EnvironmentKey {
    static let defaultValue: (Int) -> Void = { _ in }
}

extension EnvironmentValues {
    var nathanSelectTab: (Int) -> Void {
        get { self[NathanSelectTabKey.self] }
        set { self[NathanSelectTabKey.self] = newValue }
    }
}

enum NathanTab {
    static let today = 0, sleep = 1, lift = 2, body = 3, more = 4
}
