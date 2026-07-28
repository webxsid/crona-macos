import AppKit
import Combine
import XCTest
@testable import crona

@MainActor
final class CronaCompanionTests: XCTestCase {
    func testSettingsNavigationTracksBackAndForwardHistory() {
        var history = SettingsNavigationHistory()

        history.navigate(to: .menuBar)
        history.navigate(to: .notifications)
        history.goBack()

        XCTAssertEqual(history.current, .menuBar)
        XCTAssertTrue(history.canGoBack)
        XCTAssertTrue(history.canGoForward)

        history.goForward()

        XCTAssertEqual(history.current, .notifications)
        XCTAssertTrue(history.canGoBack)
        XCTAssertFalse(history.canGoForward)
    }

    func testSettingsNavigationClearsForwardHistoryAfterNewSelection() {
        var history = SettingsNavigationHistory()
        history.navigate(to: .menuBar)
        history.navigate(to: .notifications)
        history.goBack()

        history.navigate(to: .runtime)

        XCTAssertEqual(history.current, .runtime)
        XCTAssertFalse(history.canGoForward)
    }

    func testSettingsNavigationIgnoresDuplicateAndBoundaryActions() {
        var history = SettingsNavigationHistory()

        history.goBack()
        history.goForward()
        history.navigate(to: .general)

        XCTAssertEqual(history.current, .general)
        XCTAssertFalse(history.canGoBack)
        XCTAssertFalse(history.canGoForward)
    }

    func testDiscoveryResolvesEndpointAndDefaultsTransport() {
        let config = CronaConfig(
            environment: .development,
            daemonLabel: "crona",
            postHogApiKey: nil,
            discoveryFilePath: "/tmp/kernel.json",
            runtimeDirectoryPath: "/tmp",
            defaultSocketPath: "/tmp/default.sock",
            defaultKernelExecutable: "crona-kernel",
            defaultDevKernelExecutable: "crona-kernel-dev"
        )

        let discovery = CronaKernelDiscovery(
            pid: nil,
            transport: nil,
            endpoint: nil,
            socketPath: "/tmp/kernel.sock",
            protocolVersion: nil,
            token: nil,
            startedAt: nil,
            scratchDir: nil,
            env: "production",
            executablePath: nil,
            runningChannel: nil,
            runningIsBeta: nil
        )

        let resolved = discovery.resolved(using: config)

        XCTAssertEqual(resolved?.endpoint, "/tmp/kernel.sock")
        XCTAssertEqual(resolved?.transport, "unix")
        XCTAssertEqual(resolved?.env, .production)
        XCTAssertEqual(resolved?.effectiveSocketPath, "/tmp/kernel.sock")
    }

    func testDaemonClientFetchesKernelInfo() async throws {
        let response = """
        {
          "id":"response-1",
          "result":{
            "pid":42,
            "transport":"unix_socket",
            "endpoint":"/tmp/kernel.sock",
            "socketPath":"/tmp/kernel.sock",
            "protocolVersion":"1.0",
            "startedAt":"2026-06-09T00:00:00Z",
            "scratchDir":"/tmp",
            "env":"development",
            "executablePath":"/Applications/Crona.app/Contents/MacOS/crona-kernel",
            "runningChannel":"stable",
            "runningIsBeta":false
          }
        }
        """.data(using: .utf8)!
        let transport = CapturingDaemonTransport(responseData: response)
        let client = CronaDaemonClient(transport: transport)

        let fetchedInfo = try await client.kernelInfoGet()

        XCTAssertEqual(fetchedInfo.protocolVersion, "1.0")
        XCTAssertEqual(fetchedInfo.endpoint, "/tmp/kernel.sock")

        let request: Data = try XCTUnwrap(transport.requestData)
        let requestProbe = try JSONDecoder().decode(RequestProbe.self, from: request)
        XCTAssertEqual(requestProbe.method, "kernel.info.get")
    }

    func testDaemonClientBuildsKernelShutdownRequest() async throws {
        let response = """
        {
          "id":"response-1",
          "result":{"ok":true}
        }
        """.data(using: .utf8)!
        let transport = CapturingDaemonTransport(responseData: response)
        let client = CronaDaemonClient(transport: transport)

        let result = try await client.kernelShutdown()

        XCTAssertTrue(result.ok)
        let request: Data = try XCTUnwrap(transport.requestData)
        let requestProbe = try JSONDecoder().decode(RequestProbe.self, from: request)
        XCTAssertEqual(requestProbe.method, "kernel.shutdown")
    }

    func testDaemonClientBuildsTimerAdvanceRequest() async throws {
        let response = """
        {
          "id":"response-1",
          "result":{
            "state":"running",
            "sessionId":"session-1",
            "segmentType":"short_break",
            "hardLimitActive":true,
            "hardLimitKind":"pomodoro"
          }
        }
        """.data(using: .utf8)!
        let transport = CapturingDaemonTransport(responseData: response)
        let client = CronaDaemonClient(transport: transport)

        let result = try await client.timerAdvance()

        XCTAssertEqual(result.segmentType, "short_break")
        let request: Data = try XCTUnwrap(transport.requestData)
        let requestProbe = try JSONDecoder().decode(RequestProbe.self, from: request)
        XCTAssertEqual(requestProbe.method, "timer.advance")
    }

    func testAlertDeliveryDecodesWithoutActions() throws {
        let event = try JSONDecoder().decode(
            CronaProtocolEvent.self,
            from: """
            {
              "type":"alert.delivery",
              "payload":{
                "id":"alert-1",
                "alert":{
                  "kind":"daily_plan.reminder",
                  "title":"Plan the day",
                  "body":"Choose today's priorities.",
                  "urgency":"normal",
                  "iconEnabled":true,
                  "playSound":false
                },
                "deliverNotification":true,
                "playSound":false
              }
            }
            """.data(using: .utf8)!
        )

        let delivery = try event.decodePayload(CronaAlertDelivery.self)

        XCTAssertEqual(delivery.id, "alert-1")
        XCTAssertEqual(delivery.alert.kind, "daily_plan.reminder")
        XCTAssertNil(delivery.actions)
    }

    func testCompanionAlertRoutingClassifiesTimerCompletionKinds() {
        XCTAssertTrue(CompanionAlertRouting.isTimerCompletion(kind: "timer.work_complete"))
        XCTAssertTrue(CompanionAlertRouting.isTimerCompletion(kind: "timer.break_complete"))
        XCTAssertFalse(CompanionAlertRouting.isTimerCompletion(kind: "timer.hard_limit_reached"))
    }

    func testCompanionAlertRoutingMapsReminderCategories() {
        XCTAssertTrue(CompanionAlertRouting.isReminder(kind: "checkin.reminder"))
        XCTAssertTrue(CompanionAlertRouting.isReminder(kind: "daily_plan.reminder"))
        XCTAssertEqual(
            CompanionAlertRouting.reminderCategoryIdentifier(for: "checkin.reminder"),
            "crona.reminder.check-in"
        )
        XCTAssertEqual(
            CompanionAlertRouting.reminderCategoryIdentifier(for: "daily_plan.reminder"),
            "crona.reminder.daily-plan"
        )
    }

    func testCompanionAlertRoutingUsesTUIForWellbeingReminders() {
        XCTAssertTrue(CompanionAlertRouting.shouldOpenTUI(kind: "checkin.reminder"))
        XCTAssertTrue(CompanionAlertRouting.shouldOpenTUI(kind: "daily_plan.reminder"))
        XCTAssertFalse(CompanionAlertRouting.shouldOpenTUI(kind: "timer.work_complete"))
        XCTAssertFalse(CompanionAlertRouting.shouldOpenTUI(kind: "export.completed"))
    }

    func testCompanionAlertRoutingClassifiesExportCompletedKinds() {
        XCTAssertTrue(CompanionAlertRouting.isExportCompleted(kind: "export.completed"))
        XCTAssertFalse(CompanionAlertRouting.isExportCompleted(kind: "timer.work_complete"))
    }

    func testAlertDeliveryDecodesExportActionPath() throws {
        let event = try JSONDecoder().decode(
            CronaProtocolEvent.self,
            from: """
            {
              "type":"alert.delivery",
              "payload":{
                "id":"alert-2",
                "alert":{
                  "kind":"export.completed",
                  "title":"Export ready",
                  "body":"Open the file or reveal it in Finder.",
                  "urgency":"low",
                  "iconEnabled":true,
                  "playSound":false
                },
                "deliverNotification":true,
                "playSound":false,
                "actions":[
                  {
                    "id":"export.open",
                    "title":"Open File",
                    "path":"/tmp/report.md"
                  }
                ]
              }
            }
            """.data(using: .utf8)!
        )

        let delivery = try event.decodePayload(CronaAlertDelivery.self)

        XCTAssertEqual(delivery.alert.kind, "export.completed")
        XCTAssertEqual(delivery.actions?.first?.path, "/tmp/report.md")
    }

    func testDaemonClientBuildsAlertDeliveryAckRequest() async throws {
        let response = """
        {"id":"response-1","result":{"ok":true}}
        """.data(using: .utf8)!
        let transport = CapturingDaemonTransport(responseData: response)
        let client = CronaDaemonClient(transport: transport)

        _ = try await client.acknowledgeAlertDelivery(
            CronaAlertDeliveryAck(
                deliveryID: "alert-1",
                notificationAccepted: true,
                soundAccepted: false
            )
        )

        let request = try XCTUnwrap(transport.requestData)
        let probe = try JSONDecoder().decode(AlertDeliveryAckRequestProbe.self, from: request)
        XCTAssertEqual(probe.method, "alerts.delivery.ack")
        XCTAssertEqual(probe.params.deliveryID, "alert-1")
        XCTAssertTrue(probe.params.notificationAccepted)
        XCTAssertFalse(probe.params.soundAccepted)
    }

    func testDaemonClientBuildsAlertDeliverySubscription() async throws {
        let transport = CapturingDaemonTransport(responseData: Data())
        let client = CronaDaemonClient(transport: transport)

        let stream = try await client.subscribeToAlertDeliveries(
            capabilities: CronaAlertDeliveryCapability(
                clientID: "mac-client",
                notifications: true,
                sounds: true
            )
        )
        for try await _ in stream {}

        let request = try XCTUnwrap(transport.requestData)
        let probe = try JSONDecoder().decode(AlertDeliverySubscriptionProbe.self, from: request)
        XCTAssertEqual(probe.method, "alerts.delivery.subscribe")
        XCTAssertEqual(probe.params.clientID, "mac-client")
        XCTAssertTrue(probe.params.notifications)
        XCTAssertTrue(probe.params.sounds)
    }

    func testStatusItemClickIntentUsesSecondaryClickForContextMenu() {
        XCTAssertEqual(
            StatusItemClickIntent.resolve(eventType: .rightMouseUp),
            .showContextMenu
        )
        XCTAssertEqual(
            StatusItemClickIntent.resolve(eventType: .leftMouseUp),
            .togglePopup
        )
        XCTAssertEqual(
            StatusItemClickIntent.resolve(eventType: nil),
            .togglePopup
        )
    }

