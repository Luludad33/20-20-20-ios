import Foundation
import UserNotifications
import SwiftUI

@MainActor
class TimerManager: ObservableObject {
    enum Phase: String, Codable {
        case idle, working, resting
    }

    // MARK: - Published state
    @Published var phase: Phase = .idle
    @Published var timeRemaining: TimeInterval = 0
    @Published var totalTime: TimeInterval = 1200
    @Published var isRunning = false
    @Published var todayCycles = 0
    @Published var todayRestSec = 0
    @Published var showOverlay = false
    @Published var healthTip = ""
    @Published var darkMode = false

    var progress: Double {
        totalTime > 0 ? (timeRemaining / totalTime) : 1.0
    }

    // MARK: - Constants
    private let healthTips = [
        "看看窗外远处，放松眼部肌肉",
        "闭眼休息，轻轻按摩眼眶",
        "做几个深呼吸，放松身心",
        "转动眼球，上下左右各看几次",
        "伸展手臂和肩膀，缓解久坐疲劳",
        "看远处绿色植物，对眼睛有益",
        "眨眼几次，保持眼睛湿润",
        "远眺时尝试聚焦在不同距离的物体上",
        "站起来活动一下，喝口水",
        "调整坐姿，保持脊柱挺直",
    ]

    // MARK: - Wall-clock tracking
    private var deadline: Date?
    private var tickTimer: Timer?
    private var workMinutes: Int = 20
    private var restSeconds: Int = 20

    // MARK: - UserDefaults keys
    private let defaults = UserDefaults.standard

    init() {
        requestNotificationPermission()
        loadSettings()
        loadDailyStats()
    }

    // MARK: - Public API

    func startWorking() {
        let duration = TimeInterval(workMinutes * 60)
        deadline = Date().addingTimeInterval(duration)
        totalTime = duration
        timeRemaining = duration
        phase = .working
        isRunning = true
        showOverlay = false
        saveTimerState()
        scheduleNotification(title: "该休息了！", body: "看看 20 英尺外的远处，放松 20 秒", after: duration)
        startTicking()
    }

    func pause() {
        guard phase != .idle else { return }
        isRunning = false
        stopTicking()
        saveTimerState()
        cancelNotification()
    }

    func resume() {
        guard phase != .idle, !isRunning else { return }
        guard let oldDeadline = deadline else { return }
        // Recalculate deadline from remaining time
        deadline = Date().addingTimeInterval(timeRemaining)
        isRunning = true
        saveTimerState()
        scheduleNotification(title: phase == .working ? "该休息了！" : "休息结束",
                             body: phase == .working ? "看看 20 英尺外的远处" : "继续工作吧！",
                             after: timeRemaining)
        startTicking()
    }

    func reset() {
        stopTicking()
        deadline = nil
        phase = .idle
        timeRemaining = TimeInterval(workMinutes * 60)
        totalTime = TimeInterval(workMinutes * 60)
        isRunning = false
        showOverlay = false
        cancelNotification()
        clearTimerState()
    }

    func skipRest() {
        guard phase == .resting else { return }
        stopTicking()
        // Credit partial rest seconds
        let elapsed = restSeconds - Int(timeRemaining)
        if elapsed > 0 {
            todayRestSec += elapsed
        }
        showOverlay = false
        saveDailyStats()
        // Start next work
        let duration = TimeInterval(workMinutes * 60)
        deadline = Date().addingTimeInterval(duration)
        totalTime = duration
        timeRemaining = duration
        phase = .working
        isRunning = true
        saveTimerState()
        scheduleNotification(title: "该休息了！", body: "看看 20 英尺外的远处，放松 20 秒", after: duration)
        startTicking()
    }

    func updateWorkMinutes(_ val: Int) {
        workMinutes = max(1, min(120, val))
        defaults.set(workMinutes, forKey: "workMinutes")
        if phase == .idle {
            timeRemaining = TimeInterval(workMinutes * 60)
            totalTime = TimeInterval(workMinutes * 60)
        }
    }

