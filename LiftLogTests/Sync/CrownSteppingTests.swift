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

/// The weight crown turns a value counted in steps, not kilograms — bound to kilograms,
/// one unit of rotation ran through four 0.25 kg steps.
@Suite("CrownStepping — колёсико веса крутит шаги, а не килограммы")
struct WeightCrownTests {
    @Test("одно деление колёсика — ровно один шаг веса, как у повторов")
    func oneStrideIsOneWeightStep() throws {
        let start = CrownStepping.crownValue(forWeight: 20)
        let next = start + CrownStepping.weightCrownStride

        #expect(CrownStepping.weight(forCrownValue: next) == 20 + CrownStepping.weightStep)
    }

    @Test("вес переживает путь туда и обратно через значение колёсика", arguments: [0, 0.25, 20, 57.5, 102.25, 500])
    func weightRoundTrips(weight: Double) throws {
        let crown = CrownStepping.crownValue(forWeight: weight)

        #expect(CrownStepping.weight(forCrownValue: crown) == weight)
    }

    @Test("вес не на сетке шага приводится к ближайшему шагу")
    func offGridWeightSnaps() throws {
        let crown = CrownStepping.crownValue(forWeight: 20.3)

        #expect(CrownStepping.weight(forCrownValue: crown) == 20.25)
    }

    @Test("дрейф колёсика между делениями не попадает в вес")
    func crownDriftIsCleared() throws {
        let drifted = CrownStepping.crownValue(forWeight: 20) + 0.000000000004

        #expect(CrownStepping.weight(forCrownValue: drifted) == 20)
    }
}