    func testPreferencesPersist() throws {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let service = PreferencesService(defaults: defaults)
        service.preferences.menuBarDisplayMode = .textOnly
        service.preferences.menuBarIdleTextMode = .focusToday
        service.preferences.menuBarTimeFormat = .adaptive
        service.preferences.smartPauseEnabled = true
        service.preferences.smartPauseOnLock = false
        service.preferences.smartPauseOnDisplaySleep = false
        service.preferences.smartPauseOnInactivity = true
        service.preferences.smartPauseIdleSeconds = 30
        service.preferences.showHardLimitActionPopups = false
        service.preferences.showInactivityActionPopups = false
        service.preferences.inactivityPopupPosition = .bottomRight
        service.preferences.breakScreenEnabled = true
        service.preferences.breakScreenMode = .strict
        service.preferences.breakScreenStrictDelaySeconds = 30
        service.preferences.breakScreenBackgroundStyle = .gradient
        service.preferences.breakScreenGradientPreset = .ocean
        service.preferences.appUpdateChannel = .beta
        service.preferences.tuiCommand = "crona tui"

        let reloaded = PreferencesService(defaults: defaults)
        XCTAssertEqual(reloaded.preferences.menuBarDisplayMode, .textOnly)
        XCTAssertEqual(reloaded.preferences.menuBarIdleTextMode, .focusToday)
        XCTAssertEqual(reloaded.preferences.menuBarTimeFormat, .adaptive)
        XCTAssertTrue(reloaded.preferences.smartPauseEnabled)
        XCTAssertFalse(reloaded.preferences.smartPauseOnLock)
        XCTAssertFalse(reloaded.preferences.smartPauseOnDisplaySleep)
        XCTAssertTrue(reloaded.preferences.smartPauseOnInactivity)
        XCTAssertEqual(reloaded.preferences.smartPauseIdleSeconds, 30)
        XCTAssertFalse(reloaded.preferences.showHardLimitActionPopups)
        XCTAssertFalse(reloaded.preferences.showInactivityActionPopups)
        XCTAssertEqual(reloaded.preferences.inactivityPopupPosition, .bottomRight)
        XCTAssertTrue(reloaded.preferences.breakScreenEnabled)
        XCTAssertEqual(reloaded.preferences.breakScreenMode, .strict)
        XCTAssertEqual(reloaded.preferences.breakScreenStrictDelaySeconds, 30)
        XCTAssertEqual(reloaded.preferences.breakScreenBackgroundStyle, .gradient)
        XCTAssertEqual(reloaded.preferences.breakScreenGradientPreset, .ocean)
        XCTAssertEqual(reloaded.preferences.appUpdateChannel, .beta)
        XCTAssertEqual(reloaded.preferences.tuiCommand, "crona tui")
    }

    func testPreferencesDecodeValuesSavedBeforeIdleTextSettingExisted() throws {
        let data = """
        {
          "launchAtLogin": true,
          "menuBarDisplayMode": "iconAndText",
          "menuBarTimeFormat": "clock",
          "menuBarShowsSeconds": false,
          "pinPopover": true,
          "tuiCommand": "crona"
        }
        """.data(using: .utf8)!

        let preferences = try JSONDecoder().decode(CompanionPreferences.self, from: data)

        XCTAssertEqual(preferences.menuBarDisplayMode, .iconAndText)
        XCTAssertEqual(preferences.menuBarIdleTextMode, .idle)
        XCTAssertFalse(preferences.smartPauseEnabled)
        XCTAssertTrue(preferences.smartPauseOnLock)
        XCTAssertTrue(preferences.smartPauseOnDisplaySleep)
        XCTAssertTrue(preferences.smartPauseOnInactivity)
        XCTAssertEqual(preferences.smartPauseIdleSeconds, 120)
        XCTAssertTrue(preferences.showHardLimitActionPopups)
        XCTAssertTrue(preferences.showHardLimitWarningIndicator)
        XCTAssertEqual(preferences.hardLimitWarningLeadSeconds, 10)
        XCTAssertTrue(preferences.showInactivityActionPopups)
        XCTAssertEqual(preferences.inactivityPopupPosition, .topCenter)
        XCTAssertFalse(preferences.breakScreenEnabled)
        XCTAssertEqual(preferences.breakScreenMode, .easy)
        XCTAssertEqual(preferences.breakScreenStrictDelaySeconds, 15)
        XCTAssertEqual(preferences.breakScreenBackgroundStyle, .systemWallpaper)
        XCTAssertNil(preferences.appUpdateChannel)
    }

    func testPreferencesMigrateLegacyInactivityPopupPositions() throws {
        let expectedPositions: [(String, CompanionPopupPosition)] = [
            ("top", .topCenter),
            ("bottom", .bottomCenter),
            ("center", .topCenter),
            ("left", .topLeft),
            ("right", .topRight)
        ]

        for (legacyValue, expectedPosition) in expectedPositions {
            let data = "{\"inactivityPopupPosition\":\"\(legacyValue)\"}".data(using: .utf8)!
            let preferences = try JSONDecoder().decode(CompanionPreferences.self, from: data)
            XCTAssertEqual(preferences.inactivityPopupPosition, expectedPosition, legacyValue)
        }
    }

    func testInactivityPopupPositionerPlacesPanelsAtSelectedScreenAnchor() {
        let frame = NSRect(x: 100, y: 200, width: 1_200, height: 800)
        let panelSize = NSSize(width: 360, height: 320)
        let margin: CGFloat = 72

        XCTAssertEqual(
            InactivityPopupPositioner.origin(in: frame, panelSize: panelSize, preference: .topLeft, margin: margin),
            NSPoint(x: 172, y: 608)
        )
        XCTAssertEqual(
            InactivityPopupPositioner.origin(in: frame, panelSize: panelSize, preference: .topCenter, margin: margin),
            NSPoint(x: 520, y: 608)
        )
        XCTAssertEqual(
            InactivityPopupPositioner.origin(in: frame, panelSize: panelSize, preference: .topRight, margin: margin),
            NSPoint(x: 868, y: 608)
        )
        XCTAssertEqual(
            InactivityPopupPositioner.origin(in: frame, panelSize: panelSize, preference: .bottomLeft, margin: margin),
            NSPoint(x: 172, y: 272)
        )
        XCTAssertEqual(
            InactivityPopupPositioner.origin(in: frame, panelSize: panelSize, preference: .bottomCenter, margin: margin),
            NSPoint(x: 520, y: 272)
        )
        XCTAssertEqual(
            InactivityPopupPositioner.origin(in: frame, panelSize: panelSize, preference: .bottomRight, margin: margin),
            NSPoint(x: 868, y: 272)
        )
    }

    func testInactivityPopupPositionerUsesSharedEdgeInsets() {
        let frame = NSRect(x: 100, y: 200, width: 1_200, height: 800)
        let panelSize = NSSize(width: 380, height: 200)

        XCTAssertEqual(
            InactivityPopupPositioner.origin(
                in: frame,
                panelSize: panelSize,
                preference: .topCenter,
                topMargin: 12,
                bottomMargin: 8,
                horizontalMargin: 8
            ),
            NSPoint(x: 510, y: 788)
        )
        XCTAssertEqual(
            InactivityPopupPositioner.origin(
                in: frame,
                panelSize: panelSize,
                preference: .bottomRight,
                topMargin: 12,
                bottomMargin: 8,
                horizontalMargin: 8
            ),
            NSPoint(x: 912, y: 208)
        )
    }

    func testInactivityPopupPositionerStagesEdgePopupsOffscreen() {
        let visibleFrame = NSRect(x: 100, y: 200, width: 1_200, height: 800)
        let panelFrame = NSRect(x: 510, y: 788, width: 380, height: 200)
        let buffer: CGFloat = 24

        let left = InactivityPopupPositioner.offscreenOrigin(
            for: panelFrame,
            in: visibleFrame,
            preference: .topLeft,
            buffer: buffer
        )
        let right = InactivityPopupPositioner.offscreenOrigin(
            for: panelFrame,
            in: visibleFrame,
            preference: .bottomRight,
            buffer: buffer
        )

        XCTAssertEqual(left.x + panelFrame.width, visibleFrame.minX - buffer)
        XCTAssertEqual(left.y, panelFrame.origin.y)
        XCTAssertEqual(right.x, visibleFrame.maxX + buffer)
        XCTAssertEqual(right.y, panelFrame.origin.y)
    }

    func testInactivityPopupPositionerStagesCenteredPopupsOffscreen() {
        let visibleFrame = NSRect(x: 100, y: 200, width: 1_200, height: 800)
        let panelFrame = NSRect(x: 510, y: 788, width: 380, height: 200)
        let buffer: CGFloat = 24

        let top = InactivityPopupPositioner.offscreenOrigin(
            for: panelFrame,
            in: visibleFrame,
            preference: .topCenter,
            buffer: buffer
        )
        let bottom = InactivityPopupPositioner.offscreenOrigin(
            for: panelFrame,
            in: visibleFrame,
            preference: .bottomCenter,
            buffer: buffer
        )

        XCTAssertEqual(top.x, panelFrame.origin.x)
        XCTAssertEqual(top.y, visibleFrame.maxY + buffer)
        XCTAssertEqual(bottom.x, panelFrame.origin.x)
        XCTAssertEqual(bottom.y + panelFrame.height, visibleFrame.minY - buffer)
    }

    func testInactivityPopupUsesLongerDismissalDuration() {
        XCTAssertEqual(InactivityPopupConfiguration.autoDismissDuration, 60)
        XCTAssertEqual(HardLimitCountdownService.defaultDuration, 30)
    }

    func testAppReleaseChannelInfersBetaFromPrereleaseVersion() {
        XCTAssertEqual(AppReleaseChannel.inferred(from: "2.1.0-beta.3"), .beta)
        XCTAssertEqual(AppReleaseChannel.inferred(from: "2.1.0"), .stable)
    }

    func testAppReleaseChannelPrefersExplicitBundleMetadata() {
        XCTAssertEqual(
            AppReleaseChannel.resolved(configuredValue: "beta", version: "2.1.0"),
            .beta
        )
        XCTAssertEqual(
            AppReleaseChannel.resolved(configuredValue: "stable", version: "2.1.0-beta.3"),
            .stable
        )
        XCTAssertEqual(
            AppReleaseChannel.resolved(configuredValue: nil, version: "2.1.0-beta.3"),
            .beta
        )
    }

    func testAppUpdateChannelPersistsWithoutStartingSparkle() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let preferences = PreferencesService(defaults: defaults)
        let service = AppUpdateService(preferences: preferences, enabled: false)

        service.setChannel(.beta)

