import SwiftUI

extension Font {
    static func display(_ size: CGFloat) -> Font {
        .custom("Oswald-SemiBold", size: size)
    }
    
    static func sans(_ size: CGFloat) -> Font {
        .custom("IBMPlexSans-Regular", size: size)
    }
    
    static func mono(_ size: CGFloat) -> Font {
        .custom("IBMPlexMono-Regular", size: size)
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
