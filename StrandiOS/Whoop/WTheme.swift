//  WTheme.swift
//  Nathan's build: the WHOOP-style look. Every colour below was measured from Nathan's own WHOOP app
//  screenshots (iPhone 17 Pro, 3x), so the screens read like the app he is used to. No WHOOP artwork,
//  logo or font ships here; the type is the system font tuned to the same sizes, weights and tracking.

import SwiftUI
import UIKit

enum W {
    static func hex(_ h: UInt32, _ a: Double = 1) -> Color {
        Color(.sRGB, red: Double((h >> 16) & 0xFF) / 255, green: Double((h >> 8) & 0xFF) / 255,
              blue: Double(h & 0xFF) / 255, opacity: a)
    }

    // MARK: Surfaces
    static let bgTop = hex(0x272F34)
    static let bgMid = hex(0x15191D)
    static let bgBottom = hex(0x0E1314)
    static let cardTop = hex(0x363E43)
    static let cardBottom = hex(0x2C3033)
    static let row = hex(0x33373B)
    static let selector = hex(0x383F43)
    static let segTrack = hex(0x0C0F11)
    static let segOn = hex(0x2B3034)
    static let callout = hex(0x262A2D)
    static let inset = hex(0x1E2225)
    static let grid = Color.white.opacity(0.09)
    static let hairline = Color.white.opacity(0.10)

    // MARK: Text
    static let text = Color.white
    static let text2 = hex(0xBCBEBF)
    static let text3 = hex(0x8E9193)

    // MARK: Score colours
    static let green = hex(0x6EE846)      // recovery 67–100
    static let yellow = hex(0xF9DF4A)     // recovery 34–66
    static let red = hex(0xEA3334)        // recovery 0–33
    static let strain = hex(0x4090E0)     // strain, calories, steps
    static let sleep = hex(0x83A0B8)      // sleep bars and dial
    static let hours = hex(0x7BA1BB)      // "hours of sleep" line
    static let mint = hex(0x6EEDA5)       // sleep need, "better" deltas, optimal
    static let orange = hex(0xF2AB45)     // "worse" deltas, poor
    static let lineBlue = hex(0x77ACE1)   // HRV / RHR / resp lines, links
    static let deep = hex(0xFA95FA)
    static let rem = hex(0xAC5AED)
    static let teal = hex(0x00F19F)
    static let purple = hex(0xBC56D1)
    static let gold = hex(0xEBE19D)
    static let breakdownGray = hex(0x87898A)
    static let pillGreenBG = hex(0x234039)
    static let pillOrangeBG = hex(0x3B3526)
    static let pillGrayBG = hex(0x32363A)

    // MARK: Layout (points)
    static let margin: CGFloat = 16
    static let cardRadius: CGFloat = 12
    static let rowGap: CGFloat = 13

    static func recoveryColor(_ pct: Double?) -> Color {
        guard let pct else { return text3 }
        return pct >= 67 ? green : pct >= 34 ? yellow : red
    }

    /// Optimal 85+, sufficient 70–84, poor below: the bands WHOOP's breakdown bar uses.
    static func sleepBandColor(_ pct: Double?) -> Color {
        guard let pct else { return text3 }
        return pct >= 85 ? mint : pct >= 70 ? breakdownGray : orange
    }

    // MARK: Type
    /// The tracked all-caps label used on every card header ("HEART RATE VARIABILITY").
    static func caps(_ size: CGFloat = 13, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight)
    }
    /// Big numbers ("80 %", "21.0"): bold, slightly condensed like WHOOP's figures.
    static func num(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight).width(.condensed)
    }
    static func title(_ size: CGFloat = 26) -> Font { .system(size: size, weight: .medium) }
    static func body(_ size: CGFloat = 16, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight) }
}

// MARK: - Backgrounds

/// The page background: a cool grey-green glow at the top fading to near black.
struct WBackground: View {
    var body: some View {
        LinearGradient(stops: [.init(color: W.bgTop, location: 0),
                               .init(color: W.bgMid, location: 0.45),
                               .init(color: W.bgBottom, location: 1)],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

extension View {
    /// Page chrome for a WHOOP-style screen: gradient background and a transparent, centred caps title.
    func wPage(title: String? = nil) -> some View {
        self
            .background(WBackground())
            .scrollContentBackground(.hidden)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarRole(.editor)
            .toolbar {
                if let title {
                    ToolbarItem(placement: .principal) {
                        Text(title.uppercased()).font(W.caps(15)).tracking(1.6).foregroundStyle(W.text)
                    }
                }
            }
    }
}

// MARK: - Cards

struct WCard<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [W.cardTop, W.cardBottom], startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: W.cardRadius, style: .continuous))
    }
}

/// Card header row: tracked caps title on the left, an optional chevron or info glyph on the right.
struct WCardHeader: View {
    let title: String
    var chevron = false
    var info = false
    var body: some View {
        HStack(spacing: 8) {
            Text(title.uppercased()).font(W.caps(14)).tracking(1.5).foregroundStyle(W.text)
                .lineLimit(1).minimumScaleFactor(0.75)
            Spacer(minLength: 4)
            if info {
                Image(systemName: "info.circle").font(.system(size: 18, weight: .light)).foregroundStyle(W.text3)
            }
            if chevron {
                Image(systemName: "chevron.right").font(.system(size: 15, weight: .medium)).foregroundStyle(W.text3)
            }
        }
    }
}

