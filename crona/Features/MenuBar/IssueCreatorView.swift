import SwiftUI

struct IssueCreatorView: View {
    @ObservedObject var appState: CompanionAppState
    @FocusState private var focusedField: Field?
    @State private var destinationPickerPresented = false
    @State private var selectedRepoID: Int64?
    @State private var streamQuery = ""

    private enum Field { case title, estimate, streamSearch, description }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Button(action: appState.cancelIssueCreator) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(PopupVisualTheme.primaryText.opacity(0.06)))
                        .padding(7)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(appState.issueCreationService.isCreating)
                .accessibilityLabel("Back")

                Text("Create Issue")
                    .font(.headline)
                    .foregroundStyle(PopupVisualTheme.primaryText)

                Spacer()
            }

            TextField("What needs doing?", text: $appState.issueCreateTitle)
                .textFieldStyle(.plain)
                .focused($focusedField, equals: .title)
                .onChange(of: appState.issueCreateTitle) { _, value in
                    if value.count > 120 { appState.issueCreateTitle = String(value.prefix(120)) }
                }
                .creatorField(isFocused: focusedField == .title)

            TextField("Estimate (e.g. 45m, 1h30m)", text: $appState.issueCreateEstimate)
                .textFieldStyle(.plain)
                .focused($focusedField, equals: .estimate)
                .creatorField(isFocused: focusedField == .estimate)

            destinationField

            DisclosureGroup("More Options", isExpanded: moreOptionsBinding) {
                TextField("Description (optional)", text: $appState.issueCreateDescription, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(2...4)
                    .focused($focusedField, equals: .description)
                    .onChange(of: appState.issueCreateDescription) { _, value in
                        if value.count > 2_000 { appState.issueCreateDescription = String(value.prefix(2_000)) }
                    }
                    .creatorField(isFocused: focusedField == .description)
                    .padding(.top, 8)
            }

            Spacer(minLength: 0)

            if let error = validationMessage ?? appState.issueCreationService.lastErrorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                Toggle(isOn: $appState.issueCreateForToday) {
                    Label("Today", systemImage: "calendar")
                }
                .toggleStyle(.checkbox)
                .help("Plan for today")

                Spacer()
                Button(appState.issueCreationService.isCreating ? "Creating…" : "Create Issue", action: appState.submitIssueCreator)
                    .keyboardShortcut(.defaultAction)
                    .disabled(validationMessage != nil || appState.issueCreationService.isCreating)
            }
        }
        .padding(20)
        .frame(width: 420)
        .frame(minHeight: 560, maxHeight: 560, alignment: .top)
        .onAppear {
            selectedRepoID = selectedDestination?.repoID
            DispatchQueue.main.async { focusedField = .title }
        }
        .onExitCommand {
            if destinationPickerPresented {
                destinationPickerPresented = false
                streamQuery = ""
                focusedField = .title
            } else {
                appState.cancelIssueCreator()
            }
        }
        .animation(.easeInOut(duration: 0.24), value: appState.issueCreateShowsMoreOptions)
    }

    private var destinationField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                selectedRepoID = selectedDestination?.repoID ?? repoGroups.first?.id
                destinationPickerPresented.toggle()
                if destinationPickerPresented {
                    appState.issueCreateShowsMoreOptions = false
                    DispatchQueue.main.async { focusedField = .streamSearch }
                }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "folder")
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Destination").font(.caption2).foregroundStyle(.secondary)
                        Text(selectedDestination?.label ?? "Choose repo and stream")
                            .lineLimit(1)
                            .foregroundStyle(selectedDestination == nil ? .secondary : PopupVisualTheme.primaryText)
                    }
                    Spacer()
                    Image(systemName: destinationPickerPresented ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .creatorField()

            if destinationPickerPresented {
                destinationDrillDown
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.24), value: destinationPickerPresented)
    }

    private var destinationDrillDown: some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(repoGroups) { repo in
                        Button {
                            selectedRepoID = repo.id
                            streamQuery = ""
                            focusedField = .streamSearch
                        } label: {
                            Text(repo.name)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 7)
                                .background(repo.id == selectedRepoID ? Color.accentColor.opacity(0.22) : .clear)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(width: 105, height: 145)

            Divider().padding(.horizontal, 8)

            VStack(spacing: 7) {
                TextField("Search streams", text: $streamQuery)
                    .textFieldStyle(.plain)
                    .focused($focusedField, equals: .streamSearch)
                    .creatorField(isFocused: focusedField == .streamSearch)

                if appState.issueCreationService.isLoadingDestinations {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if repoGroups.isEmpty {
                    emptyDestinationView
                } else if filteredStreams.isEmpty {
                    Text(streamQuery.isEmpty ? "No streams" : "No matches")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 3) {
                            ForEach(filteredStreams) { destination in
                                Button {
                                    appState.issueCreateDestinationID = destination.streamID
                                    selectedRepoID = destination.repoID
                                    streamQuery = ""
                                    destinationPickerPresented = false
                                    focusedField = .title
                                } label: {
                                    HStack(spacing: 7) {
                                        Image(systemName: destination.streamID == appState.issueCreateDestinationID
                                            ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(destination.streamID == appState.issueCreateDestinationID ? .yellow : .secondary)
                                        Text(destination.streamName).lineLimit(1)
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.horizontal, 6).padding(.vertical, 5)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 145, maxHeight: 145)
        }
        .padding(8)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(PopupVisualTheme.divider.opacity(0.5))
                .frame(height: 0.5)
        }
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(PopupVisualTheme.surfaceStroke, lineWidth: 0.7))
    }

    private var emptyDestinationView: some View {
        VStack(spacing: 6) {
            Text("Create a repo and stream in Crona first.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Open Crona") {
                appState.cancelIssueCreator()
                appState.openTUI()
            }
            .buttonStyle(.link)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private struct RepoGroup: Identifiable {
        let id: Int64
        let name: String
    }

    private var repoGroups: [RepoGroup] {
        var seen = Set<Int64>()
        return appState.issueCreationService.destinations.compactMap { destination in
            guard seen.insert(destination.repoID).inserted else { return nil }
            return RepoGroup(id: destination.repoID, name: destination.repoName)
        }
    }

    private var filteredStreams: [IssueDestination] {
        let query = streamQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return appState.issueCreationService.destinations.filter {
            $0.repoID == selectedRepoID && (query.isEmpty || $0.streamName.localizedCaseInsensitiveContains(query))
        }
    }

    private var selectedDestination: IssueDestination? {
        appState.issueCreationService.destinations.first { $0.streamID == appState.issueCreateDestinationID }
    }

    private var moreOptionsBinding: Binding<Bool> {
        Binding(
            get: { appState.issueCreateShowsMoreOptions },
            set: { expanded in
                appState.issueCreateShowsMoreOptions = expanded
                if expanded {
                    destinationPickerPresented = false
                    streamQuery = ""
                }
            }
        )
    }

    private var validationMessage: String? {
        if appState.issueCreateTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Issue title is required."
        }
        if appState.issueCreateDestinationID == nil { return "Choose a repo and stream." }
        if case .failure = FlexibleDurationParser.optionalMinutes(appState.issueCreateEstimate) {
            return "Estimate must be like 90, 90m, 1h30m, 1.5h, or 1h34m23s."
        }
        return nil
    }
}

struct IssueCreationSuccessView: View {
    @ObservedObject var appState: CompanionAppState
    let success: IssueCreationSuccess

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text("Created \(success.issue.title)").font(.caption.weight(.semibold)).lineLimit(1)
            Spacer(minLength: 0)
            if success.plannedForToday && !appState.hasActiveFocusSession {
                Button("Start Focus", action: appState.startFocusFromCreatedIssue)
                    .buttonStyle(.plain).font(.caption.weight(.semibold)).foregroundStyle(.yellow)
            }
            Button(action: appState.dismissIssueCreationSuccess) { Image(systemName: "xmark") }
                .buttonStyle(.plain).accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14).fill(PopupVisualTheme.primaryText.opacity(0.07)))
    }
}

private extension View {
    func creatorField(isFocused: Bool = false) -> some View {
        padding(10)
            .popupInputSurface(isFocused: isFocused)
    }
}
