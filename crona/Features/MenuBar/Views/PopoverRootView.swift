import AppKit
import Combine
import SwiftUI

enum PopoverModalKind: Equatable {
    case statusNote
    case endSession
    case dueDate
    case issueCreate
    case deleteIssue

    var minimumHeight: CGFloat {
        switch self {
        case .statusNote: return 260
        case .endSession: return 360
        case .dueDate: return 430
        case .issueCreate: return 560
        case .deleteIssue: return 280
        }
    }
}

// Shared popover composition helpers end here.

// End of popover root composition.

//

private struct PopupSurfaceHeightKey: PreferenceKey {
    static let defaultValue = StatusPopupSizing.viewportHeight

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

func formattedPopoverDate(_ date: String, appState: CompanionAppState) -> String {
    let value =
        date.isEmpty
        ? (appState.daemonConnection.currentDate.isEmpty
            ? DailyFocusService.todayString() : appState.daemonConnection.currentDate)
        : date
    return CronaDateDisplayFormatter.string(
        fromISODate: value,
        settings: appState.coreSettingsService.settings
    )
}

struct PopoverRootView: View {
    @ObservedObject var appState: CompanionAppState
    let displayClock: PopupDisplayClock
    let onVisibleSurfaceHeightChange: ((CGFloat) -> Void)?
    @Environment(\.openSettings) private var openSettings

    init(
        appState: CompanionAppState,
        displayClock: PopupDisplayClock,
        onVisibleSurfaceHeightChange: ((CGFloat) -> Void)? = nil
    ) {
        self.appState = appState
        self.displayClock = displayClock
        self.onVisibleSurfaceHeightChange = onVisibleSurfaceHeightChange
    }

    var body: some View {
        ZStack(alignment: .top) {
            visibleSurface

            if hasDashboardModal || appState.isIssueCreatorPresented {
                modalSurface
                    .frame(
                        width: StatusPopupSizing.width,
                        height: StatusPopupSizing.viewportHeight,
                        alignment: .center
                    )
                    .transition(
                        .asymmetric(
                            insertion: .opacity,
                            removal: .opacity
                        )
                    )
            }
        }
        .frame(
            width: StatusPopupSizing.width,
            height: StatusPopupSizing.viewportHeight,
            alignment: .top
        )
        .clipped()
        .onPreferenceChange(PopupSurfaceHeightKey.self) { height in
            onVisibleSurfaceHeightChange?(height)
        }
        .onAppear {
            appState.registerSettingsSceneAction {
                openSettings()
            }
        }
        .companionAppearance(appState)
    }

