import SwiftUI

struct WeightInputRow: View {
    @Binding var weight: Double?
    var stepper: Binding<Double>?
    /// Overridable so two `WeightInputRow`s on screen at once (e.g. a background
    /// screen's own input plus an edit sheet presented over it) stay distinguishable
    /// to UI tests instead of colliding on the shared default.
    var accessibilityID = "weightInput"

    // Field width scales with Dynamic Type instead of staying fixed, or "125,5" clips
    // at large text sizes.
    @ScaledMetric(relativeTo: .body) private var fieldWidth = 80.0
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack {
            Text("Вес").font(.sans(16)).foregroundStyle(.ink)
            Spacer()
            TextField("кг", value: $weight, format: .number)
                .font(.mono(17))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .frame(width: fieldWidth)
                .padding(.vertical, 8)
                .background(.chalkDeep, in: .rect(cornerRadius: 8))
                .accessibilityIdentifier(accessibilityID)
                .focused($isFocused)
                // Numeric keypads have no Return key; only the currently-focused field
                // contributes a "Готово" button, so this never duplicates alongside
                // RepsInputRow's own copy of the same toolbar.
                .toolbar {
                    if isFocused {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Готово") { isFocused = false }
                        }
                    }
                }
            if let stepper {
                Stepper("Вес, кг", value: stepper, in: 0...500, step: 0.25)
                    .labelsHidden()
            }
        }
    }
}

struct RepsInputRow: View {
    @Binding var reps: Int?
    var stepper: Binding<Int>?
    /// See `WeightInputRow.accessibilityID`.
    var accessibilityID = "repsInput"

    @ScaledMetric(relativeTo: .body) private var fieldWidth = 80.0
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack {
            Text("Повторы").font(.sans(16)).foregroundStyle(.ink)
            Spacer()
            TextField("Повторы", value: $reps, format: .number)
                .font(.mono(17))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .frame(width: fieldWidth)
                .padding(.vertical, 8)
                .background(.chalkDeep, in: .rect(cornerRadius: 8))
                .accessibilityIdentifier(accessibilityID)
                .focused($isFocused)
                .toolbar {
                    if isFocused {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Готово") { isFocused = false }
                        }
                    }
                }
            if let stepper {
                Stepper("Повторы", value: stepper, in: 1...100)
                    .labelsHidden()
            }
        }
    }
}

struct SetRow: View {
    let weight: Double
    let reps: Int
    var fontSize: CGFloat = 15

    var body: some View {
        HStack {
            Text(weight.formatted(.number) + " кг")
                .font(.mono(fontSize)).foregroundStyle(.ink)
            Spacer()
            Text("× \(reps)")
                .font(.mono(fontSize)).foregroundStyle(.steel)
        }
        // Otherwise VoiceOver reads "× 10" as "multiplication sign ten" across two
        // separate elements instead of one composed "75 kg, 10 reps" reading — this
        // row appears on five screens, so it's worth fixing once here.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(weight.formatted(.number)) кг, \(reps) \(RussianPlural.form(reps, "повтор", "повтора", "повторов"))")
    }
}
