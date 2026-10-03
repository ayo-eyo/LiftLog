import Testing
@testable import LiftLog

/// `CrownStepping` backs the watch's weight-entry Digital Crown. Lives in the shared
/// `WorkoutSyncModels.swift` purely so it's testable from here — see that file's header.
@Suite("CrownStepping — снап значения диджитал крауна на шаг")
struct CrownSteppingTests {
    @Test("дрейф с плавающей точкой убирается округлением до ближайшего шага 0.25")
    func floatingPointDriftIsCleared() throws {
        // What `digitalCrownRotation`'s accumulated rotation deltas actually produce —
        // this is the exact defect: displayed as a value with stray decimal digits down
        // to the ten-thousandths instead of a clean 20.
        let drifted = 20.000000000000004

        #expect(CrownStepping.snapped(drifted, step: 0.25) == 20)
    }

    @Test("значение между двумя шагами округляется до ближайшего")
    func roundsToNearestStep() throws {
        #expect(CrownStepping.snapped(20.3, step: 0.25) == 20.25)
        #expect(CrownStepping.snapped(20.4, step: 0.25) == 20.5)
    }

    @Test("значение уже на сетке шага не меняется")
    func valueAlreadyOnGridIsUnchanged() throws {
        #expect(CrownStepping.snapped(21.25, step: 0.25) == 21.25)
    }
}

/// The weight and reps crowns turn a value counted in steps, not kilograms or reps — bound
/// to kilograms, one unit of rotation ran through four 0.25 kg steps but only one rep.
@Suite("CrownStepping — колёсики веса и повторов крутят шаги, а не килограммы")
struct SteppedCrownTests {
    @Test("одно деление колёсика — ровно один шаг, у веса и у повторов одинаково", arguments: [
        (20.0, CrownStepping.weightStep),
        (10.0, CrownStepping.repsStep),
    ])
    func oneStrideIsOneStep(value: Double, step: Double) throws {
        let next = CrownStepping.crownValue(for: value, step: step) + CrownStepping.crownStride

        #expect(CrownStepping.value(forCrownValue: next, step: step) == value + step)
    }

    @Test("полный диапазон веса и повторов занимает столько делений, сколько в нём шагов")
    func rangesAreCountedInSteps() throws {
        let weightDetents = CrownStepping.crownValue(for: CrownStepping.maxWeight, step: CrownStepping.weightStep) / CrownStepping.crownStride
        let repsDetents = CrownStepping.crownValue(for: CrownStepping.maxReps, step: CrownStepping.repsStep) / CrownStepping.crownStride

        #expect(weightDetents == 2000)
        #expect(repsDetents == 50)
    }

    @Test("вес переживает путь туда и обратно через значение колёсика", arguments: [0, 0.25, 20, 57.5, 102.25, 500])
    func weightRoundTrips(weight: Double) throws {
        let crown = CrownStepping.crownValue(for: weight, step: CrownStepping.weightStep)

        #expect(CrownStepping.value(forCrownValue: crown, step: CrownStepping.weightStep) == weight)
    }

    @Test("повторы переживают путь туда и обратно через значение колёсика", arguments: [1.0, 8, 12, 50])
    func repsRoundTrip(reps: Double) throws {
        let crown = CrownStepping.crownValue(for: reps, step: CrownStepping.repsStep)

        #expect(CrownStepping.value(forCrownValue: crown, step: CrownStepping.repsStep) == reps)
    }

    @Test("вес не на сетке шага приводится к ближайшему шагу")
    func offGridWeightSnaps() throws {
        let crown = CrownStepping.crownValue(for: 20.3, step: CrownStepping.weightStep)

        #expect(CrownStepping.value(forCrownValue: crown, step: CrownStepping.weightStep) == 20.25)
    }

    @Test("дрейф колёсика между делениями не попадает в значение")
    func crownDriftIsCleared() throws {
        let drifted = CrownStepping.crownValue(for: 20, step: CrownStepping.weightStep) + 0.000000000004

        #expect(CrownStepping.value(forCrownValue: drifted, step: CrownStepping.weightStep) == 20)
    }
}
