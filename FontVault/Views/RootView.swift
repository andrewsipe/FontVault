import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openSettings) private var openSettings
    @ObservedObject private var settings = VaultSettings.shared

    var body: some View {
        Group {
            if !settings.hasCompletedOnboarding || settings.vaultRootURL == nil {
                OnboardingView()
            } else if !appState.launchPhase.isReady {
                LaunchProgressView()
            } else {
                MainWindowView()
            }
        }
        .onAppear {
            if settings.hasCompletedOnboarding, settings.vaultRootURL != nil {
                appState.startLaunch()
            }
        }
        .onChange(of: appState.settingsOpenRequest) { _, request in
            guard let request else { return }
            appState.settingsTab = request.tab
            openSettings()
            DispatchQueue.main.async {
                appState.clearSettingsOpenRequest()
            }
        }
    }
}