    func updateRestSeconds(_ val: Int) {
        restSeconds = max(5, min(300, val))
        defaults.set(restSeconds, forKey: "restSeconds")
    }

    var currentWorkMinutes: Int { workMinutes }
    var currentRestSeconds: Int { restSeconds }

    // MARK: - Background / Foreground

    func enteredBackground() {
        stopTicking()
        if phase != .idle {
            saveTimerState()
        }
    }

    func returnedToForeground() {
        guard let savedDeadline = deadline, phase != .idle else {
            loadDailyStats()
            return
        }
        let now = Date()
        if savedDeadline > now {
            // Phase still active
            timeRemaining = savedDeadline.timeIntervalSince(now)
            if isRunning {
                startTicking()
            }
        } else {
            // Phase expired while away
            let overshoot = now.timeIntervalSince(savedDeadline)
            if phase == .working {
                handleWorkExpiredInBackground(overshoot: overshoot)
            } else {
                handleRestExpiredInBackground(overshoot: overshoot)
            }
        }
    }

    // MARK: - Private

    private func handleWorkExpiredInBackground(overshoot: TimeInterval) {
        todayCycles += 1
        // Check if rest also expired
        let restDuration = TimeInterval(restSeconds)
        if overshoot >= restDuration {
            // Both work and rest expired
            todayRestSec += restSeconds
            saveDailyStats()
            // Start new work
            let duration = TimeInterval(workMinutes * 60)
            deadline = Date().addingTimeInterval(duration)
            totalTime = duration
            timeRemaining = duration
            phase = .working
            isRunning = true
            saveTimerState()
            scheduleNotification(title: "该休息了！", body: "看看 20 英尺外的远处", after: duration)
            startTicking()
        } else {
            // Rest still in progress
            let remaining = restDuration - overshoot
            deadline = Date().addingTimeInterval(remaining)
            totalTime = restDuration
            timeRemaining = remaining
            phase = .resting
            showOverlay = true
            healthTip = healthTips.randomElement() ?? ""
            isRunning = true
            saveTimerState()
            scheduleNotification(title: "休息结束", body: "继续工作吧！", after: remaining)
            startTicking()
        }
    }

    private func handleRestExpiredInBackground(overshoot: TimeInterval) {
        todayRestSec += Int(TimeInterval(restSeconds) - overshoot)
        saveDailyStats()
        // Start next work
        let duration = TimeInterval(workMinutes * 60)
        deadline = Date().addingTimeInterval(duration)
        totalTime = duration
        timeRemaining = duration
        phase = .working
        showOverlay = false
        isRunning = true
        saveTimerState()
        scheduleNotification(title: "该休息了！", body: "看看 20 英尺外的远处", after: duration)
        startTicking()
    }

