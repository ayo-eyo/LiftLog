import SwiftUI

/// Maps free-exercise-db muscle names (as used in `primaryMuscles`/`secondaryMuscles`)
/// to body-region slugs from the MuscleMapData atlas, split by which side of the body
/// they're visible from. A muscle with no entry for a side (e.g. "chest" has no back
/// slugs, "glutes" has no front slugs) simply never highlights anything on that side.
enum MuscleAtlas {
    private static let slugs: [String: (front: [String], back: [String])] = [
        "abdominals": (["abs-upper", "abs-lower"], []),
        "abductors": ([], ["hip-left", "hip-right"]),
        "adductors": (["adductors-left-front", "adductors-right-front"], ["adductors-left-back", "adductors-right-back"]),
        "biceps": (["biceps-left", "biceps-right"], []),
        "calves": (["calves-left-front", "calves-right-front"], ["calves-left-back", "calves-right-back"]),
        "chest": (["chest-left", "chest-right"], []),
        "forearms": (["forearm-left-front", "forearm-right-front"], ["forearm-left-back", "forearm-right-back"]),
        "glutes": ([], ["gluteal-left", "gluteal-right"]),
        "hamstrings": ([], ["hamstring-left", "hamstring-right"]),
        // body-highlighter has no separate "lats" region; latissimus dorsi is folded into upper-back.
        "lats": ([], ["upper-back-left", "upper-back-right"]),
        "lower back": ([], ["lower-back-left", "lower-back-right"]),
        "middle back": ([], ["upper-back-left", "upper-back-right"]),
        "neck": (["neck-left-front", "neck-right-front"], ["neck-left-back", "neck-right-back"]),
        "quadriceps": (["quadriceps-left", "quadriceps-right"], []),
        "shoulders": (["deltoids-left-front", "deltoids-right-front"], ["deltoids-left-back", "deltoids-right-back"]),
        "traps": (["trapezius-left-front", "trapezius-right-front"], ["trapezius-left-back", "trapezius-right-back"]),
        "triceps": (["triceps-left-front", "triceps-right-front"], ["triceps-left-back", "triceps-right-back"]),
    ]

    static func frontSlugs(for muscles: [String]) -> Set<String> {
        Set(muscles.flatMap { slugs[$0]?.front ?? [] })
    }

    static func backSlugs(for muscles: [String]) -> Set<String> {
        Set(muscles.flatMap { slugs[$0]?.back ?? [] })
    }

    /// Picks whichever side actually shows something for these muscles, front first.
    static func preferredSide(primary: [String], secondary: [String]) -> MuscleMapView.Side {
        if !frontSlugs(for: primary).isEmpty { return .front }
        if !backSlugs(for: primary).isEmpty { return .back }
        if !frontSlugs(for: secondary).isEmpty { return .front }
        if !backSlugs(for: secondary).isEmpty { return .back }
        return .front
    }
}

/// Parsed, cached vector geometry for the body atlas. Parsing ~35 region paths and
/// two outline paths happens once per process, not per render.
enum MuscleMap {
    struct Region {
        let slug: String
        let path: Path
    }

    static let frontRegions: [Region] = MuscleMapData.front.map { Region(slug: $0.slug, path: SVGPath.path(from: $0.paths)) }
    static let backRegions: [Region] = MuscleMapData.back.map { Region(slug: $0.slug, path: SVGPath.path(from: $0.paths)) }
    static let outlineFront: Path = SVGPath.path(from: MuscleMapData.outlineFront)
    static let outlineBack: Path = SVGPath.path(from: MuscleMapData.outlineBack)
}

/// Renders one side of the body atlas, tinting the regions that match the given
/// muscles and drawing a thin contour outline over everything.
struct MuscleMapView: View {
    enum Side { case front, back }

    var primaryMuscles: [String]
    var secondaryMuscles: [String] = []
    var side: Side
    /// When true, frames the view on the highlighted regions' bounding box instead
    /// of the whole body — used for small thumbnails where a full 724x1448 figure
    /// would render as a sliver.
    var zoomToHighlight = false

