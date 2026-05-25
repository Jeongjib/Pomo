import SwiftUI
import AVFoundation
import Vision
import Combine
import AppKit
import UserNotifications
import UniformTypeIdentifiers

struct TriggerEvent: Identifiable {
    let id = UUID()
    let timestamp: Date
    let yaw: Double
    let baseline: Double
    let reason: String
}

struct SafePosition: Identifiable {
    let id = UUID()
    let yaw: Double
    let createdAt: Date
}

struct SensitiveApp: Identifiable, Hashable {
    let id = UUID()
    let bundleId: String
    let name: String
}

struct ContentView: View {
    @EnvironmentObject var camera: CameraManager
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        if hasCompletedOnboarding {
            mainView
        } else {
            OnboardingView()
        }
    }

    private var mainView: some View {
        ScrollView {
            VStack(spacing: 12) {
                CameraPreview(session: camera.session)
                    .frame(height: 180)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(camera.triggerFlash ? Color.red : Color.clear, lineWidth: 8)
                            .animation(.easeOut(duration: 0.4), value: camera.triggerFlash)
                    )

                liveStatusPanel
                safeRangePanel
                sensitiveAppsPanel
                triggerPanel
                advancedPanel
            }
            .padding()
        }
        .frame(minWidth: 620, minHeight: 720)
    }

    private var advancedPanel: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    hasCompletedOnboarding = false
                    camera.isReady = false
                } label: {
                    Label("온보딩 다시 보기", systemImage: "arrow.counterclockwise")
                }
                .controlSize(.small)
                Text("이 버튼을 누르면 첫 실행 시 봤던 안내 화면이 다시 나옵니다. 등록된 safe 범위와 민감 앱은 유지됩니다.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text("고급")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .padding(.bottom, 4)
    }

    // MARK: - Panels

    private var liveStatusPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(camera.faceDetected ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
                Text(camera.faceDetected ? "Face detected" : "No face")
                    .font(.subheadline)
                Spacer()
                if camera.baselineReady {
                    Text(String(format: "baseline %+.1f°", camera.baselineYaw))
                        .font(.caption).foregroundColor(.secondary)
                } else {
                    Text("baseline: calibrating…")
                        .font(.caption).foregroundColor(.orange)
                }
            }
            Text(String(format: "yaw %+6.1f°   pitch %+6.1f°   roll %+6.1f°",
                        camera.yaw, camera.pitch, camera.roll))
        }
        .font(.system(.body, design: .monospaced))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.gray.opacity(0.12))
        .cornerRadius(8)
    }

    private var safeRangePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("✅ Safe range (등록한 점들 사이 + 여유 ±10°)")
                    .font(.headline)
                Spacer()
                Button(action: { camera.saveCurrentAsSafe() }) {
                    Label("현재 위치 추가", systemImage: "plus.circle.fill")
                }
                .disabled(!camera.faceDetected)
            }

            if camera.safePositions.isEmpty {
                Text("등록된 점 없음 — 모니터 시야의 양쪽 끝을 등록하세요. 예: 외장 모니터 오른쪽 끝 → 노트북 왼쪽 끝.")
                    .font(.caption).foregroundColor(.secondary)
            } else {
                if camera.safePositions.count >= 2,
                   let lo = camera.safeRangeLow, let hi = camera.safeRangeHigh {
                    Text(String(format: "현재 안전 범위: [%+.1f°, %+.1f°]", lo, hi))
                        .font(.caption).foregroundColor(.green)
                } else {
                    Text("⚠️ 1개만 등록됨 — 반대편 끝도 등록해야 범위가 완성됩니다")
                        .font(.caption).foregroundColor(.orange)
                }
                HStack(spacing: 8) {
                    ForEach(camera.safePositions) { pos in
                        HStack(spacing: 4) {
                            Text(String(format: "%+.1f°", pos.yaw))
                                .font(.system(.caption, design: .monospaced))
                            Button(action: { camera.removeSafe(pos.id) }) {
                                Image(systemName: "xmark.circle.fill").font(.caption)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.green.opacity(0.2))
                        .cornerRadius(6)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.green.opacity(0.06))
        .cornerRadius(8)
    }

    private var sensitiveAppsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("🙈 민감 앱 (트리거 발동 시 hide)")
                    .font(.headline)
                Spacer()
                Button(action: { camera.pickSensitiveApp() }) {
                    Label("앱 추가", systemImage: "plus.circle.fill")
                }
            }

            if camera.sensitiveApps.isEmpty {
                Text("등록된 앱 없음 — '앱 추가' 눌러서 /Applications에서 카톡, 슬랙 등을 선택하세요.")
                    .font(.caption).foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(camera.sensitiveApps) { app in
                        HStack {
                            Image(systemName: "app.dashed")
                            VStack(alignment: .leading, spacing: 1) {
                                Text(app.name).font(.body)
                                Text(app.bundleId).font(.caption2).foregroundColor(.secondary)
                            }
                            Spacer()
                            Button(action: { camera.removeSensitiveApp(app.id) }) {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.orange.opacity(0.15))
                        .cornerRadius(6)
                    }
                }
            }

            Button(action: { camera.testHideNow() }) {
                Label("Test: 지금 hide + 알림 발사", systemImage: "play.circle")
            }
            .disabled(camera.sensitiveApps.isEmpty)
            .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.orange.opacity(0.06))
        .cornerRadius(8)
    }

    private var triggerPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("🎯 Triggers fired: \(camera.triggerCount)")
                    .font(.title3)
                    .foregroundColor(camera.triggerCount > 0 ? .red : .primary)
                Spacer()
                Button("Reset") { camera.resetTriggers() }
            }

            Text("규칙: safe range 2개 이상 → 범위 밖으로 나가면 발동. 미등록 시 → |yaw − baseline| > 25°. Cooldown 5초.")
                .font(.caption).foregroundColor(.secondary)

            if !camera.recentTriggers.isEmpty {
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(camera.recentTriggers.reversed()) { ev in
                            Text("\(formatTime(ev.timestamp))  · \(ev.reason)  · yaw \(String(format: "%+.1f", ev.yaw))° vs baseline \(String(format: "%+.1f", ev.baseline))°")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
            }
        }
        .padding()
        .background(Color.blue.opacity(0.08))
        .cornerRadius(8)
    }

    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SS"
        return f.string(from: date)
    }
}

