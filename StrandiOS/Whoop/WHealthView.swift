//  WHealthView.swift
//  Nathan's build: the WHOOP-style Health tab (round 1). Health Monitor: last night's breathing rate,
//  blood oxygen, resting heart rate, HRV and skin temperature, each checked against your own typical
//  range, with every vital opening its Trend View.

import SwiftUI

struct WHealthView: View {
    @EnvironmentObject var repo: Repository
    @EnvironmentObject var data: WhoopData

    private let vitals: [WMetric] = [.respRate, .spo2, .rhr, .hrv, .skinTemp]

    private func latest(_ m: WMetric) -> (day: String, value: Double)? { data.latest(m) }

    /// In range when inside the middle 80% of the prior 30 days (or within 1° for skin temperature).
    private func inRange(_ m: WMetric) -> Bool? {
        guard let l = latest(m) else { return nil }
        if m == .skinTemp { return abs(l.value) <= 1.8 }
        guard let d = WFmt.dayDate(l.day), let end = Calendar.current.date(byAdding: .day, value: -1, to: d) else { return nil }
        let xs = data.window(m, end: end, days: 30).compactMap(\.value).sorted()
        guard xs.count >= 7 else { return nil }
        let lo = xs[Int(Double(xs.count - 1) * 0.1)], hi = xs[Int(Double(xs.count - 1) * 0.9)]
        return l.value >= lo && l.value <= hi
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: W.rowGap) {
                Text("HEALTH").font(W.caps(15)).tracking(1.6).foregroundStyle(W.text)
                    .frame(maxWidth: .infinity).padding(.top, 8).padding(.bottom, 8)
                monitorCard
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                    ForEach(vitals) { m in
                        NavigationLink(value: WRoute.trend(m, .month)) { vitalTile(m) }
                            .buttonStyle(WPressStyle())
                    }
                }
                Text("Health Monitor compares each overnight vital with your own recent range. It is not a medical device and cannot diagnose anything.")
                    .font(W.body(14)).foregroundStyle(W.text3).padding(.top, 10)
            }
            .padding(.horizontal, W.margin)
            .padding(.bottom, 40)
        }
        .background(WBackground().overlay(
            RadialGradient(colors: [W.hex(0x5A4420, 0.55), .clear], center: .topTrailing, startRadius: 10, endRadius: 420)
                .ignoresSafeArea()))
        .refreshable { await repo.refresh() }
        .wRoutes()
    }

    private var monitorCard: some View {
        let flags = vitals.compactMap(inRange)
        let out = flags.filter { !$0 }.count
        return WCard {
            VStack(alignment: .leading, spacing: 18) {
                WCardHeader(title: "Health Monitor")
                HStack(spacing: 0) {
                    ForEach(Array(vitals.enumerated()), id: \.offset) { i, m in
                        VStack(spacing: 10) {
                            Image(systemName: m.icon).font(.system(size: 20, weight: .light)).foregroundStyle(W.text2)
                            Text(short(m)).font(W.caps(13)).tracking(1.1).foregroundStyle(W.text)
                            statusSquare(inRange(m))
                        }
                        .frame(maxWidth: .infinity)
                        if i < vitals.count - 1 { Rectangle().fill(W.hairline).frame(width: 1, height: 80) }
                    }
                }
                HStack(spacing: 10) {
                    statusSquare(flags.isEmpty ? nil : out == 0)
                    Text(flags.isEmpty ? "No data" : out == 0 ? "All metrics within range" : "\(out) metric\(out == 1 ? "" : "s") out of range")
                        .font(W.body(16)).foregroundStyle(W.text)
                    Spacer()
                }
                .padding(12)
                .background(W.segTrack.opacity(0.7), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private func short(_ m: WMetric) -> String {
        switch m {
        case .respRate: "RESP"
        case .spo2: "SPO₂"
        case .rhr: "RHR"
        case .hrv: "HRV"
        default: "TEMP"
        }
    }

    private func statusSquare(_ ok: Bool?) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(ok == nil ? W.text3.opacity(0.35) : (ok! ? W.mint.opacity(0.25) : W.orange.opacity(0.25)))
            .frame(width: 26, height: 26)
            .overlay(
                Image(systemName: ok == nil ? "minus" : (ok! ? "checkmark" : "exclamationmark"))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(ok == nil ? W.text3 : (ok! ? W.mint : W.orange)))
    }

    private func vitalTile(_ m: WMetric) -> some View {
        let l = latest(m)
        let ok = inRange(m)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: m.icon).font(.system(size: 17, weight: .light)).foregroundStyle(W.text2)
                Text(m.title.uppercased()).font(W.caps(13)).tracking(1.1).foregroundStyle(W.text)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(l.map { m.format($0.value) } ?? "--").font(W.num(32)).foregroundStyle(W.text)
                if l != nil { Text(m == .skinTemp ? "°F" : m.unit).font(W.body(15)).foregroundStyle(W.text3) }
            }
            HStack(spacing: 6) {
                Circle().fill(ok == nil ? W.text3 : (ok! ? W.mint : W.orange)).frame(width: 7, height: 7)
                Text(ok == nil ? "No data" : (ok! ? "Within range" : "Out of range")).font(W.body(14, .semibold))
            }
            .foregroundStyle(W.text)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(W.segTrack.opacity(0.7), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
        .background(LinearGradient(colors: [W.cardTop, W.cardBottom], startPoint: .top, endPoint: .bottom),
                    in: RoundedRectangle(cornerRadius: W.cardRadius, style: .continuous))
    }
}
