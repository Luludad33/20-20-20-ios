import ActivityKit
import Foundation

struct EyeCareAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var phase: String
        var timeRemaining: Int
        var cycleNumber: Int
        var maxCycles: Int
        var focusMinutes: Int
    }
}
