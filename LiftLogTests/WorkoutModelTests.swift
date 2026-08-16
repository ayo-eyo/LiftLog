import Testing
import SwiftData
@testable import LiftLog

@Suite("Workout.setsFor — порядок подходов")
struct WorkoutSetsForOrderTests {
    @Test("сохраняет порядок логирования, даже если createdAt совпадает")
    func stableOrderOnTiedTimestamps() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise("Жим лёжа", in: store.context)
        let workout = Fixtures.workout(exercises: [bench], in: store.context)

        // Одинаковый createdAt имитирует пачку команд с часов, доставленных почти
        // одновременно через transferUserInfo — единственный способ вызвать реальную
        // коллизию `sorted(by:)`, который не гарантированно стабилен.
        let tiedDate = Fixtures.date(offset: 10)
        for (weight, reps) in [(60.0, 8), (65.0, 6), (70.0, 4)] {
            let set = WorkoutSet(weight: weight, reps: reps, exercise: bench, workout: workout, createdAt: tiedDate, order: workout.sets.count)
            store.context.insert(set)
            workout.sets.append(set)
            bench.sets.append(set)
        }

        let sets = workout.setsFor(bench)
        #expect(sets.map(\.weight) == [60, 65, 70])
    }

    @Test("logSet назначает возрастающий order независимо от createdAt")
    func logSetAssignsMonotonicOrder() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise("Жим лёжа", in: store.context)
        let workout = Fixtures.workout(exercises: [bench], in: store.context)

        Fixtures.log([(60, 8), (65, 6), (70, 4)], for: bench, in: workout, context: store.context)

        let orders = workout.setsFor(bench).map(\.order)
        #expect(orders == orders.sorted())
        #expect(Set(orders).count == orders.count)
    }
}

@Suite("Workout.addExercise")
struct WorkoutAddExerciseTests {
    @Test("повторное добавление того же объекта не создаёт дубль")
    func sameObjectTwiceIsNotDuplicated() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        let workout = Fixtures.workout(in: store.context)

        workout.addExercise(bench)
        workout.addExercise(bench)

        #expect(workout.exercises.count == 1)
    }

    @Test("два разных упражнения с одинаковым именем добавляются оба — дедуп только по идентичности")
    func differentObjectsSameNameBothAdded() throws {
        let store = try TestStore.open()
        let bench1 = Fixtures.exercise("Жим лёжа", in: store.context)
        let bench2 = Fixtures.exercise("Жим лёжа", in: store.context)
        let workout = Fixtures.workout(in: store.context)

        workout.addExercise(bench1)
        workout.addExercise(bench2)

        #expect(workout.exercises.count == 2)
    }

    @Test("порядок exercises соответствует порядку добавления")
    func preservesInsertionOrder() throws {
        let store = try TestStore.open()
        let squat = Fixtures.exercise("Присед", in: store.context)
        let bench = Fixtures.exercise("Жим лёжа", in: store.context)
        let row = Fixtures.exercise("Тяга", in: store.context)
        let workout = Fixtures.workout(in: store.context)

        workout.addExercise(squat)
        workout.addExercise(bench)
        workout.addExercise(row)

        #expect(workout.exercises.map(\.name) == ["Присед", "Жим лёжа", "Тяга"])
    }
}

@Suite("Workout.logSet")
struct WorkoutLogSetTests {
    @Test("вставляет WorkoutSet в контекст и связывает его с тренировкой и упражнением (inverse-связи)")
    func linksBackToWorkoutAndExercise() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        let workout = Fixtures.workout(exercises: [bench], in: store.context)

        workout.logSet(weight: 60, reps: 8, for: bench, context: store.context)
        try store.context.save()

        let set = try #require(workout.sets.first)
        #expect(set.workout === workout)
        #expect(set.exercise === bench)
        #expect(bench.sets.contains(where: { $0.persistentModelID == set.persistentModelID }))
    }

    @Test("не проверяет вес и повторы — нулевые и отрицательные значения принимаются как есть")
    func acceptsNonPositiveValuesUnvalidated() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        let workout = Fixtures.workout(exercises: [bench], in: store.context)

        workout.logSet(weight: 0, reps: 0, for: bench, context: store.context)
        workout.logSet(weight: -10, reps: -5, for: bench, context: store.context)

        #expect(workout.setsFor(bench).map(\.weight) == [0, -10])
        #expect(workout.setsFor(bench).map(\.reps) == [0, -5])
    }
}

@Suite("Workout.setsFor")
struct WorkoutSetsForTests {
    @Test("возвращает только сеты запрошенного упражнения")
    func filtersByExercise() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise("Жим лёжа", in: store.context)
        let squat = Fixtures.exercise("Присед", in: store.context)
        let workout = Fixtures.workout(exercises: [bench, squat], in: store.context)

        Fixtures.log([(60, 8)], for: bench, in: workout, context: store.context)
        Fixtures.log([(100, 5)], for: squat, in: workout, context: store.context)