    private var primarySlugs: Set<String> {
        side == .front ? MuscleAtlas.frontSlugs(for: primaryMuscles) : MuscleAtlas.backSlugs(for: primaryMuscles)
    }

    private var secondarySlugs: Set<String> {
        side == .front ? MuscleAtlas.frontSlugs(for: secondaryMuscles) : MuscleAtlas.backSlugs(for: secondaryMuscles)
    }

    private var regions: [MuscleMap.Region] {
        side == .front ? MuscleMap.frontRegions : MuscleMap.backRegions
    }

    private var outline: Path {
        side == .front ? MuscleMap.outlineFront : MuscleMap.outlineBack
    }

    /// Full canvas per side is 724x1448; back-side paths are pre-offset by +724 in x
    /// (see MuscleMapData). Framing on that offset rect, rather than special-casing
    /// it, is what makes zoomed and full views share one transform.
    private var fullRect: CGRect {
        side == .front ? CGRect(x: 0, y: 0, width: 724, height: 1448) : CGRect(x: 724, y: 0, width: 724, height: 1448)
    }

    private func sourceRect(primary: Set<String>, secondary: Set<String>) -> CGRect {
        guard zoomToHighlight else { return fullRect }
        let slugs = primary.isEmpty ? secondary : primary
        guard !slugs.isEmpty else { return fullRect }

        var box: CGRect?
        for region in regions where slugs.contains(region.slug) {
            let rect = region.path.boundingRect
            box = box.map { $0.union(rect) } ?? rect
        }
        guard let highlighted = box else { return fullRect }

        let paddingX = highlighted.width * 0.25 + 16
        let paddingY = highlighted.height * 0.25 + 16
        return highlighted.insetBy(dx: -paddingX, dy: -paddingY).intersection(fullRect)
    }

    var body: some View {
        // `primarySlugs`/`secondarySlugs` each build a fresh `Set` from the muscle atlas —
        // hoisted out of the per-region loop below so a ~35-region draw builds them once,
        // not ~70 times (this view renders once per row in lists with hundreds of rows).
        let primary = primarySlugs
        let secondary = secondarySlugs
        let rect = sourceRect(primary: primary, secondary: secondary)


        Canvas { context, size in
            guard rect.width > 0, rect.height > 0 else { return }
            let scale = min(size.width / rect.width, size.height / rect.height)
            let tx = (size.width - rect.width * scale) / 2 - rect.minX * scale
            let ty = (size.height - rect.height * scale) / 2 - rect.minY * scale
            context.transform = CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: tx, ty: ty)

            for region in regions {
                let color: Color
                if primary.contains(region.slug) {
                    color = .plateBlue
                } else if secondary.contains(region.slug) {
                    color = .steelLight
                } else {
                    color = .chalkDeep
                }
                context.fill(region.path, with: .color(color))
            }
            context.stroke(outline, with: .color(.steel.opacity(0.55)), lineWidth: max(1, 1.4 / scale))
        }
    }
}

/// Front + back pair for detail screens, at full body scale.
struct MuscleMapHero: View {
    var primaryMuscles: [String]
    var secondaryMuscles: [String] = []
    var height: CGFloat = 200

    var body: some View {
        HStack(spacing: 1) {
            MuscleMapView(primaryMuscles: primaryMuscles, secondaryMuscles: secondaryMuscles, side: .front)
            MuscleMapView(primaryMuscles: primaryMuscles, secondaryMuscles: secondaryMuscles, side: .back)
        }
        // Unlike `ExerciseThumbnail`, this is the primary content of the screens that
        // show it — a `Canvas` is otherwise invisible to VoiceOver.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .background(.chalkDeep)
    }

    private var accessibilityLabel: String {
        var parts: [String] = []
        if !primaryMuscles.isEmpty {
            parts.append("основные мышцы: \(primaryMuscles.joined(separator: ", "))")
        }
        if !secondaryMuscles.isEmpty {
            parts.append("вспомогательные: \(secondaryMuscles.joined(separator: ", "))")
        }
        return parts.isEmpty ? "Карта мышц" : parts.joined(separator: ", ")
    }
}
