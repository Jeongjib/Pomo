import SwiftUI

extension Notification.Name {
    static let requestOpenSettings = Notification.Name("requestOpenSettings")
}

/// On launch, if onboarding hasn't been completed, post a notification
/// so the MenuBarLabel can openWindow(id: "settings").
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApp.activate(ignoringOtherApps: true)
                NotificationCenter.default.post(name: .requestOpenSettings, object: nil)
            }
        }
    }
}

@main
struct HeadPosePoCApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var camera: CameraManager
    @StateObject private var pomodoro: PomodoroManager

    init() {
        let p = PomodoroManager()
        let c = CameraManager()
        c.attachPomodoro(p)

        // Returning users who already completed onboarding → start in ready state
        c.isReady = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")

        _camera = StateObject(wrappedValue: c)
        _pomodoro = StateObject(wrappedValue: p)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(camera)
                .environmentObject(pomodoro)
        } label: {
            MenuBarLabel(pomodoro: pomodoro, camera: camera)
        }
        .menuBarExtraStyle(.window)

        Window("Pomo Settings", id: "settings") {
            ContentView()
                .environmentObject(camera)
        }
        .windowResizability(.contentSize)
    }
}

struct MenuBarLabel: View {
    @ObservedObject var pomodoro: PomodoroManager
    @ObservedObject var camera: CameraManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .requestOpenSettings)) { _ in
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            }
    }

    @ViewBuilder
    private var content: some View {
        if camera.isUserAway {
            Text("🍅 💤")
        } else if pomodoro.isRunning {
            Text(pomodoro.label)
        } else {
            Text("🍅")
        }
    }
}

struct MenuBarView: View {
    @EnvironmentObject var camera: CameraManager
    @EnvironmentObject var pomodoro: PomodoroManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Pomodoro section (primary)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(pomodoro.phase == .work ? "🍅 Focus" : "☕️ Break")
                        .font(.headline)
                    if camera.isUserAway {
                        Text("· 자리 비움")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    Spacer()
                    Text(pomodoro.label)
                        .font(.system(.title3, design: .monospaced))
                        .foregroundColor(pomodoro.phase == .work ? .primary : .green)
                }

                HStack(spacing: 8) {
                    Button {
                        pomodoro.isRunning ? pomodoro.pause() : pomodoro.start()
                    } label: {
                        Label(pomodoro.isRunning ? "일시정지" : "시작",
                              systemImage: pomodoro.isRunning ? "pause.fill" : "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    Button {
                        pomodoro.skipPhase()
                    } label: {
                        Label("건너뛰기", systemImage: "forward.fill")
                            .frame(maxWidth: .infinity)
                    }
                }
            }

            Divider()

            // Hidden-ish: motion detection status
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("감지 활성화", isOn: $camera.isEnabled)
                        .toggleStyle(.switch)
                        .font(.caption)

                    HStack {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                        Text(statusText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("발동 \(camera.triggerCount)회")
                            .font(.caption)
                            .foregroundColor(camera.triggerCount > 0 ? .red : .secondary)
                    }

                    if camera.isEnabled && camera.faceDetected {
                        Text(String(format: "yaw %+.1f°", camera.yaw))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 4)
            } label: {
                Text("고급 설정")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            Button {
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("설정 열기", systemImage: "gear")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("종료", systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q")
        }
        .padding()
        .frame(width: 260)
    }

    private var statusColor: Color {
        if !camera.isEnabled { return .gray }
        return camera.faceDetected ? .green : .orange
    }

    private var statusText: String {
        if !camera.isEnabled { return "감지 정지" }
        return camera.faceDetected ? "감지 중" : "얼굴 찾는 중"
    }
}
