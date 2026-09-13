import SwiftUI
import Charts

/// Number and date formatting shared by the progress screen's pieces.
enum ProgressFormat {
    static func kg(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2))) + " кг"
    }

    static func value(_ value: Double, metric: ExerciseProgressMetric) -> String {
        switch metric {
        case .reps:
            let reps = Int(value.rounded())
            return "\(reps) \(RussianPlural.form(reps, "повтор", "повтора", "повторов"))"
        case .oneRepMax:
            // An estimate — hundredths would be false precision.
            return value.formatted(.number.precision(.fractionLength(0...1))) + " кг"
        case .weight, .volume:
            return kg(value)
        }
    }

    /// «3 сент.», with the year only when it isn't the current one.
    static func day(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            return date.formatted(.dateTime.day().month(.abbreviated))
        }
        return date.formatted(.dateTime.day().month(.abbreviated).year())
    }
}

/// «Рекорд веса» plus reference tiles without a trophy — 1ПМ and volume aren't records
/// (decision 2). An exercise only ever done without weight gets a lone «Макс. повторы».
struct ExerciseRecordTiles: View {
    let samples: [SetSample]
    let sessions: [ExerciseSession]

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if let record = ExerciseStats.currentRecord(samples) {
                tile(
                    title: "Рекорд веса",
                    value: ProgressFormat.kg(record.weight),
                    caption: "× \(record.reps) · \(ProgressFormat.day(record.date))",
                    isRecord: true
                )
                .accessibilityIdentifier("exerciseProgress.recordWeight")
                if let best = sessions.compactMap(\.bestOneRepMax).max() {
                    tile(title: "Лучший 1ПМ", value: ProgressFormat.value(best, metric: .oneRepMax), caption: "расчётный")
                }
                if let last = sessions.first, last.volume > 0 {
                    tile(title: "Объём", value: ProgressFormat.kg(last.volume), caption: "последний раз")
                }
            } else {
                let maxReps = sessions.map(\.maxReps).max() ?? 0
                tile(title: "Макс. повторы", value: "\(maxReps)", caption: "без веса")
                    .accessibilityIdentifier("exerciseProgress.maxReps")
            }
        }
    }

    private func tile(title: String, value: String, caption: String, isRecord: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                if isRecord {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.plateRed)
                }
                Text(title)
                    .font(.sans(12))
                    .foregroundStyle(.steel)
                    .lineLimit(1)
            }
            Text(value)
                .font(.mono(17))
                .foregroundStyle(.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption)
                .font(.sans(11))
                .foregroundStyle(.steel)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.chalkDeep, in: .rect(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}

/// One point per session, metric and period pickers above it. Sessions with a weight
/// record are drawn larger in `.plateRed`, whichever metric is shown.
struct ExerciseProgressChart: View {
    let sessions: [ExerciseSession]
    let metrics: [ExerciseProgressMetric]
    @Binding var metric: ExerciseProgressMetric
    @Binding var period: ExerciseChartPeriod

    @State private var selectedDate: Date?

    var body: some View {
        let points = ExerciseStats.chartPoints(sessions, metric: metric, period: period, now: .now, calendar: .current)
        VStack(alignment: .leading, spacing: 10) {
            if metrics.count > 1 {
                Picker("Метрика", selection: $metric) {
                    ForEach(metrics) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("exerciseProgress.metric")
            }
            Picker("Период", selection: $period) {
                ForEach(ExerciseChartPeriod.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("exerciseProgress.period")

            if points.count < 2 {
                Text(sessions.count < 2 ? "Нужно хотя бы две тренировки" : "За этот период меньше двух тренировок")
                    .font(.sans(13))
                    .foregroundStyle(.steel)
                    .frame(maxWidth: .infinity, minHeight: 140)
                    .accessibilityIdentifier("exerciseProgress.chartPlaceholder")
            } else {
                chart(points)
                if let first = points.first, let last = points.last {
                    Text("\(metric.title): \(ProgressFormat.value(first.value, metric: metric)) → \(ProgressFormat.value(last.value, metric: metric))")
                        .font(.sans(12))
                        .foregroundStyle(.steel)
                }
            }
        }
    }

    private func chart(_ points: [ExerciseChartPoint]) -> some View {
        let selected = selectedDate.flatMap { date in
            points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
        }
        return Chart {
            ForEach(points) { point in
                LineMark(x: .value("Дата", point.date), y: .value(metric.title, point.value))
                    .foregroundStyle(Color.plateBlue)
                PointMark(x: .value("Дата", point.date), y: .value(metric.title, point.value))
                    .foregroundStyle(point.hasRecord ? Color.plateRed : Color.plateBlue)
                    .symbolSize(point.hasRecord ? 70 : 28)
            }
            if let selected {
                RuleMark(x: .value("Дата", selected.date))
                    .foregroundStyle(Color.steelLight)
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(spacing: 2) {
                            Text(ProgressFormat.value(selected.value, metric: metric))
                                .font(.mono(13))
                                .foregroundStyle(.ink)
                            Text(ProgressFormat.day(selected.date))
                                .font(.sans(11))
                                .foregroundStyle(.steel)
                        }
                        .padding(6)
                        .background(.chalk, in: .rect(cornerRadius: 6))
                    }
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXSelection(value: $selectedDate)
        .frame(height: 180)
        .accessibilityIdentifier("exerciseProgress.chart")
    }
}
