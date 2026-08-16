import AppKit
import SwiftUI
import UserNotifications

enum SettingsChromeMetrics {
    static let sidebarWidth: CGFloat = 236
    static let toolbarHeight: CGFloat = 52
}

enum SettingsLayoutMetrics {
    static let sidebarTopPadding: CGFloat = 20
    static let sidebarBottomPadding: CGFloat = 26
    static let detailHorizontalPadding: CGFloat = 28
    static let detailTopPadding: CGFloat = 20
    static let detailBottomPadding: CGFloat = 28
    static let sectionSpacing: CGFloat = 22
    static let cardHeaderSpacing: CGFloat = 10
    static let cardContentHorizontalPadding: CGFloat = 14
    static let cardContentVerticalPadding: CGFloat = 8
    static let rowVerticalPadding: CGFloat = 12
    static let rowSpacing: CGFloat = 18
    static let labelColumnWidth: CGFloat = 260
    static let controlColumnWidth: CGFloat = 178
    static let actionButtonMinimumHeight: CGFloat = 38
    static let actionButtonCornerRadius: CGFloat = 11
    static let detailCardCornerRadius: CGFloat = 14
}

struct SettingsScrollEdgeEffectModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            content
        }
    }
}

struct SettingsWindowToolbarChromeModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 27.0, *) {
            content
                .toolbar(removing: .title)
                .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        } else if #available(macOS 26.0, *) {
            content
                .toolbar(removing: .title)
                .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        } else if #available(macOS 15.0, *) {
            content
                .toolbar(removing: .title)
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        } else {
            content
        }
    }
}

struct SettingsWindowToolbarBackgroundModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content
                .toolbarBackground(.regularMaterial, for: .windowToolbar)
                .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        } else {
            content
        }
    }
}

struct SettingsPane<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(PopupVisualTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            content
        }
    }
}

struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(PopupVisualTheme.secondaryText)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(.horizontal, SettingsLayoutMetrics.cardContentHorizontalPadding)
            .padding(.vertical, SettingsLayoutMetrics.cardContentVerticalPadding)
            .background(
                PopupVisualTheme.cardBackground,
                in: RoundedRectangle(
                    cornerRadius: 12,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 12,
                    style: .continuous
                )
                .strokeBorder(PopupVisualTheme.border.opacity(0.72), lineWidth: 0.75)
            }
        }
    }
}

struct TimerDisplayStyleRow: View {
    let selection: Binding<MenuBarTimeFormat>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Timer Display")
                    .font(.subheadline.weight(.medium))
                Text("How an active timer fits in the menu bar.")
                    .foregroundStyle(PopupVisualTheme.secondaryText)
                    .font(.caption)
            }

            HStack(spacing: 12) {
                styleButton(
                    .clock,
                    detail: "A precise digital clock.",
                    preview: "04:07  ·  1:04:07"
                )
                styleButton(
                    .adaptive,
                    detail: "Compact until the final minute.",
                    preview: "1h4m  ·  4m  ·  42s"
                )
            }
        }
        .padding(.vertical, SettingsLayoutMetrics.rowVerticalPadding)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.3)
        }
    }

    private func styleButton(
        _ style: MenuBarTimeFormat,
        detail: String,
        preview: String
    ) -> some View {
        Button {
            selection.wrappedValue = style
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(style.title)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(
                        systemName: selection.wrappedValue == style
                            ? "checkmark.circle.fill"
                            : "circle"
                    )
                    .foregroundStyle(
                        selection.wrappedValue == style ? Color.accentColor : .secondary)
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(PopupVisualTheme.secondaryText)
                Text(preview)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(PopupVisualTheme.primaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(
                    cornerRadius: SettingsLayoutMetrics.actionButtonCornerRadius, style: .continuous
                )
                .fill(
                    selection.wrappedValue == style
                        ? Color.accentColor.opacity(0.12)
                        : PopupVisualTheme.primaryText.opacity(0.045)
                )
                .overlay(
                    RoundedRectangle(
                        cornerRadius: SettingsLayoutMetrics.actionButtonCornerRadius,
                        style: .continuous
                    )
                    .strokeBorder(
                        selection.wrappedValue == style
                            ? Color.accentColor.opacity(0.55)
                            : PopupVisualTheme.primaryText.opacity(0.07),
                        lineWidth: 0.8
                    )
                )
            )
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(style.title) timer display")
        .accessibilityAddTraits(selection.wrappedValue == style ? .isSelected : [])
    }
}

struct SettingsToggleRow: View {
    let title: String
    let subtitle: String
    let isOn: Binding<Bool>

    var body: some View {
        HStack(alignment: .top, spacing: SettingsLayoutMetrics.rowSpacing) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(subtitle)
                    .foregroundStyle(PopupVisualTheme.secondaryText)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: SettingsLayoutMetrics.labelColumnWidth, alignment: .leading)
            .layoutPriority(1)