    private var visibleSurface: some View {
        ZStack(alignment: .top) {
            dashboardSurface
                .offset(x: appState.isIssueCreatorContentVisible ? -420 : 0)
                .allowsHitTesting(!appState.isIssueCreatorPresented)
        }
        .frame(width: StatusPopupSizing.width, alignment: .top)
        .frame(minHeight: modalMinimumHeight, alignment: .top)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: PopupSurfaceHeightKey.self,
                    value: proxy.size.height
                )
            }
        }
        .background(PopoverGlassBackground())
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var dashboardSurface: some View {
        VStack(spacing: 16) {
            header

            if !appState.isStatsCalendarPresented {
                if let success = appState.issueCreationSuccess {
                    IssueCreationSuccessView(appState: appState, success: success)
                }

                if appState.appUpdateService.hasAvailableUpdate,
                    !appState.isUpdatePresentationBlocked
                {
                    Button(action: appState.checkForAppUpdates) {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundStyle(.blue)
                            Text(
                                "Crona \(appState.appUpdateService.snapshot.latestVersion ?? "") is ready"
                            )
                            .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("Update")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(PopupVisualTheme.primaryText.opacity(0.07))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if appState.isStatsCalendarPresented {
                if case .stats = appState.selectedPopoverTab {
                    StatsTabView(appState: appState)
                }
            } else if appState.hasActiveFocusSession {
                IssuesTabView(
                    appState: appState,
                    displayClock: displayClock
                )
            } else if appState.todayIsAway {
                AwayModeView(appState: appState)
            } else {
                switch appState.selectedPopoverTab {
                case .now:
                    IssuesTabView(
                        appState: appState,
                        displayClock: displayClock
                    )
                case .habits:
                    HabitsTabView(appState: appState)
                case .wellbeing:
                    WellbeingTabView(appState: appState)
                case .stats:
                    StatsTabView(appState: appState)
                }
            }

            if !appState.isStatsCalendarPresented,
                let error = appState.daemonConnection.lastErrorDescription,
                !error.isEmpty,
                appState.daemonConnection.connectionState == .connected
            {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(error)
                        .lineLimit(2)
                }
                .font(.caption2)
                .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.72))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(width: StatusPopupSizing.width)
        .opacity(hasDashboardModal ? 0.38 : 1)
        .blur(radius: hasDashboardModal ? 3 : 0)
        .scaleEffect(hasDashboardModal ? 0.985 : 1)
        .allowsHitTesting(!hasDashboardModal)
        .animation(.easeInOut(duration: 0.16), value: appState.isEndSessionSheetPresented)
        .animation(.easeInOut(duration: 0.16), value: appState.issueActionEditor)
    }

    @ViewBuilder
    private var modalSurface: some View {
        ZStack {
            PopoverGlassBackground()

            if hasDashboardModal {
                PopoverModalScrim {
                    if appState.isEndSessionSheetPresented {
                        if !appState.isSubmittingEndSession {
                            appState.cancelEndSession()
                        }
                    } else {
                        appState.cancelIssueActionEditor()
                    }
                }
            }

            if appState.isEndSessionSheetPresented {
                EndSessionSheetView(appState: appState)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.96).combined(with: .opacity),
                            removal: .opacity
                        )
                    )
            } else if appState.issueActionEditor != nil {
                IssueActionEditorView(appState: appState)
                    .padding(.horizontal, 28)
                    .transition(
                        .scale(scale: 0.96)
                            .combined(with: .opacity)
                    )
            } else if appState.isIssueCreatorPresented {
                IssueCreatorView(appState: appState)
                    .offset(x: appState.isIssueCreatorContentVisible ? 0 : 420)
                    .allowsHitTesting(appState.isIssueCreatorContentVisible)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var hasDashboardModal: Bool {
        appState.isEndSessionSheetPresented || appState.issueActionEditor != nil
    }

    private var modalMinimumHeight: CGFloat? {
        if appState.isEndSessionSheetPresented {
            return PopoverModalKind.endSession.minimumHeight
        }
        if appState.isIssueCreatorPresented {
            return PopoverModalKind.issueCreate.minimumHeight
        }
        switch appState.issueActionEditor {
        case .status:
            return PopoverModalKind.statusNote.minimumHeight
        case .dueDate:
            return PopoverModalKind.dueDate.minimumHeight
        case .manualSession:
            return 560
        case .delete:
            return PopoverModalKind.deleteIssue.minimumHeight
        case nil:
            return nil
        }
    }

    private var header: some View {
        ZStack {
            if appState.isStatsCalendarPresented {
                Text("Calendar")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(PopupVisualTheme.primaryText)
            } else if !appState.hasActiveFocusSession && !appState.todayIsAway {
                SegmentedControl(
                    selection: $appState.selectedPopoverTab,
                    title: \.title,
                    fitsContent: true
                )
                .onChange(of: appState.selectedPopoverTab) { _, newTab in
                    appState.setSelectedPopoverTab(newTab)
                }
            }

            HStack {
                if !appState.todayIsAway
                    && (appState.isStatsCalendarPresented
                        || appState.selectedPopoverTab == .stats
                        || appState.selectedPopoverTab == .now)
                {
                    Button {
                        if appState.isStatsCalendarPresented {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                appState.isStatsCalendarPresented = false
                                appState.popoverStatsService.endCalendar()
                            }
                        } else if appState.selectedPopoverTab == .stats {
                            appState.popoverStatsService.beginCalendar()
                            appState.isStatsCalendarPresented.toggle()
                        } else {
                            appState.presentIssueCreator()
                        }
                    } label: {
                        Image(
                            systemName: appState.isStatsCalendarPresented
                                ? "chevron.left"
                                : (appState.selectedPopoverTab == .stats ? "calendar" : "plus")
                        )
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.7))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(PopupVisualTheme.primaryText.opacity(0.06)))
                        .menuBarIconHitTarget()
                    }
                    .buttonStyle(.plain)
                    .help(
                        appState.isStatsCalendarPresented
                            ? "Back to stats"
                            : (appState.selectedPopoverTab == .stats
                                ? "Show calendar" : "Create Issue")
                    )
                    .accessibilityLabel(
                        appState.isStatsCalendarPresented
                            ? "Back to stats"
                            : (appState.selectedPopoverTab == .stats
                                ? "Show calendar" : "Create Issue")
                    )
                    .disabled(
                        appState.daemonConnection.connectionState != .connected
                            || appState.isEndSessionSheetPresented
                            || appState.issueActionEditor != nil
                            || appState.isIssueCreatorPresented
                            || appState.issueCreationService.isCreating
                    )
                }

                Spacer()

                Menu {
                    Button("About Crona", action: appState.openAbout)

                    Divider()

                    SettingsLink {
                        Text("Settings…")
                    }

                    Button(
                        appState.appUpdateService.hasAvailableUpdate
                            ? "Update Available…"
                            : "Check for Updates…",
                        action: appState.checkForAppUpdates
                    )
                    .disabled(!appState.appUpdateService.canCheckForUpdates)

                    Divider()

                    Button {
                        appState.setAwayMode(!appState.coreSettingsService.settings.awayModeEnabled)
                    } label: {
                        Label(
                            appState.coreSettingsService.settings.awayModeEnabled
                                ? "Disable Away"
                                : (appState.todayIsAway
                                    ? "Away Today (Rest Rule)" : "Mark Today as Away"),
                            systemImage: "figure.walk.circle"
                        )
                    }
                    .disabled(
                        appState.daemonConnection.connectionState != .connected
                            || appState.coreSettingsService.isSaving
                            || (!appState.coreSettingsService.settings.awayModeEnabled
                                && appState.todayIsAway)
                    )

                    Divider()

                    Button("Documentation", action: appState.openDocumentation)
                    Button("Feedback & Roadmap", action: appState.openFeedbackAndRoadmap)
                    Button("GitHub", action: appState.openGitHub)
                    Button("Support", action: appState.openSupport)

                    Divider()

                    Button("Stop Crona…", role: .destructive, action: appState.requestStopCrona)
                    Button("Quit Crona", action: appState.quitCrona)
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.7))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(PopupVisualTheme.primaryText.opacity(0.06)))
                        .menuBarIconHitTarget()
                }
                .buttonStyle(.plain)
                .help("Crona Menu")
                .accessibilityLabel("Open Crona Menu")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 30)
    }
}













































