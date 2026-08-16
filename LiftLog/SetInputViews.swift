import SwiftUI

struct WeightInputRow: View {
    @Binding var weight: Double?
    var stepper: Binding<Double>?

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