            Spacer(minLength: 0)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.regular)
                .frame(width: 44, alignment: .trailing)
                .padding(.top, 2)
        }
        .padding(.vertical, SettingsLayoutMetrics.rowVerticalPadding)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.3)
        }
    }
}

struct SettingsPickerRow<SelectionValue: Hashable, Content: View>: View {
    let title: String
    let subtitle: String
    let selection: Binding<SelectionValue>
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: SettingsLayoutMetrics.rowSpacing) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(subtitle)
                    .foregroundStyle(PopupVisualTheme.secondaryText)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: SettingsLayoutMetrics.labelColumnWidth, alignment: .leading)
            .layoutPriority(1)

            Spacer(minLength: 0)

            Picker("", selection: selection) {
                content
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.regular)
            .frame(width: SettingsLayoutMetrics.controlColumnWidth, alignment: .trailing)
            .padding(.top, 2)
        }
        .padding(.vertical, SettingsLayoutMetrics.rowVerticalPadding)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.3)
        }
    }
}

struct InactivityPopupPositionRow: View {
    let selection: Binding<CompanionPopupPosition>
    var title = "Popup Position"
    var subtitle = "Choose where the reminder appears on screen."
    var accessibilityTitle = "Inactivity popup position"

    var body: some View {
        HStack(alignment: .top, spacing: SettingsLayoutMetrics.rowSpacing) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(subtitle)
                    .foregroundStyle(PopupVisualTheme.secondaryText)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: SettingsLayoutMetrics.labelColumnWidth, alignment: .leading)
            .layoutPriority(1)

            Spacer(minLength: 0)

            placementGrid
        }
        .padding(.vertical, SettingsLayoutMetrics.rowVerticalPadding)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.3)
        }
    }

    private var placementGrid: some View {
        VStack(spacing: 26) {
            positionRow([.topLeft, .topCenter, .topRight])
            positionRow([.bottomLeft, .bottomCenter, .bottomRight])
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 156, height: 82)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(PopupVisualTheme.primaryText.opacity(0.055))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(PopupVisualTheme.primaryText.opacity(0.1), lineWidth: 0.75)
                )
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityTitle)
    }

    private func positionRow(_ positions: [CompanionPopupPosition]) -> some View {
        HStack(spacing: 20) {
            ForEach(positions) { position in
                Button {
                    selection.wrappedValue = position
                } label: {
                    Circle()
                        .fill(
                            selection.wrappedValue == position
                                ? Color.accentColor : Color.secondary.opacity(0.5)
                        )
                        .frame(width: 9, height: 9)
                        .overlay {
                            if selection.wrappedValue == position {
                                Circle()
                                    .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 4)
                                    .scaleEffect(1.7)
                            }
                        }
                        .frame(width: 24, height: 24)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(position.title)
                .accessibilityAddTraits(selection.wrappedValue == position ? .isSelected : [])
            }
        }
    }
}

struct TimerHUDPositionRow: View {
    let selection: Binding<CompanionPopupPosition>

    var body: some View {
        InactivityPopupPositionRow(
            selection: selection,
            title: "Default Position",
            subtitle: "Choose where the timer first appears on screen.",
            accessibilityTitle: "Floating timer default position"
        )
    }
}

struct SettingsValueRow: View {
    let title: String
    let subtitle: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: SettingsLayoutMetrics.rowSpacing) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(subtitle)
                    .foregroundStyle(PopupVisualTheme.secondaryText)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: SettingsLayoutMetrics.labelColumnWidth, alignment: .leading)
            .layoutPriority(1)

            Spacer(minLength: 0)

            Text(value)
                .foregroundStyle(PopupVisualTheme.secondaryText)
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: SettingsLayoutMetrics.controlColumnWidth, alignment: .trailing)
                .padding(.top, 2)
        }
        .padding(.vertical, SettingsLayoutMetrics.rowVerticalPadding)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.3)
        }
    }
}

struct SettingsActionButton: View {
    let title: String
    let systemImage: String
    let prominent: Bool
    let action: () -> Void

    init(
        _ title: String,
        systemImage: String,
        prominent: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.prominent = prominent
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(minHeight: 22)
        }
        .buttonStyle(.bordered)
        .tint(prominent ? Color.accentColor : nil)
        .controlSize(.regular)
    }
}

struct SettingsActionGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 12) {
            content
        }
        .padding(.vertical, SettingsLayoutMetrics.rowVerticalPadding)
    }
}

struct SettingsActionLink: View {
    let title: String
    let systemImage: String
    let destination: URL

    var body: some View {
        Link(destination: destination) {
            Label(title, systemImage: systemImage)
                .frame(minHeight: 22)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }
}

struct SettingsPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SettingsWindowReader: NSViewRepresentable {
    let windowService: WindowService
    let appearance: CompanionAppearance

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        registerWindow(from: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        registerWindow(from: nsView)
    }

    private func registerWindow(from view: NSView) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            windowService.registerSettingsWindow(window, appearance: appearance)
        }
    }
}