extension View {
    func menuBarIconHitTarget() -> some View {
        padding(7)
            .contentShape(Rectangle())
    }
}

@MainActor
final class FocusStartConfigEditor: ObservableObject {
    @Published var state: FocusStartConfigState

    init(initialState: FocusStartConfigState) {
        state = initialState
    }

    var focusDisplay: String {
        displayText(for: state.focusChoice, customMinutes: state.customFocusMinutes)
    }

    var breakDisplay: String {
        displayText(for: state.breakChoice, customMinutes: state.customBreakMinutes)
    }

    var longBreakDisplay: String {
        displayText(for: state.longBreakChoice, customMinutes: state.customLongBreakMinutes)
    }

    var countdownDisplay: String {
        displayText(for: state.countdownChoice, customMinutes: state.customCountdownMinutes)
    }

    func handleModeChange(_ mode: FocusSessionMode) {
        state.mode = mode
    }

    func selectFocus(_ choice: FocusPresetChoice) {
        state.focusChoice = choice
    }

    func selectBreak(_ choice: FocusPresetChoice) {
        state.breakChoice = choice
        if choice == .noBreak {
            state.longBreakChoice = .noBreak
            state.pomodoroCycles = 1
            state.pomodoroCyclesBeforeLongBreak = 0
        } else {
            if state.longBreakChoice == .noBreak {
                state.pomodoroCyclesBeforeLongBreak = max(4, state.pomodoroCyclesBeforeLongBreak)
            }
            state.pomodoroCycles = max(1, state.pomodoroCycles)
        }
    }

    func selectLongBreak(_ choice: FocusPresetChoice) {
        state.longBreakChoice = choice
        state.pomodoroCyclesBeforeLongBreak =
            choice == .noBreak ? 0 : max(1, state.pomodoroCyclesBeforeLongBreak)
    }

    func selectCountdown(_ choice: FocusPresetChoice) {
        state.countdownChoice = choice
    }

    private func displayText(for choice: FocusPresetChoice, customMinutes: Int) -> String {
        switch choice {
        case .custom:
            return "\(max(0, customMinutes))m"
        default:
            return choice.title
        }
    }
}









