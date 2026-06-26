import SwiftUI

struct ContentView: View {
    @EnvironmentObject var tm: TimerManager

    var body: some View {
        ZStack {
            (tm.darkMode ? Color(.systemBackground) : Color(.systemGroupedBackground))
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HeaderView()
                Spacer()
                TimerView()
                Spacer()
                ControlsView()
                StatsView()
                Spacer().frame(height: 8)
                SettingsToggleView()
            }

            // Screen flash on rest start
            if tm.screenFlash {
                Color.green.opacity(0.25)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .animation(.easeOut(duration: 0.4), value: tm.screenFlash)
            }

            // Rest overlay
            if tm.showOverlay {
                RestOverlayView()
            }

            // Rest end toast
            if tm.showRestEndToast {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("休息结束，继续工作")
                            .font(.subheadline.weight(.medium))
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.regularMaterial)
                    .clipShape(.capsule)
                    .shadow(radius: 8)
                    .padding(.bottom, 100)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .animation(.spring(duration: 0.4), value: tm.showRestEndToast)
            }
        }
        .preferredColorScheme(tm.darkMode ? .dark : .light)
    }
}

struct HeaderView: View {
    @EnvironmentObject var tm: TimerManager

    var body: some View {
        HStack {
            Text("20-20-20")
                .font(.title.weight(.bold))
            Spacer()
            Button {
                tm.darkMode.toggle()
            } label: {
                Image(systemName: tm.darkMode ? "sun.max.fill" : "moon.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.secondary)
                    .frame(width: 36, height: 36)
                    .background(.regularMaterial, in: .circle)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
}

struct TimerView: View {
    @EnvironmentObject var tm: TimerManager

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                CircularProgressView(progress: tm.progress, isRest: tm.phase == .resting)
                    .frame(width: 220, height: 220)

                VStack(spacing: 4) {
                    Text(timeString(from: tm.timeRemaining))
                        .font(.system(size: 48, weight: .bold, design: .monospaced))
                        .contentTransition(.numericText())
                    Text(label)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            if tm.todayCycles > 0 {
                Text("第 \(tm.todayCycles) 轮")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var label: String {
        switch tm.phase {
        case .idle: return "准备开始"
        case .working: return "专注中"
        case .resting: return "休息中"
        }
    }

    private func timeString(from t: TimeInterval) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%02d:%02d", m, s)
    }
}

struct CircularProgressView: View {
    let progress: Double
    let isRest: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: 8)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(isRest ? Color.green : Color.blue, style: .init(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.2), value: progress)
        }
        .padding(4)
    }
}

struct ControlsView: View {
    @EnvironmentObject var tm: TimerManager

    var body: some View {
        VStack(spacing: 12) {
            Button(action: mainAction) {
                Text(mainLabel)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 48)
                    .padding(.vertical, 14)
                    .background(tm.phase == .resting ? Color.green : Color.blue)
                    .clipShape(.capsule)
                    .shadow(color: (tm.phase == .resting ? Color.green : Color.blue).opacity(0.3),
                            radius: 8, y: 4)
            }

            HStack(spacing: 16) {
                Button("重置") { withAnimation { tm.reset() } }
                    .buttonStyle(.bordered)
                    .tint(.secondary)

                if tm.phase == .resting {
                    Button("跳过休息") { withAnimation { tm.skipRest() } }
                        .buttonStyle(.bordered)
                        .tint(.green)
                }
            }
            .font(.subheadline)
        }
    }

    private var mainLabel: String {
        switch tm.phase {
        case .idle: return "开始"
        case .working: return tm.isRunning ? "暂停" : "继续"
        case .resting: return "跳过休息"
        }
    }

    private func mainAction() {
        switch tm.phase {
        case .idle: tm.startWorking()
        case .working:
            if tm.isRunning { tm.pause() }
            else { tm.resume() }
        case .resting: tm.skipRest()
        }
    }
}

struct StatsView: View {
    @EnvironmentObject var tm: TimerManager

    var body: some View {
        HStack(spacing: 0) {
            StatItem(value: "\(tm.todayCycles)", label: "今日已完成轮数")
            Divider().frame(height: 32).padding(.vertical, 8)
            StatItem(value: "\(tm.todayCycles * tm.currentWorkMinutes)", label: "今日专注(分钟)")
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }
}

struct StatItem: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.weight(.bold))
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct SettingsToggleView: View {
    @EnvironmentObject var tm: TimerManager
    @State private var expanded = false

    var body: some View {
        VStack(spacing: 10) {
            Button {
                withAnimation(.spring(duration: 0.3)) { expanded.toggle() }
            } label: {
                HStack {
                    Image(systemName: "gearshape.fill").font(.caption)
                    Text("设置")
                    Text(expanded ? "▲" : "▼").font(.caption2)
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.vertical, 8)
                .padding(.horizontal, 20)
                .background(.regularMaterial, in: .capsule)
            }

            if expanded {
                VStack(spacing: 16) {
                    SettingsRow(label: "工作时长") {
                        Picker("", selection: Binding(
                            get: { tm.currentWorkMinutes },
                            set: { tm.updateWorkMinutes($0); if tm.phase == .idle { tm.reset() } }
                        )) {
                            ForEach(Array(stride(from: 1, through: 120, by: 1)), id: \.self) { i in
                                Text("\(i) 分钟").tag(i)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    SettingsRow(label: "休息时长") {
                        Picker("", selection: Binding(
                            get: { tm.currentRestSeconds },
                            set: { tm.updateRestSeconds($0) }
                        )) {
                            ForEach([5, 10, 15, 20, 25, 30, 45, 60, 90, 120], id: \.self) { s in
                                Text("\(s) 秒").tag(s)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
                .padding(16)
                .background(.regularMaterial, in: .rect(cornerRadius: 16))
                .padding(.horizontal, 24)
            }
        }
        .padding(.bottom, 24)
    }
}

struct SettingsRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack {
            Text(label).font(.subheadline)
            Spacer()
            content
        }
    }
}

struct RestOverlayView: View {
    @EnvironmentObject var tm: TimerManager
    @State private var opacity: Double = 0
    @State private var scale: CGFloat = 0.8

    var body: some View {
        ZStack {
            Color.green.opacity(0.95)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Text("🌿")
                    .font(.system(size: 60))

                Text("该休息了！")
                    .font(.title.weight(.bold))
                    .foregroundColor(.white)

                Text("\(Int(tm.timeRemaining))")
                    .font(.system(size: 96, weight: .heavy, design: .monospaced))
                    .foregroundColor(.white)
                    .scaleEffect(scale)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                            scale = 1.15
                        }
                    }

                Text(tm.healthTip)
                    .font(.body)
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                Button("跳过休息") {
                    withAnimation { tm.skipRest() }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .clipShape(.capsule)
                .foregroundColor(.white)
                .font(.subheadline.weight(.semibold))
            }
        }
        .opacity(opacity)
        .onAppear {
            withAnimation(.easeOut(duration: 0.15)) { opacity = 1 }
        }
    }
}