        #expect(workout.setsFor(bench).map(\.weight) == [60])
    }

    @Test("для упражнения, не входящего в тренировку, — пусто")
    func exerciseNotInWorkoutIsEmpty() throws {
        let store = try TestStore.open()
        let outsider = Fixtures.exercise(in: store.context)
        let workout = Fixtures.workout(in: store.context)

        #expect(workout.setsFor(outsider).isEmpty)
    }
}

@Suite("Workout.isActive / finish")
struct WorkoutLifecycleTests {
    @Test("isActive истинно, пока completedAt == nil")
    func isActiveWhileNotCompleted() throws {
        let store = try TestStore.open()
        let workout = Fixtures.workout(in: store.context)
        #expect(workout.isActive == true)
    }

    @Test("finish() проставляет completedAt и делает isActive ложным")
    func finishSetsCompletedAt() throws {
        let store = try TestStore.open()
        let workout = Fixtures.workout(in: store.context)

        workout.finish()

        #expect(workout.completedAt != nil)
        #expect(workout.isActive == false)
    }

    @Test("повторный finish() перезаписывает время завершения")
    func repeatedFinishOverwritesCompletedAt() throws {
        let store = try TestStore.open()
        let workout = Fixtures.workout(in: store.context)

        workout.finish(now: Fixtures.date(offset: 0))
        workout.finish(now: Fixtures.date(offset: 10))

        #expect(workout.completedAt == Fixtures.date(offset: 10))
    }
}

@Suite("Workout.applyTemplate")
struct WorkoutApplyTemplateTests {
    @Test("добавляет упражнения в порядке sortedItems")
    func addsExercisesInSortedOrder() throws {
        let store = try TestStore.open()
        let squat = Fixtures.exercise("Присед", in: store.context)
        let bench = Fixtures.exercise("Жим лёжа", in: store.context)
        let template = Fixtures.template(items: [(squat, 100, 5), (bench, 60, 8)], in: store.context)
        let workout = Fixtures.workout(in: store.context)

        workout.applyTemplate(template)

        #expect(workout.exercises.map(\.name) == ["Присед", "Жим лёжа"])
        #expect(workout.template === template)
    }

    @Test("пропускает позиции с exercise == nil")
    func skipsNilExercisePositions() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        let template = Fixtures.template(in: store.context)
        template.addExercise(bench, weight: 60, reps: 8, context: store.context)
        let removable = Fixtures.exercise("Удалённое", in: store.context)
        template.addExercise(removable, weight: 1, reps: 1, context: store.context)
        // Simulates the exercise being deleted elsewhere: the TemplateItem survives,
        // its `exercise` link goes nil (no cascade from Exercise -> TemplateItem).
        template.items.last?.exercise = nil

        let workout = Fixtures.workout(in: store.context)
        workout.applyTemplate(template)

        #expect(workout.exercises.map(\.name) == ["Жим лёжа"])
    }

    @Test("не дублирует уже добавленные упражнения")
    func doesNotDuplicateAlreadyAddedExercises() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        let template = Fixtures.template(items: [(bench, 60, 8)], in: store.context)
        let workout = Fixtures.workout(exercises: [bench], in: store.context)

        workout.applyTemplate(template)

        #expect(workout.exercises.count == 1)
    }
}

@Suite("Каскад удаления Workout -> WorkoutSet")
struct WorkoutDeleteCascadeTests {
    @Test("удаление тренировки удаляет все её сеты (проверка через fetchCount после save)")
    func deletingWorkoutCascadesToSets() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        let workout = Fixtures.workout(exercises: [bench], in: store.context)
        Fixtures.log([(60, 8), (65, 6)], for: bench, in: workout, context: store.context)
        try store.context.save()

        #expect(try store.count(WorkoutSet.self) == 2)

        store.context.delete(workout)
        try store.context.save()

        #expect(try store.count(WorkoutSet.self) == 0)
    }
}

@Suite("Каскад удаления Exercise -> WorkoutSet")
struct ExerciseDeleteCascadeTests {
    @Test("удаление упражнения удаляет его подходы, а не оставляет их с exercise == nil")
    func deletingExerciseCascadesToSets() throws {
        let store = try TestStore.open()
        // Стоящее особняком упражнение, без Workout: `Workout.exercises` — обычный
        // массив без @Relationship и без inverse, так что подключение сюда ещё и
        // тренировки задевало бы её отдельную (нерелевантную здесь) семантику.
        // Каскад, который проверяет этот тест, — только Exercise -> WorkoutSet.
        let bench = Fixtures.exercise("Жим лёжа", in: store.context)
        bench.addSet(weight: 60, reps: 8, context: store.context)
        bench.addSet(weight: 65, reps: 6, context: store.context)

        #expect(try store.count(WorkoutSet.self) == 2)

        store.context.delete(bench)
        try store.context.save()

        #expect(try store.count(WorkoutSet.self) == 0)
    }
}
