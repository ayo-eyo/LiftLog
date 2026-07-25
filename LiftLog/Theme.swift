import SwiftUI

extension Color {
    init(hex: String) {
        var rgb: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&rgb)
        
        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >> 8) & 0xFF) / 255
        let b = Double(rgb & 0xFF) / 255
        
        self.init(red: r, green: g, blue: b)
    }
    
    static let ink = Color(hex: "1A1A1B")
    static let chalk = Color(hex: "EDEFEA")
    static let chalkDeep = Color(hex: "E1E4DC")
    static let steel = Color(hex: "6E7570")
    static let steelLight = Color(hex: "B7BDB6")
    static let hairline = Color(hex: "D3D6CE")
    static let plateBlue = Color(hex: "2B5578")
    static let plateRed = Color(hex: "B23B2C")
    static let plateGreen = Color(hex: "4C7A4E")
    
}

extension ShapeStyle where Self == Color {
    static var ink: Color { Color.ink }
    static var chalk: Color { Color.chalk }
    static var chalkDeep: Color { Color.chalkDeep }
    static var steel: Color { Color.steel }
    static var steelLight: Color { Color.steelLight }
    static var hairline: Color { Color.hairline }
    static var plateBlue: Color { Color.plateBlue }
    static var plateRed: Color { Color.plateRed }
    static var plateGreen: Color { Color.plateGreen }
}

#Preview {
    let colors: [(String, Color)] = [
        ("Ink", .ink), ("Chalk", .chalk), ("Chalk Deep", .chalkDeep), ("Steel", .steel), ("Steel Light", .steelLight), ("Hairline", .hairline), ("Plate Blue", .plateBlue), ("Plate Red", .plateRed), ("Plate Green", .plateGreen)
    ]
    return VStack(spacing: 8) {
        ForEach(colors, id: \.0) {
            name, color in
            HStack {
                RoundedRectangle(cornerRadius: 8).fill(color).frame(width: 44, height: 44)
                Text(name)
            }
        }
    }
    .padding()
}


