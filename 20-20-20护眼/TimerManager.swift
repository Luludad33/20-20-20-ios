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
    @Published var showOverlay = false
    @Published var healthTip = ""
    @Published var darkMode = false
    @Published var screenFlash = false
    @Published var showRestEndToast = false
    @Published var scheduleCycleCount = 15

    var progress: Double {
        totalTime > 0 ? (timeRemaining / totalTime) : 1.0
    }

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

    private var deadline: Date?
    private var tickTimer: Timer?
    private var workMinutes: Int = 20
    private var restSeconds: Int = 20
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
        scheduleNotificationChain()
        startTicking()
    }

    func pause() {
        guard phase != .idle else { return }
        isRunning = false
        stopTicking()
        saveTimerState()
        cancelAllTimerNotifications()
    }

    func resume() {
        guard phase != .idle, !isRunning else { return }
        deadline = Date().addingTimeInterval(timeRemaining)
        isRunning = true
        saveTimerState()
        scheduleNotificationChain()
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
        cancelAllTimerNotifications()
        clearTimerState()
    }

    func skipRest() {
        guard phase == .resting else { return }
        stopTicking()
        showOverlay = false
        saveDailyStats()
        let duration = TimeInterval(workMinutes * 60)
        deadline = Date().addingTimeInterval(duration)
        totalTime = duration
        timeRemaining = duration
        phase = .working
        isRunning = true
        saveTimerState()
        scheduleNotificationChain()
        startTicking()
        showRestEndToast = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.showRestEndToast = false
        }
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

    func updateScheduleCycleCount(_ val: Int) {
        scheduleCycleCount = max(1, min(31, val))
        defaults.set(scheduleCycleCount, forKey: "scheduleCycleCount")
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
        loadDailyStats()
        guard let savedDeadline = deadline, phase != .idle else {
            loadDailyStats()
            return
        }
        let now = Date()
        if savedDeadline > now {
            timeRemaining = savedDeadline.timeIntervalSince(now)
            if isRunning { startTicking() }
        } else {
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
        let restDuration = TimeInterval(restSeconds)
        if overshoot >= restDuration {
            saveDailyStats()
            let duration = TimeInterval(workMinutes * 60)
            deadline = Date().addingTimeInterval(duration)
            totalTime = duration
            timeRemaining = duration
            phase = .working
            isRunning = true
            saveTimerState()
            scheduleNotificationChain()
            startTicking()
        } else {
            let remaining = restDuration - overshoot
            deadline = Date().addingTimeInterval(remaining)
            totalTime = restDuration
            timeRemaining = remaining
            phase = .resting
            showOverlay = true
            healthTip = healthTips.randomElement() ?? ""
            isRunning = true
            saveTimerState()
            scheduleNotificationChain()
            startTicking()
        }
    }

    private func handleRestExpiredInBackground(overshoot: TimeInterval) {
        saveDailyStats()
        let duration = TimeInterval(workMinutes * 60)
        deadline = Date().addingTimeInterval(duration)
        totalTime = duration
        timeRemaining = duration
        phase = .working
        showOverlay = false
        isRunning = true
        saveTimerState()
        scheduleNotificationChain()
        startTicking()
    }

    private func startTicking() {
        stopTicking()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self, let deadline = self.deadline else { return }
            let remaining = max(0, deadline.timeIntervalSinceNow)
            DispatchQueue.main.async { self.timeRemaining = remaining }
            if remaining <= 0 {
                DispatchQueue.main.async {
                    self.stopTicking()
                    self.completePhase()
                }
            }
        }
    }

    private func stopTicking() { tickTimer?.invalidate(); tickTimer = nil }

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
            scheduleNotificationChain()
            startTicking()
            screenFlash = true
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.screenFlash = false
            }
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
            scheduleNotificationChain()
            startTicking()
            showRestEndToast = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.showRestEndToast = false
            }
        }
    }

    // MARK: - Notifications (dual: rest-start + rest-end)

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Schedule chained notifications for the current and future cycles.
    /// This enables auto-loop in the background without the app being opened.
    private func scheduleNotificationChain() {
        cancelAllTimerNotifications()

        let work = TimeInterval(workMinutes * 60)
        let rest = TimeInterval(restSeconds)
        let cycle = work + rest

        var offset: TimeInterval = 0

        switch phase {
        case .working:
            offset = max(1, timeRemaining)
            // Current work → rest
            scheduleOne(id: "eye20-rest-start-0", title: "该休息了！",
                        body: "看远处 \(restSeconds) 秒，放松眼睛", sound: "alert.wav", after: offset)
            scheduleOne(id: "eye20-rest-end-0", title: "休息结束",
                        body: "继续工作吧！", sound: "complete.wav", after: offset + rest)
            offset += cycle
        case .resting:
            offset = max(1, timeRemaining)
            // Current rest end
            scheduleOne(id: "eye20-rest-end-0", title: "休息结束",
                        body: "继续工作吧！", sound: "complete.wav", after: offset)
            offset += work
        case .idle:
            return
        }

        // Future cycles
        for i in 1 ... scheduleCycleCount {
            scheduleOne(id: "eye20-rest-start-\(i)", title: "该休息了！",
                        body: "看远处 \(restSeconds) 秒，放松眼睛", sound: "alert.wav", after: offset)
            scheduleOne(id: "eye20-rest-end-\(i)", title: "休息结束",
                        body: "继续工作吧！", sound: "complete.wav", after: offset + rest)
            offset += cycle
        }
    }

    private func scheduleOne(id: String, title: String, body: String, sound: String, after: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = UNNotificationSound(named: UNNotificationSoundName(sound))
        let req = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: after, repeats: false)
        )
        UNUserNotificationCenter.current().add(req)
    }

    private func cancelAllTimerNotifications() {
        var ids: [String] = []
        for i in 0 ... 31 {
            ids.append("eye20-rest-start-\(i)")
            ids.append("eye20-rest-end-\(i)")
        }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: - Persistence

    private func saveTimerState() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(phase.rawValue) {
            defaults.set(data, forKey: "timerPhase")
        }
        if let deadline { defaults.set(deadline.timeIntervalSince1970, forKey: "timerDeadline") }
        defaults.set(isRunning, forKey: "timerIsRunning")
        defaults.set(showOverlay, forKey: "timerShowOverlay")
        if !healthTip.isEmpty { defaults.set(healthTip, forKey: "timerHealthTip") }
    }

    private func loadTimerState() {
        if let data = defaults.data(forKey: "timerPhase"),
           let raw = try? JSONDecoder().decode(String.self, from: data),
           let savedPhase = Phase(rawValue: raw) {
            phase = savedPhase
        }
        let sd = defaults.double(forKey: "timerDeadline")
        if sd > 0 { deadline = Date(timeIntervalSince1970: sd) }
        isRunning = defaults.bool(forKey: "timerIsRunning")
        showOverlay = defaults.bool(forKey: "timerShowOverlay")
        healthTip = defaults.string(forKey: "timerHealthTip") ?? ""
    }

    private func clearTimerState() {
        ["timerPhase","timerDeadline","timerIsRunning","timerShowOverlay","timerHealthTip"]
            .forEach { defaults.removeObject(forKey: $0) }
    }

    private func loadSettings() {
        workMinutes = defaults.integer(forKey: "workMinutes")
        if workMinutes == 0 { workMinutes = 20 }
        restSeconds = defaults.integer(forKey: "restSeconds")
        if restSeconds == 0 { restSeconds = 20 }
        darkMode = defaults.bool(forKey: "darkMode")
        scheduleCycleCount = defaults.integer(forKey: "scheduleCycleCount")
        if scheduleCycleCount == 0 { scheduleCycleCount = 15 }
        loadTimerState()
        if phase != .idle, let deadline {
            let remaining = deadline.timeIntervalSince(Date())
            if remaining > 0 {
                timeRemaining = remaining
                totalTime = phase == .working
                    ? TimeInterval(workMinutes * 60)
                    : TimeInterval(restSeconds)
                if isRunning { startTicking() }
            } else {
                reset()
            }
        } else {
            timeRemaining = TimeInterval(workMinutes * 60)
            totalTime = TimeInterval(workMinutes * 60)
        }
    }

    private func saveDailyStats() {
        defaults.set(todayCycles, forKey: "cycles_\(todayKey)")
    }

    private func loadDailyStats() {
        todayCycles = defaults.integer(forKey: "cycles_\(todayKey)")
    }

    private var todayKey: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}
