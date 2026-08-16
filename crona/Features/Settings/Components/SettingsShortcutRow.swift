import AppKit
import SwiftUI

struct SettingsShortcutRow: View {
    @Binding var shortcut: SettingsShortcut?
    @State private var recordingState: ShortcutRecordingState?
    @State private var confirmationDismissTask: Task<Void, Never>?

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Open Settings")
                    .font(.subheadline.weight(.medium))
                Text("Choose a global shortcut to open Crona Settings.")
                    .font(.caption)
                    .foregroundStyle(PopupVisualTheme.secondaryText)
            }

            Spacer(minLength: 16)

            HStack(spacing: 8) {
                ShortcutRecorder(
                    shortcut: $shortcut,
                    onRecordingStateChange: handleRecordingStateChange
                )
                .frame(width: 150, height: 28)
                .overlay(alignment: .top) {
                    if let recordingState {
                        ShortcutRecordingOverlay(state: recordingState)
                            .offset(y: -50)
                            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)))
                            .zIndex(1)
                    }
                }

                if shortcut != nil {
                    Button("Clear") { shortcut = nil }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(PopupVisualTheme.secondaryText)
                }
            }
        }
        .padding(.vertical, 5)
        .onDisappear { confirmationDismissTask?.cancel() }
    }

    private func handleRecordingStateChange(_ state: ShortcutRecordingState?) {
        confirmationDismissTask?.cancel()
        withAnimation(.easeOut(duration: 0.14)) {
            recordingState = state
        }

        guard case .confirmed = state else { return }
        confirmationDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.14)) {
                recordingState = nil
            }
        }
    }
}

private struct ShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: SettingsShortcut?
    let onRecordingStateChange: (ShortcutRecordingState?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        button.target = context.coordinator
        button.action = #selector(Coordinator.beginRecording)
        button.onShortcut = { shortcut in context.coordinator.parent.shortcut = shortcut }
        button.onRecordingStateChange = { state in
            context.coordinator.parent.onRecordingStateChange(state)
        }
        return button
    }

    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        button.shortcut = shortcut
    }

    final class Coordinator: NSObject {
        var parent: ShortcutRecorder
        init(_ parent: ShortcutRecorder) { self.parent = parent }
        @objc func beginRecording(_ sender: ShortcutRecorderButton) { sender.beginRecording() }
    }
}

private final class ShortcutRecorderButton: NSButton {
    var shortcut: SettingsShortcut? { didSet { updateTitle() } }
    var onShortcut: ((SettingsShortcut) -> Void)?
    var onRecordingStateChange: ((ShortcutRecordingState?) -> Void)?
    private var isRecording = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        focusRingType = .default
        updateTitle()
    }

    required init?(coder: NSCoder) { nil }

    func beginRecording() {
        isRecording = true
        title = "Press shortcut"
        onRecordingStateChange?(.recording(modifiers: modifierDisplay(for: NSEvent.modifierFlags)))
        window?.makeFirstResponder(self)
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else { return super.flagsChanged(with: event) }
        onRecordingStateChange?(.recording(modifiers: modifierDisplay(for: event.modifierFlags)))
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return super.keyDown(with: event) }
        if event.keyCode == 53 {
            isRecording = false
            updateTitle()
            onRecordingStateChange?(nil)
            return
        }
        guard let shortcut = SettingsShortcut(event: event) else {
            onRecordingStateChange?(.recording(modifiers: modifierDisplay(for: event.modifierFlags)))
            return
        }
        isRecording = false
        onShortcut?(shortcut)
        self.shortcut = shortcut
        onRecordingStateChange?(.confirmed(shortcut.display))
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event)
        return true
    }

    private func updateTitle() {
        guard !isRecording else { return }
        title = shortcut?.display ?? "Record Shortcut"
    }

    private func modifierDisplay(for flags: NSEvent.ModifierFlags) -> String {
        let flags = flags.intersection(.deviceIndependentFlagsMask)
        var display = ""
        if flags.contains(.control) { display += "⌃" }
        if flags.contains(.option) { display += "⌥" }
        if flags.contains(.shift) { display += "⇧" }
        if flags.contains(.command) { display += "⌘" }
        return display
    }
}

private enum ShortcutRecordingState: Equatable {
    case recording(modifiers: String)
    case confirmed(String)

    var title: String {
        switch self {
        case let .recording(modifiers):
            modifiers.isEmpty ? "Press a shortcut" : modifiers
        case let .confirmed(shortcut):
            shortcut
        }
    }

    var subtitle: String {
        switch self {
        case .recording:
            "Hold modifiers, then press a key"
        case .confirmed:
            "Shortcut saved"
        }
    }
}

private struct ShortcutRecordingOverlay: View {
    let state: ShortcutRecordingState

    var body: some View {
        VStack(spacing: 2) {
            Text(state.title)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(PopupVisualTheme.primaryText)
            Text(state.subtitle)
                .font(.caption2)
                .foregroundStyle(PopupVisualTheme.secondaryText)
        }
        .fixedSize()
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(PopupVisualTheme.surfaceStroke, lineWidth: 0.75)
        }
        .shadow(color: PopupVisualTheme.shadow.opacity(0.16), radius: 8, y: 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Shortcut recording: \(state.title)")
    }
}
