import SwiftUI

struct ExerciseThumbnail: View {
    var primaryMuscles: [String]
    var secondaryMuscles: [String] = []
    var size: CGFloat = 52
    var cornerRadius: CGFloat = 11

    @ScaledMetric(relativeTo: .body) private var scaledSize: CGFloat = 52

    var body: some View {
        // `size` doubles as an explicit override (see call sites passing 44) and as the
        // scaling base — scale relative to the ratio against the struct's own default,
        // so an explicit override still grows with Dynamic Type instead of being frozen.
        let resolvedSize = size * (scaledSize / 52)
        MuscleMapView(
            primaryMuscles: primaryMuscles,
            secondaryMuscles: secondaryMuscles,
            side: MuscleAtlas.preferredSide(primary: primaryMuscles, secondary: secondaryMuscles),
            zoomToHighlight: true
        )
        .frame(width: resolvedSize, height: resolvedSize)
        .background(.chalkDeep)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        // Purely decorative — the exercise name next to it already carries the meaning;
        // the rendered body-map silhouette adds nothing a screen reader user needs.
        .accessibilityHidden(true)
    }
}
