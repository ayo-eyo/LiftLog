import SwiftUI
import SwiftData
import Charts

/// The «Аналитика» tab (plans/features/progress-analytics, FR-5): a period summary against
/// the period before, volume by week, muscle load, recent records and every exercise's
/// trend. Only finished workouts count (decision 8).
struct AnalyticsView: View {
    @Query(filter: #Predicate<Workout> { $0.completedAt != nil })
    private var completedWorkouts: [Workout]
    @Query(sort: \Exercise.name)
    private var exercises: [Exercise]

    @State private var period: AnalyticsPeriod = .month
    @State private var snapshot: AnalyticsSnapshot?

    /// What the snapshot depends on. Summing every set here is a cheap linear pass next to
    /// the grouping and record passes it guards, and reading the sets is also what makes an
    /// edit to a finished workout's set refresh the tab.
    private struct InputKey: Hashable {
        let period: AnalyticsPeriod
        let workouts: Int
        let lastCompleted: Date?
        let sets: Int
        let volume: Double
    }

    private var inputKey: InputKey {
        var sets = 0
        var volume = 0.0
        for exercise in exercises {
            for set in exercise.sets {
                sets += 1
                volume += set.weight * Double(set.reps)
            }
        }
        return InputKey(
            period: period,
            workouts: completedWorkouts.count,
            lastCompleted: completedWorkouts.compactMap(\.completedAt).max(),
            sets: sets,
            volume: volume
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if let snapshot {
                    if snapshot.hasHistory {
                        content(snapshot)
                    } else {
                        ContentUnavailableView(
                            "Пока нечего анализировать",
                            systemImage: "chart.xyaxis.line",
                            description: Text("Заверши первую тренировку — здесь появится статистика")
                        )
                        .accessibilityIdentifier("analytics.empty")
                    }
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.chalk)
            .navigationTitle("Аналитика")
        }
        .task(id: inputKey) {
            snapshot = TrainingAnalytics.snapshot(
                exercises: exercises.map { AnalyticsExercise($0) },
                workouts: completedWorkouts.compactMap { AnalyticsWorkout($0) },
                period: period,
                now: .now,
                calendar: .current
            )
        }
    }

    private func content(_ snapshot: AnalyticsSnapshot) -> some View {
        List {
            Section {
                Picker("Период", selection: $period) {
                    ForEach(AnalyticsPeriod.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("analytics.period")
                summaryGrid(snapshot)
            }
            .listRowBackground(Color.chalk)
            .listRowSeparator(.hidden)

            Section {
                volumeChart(snapshot)
            } header: {
                sectionHeader(snapshot.bucketsAreMonthly ? "Объём по месяцам" : "Объём по неделям")
            }
            .listRowBackground(Color.chalk)

            Section {
                muscleLoad(snapshot)
            } header: {
                sectionHeader("Нагрузка мышц")
            }
            .listRowBackground(Color.chalk)

            Section {
                recordRows(snapshot)
            } header: {
                sectionHeader("Рекорды за период")
            }
            .listRowBackground(Color.chalk)

            Section {
                trendRows(snapshot)
            } header: {
                sectionHeader("Упражнения")
            }
            .listRowBackground(Color.chalk)
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: Summary

    private func summaryGrid(_ snapshot: AnalyticsSnapshot) -> some View {
        let current = snapshot.summary
        let previous = snapshot.previousSummary
        // No data before this period at all → no comparison, rather than a "+100 %".
        let compares = !previous.isEmpty
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            summaryTile("Тренировки", value: "\(current.workouts)",
                        delta: compares ? Self.signed(current.workouts - previous.workouts) : nil, id: "workouts")
            summaryTile("Подходы", value: "\(current.sets)",
                        delta: compares ? Self.signed(current.sets - previous.sets) : nil, id: "sets")
            summaryTile("Объём", value: ProgressFormat.kg(current.volume),
                        delta: compares ? TrainingAnalytics.percentChange(from: previous.volume, to: current.volume).map(Self.percent) : nil, id: "volume")
            summaryTile("Время", value: Self.duration(current.duration),
                        delta: compares ? TrainingAnalytics.percentChange(from: previous.duration, to: current.duration).map(Self.percent) : nil, id: "time")
        }
    }

    private func summaryTile(_ title: String, value: String, delta: String?, id: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.sans(12))
                .foregroundStyle(.steel)
            Text(value)
                .font(.mono(18))
                .foregroundStyle(.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(delta.map { "\($0) к прошлому" } ?? " ")
                .font(.sans(11))
                .foregroundStyle(.steel)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.chalkDeep, in: .rect(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("analytics.summary.\(id)")
    }

    static func signed(_ value: Int) -> String {
        value > 0 ? "+\(value)" : (value < 0 ? "−\(-value)" : "0")
    }

    static func percent(_ value: Int) -> String {
        (value > 0 ? "+" : (value < 0 ? "−" : "")) + "\(abs(value)) %"
    }

    static func duration(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    // MARK: Volume

    @ViewBuilder
    private func volumeChart(_ snapshot: AnalyticsSnapshot) -> some View {
        if snapshot.volumeBuckets.allSatisfy({ $0.volume == 0 }) {
            placeholder(snapshot.bucketsAreMonthly ? "Нет тренировок за 12 месяцев" : "Нет тренировок за 12 недель")
        } else {
            let unit: Calendar.Component = snapshot.bucketsAreMonthly ? .month : .weekOfYear
            VStack(alignment: .leading, spacing: 6) {
                Chart(snapshot.volumeBuckets) { bucket in
                    BarMark(x: .value("Период", bucket.start, unit: unit), y: .value("Объём", bucket.volume))
                        .foregroundStyle(Color.plateBlue.opacity(bucket.isCurrent ? 0.4 : 1))
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: snapshot.bucketsAreMonthly ? .dateTime.month(.abbreviated) : .dateTime.day().month(.abbreviated))
                    }
                }
                .frame(height: 160)
                .accessibilityIdentifier("analytics.volumeChart")
                Text(snapshot.bucketsAreMonthly ? "Текущий месяц ещё не закончился" : "Текущая неделя ещё не закончилась")
                    .font(.sans(11))
                    .foregroundStyle(.steel)
            }
        }
    }

    // MARK: Muscles

    @ViewBuilder
    private func muscleLoad(_ snapshot: AnalyticsSnapshot) -> some View {
        if snapshot.summary.sets == 0 {
            placeholder("Нет тренировок за период")
        } else {
            HStack(spacing: 1) {
                MuscleMapView(primaryMuscles: [], side: .front, intensities: snapshot.intensities)
                MuscleMapView(primaryMuscles: [], side: .back, intensities: snapshot.intensities)
            }
            .frame(height: 240)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.muscleMapLabel(snapshot.muscleLoad))
            .accessibilityIdentifier("analytics.muscleMap")

            if !snapshot.underloaded.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Мало нагружены")
                        .font(.sans(13))
                        .foregroundStyle(.ink)
                    Text(snapshot.underloaded.map(\.capitalized).joined(separator: ", "))
                        .font(.sans(13))
                        .foregroundStyle(.steel)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("analytics.underloaded")
            }
            Text("Без учёта упражнений с собственным весом")
                .font(.sans(11))
                .foregroundStyle(.steel)
        }
    }

    private static func muscleMapLabel(_ load: MuscleLoad) -> String {
        let top = load.volume.sorted { $0.value > $1.value }.prefix(3).map(\.key)
        return top.isEmpty ? "Карта нагрузки мышц" : "Больше всего нагружены: \(top.joined(separator: ", "))"
    }

    // MARK: Records and exercises

    @ViewBuilder
    private func recordRows(_ snapshot: AnalyticsSnapshot) -> some View {
        if snapshot.records.isEmpty {
            placeholder("Рекордов за период нет")
        } else {
            ForEach(snapshot.records) { record in
                NavigationLink {
                    progressScreen(for: record.exerciseID)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.exerciseName).font(.sans(15)).foregroundStyle(.ink)
                            Text(ProgressFormat.day(record.date)).font(.sans(12)).foregroundStyle(.steel)
                        }
                        Spacer()
                        Image(systemName: "trophy.fill").foregroundStyle(.plateRed)
                        Text(ProgressFormat.kg(record.weight)).font(.mono(14)).foregroundStyle(.ink)
                    }
                }
            }
        }
    }

    private func trendRows(_ snapshot: AnalyticsSnapshot) -> some View {
        ForEach(Array(snapshot.trends.enumerated()), id: \.element.id) { index, trend in
            NavigationLink {
                progressScreen(for: trend.exerciseID)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(trend.name).font(.sans(15)).foregroundStyle(.ink)
                        Text(ProgressFormat.day(trend.lastDate)).font(.sans(12)).foregroundStyle(.steel)
                    }
                    Spacer()
                    if let value = trend.value {
                        Text(ProgressFormat.value(value, metric: trend.metric)).font(.mono(14)).foregroundStyle(.ink)
                    }
                    if let direction = trend.direction {
                        trendArrow(direction)
                    }
                }
            }
            .accessibilityIdentifier("analytics.exercise.\(index)")
        }
    }

    @ViewBuilder
    private func trendArrow(_ direction: ExerciseTrend.Direction) -> some View {
        switch direction {
        case .up:
            Image(systemName: "arrow.up.right").foregroundStyle(.plateGreen).accessibilityLabel("растёт")
        case .down:
            Image(systemName: "arrow.down.right").foregroundStyle(.plateRed).accessibilityLabel("падает")
        case .flat:
            Image(systemName: "arrow.right").foregroundStyle(.steel).accessibilityLabel("без изменений")
        }
    }

    @ViewBuilder
    private func progressScreen(for exerciseID: PersistentIdentifier) -> some View {
        if let exercise = exercises.first(where: { $0.persistentModelID == exerciseID }) {
            ExerciseDetailView(exercise: exercise)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title).font(.mono(12)).foregroundStyle(.steel)
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.sans(13))
            .foregroundStyle(.steel)
            .frame(maxWidth: .infinity, minHeight: 60)
    }
}
