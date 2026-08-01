import SwiftUI
import SwiftData

struct EditSetView: View {
    @Bindable var set: WorkoutSet
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                HStack {
                    Text("Вес").font(.sans(16)).foregroundStyle(.ink)
                    Spacer()
                    TextField("кг", value: $set.weight, format: .number)
                        .font(.mono(17))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .frame(width: 80)
                        .padding(.vertical, 8)
                        .background(.chalkDeep, in: .rect(cornerRadius: 8))
                }
                HStack {
                    Text("Повторы").font(.sans(16)).foregroundStyle(.ink)
                    Spacer()
                    TextField("", value: $set.reps, format: .number)
                        .font(.mono(17))
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .frame(width: 80)
                        .padding(.vertical, 8)
                        .background(.chalkDeep, in: .rect(cornerRadius: 8))
                }
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