/// Section heading between cards ("My Dashboard", "Weekly Trends").
struct WSectionTitle: View {
    let title: String
    var subtitle: String? = nil
    var trailing: AnyView? = nil
    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(W.title(26)).foregroundStyle(W.text)
                if let subtitle {
                    Text(subtitle).font(W.body(14)).foregroundStyle(W.text3)
                }
            }
            Spacer()
            if let trailing { trailing }
        }
        .padding(.top, 14)
    }
}

/// "NO DATA" placeholder used inside empty chart cards.
struct WNoData: View {
    var height: CGFloat = 180
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.bar.xaxis").font(.system(size: 26, weight: .light)).foregroundStyle(W.text3)
            Text("NO DATA").font(W.caps(15)).tracking(1.4).foregroundStyle(W.text)
        }
        .frame(maxWidth: .infinity, minHeight: height)
    }
}

/// The small rounded delta chip under an average ("▲ 1% vs. prior week").
struct WDeltaPill: View {
    let text: String
    let up: Bool?
    let good: Bool?
    var body: some View {
        let fg: Color = good == nil ? W.text2 : (good! ? W.mint : W.orange)
        let bg: Color = good == nil ? W.pillGrayBG : (good! ? W.pillGreenBG : W.pillOrangeBG)
        HStack(spacing: 5) {
            if let up {
                Image(systemName: up ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill").font(.system(size: 8))
            } else {
                Circle().frame(width: 6, height: 6)
            }
            Text(text).font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(fg)
        .padding(.horizontal, 7).padding(.vertical, 4)
        .background(bg, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

/// W · M · 6M segmented control: dark track, raised selected segment.
struct WSegmented<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    var body: some View {
        HStack(spacing: 4) {
            ForEach(options.indices, id: \.self) { i in
                let (value, label) = options[i]
                Button {
                    WHaptics.select()
                    withAnimation(.easeInOut(duration: 0.2)) { selection = value }
                } label: {
                    Text(label).font(W.caps(14)).tracking(1)
                        .foregroundStyle(selection == value ? W.text : W.text3)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(selection == value ? W.segOn : .clear,
                                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(W.segTrack, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Legend swatch + caps label ("■ DEEP SLEEP").
struct WLegend: View {
    let color: Color
    let label: String
    var ring = false
    var body: some View {
        HStack(spacing: 7) {
            if ring {
                Circle().stroke(color, lineWidth: 2).frame(width: 9, height: 9)
            } else {
                RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: 10, height: 10)
            }
            Text(label.uppercased()).font(W.caps(12)).tracking(1.2).foregroundStyle(W.text2)
        }
    }
}

// MARK: - Dials

/// The big score dial on the Sleep / Recovery / Strain pages and the three dials on Home.
/// `fraction` 0…1; the ring animates up from empty when it first appears.
struct WDial<Center: View>: View {
    let fraction: Double?
    let color: Color
    var size: CGFloat = 258
    var lineWidth: CGFloat = 15
    /// Optional target band (0…1 of the ring), drawn as a lighter arc with a notch at its start: the
    /// strain dial's optimal range for today's recovery.
    var target: ClosedRange<Double>? = nil
    @ViewBuilder var center: () -> Center
    @State private var shown: Double = 0

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.10), lineWidth: lineWidth)
            if let target {
                Circle()
                    .trim(from: max(0, target.lowerBound), to: min(1, target.upperBound))
                    .stroke(Color.white.opacity(0.26), style: StrokeStyle(lineWidth: lineWidth))
                    .rotationEffect(.degrees(-90))
            }
            Circle()
                .trim(from: 0, to: max(0, min(1, shown)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if let target {
                ForEach([target.lowerBound, target.upperBound], id: \.self) { f in
                    Capsule().fill(W.text)
                        .frame(width: max(2, lineWidth * 0.22), height: lineWidth + 6)
                        .offset(y: -size / 2 + lineWidth / 2)
                        .rotationEffect(.degrees(360 * max(0, min(1, f))))
                }
            }
            center()
        }
        .frame(width: size, height: size)
        .onAppear {
            shown = 0
            withAnimation(.easeOut(duration: 0.9).delay(0.1)) { shown = fraction ?? 0 }
        }
        .onChange(of: fraction) { _, new in
            withAnimation(.easeOut(duration: 0.6)) { shown = new ?? 0 }
        }
    }
}

// MARK: - Haptics

enum WHaptics {
    private static let selection = UISelectionFeedbackGenerator()
    private static let light = UIImpactFeedbackGenerator(style: .light)
    static func select() { selection.selectionChanged() }
    static func tick() { selection.selectionChanged() }
    static func tap() { light.impactOccurred() }
}

/// Press feedback for tappable cards: a slight dim and shrink while held.
struct WPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Formatting

enum WFmt {
    static func int(_ v: Double) -> String { String(Int(v.rounded())) }
    static func one(_ v: Double) -> String { String(format: "%.1f", v) }
    static func grouped(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v.rounded())) ?? int(v)
    }
    /// Minutes → "7:41".
    static func hm(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        return "\(m / 60):" + String(format: "%02d", abs(m % 60))
    }
    static func dayDate(_ key: String) -> Date? {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.date(from: key)
    }
    static func key(_ d: Date) -> String { Repository.localDayKey(d) }
    static func clock(_ ts: Int) -> String {
        let f = DateFormatter(); f.dateFormat = "h:mm a"
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }
}
