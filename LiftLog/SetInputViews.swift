import SwiftUI

struct WeightInputRow: View {
    @Binding var weight: Double?
    var stepper: Binding<Double>?
    /// Overridable so two `WeightInputRow`s on screen at once (e.g. a background
    /// screen's own input plus an edit sheet presented over it) stay distinguishable
    /// to UI tests instead of colliding on the shared default.
    var accessibilityID = "weightInput"

    var body: some View {
        HStack {
            Text("Вес").font(.sans(16)).foregroundStyle(.ink)
            Spacer()
            TextField("кг", value: $weight, format: .number)
                .font(.mono(17))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .frame(width: 80)
                .padding(.vertical, 8)
                .background(.chalkDeep, in: .rect(cornerRadius: 8))
                .accessibilityIdentifier(accessibilityID)
            if let stepper {
                Stepper("", value: stepper, in: 0...500, step: 0.5)
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

    var body: some View {
        HStack {
            Text("Повторы").font(.sans(16)).foregroundStyle(.ink)
            Spacer()
            TextField("", value: $reps, format: .number)
                .font(.mono(17))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .frame(width: 80)
                .padding(.vertical, 8)
                .background(.chalkDeep, in: .rect(cornerRadius: 8))
                .accessibilityIdentifier(accessibilityID)
            if let stepper {
                Stepper("", value: stepper, in: 1...100)
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
    }
}
