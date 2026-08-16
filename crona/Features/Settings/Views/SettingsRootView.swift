import AppKit
import SwiftUI
import UserNotifications

struct SettingsRootView: View {
    @ObservedObject var appState: CompanionAppState
    @State var sidebarSelection: SettingsDestination

    init(appState: CompanionAppState) {
        self.appState = appState
        _sidebarSelection = State(initialValue: appState.selectedSettingsDestination)
    }

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar
            settingsWorkArea
        }
        .frame(minWidth: 860, minHeight: 620)
        .ignoresSafeArea(.container, edges: .top)
        .background(
            SettingsWindowReader(
                windowService: appState.windowService,
                appearance: appState.preferences.preferences.appearance
            )
        )
        .companionAppearance(appState)
        .onChange(of: sidebarSelection) { _, destination in
            appState.setSelectedSettingsDestination(destination)
        }
        .onChange(of: appState.selectedSettingsDestination) { _, destination in
            guard destination != sidebarSelection else { return }
            sidebarSelection = destination
        }
    }

    var settingsSidebar: some View {
        ZStack {
            VisualEffectView(material: .sidebar, blendingMode: .behindWindow, emphasized: true)

            VStack(spacing: 0) {
                List(selection: $sidebarSelection) {
                    sidebarSection("Preferences", items: [.general, .menuBar])
                    sidebarSection(
                        "Focus", items: [.away, .daySchedule, .smartPause, .breakScreen, .notifications])
                    sidebarSection("System", items: [.advanced])
                    sidebarSection("Crona", items: [.about])
                    #if DEBUG
                        sidebarSection("Developer", items: [.developer])
                    #endif
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .padding(.top, 32)
            }
        }
        .frame(width: SettingsChromeMetrics.sidebarWidth)
    }

    @ViewBuilder
    func sidebarSection(_ title: String, items: [SettingsDestination]) -> some View {
        Section(title) {
            ForEach(items) { item in
                Label(item.title, systemImage: item.iconName)
                    .tag(item)
                    .help(item.title)
            }
        }
    }

    var settingsWorkArea: some View {
        VStack(spacing: 0) {
            settingsToolbar

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    settingsPageContent
                }
                .padding(.horizontal, SettingsLayoutMetrics.detailHorizontalPadding)
                .padding(.top, SettingsLayoutMetrics.detailTopPadding)
                .padding(.bottom, SettingsLayoutMetrics.detailBottomPadding)
                .frame(maxWidth: 760, alignment: .leading)
            }
            .scrollIndicators(.visible)
            .modifier(SettingsScrollEdgeEffectModifier())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            VisualEffectView(
                material: .contentBackground, blendingMode: .withinWindow, emphasized: false)
        )
    }

    @ViewBuilder
    var settingsPageContent: some View {
        switch sidebarSelection {
        case .general:
            SettingsPane(
                title: "General",
                subtitle: "Choose how Crona starts and looks on this Mac."
            ) {
                GeneralSettingsView(appState: appState)
            }
        case .away:
            SettingsPane(
                title: "Away",
                subtitle: "Manage Away Mode and the days Crona should protect."
            ) {
                AwaySettingsView(appState: appState)
            }
        case .menuBar:
            SettingsPane(
                title: "Menu Bar", subtitle: "Choose what Crona shows while you work."
            ) {
                MenuBarSettingsView(appState: appState)
            }
        case .daySchedule:
            SettingsPane(
                title: "Day Schedule",
                subtitle: "Set when each Crona day starts and ends."
            ) {
                DayBoundarySettingsCard(appState: appState)
            }
        case .smartPause:
            SettingsPane(
                title: "Smart Pause",
                subtitle: "Pause Stopwatch sessions when you step away."
            ) {
                SmartPauseSettingsView(appState: appState)
            }
        case .breakScreen:
            SettingsPane(
                title: "Breaks",
                subtitle: "Choose how Pomodoro breaks appear on your displays."
            ) {
                BreakScreenSettingsView(appState: appState)
            }
        case .notifications:
            SettingsPane(
                title: "Notifications",
                subtitle: "Choose which alerts appear and how they get your attention."
            ) {
                NotificationSettingsView(appState: appState)
            }
        case .advanced:
            SettingsPane(
                title: "Advanced",
                subtitle: "Check Crona’s local service connection and diagnostics."
            ) {
                RuntimeSettingsView(appState: appState)
                DiagnosticsSettingsView(appState: appState)
            }
        case .about:
            SettingsPane(
                title: "About",
                subtitle: "View version details, updates, and release information."
            ) {
                AboutSettingsView(appState: appState)
                UpdatesSettingsView(appState: appState)
            }
        #if DEBUG
            case .developer:
                SettingsPane(
                    title: "Developer",
                    subtitle: "Open safe, local previews of Crona’s transient surfaces."
                ) {
                    DeveloperSettingsView(appState: appState)
                }
        #endif
        }
    }

    var settingsToolbar: some View {
        HStack(spacing: 12) {
            Text(sidebarSelection.title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(PopupVisualTheme.primaryText)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .frame(height: SettingsChromeMetrics.toolbarHeight)
        .background(
            VisualEffectView(material: .headerView, blendingMode: .behindWindow, emphasized: false)
        )
    }

}



























func dayBoundaryTimeDate(from value: String) -> Date {
    let parts = value.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 2,
        let hour = Int(parts[0]),
        let minute = Int(parts[1])
    else {
        return Date()
    }

    let calendar = Calendar.current
    let components = calendar.dateComponents([.year, .month, .day], from: Date())
    let baseDate = calendar.date(from: components) ?? Date()
    return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: baseDate) ?? Date()
}

