import SwiftUI

struct HardLimitWarningIndicatorRootView: View {
    @ObservedObject var appState: CompanionAppState

    var body: some View {
        if let model = appState.hardLimitWarningIndicatorModel {
            let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)

            ZStack {
                PopoverGlassBackground(cornerRadius: 20)

                HStack(spacing: 10) {
                    Circle()
                        .fill(Color(nsColor: model.kind.tint))
                        .frame(width: 24, height: 24)
                        .overlay {
                            Image(systemName: model.kind.symbolName)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.black)
                        }

                    Text(model.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PopupVisualTheme.primaryText)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Text(model.remainingText)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(PopupVisualTheme.primaryText)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
            }
            .frame(width: 184)
            .clipShape(shape)
            .opacity(appState.isHardLimitWarningIndicatorAnimatingIn ? 1 : 0.02)
            .blur(radius: appState.isHardLimitWarningIndicatorAnimatingIn ? 0 : 16)
            .animation(.easeOut(duration: 0.16), value: appState.isHardLimitWarningIndicatorAnimatingIn)
            .companionAppearance(appState)
        }
    }
}