    private func startTicking() {
        stopTicking()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self, let deadline = self.deadline else { return }
            let remaining = max(0, deadline.timeIntervalSinceNow)
            DispatchQueue.main.async {
                self.timeRemaining = remaining
            }
            if remaining <= 0 {
                DispatchQueue.main.async {
                    self.stopTicking()
                    self.completePhase()
                }
            }
        }
    }

    private func stopTicking() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    private func completePhase() {
        if phase == .working {
            // WORK -> REST
            todayCycles += 1
            let duration = TimeInterval(restSeconds)
            deadline = Date().addingTimeInterval(duration)
            totalTime = duration
            timeRemaining = duration
            phase = .resting
            showOverlay = true
            healthTip = healthTips.randomElement() ?? ""
            isRunning = true
            saveDailyStats()
            saveTimerState()
            cancelNotification()
            scheduleNotification(title: "休息结束", body: "继续工作吧！", after: duration)
            startTicking()
            // Haptic feedback
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else if phase == .resting {
            // REST -> WORK
            let duration = TimeInterval(workMinutes * 60)
            deadline = Date().addingTimeInterval(duration)
            totalTime = duration
            timeRemaining = duration
            phase = .working
            showOverlay = false
            isRunning = true
            saveTimerState()
            cancelNotification()
            scheduleNotification(title: "该休息了！", body: "看看 20 英尺外的远处", after: duration)
            startTicking()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    // MARK: - Notifications

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private func scheduleNotification(title: String, body: String, after duration: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, duration), repeats: false)
        let request = UNNotificationRequest(identifier: "eye20-timer", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    private func cancelNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["eye20-timer"])
    }

    // MARK: - Persistence

    private func saveTimerState() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(phase.rawValue) {
            defaults.set(data, forKey: "timerPhase")
        }
        if let deadline {
            defaults.set(deadline.timeIntervalSince1970, forKey: "timerDeadline")
        }
        defaults.set(isRunning, forKey: "timerIsRunning")
        defaults.set(showOverlay, forKey: "timerShowOverlay")
        if !healthTip.isEmpty {
            defaults.set(healthTip, forKey: "timerHealthTip")
        }
        defaults.synchronize()
    }

    private func loadTimerState() {
        if let data = defaults.data(forKey: "timerPhase"),
           let phaseRaw = try? JSONDecoder().decode(String.self, from: data),
           let savedPhase = Phase(rawValue: phaseRaw) {
            phase = savedPhase
        }
        let savedDeadline = defaults.double(forKey: "timerDeadline")
        if savedDeadline > 0 {
            deadline = Date(timeIntervalSince1970: savedDeadline)
        }
        isRunning = defaults.bool(forKey: "timerIsRunning")
        showOverlay = defaults.bool(forKey: "timerShowOverlay")
        if let tip = defaults.string(forKey: "timerHealthTip") {
            healthTip = tip
        }
    }

    private func clearTimerState() {
        defaults.removeObject(forKey: "timerPhase")
        defaults.removeObject(forKey: "timerDeadline")
        defaults.removeObject(forKey: "timerIsRunning")
        defaults.removeObject(forKey: "timerShowOverlay")
        defaults.removeObject(forKey: "timerHealthTip")
    }

    private func loadSettings() {
        workMinutes = defaults.integer(forKey: "workMinutes")
        if workMinutes == 0 { workMinutes = 20 }
        restSeconds = defaults.integer(forKey: "restSeconds")
        if restSeconds == 0 { restSeconds = 20 }
        darkMode = defaults.bool(forKey: "darkMode")
        // Restore timer state from last session
        loadTimerState()
        if phase != .idle, let deadline {
            let remaining = deadline.timeIntervalSince(Date())
            if remaining > 0 {
                timeRemaining = remaining
                totalTime = phase == .working ? TimeInterval(workMinutes * 60) : TimeInterval(restSeconds)
                if isRunning {
                    startTicking()
                }
            } else {
                // Timer expired while app was closed
                reset()
            }
        } else {
            timeRemaining = TimeInterval(workMinutes * 60)
            totalTime = TimeInterval(workMinutes * 60)
        }
    }

    private func saveDailyStats() {
        let key = todayKey
        defaults.set(todayCycles, forKey: "cycles_\(key)")
        defaults.set(todayRestSec, forKey: "restSec_\(key)")
    }

    private func loadDailyStats() {
        let key = todayKey
        let savedCycles = defaults.integer(forKey: "cycles_\(key)")
        let savedRest = defaults.integer(forKey: "restSec_\(key)")
        // Corner case: if timer ran while app was closed, we might have already
        // incremented cycles from loadTimerState -> reset(). Don't overwrite.
        if savedCycles > todayCycles || phase == .idle {
            todayCycles = savedCycles
        }
        if savedRest > todayRestSec || phase == .idle {
            todayRestSec = savedRest
        }
    }

    private var todayKey: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}
