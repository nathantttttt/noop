//
//  LiftSetupNotes.swift
//  NOOP (Nathan's build)
//
//  Where a machine is set for each exercise: the pulley pin on a cable, the seat and pad holes on a leg
//  press, extension or curl. One short line per exercise NAME, so it follows the exercise into every
//  program and session. Kept on this device (UserDefaults).
//

import SwiftUI
import StrandDesign

@MainActor
final class LiftSetupStore: ObservableObject {
    static let shared = LiftSetupStore()
    private static let key = "lift.setupNotes"

    @Published private(set) var notes: [String: String]

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            notes = dict
        } else {
            notes = [:]
        }
    }

    static func normalized(_ exercise: String) -> String {
        exercise.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func note(for exercise: String) -> String? {
        let n = notes[Self.normalized(exercise)]
        return (n?.isEmpty ?? true) ? nil : n
    }

    func set(_ text: String, for exercise: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        notes[Self.normalized(exercise)] = clean.isEmpty ? nil : clean
        if let data = try? JSONEncoder().encode(notes) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}

/// A one-line setup reminder under an exercise's name; tap to edit. When nothing is saved yet it is a
/// faint "Add setup" so it stays out of the way.
struct LiftSetupChip: View {
    let exercise: String
    @ObservedObject private var store = LiftSetupStore.shared
    @State private var editing = false

    var body: some View {
        Button { editing = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "wrench.adjustable")
                    .font(.system(size: 11, weight: .semibold))
                if let note = store.note(for: exercise) {
                    Text(note)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                } else {
                    Text("Add setup")
                }
            }
            .font(StrandFont.caption)
            .foregroundStyle(StrandPalette.textTertiary)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $editing) {
            LiftSetupEditor(exercise: exercise, initial: store.note(for: exercise) ?? "")
        }
    }
}

struct LiftSetupEditor: View {
    let exercise: String
    @State var text: String
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    init(exercise: String, initial: String) {
        self.exercise = exercise
        _text = State(initialValue: initial)
    }

    /// Quick words for the usual adjustments; tapping one adds it to the end, ready for the number.
    private static let parts = ["Seat", "Back pad", "Leg pad", "Ankle pad", "Pulley pin", "Handle",
                                "Foot plate", "Bench angle", "Range lock", "Arm"]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(exercise)
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                TextField("e.g. Seat 4 · Back pad 2 · Pulley pin 7", text: $text, axis: .vertical)
                    .lineLimit(1...4)
                    .font(StrandFont.body)
                    .padding(12)
                    .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .focused($focused)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Self.parts, id: \.self) { part in
                            Button {
                                let t = text.trimmingCharacters(in: .whitespaces)
                                text = t.isEmpty ? "\(part) " : "\(t) · \(part) "
                                focused = true
                            } label: {
                                Text(part)
                                    .font(StrandFont.caption)
                                    .foregroundStyle(StrandPalette.textPrimary)
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(StrandPalette.surfaceRaised, in: Capsule())
                                    .overlay(Capsule().stroke(StrandPalette.hairline, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Text("Saved for this exercise in every program and session, on this phone.")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                Spacer()
            }
            .padding(20)
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationTitle("Machine setup")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        LiftSetupStore.shared.set(text, for: exercise)
                        dismiss()
                    }
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
    }
}
