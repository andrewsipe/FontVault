import AppKit
import SwiftUI

/// FEX-style launch sheet shown while the catalog and first browse page load.
struct LaunchProgressView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: DesignMetrics.sectionSpacing) {
            Spacer()

            VStack(spacing: DesignMetrics.controlSpacing + 4) {
                Text("Font Vault")
                    .font(.largeTitle.weight(.semibold))

                if case .failed(let message) = appState.launchPhase {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                } else {
                    ProgressView()
                        .controlSize(.regular)
                        .frame(width: 220)

                    Text(appState.launchStatusMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }
            }

            Spacer()

            if case .failed = appState.launchPhase {
                HStack(spacing: DesignMetrics.controlSpacing + 4) {
                    Button("Quit") {
                        NSApp.terminate(nil)
                    }
                    .keyboardShortcut(.cancelAction)

                    Button("Retry") {
                        appState.retryLaunch()
                    }
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.bottom, DesignMetrics.windowMargin)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
