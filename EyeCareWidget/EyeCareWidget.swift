import WidgetKit
import SwiftUI
import ActivityKit

@main
@main
struct EyeCareWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: EyeCareAttributes.self) { context in
            LockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("🌿", systemImage: "eye")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timeString(from: context.state.timeRemaining))
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.state.phase == "working" ? "专注中" : "休息中")
                            .font(.subheadline)
                        Spacer()
                        if context.state.cycleNumber > 0 {
                            Text("第 \(context.state.cycleNumber)/\(context.state.maxCycles) 轮")
                                .font(.caption)
                        }
                    }
                }
            } compactLeading: {
                Text("🌿").font(.system(size: 14))
            } compactTrailing: {
                Text(timeString(from: context.state.timeRemaining))
                    .font(.system(size: 14, weight: .bold))
                    .monospacedDigit()
            } minimal: {
                Text("🌿").font(.system(size: 14))
            }
        }
    }

    private func timeString(from seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

struct LockScreenView: View {
    let context: ActivityViewContext<EyeCareAttributes>

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("🌿")
                    Text(context.state.phase == "working" ? "专注中" : "休息中")
                        .font(.headline)
                }
                Text(timeString(from: context.state.timeRemaining))
                    .font(.system(size: 40, weight: .bold, design: .monospaced))
                    .foregroundColor(context.state.phase == "resting" ? .green : .blue)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if context.state.cycleNumber > 0 {
                    Text("第 \(context.state.cycleNumber)/\(context.state.maxCycles) 轮")
                        .font(.caption)
                }
                Text("专注 \(context.state.focusMinutes) 分")
                    .font(.caption)
            }
            .foregroundColor(.secondary)
        }
        .padding()
        .activityBackgroundTint(Color.black.opacity(0.2))
    }

    private func timeString(from seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
