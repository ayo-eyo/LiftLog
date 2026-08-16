import SwiftUI
import SwiftData

struct EditSetView: View {
    @Bindable var set: WorkoutSet
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    private var weightBinding: Binding<Double?> {
        Binding(get: { set.weight }, set: { set.weight = $0 ?? set.weight })
    }

    private var repsBinding: Binding<Int?> {
        Binding(get: { set.reps }, set: { set.reps = $0 ?? set.reps })
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                WeightInputRow(weight: weightBinding)
                RepsInputRow(reps: repsBinding)
                Button("Удалить подход", role: .destructive) {
                    context.delete(set)
                    dismiss()
                }
                .font(.sans(15))
                Spacer()
            }
            .padding()
            .background(.chalk)
            .navigationTitle("Подход")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Готово") { dismiss() }
            }
        }
    }
}
