import SwiftUI

struct SegmentedControl<T: Hashable & CaseIterable & Identifiable>: View
where T.AllCases: RandomAccessCollection {

    @Binding var selection: T
    let title: (T) -> String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(T.allCases)) { item in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selection = item
                    }
                } label: {
                    Text(title(item))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(selection == item ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            selection == item
                                ? Color.white.opacity(0.12)
                                : .clear
                        )
                }
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.05))
        )
    }
}
