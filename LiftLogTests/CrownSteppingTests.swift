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
