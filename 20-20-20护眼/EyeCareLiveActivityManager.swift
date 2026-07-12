import ActivityKit
import Foundation

@MainActor
class EyeCareLiveActivityManager {
    static let shared = EyeCareLiveActivityManager()
    private var activity: Activity<EyeCareAttributes>?
    private var lastUpdateTime: Date = .distantPast
    private let updateInterval: TimeInterval = 4

    func startOrUpdate(phase: String, timeRemaining: Int, cycleNumber: Int, maxCycles: Int, focusMinutes: Int) {
        guard phase != "idle" else { end(); return }
        let now = Date()
        if activity != nil, now.timeIntervalSince(lastUpdateTime) < updateInterval { return }
        lastUpdateTime = now

        let state = EyeCareAttributes.ContentState(
            phase: phase,
            timeRemaining: timeRemaining,
            cycleNumber: cycleNumber,
            maxCycles: maxCycles,
            focusMinutes: focusMinutes
        )
        let content = ActivityContent(state: state, staleDate: nil)

        if let activity {
            Task { await activity.update(content) }
        } else {
            let attr = EyeCareAttributes()
            do {
                activity = try Activity.request(attributes: attr, content: content, pushType: nil)
            } catch {
                print("Live Activity start failed: \(error)")
            }
        }
    }

    func end() {
        Task {
            await activity?.end(dismissalPolicy: .immediate)
            activity = nil
        }
        lastUpdateTime = .distantPast
    }
}
