import SwiftUI

@main
struct EyeCareApp: App {
    @StateObject private var timerManager = TimerManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(timerManager)
                .onChange(of: scenePhase) { _, newPhase in
                    timerManager.handleScenePhaseChange(to: newPhase)
                }
        }
    }
}