func dayBoundaryTimeString(from date: Date) -> String {
    let calendar = Calendar.current
    return String(
        format: "%02d:%02d",
        calendar.component(.hour, from: date),
        calendar.component(.minute, from: date)
    )
}















































#if DEBUG
    private struct DeveloperSettingsView: View {
        @ObservedObject var appState: CompanionAppState

        var body: some View {
            VStack(alignment: .leading, spacing: SettingsLayoutMetrics.sectionSpacing) {
                SettingsCard("Preview Tools") {
                    Text(
                        "These previews use local fixtures only. They never start, pause, extend, or end a daemon session."
                    )
                    .font(.caption)
                    .foregroundStyle(PopupVisualTheme.secondaryText)
                    .padding(.vertical, SettingsLayoutMetrics.rowVerticalPadding)

                    SettingsActionGroup {
                        SettingsActionButton("Hard Limit Flow", systemImage: "hourglass.circle") {
                            appState.showDeveloperHardLimitPreview()
                        }
                        SettingsActionButton(
                            "Inactivity Prompt", systemImage: "timer.circle", prominent: false
                        ) {
                            appState.showDeveloperInactivityPreview()
                        }
                    }

                    SettingsActionGroup {
                        SettingsActionButton(
                            "Warning Indicator", systemImage: "exclamationmark.circle",
                            prominent: false
                        ) {
                            appState.showDeveloperWarningPreview()
                        }
                        SettingsActionButton(
                            "Focus Resumed", systemImage: "play.circle", prominent: false
                        ) {
                            appState.showDeveloperSmartPauseResumePreview()
                        }
                        SettingsActionButton(
                            "Break Screen", systemImage: "moon.stars", prominent: false
                        ) {
                            appState.showDeveloperBreakScreenPreview()
                        }
                    }
                }

                SettingsCard("Cleanup") {
                    SettingsActionGroup {
                        SettingsActionButton(
                            "Dismiss All Previews", systemImage: "xmark.circle", prominent: false
                        ) {
                            appState.dismissDeveloperPreviews()
                        }
                    }
                }

                SettingsCard("Menu Bar Icon Preview") {
                    MenuBarIconPreviewGrid()
                }
            }
        }
    }
#endif

#if DEBUG
    private struct MenuBarIconPreviewGrid: View {
        private let previews: [(String, MenuBarIconState)] = [
            ("Idle", .idle),
            ("Focus", .focus(progress: 0.55)),
            ("Paused", .paused(progress: 0.55)),
            ("Break", .breakTime(progress: 0.55)),
            ("Connecting", .connecting),
            ("Offline", .offline),
            ("Error", .error),
            ("Completed", .completed),
            ("Update", .updateAvailable),
        ]

        var body: some View {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92))], spacing: 14) {
                ForEach(previews, id: \.0) { title, state in
                    VStack(spacing: 7) {
                        Image(nsImage: MenuBarIconProvider.image(for: state))
                            .resizable()
                            .frame(width: 18, height: 18)
                        Text(title)
                            .font(.caption)
                            .foregroundStyle(PopupVisualTheme.secondaryText)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
#endif

































@ViewBuilder
func settingsFootnote(_ text: String) -> some View {
    Text(text)
        .font(.footnote)
        .foregroundStyle(PopupVisualTheme.secondaryText)
        .padding(.top, 8)
}

extension SettingsDestination {
    fileprivate var title: String {
        switch self {
        case .general: return "General"
        case .away: return "Away"
        case .menuBar: return "Menu Bar"
        case .daySchedule: return "Day Schedule"
        case .smartPause: return "Smart Pause"
        case .breakScreen: return "Breaks"
        case .notifications: return "Notifications"
        case .advanced: return "Advanced"
        case .about: return "About"
        #if DEBUG
            case .developer: return "Dev"
        #endif
        }
    }

    fileprivate var iconName: String {
        switch self {
        case .general: return "gearshape.fill"
        case .away: return "figure.walk.circle.fill"
        case .menuBar: return "menubar.rectangle"
        case .daySchedule: return "calendar.badge.clock"
        case .smartPause: return "pause.circle.fill"
        case .breakScreen: return "moon.stars.fill"
        case .notifications: return "bell.fill"
        case .advanced: return "wrench.and.screwdriver.fill"
        case .about: return "info.circle.fill"
        #if DEBUG
            case .developer: return "hammer.fill"
        #endif
        }
    }
}
