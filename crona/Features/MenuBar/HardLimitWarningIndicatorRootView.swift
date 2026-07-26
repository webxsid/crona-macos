import SwiftUI

struct HardLimitWarningIndicatorRootView: View {
    @ObservedObject var appState: CompanionAppState

    var body: some View {
        if let model = appState.hardLimitWarningIndicatorModel {
            let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)

            ZStack {
                shape
                    .fill(.clear)
                    .background(
                        VisualEffectView(material: .hudWindow, blendingMode: .behindWindow, emphasized: true)
                            .clipShape(shape)
                    )

                shape
                    .fill(Color.black.opacity(0.16))

                shape
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.8)

                HStack(spacing: 10) {
                    Circle()
                        .fill(Color(nsColor: model.kind.tint))
                        .frame(width: 26, height: 26)
                        .overlay {
                            Image(systemName: model.kind.symbolName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.black)
                        }

                    Text(model.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Text(model.remainingText)
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .frame(width: 190)
            .clipShape(shape)
        }
    }
}
