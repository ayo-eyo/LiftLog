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
            .navigationTitle("Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
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
                "Load from file?",
                isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } }),
                presenting: pendingImport
            ) { pending in
                if pending.preview.hasChanges {
                    Button("Load") { applyImport(pending.file) }
                }
                Button(pending.preview.hasChanges ? "Cancel" : "Got it", role: .cancel) {}
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
                Label("Export the whole history (JSON)", systemImage: "square.and.arrow.up")
            }
            .disabled(isExporting)
            .accessibilityIdentifier("dataManagement.exportJSON")

            Button {
                exportCSV()
            } label: {
                Label("Export sets (CSV)", systemImage: "tablecells")
            }
            .disabled(isExporting)
            .accessibilityIdentifier("dataManagement.exportCSV")
        } header: {
            sectionHeader("Export")
        } footer: {
            Text("JSON can be loaded back — on this phone or a new one. CSV opens in Numbers and Excel.")
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
                Label("Load from file", systemImage: "square.and.arrow.down")
            }
            .accessibilityIdentifier("dataManagement.import")

            if let importStatus {
                Text(importStatus)
                    .font(.sans(13))
                    .foregroundStyle(.steel)
                    .accessibilityIdentifier("dataManagement.importStatus")
            }
        } header: {
            sectionHeader("Import")
        } footer: {
            Text("Only workouts the app doesn’t have yet are added. Existing ones aren’t changed.")
                .font(.sans(12))
        }
        .font(.sans(15))
        .listRowBackground(Color.chalk)
    }

    private var summarySection: some View {
        Section {
            LabeledContent("Workouts", value: "\(workouts.count)")
                .accessibilityIdentifier("dataManagement.summary.workouts")
            LabeledContent("Sets", value: "\(sets.count)")
                .accessibilityIdentifier("dataManagement.summary.sets")
            LabeledContent("Exercises", value: "\(exercises.count)")
                .accessibilityIdentifier("dataManagement.summary.exercises")
        } header: {
            sectionHeader("In the app")
        } footer: {
            Text("The iPhone’s system backup (iCloud or a computer) also keeps this data along with the rest of the phone. An export file is a separate copy in your hands.")
                .font(.sans(12))
        }
        .font(.sans(15))
        .listRowBackground(Color.chalk)
    }

    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title).font(.mono(12)).foregroundStyle(.steel)
    }

    // MARK: Export

    private func exportJSON() {
        let file: BackupFile
        do {
            file = try BackupExporter.makeFile(context: context)
        } catch {
            notice = Notice(title: String(localized: "Couldn’t export"), text: error.localizedDescription)
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
                notice = Notice(title: String(localized: "Couldn’t export"), text: error.localizedDescription)
            }
        }
    }

    private func exportCSV() {
        let file: BackupFile
        do {
            file = try BackupExporter.makeFile(context: context)
        } catch {
            notice = Notice(title: String(localized: "Couldn’t export"), text: error.localizedDescription)
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
                notice = Notice(title: String(localized: "Couldn’t export"), text: error.localizedDescription)
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
            notice = Notice(title: String(localized: "Couldn’t open the file"), text: error.localizedDescription)
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
            notice = Notice(title: String(localized: "Couldn’t read the file"), text: error.localizedDescription)
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
            importStatus = String(localized: "Couldn’t load: \(error.localizedDescription)")
        }
    }

    // MARK: Text

    static func previewText(_ preview: ImportPreview) -> String {
        guard preview.hasChanges else { return String(localized: "Everything in this file is already in the app.") }
        var lines = [String(localized: "Will be added: \(counts(workouts: preview.newWorkouts, exercises: preview.newExercises, standaloneSets: preview.newStandaloneSets)).")]
        if preview.existingWorkouts > 0 {
            lines.append(String(localized: "Already here, will be skipped: \(preview.existingWorkouts) workouts."))
        }
        if preview.activeBecomesCompleted {
            lines.append(String(localized: "The file’s running workout will be added as finished — another one is running here."))
        }
        return lines.joined(separator: "\n")
    }

    static func resultText(_ result: ImportResult) -> String {
        let added = counts(workouts: result.addedWorkouts, exercises: result.addedExercises, standaloneSets: result.addedStandaloneSets)
        return added.isEmpty ? String(localized: "Nothing added — it was all here already.") : String(localized: "Added: \(added).")
    }

    private static func counts(workouts: Int, exercises: Int, standaloneSets: Int) -> String {
        var parts: [String] = []
        if workouts > 0 { parts.append(String(localized: "\(workouts) workouts")) }
        if exercises > 0 { parts.append(String(localized: "\(exercises) exercises")) }
        if standaloneSets > 0 { parts.append(String(localized: "\(standaloneSets) sets outside a workout")) }
        return parts.joined(separator: ", ")
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
