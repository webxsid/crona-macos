import AppKit
import SwiftUI
import UserNotifications

struct NotificationSettingsView: View {
    @ObservedObject var appState: CompanionAppState
    @ObservedObject private var alertSettings: AlertSettingsService

    init(appState: CompanionAppState) {
        self.appState = appState
        _alertSettings = ObservedObject(wrappedValue: appState.alertSettingsService)
    }

    var body: some View {
        let settings = alertSettings.settings

        VStack(alignment: .leading, spacing: SettingsLayoutMetrics.sectionSpacing) {
            SettingsCard("System Notifications") {
                SettingsValueRow(
                    title: "Permission",
                    subtitle: "Access to native alerts, actions, and sounds.",
                    value: notificationStatusText(
                        appState.notificationService.authorizationStatus
                    )
                )

                SettingsValueRow(
                    title: "Delivery",
                    subtitle:
                        "See when the daemon falls back automatically if the app cannot deliver.",
                    value: deliveryStatusText
                )

                SettingsActionGroup {
                    SettingsActionButton("Allow Notifications", systemImage: "bell.badge.fill") {
                        appState.requestNotificationAuthorization()
                    }

                    SettingsActionButton("System Settings", systemImage: "gear", prominent: false) {
                        appState.notificationService.openSystemNotificationSettings()
                    }
                }
            }

            SettingsCard("Alerts") {
                SettingsToggleRow(
                    title: "Show Notifications",
                    subtitle: "Show boundaries, reminders, and updates in Notification Center.",
                    isOn: Binding(
                        get: { settings?.boundaryNotificationsEnabled ?? true },
                        set: {
                            appState.alertSettingsService.setBoolean(
                                "boundaryNotificationsEnabled",
                                value: $0
                            )
                        }
                    )
                )
                .disabled(settings == nil)

                SettingsToggleRow(
                    title: "Play Alert Sounds",
                    subtitle: "Play a sound when an alert needs attention.",
                    isOn: Binding(
                        get: { settings?.boundarySoundEnabled ?? true },
                        set: {
                            appState.alertSettingsService.setBoolean(
                                "boundarySoundEnabled",
                                value: $0
                            )
                        }
                    )
                )
                .disabled(settings == nil)

                SettingsPickerRow(
                    title: "Sound",
                    subtitle: "Choose the tone used for Crona alerts.",
                    selection: Binding(
                        get: {
                            alertSettings.settings?.alertSoundPreset ?? .chime
                        },
                        set: {
                            alertSettings.setSoundPreset($0)
                            appState.notificationService.playPresetPreview($0.rawValue)
                        }
                    )
                ) {
                    Text("Chime").tag(CronaAlertSoundPreset.chime)
                    Text("Soft Bell").tag(CronaAlertSoundPreset.softBell)
                    Text("Notification Ping").tag(CronaAlertSoundPreset.notificationPing)
                    Text("Focus Gong").tag(CronaAlertSoundPreset.focusGong)
                    Text("Minimal Click").tag(CronaAlertSoundPreset.minimalClick)
                }
                .disabled(settings == nil || settings?.boundarySoundEnabled == false)

                SettingsPickerRow(
                    title: "Prominence",
                    subtitle: "How strongly alerts can interrupt you.",
                    selection: Binding(
                        get: {
                            alertSettings.settings?.alertUrgency ?? .standard
                        },
                        set: {
                            alertSettings.setProminence($0)
                        }
                    )
                ) {
                    Text("Quiet").tag(CronaAlertProminence.quiet)
                    Text("Standard").tag(CronaAlertProminence.standard)
                    Text("Time Sensitive").tag(CronaAlertProminence.timeSensitive)
                }
                .disabled(settings == nil)

                HStack(spacing: 12) {
                    SettingsActionButton("Send Test", systemImage: "paperplane.fill") {
                        appState.sendTestNotification()
                    }

                    SettingsActionButton(
                        "Play Sound", systemImage: "speaker.wave.2.fill", prominent: false
                    ) {
                        appState.sendTestSound()
                    }
                }
                .disabled(appState.daemonConnection.connectionState != .connected)
            }

            SettingsCard("Focus Reminders") {
                SettingsToggleRow(
                    title: "Inactivity Reminder",
                    subtitle: "Nudge you when a session may have been left running.",
                    isOn: Binding(
                        get: { settings?.inactivityAlertsEnabled ?? true },
                        set: {
                            appState.alertSettingsService.setBoolean(
                                "inactivityAlertsEnabled",
                                value: $0
                            )
                        }
                    )
                )
                .disabled(settings == nil)

                SettingsPickerRow(
                    title: "Remind After",
                    subtitle: "Wait before the first reminder.",
                    selection: Binding(
                        get: { settings?.inactivityThresholdMinutes ?? 60 },
                        set: {
                            appState.alertSettingsService.setInteger(
                                "inactivityThresholdMinutes",
                                value: $0
                            )
                        }
                    )
                ) {
                    ForEach([15, 30, 45, 60, 90, 120], id: \.self) {
                        Text("\($0) minutes").tag($0)
                    }
                }
                .disabled(settings == nil || settings?.inactivityAlertsEnabled == false)

                SettingsPickerRow(
                    title: "Repeat",
                    subtitle: "Repeat while the session stays active.",
                    selection: Binding(
                        get: { settings?.inactivityRepeatMinutes ?? 60 },
                        set: {
                            appState.alertSettingsService.setInteger(
                                "inactivityRepeatMinutes",
                                value: $0
                            )
                        }
                    )
                ) {
                    ForEach([15, 30, 60, 90, 120], id: \.self) {
                        Text("\($0) minutes").tag($0)
                    }
                }
                .disabled(settings == nil || settings?.inactivityAlertsEnabled == false)

                SettingsToggleRow(
                    title: "Show Action Popup",
                    subtitle: "Show desktop actions with the reminder.",
                    isOn: Binding(
                        get: { appState.preferences.preferences.showInactivityActionPopups },
                        set: {
                            appState.preferences.preferences.showInactivityActionPopups = $0
                        }
                    )
                )
                .disabled(settings == nil || settings?.inactivityAlertsEnabled == false)

                InactivityPopupPositionRow(
                    selection: Binding(
                        get: { appState.preferences.preferences.inactivityPopupPosition },
                        set: { appState.preferences.preferences.inactivityPopupPosition = $0 }
                    )
                )
                .disabled(
                    settings == nil
                        || settings?.inactivityAlertsEnabled == false
                        || !appState.preferences.preferences.showInactivityActionPopups
                )

                InactivityReminderSettingsPreview()
            }

            SettingsCard("Focus Boundaries") {
                SettingsToggleRow(
                    title: "Show Action Popup",
                    subtitle: "Show End and Extend at a session boundary.",
                    isOn: Binding(
                        get: { appState.preferences.preferences.showHardLimitActionPopups },
                        set: { appState.preferences.preferences.showHardLimitActionPopups = $0 }
                    )
                )

                SettingsToggleRow(
                    title: "Show Early Warning",
                    subtitle: "Show a pointer-side warning before a session changes.",
                    isOn: Binding(
                        get: { appState.preferences.preferences.showHardLimitWarningIndicator },
                        set: { appState.preferences.preferences.showHardLimitWarningIndicator = $0 }
                    )
                )

                SettingsPickerRow(
                    title: "Warn Me",
                    subtitle: "Lead time for the early warning.",
                    selection: Binding(
                        get: {
                            CompanionPreferences.normalizedHardLimitWarningLeadSeconds(
                                appState.preferences.preferences.hardLimitWarningLeadSeconds
                            )
                        },
                        set: {
                            appState.preferences.preferences.hardLimitWarningLeadSeconds = $0
                        }
                    )
                ) {
                    ForEach(CompanionPreferences.hardLimitWarningLeadTimeOptions, id: \.self) {
                        Text("\($0) seconds").tag($0)
                    }
                }

                WarningIndicatorSettingsPreview(
                    leadSeconds: CompanionPreferences.normalizedHardLimitWarningLeadSeconds(
                        appState.preferences.preferences.hardLimitWarningLeadSeconds
                    )
                )
            }

            if let error = alertSettings.lastErrorDescription {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var deliveryStatusText: String {
        switch appState.notificationService.deliveryState {
        case .active: return "Crona for macOS"
        case .connecting: return "Connecting"
        case .failed: return "Daemon fallback"
        case .unavailable: return "Daemon fallback"
        }
    }

    private func notificationStatusText(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "Authorized"
        case .denied: return "Denied"
        case .ephemeral: return "Ephemeral"
        case .notDetermined: return "Not Determined"
        case .provisional: return "Provisional"
        @unknown default: return "Unknown"
        }
    }
}
