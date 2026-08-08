import SwiftUI
import UserNotifications

@main
struct EyeCareApp: App {
    @StateObject private var timerManager = TimerManager()
    @Environment(\.scenePhase) private var scenePhase
    private let notificationDelegate = NotificationDelegate()

    init() {
        UNUserNotificationCenter.current().delegate = notificationDelegate
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

// UNUserNotificationCenterDelegate 是类协议，必须由 NSObject 子类实现
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    // 前台也展示通知横幅并播放自定义声音
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}
