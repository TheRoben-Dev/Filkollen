import SwiftUI

struct GradientIcon: View {
    let symbol: String
    let gradient: LinearGradient
    var size: CGFloat = 44

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(gradient)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.48, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .shadow(color: .black.opacity(0.25), radius: size * 0.12, y: size * 0.06)
    }
}

extension GradientIcon {
    init(_ category: JunkCategory, size: CGFloat = 44) {
        self.init(symbol: category.symbol, gradient: category.gradient, size: size)
    }
}
