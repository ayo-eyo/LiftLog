import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// «Данные»: export the history as JSON or CSV, load a JSON backup back
/// (plans/features/backup-sync, FR-1). Presented as a sheet from the workout list.
struct DataManagementView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var workouts: [Workout]
    @Query private var exercises: [Exercise]
    @Query private var sets: [WorkoutSet]

    private struct ShareItem: Identifiable {
        let url: URL
        var id: URL { url }
    }

    private struct PendingImport {
        let file: BackupFile
        let preview: ImportPreview
    }

    private struct Notice {
        let title: String
        let text: String
    }

    @State private var shareItem: ShareItem?
    @State private var isPickingFile = false
    @State private var pendingImport: PendingImport?
    @State private var notice: Notice?
    /// Shown under the import button rather than as a second alert: presenting one alert
    /// from the button of another isn't reliable.
    @State private var importStatus: String?
    @State private var isExporting = false

    var body: some View {
        NavigationStack {
            List {
                exportSection
                importSection
                summarySection
            }
            .scrollContentBackground(.hidden)
            .background(.chalk)
            .navigationTitle("Данные")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
            .sheet(item: $shareItem) { item in
                ActivityView(activityItems: [item.url])
                    .presentationDetents([.medium, .large])
            }
            .fileImporter(isPresented: $isPickingFile, allowedContentTypes: [.json]) { result in
                readPickedFile(result)
            }
            .alert(
                "Загрузить из файла?",
                isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } }),
                presenting: pendingImport
            ) { pending in
                if pending.preview.hasChanges {
                    Button("Загрузить") { applyImport(pending.file) }
                }
                Button(pending.preview.hasChanges ? "Отмена" : "Понятно", role: .cancel) {}
            } message: { pending in
                Text(Self.previewText(pending.preview))
            }
        }
        .alert(
            notice?.title ?? "",
            isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } }),
            presenting: notice
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { notice in
            Text(notice.text)
        }
    }

    // MARK: Sections

    private var exportSection: some View {
        Section {
            Button {
                exportJSON()
            } label: {
                Label("Выгрузить всю историю (JSON)", systemImage: "square.and.arrow.up")
            }
            .disabled(isExporting)
            .accessibilityIdentifier("dataManagement.exportJSON")

            Button {
                exportCSV()
            } label: {
                Label("Выгрузить подходы (CSV)", systemImage: "tablecells")
            }
            .disabled(isExporting)
            .accessibilityIdentifier("dataManagement.exportCSV")
        } header: {
            sectionHeader("Экспорт")
        } footer: {
            Text("JSON можно загрузить обратно — на этот или на новый телефон. CSV открывается в Numbers и Excel.")
                .font(.sans(12))
        }
        .font(.sans(15))
        .listRowBackground(Color.chalk)
    }

    private var importSection: some View {
        Section {
            Button {
                importStatus = nil
                isPickingFile = true
            } label: {
                Label("Загрузить из файла", systemImage: "square.and.arrow.down")
            }
            .accessibilityIdentifier("dataManagement.import")

            if let importStatus {
                Text(importStatus)
                    .font(.sans(13))
                    .foregroundStyle(.steel)
                    .accessibilityIdentifier("dataManagement.importStatus")
            }
        } header: {
            sectionHeader("Импорт")
        } footer: {
            Text("Добавятся только тренировки, которых ещё нет в приложении. Уже существующие не меняются.")
                .font(.sans(12))
        }
        .font(.sans(15))
        .listRowBackground(Color.chalk)
    }

    private var summarySection: some View {
        Section {
            LabeledContent("Тренировки", value: "\(workouts.count)")
                .accessibilityIdentifier("dataManagement.summary.workouts")
            LabeledContent("Подходы", value: "\(sets.count)")
                .accessibilityIdentifier("dataManagement.summary.sets")
            LabeledContent("Упражнения", value: "\(exercises.count)")
                .accessibilityIdentifier("dataManagement.summary.exercises")
        } header: {
            sectionHeader("В приложении")
        } footer: {
            Text("Системная резервная копия iPhone (iCloud или компьютер) тоже сохраняет эти данные вместе со всем телефоном. Файл экспорта — отдельная копия у вас на руках.")
                .font(.sans(12))
        }
        .font(.sans(15))
        .listRowBackground(Color.chalk)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title).font(.mono(12)).foregroundStyle(.steel)
    }

    // MARK: Export

    private func exportJSON() {
        let file: BackupFile
        do {
            file = try BackupExporter.makeFile(context: context)
        } catch {
            notice = Notice(title: "Не удалось выгрузить", text: error.localizedDescription)
            return
        }
        isExporting = true
        Task {
            defer { isExporting = false }
            do {
                // Encoding years of history is the slow part — off the main actor.
                let url = try await Task.detached(priority: .userInitiated) {
                    let data = try BackupExporter.encodeJSON(file)
                    return try BackupExporter.writeTemporaryFile(data, named: BackupExporter.fileName(.json, date: file.exportedAt))
                }.value
                shareItem = ShareItem(url: url)
            } catch {
                notice = Notice(title: "Не удалось выгрузить", text: error.localizedDescription)
            }
        }
    }

    private func exportCSV() {
        let file: BackupFile
        do {
            file = try BackupExporter.makeFile(context: context)
        } catch {
            notice = Notice(title: "Не удалось выгрузить", text: error.localizedDescription)
            return
        }
        isExporting = true
        Task {
            defer { isExporting = false }
            do {
                let url = try await Task.detached(priority: .userInitiated) {
                    let data = Data(BackupExporter.csv(from: file).utf8)
                    return try BackupExporter.writeTemporaryFile(data, named: BackupExporter.fileName(.csv, date: file.exportedAt))
                }.value
                shareItem = ShareItem(url: url)
            } catch {
                notice = Notice(title: "Не удалось выгрузить", text: error.localizedDescription)
            }
        }
    }

    // MARK: Import

    private func readPickedFile(_ result: Result<URL, Error>) {
        let url: URL
        switch result {
        case .success(let picked):
            url = picked
        case .failure(let error):
            notice = Notice(title: "Не удалось открыть файл", text: error.localizedDescription)
            return
        }
        // A file picked in Files lives outside the sandbox until access is started.
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing { url.stopAccessingSecurityScopedResource() }
        }
        do {
            let file = try BackupImporter.decode(Data(contentsOf: url))
            pendingImport = PendingImport(file: file, preview: try BackupImporter.preview(file, context: context))
        } catch {
            notice = Notice(title: "Не удалось прочитать файл", text: error.localizedDescription)
        }
    }

    private func applyImport(_ file: BackupFile) {
        // A separate, non-autosaving context: nothing half-imported shows in the UI, and a
        // failed save is rolled back whole. The main context picks the result up on save.
        let importContext = ModelContext(context.container)
        importContext.autosaveEnabled = false
        do {
            let result = try BackupImporter.apply(file, context: importContext)
            importStatus = Self.resultText(result)
            WatchSessionManager.shared.refresh()
        } catch {
            importStatus = "Не удалось загрузить: \(error.localizedDescription)"
        }
    }

    // MARK: Text

    static func previewText(_ preview: ImportPreview) -> String {
        guard preview.hasChanges else { return "Всё из этого файла уже есть в приложении." }
        var lines = ["Добавится: " + counts(workouts: preview.newWorkouts, exercises: preview.newExercises, standaloneSets: preview.newStandaloneSets) + "."]
        if preview.existingWorkouts > 0 {
            lines.append("Уже есть и будут пропущены: \(count(preview.existingWorkouts, "тренировка", "тренировки", "тренировок")).")
        }
        if preview.activeBecomesCompleted {
            lines.append("Идущая тренировка из файла добавится завершённой — здесь уже идёт другая.")
        }
        return lines.joined(separator: "\n")
    }

    static func resultText(_ result: ImportResult) -> String {
        let added = counts(workouts: result.addedWorkouts, exercises: result.addedExercises, standaloneSets: result.addedStandaloneSets)
        return added.isEmpty ? "Ничего не добавлено — всё уже было." : "Добавлено: \(added)."
    }

    private static func counts(workouts: Int, exercises: Int, standaloneSets: Int) -> String {
        var parts: [String] = []
        if workouts > 0 { parts.append(count(workouts, "тренировка", "тренировки", "тренировок")) }
        if exercises > 0 { parts.append(count(exercises, "упражнение", "упражнения", "упражнений")) }
        if standaloneSets > 0 { parts.append(count(standaloneSets, "подход", "подхода", "подходов") + " вне тренировки") }
        return parts.joined(separator: ", ")
    }

    private static func count(_ value: Int, _ one: String, _ few: String, _ many: String) -> String {
        "\(value) \(RussianPlural.form(value, one, few, many))"
    }
}

/// The system share sheet. `ShareLink` needs its item up front, but the file only exists
/// once the export has run.
struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        controller.view.accessibilityIdentifier = "dataManagement.shareSheet"
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