// MARK: - Onboarding

struct OnboardingView: View {
    @EnvironmentObject var camera: CameraManager
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var step = 0  // 0: welcome · 1: safe range · 2: apps · 3: notifications · 4: done
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        VStack(spacing: 0) {
            // Progress dots
            HStack(spacing: 8) {
                ForEach(0..<5) { i in
                    Circle()
                        .fill(i <= step ? Color.accentColor : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 20)

            Group {
                switch step {
                case 0: welcomeStep
                case 1: safeRangeStep
                case 2: appsStep
                case 3: notificationStep
                default: doneStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Footer
            HStack {
                if step > 0 && step < 4 {
                    Button("이전") { step -= 1 }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                }
                Spacer()
                navigationButton
            }
            .padding()
        }
        .frame(minWidth: 540, minHeight: 600)
    }

    @ViewBuilder
    private var navigationButton: some View {
        switch step {
        case 0:
            Button("시작하기") { step += 1 }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        case 1:
            Button(camera.safePositions.count >= 2 ? "다음" : "다음 (최소 2개 등록)") { step += 1 }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(camera.safePositions.count < 2)
        case 2:
            HStack(spacing: 8) {
                Button("건너뛰기") { step += 1 }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                Button("다음") { step += 1 }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        case 3:
            Button("다음") { step += 1 }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        default:
            Button("완료") {
                hasCompletedOnboarding = true
                camera.isReady = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private func checkNotificationStatus() {
        NotificationManager.shared.checkPermissionStatus { status in
            notificationStatus = status
        }
    }

    // MARK: Steps

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("🍅")
                .font(.system(size: 80))
            Text("Pomo에 오신 걸 환영합니다")
                .font(.title).bold()
            Text("50분 집중 / 10분 휴식 뽀모도로 타이머.\n카메라로 자리 비움을 자동 감지해\n타이머를 알아서 일시정지하고\n자리를 비우면 스크린 세이버까지 띄워줍니다.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .lineSpacing(4)
            Spacer()
        }
        .padding(.horizontal, 40)
    }

    private var safeRangeStep: some View {
        VStack(spacing: 14) {
            Text("1. 안전 시야 범위 등록")
                .font(.title2).bold()
            Text("평소 보시는 모니터의 양쪽 끝을 차례로 등록해주세요.\n이 범위 안 어디를 보든 정상으로 인식합니다.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .font(.subheadline)

            CameraPreview(session: camera.session)
                .frame(height: 160)
                .cornerRadius(8)

            HStack {
                Circle()
                    .fill(camera.faceDetected ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
                Text(camera.faceDetected ? "얼굴 감지됨" : "얼굴이 안 보여요")
                    .font(.subheadline)
                Spacer()
                Text(String(format: "현재 yaw: %+.1f°", camera.yaw))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Button {
                camera.saveCurrentAsSafe()
            } label: {
                Label("현재 위치 등록", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .disabled(!camera.faceDetected)
            .controlSize(.large)

            if !camera.safePositions.isEmpty {
                HStack(spacing: 8) {
                    ForEach(camera.safePositions) { pos in
                        HStack(spacing: 4) {
                            Text(String(format: "%+.1f°", pos.yaw))
                                .font(.system(.caption, design: .monospaced))
                            Button {
                                camera.removeSafe(pos.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill").font(.caption)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.green.opacity(0.2))
                        .cornerRadius(6)
                    }
                }
            }

            Group {
                if camera.safePositions.isEmpty {
                    Text("💡 예: 외장 모니터의 가장 오른쪽 끝을 보면서 '등록' → 노트북 화면의 가장 왼쪽 끝을 보면서 '등록'")
                } else if camera.safePositions.count == 1 {
                    Text("✓ 1개 등록됨. 반대편 끝도 등록해주세요.")
                        .foregroundColor(.orange)
                } else if let lo = camera.safeRangeLow, let hi = camera.safeRangeHigh {
                    Text(String(format: "✓ 안전 범위 완성: [%+.1f°, %+.1f°]", lo, hi))
                        .foregroundColor(.green)
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)

            Spacer()
        }
        .padding(.horizontal, 32)
    }

    private var appsStep: some View {
        VStack(spacing: 14) {
            Text("2. 숨길 앱 등록")
                .font(.title2).bold()
            Text("자리에서 누군가 다가오는 게 감지되면\n자동으로 숨겨질 앱을 골라주세요.\n카톡, 슬랙, 개인 브라우저 등 (선택사항)")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .font(.subheadline)

            Button {
                camera.pickSensitiveApp()
            } label: {
                Label("앱 추가", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)

            if camera.sensitiveApps.isEmpty {
                Text("아직 등록된 앱 없음 — 그대로 건너뛰셔도 돼요. 나중에 설정에서 추가 가능.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(camera.sensitiveApps) { app in
                            HStack {
                                Image(systemName: "app.dashed")
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(app.name)
                                    Text(app.bundleId)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Button {
                                    camera.removeSensitiveApp(app.id)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .background(Color.orange.opacity(0.15))
                            .cornerRadius(6)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }

            Spacer()
        }
        .padding(.horizontal, 32)
    }

    private var notificationStep: some View {
        VStack(spacing: 14) {
            Text("3. 알림 권한")
                .font(.title2).bold()
            Text("뽀모도로 사이클 전환 시 알림을 보내드려요.\n예: \"쉬는 시간 종료, 업무로 복귀할 시간이에요\"")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .font(.subheadline)

            Spacer().frame(height: 8)

            Image(systemName: statusIconName)
                .font(.system(size: 60))
                .foregroundColor(statusIconColor)

            Text(statusDescription)
                .font(.headline)
                .foregroundColor(statusIconColor)

            if notificationStatus == .notDetermined {
                Button {
                    NotificationManager.shared.requestPermission { _ in
                        checkNotificationStatus()
                    }
                } label: {
                    Label("알림 허용 요청", systemImage: "bell.fill")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
            } else if notificationStatus == .denied {
                VStack(spacing: 6) {
                    Text("시스템 설정 → 알림 → Pomo 에서 켤 수 있어요")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Label("시스템 설정 열기", systemImage: "gearshape")
                    }
                    .controlSize(.small)
                }
                .padding(.top, 4)
            }

            Text("알림 없이도 앱 자체는 정상 작동합니다.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.top, 8)

            Spacer()
        }
        .padding(.horizontal, 32)
        .onAppear { checkNotificationStatus() }
    }

    private var statusIconName: String {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral: return "checkmark.circle.fill"
        case .denied: return "xmark.circle.fill"
        default: return "bell.circle"
        }
    }

    private var statusIconColor: Color {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral: return .green
        case .denied: return .orange
        default: return .secondary
        }
    }

    private var statusDescription: String {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral: return "알림 허용됨"
        case .denied: return "알림 거부됨"
        default: return "아직 요청하지 않음"
        }
    }

    private var doneStep: some View {
        VStack(spacing: 18) {
            Spacer()
            Text("🎉")
                .font(.system(size: 80))
            Text("준비 완료!")
                .font(.title).bold()
            VStack(alignment: .leading, spacing: 10) {
                Label("메뉴바 🍅 아이콘에서 타이머 시작", systemImage: "1.circle.fill")
                Label("50분 집중 + 10분 휴식 자동 사이클", systemImage: "2.circle.fill")
                Label("자리 비움 시 타이머 자동 정지 + 스크린 세이버", systemImage: "3.circle.fill")
                Label("뒤돌아보면 민감 앱 자동 숨김", systemImage: "4.circle.fill")
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 40)
            Spacer()
        }
        .padding(.horizontal, 32)
    }
}

// MARK: - Notifications

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    func setup() {
        UNUserNotificationCenter.current().delegate = self
        // Permission is now requested explicitly in onboarding (not auto on launch)
    }

    func requestPermission(completion: @escaping (Bool) -> Void = { _ in }) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, err in
            print("[notif] permission granted=\(granted) err=\(String(describing: err))")
            DispatchQueue.main.async { completion(granted) }
        }
    }

    func checkPermissionStatus(completion: @escaping (UNAuthorizationStatus) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async { completion(settings.authorizationStatus) }
        }
    }

    func sendBreakStart() {
        send(title: "휴식 시간", body: "10분간 휴식하세요. 잠깐 일어나서 스트레칭 어떠세요?")
    }

    func sendBreakEnded() {
        send(title: "쉬는 시간 종료", body: "10분 휴식이 끝났어요. 업무로 복귀할 시간이에요")
    }

    private func send(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let req = UNNotificationRequest(identifier: UUID().uuidString,
                                        content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req) { err in
            if let err = err { print("[notif] send error: \(err)") }
        }
    }

    // Show banner even when our app is in the foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

// MARK: - Pomodoro

enum PomodoroPhase {
    case work, breakTime

    var displayName: String {
        switch self {
        case .work: return "Focus"
        case .breakTime: return "Break"
        }
    }
}

final class PomodoroManager: ObservableObject {
    @Published var phase: PomodoroPhase = .work
    @Published var remainingSeconds: Int
    @Published var isRunning: Bool = false
    @Published var pausedDueToAway: Bool = false

    let workDuration: Int = 50 * 60       // 50 min
    let breakDuration: Int = 10 * 60      // 10 min (matches "10분 휴식" notification)

    private var timer: Timer?

    init() {
        self.remainingSeconds = 50 * 60
    }

    var label: String {
        let m = remainingSeconds / 60
        let s = remainingSeconds % 60
        let emoji = phase == .work ? "🍅" : "☕️"
        return String(format: "%@ %d:%02d", emoji, m, s)
    }

    func start() {
        guard !isRunning else { return }
        pausedDueToAway = false
        isRunning = true
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    /// User-initiated pause. Clears auto-pause flag.
    func pause() {
        pauseInternal()
        pausedDueToAway = false
    }

    /// Pause because user left desk. Will auto-resume when user returns.
    func pauseDueToAway() {
        guard isRunning else { return }
        pauseInternal()
        pausedDueToAway = true
        print("[pomo] auto-paused (user away)")
    }

    /// Resume after user returned to desk.
    func resumeFromAway() {
        guard pausedDueToAway else { return }
        print("[pomo] auto-resumed (user back)")
        start()  // start() clears pausedDueToAway
    }

    private func pauseInternal() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    func reset() {
        pause()
        phase = .work
        remainingSeconds = workDuration
    }

    func skipPhase() {
        transitionToNextPhase()
    }

    private func tick() {
        remainingSeconds -= 1
        if remainingSeconds <= 0 {
            transitionToNextPhase()
        }
    }

    private func transitionToNextPhase() {
        if phase == .work {
            phase = .breakTime
            remainingSeconds = breakDuration
            NotificationManager.shared.sendBreakStart()
        } else {
            phase = .work
            remainingSeconds = workDuration
            NotificationManager.shared.sendBreakEnded()
        }
    }
}

// MARK: - Camera + trigger manager

final class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "camera.frames")

    // On/off
    @Published var isEnabled: Bool = true {
        didSet { handleEnabledChange() }
    }

    /// Gate for all trigger/away/lock behaviors. Set true when onboarding completes.
    /// Camera still captures frames (so yaw display works in onboarding's safe-range setup),
    /// but no actions fire.
    @Published var isReady: Bool = false

    // Live
    @Published var faceDetected = false
    @Published var yaw: Double = 0
    @Published var pitch: Double = 0
    @Published var roll: Double = 0

    // Attention / away detection (for pomodoro auto-pause)
    // "Attentive" = face detected AND yaw inside safe zone.
    // After awayThreshold seconds of non-attentive → marked as away.
    @Published var isUserAway: Bool = false
    private let awayThreshold: TimeInterval = 5.0  // sec
    private var notAttentiveSince: Date?

    // Screen-lock fires only when face is actually lost (user left desk),
    // not when face is detected but yaw moved away.
    private var faceLostSince: Date?
    private var didLockThisAbsence: Bool = false

    private weak var pomodoroRef: PomodoroManager?

    func attachPomodoro(_ p: PomodoroManager) {
        self.pomodoroRef = p
    }

    // Trigger system
    @Published var baselineYaw: Double = 0
    @Published var baselineReady = false
    @Published var triggerCount = 0
    @Published var recentTriggers: [TriggerEvent] = []
    @Published var triggerFlash = false

    // Safe positions
    @Published var safePositions: [SafePosition] = []
    private let safeMargin: Double = 10.0
    private let singlePointTolerance: Double = 25.0

    var safeRangeLow: Double? {
        guard safePositions.count >= 2 else { return nil }
        return (safePositions.map { $0.yaw }.min() ?? 0) - safeMargin
    }
    var safeRangeHigh: Double? {
        guard safePositions.count >= 2 else { return nil }
        return (safePositions.map { $0.yaw }.max() ?? 0) + safeMargin
    }

    // Sensitive apps
    @Published var sensitiveApps: [SensitiveApp] = []

    // Config
    private let baselineWindow: TimeInterval = 3.0
    private let triggerThreshold: Double = 25.0
    private let faceLostDuration: TimeInterval = 1.0
    private let cooldownDuration: TimeInterval = 5.0
    private let minBaselineSamples = 30

    // Internal state (main thread only)
    private var yawBuffer: [(time: Date, yaw: Double)] = []
    private var faceLastSeenAt: Date = Date()
    private var triggerCooldownUntil: Date?
    private var hadFaceBefore = false
    private var wasOutsideSafeZone = false  // edge-trigger: fire only on transition
    private var triggerArmed = true         // re-armed only after sustained safe dwell
    private var safeZoneEnteredAt: Date?    // when we first re-entered safe zone
    private let armDelay: TimeInterval = 2.0  // sec of safe dwell required to re-arm

    override init() {
        super.init()
        NotificationManager.shared.setup()
        configure()
        startSession()
    }

    private func handleEnabledChange() {
        if isEnabled {
            startSession()
        } else {
            stopSession()
            faceDetected = false
            yawBuffer.removeAll()
            baselineReady = false
        }
    }

    private func startSession() {
        Task.detached { [session] in
            if !session.isRunning { session.startRunning() }
        }
    }

    private func stopSession() {
        Task.detached { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    // MARK: - Public actions

    func saveCurrentAsSafe() {
        guard faceDetected else { return }
        let pos = SafePosition(yaw: yaw, createdAt: Date())
        safePositions.append(pos)
        print(String(format: "✅ Saved safe position: yaw=%+.1f°", pos.yaw))
    }

    func removeSafe(_ id: UUID) {
        safePositions.removeAll { $0.id == id }
    }

    func resetTriggers() {
        triggerCount = 0
        recentTriggers = []
    }

    func pickSensitiveApp() {
        let panel = NSOpenPanel()
        panel.title = "민감 앱 선택"
        panel.message = "트리거 발동 시 자동으로 hide할 앱을 선택하세요"
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            guard let bundle = Bundle(url: url),
                  let bundleId = bundle.bundleIdentifier else {
                print("[app] failed to read bundle id")
                return
            }
            let name = url.deletingPathExtension().lastPathComponent
            if sensitiveApps.contains(where: { $0.bundleId == bundleId }) {
                print("[app] already added: \(bundleId)")
                return
            }
            let app = SensitiveApp(bundleId: bundleId, name: name)
            sensitiveApps.append(app)
            print("[app] added: \(name) (\(bundleId))")
        }
    }

    func removeSensitiveApp(_ id: UUID) {
        sensitiveApps.removeAll { $0.id == id }
    }

    func testHideNow() {
        performTriggerAction(reason: "manual test")
    }

    // MARK: - Trigger logic

    private func tryFireTrigger(reason: String, yaw: Double, baseline: Double) {
        let now = Date()
        if let cooldown = triggerCooldownUntil, now < cooldown { return }
        triggerCooldownUntil = now.addingTimeInterval(cooldownDuration)

        let event = TriggerEvent(timestamp: now, yaw: yaw, baseline: baseline, reason: reason)
        print(String(format: "🔴 TRIGGER FIRED: %@  yaw=%+.1f°  baseline=%+.1f°",
                     reason, yaw, baseline))

        triggerCount += 1
        recentTriggers.append(event)
        if recentTriggers.count > 10 { recentTriggers.removeFirst() }
        triggerFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.triggerFlash = false
        }

        performTriggerAction(reason: reason)
    }

    /// Action that runs when trigger fires (or via manual test button)
    private func performTriggerAction(reason: String) {
        let isBreak = pomodoroRef?.phase == .breakTime

        NSSound.beep()

        // 1) Hide all registered sensitive apps (always — even during break)
        var hiddenCount = 0
        for app in sensitiveApps {
            let runningInstances = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleId)
            for r in runningInstances {
                if r.hide() {
                    hiddenCount += 1
                    print("[hide] \(app.name) (\(app.bundleId))")
                }
            }
        }
        if !sensitiveApps.isEmpty {
            print("[hide] hid \(hiddenCount) app instance(s)")
        }

        // 2) Send notification — skipped during break (already in break, "쉬는 시간 종료" doesn't fit)
        if isBreak {
            print("[trigger] skipped notification (in break time)")
        } else {
            NotificationManager.shared.sendBreakEnded()
        }
    }

    private func processYaw(_ newYaw: Double) {
        let now = Date()
        yawBuffer.append((now, newYaw))
        let cutoff = now.addingTimeInterval(-baselineWindow)
        yawBuffer.removeAll { $0.time < cutoff }

        guard yawBuffer.count >= minBaselineSamples else {
            baselineReady = false
            return
        }

        let sorted = yawBuffer.map { $0.yaw }.sorted()
        let median = sorted[sorted.count / 2]
        baselineYaw = median
        baselineReady = true

        // Trigger evaluation requires onboarding complete
        guard isReady else { return }

        // Evaluate current "danger zone" state across modes
        var isOutside = false
        var reason = ""
        var compareBase = median

        if let lo = safeRangeLow, let hi = safeRangeHigh {
            // Mode A: safe range
            if newYaw < lo || newYaw > hi {
                isOutside = true
                let outBy = newYaw < lo ? (lo - newYaw) : (newYaw - hi)
                reason = String(format: "outside safe range by %.0f°", outBy)
            }
        } else if safePositions.count == 1 {
            // Mode B: single safe point
            let pos = safePositions[0].yaw
            let delta = abs(newYaw - pos)
            if delta > singlePointTolerance {
                isOutside = true
                compareBase = pos
                reason = String(format: "Δ%.0f° from safe point", delta)
            }
        } else {
            // Mode C: fallback (no safe points)
            let delta = abs(newYaw - median)
            if delta > triggerThreshold {
                isOutside = true
                reason = String(format: "yaw Δ%.0f° (no safe range set)", delta)
            }
        }

        // Edge-trigger with re-arming:
        // - Fires only on safe → outside transition
        // - After firing, disarmed until user dwells inside safe zone for armDelay seconds
        if isOutside {
            safeZoneEnteredAt = nil
            if !wasOutsideSafeZone && triggerArmed {
                tryFireTrigger(reason: reason, yaw: newYaw, baseline: compareBase)
                triggerArmed = false
            }
        } else {
            if safeZoneEnteredAt == nil {
                safeZoneEnteredAt = now
            }
            if let entered = safeZoneEnteredAt,
               now.timeIntervalSince(entered) >= armDelay,
               !triggerArmed {
                triggerArmed = true
                print("[trigger] re-armed after \(String(format: "%.1f", armDelay))s safe dwell")
            }
        }
        wasOutsideSafeZone = isOutside
    }

    private func processFaceLost() {
        let now = Date()
        let elapsed = now.timeIntervalSince(faceLastSeenAt)

        guard hadFaceBefore, elapsed > faceLostDuration, yawBuffer.count >= minBaselineSamples else { return }

        let sorted = yawBuffer.map { $0.yaw }.sorted()
        let median = sorted[sorted.count / 2]
        tryFireTrigger(reason: String(format: "face lost %.1fs", elapsed),
                       yaw: 0, baseline: median)
        yawBuffer.removeAll()
        hadFaceBefore = false
    }

    // MARK: - Frame handlers

    private func handleFaceDetected(yaw: Double, pitch: Double, roll: Double) {
        self.faceDetected = true
        self.yaw = yaw
        self.pitch = pitch
        self.roll = roll
        self.faceLastSeenAt = Date()
        self.hadFaceBefore = true

        // Reset face-lost tracking (user is back in frame)
        faceLostSince = nil
        didLockThisAbsence = false

        if isReady {
            updateAttentionState(isAttentive: isYawInsideSafeZone(yaw))
        }

        processYaw(yaw)  // internally gates trigger evaluation
    }

    private func handleFaceLost() {
        self.faceDetected = false

        // All face-lost-driven actions require ready state
        guard isReady else { return }

        // Track face-lost duration and lock screen if sustained
        if faceLostSince == nil {
            faceLostSince = Date()
        }
        if let start = faceLostSince,
           !didLockThisAbsence,
           Date().timeIntervalSince(start) > awayThreshold {
            lockScreen()
            didLockThisAbsence = true
        }

        updateAttentionState(isAttentive: false)
        processFaceLost()
    }

    /// True if yaw is inside the user-defined safe zone.
    /// No safe zone configured → treat as inside (avoid false away state during setup).
    private func isYawInsideSafeZone(_ y: Double) -> Bool {
        if let lo = safeRangeLow, let hi = safeRangeHigh {
            return y >= lo && y <= hi
        }
        if safePositions.count == 1 {
            return abs(safePositions[0].yaw - y) <= singlePointTolerance
        }
        return true
    }

    /// Track attention state for pomodoro auto-pause.
    /// Screen lock is handled separately in handleFaceLost (only when face is actually lost).
    private func updateAttentionState(isAttentive: Bool) {
        if isAttentive {
            notAttentiveSince = nil
            if isUserAway {
                isUserAway = false
                pomodoroRef?.resumeFromAway()
            }
        } else {
            if notAttentiveSince == nil {
                notAttentiveSince = Date()
            }
            if let start = notAttentiveSince,
               !isUserAway,
               Date().timeIntervalSince(start) > awayThreshold {
                isUserAway = true
                pomodoroRef?.pauseDueToAway()
            }
        }
    }

    /// Start the screen saver. Gentler than display sleep — fades in smoothly.
    /// Auto-lock happens based on the system's "Require password after screen saver" setting.
    private func lockScreen() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-a", "ScreenSaverEngine"]
        do {
            try task.run()
            print("[lock] screen saver triggered")
        } catch {
            print("[lock] failed: \(error)")
        }
    }

    // MARK: - Camera setup

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .medium

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            print("[camera] setup failed")
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) {
            session.addOutput(output)
        }
        session.commitConfiguration()
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let request = VNDetectFaceRectanglesRequest { [weak self] req, _ in
            guard let self else { return }

            if let face = req.results?.first as? VNFaceObservation {
                let yaw   = (face.yaw?.doubleValue   ?? 0) * 180 / .pi
                let pitch = (face.pitch?.doubleValue ?? 0) * 180 / .pi
                let roll  = (face.roll?.doubleValue  ?? 0) * 180 / .pi
                DispatchQueue.main.async {
                    self.handleFaceDetected(yaw: yaw, pitch: pitch, roll: roll)
                }
            } else {
                DispatchQueue.main.async {
                    self.handleFaceLost()
                }
            }
        }
        request.revision = VNDetectFaceRectanglesRequestRevision3

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try? handler.perform([request])
    }
}

struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspect
        previewLayer.frame = view.bounds
        previewLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer = previewLayer
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