func configDisclosureHeader(
    icon: String,
    tint: Color,
    title: String,
    displayValue: String,
    isExpanded: Bool,
    action: @escaping () -> Void
) -> some View {
    Button(action: action) {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.black)
                .frame(width: 24, height: 24)
                .background(Circle().fill(tint))

            Text(title)
                .foregroundStyle(PopupVisualTheme.primaryText)
                .font(.headline)

            Spacer()

            Text(displayValue)
                .foregroundStyle(PopupVisualTheme.primaryText)
                .font(.headline.monospacedDigit())

            Image(systemName: "chevron.down")
                .font(.caption.weight(.bold))
                .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.52))
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
    }
    .buttonStyle(.plain)
}

func configOptionButton(
    title: String,
    isSelected: Bool,
    action: @escaping () -> Void
) -> some View {
    Button(action: action) {
        HStack(spacing: 5) {
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.bold))
            }
            Text(title)
                .lineLimit(1)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(PopupVisualTheme.primaryText.opacity(isSelected ? 1 : 0.72))
        .frame(maxWidth: .infinity, minHeight: 34)
        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(PopupVisualTheme.primaryText.opacity(isSelected ? 0.14 : 0.05))
                .strokeBorder(
                    PopupVisualTheme.primaryText.opacity(isSelected ? 0.16 : 0.05), lineWidth: 1)
        )
    }
    .buttonStyle(GlassPressButtonStyle())
}

func actionPill(
    _ title: String,
    fill: Color,
    shortcut: KeyboardShortcut? = nil,
    shortcutLabel: String? = nil,
    action: @escaping () -> Void
) -> some View {
    Button(action: action) {
        HStack(spacing: 7) {
            Text(title)
            if let shortcutLabel {
                Text(shortcutLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.46))
            }
        }
        .font(.headline)
        .foregroundStyle(PopupVisualTheme.primaryText)
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .contentShape(Capsule())
        .background(
            flatActionCapsuleBackground(fill: fill)
        )
    }
    .buttonStyle(GlassPressButtonStyle())
    .modifier(OptionalKeyboardShortcut(shortcut: shortcut))
}



func cardBackground(stroke: Color, cornerRadius: CGFloat = 20) -> some View {
    Color.clear
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(stroke.opacity(0.38))
                .frame(height: 0.5)
        }
}

func subtleCardBackground(stroke: Color, cornerRadius: CGFloat = 16) -> some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

    return
        shape
        .fill(PopupVisualTheme.surfaceFill.opacity(0.72))
        .overlay {
            shape.strokeBorder(
                PopupVisualTheme.surfaceStroke.opacity(0.8),
                lineWidth: 0.7
            )
        }
        .overlay {
            shape.strokeBorder(stroke.opacity(0.22), lineWidth: 0.45)
        }
}

extension View {
    func popupInputSurface(isFocused: Bool = false, cornerRadius: CGFloat = 11) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return
            self
            .background(shape.fill(PopupVisualTheme.surfaceFill))
            .overlay {
                shape.strokeBorder(
                    isFocused ? Color.accentColor.opacity(0.85) : PopupVisualTheme.surfaceStroke,
                    lineWidth: isFocused ? 1.25 : 0.8
                )
            }
    }
}

@MainActor
final class SystemGlassSettings: ObservableObject {
    static let shared = SystemGlassSettings()

    @Published private(set) var reduceTransparency = NSWorkspace.shared
        .accessibilityDisplayShouldReduceTransparency
    @Published private(set) var reduceMotion = NSWorkspace.shared
        .accessibilityDisplayShouldReduceMotion
    @Published private(set) var increaseContrast = NSWorkspace.shared
        .accessibilityDisplayShouldIncreaseContrast
    @Published private(set) var differentiateWithoutColor = NSWorkspace.shared
        .accessibilityDisplayShouldDifferentiateWithoutColor

    private var observer: NSObjectProtocol?

    private init() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: NSWorkspace.shared,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    private func refresh() {
        reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        differentiateWithoutColor =
            NSWorkspace.shared.accessibilityDisplayShouldDifferentiateWithoutColor
    }

    isolated deinit {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
}





func glassCapsuleBackground(emphasis: Double = 0.12) -> some View {
    GlassCapsuleBackground(emphasis: emphasis)
}

private func flatActionCapsuleBackground(fill: Color) -> some View {
    Capsule()
        .fill(fill)
        .overlay {
            Capsule()
                .strokeBorder(PopupVisualTheme.surfaceStroke, lineWidth: 0.8)
        }
}

// Shared popover composition helpers end here.
