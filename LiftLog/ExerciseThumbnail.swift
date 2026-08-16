import SwiftUI

struct ExerciseThumbnail: View {
    var primaryMuscles: [String]
    var secondaryMuscles: [String] = []
    var size: CGFloat = 52
    var cornerRadius: CGFloat = 11

    var body: some View {
        MuscleMapView(
            primaryMuscles: primaryMuscles,
            secondaryMuscles: secondaryMuscles,
            side: MuscleAtlas.preferredSide(primary: primaryMuscles, secondary: secondaryMuscles),
            zoomToHighlight: true
        )
        .frame(width: size, height: size)
        .background(.chalkDeep)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
