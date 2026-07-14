import SwiftUI

struct DiagnosticsView: View {
    @ObservedObject var appState: CompanionAppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Form {
                LabeledContent("Connection State") {
                    Text(appState.diagnosticsService.snapshot.connectionState)
                }
                LabeledContent("Protocol Version") {
                    Text(appState.diagnosticsService.snapshot.protocolVersion)
                }
                LabeledContent("Kernel Version") {
                    Text(appState.diagnosticsService.snapshot.kernelVersion)
                }
                LabeledContent("Runtime Directory") {
                    Text(appState.diagnosticsService.snapshot.runtimeDirectory)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Health") {
                    Text(appState.diagnosticsService.snapshot.healthSummary)
                }
                LabeledContent("Last Reconnect") {
                    Text(appState.diagnosticsService.snapshot.lastReconnect)
                }
            }

            HStack {
                Button("Copy Diagnostics") {
                    appState.diagnosticsService.copyToPasteboard()
                }
                Button("Manual Reconnect") {
                    appState.manualReconnect()
                }
            }

            Spacer()
        }
        .padding()
        .onAppear {
            Task { await appState.diagnosticsService.refresh() }
        }
    }
}
