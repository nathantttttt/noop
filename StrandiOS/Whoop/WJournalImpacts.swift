//  WJournalImpacts.swift
//  Nathan's build: "Journal Impacts", WHOOP-style. For the outcome you pick (Recovery, HRV, resting
//  heart rate, sleep) every journal habit you log is ranked by how your numbers differ on the days you
//  did it versus the days you didn't, with its strongest lag (same day, next day, two days on). The
//  maths is NOOP's EffectRanker (InsightsHubViewModel); this page only presents it. Association only.

import SwiftUI
import StrandAnalytics

struct WJournalImpacts: View {
    @EnvironmentObject var repo: Repository
    @StateObject private var model = InsightsHubViewModel()
    @State private var outcome: InsightsHubViewModel.Outcome = .recovery
    @State private var expanded: String?
    @State private var showJournal = false

    private func name(_ o: InsightsHubViewModel.Outcome) -> String {
        switch o {
        case .recovery: "Recovery"
        case .hrv: "HRV"
        case .rhr: "RHR"
        case .sleep: "Sleep"
        }
    }

    private func good(_ r: RankedEffect) -> Bool? {
        r.effect.delta == 0 ? nil : ((r.effect.delta > 0) == outcome.higherIsBetter)
    }

    private func pct(_ r: RankedEffect) -> Double {
        if let p = r.effect.pctChange { return p }
        let base = r.effect.meanWithout
        return base == 0 ? 0 : r.effect.delta / abs(base) * 100
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("How the habits you log change your numbers, from your own days with and without each one. This shows association, not cause.")
                    .font(W.body(16)).foregroundStyle(W.text2).fixedSize(horizontal: false, vertical: true)
                WSegmented(options: InsightsHubViewModel.Outcome.allCases.map { ($0, name($0).uppercased()) }, selection: $outcome)
                if !model.loaded {
                    ProgressView().tint(W.text).frame(maxWidth: .infinity, minHeight: 160)
                } else if model.ranked.isEmpty {
                    WCard(padding: 22) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Keep logging").font(W.body(20, .semibold)).foregroundStyle(W.text)
                            Text("Each habit needs some days with it and some days without before NOOP can show its effect on your \(name(outcome).lowercased()). Two to three weeks of daily logging usually does it.")
                                .font(W.body(16)).foregroundStyle(W.text2).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    let pos = model.ranked.filter { good($0) == true }
                    let neg = model.ranked.filter { good($0) == false }
                    let flat = model.ranked.filter { good($0) == nil }
                    let scale = max(5, model.ranked.map { abs(pct($0)) }.max() ?? 5)
                    if !pos.isEmpty { section("Positive impacts", pos, scale) }
                    if !neg.isEmpty { section("Negative impacts", neg, scale) }
                    if !flat.isEmpty { section("No clear effect", flat, scale) }
                }
                Button { showJournal = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.pencil")
                        Text("LOG OR ADD HABITS").font(W.caps(14)).tracking(1.5)
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(W.text, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(WPressStyle())
                .padding(.top, 6)
            }
            .padding(.horizontal, W.margin)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .wPage(title: "Journal Impacts")
        .task(id: repo.refreshSeq) { await model.load(repo: repo); model.rankFor(outcome) }
        .onChange(of: outcome) { _, o in model.rankFor(o); expanded = nil }
        .fullScreenCover(isPresented: $showJournal) { NathanMorningJournal() }
    }

    private func section(_ title: String, _ rows: [RankedEffect], _ scale: Double) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).font(W.caps(13)).tracking(1.4).foregroundStyle(W.text3).padding(.top, 6)
            ForEach(rows, id: \.behavior) { r in row(r, scale) }
        }
    }

    private func row(_ r: RankedEffect, _ scale: Double) -> some View {
        let p = pct(r)
        let g = good(r)
        let color = g == nil ? W.text3 : (g! ? W.mint : W.orange)
        let open = expanded == r.behavior
        return Button {
            WHaptics.select()
            withAnimation(.easeInOut(duration: 0.22)) { expanded = open ? nil : r.behavior }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(r.behavior).font(W.body(17, .semibold)).foregroundStyle(W.text)
                            .lineLimit(2).multilineTextAlignment(.leading)
                        Text("\(p >= 0 ? "+" : "−")\(Int(abs(p).rounded()))% \(name(outcome)) · \(r.leadLagText.lowercased())")
                            .font(W.body(14)).foregroundStyle(color)
                    }
                    Spacer(minLength: 8)
                    divergingBar(p / scale, color: color).frame(width: 110, height: 10)
                }
                if open {
                    Text(r.sentence()).font(W.body(15)).foregroundStyle(W.text2).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 24) {
                        stat("WITH", outcome.format(r.effect.meanWith), "\(r.effect.nWith) days", color)
                        stat("WITHOUT", outcome.format(r.effect.meanWithout), "\(r.effect.nWithout) days", W.text)
                    }
                }
            }
            .padding(16)
            .background(W.row, in: RoundedRectangle(cornerRadius: W.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func stat(_ label: String, _ value: String, _ sub: String, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(W.caps(12)).tracking(1.2).foregroundStyle(W.text3)
            Text(value).font(W.num(24)).foregroundStyle(c)
            Text(sub).font(W.body(13)).foregroundStyle(W.text3)
        }
    }

    /// Centre-anchored bar: right for a rise, left for a fall, length relative to the biggest effect.
    private func divergingBar(_ f: Double, color: Color) -> some View {
        GeometryReader { g in
            let half = g.size.width / 2
            let len = max(3, half * min(1, abs(f)))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.07))
                Rectangle().fill(W.text3.opacity(0.6)).frame(width: 1).offset(x: half)
                Capsule().fill(color).frame(width: len).offset(x: f >= 0 ? half : half - len)
            }
        }
    }
}