        XCTAssertEqual(service.selectedChannel, .beta)
        XCTAssertEqual(PreferencesService(defaults: defaults).preferences.appUpdateChannel, .beta)
    }

    func testPreferencesDefaultHardLimitPopupEnabled() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let service = PreferencesService(defaults: defaults)

        XCTAssertTrue(service.preferences.showHardLimitActionPopups)
    }

    func testHardLimitWarningLeadTimeUsesFixedPresets() {
        XCTAssertEqual(CompanionPreferences.hardLimitWarningLeadTimeOptions, [10, 20, 30])
        XCTAssertEqual(CompanionPreferences.normalizedHardLimitWarningLeadSeconds(1), 10)
        XCTAssertEqual(CompanionPreferences.normalizedHardLimitWarningLeadSeconds(17), 20)
        XCTAssertEqual(CompanionPreferences.normalizedHardLimitWarningLeadSeconds(60), 30)
    }

    func testBreakScreenStrictDelayUsesFixedPresets() {
        XCTAssertEqual(
            CompanionPreferences.breakScreenStrictDelayOptions,
            [5, 10, 15, 30, 60]
        )
        XCTAssertEqual(CompanionPreferences.normalizedBreakScreenStrictDelaySeconds(1), 5)
        XCTAssertEqual(CompanionPreferences.normalizedBreakScreenStrictDelaySeconds(18), 15)
        XCTAssertEqual(CompanionPreferences.normalizedBreakScreenStrictDelaySeconds(100), 60)
    }

    func testSmartPauseIdleDurationUsesShortPresets() {
        XCTAssertEqual(
            CompanionPreferences.smartPauseIdleOptions,
            [30, 60, 120, 300, 600]
        )
        XCTAssertEqual(CompanionPreferences.normalizedSmartPauseIdleSeconds(20), 30)
        XCTAssertEqual(CompanionPreferences.normalizedSmartPauseIdleSeconds(100), 120)
        XCTAssertEqual(CompanionPreferences.normalizedSmartPauseIdleSeconds(480), 600)
    }

    func testSmartPauseEligibilityOnlyAllowsRunningStopwatch() {
        let stopwatch = TimerSnapshot(
            state: "running",
            sessionID: "session-1",
            hardLimitActive: false,
            isConnected: true
        )
        XCTAssertTrue(SmartPauseService.isEligibleStopwatch(stopwatch))

        var paused = stopwatch
        paused.state = "paused"
        XCTAssertFalse(SmartPauseService.isEligibleStopwatch(paused))

        var pomodoro = stopwatch
        pomodoro.hardLimitActive = true
        pomodoro.hardLimitKind = .pomodoro
        XCTAssertFalse(SmartPauseService.isEligibleStopwatch(pomodoro))

        var disconnected = stopwatch
        disconnected.isConnected = false
        XCTAssertFalse(SmartPauseService.isEligibleStopwatch(disconnected))
    }

    func testSmartPauseDeduplicatesConditionsAndResumesAfterAllClear() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let preferences = PreferencesService(defaults: defaults)
        preferences.preferences.smartPauseEnabled = true
        preferences.preferences.smartPauseOnInactivity = false

        let timer = SmartPauseTimerController()
        timer.snapshot = TimerSnapshot(
            state: "running",
            sessionID: "session-1",
            hardLimitActive: false,
            isConnected: true
        )
        let service = SmartPauseService(
            preferences: preferences,
            timerController: timer,
            systemMonitor: SmartPauseMonitor(),
            idleTimeProvider: SmartPauseIdleProvider(seconds: 0)
        )
        service.start()
        defer { service.stop() }

        service.handleSystemEvent(.sessionResigned)
        await settleSmartPauseTasks()
        XCTAssertEqual(timer.pauseCount, 1)
        XCTAssertEqual(timer.snapshot.state, "paused")

        service.handleSystemEvent(.screensSlept)
        service.handleSystemEvent(.sessionBecameActive)
        await settleSmartPauseTasks()
        XCTAssertEqual(timer.resumeCount, 0)

        service.handleSystemEvent(.screensWoke)
        await settleSmartPauseTasks()
        XCTAssertEqual(timer.resumeCount, 1)
        XCTAssertEqual(timer.snapshot.state, "running")
    }

    func testDisablingSmartPauseDoesNotResumeOwnedPause() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let preferences = PreferencesService(defaults: defaults)
        preferences.preferences.smartPauseEnabled = true
        preferences.preferences.smartPauseOnInactivity = false

        let timer = SmartPauseTimerController()
        timer.snapshot = TimerSnapshot(
            state: "running",
            sessionID: "session-1",
            hardLimitActive: false,
            isConnected: true
        )
        let service = SmartPauseService(
            preferences: preferences,
            timerController: timer,
            systemMonitor: SmartPauseMonitor(),
            idleTimeProvider: SmartPauseIdleProvider(seconds: 0)
        )
        service.start()
        defer { service.stop() }

        service.handleSystemEvent(.sessionResigned)
        await settleSmartPauseTasks()
        preferences.preferences.smartPauseEnabled = false
        service.handleSystemEvent(.sessionBecameActive)
        await settleSmartPauseTasks()

        XCTAssertEqual(timer.pauseCount, 1)
        XCTAssertEqual(timer.resumeCount, 0)
        XCTAssertEqual(timer.snapshot.state, "paused")
    }

    func testSmartPauseUsesIdleThresholdAndResumesOnInput() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let preferences = PreferencesService(defaults: defaults)
        preferences.preferences.smartPauseEnabled = true
        preferences.preferences.smartPauseOnLock = false
        preferences.preferences.smartPauseOnDisplaySleep = false
        preferences.preferences.smartPauseOnInactivity = true
        preferences.preferences.smartPauseIdleSeconds = 30

        let timer = SmartPauseTimerController()
        timer.snapshot = TimerSnapshot(
            state: "running",
            sessionID: "session-1",
            hardLimitActive: false,
            isConnected: true
        )
        let idleProvider = SmartPauseMutableIdleProvider(seconds: 31)
        let service = SmartPauseService(
            preferences: preferences,
            timerController: timer,
            systemMonitor: SmartPauseMonitor(),
            idleTimeProvider: idleProvider
        )
        service.start()
        defer { service.stop() }

        await settleSmartPauseTasks()
        XCTAssertEqual(timer.pauseCount, 1)

        idleProvider.seconds = 0
        service.evaluateIdleState()
        await settleSmartPauseTasks()

        XCTAssertEqual(timer.resumeCount, 1)
        XCTAssertEqual(timer.snapshot.state, "running")
    }

    func testSmartPauseLockPausesImmediatelyAndReportsAutomaticResume() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let preferences = PreferencesService(defaults: defaults)
        preferences.preferences.smartPauseEnabled = true
        preferences.preferences.smartPauseOnLock = true
        preferences.preferences.smartPauseOnDisplaySleep = false
        preferences.preferences.smartPauseOnInactivity = true
        preferences.preferences.smartPauseIdleSeconds = 600

        let timer = SmartPauseTimerController()
        timer.snapshot = TimerSnapshot(
            state: "running",
            sessionID: "session-1",
            hardLimitActive: false,
            isConnected: true
        )
        var resumedSessionID: String?
        let service = SmartPauseService(
            preferences: preferences,
            timerController: timer,
            systemMonitor: SmartPauseMonitor(),
            idleTimeProvider: SmartPauseIdleProvider(seconds: 0)
        )
        service.setAutomaticResumeHandler { snapshot in resumedSessionID = snapshot.sessionID }
        service.start()
        defer { service.stop() }

        service.handleSystemEvent(.sessionResigned)
        await settleSmartPauseTasks()
        XCTAssertEqual(timer.pauseCount, 1)

        service.handleSystemEvent(.sessionBecameActive)
        await settleSmartPauseTasks()
        XCTAssertEqual(timer.resumeCount, 1)
        XCTAssertEqual(resumedSessionID, "session-1")
    }

    private func settleSmartPauseTasks() async {
        for _ in 0..<4 {
            await Task.yield()
        }
    }

    func testConfigLoaderUsesBundleDefaultsForDevelopment() {
        let loader = CronaConfigLoader(
            bundle: TestBundle.info([
                "CRONA_APP_ENV": "development",
                "CRONA_DAEMON_LABEL": "crona",
                "CRONA_RUNTIME_DIR": "/tmp/Crona Dev",
                "CRONA_KERNEL_EXECUTABLE": "crona-kernel",
                "CRONA_KERNEL_DEV_EXECUTABLE": "crona-kernel-dev"
            ]),
            environmentProvider: { [:] }
        )

        let runtime = loader.load()

        XCTAssertEqual(runtime.config.environment, .development)
        XCTAssertEqual(runtime.config.runtimeDirectoryPath, "/tmp/Crona Dev")
        XCTAssertEqual(runtime.config.discoveryFilePath, "/tmp/Crona Dev/kernel.json")
        XCTAssertEqual(runtime.config.defaultSocketPath, "/tmp/Crona Dev/kernel.sock")
    }

    func testConfigLoaderAllowsOnlyCRONA_HOMEOverride() {
        let loader = CronaConfigLoader(
            bundle: TestBundle.info([
                "CRONA_APP_ENV": "production",
                "CRONA_DAEMON_LABEL": "crona",
                "CRONA_RUNTIME_DIR": "/tmp/Crona",
                "CRONA_KERNEL_EXECUTABLE": "crona-kernel",
                "CRONA_KERNEL_DEV_EXECUTABLE": "crona-kernel-dev"
            ]),
            environmentProvider: {
                [
                    "CRONA_HOME": "/tmp/override",
                    "CRONA_DISCOVERY_FILE": "/tmp/ignored/kernel.json",
                    "CRONA_DAEMON_SOCKET_PATH": "/tmp/ignored/kernel.sock"
                ]
            }
        )

        let runtime = loader.load()

        XCTAssertEqual(runtime.config.runtimeDirectoryPath, "/tmp/override")
        XCTAssertEqual(runtime.config.discoveryFilePath, "/tmp/override/kernel.json")
        XCTAssertEqual(runtime.config.defaultSocketPath, "/tmp/override/kernel.sock")
    }

    func testConfigLoaderExpandsRuntimeHomeAtLaunch() {
        let loader = CronaConfigLoader(
            bundle: TestBundle.info([
                "CRONA_APP_ENV": "production",
                "CRONA_DAEMON_LABEL": "crona",
                "CRONA_RUNTIME_DIR": "~/Library/Application Support/Crona",
                "CRONA_KERNEL_EXECUTABLE": "crona-kernel",
                "CRONA_KERNEL_DEV_EXECUTABLE": "crona-kernel-dev"
            ]),
            environmentProvider: { [:] }
        )

        let runtime = loader.load()
        let expected = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Crona")
            .path

        XCTAssertEqual(runtime.config.runtimeDirectoryPath, expected)
        XCTAssertFalse(runtime.config.runtimeDirectoryPath.contains("/Users/runner"))
    }

    func testOptionalActiveContextDecodesNull() throws {
        let response = """
        {"id":"response-1","result":null}
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(CronaKernelResponseEnvelope<CronaActiveContext?>.self, from: response)

        XCTAssertNil(decoded.result ?? nil)
    }

    func testActiveContextDecodesDaemonWireKeys() throws {
        let response = """
        {
          "id":"response-1",
          "result":{
            "userId":"local",
            "deviceId":"macbook",
            "repoId":101,
            "repoName":"crona",
            "streamId":202,
            "streamName":"desktop",
            "issueId":303,
            "issueTitle":"Ship companion",
            "updatedAt":"2026-07-13T06:30:00Z"
          }
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(CronaKernelResponseEnvelope<CronaActiveContext>.self, from: response)
        let context = try XCTUnwrap(decoded.result)

        XCTAssertEqual(context.userID, "local")
        XCTAssertEqual(context.deviceID, "macbook")
        XCTAssertEqual(context.repoID, 101)
        XCTAssertEqual(context.repoName, "crona")
        XCTAssertEqual(context.streamID, 202)
        XCTAssertEqual(context.streamName, "desktop")
        XCTAssertEqual(context.issueID, 303)
        XCTAssertEqual(context.issueTitle, "Ship companion")
    }

    func testSparseTimerStateDecodesIdleState() throws {
        let response = """
        {"id":"response-1","result":{"state":"idle"}}
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(CronaKernelResponseEnvelope<CronaTimerState>.self, from: response)

        XCTAssertEqual(decoded.result?.state, "idle")
        XCTAssertNil(decoded.result?.elapsedSeconds)
    }

    func testTimerStateDecodesDaemonWireKeys() throws {
        let response = """
        {
          "id":"response-1",
          "result":{
            "state":"running",
            "sessionId":"session-1",
            "sessionStartTime":"2026-07-13T06:00:00Z",
            "issueId":303,
            "segmentType":"work",
            "segmentStartTime":"2026-07-13T06:05:00Z",
            "segmentElapsedOffsetSeconds":15,
            "nextSegmentType":"break",
            "elapsedSeconds":600
          }
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(CronaKernelResponseEnvelope<CronaTimerState>.self, from: response)
        let state = try XCTUnwrap(decoded.result)

        XCTAssertEqual(state.sessionID, "session-1")
        XCTAssertEqual(state.issueID, 303)
        XCTAssertEqual(state.segmentType, "work")
        XCTAssertEqual(state.segmentElapsedOffsetSeconds, 15)
        XCTAssertEqual(state.elapsedSeconds, 600)
    }

    func testTimerStateDecodesExplicitHardLimitKind() throws {
        let response = """
        {
          "id":"response-1",
          "result":{
            "state":"running",
            "sessionId":"session-1",
            "hardLimitActive":true,
            "hardLimitKind":"countdown",
            "hardLimitTotalSeconds":1500
          }
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(CronaKernelResponseEnvelope<CronaTimerState>.self, from: response)
        let state = try XCTUnwrap(decoded.result)
        let snapshot = TimerSnapshot.from(state)

        XCTAssertEqual(state.hardLimitKind, "countdown")
        XCTAssertEqual(snapshot.hardLimitKind, .countdown)
        XCTAssertEqual(TimerPresentation.from(snapshot).mode, .timer)
    }

    func testMissingAndUnknownHardLimitKindsNormalizeToPomodoro() throws {
        for rawKind in [nil, "future-kind"] as [String?] {
            let snapshot = TimerSnapshot(
                state: "running",
                sessionID: "session-1",
                hardLimitActive: true,
                hardLimitKind: CronaTimerHardLimitKind.normalized(rawKind),
                hardLimitTotalSeconds: 1500,
                hardLimitWorkSeconds: 1500,
                isConnected: true
            )

            XCTAssertEqual(snapshot.hardLimitKind, .pomodoro)
            XCTAssertEqual(TimerPresentation.from(snapshot).mode, .pomodoro)
        }
    }

    func testHabitDailyItemDecodesDueHabitPayload() throws {
        let response = """
        {
          "id":"response-1",
          "result":[{
            "id":101,
            "streamId":202,
            "name":"Stretch",
            "description":"Move a bit",
            "scheduleType":"daily",
            "weekdays":[],
            "targetMinutes":15,
            "active":true,
            "repoId":1,
            "repoName":"Crona",
            "streamName":"Wellbeing",
            "status":"completed",
            "completed":true,
            "completionId":44,
            "completionDate":"2026-07-13",
            "durationMinutes":12
          }]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(CronaKernelResponseEnvelope<[CronaHabitDailyItem]>.self, from: response)
        let item = try XCTUnwrap(decoded.result?.first)

        XCTAssertEqual(item.id, 101)
        XCTAssertEqual(item.name, "Stretch")
        XCTAssertEqual(item.repoName, "Crona")
        XCTAssertEqual(item.streamName, "Wellbeing")
        XCTAssertEqual(item.status, "completed")
        XCTAssertEqual(item.durationMinutes, 12)
        XCTAssertEqual(item.targetMinutes, 15)
    }

    func testTimerSnapshotAppliesRunningState() {
        let state = CronaTimerState(
            state: "running",
            sessionID: "session-1",
            sessionStartTime: "2026-06-09T00:00:00Z",
            issueID: 10,
            segmentType: "work",
            segmentStartTime: "2026-06-09T00:00:30Z",
            segmentElapsedOffsetSeconds: nil,
            readySegmentType: nil,
            nextSegmentType: "rest",
            elapsedSeconds: 90,
            hardLimitActive: false,
            hardLimitExpired: false,
            hardLimitTotalSeconds: 0,
            hardLimitRemainingSeconds: 0,
            hardLimitWorkSeconds: 0,
            hardLimitBreakSeconds: 0,
            hardLimitLongBreakSeconds: 0,
            hardLimitCyclesBeforeLongBreak: 0
        )

        let snapshot = TimerSnapshot.from(state)
        XCTAssertEqual(snapshot.state, "running")
        XCTAssertEqual(snapshot.sessionID, "session-1")
        XCTAssertEqual(snapshot.issueID, 10)
        XCTAssertEqual(snapshot.segmentType, "work")
        XCTAssertEqual(snapshot.elapsedSeconds, 90)
        XCTAssertTrue(snapshot.isConnected)
    }

    func testTimerPresentationClassifiesStructuredTimer() {
        let now = Date(timeIntervalSince1970: 10_000)
        let snapshot = TimerSnapshot(
            state: "running",
            sessionID: "session-1",
            issueID: 10,
            segmentType: "work",
            nextSegmentType: nil,
            readySegmentType: nil,
            elapsedSeconds: 600,
            sessionStartTime: nil,
            segmentStartTime: nil,
            hardLimitActive: true,
            hardLimitKind: .countdown,
            hardLimitExpired: false,
            hardLimitTotalSeconds: 1800,
            hardLimitRemainingSeconds: 1200,
            hardLimitWorkSeconds: 1800,
            hardLimitBreakSeconds: 0,
            hardLimitLongBreakSeconds: 0,
            hardLimitCyclesBeforeLongBreak: 0,
            snapshotAppliedAt: now,
            isConnected: true
        )

        let presentation = TimerPresentation.from(snapshot, at: now)

        XCTAssertEqual(presentation.mode, .timer)
        XCTAssertTrue(presentation.countsDown)
        XCTAssertEqual(presentation.displaySeconds, 1200)
        XCTAssertEqual(presentation.progressFraction ?? 0, 2.0 / 3.0, accuracy: 0.001)
        XCTAssertFalse(presentation.canPause)
        XCTAssertFalse(presentation.canResume)
        XCTAssertEqual(presentation.phaseTitle, "Timer ends in")
    }

    func testTimerPresentationClassifiesPomodoroBreak() {
        let now = Date(timeIntervalSince1970: 10_000)
        let snapshot = TimerSnapshot(
            state: "running",
            sessionID: "session-1",
            issueID: 10,
            segmentType: "rest",
            nextSegmentType: "work",
            readySegmentType: nil,
            elapsedSeconds: 1500,
            sessionStartTime: nil,
            segmentStartTime: nil,
            hardLimitActive: true,
            hardLimitKind: .pomodoro,
            hardLimitExpired: false,
            hardLimitTotalSeconds: 1800,
            hardLimitRemainingSeconds: 300,
            hardLimitWorkSeconds: 1500,
            hardLimitBreakSeconds: 300,
            hardLimitLongBreakSeconds: 900,
            hardLimitCyclesBeforeLongBreak: 4,
            snapshotAppliedAt: now,
            isConnected: true
        )

        let presentation = TimerPresentation.from(snapshot, at: now)

        XCTAssertEqual(presentation.mode, .pomodoro)
        XCTAssertEqual(presentation.phaseTitle, "Break ends in")
        XCTAssertEqual(presentation.displaySeconds, 300)
        XCTAssertEqual(presentation.upcomingSegment?.kind, .work)
        XCTAssertEqual(presentation.upcomingSegment?.durationSeconds, 1500)
        XCTAssertFalse(presentation.canPause)
        XCTAssertFalse(presentation.canResume)
    }

    func testBreakScreenProjectionStartsPreparedPomodoroBreak() {
        let snapshot = TimerSnapshot(
            state: "ready",
            sessionID: "session-1",
            nextSegmentType: "short_break",
            readySegmentType: "short_break",
            hardLimitActive: true,
            hardLimitKind: .pomodoro,
            hardLimitBreakSeconds: 300,
            isConnected: true
        )

        let projection = BreakScreenProjection.resolve(
            snapshot: snapshot,
            enabled: true,
            managedSessionID: nil
        )

        XCTAssertTrue(projection.shouldPresent)
        XCTAssertEqual(projection.transition, .startBreak)
        XCTAssertEqual(projection.segment, .shortBreak)
    }

    func testBreakScreenProjectionResumesWorkOnlyForManagedBreak() {
        let snapshot = TimerSnapshot(
            state: "ready",
            sessionID: "session-1",
            nextSegmentType: "work",
            readySegmentType: "work",
            hardLimitActive: true,
            hardLimitKind: .pomodoro,
            isConnected: true
        )

        let managed = BreakScreenProjection.resolve(
            snapshot: snapshot,
            enabled: false,
            managedSessionID: "session-1"
        )
        let unmanaged = BreakScreenProjection.resolve(
            snapshot: snapshot,
            enabled: true,
            managedSessionID: nil
        )

        XCTAssertEqual(managed.transition, .resumeWork)
        XCTAssertFalse(managed.shouldPresent)
        XCTAssertEqual(unmanaged.transition, .none)
    }

    func testBreakScreenProjectionIgnoresCountdownAndStopwatchStates() {
        let countdown = TimerSnapshot(
            state: "running",
            sessionID: "session-1",
            segmentType: "short_break",
            hardLimitActive: true,
            hardLimitKind: .countdown,
            isConnected: true
        )
        let stopwatch = TimerSnapshot(
            state: "paused",
            sessionID: "session-2",
            segmentType: "short_break",
            hardLimitActive: false,
            isConnected: true
        )

        XCTAssertFalse(
            BreakScreenProjection.resolve(
                snapshot: countdown,
                enabled: true,
                managedSessionID: nil
            ).shouldPresent
        )
        XCTAssertFalse(
            BreakScreenProjection.resolve(
                snapshot: stopwatch,
                enabled: true,
                managedSessionID: nil
            ).shouldPresent
        )
    }

    func testBreakScreenStrictDelayUsesAuthoritativeRemainingTime() {
        let now = Date(timeIntervalSince1970: 10_000)
        let snapshot = TimerSnapshot(
            state: "running",
            sessionID: "session-1",
            segmentType: "short_break",
            hardLimitActive: true,
            hardLimitKind: .pomodoro,
            hardLimitRemainingSeconds: 290,
            hardLimitBreakSeconds: 300,
            snapshotAppliedAt: now,
            isConnected: true
        )

        XCTAssertEqual(
            BreakScreenService.strictDelayRemaining(
                snapshot: snapshot,
                segment: .shortBreak,
                delaySeconds: 15,
                now: now
            ),
            5
        )

        XCTAssertEqual(
            BreakScreenService.strictDelayRemaining(
                snapshot: snapshot,
                segment: .shortBreak,
                delaySeconds: 15,
                now: now.addingTimeInterval(10)
            ),
            0
        )
    }

    func testTimerPresentationKeepsNoBreakPomodoroAsPomodoro() {
        let snapshot = TimerSnapshot(
            state: "running",
            sessionID: "session-1",
            segmentType: "work",
            hardLimitActive: true,
            hardLimitKind: .pomodoro,
            hardLimitTotalSeconds: 1500,
            hardLimitRemainingSeconds: 1200,
            hardLimitWorkSeconds: 1500,
            isConnected: true
        )

        let presentation = TimerPresentation.from(snapshot)

        XCTAssertEqual(presentation.mode, .pomodoro)
        XCTAssertEqual(presentation.phaseTitle, "Focus ends in")
        XCTAssertNil(presentation.upcomingSegment)
    }

    func testPomodoroWorkProjectionUsesCurrentSegmentDuration() {
        let now = Date(timeIntervalSince1970: 10_000)
        let snapshot = TimerSnapshot(
            state: "running",
            sessionID: "session-1",
            segmentType: "work",
            nextSegmentType: "short_break",
            elapsedSeconds: 10,
            segmentStartTime: now.addingTimeInterval(-10),
            hardLimitActive: true,
            hardLimitKind: .pomodoro,
            hardLimitTotalSeconds: 120,
            hardLimitRemainingSeconds: 110,
            hardLimitWorkSeconds: 60,
            hardLimitBreakSeconds: 60,
            snapshotAppliedAt: now,
            isConnected: true
        )
        let presentation = TimerPresentation.from(snapshot, at: now)

        XCTAssertEqual(presentation.displaySeconds, 50)
        XCTAssertEqual(presentation.progressFraction ?? 0, 5.0 / 6.0, accuracy: 0.001)
        XCTAssertEqual(presentation.phaseTitle, "Break starts in")
        XCTAssertEqual(presentation.upcomingSegment?.kind, .shortBreak)
        XCTAssertEqual(presentation.upcomingSegment?.durationSeconds, 60)
    }

    func testPomodoroBreakProjectionUsesBreakDurationAndUpcomingFocus() {
        let now = Date(timeIntervalSince1970: 10_000)
        let snapshot = TimerSnapshot(
            state: "running",
            sessionID: "session-1",
            segmentType: "short_break",
            nextSegmentType: "work",
            elapsedSeconds: 15,
            segmentStartTime: now.addingTimeInterval(-15),
            hardLimitActive: true,
            hardLimitKind: .pomodoro,
            hardLimitTotalSeconds: 120,
            hardLimitRemainingSeconds: 45,
            hardLimitWorkSeconds: 60,
            hardLimitBreakSeconds: 60,
            snapshotAppliedAt: now,
            isConnected: true
        )
        let presentation = TimerPresentation.from(snapshot, at: now)

        XCTAssertEqual(presentation.displaySeconds, 45)
        XCTAssertEqual(presentation.progressFraction ?? 0, 0.75, accuracy: 0.001)
        XCTAssertEqual(presentation.phaseTitle, "Break ends in")
        XCTAssertEqual(presentation.upcomingSegment?.kind, .work)
        XCTAssertEqual(presentation.upcomingSegment?.durationSeconds, 60)
    }

    func testTimerPresentationAllowsPauseAndResumeOnlyForStopwatch() {
        let running = TimerSnapshot(
            state: "running",
            sessionID: "session-1",
            elapsedSeconds: 90,
            isConnected: true
        )
        let paused = TimerSnapshot(
            state: "paused",
            sessionID: "session-1",
            elapsedSeconds: 90,
            isConnected: true
        )

        let runningPresentation = TimerPresentation.from(running)
        let pausedPresentation = TimerPresentation.from(paused)

        XCTAssertEqual(runningPresentation.mode, .stopwatch)
        XCTAssertTrue(runningPresentation.canPause)
        XCTAssertFalse(runningPresentation.canResume)
        XCTAssertFalse(pausedPresentation.canPause)
        XCTAssertTrue(pausedPresentation.canResume)
    }

    func testFocusStartConfigBuildsStopwatchRequest() {
        let issue = DailyFocusIssue(id: 33, streamID: 22, title: "Issue", status: "planned", estimateMinutes: nil, workedSeconds: 0, todoForDate: nil)
        let state = FocusStartConfigState(mode: .stopwatch)

        let request = state.startRequest(for: issue)

        XCTAssertEqual(request.streamID, 22)
        XCTAssertEqual(request.issueID, 33)
        XCTAssertNil(request.hardLimitKind)
        XCTAssertNil(request.hardLimitTotalSeconds)
        XCTAssertNil(request.hardLimitWorkSeconds)
    }

    func testFocusStartConfigBuildsPomodoroRequest() {
        let issue = DailyFocusIssue(id: 33, streamID: 22, title: "Issue", status: "planned", estimateMinutes: nil, workedSeconds: 0, todoForDate: nil)
        let state = FocusStartConfigState(
            mode: .pomodoro,
            focusChoice: .preset25,
            breakChoice: .preset5,
            longBreakChoice: .preset15,
            countdownChoice: .preset25,
            pomodoroCycles: 4,
            pomodoroCyclesBeforeLongBreak: 4,
            extendMinutes: 25,
            extendSessions: 1
        )

        let request = state.startRequest(for: issue)

        XCTAssertEqual(request.hardLimitKind, .pomodoro)
        XCTAssertEqual(request.hardLimitTotalSeconds, 7800)
        XCTAssertEqual(request.hardLimitWorkSeconds, 1500)
        XCTAssertEqual(request.hardLimitBreakSeconds, 300)
        XCTAssertEqual(request.hardLimitLongBreakSeconds, 900)
        XCTAssertEqual(request.hardLimitCyclesBeforeLongBreak, 4)
    }

    func testTimerStartEndProjectionUsesConfiguredCountdown() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let state = FocusStartConfigState(
            mode: .timer,
            countdownChoice: .custom,
            customCountdownMinutes: 45
        )

        let endDate = try XCTUnwrap(TimerEndProjection.startEndDate(config: state, now: now))

        XCTAssertEqual(endDate, now.addingTimeInterval(45 * 60))
    }

    func testPomodoroStartEndProjectionUsesCompletePlan() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let state = FocusStartConfigState(
            mode: .pomodoro,
            focusChoice: .preset25,
            breakChoice: .preset5,
            longBreakChoice: .preset15,
            countdownChoice: .preset25,
            pomodoroCycles: 4,
            pomodoroCyclesBeforeLongBreak: 4
        )

        let endDate = try XCTUnwrap(TimerEndProjection.startEndDate(config: state, now: now))

        XCTAssertEqual(endDate, now.addingTimeInterval(7_800))
    }

    func testStopwatchHasNoProjectedEndDate() {
        let state = FocusStartConfigState(mode: .stopwatch)

        XCTAssertNil(TimerEndProjection.startEndDate(config: state))
    }

    func testActiveEndProjectionUsesAuthoritativeRemainingTime() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let snapshot = TimerSnapshot(
            state: "running",
            sessionID: "session-1",
            hardLimitActive: true,
            hardLimitRemainingSeconds: 600,
            snapshotAppliedAt: now,
            isConnected: true
        )

        let endDate = try XCTUnwrap(TimerEndProjection.activeEndDate(snapshot: snapshot, now: now))

        XCTAssertEqual(endDate, now.addingTimeInterval(600))
    }

    func testTimerProjectionAdvancesWithoutMutatingAuthoritativeSnapshot() {
        let appliedAt = Date(timeIntervalSince1970: 10_000)
        let snapshot = TimerSnapshot(
            state: "running",
            sessionID: "session-1",
            elapsedSeconds: 90,
            snapshotAppliedAt: appliedAt,
            isConnected: true
        )

        XCTAssertEqual(
            TimerPresentation.projectedDisplaySeconds(
                for: snapshot,
                at: appliedAt.addingTimeInterval(14_400)
            ),
            14_490
        )
        XCTAssertEqual(snapshot.elapsedSeconds, 90)
    }

    func testStatusPopupLayoutKeyIgnoresTimerDisplayChanges() {
        let first = StatusPopupLayoutKey(
            connectionState: .connected,
            selectedTab: .now,
            hasActiveSession: true,
            hasSelectedIssue: false,
            hasContext: true,
            hasUpcomingSegment: false,
            modalKind: nil,
            showsUpdate: false
        )
        let afterSeveralHours = StatusPopupLayoutKey(
            connectionState: .connected,
            selectedTab: .now,
            hasActiveSession: true,
            hasSelectedIssue: false,
            hasContext: true,
            hasUpcomingSegment: false,
            modalKind: nil,
            showsUpdate: false
        )

        XCTAssertEqual(first, afterSeveralHours)
        XCTAssertNotEqual(
            first,
            StatusPopupLayoutKey(
                connectionState: .connected,
                selectedTab: .now,
                hasActiveSession: true,
                hasSelectedIssue: false,
                hasContext: true,
                hasUpcomingSegment: true,
                modalKind: nil,
                showsUpdate: false
            )
        )
    }

    func testStatusPopupLayoutKeyTracksAsyncContentChanges() {
        let base = StatusPopupLayoutKey(
            connectionState: .connected,
            selectedTab: .now,
            hasActiveSession: false,
            hasSelectedIssue: false,
            hasContext: false,
            hasUpcomingSegment: false,
            dailyIssueCount: 2,
            habitsItemCount: 1,
            habitsIsLoading: false,
            habitsHasError: false,
            habitActionInFlightID: nil,
            statsDate: "2026-07-28",
            statsIsLoading: false,
            statsHasError: false,
            statsHasScore: true,
            modalKind: nil,
            showsUpdate: false
        )

        XCTAssertNotEqual(
            base,
            StatusPopupLayoutKey(
                connectionState: .connected,
                selectedTab: .now,
                hasActiveSession: false,
                hasSelectedIssue: false,
                hasContext: false,
                hasUpcomingSegment: false,
                dailyIssueCount: 3,
                habitsItemCount: 1,
                habitsIsLoading: false,
                habitsHasError: false,
                habitActionInFlightID: nil,
                statsDate: "2026-07-28",
                statsIsLoading: false,
                statsHasError: false,
                statsHasScore: true,
                modalKind: nil,
                showsUpdate: false
            )
        )
        XCTAssertNotEqual(
            base,
            StatusPopupLayoutKey(
                connectionState: .connected,
                selectedTab: .habits,
                hasActiveSession: false,
                hasSelectedIssue: false,
                hasContext: false,
                hasUpcomingSegment: false,
                dailyIssueCount: 2,
                habitsItemCount: 2,
                habitsIsLoading: true,
                habitsHasError: false,
                habitActionInFlightID: 42,
                statsDate: "2026-07-28",
                statsIsLoading: false,
                statsHasError: false,
                statsHasScore: true,
                modalKind: nil,
                showsUpdate: false
            )
        )
        XCTAssertNotEqual(
            base,
            StatusPopupLayoutKey(
                connectionState: .connected,
                selectedTab: .stats,
                hasActiveSession: false,
                hasSelectedIssue: false,
                hasContext: false,
                hasUpcomingSegment: false,
                dailyIssueCount: 2,
                habitsItemCount: 1,
                habitsIsLoading: false,
                habitsHasError: false,
                habitActionInFlightID: nil,
                statsDate: "2026-07-27",
                statsIsLoading: true,
                statsHasError: true,
                statsHasScore: false,
                modalKind: nil,
                showsUpdate: false
            )
        )
    }

    func testPopupDisplayClockStopsWhenDismissed() {
        let clock = PopupDisplayClock()

        XCTAssertFalse(clock.isRunning)
        clock.start()
        XCTAssertTrue(clock.isRunning)
        clock.stop()
        XCTAssertFalse(clock.isRunning)
    }

    func testTimerExtensionEndProjectionIncludesRemainingTime() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let snapshot = TimerSnapshot(
            state: "running",
            sessionID: "session-1",
            hardLimitActive: true,
            hardLimitRemainingSeconds: 120,
            snapshotAppliedAt: now,
            isConnected: true
        )
        let request = CronaTimerExtendRequest(
            additionalSeconds: 300,
            additionalSessions: 1,
            hardLimitTotalSeconds: nil,
            hardLimitWorkSeconds: nil,
            hardLimitBreakSeconds: nil,
            hardLimitLongBreakSeconds: nil,
            hardLimitCyclesBeforeLongBreak: nil
        )

        let endDate = try XCTUnwrap(
            TimerEndProjection.extensionEndDate(snapshot: snapshot, request: request, now: now)
        )

        XCTAssertEqual(endDate, now.addingTimeInterval(420))
    }

    func testConfiguredExtensionEndProjectionUsesSessionCount() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let snapshot = TimerSnapshot(
            state: "expired",
            sessionID: "session-1",
            hardLimitActive: true,
            hardLimitExpired: true,
            isConnected: true
        )
        let request = CronaTimerExtendRequest(
            additionalSeconds: 0,
            additionalSessions: 2,
            hardLimitTotalSeconds: 1_800,
            hardLimitWorkSeconds: 1_500,
            hardLimitBreakSeconds: 300,
            hardLimitLongBreakSeconds: 0,
            hardLimitCyclesBeforeLongBreak: 0
        )

        let endDate = try XCTUnwrap(
            TimerEndProjection.extensionEndDate(snapshot: snapshot, request: request, now: now)
        )

        XCTAssertEqual(endDate, now.addingTimeInterval(3_600))
    }

    func testFocusStartConfigUsesRemainingEstimateForTimerDefault() {
        let state = FocusStartConfigState.defaultState(estimateMinutes: 60, workedSeconds: 15 * 60)
        let issue = DailyFocusIssue(id: 33, streamID: 22, title: "Issue", status: "planned", estimateMinutes: 60, workedSeconds: 15 * 60, todoForDate: nil)
        var timerState = state
        timerState.mode = .timer

        let request = timerState.startRequest(for: issue)

        XCTAssertEqual(state.customCountdownMinutes, 45)
        XCTAssertEqual(state.countdownChoice, .custom)
        XCTAssertEqual(request.hardLimitKind, .countdown)
        XCTAssertEqual(request.hardLimitTotalSeconds, 45 * 60)
        XCTAssertNil(request.hardLimitWorkSeconds)
        XCTAssertNil(request.hardLimitBreakSeconds)
        XCTAssertNil(request.hardLimitLongBreakSeconds)
        XCTAssertNil(request.hardLimitCyclesBeforeLongBreak)
    }

    func testCountdownStartEncodingOmitsPomodoroCadence() throws {
        let issue = DailyFocusIssue(
            id: 33,
            streamID: 22,
            title: "Issue",
            status: "planned",
            estimateMinutes: nil,
            workedSeconds: 0,
            todoForDate: nil
        )
        let state = FocusStartConfigState(
            mode: .timer,
            countdownChoice: .custom,
            customCountdownMinutes: 45
        )

        let encoded = try JSONEncoder().encode(state.startRequest(for: issue))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )

        XCTAssertEqual(object["hardLimitKind"] as? String, "countdown")
        XCTAssertEqual(object["hardLimitTotalSeconds"] as? Int, 45 * 60)
        XCTAssertNil(object["hardLimitWorkSeconds"])
        XCTAssertNil(object["hardLimitBreakSeconds"])
        XCTAssertNil(object["hardLimitLongBreakSeconds"])
        XCTAssertNil(object["hardLimitCyclesBeforeLongBreak"])
    }

    func testFocusStartConfigDisablesDependentPomodoroFieldsWhenNoBreakSelected() {
        let state = FocusStartConfigState(
            mode: .pomodoro,
            focusChoice: .preset25,
            breakChoice: .noBreak,
            longBreakChoice: .preset15,
            countdownChoice: .preset25,
            pomodoroCycles: 4,
            pomodoroCyclesBeforeLongBreak: 4
        )

        XCTAssertFalse(state.breaksEnabled)
        XCTAssertFalse(state.showsLongBreakControls)
        XCTAssertFalse(state.showsCycleControls)
        XCTAssertFalse(state.showsLongBreakAfterControls)
        XCTAssertEqual(state.pomodoroValues.breakSeconds, 0)
        XCTAssertEqual(state.pomodoroValues.longBreakSeconds, 0)
        XCTAssertEqual(state.pomodoroValues.cyclesBeforeLongBreak, 0)
        XCTAssertEqual(state.pomodoroValues.totalSeconds, 25 * 60)
    }

    func testFocusStartConfigDisablesLongBreakAfterWhenLongBreakDisabled() {
        let state = FocusStartConfigState(
            mode: .pomodoro,
            focusChoice: .preset25,
            breakChoice: .preset5,
            longBreakChoice: .noBreak,
            countdownChoice: .preset25,
            pomodoroCycles: 4,
            pomodoroCyclesBeforeLongBreak: 4
        )

        XCTAssertTrue(state.breaksEnabled)
        XCTAssertFalse(state.longBreakEnabled)
        XCTAssertTrue(state.showsCycleControls)
        XCTAssertFalse(state.showsLongBreakAfterControls)
        XCTAssertEqual(state.pomodoroValues.longBreakSeconds, 0)
        XCTAssertEqual(state.pomodoroValues.cyclesBeforeLongBreak, 0)
    }

    func testFocusStartConfigClampsCustomDurations() {
        let state = FocusStartConfigState(
            mode: .pomodoro,
            focusChoice: .custom,
            breakChoice: .custom,
            longBreakChoice: .custom,
            countdownChoice: .custom,
            customFocusMinutes: 0,
            customBreakMinutes: -5,
            customLongBreakMinutes: -10,
            customCountdownMinutes: 0
        )
        var timerState = state
        timerState.mode = .timer

        XCTAssertEqual(state.resolvedFocusMinutes, 1)
        XCTAssertEqual(state.resolvedBreakMinutes, 0)
        XCTAssertEqual(state.resolvedLongBreakMinutes, 0)
        XCTAssertEqual(timerState.resolvedCountdownMinutes, 1)
    }

    func testPopoverStatsMessagesCoverKnownLevels() {
        XCTAssertTrue(PopoverStatsService.message(for: "strong").contains("strong"))
        XCTAssertTrue(PopoverStatsService.message(for: "steady").contains("steady"))
        XCTAssertTrue(PopoverStatsService.message(for: "overextended").contains("recovery"))
        XCTAssertFalse(PopoverStatsService.message(for: "unknown").isEmpty)
    }

    func testHabitsServiceRefreshesForHabitCompletionEvents() {
        XCTAssertTrue(HabitsService.shouldRefresh(for: "habit.completed"))
        XCTAssertTrue(HabitsService.shouldRefresh(for: "habit.uncompleted"))
        XCTAssertFalse(HabitsService.shouldRefresh(for: "timer.state"))
    }

    func testHabitRowActionSwitchesByCompletionState() {
        let pending = HabitRowModel(
            id: 1,
            name: "Stretch",
            repoName: "Crona",
            streamName: "Health",
            status: "completed",
            completed: false,
            durationMinutes: nil,
            targetMinutes: 15
        )
        let completed = HabitRowModel(
            id: 2,
            name: "Walk",
            repoName: "Crona",
            streamName: "Health",
            status: "completed",
            completed: true,
            durationMinutes: 12,
            targetMinutes: 15
        )
        let failed = HabitRowModel(
            id: 3,
            name: "Sleep",
            repoName: "Crona",
            streamName: "Health",
            status: "failed",
            completed: false,
            durationMinutes: nil,
            targetMinutes: nil
        )

        XCTAssertFalse(pending.supportsClearAction)
        XCTAssertTrue(completed.supportsClearAction)
        XCTAssertTrue(failed.supportsClearAction)
    }

    func testDailyFocusBuildsPlannedOrderFromPlanEntries() {
        let summary = CronaDailyIssueSummary(
            date: "2026-07-13",
            totalIssues: 2,
            issues: [
                CronaIssue(id: 2, streamID: 20, title: "Second", status: "planned", estimateMinutes: 30, workedSeconds: 0, pinnedDaily: false, todoForDate: "2026-07-13", completedAt: nil, abandonedAt: nil),
                CronaIssue(id: 1, streamID: 10, title: "First", status: "planned", estimateMinutes: 45, workedSeconds: 0, pinnedDaily: false, todoForDate: "2026-07-13", completedAt: nil, abandonedAt: nil)
            ],
            totalEstimatedMinutes: 75,
            completedIssues: 0,
            abandonedIssues: 0,
            workedSeconds: 0
        )
        let plan = CronaDailyPlan(
            id: "plan-1",
            date: "2026-07-13",
            createdAt: "2026-07-13T00:00:00Z",
            updatedAt: "2026-07-13T00:00:00Z",
            entries: [
                CronaDailyPlanEntry(id: "entry-1", date: "2026-07-13", issueID: 1, source: "todo_for_date", status: "planned", committedAt: "2026-07-13T00:00:00Z", baselineDate: "2026-07-13", currentPlannedDate: "2026-07-13", postponeCount: 0, currentDelayedDays: 0, maxDelayedDays: 0, failScore: 0),
                CronaDailyPlanEntry(id: "entry-2", date: "2026-07-13", issueID: 2, source: "todo_for_date", status: "planned", committedAt: "2026-07-13T00:00:00Z", baselineDate: "2026-07-13", currentPlannedDate: "2026-07-13", postponeCount: 0, currentDelayedDays: 0, maxDelayedDays: 0, failScore: 0)
            ]
        )

        let issues = DailyFocusService.buildIssues(summary: summary, plan: plan)

        XCTAssertEqual(issues.map(\.id), [1, 2])
    }

    func testDiagnosticsTextContainsCoreFields() {
        let snapshot = DiagnosticsSnapshot(
            connectionState: "Connected",
            protocolVersion: "1.0",
            kernelVersion: "stable",
            runtimeDirectory: "/tmp/crona",
            healthSummary: "ok | db=true | uptime=10s",
            lastReconnect: "Today",
            endpoint: "/tmp/crona/kernel.sock",
            transport: "unix_socket",
            alertBackend: "usernotifications",
            lastError: nil
        )

        XCTAssertTrue(snapshot.text.contains("Connection State: Connected"))
        XCTAssertTrue(snapshot.text.contains("Runtime Directory: /tmp/crona"))
    }

    func testMenuBarFormatterClockOmitsZeroHours() {
        XCTAssertEqual(MenuBarTextFormatter.formatClock(seconds: 247), "04:07")
        XCTAssertEqual(MenuBarTextFormatter.formatClock(seconds: 3_847), "1:04:07")
    }

    func testMenuBarIconStateFollowsConnectionAndTimerProjection() {
        var activeSnapshot = TimerSnapshot()
        activeSnapshot.sessionID = "session-1"
        activeSnapshot.state = "running"

        XCTAssertEqual(
            MenuBarIconState.resolve(connectionState: .disconnected, timerSnapshot: activeSnapshot),
            .offline
        )
        XCTAssertEqual(
            MenuBarIconState.resolve(connectionState: .connected, timerSnapshot: TimerSnapshot()),
            .idle
        )
        XCTAssertEqual(
            MenuBarIconState.resolve(connectionState: .connected, timerSnapshot: activeSnapshot),
            .focus
        )

        activeSnapshot.state = "paused"
        XCTAssertEqual(
            MenuBarIconState.resolve(connectionState: .connected, timerSnapshot: activeSnapshot),
            .paused
        )

        activeSnapshot.state = "running"
        activeSnapshot.segmentType = "short_break"
        XCTAssertEqual(
            MenuBarIconState.resolve(connectionState: .connected, timerSnapshot: activeSnapshot),
            .breakTime
        )

        activeSnapshot.hardLimitExpired = true
        XCTAssertEqual(
            MenuBarIconState.resolve(connectionState: .connected, timerSnapshot: activeSnapshot),
            .attention
        )
    }

    func testMenuBarIconStatesHaveStableSVGAssetNames() {
        XCTAssertEqual(
            Set(MenuBarIconState.allCases.map(\.assetName)),
            [
                "menu-icon-idle",
                "menu-icon-focus",
                "menu-icon-paused",
                "menu-icon-break-time",
                "menu-icon-attention",
                "menu-icon-offline",
            ]
        )
    }

    func testMenuBarFormatterAdaptiveUsesContextualUnits() {
        XCTAssertEqual(MenuBarTextFormatter.formatAdaptive(seconds: 0), "0s")
        XCTAssertEqual(MenuBarTextFormatter.formatAdaptive(seconds: 59), "59s")
        XCTAssertEqual(MenuBarTextFormatter.formatAdaptive(seconds: 60), "1m")
        XCTAssertEqual(MenuBarTextFormatter.formatAdaptive(seconds: 3_599), "59m")
        XCTAssertEqual(MenuBarTextFormatter.formatAdaptive(seconds: 3_600), "1h")
        XCTAssertEqual(MenuBarTextFormatter.formatAdaptive(seconds: 3_847), "1h4m")
    }

    func testMenuBarFormatterFormatsMinutes() {
        XCTAssertEqual(MenuBarTextFormatter.formatMinutes(75), "1h15m")
    }

    func testMenuBarFormatterUsesIdleForConnectedWithoutTimer() {
        var preferences = CompanionPreferences()
        preferences.menuBarDisplayMode = .iconAndText
        preferences.menuBarTimeFormat = .clock
        let title = MenuBarTextFormatter.statusItemTitle(
            preferences: preferences,
            connectionState: .connected,
            timerSnapshot: TimerSnapshot()
        )
        XCTAssertEqual(title, "Idle")
    }

    func testMenuBarTimeFormatMigratesExpandedToAdaptive() throws {
        let data = Data("\"expanded\"".utf8)
        let format = try JSONDecoder().decode(MenuBarTimeFormat.self, from: data)
        XCTAssertEqual(format, .adaptive)
    }

    func testAdaptiveRefreshIntervalsFollowVisibleBoundaries() {
        XCTAssertEqual(
            MenuBarTextFormatter.nextRefreshInterval(
                seconds: 125,
                style: .adaptive,
                countsDown: true
            ),
            6
        )
        XCTAssertEqual(
            MenuBarTextFormatter.nextRefreshInterval(
                seconds: 125,
                style: .adaptive,
                countsDown: false
            ),
            55
        )
        XCTAssertEqual(
            MenuBarTextFormatter.nextRefreshInterval(
                seconds: 59,
                style: .adaptive,
                countsDown: true
            ),
            1
        )
        XCTAssertEqual(
            MenuBarTextFormatter.nextRefreshInterval(
                seconds: 3_600,
                style: .clock,
                countsDown: true
            ),
            1
        )
    }

    func testMenuBarFormatterUsesTodayFocusWhenIdle() {
        var preferences = CompanionPreferences()
        preferences.menuBarDisplayMode = .textOnly
        preferences.menuBarIdleTextMode = .focusToday

        let title = MenuBarTextFormatter.statusItemTitle(
            preferences: preferences,
            connectionState: .connected,
            timerSnapshot: TimerSnapshot(),
            todayWorkedSeconds: 5_520
        )

        XCTAssertEqual(title, "1h32m")
    }

    func testMenuBarFormatterOmitsZeroHoursFromTodayFocus() {
        var preferences = CompanionPreferences()
        preferences.menuBarDisplayMode = .textOnly
        preferences.menuBarIdleTextMode = .focusToday

        let title = MenuBarTextFormatter.statusItemTitle(
            preferences: preferences,
            connectionState: .connected,
            timerSnapshot: TimerSnapshot(),
            todayWorkedSeconds: 1_920
        )

        XCTAssertEqual(title, "32m")
    }

    func testMenuBarFormatterFallsBackToIdleWithoutTodayMetrics() {
        var preferences = CompanionPreferences()
        preferences.menuBarDisplayMode = .iconAndText
        preferences.menuBarIdleTextMode = .focusToday

        let title = MenuBarTextFormatter.statusItemTitle(
            preferences: preferences,
            connectionState: .connected,
            timerSnapshot: TimerSnapshot()
        )

        XCTAssertEqual(title, "Idle")
    }

    func testMenuBarFormatterKeepsTextOnlyItemReachableWhenDisconnected() {
        var preferences = CompanionPreferences()
        preferences.menuBarDisplayMode = .textOnly

        let title = MenuBarTextFormatter.statusItemTitle(
            preferences: preferences,
            connectionState: .disconnected,
            timerSnapshot: TimerSnapshot()
        )

        XCTAssertEqual(title, "Offline")
    }

    func testDaemonClientBuildsListDueHabitsRequest() async throws {
        let response = """
        {"id":"response-1","result":[]}
        """.data(using: .utf8)!
        let transport = CapturingDaemonTransport(responseData: response)
        let client = CronaDaemonClient(transport: transport)

        let habits = try await client.listDueHabits(date: "2026-07-13")

        XCTAssertEqual(habits.count, 0)
        let request = try XCTUnwrap(transport.requestData)
        let requestProbe = try JSONDecoder().decode(RequestWithParamsProbe.self, from: request)
        XCTAssertEqual(requestProbe.method, "habit.list_due")
        XCTAssertEqual(requestProbe.params["date"]?.stringValue, "2026-07-13")
    }

    func testDaemonClientBuildsIssueStatusTransitionsRequest() async throws {
        let response = """
        {
          "id":"response-1",
          "result":{
            "id":42,
            "currentStatus":"in_progress",
            "allowedStatuses":["planned","blocked","in_review","done","abandoned"]
          }
        }
        """.data(using: .utf8)!
        let transport = CapturingDaemonTransport(responseData: response)
        let client = CronaDaemonClient(transport: transport)

        let result = try await client.issueStatusTransitions(issueID: 42)

        XCTAssertEqual(result.currentStatus, "in_progress")
        XCTAssertEqual(result.allowedStatuses, [.planned, .blocked, .inReview, .done, .abandoned])
        let request = try XCTUnwrap(transport.requestData)
        let requestProbe = try JSONDecoder().decode(RequestWithParamsProbe.self, from: request)
        XCTAssertEqual(requestProbe.method, "issue.status_transitions")
        XCTAssertEqual(requestProbe.params["id"]?.intValue, 42)
    }

    func testDaemonClientBuildsIssueStatusChangeRequestWithNote() async throws {
        let response = issueResponseData(status: "blocked", todoForDate: nil)
        let transport = CapturingDaemonTransport(responseData: response)
        let client = CronaDaemonClient(transport: transport)

        _ = try await client.changeIssueStatus(
            issueID: 42,
            status: .blocked,
            note: "Waiting for review"
        )

        let request = try XCTUnwrap(transport.requestData)
        let requestProbe = try JSONDecoder().decode(RequestWithParamsProbe.self, from: request)
        XCTAssertEqual(requestProbe.method, "issue.change_status")
        XCTAssertEqual(requestProbe.params["id"]?.intValue, 42)
        XCTAssertEqual(requestProbe.params["status"]?.stringValue, "blocked")
        XCTAssertEqual(requestProbe.params["note"]?.stringValue, "Waiting for review")
    }

    func testDaemonClientBuildsSetAndClearIssueDueDateRequests() async throws {
        let setTransport = CapturingDaemonTransport(
            responseData: issueResponseData(status: "planned", todoForDate: "2026-08-02")
        )
        let setClient = CronaDaemonClient(transport: setTransport)
        _ = try await setClient.setIssueTodo(issueID: 42, date: "2026-08-02")

        var request = try XCTUnwrap(setTransport.requestData)
        var requestProbe = try JSONDecoder().decode(RequestWithParamsProbe.self, from: request)
        XCTAssertEqual(requestProbe.method, "issue.set_todo")
        XCTAssertEqual(requestProbe.params["id"]?.intValue, 42)
        XCTAssertEqual(requestProbe.params["date"]?.stringValue, "2026-08-02")

        let clearTransport = CapturingDaemonTransport(
            responseData: issueResponseData(status: "planned", todoForDate: nil)
        )
        let clearClient = CronaDaemonClient(transport: clearTransport)
        _ = try await clearClient.clearIssueTodo(issueID: 42)

        request = try XCTUnwrap(clearTransport.requestData)
        requestProbe = try JSONDecoder().decode(RequestWithParamsProbe.self, from: request)
        XCTAssertEqual(requestProbe.method, "issue.clear_todo")
        XCTAssertEqual(requestProbe.params["id"]?.intValue, 42)
    }

    func testIssueStatusNoteRequirementsMirrorDaemonContract() {
        XCTAssertTrue(CronaIssueStatus.blocked.requiresNote)
        XCTAssertTrue(CronaIssueStatus.abandoned.requiresNote)
        XCTAssertFalse(CronaIssueStatus.done.requiresNote)
        XCTAssertEqual(CronaIssueStatus.inReview.notePrompt, "Review note (optional)")
        XCTAssertNil(CronaIssueStatus.planned.notePrompt)
    }

    func testCronaCalendarDateQuickChoicesAreStable() throws {
        XCTAssertEqual(
            CronaCalendarDate.adding(days: 1, to: "2026-07-26"),
            "2026-07-27"
        )
        XCTAssertEqual(
            CronaCalendarDate.adding(days: 7, to: "2026-07-26"),
            "2026-08-02"
        )
        let date = try XCTUnwrap(CronaCalendarDate.date(from: "2026-08-02"))
        XCTAssertEqual(CronaCalendarDate.string(from: date), "2026-08-02")
    }

    func testDaemonClientBuildsHabitCompleteRequest() async throws {
        let response = """
        {"id":"response-1","result":{"id":8,"habitId":101,"date":"2026-07-13","status":"completed"}}
        """.data(using: .utf8)!
        let transport = CapturingDaemonTransport(responseData: response)
        let client = CronaDaemonClient(transport: transport)

        let completion = try await client.completeHabit(habitID: 101, date: "2026-07-13")

        XCTAssertEqual(completion.id, 8)
        let request = try XCTUnwrap(transport.requestData)
        let requestProbe = try JSONDecoder().decode(RequestWithParamsProbe.self, from: request)
        XCTAssertEqual(requestProbe.method, "habit.complete")
        XCTAssertEqual(requestProbe.params["habitId"]?.intValue, 101)
        XCTAssertEqual(requestProbe.params["date"]?.stringValue, "2026-07-13")
        XCTAssertEqual(requestProbe.params["status"]?.stringValue, "completed")
    }

    func testDaemonClientBuildsHabitFailedRequest() async throws {
        let response = """
        {"id":"response-1","result":{"id":8,"habitId":101,"date":"2026-07-13","status":"failed"}}
        """.data(using: .utf8)!
        let transport = CapturingDaemonTransport(responseData: response)
        let client = CronaDaemonClient(transport: transport)

        let completion = try await client.completeHabit(
            habitID: 101,
            date: "2026-07-13",
            status: "failed"
        )

        XCTAssertEqual(completion.status, "failed")
        let request = try XCTUnwrap(transport.requestData)
        let requestProbe = try JSONDecoder().decode(RequestWithParamsProbe.self, from: request)
        XCTAssertEqual(requestProbe.method, "habit.complete")
        XCTAssertEqual(requestProbe.params["habitId"]?.intValue, 101)
        XCTAssertEqual(requestProbe.params["date"]?.stringValue, "2026-07-13")
        XCTAssertEqual(requestProbe.params["status"]?.stringValue, "failed")
    }

    func testDaemonClientBuildsTimedHabitLogRequest() async throws {
        let response = """
        {"id":"response-1","result":{"id":8,"habitId":101,"date":"2026-07-13","status":"completed","durationMinutes":25}}
        """.data(using: .utf8)!
        let transport = CapturingDaemonTransport(responseData: response)
        let client = CronaDaemonClient(transport: transport)

        let completion = try await client.completeHabit(
            habitID: 101,
            date: "2026-07-13",
            durationMinutes: 25
        )

        XCTAssertEqual(completion.durationMinutes, 25)
        let request = try XCTUnwrap(transport.requestData)
        let requestProbe = try JSONDecoder().decode(RequestWithParamsProbe.self, from: request)
        XCTAssertEqual(requestProbe.method, "habit.complete")
        XCTAssertEqual(requestProbe.params["status"]?.stringValue, "completed")
        XCTAssertEqual(requestProbe.params["durationMinutes"]?.intValue, 25)
    }

    func testDaemonClientBuildsEndSessionRequestWithCommitMessage() async throws {
        let response = """
        {"id":"response-1","result":{"ok":true}}
        """.data(using: .utf8)!
        let transport = CapturingDaemonTransport(responseData: response)
        let client = CronaDaemonClient(transport: transport)

        let result = try await client.timerEnd(commitMessage: "Ship macOS companion end flow")

        XCTAssertTrue(result.ok)
        let request = try XCTUnwrap(transport.requestData)
        let requestProbe = try JSONDecoder().decode(RequestWithParamsProbe.self, from: request)
        XCTAssertEqual(requestProbe.method, "timer.end")
        XCTAssertEqual(requestProbe.params["commitMessage"]?.stringValue, "Ship macOS companion end flow")
    }

    func testTimerServiceRefreshesForEndAndExtendEvents() {
        XCTAssertTrue(TimerService.shouldRefresh(for: "session.ended"))
        XCTAssertTrue(TimerService.shouldRefresh(for: "timer.extended"))
        XCTAssertFalse(TimerService.shouldRefresh(for: "habit.completed"))
    }

    private func issueResponseData(status: String, todoForDate: String?) -> Data {
        let todoJSON = todoForDate.map { "\"\($0)\"" } ?? "null"
        return """
        {
          "id":"response-1",
          "result":{
            "id":42,
            "streamId":7,
            "title":"Ship context menu",
            "status":"\(status)",
            "workedSeconds":0,
            "pinnedDaily":false,
            "todoForDate":\(todoJSON)
          }
        }
        """.data(using: .utf8)!
    }

    func testContextServiceRefreshesForEndAndExtendEvents() {
        XCTAssertTrue(ContextService.shouldRefresh(for: "session.ended"))
        XCTAssertTrue(ContextService.shouldRefresh(for: "timer.extended"))
        XCTAssertFalse(ContextService.shouldRefresh(for: "habit.completed"))
    }

    func testProtocolEventExtractsSessionIDFromPayload() throws {
        let data = """
        {"type":"session.ended","payload":{"sessionId":"session-42"}}
        """.data(using: .utf8)!

        let event = try JSONDecoder().decode(CronaProtocolEvent.self, from: data)

        XCTAssertEqual(event.sessionID, "session-42")
    }

    func testQuickExtendRequestUsesSecondsNotSessions() {
        let snapshot = TimerSnapshot(
            state: "running",
            sessionID: "session-1",
            issueID: 10,
            segmentType: "work",
            nextSegmentType: nil,
            readySegmentType: nil,
            elapsedSeconds: 600,
            sessionStartTime: nil,
            segmentStartTime: nil,
            hardLimitActive: true,
            hardLimitExpired: false,
            hardLimitTotalSeconds: 1800,
            hardLimitRemainingSeconds: 1200,
            hardLimitWorkSeconds: 1500,
            hardLimitBreakSeconds: 300,
            hardLimitLongBreakSeconds: 900,
            hardLimitCyclesBeforeLongBreak: 4,
            snapshotAppliedAt: Date(),
            isConnected: true
        )

        let request = CompanionAppState.buildQuickExtendRequest(snapshot: snapshot, additionalSeconds: 300)

        XCTAssertEqual(request?.additionalSeconds, 300)
        XCTAssertEqual(request?.additionalSessions, 0)
        XCTAssertNil(request?.hardLimitTotalSeconds)
        XCTAssertNil(request?.hardLimitWorkSeconds)
        XCTAssertNil(request?.hardLimitBreakSeconds)
    }

    func testQuickExtendRequestRejectsZeroSeconds() {
        let request = CompanionAppState.buildQuickExtendRequest(snapshot: TimerSnapshot(), additionalSeconds: 0)
        XCTAssertNil(request)
    }

    func testHardLimitExtendChoiceMapsTimerValues() {
        XCTAssertEqual(HardLimitExtendChoice.minutes1.secondsValue, 60)
        XCTAssertEqual(HardLimitExtendChoice.minutes5.secondsValue, 300)
        XCTAssertEqual(HardLimitExtendChoice.minutes15.secondsValue, 900)
        XCTAssertNil(HardLimitExtendChoice.minutes15.sessionValue)
    }

    func testHardLimitExtendChoiceMapsPomodoroValues() {
        XCTAssertEqual(HardLimitExtendChoice.session1.sessionValue, 1)
        XCTAssertEqual(HardLimitExtendChoice.session2.sessionValue, 2)
        XCTAssertNil(HardLimitExtendChoice.session1.secondsValue)
    }

    func testHardLimitCountdownAdvancesAndExpiresOnce() {
        var state = HardLimitCountdownState(duration: 30)

        XCTAssertFalse(state.advance(by: 12))
        XCTAssertEqual(state.remaining, 18)
        XCTAssertEqual(state.progress, 0.6, accuracy: 0.001)
        XCTAssertEqual(state.displayedSeconds, 18)

        XCTAssertTrue(state.advance(by: 18))
        XCTAssertEqual(state.remaining, 0)
        XCTAssertFalse(state.isRunning)
        XCTAssertFalse(state.advance(by: 1))
    }

    func testHardLimitCountdownPausePreservesRemainingTime() {
        var state = HardLimitCountdownState(duration: 30)
        state.isPaused = true

        XCTAssertFalse(state.advance(by: 3))
        XCTAssertEqual(state.remaining, 30)

        state.isPaused = false
        XCTAssertFalse(state.advance(by: 2.5))
        XCTAssertEqual(state.remaining, 27.5)
        XCTAssertEqual(state.displayedSeconds, 28)
    }

    func testHardLimitCountdownClampsProjection() {
        let state = HardLimitCountdownState(duration: 30, remaining: 40)

        XCTAssertEqual(state.remaining, 30)
        XCTAssertEqual(state.progress, 1)
    }

    func testHardLimitCountdownWaitsForAllPauseReasonsToClear() {
        let service = HardLimitCountdownService()
        service.start {}
        XCTAssertEqual(service.state.duration, 30)

        service.setPaused(true, reason: .hoverEnd)
        service.setPaused(true, reason: .keyboardFocus)
        XCTAssertTrue(service.state.isPaused)

        service.setPaused(false, reason: .hoverEnd)
        XCTAssertTrue(service.state.isPaused)

        service.setPaused(false, reason: .keyboardFocus)
        XCTAssertFalse(service.state.isPaused)
        service.cancel()
    }

    func testStatusPopupOriginCentersBelowIcon() {
        let origin = StatusBarService.popupOrigin(
            iconRect: NSRect(x: 850, y: 1050, width: 20, height: 20),
            menuBarBottomY: 1050,
            panelSize: NSSize(width: 420, height: 400),
            visibleFrame: NSRect(x: 0, y: 0, width: 1920, height: 1050)
        )

        XCTAssertEqual(origin.x, 650)
        XCTAssertEqual(origin.y, 638)
    }

    func testStatusPopupOriginClampsToVisibleScreenEdges() {
        let leftOrigin = StatusBarService.popupOrigin(
            iconRect: NSRect(x: 10, y: 1050, width: 20, height: 20),
            menuBarBottomY: 1050,
            panelSize: NSSize(width: 420, height: 400),
            visibleFrame: NSRect(x: 0, y: 0, width: 1920, height: 1050)
        )
        let rightOrigin = StatusBarService.popupOrigin(
            iconRect: NSRect(x: 1900, y: 1050, width: 20, height: 20),
            menuBarBottomY: 1050,
            panelSize: NSSize(width: 420, height: 400),
            visibleFrame: NSRect(x: 0, y: 0, width: 1920, height: 1050)
        )

        XCTAssertEqual(leftOrigin.x, 8)
        XCTAssertEqual(rightOrigin.x, 1492)
    }

    func testStatusPopupOriginUsesSecondaryScreenCoordinates() {
        let origin = StatusBarService.popupOrigin(
            iconRect: NSRect(x: -600, y: 880, width: 20, height: 20),
            menuBarBottomY: 880,
            panelSize: NSSize(width: 420, height: 300),
            visibleFrame: NSRect(x: -1440, y: 0, width: 1440, height: 880)
        )

        XCTAssertEqual(origin.x, -800)
        XCTAssertEqual(origin.y, 568)
    }

    func testStatusPopupSizingClampsTransientMeasurements() {
        XCTAssertEqual(StatusPopupSizing.resolvedHeight(for: 120), 180)
        XCTAssertEqual(StatusPopupSizing.resolvedHeight(for: 312.2), 313)
        XCTAssertEqual(StatusPopupSizing.resolvedHeight(for: 800), 700)
    }

    func testPopoverModalMinimumHeightsRemainBounded() {
        XCTAssertEqual(PopoverModalKind.statusNote.minimumHeight, 260)
        XCTAssertEqual(PopoverModalKind.endSession.minimumHeight, 360)
        XCTAssertEqual(PopoverModalKind.dueDate.minimumHeight, 430)
        XCTAssertLessThan(PopoverModalKind.dueDate.minimumHeight, StatusPopupSizing.maximumHeight)
    }

    func testAlertSettingsOptimisticProjectionMapsSoundAndProminence() throws {
        let settings = try JSONDecoder().decode(
            CronaAlertSettings.self,
            from: Data("""
            {
              "alertSoundPreset":"chime",
              "alertUrgency":"normal"
            }
            """.utf8)
        )

        let projected = settings
            .applying(key: "alertSoundPreset", value: .string("focus_gong"))
            .applying(key: "alertUrgency", value: .string("high"))

        XCTAssertEqual(projected.alertSoundPreset, .focusGong)
        XCTAssertEqual(projected.alertUrgency, .timeSensitive)
    }

    func testDaemonClientBuildsSingleAlertSettingPatch() async throws {
        let response = Data(#"{"id":"response-1","result":{"ok":true}}"#.utf8)
        let transport = CapturingDaemonTransport(responseData: response)
        let client = CronaDaemonClient(transport: transport)

        try await client.alertSettingPatch(
            key: "alertSoundPreset",
            value: .string("notification_ping")
        )

        let request = try XCTUnwrap(transport.requestData)
        let requestProbe = try JSONDecoder().decode(RequestWithParamsProbe.self, from: request)
        XCTAssertEqual(requestProbe.method, "settings.patch")
        XCTAssertEqual(requestProbe.params["key"]?.stringValue, "alertSoundPreset")
        XCTAssertEqual(requestProbe.params["value"]?.stringValue, "notification_ping")
    }

    func testDaemonClientSelectsLocalAlertSettings() async throws {
        let response = alertSettingsResponse(
            entries: """
            "other": {"alertSoundPreset":"chime","alertUrgency":"low"},
            "local": {"alertSoundPreset":"focus_gong","alertUrgency":"high"}
            """
        )
        let client = CronaDaemonClient(
            transport: CapturingDaemonTransport(responseData: response)
        )

        let settings = try await client.alertSettingsGet()

        XCTAssertEqual(settings.alertSoundPreset, .focusGong)
        XCTAssertEqual(settings.alertUrgency, .timeSensitive)
    }

    func testDaemonClientFallsBackToAvailableAlertSettingsUser() async throws {
        let response = alertSettingsResponse(
            entries: """
            "account-user": {
              "alertSoundPreset":"notification_ping",
              "alertUrgency":"low"
            }
            """
        )
        let client = CronaDaemonClient(
            transport: CapturingDaemonTransport(responseData: response)
        )

        let settings = try await client.alertSettingsGet()

        XCTAssertEqual(settings.alertSoundPreset, .notificationPing)
        XCTAssertEqual(settings.alertUrgency, .quiet)
    }

    func testDaemonClientRejectsEmptyAlertSettingsMap() async {
        let response = alertSettingsResponse(entries: "")
        let client = CronaDaemonClient(
            transport: CapturingDaemonTransport(responseData: response)
        )

        do {
            _ = try await client.alertSettingsGet()
            XCTFail("Expected an empty settings map to be rejected")
        } catch let error as CronaConnectionFailure {
            XCTAssertEqual(error, .malformedResponse)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func alertSettingsResponse(entries: String) -> Data {
        Data(
            """
            {
              "id":"response-1",
              "result":{\(entries)}
            }
            """.utf8
        )
    }
}

private final class TestBundle: Bundle, @unchecked Sendable {
    private let values: [String: Any]

    init(values: [String: Any]) {
        self.values = values
        super.init()
    }

    static func info(_ values: [String: Any]) -> Bundle {
        TestBundle(values: values)
    }

    override func object(forInfoDictionaryKey key: String) -> Any? {
        values[key]
    }
}

private struct RequestProbe: Decodable {
    let id: String
    let method: String
}

private struct RequestWithParamsProbe: Decodable {
    let id: String
    let method: String
    let params: [String: JSONScalar]
}

private struct AlertDeliveryAckRequestProbe: Decodable {
    struct Params: Decodable {
        let deliveryID: String
        let notificationAccepted: Bool
        let soundAccepted: Bool

        enum CodingKeys: String, CodingKey {
            case deliveryID = "deliveryId"
            case notificationAccepted
            case soundAccepted
        }
    }

    let method: String
    let params: Params
}

private struct AlertDeliverySubscriptionProbe: Decodable {
    struct Params: Decodable {
        let clientID: String
        let notifications: Bool
        let sounds: Bool

        enum CodingKeys: String, CodingKey {
            case clientID = "clientId"
            case notifications
            case sounds
        }
    }

    let method: String
    let params: Params
}

private enum JSONScalar: Decodable {
    case string(String)
    case int(Int)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    var stringValue: String? {
        if case let .string(value) = self { return value }
        return nil
    }

    var intValue: Int? {
        if case let .int(value) = self { return value }
        return nil
    }
}

@MainActor
private final class SmartPauseTimerController: SmartPauseTimerControlling {
    private let subject = PassthroughSubject<TimerSnapshot, Never>()
    var snapshot = TimerSnapshot()
    private(set) var pauseCount = 0
    private(set) var resumeCount = 0

    var smartPauseSnapshot: TimerSnapshot { snapshot }
    var smartPauseSnapshots: AnyPublisher<TimerSnapshot, Never> {
        subject.eraseToAnyPublisher()
    }

    func pauseForSmartPause() async throws -> TimerSnapshot {
        pauseCount += 1
        snapshot.state = "paused"
        subject.send(snapshot)
        return snapshot
    }

    func resumeFromSmartPause() async throws -> TimerSnapshot {
        resumeCount += 1
        snapshot.state = "running"
        subject.send(snapshot)
        return snapshot
    }
}

private final class SmartPauseMonitor: SmartPauseSystemMonitoring {
    private(set) var isStarted = false

    func start(handler: @escaping @MainActor (SmartPauseSystemEvent) -> Void) {
        isStarted = true
    }

    func stop() {
        isStarted = false
    }
}

private struct SmartPauseIdleProvider: SmartPauseIdleTimeProviding {
    let seconds: TimeInterval
    var idleSeconds: TimeInterval { seconds }
}

private final class SmartPauseMutableIdleProvider: SmartPauseIdleTimeProviding {
    var seconds: TimeInterval
    var idleSeconds: TimeInterval { seconds }

    init(seconds: TimeInterval) {
        self.seconds = seconds
    }
}

private final class CapturingDaemonTransport: CronaDaemonTransport {
    let responseData: Data
    private(set) var requestData: Data?

    init(responseData: Data) {
        self.responseData = responseData
    }

    func send(_ request: Data) async throws -> Data {
        requestData = request
        return responseData
    }

    func openEventStream(with request: Data) async throws -> AsyncThrowingStream<CronaProtocolEvent, Error> {
        requestData = request
        return AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}
