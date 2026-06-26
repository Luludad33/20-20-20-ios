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
    private var lastActiveDate: Date?
    private let defaults = UserDefaults.standard

    init() {
        requestNotificationPermission()
        loadSettings()
        loadDailyStats()
        // If deadline is already past at launch, recover state
        if phase != .idle, let deadline, deadline < Date() {
            recoverFromBackground()
        }
    }

    // MARK: - Lifecycle (called from App.swift)

    func handleScenePhaseChange(to newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            if phase != .idle {
                if let deadline, deadline < Date() {
                    // Deadline passed while away — recover full state
                    recoverFromBackground()
                } else if isRunning {
                    // Still within current phase — resume ticking
                    startTicking()
                }
                scheduleNextNotifications()
            }
            lastActiveDate = Date()

        case .background:
            lastActiveDate = Date()
            saveLastActiveDate()
            if phase != .idle {
                saveTimerState()
                saveDailyStats()
            }
            stopTicking()

        case .inactive:
            break
        @unknown default:
            break
        }
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
        lastActiveDate = Date()
        saveLastActiveDate()
        saveTimerState()
        scheduleNextNotifications()
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
        scheduleNextNotifications()
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
        lastActiveDate = Date()
        saveLastActiveDate()
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
        scheduleNextNotifications()
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

    var currentWorkMinutes: Int { workMinutes }
    var currentRestSeconds: Int { restSeconds }

    // MARK: - Background recovery

    /// Recover app state after being in background.
    /// Calculates elapsed time since `lastActiveDate` and advances through
    /// completed work/rest cycles, so the internal state is always correct
    /// regardless of how long the app was away.
    private func recoverFromBackground() {
        guard let savedDeadline = deadline, let lastActive = lastActiveDate, lastActive < Date() else {
            // No reference point — if deadline is past, reset safely
            if let deadline, deadline < Date() { reset() }
            return
        }

        let now = Date()
        let work = TimeInterval(workMinutes * 60)
        let rest = TimeInterval(restSeconds)
        let cycle = work + rest

        // How much time passed since we were last active
        let elapsed = now.timeIntervalSince(lastActive)

        // How much time was remaining in the current phase at lastActive
        let remainingAtLastActive = max(0, savedDeadline.timeIntervalSince(lastActive))

        if elapsed < remainingAtLastActive {
            // Still in the same phase
            timeRemaining = remainingAtLastActive - elapsed
            totalTime = phase == .working ? work : rest
            return
        }

        // Current phase ended while we were away
        var t = elapsed - remainingAtLastActive  // time since phase ended

        if phase == .working {
            // Work ended → 1 cycle completed
            todayCycles += 1

            if t < rest {
                // Still inside the rest period
                let remaining = rest - t
                phase = .resting
                deadline = Date().addingTimeInterval(remaining)
                timeRemaining = remaining
                totalTime = rest
                showOverlay = true
                healthTip = healthTips.randomElement() ?? ""
                isRunning = true
                saveTimerState()
                saveDailyStats()
                return
            }
            t -= rest
        } else {
            // Rest ended (was .resting) → 1 cycle completed
            todayCycles += 1
        }

        // Advance through any full cycles that elapsed
        let fullCycles = Int(t / cycle)
        if fullCycles > 0 {
            todayCycles += fullCycles
            t -= Double(fullCycles) * cycle
        }

        // Now t < cycle — determine current phase
        if t < work {
            // In work block
            phase = .working
            timeRemaining = work - t
            totalTime = work
            showOverlay = false
        } else {
            // In rest block
            t -= work
            phase = .resting
            timeRemaining = rest - t
            totalTime = rest
            showOverlay = true
            healthTip = healthTips.randomElement() ?? ""
        }

        deadline = Date().addingTimeInterval(timeRemaining)
        isRunning = true
        saveTimerState()
        saveDailyStats()
        // Prevent double-advance if recoverFromBackground is called again
        lastActiveDate = Date()
        saveLastActiveDate()
    }

    // MARK: - Timer

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
            scheduleNextNotifications()
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
            scheduleNextNotifications()
            startTicking()
            showRestEndToast = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.showRestEndToast = false
            }
        }
    }

    // MARK: - Notifications

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Schedule only the NEXT pair of notifications (single cycle).
    /// No chain — the system fires these at the right absolute time,
    /// and on next foreground we recalculate from lastActiveDate.
    private func scheduleNextNotifications() {
        cancelAllTimerNotifications()

        guard let deadline, deadline > Date() else { return }
        let now = Date()

        switch phase {
        case .working:
            let workRemaining = max(1, deadline.timeIntervalSince(now))
            let restDur = TimeInterval(restSeconds)
            scheduleOne(id: "eye20-rest-start",
                        title: "该休息了！",
                        body: "看远处 \(restSeconds) 秒，放松眼睛",
                        sound: "alert.wav", after: workRemaining)
            scheduleOne(id: "eye20-rest-end",
                        title: "休息结束",
                        body: "继续工作吧！第 \(todayCycles + 1) 轮完成",
                        sound: "complete.wav", after: workRemaining + restDur)

        case .resting:
            let restRemaining = max(1, deadline.timeIntervalSince(now))
            scheduleOne(id: "eye20-rest-end",
                        title: "休息结束",
                        body: "继续工作吧！第 \(todayCycles) 轮完成",
                        sound: "complete.wav", after: restRemaining)

        case .idle:
            break
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
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(
                withIdentifiers: ["eye20-rest-start", "eye20-rest-end"])
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

    private func saveLastActiveDate() {
        if let date = lastActiveDate {
            defaults.set(date.timeIntervalSince1970, forKey: "lastActiveDate")
        }
    }

    private func loadLastActiveDate() {
        let ts = defaults.double(forKey: "lastActiveDate")
        if ts > 0 {
            lastActiveDate = Date(timeIntervalSince1970: ts)
        }
    }

    private func loadSettings() {
        workMinutes = defaults.integer(forKey: "workMinutes")
        if workMinutes == 0 { workMinutes = 20 }
        restSeconds = defaults.integer(forKey: "restSeconds")
        if restSeconds == 0 { restSeconds = 20 }
        darkMode = defaults.bool(forKey: "darkMode")

        loadTimerState()
        loadLastActiveDate()

        if phase != .idle, let deadline {
            let remaining = deadline.timeIntervalSince(Date())
            if remaining > 0 {
                timeRemaining = remaining
                totalTime = phase == .working
                    ? TimeInterval(workMinutes * 60)
                    : TimeInterval(restSeconds)
                if isRunning { startTicking() }
            }
            // Deadline ≤ 0 → handled by init() calling recoverFromBackground()
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
