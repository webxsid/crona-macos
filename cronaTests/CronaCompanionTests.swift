import XCTest
@testable import crona

@MainActor
final class CronaCompanionTests: XCTestCase {
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

    func testPreferencesPersist() throws {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let service = PreferencesService(defaults: defaults)
        service.preferences.menuBarDisplayMode = .iconOnly
        service.preferences.menuBarTimeFormat = .expanded
        service.preferences.menuBarShowsSeconds = false
        service.preferences.tuiCommand = "crona tui"

        let reloaded = PreferencesService(defaults: defaults)
        XCTAssertEqual(reloaded.preferences.menuBarDisplayMode, .iconOnly)
        XCTAssertEqual(reloaded.preferences.menuBarTimeFormat, .expanded)
        XCTAssertFalse(reloaded.preferences.menuBarShowsSeconds)
        XCTAssertEqual(reloaded.preferences.tuiCommand, "crona tui")
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
        let snapshot = TimerSnapshot(
            state: "running",
            sessionID: "session-1",
            issueID: 10,
            segmentType: "work",
            nextSegmentType: nil,
            readySegmentType: nil,
            elapsedSeconds: 600,
            displayElapsedSeconds: 1200,
            sessionStartTime: nil,
            segmentStartTime: nil,
            hardLimitActive: true,
            hardLimitExpired: false,
            hardLimitTotalSeconds: 1800,
            hardLimitRemainingSeconds: 600,
            hardLimitWorkSeconds: 1800,
            hardLimitBreakSeconds: 0,
            hardLimitLongBreakSeconds: 0,
            hardLimitCyclesBeforeLongBreak: 0,
            snapshotAppliedAt: Date(),
            isConnected: true
        )

        let presentation = TimerPresentation.from(snapshot)

        XCTAssertEqual(presentation.mode, .timer)
        XCTAssertTrue(presentation.countsDown)
        XCTAssertEqual(presentation.displaySeconds, 1200)
        XCTAssertEqual(presentation.progressFraction ?? 0, 2.0 / 3.0, accuracy: 0.001)
        XCTAssertTrue(presentation.canPause)
        XCTAssertEqual(presentation.phaseTitle, "Timer ends in")
    }

    func testTimerPresentationClassifiesPomodoroBreak() {
        let snapshot = TimerSnapshot(
            state: "running",
            sessionID: "session-1",
            issueID: 10,
            segmentType: "rest",
            nextSegmentType: "work",
            readySegmentType: nil,
            elapsedSeconds: 1500,
            displayElapsedSeconds: 300,
            sessionStartTime: nil,
            segmentStartTime: nil,
            hardLimitActive: true,
            hardLimitExpired: false,
            hardLimitTotalSeconds: 1800,
            hardLimitRemainingSeconds: 300,
            hardLimitWorkSeconds: 1500,
            hardLimitBreakSeconds: 300,
            hardLimitLongBreakSeconds: 900,
            hardLimitCyclesBeforeLongBreak: 4,
            snapshotAppliedAt: Date(),
            isConnected: true
        )

        let presentation = TimerPresentation.from(snapshot)

        XCTAssertEqual(presentation.mode, .pomodoro)
        XCTAssertEqual(presentation.phaseTitle, "Break ends in")
        XCTAssertEqual(presentation.displaySeconds, 300)
        XCTAssertNil(presentation.upcomingBreakSeconds)
    }

    func testFocusStartConfigBuildsStopwatchRequest() {
        let issue = DailyFocusIssue(id: 33, streamID: 22, title: "Issue", status: "planned", estimateMinutes: nil, workedSeconds: 0, todoForDate: nil)
        let state = FocusStartConfigState(mode: .stopwatch)

        let request = state.startRequest(for: issue)

        XCTAssertEqual(request.streamID, 22)
        XCTAssertEqual(request.issueID, 33)
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

        XCTAssertEqual(request.hardLimitTotalSeconds, 7800)
        XCTAssertEqual(request.hardLimitWorkSeconds, 1500)
        XCTAssertEqual(request.hardLimitBreakSeconds, 300)
        XCTAssertEqual(request.hardLimitLongBreakSeconds, 900)
        XCTAssertEqual(request.hardLimitCyclesBeforeLongBreak, 4)
    }

    func testFocusStartConfigUsesRemainingEstimateForTimerDefault() {
        let state = FocusStartConfigState.defaultState(estimateMinutes: 60, workedSeconds: 15 * 60)
        let issue = DailyFocusIssue(id: 33, streamID: 22, title: "Issue", status: "planned", estimateMinutes: 60, workedSeconds: 15 * 60, todoForDate: nil)
        var timerState = state
        timerState.mode = .timer

        let request = timerState.startRequest(for: issue)

        XCTAssertEqual(state.customCountdownMinutes, 45)
        XCTAssertEqual(state.countdownChoice, .custom)
        XCTAssertEqual(request.hardLimitTotalSeconds, 45 * 60)
        XCTAssertEqual(request.hardLimitBreakSeconds, 0)
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

    func testMenuBarFormatterClockWithSeconds() {
        let text = MenuBarTextFormatter.formatElapsed(seconds: 3661, format: .clock, showsSeconds: true)
        XCTAssertEqual(text, "1:01:01")
    }

    func testMenuBarFormatterExpandedWithoutSeconds() {
        let text = MenuBarTextFormatter.formatElapsed(seconds: 3661, format: .expanded, showsSeconds: false)
        XCTAssertEqual(text, "1h1m")
    }

    func testMenuBarFormatterFormatsMinutes() {
        XCTAssertEqual(MenuBarTextFormatter.formatMinutes(75), "1h15m")
    }

    func testMenuBarFormatterUsesIdleForConnectedWithoutTimer() {
        let preferences = CompanionPreferences(
            launchAtLogin: false,
            menuBarDisplayMode: .iconAndText,
            menuBarTimeFormat: .clock,
            menuBarShowsSeconds: true,
            pinPopover: false,
            runtimeDirectoryOverride: nil,
            tuiCommand: "crona"
        )
        let title = MenuBarTextFormatter.statusItemTitle(
            preferences: preferences,
            connectionState: .connected,
            timerSnapshot: TimerSnapshot()
        )
        XCTAssertEqual(title, "Idle")
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
            displayElapsedSeconds: 600,
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
        XCTAssertEqual(request?.hardLimitTotalSeconds, 1800)
    }

    func testQuickExtendRequestRejectsZeroSeconds() {
        let request = CompanionAppState.buildQuickExtendRequest(snapshot: TimerSnapshot(), additionalSeconds: 0)
        XCTAssertNil(request)
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
