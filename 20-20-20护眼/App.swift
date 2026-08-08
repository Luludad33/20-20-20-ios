import SwiftUI
import UserNotifications

@main
struct EyeCareApp: App, UNUserNotificationCenterDelegate {
    @StateObject private var timerManager = TimerManager()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        UNUserNotificationCenter.current().delegate = self
    }

    // 前台也展示通知横幅并播放自定义声音
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

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
