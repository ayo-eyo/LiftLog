import SwiftUI

extension Font {
    // `relativeTo:` ties each style to a specific Dynamic Type text style, so display,
    // body, and numeric text keep their relative proportions at large text sizes
    // instead of all scaling uniformly off `.body` (the default for `.custom(_:size:)`
    // without `relativeTo:`).
    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .title2) -> Font {
        .custom("Oswald-SemiBold", size: size, relativeTo: style)
    }

    static func sans(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom("IBMPlexSans-Regular", size: size, relativeTo: style)
    }

    static func mono(_ size: CGFloat, relativeTo style: Font.TextStyle = .callout) -> Font {
        .custom("IBMPlexMono-Regular", size: size, relativeTo: style)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        Text("Присед в гакк-машине").font(.display(28))
        Text("Основные мышцы: квадрицепс, ягодичные").font(.sans(16))
        Text("75,0 кг × 10").font(.mono(20))
        Text("77,5 кг × 8").font(.mono(20))
    }
    .padding()
}
