//  NathanRestScreen.swift
//  Full-screen rest between sets: a big countdown ring, the set you just did (weight with −/+ and a
//  row of rep chips, both large), last time's numbers and the go-up cue, then Next set — or, after an
//  exercise's last set, a pick of the next exercise. Everything reads and writes through
//  LiftSessionController, so the timer, the strap buzz, the rest notification and the saved session
//  are exactly the ones the stock sheet uses.

import SwiftUI
import StrandDesign

struct NathanRestScreen: View {
    @ObservedObject var session: LiftSessionController
    let units: UnitSystem
    let onMinimize: () -> Void
    let onFinishWorkout: () -> Void

    private static let lbPerKg = 2.2046226218

    var body: some View {
        if let engine = session.engine, case .resting(let slot, let endsAt) = engine.stage,
           let item = engine.planItem(for: slot) {
            content(engine: engine, slot: slot, endsAt: endsAt, item: item)
        }
    }

    private func content(engine: LiftSessionEngine, slot: LiftSlot, endsAt: Int, item: LiftPlanItem) -> some View {
        let next = engine.slotAfter(slot)
        let nextInSame = next.map { $0.exerciseIndex == slot.exerciseIndex } ?? false
        return VStack(spacing: 18) {
            HStack {
                Button("Minimize", action: onMinimize)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(NathanStyle.text2)
                    .padding(.horizontal, 16).frame(height: 44)
                    .background(NathanStyle.card, in: Capsule())
                    .overlay(Capsule().stroke(NathanStyle.line, lineWidth: 1))
                Spacer()
                NathanLiftHeartRate()
            }

            VStack(spacing: 4) {
                Text(item.exercise).font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(NathanStyle.text).multilineTextAlignment(.center)
                Text("Set \(slot.setIndex + 1) of \(item.targetSets) done")
                    .font(.system(size: 14)).foregroundStyle(NathanStyle.text3)
            }

            countdown(endsAt: endsAt, total: max(1, item.restSec))

            setEntry(engine: engine, slot: slot, item: item)

            Spacer(minLength: 0)

            if engine.allCompleted {
                bigButton("Finish workout", filled: true, action: onFinishWorkout)
            } else if nextInSame {
                bigButton("Next set", filled: true) { session.advance() }
            } else {
                nextExercisePicker(engine: engine, finished: slot.exerciseIndex)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NathanStyle.canvas.ignoresSafeArea())
    }

    // MARK: Countdown

    private func countdown(endsAt: Int, total: Int) -> some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let left = max(0, Double(endsAt) - ctx.date.timeIntervalSince1970)
            let done = left <= 0
            NathanRing(fraction: done ? 1 : left / Double(total),
                       color: done ? NathanStyle.good : NathanStyle.accent, size: 210, lineWidth: 10) {
                VStack(spacing: 2) {
                    Text(done ? "Go" : Self.mmss(Int(left.rounded(.up))))
                        .font(NathanStyle.number(60)).foregroundStyle(NathanStyle.text)
                        .monospacedDigit()
                    Text(done ? "rest is up" : "of \(Self.mmss(total)) rest")
                        .font(.system(size: 13))
                        .foregroundStyle(done ? NathanStyle.good : NathanStyle.text3)
                }
            }
        }
    }

    static func mmss(_ s: Int) -> String { "\(s / 60):" + String(format: "%02d", s % 60) }

    // MARK: The set just done

    private func setEntry(engine: LiftSessionEngine, slot: LiftSlot, item: LiftPlanItem) -> some View {
        let values = session.values(of: slot)
        let last = session.lastTime(for: slot)
        let shownWeight = values.weightKg.map { toDisplay($0) }
        let top = item.targetRepsHigh ?? item.targetRepsLow
        let low = item.targetRepsLow ?? top ?? 8
        let chips = Array(max(1, low - 3)...max(low + 6, (top ?? low) + 3))
        let goUp = session.shouldGoUp(exerciseIndex: slot.exerciseIndex)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("What you just did").font(.system(size: 15, weight: .bold)).foregroundStyle(NathanStyle.text)
                Spacer()
                if let last, last.weightKg != nil || last.reps != nil {
                    Text("Last time \(last.weightKg.map { NathanFormat.one(toDisplay($0)).replacingOccurrences(of: ".0", with: "") } ?? "—") \(unitLabel) × \(last.reps.map(String.init) ?? "—")")
                        .font(.system(size: 13)).foregroundStyle(NathanStyle.text3)
                }
            }

            HStack(spacing: 10) {
                stepButton("−5") { setWeight(slot, (shownWeight ?? 0) - step) }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(shownWeight.map { NathanFormat.one($0).replacingOccurrences(of: ".0", with: "") } ?? "—")
                        .font(NathanStyle.number(40)).foregroundStyle(NathanStyle.text)
                    Text(unitLabel).font(.system(size: 15)).foregroundStyle(NathanStyle.text3)
                }
                .frame(maxWidth: .infinity).frame(height: 60)
                .background(NathanStyle.inset, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                stepButton("+5") { setWeight(slot, (shownWeight ?? 0) + step) }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(top.map { "Reps · target \($0)" } ?? "Reps")
                    .font(.system(size: 12)).foregroundStyle(NathanStyle.text3)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(chips, id: \.self) { r in
                            let on = values.reps == r
                            Button { setReps(slot, r) } label: {
                                Text("\(r)").font(NathanStyle.number(24))
                                    .frame(width: 52, height: 52)
                                    .foregroundStyle(on ? StrandPalette.goldDeepText : NathanStyle.text)
                                    .background(on ? NathanStyle.accent : NathanStyle.inset,
                                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(r) reps")
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                }
            }

            if goUp {
                Label("You hit every rep last time. Go up in weight.", systemImage: "arrow.up.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NathanStyle.accent)
            }
        }
        .padding(16)
        .background(NathanStyle.card, in: RoundedRectangle(cornerRadius: NathanStyle.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NathanStyle.cardRadius, style: .continuous).stroke(NathanStyle.line, lineWidth: 1))
    }

    private var unitLabel: String { units == .imperial ? "lb" : "kg" }
    private var step: Double { units == .imperial ? 5 : 2.5 }
    private func toDisplay(_ kg: Double) -> Double { units == .imperial ? kg * Self.lbPerKg : kg }
    private func toKg(_ v: Double) -> Double { units == .imperial ? v / Self.lbPerKg : v }

    private func setWeight(_ slot: LiftSlot, _ display: Double) {
        guard let engine = session.engine else { return }
        let v = session.values(of: slot)
        session.updateSet(slot, weightKg: toKg(max(0, display)), reps: v.reps,
                          rpe: engine.recordedSet(for: slot)?.rpe, isWarmup: session.isWarmup(slot))
    }

    private func setReps(_ slot: LiftSlot, _ reps: Int) {
        guard let engine = session.engine else { return }
        let v = session.values(of: slot)
        session.updateSet(slot, weightKg: v.weightKg, reps: reps,
                          rpe: engine.recordedSet(for: slot)?.rpe, isWarmup: session.isWarmup(slot))
    }

    // MARK: Next

    private func nextExercisePicker(engine: LiftSessionEngine, finished: Int) -> some View {
        let pending = engine.plan.indices.compactMap { i -> PendingExercise? in
            guard i != finished, let s = engine.slots(forExercise: i).first(where: { !engine.isCompleted($0) }) else { return nil }
            return PendingExercise(index: i, slot: s)
        }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Exercise done. What's next?").font(.system(size: 15, weight: .bold))
                .foregroundStyle(NathanStyle.text)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(pending) { p in
                        let i = p.index
                        Button { session.start(p.slot) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(engine.plan[i].exercise).font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(NathanStyle.text)
                                    Text("\(engine.slots(forExercise: i).filter { !engine.isCompleted($0) }.count) sets left"
                                         + (session.shouldGoUp(exerciseIndex: i) ? " · go up in weight" : ""))
                                        .font(.system(size: 12)).foregroundStyle(NathanStyle.text3)
                                }
                                Spacer()
                                Image(systemName: "play.fill").foregroundStyle(NathanStyle.accent)
                            }
                            .padding(.horizontal, 16).frame(minHeight: 56)
                            .background(NathanStyle.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(NathanStyle.line, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 220)
            bigButton("Finish workout", filled: false, action: onFinishWorkout)
        }
    }

    private func stepButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 18, weight: .bold))
                .frame(width: 64, height: 60)
                .foregroundStyle(NathanStyle.text)
                .background(NathanStyle.inset, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func bigButton(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 17, weight: .heavy))
                .frame(maxWidth: .infinity).frame(height: 58)
                .foregroundStyle(filled ? StrandPalette.goldDeepText : NathanStyle.text)
                .background(filled ? NathanStyle.accent : NathanStyle.card,
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(filled ? .clear : NathanStyle.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct PendingExercise: Identifiable {
    let index: Int
    let slot: LiftSlot
    var id: Int { index }
}

/// Live heart rate pill for the rest screen. Its own view so the 1 Hz updates stay local.
struct NathanLiftHeartRate: View {
    @EnvironmentObject var live: LiveState
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "heart.fill").foregroundStyle(NathanStyle.bad)
            Text(live.heartRate.map { "\($0) bpm" } ?? "— bpm")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(NathanStyle.text2)
                .monospacedDigit()
        }
        .padding(.horizontal, 14).frame(height: 44)
        .background(NathanStyle.card, in: Capsule())
        .overlay(Capsule().stroke(NathanStyle.line, lineWidth: 1))
    }
}
