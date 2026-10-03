import SwiftUI
import SwiftData

/// «Настройки»: the app-wide progression step and rep limit (plans/features/progression,
/// FR-3) and the way into «Данные». Presented as a sheet from the workout list's gear.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(ProgressionDefaults.weightStepKey) private var weightStep = ProgressionSettings.standard.weightStep
    @AppStorage(ProgressionDefaults.repLimitKey) private var repLimit = ProgressionSettings.standard.repLimit

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ProgressionWeightStepRow(step: $weightStep)
                    ProgressionRepLimitRow(limit: $repLimit)
                } header: {
                    Text("Progression")
                } footer: {
                    Text("When a workout’s plan is done, the next one adds this much weight. Bodyweight exercises add a rep instead, up to the limit. Each exercise can have its own values on its progress screen.")
                }
                .listRowBackground(Color.chalk)

                Section {
                    NavigationLink("Data") { DataManagementView() }
                        .accessibilityIdentifier("settings.data")
                }
                .listRowBackground(Color.chalk)
            }
            .scrollContentBackground(.hidden)
            .background(.chalk)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// «Шаг прибавки» with its stepper — shared by `SettingsView` and the per-exercise override
/// on `ExerciseDetailView`.
struct ProgressionWeightStepRow: View {
    @Binding var step: Double

    var body: some View {
        Stepper(
            value: $step,
            in: ProgressionSettings.weightStepRange,
            step: ProgressionSettings.weightStepIncrement
        ) {
            HStack {
                Text("Weight step").font(.sans(16)).foregroundStyle(.ink)
                Spacer()
                Text("\(step.formatted(.number)) kg").font(.mono(15)).foregroundStyle(.steel)
            }
        }
        .accessibilityIdentifier("progression.weightStep")
    }
}

/// «Лимит повторов» with its stepper — see `ProgressionWeightStepRow`.
struct ProgressionRepLimitRow: View {
    @Binding var limit: Int

    var body: some View {
        Stepper(value: $limit, in: ProgressionSettings.repLimitRange) {
            HStack {
                Text("Rep limit").font(.sans(16)).foregroundStyle(.ink)
                Spacer()
                Text(limit, format: .number).font(.mono(15)).foregroundStyle(.steel)
            }
        }
        .accessibilityIdentifier("progression.repLimit")
    }
}

#Preview {
    SettingsView()
        .modelContainer(PreviewSupport.container())
}
