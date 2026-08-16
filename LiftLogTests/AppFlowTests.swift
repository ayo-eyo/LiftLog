import Testing
import SwiftData
@testable import LiftLog

@Suite("RootTabView.workoutToResume — начать/продолжить")
struct RootTabViewResumeTests {
    @Test("при наличии активной тренировки возвращается она, новая не создаётся")
    func returnsExistingActiveWorkout() throws {
        let store = try TestStore.open()
        let active = Fixtures.workout(in: store.context)

        let resumed = RootTabView.workoutToResume(activeWorkouts: [active], context: store.context)

        #expect(resumed.persistentModelID == active.persistentModelID)
        #expect(try store.count(Workout.self) == 1)
    }

    @Test("без активной тренировки создаётся новая, вставляется в контекст и сразу становится идущей")
    func createsNewWorkoutWhenNoneActive() throws {
        let store = try TestStore.open()

        let created = RootTabView.workoutToResume(activeWorkouts: [], context: store.context)

        #expect(try store.count(Workout.self) == 1)
        #expect(created.isActive == true)
    }
}

@Suite("RootTabView.accessoryText — три состояния")
struct RootTabViewAccessoryTextTests {
    @Test("идёт отдых — показывает имя упражнения и таймер")
    func showsRestingState() {
        let timer = Fixtures.restTimer()
        let now = Fixtures.date(offset: 0)
        timer.start(duration: 65, exerciseName: "Присед", now: now)

        let text = RootTabView.accessoryText(restTimer: timer, hasActiveWorkout: true, at: now)

        #expect(text == "Присед · 1:05")
    }

    @Test("тренировка идёт, отдыха нет")
    func showsWorkoutInProgress() {
        let timer = Fixtures.restTimer()
        let text = RootTabView.accessoryText(restTimer: timer, hasActiveWorkout: true, at: Fixtures.date(offset: 0))
        #expect(text == "Тренировка идёт")
    }

    @Test("нет активной тренировки — предлагает начать")
    func showsStartPrompt() {
        let timer = Fixtures.restTimer()
        let text = RootTabView.accessoryText(restTimer: timer, hasActiveWorkout: false, at: Fixtures.date(offset: 0))
        #expect(text == "Начать тренировку")
    }
}

@Suite("WorkoutExerciseLogView.prefill — приоритет предзаполнения")
struct WorkoutExerciseLogViewPrefillTests {
    @Test("план тренировки имеет приоритет над последним сетом этой тренировки и над всей историей")
    func plannedItemTakesPriority() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        // All-time history: a heavy set from a past, plan-less workout — must not
        // override the new workout's planned default.
        let pastWorkout = Fixtures.workout(exercises: [bench], in: store.context)
        Fixtures.log([(999, 99)], for: bench, in: pastWorkout, context: store.context)

        let workout = Fixtures.workout(items: [(bench, 60, 8)], in: store.context)

        let prefill = WorkoutExerciseLogView.prefill(workout: workout, exercise: bench)

        #expect(prefill.weight == 60)
        #expect(prefill.reps == 8)
    }

    @Test("без плана — последний сет в этой тренировке")
    func fallsBackToSessionLast() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        let workout = Fixtures.workout(exercises: [bench], in: store.context)
        Fixtures.log([(60, 8), (65, 6)], for: bench, in: workout, context: store.context)

        let prefill = WorkoutExerciseLogView.prefill(workout: workout, exercise: bench)

        #expect(prefill.weight == 65)
        #expect(prefill.reps == 6)
    }

    @Test("без плана и без сетов в этой тренировке — последний сет за всё время")
    func fallsBackToAllTimeLast() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        let pastWorkout = Fixtures.workout(exercises: [bench], in: store.context)
        Fixtures.log([(70, 5)], for: bench, in: pastWorkout, context: store.context)

        let newWorkout = Fixtures.workout(exercises: [bench], in: store.context)
        let prefill = WorkoutExerciseLogView.prefill(workout: newWorkout, exercise: bench)

        #expect(prefill.weight == 70)
        #expect(prefill.reps == 5)
    }

    @Test("ничего нет — пустые дефолты")
    func emptyWhenNothingToFallBackTo() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        let workout = Fixtures.workout(exercises: [bench], in: store.context)

        let prefill = WorkoutExerciseLogView.prefill(workout: workout, exercise: bench)

        #expect(prefill.weight == nil)
        #expect(prefill.reps == nil)
    }
}

@Suite("ExercisePickerView.filteredGroups")
struct ExercisePickerViewFilterTests {
    static let groups: [(muscle: String, exercises: [CatalogExercise])] = [
        (
            muscle: "chest",
            exercises: [
                CatalogExercise(id: "a", name: "Жим лёжа", force: nil, level: nil, mechanic: nil, equipment: nil, primaryMuscles: ["chest"], secondaryMuscles: [], instructions: [], category: "strength"),
                CatalogExercise(id: "b", name: "Разводка", force: nil, level: nil, mechanic: nil, equipment: nil, primaryMuscles: ["chest"], secondaryMuscles: [], instructions: [], category: "strength"),
            ]
        ),
        (
            muscle: "quadriceps",
            exercises: [
                CatalogExercise(id: "c", name: "Присед", force: nil, level: nil, mechanic: nil, equipment: nil, primaryMuscles: ["quadriceps"], secondaryMuscles: [], instructions: [], category: "strength"),
            ]
        ),
    ]

    @Test("уже добавленные catalogID исключаются")
    func excludesAlreadyAddedCatalogIDs() {
        let result = ExercisePickerView.filteredGroups(Self.groups, excluding: ["a"], searchText: "")

        let allIDs = result.flatMap { $0.exercises.map(\.id) }
        #expect(!allIDs.contains("a"))
        #expect(allIDs.contains("b"))
        #expect(allIDs.contains("c"))
    }

    @Test("группа, полностью исключённая поиском/exclusion, пропадает из результата")
    func groupDisappearsWhenEmptyAfterFilter() {
        let result = ExercisePickerView.filteredGroups(Self.groups, excluding: ["c"], searchText: "")

        #expect(result.map(\.muscle) == ["chest"])
    }

    @Test("поиск по имени регистронезависим и фильтрует внутри групп")
    func searchFiltersCaseInsensitively() {
        let result = ExercisePickerView.filteredGroups(Self.groups, excluding: [], searchText: "жим")

        #expect(result.flatMap { $0.exercises.map(\.id) } == ["a"])
    }
}
