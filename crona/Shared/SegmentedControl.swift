import SwiftUI

struct SegmentedControl<T: Hashable & CaseIterable & Identifiable>: View
where T.AllCases: RandomAccessCollection {

    @Binding var selection: T
    let title: (T) -> String

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(T.allCases)) { item in
                let isSelected = selection == item
                Button {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
                        selection = item
                    }
                } label: {
                    let label = title(item)

                    Text(label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(
                            isSelected
                                ? PopupVisualTheme.selectedControlText
                                : PopupVisualTheme.secondaryText
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .background {
                    segmentBackground(isSelected: isSelected)
                }
            }
        }
        .padding(4)
        .background(
            Capsule()
                .fill(PopupVisualTheme.controlBackground)
                .overlay {
                    Capsule()
                        .strokeBorder(PopupVisualTheme.border, lineWidth: 0.8)
                }
        )
    }

    @ViewBuilder
    private func segmentBackground(isSelected: Bool) -> some View {
        if isSelected {
            Capsule()
                .fill(PopupVisualTheme.selectedControlBackground)
                .overlay {
                    Capsule()
                        .strokeBorder(PopupVisualTheme.highlightedBorder, lineWidth: 0.8)
                }
                .shadow(color: PopupVisualTheme.shadow, radius: 8, y: 5)
        } else {
            Capsule()
                .fill(Color.clear)
        }
    }
}
