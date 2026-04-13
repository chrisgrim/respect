import Foundation
import SwiftUI
import UserNotifications
import IOKit.pwr_mgt
import Combine

// MARK: - Data Types

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: MessageRole
    let content: String

    enum MessageRole {
        case assistant, user
    }
}

enum AppState: Equatable {
    case apiKeyNeeded
    case setup
    case processing
    case working
    case locked
}

extension Notification.Name {
    static let showLockScreen = Notification.Name("showLockScreen")
    static let hideLockScreen = Notification.Name("hideLockScreen")
}

// MARK: - Session Manager

@MainActor
class SessionManager: ObservableObject {
    @Published var state: AppState = .setup
    @Published var messages: [ChatMessage] = []
    @Published var endTime: Date?
    @Published var lockEndTime: Date?
    @Published var timeRemaining: TimeInterval = 0
    @Published var lockTimeRemaining: TimeInterval = 0
    @Published var spacebarTranscript = ""
    @Published var submitRequested = false
    @Published var isRecording = false
    @Published var liveTranscript = ""

    let speech = SpeechService()
    private var speechObserver: Any?

    private var workTimer: Timer?
    private var lockTimer: Timer?
    private var warningShown = false
    private var apiKey: String = ""
    private var sleepAssertionID: IOPMAssertionID = 0

    // MARK: - Formatted strings

    var formattedTimeRemaining: String {
        let total = max(0, Int(timeRemaining))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }

    var formattedLockTimeRemaining: String {
        let total = max(0, Int(lockTimeRemaining))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    var formattedEndTime: String {
        guard let endTime else { return "" }
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: endTime)
    }

    // MARK: - Init

    init() {
        loadApiKey()
        if apiKey.isEmpty {
            state = .apiKeyNeeded
        } else {
            state = .setup
            addAssistantMessage("Take a moment Chris. Have you spoken to Lucy and told her you are doing this? She is okay with it as long as she knows.\n\nHow long are you working for today?")
        }
        requestNotificationPermission()
        setupSpacebarMonitor()

        // Forward speech state changes to trigger SwiftUI updates
        speechObserver = speech.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.isRecording = self?.speech.isRecording ?? false
                self?.liveTranscript = self?.speech.transcript ?? ""
            }
        }
    }

    // MARK: - Spacebar Monitor

    nonisolated private func setupSpacebarMonitor() {
        var holdTimer: DispatchWorkItem?
        var spaceHeld = false

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let currentState = MainActor.assumeIsolated { self.state }

            // Enter/Return — submit
            if (event.keyCode == 36 || event.keyCode == 76) && currentState == .setup {
                MainActor.assumeIsolated { self.submitRequested = true }
                return nil
            }

            // Spacebar hold-to-talk
            if event.keyCode == 49 && currentState == .setup {
                if spaceHeld { return nil }
                if event.isARepeat { return nil }

                spaceHeld = true

                let timer = DispatchWorkItem {
                    guard spaceHeld else { return }
                    MainActor.assumeIsolated { self.speech.startRecording() }
                }
                holdTimer = timer
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: timer)

                return event
            }
            return event
        }

        NSEvent.addLocalMonitorForEvents(matching: .keyUp) { event in
            if event.keyCode == 49 && spaceHeld {
                spaceHeld = false
                holdTimer?.cancel()
                holdTimer = nil

                let isRecording = MainActor.assumeIsolated { self.speech.isRecording }
                if isRecording {
                    MainActor.assumeIsolated {
                        self.speech.stopRecording()
                        let text = self.speech.transcript.trimmingCharacters(in: .whitespaces)
                        if !text.isEmpty {
                            self.spacebarTranscript = text
                        }
                    }
                    return nil
                }
                return event
            }
            return event
        }
    }

    // MARK: - API Key

    func setApiKey(_ key: String) {
        apiKey = key
        saveApiKey(key)
        state = .setup
        addAssistantMessage("Take a moment Chris. Have you spoken to Lucy and told her you are doing this? She is okay with it as long as she knows.\n\nHow long are you working for today?")
    }

    private func loadApiKey() {
        let path = (("~/.config/respect/api_key") as NSString).expandingTildeInPath
        apiKey = (try? String(contentsOfFile: path, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func saveApiKey(_ key: String) {
        let dir = (("~/.config/respect") as NSString).expandingTildeInPath
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = dir + "/api_key"
        try? key.write(toFile: path, atomically: true, encoding: .utf8)
        // Restrict permissions to owner only
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
    }

    // MARK: - User Input

    func handleUserInput(_ input: String) async {
        messages.append(ChatMessage(role: .user, content: input))
        state = .processing

        // Try Sonnet first, fall back to Haiku if it fails
        let models = ["claude-sonnet-4-20250514", "claude-haiku-4-5-20251001"]
        var lastError: Error?

        for model in models {
            do {
                let (response, minutes) = try await parseTimeWithClaude(input, model: model)
                addAssistantMessage(response)

                // Brief pause so the user can read the response
                try await Task.sleep(nanoseconds: 2_500_000_000)
                startWorkSession(minutes: minutes)
                return
            } catch {
                lastError = error
            }
        }

        addAssistantMessage(
            "Sorry, I couldn't understand that. Try something like \"2 hours\" or \"until 10:30 PM\".\n\n(Error: \(lastError?.localizedDescription ?? "unknown"))"
        )
        state = .setup
    }

    // MARK: - Work Session

    private func startWorkSession(minutes: Int) {
        endTime = Date().addingTimeInterval(Double(minutes) * 60)
        warningShown = false
        state = .working
        preventSleep()

        // Exit full screen and hide the app so the user can work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let window = NSApplication.shared.windows.first {
                if window.styleMask.contains(.fullScreen) {
                    window.toggleFullScreen(nil)
                    // Wait for the full-screen animation to finish, then hide
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        NSApplication.shared.hide(nil)
                    }
                } else {
                    NSApplication.shared.hide(nil)
                }
            }
        }

        // Use a RunLoop-tolerant timer that keeps firing even when the app is hidden
        workTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickWork() }
        }
        RunLoop.main.add(workTimer!, forMode: .common)
    }

    private func tickWork() {
        guard let endTime else { return }
        timeRemaining = endTime.timeIntervalSinceNow

        if timeRemaining <= 600 && !warningShown {
            warningShown = true
            showWarning()
        }
        if timeRemaining <= 0 {
            workTimer?.invalidate()
            lockScreen()
        }
    }

    // MARK: - Warning

    private func showWarning() {
        let content = UNMutableNotificationContent()
        content.title = "Respect"
        content.body = "You have 10 minutes left! Start wrapping up."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "respect-warning",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)

        // Unhide the app and bring window to front
        NSApplication.shared.unhide(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let window = NSApplication.shared.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - Lock Screen

    func lockScreen() {
        workTimer?.invalidate()
        allowSleep()
        state = .locked
        lockEndTime = Date().addingTimeInterval(120) // 2 minutes

        NotificationCenter.default.post(name: .showLockScreen, object: self)

        lockTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickLock() }
        }
        RunLoop.main.add(lockTimer!, forMode: .common)
    }

    private func tickLock() {
        guard let lockEndTime else { return }
        lockTimeRemaining = lockEndTime.timeIntervalSinceNow

        if lockTimeRemaining <= 0 {
            lockTimer?.invalidate()
            logOut()
        }
    }

    func unlock() {
        lockTimer?.invalidate()
        workTimer?.invalidate()
        state = .setup
        messages = []
        endTime = nil
        lockEndTime = nil
        warningShown = false
        addAssistantMessage("Welcome back! How long are you working for this time?")

        NotificationCenter.default.post(name: .hideLockScreen, object: nil)
    }

    private func logOut() {
        // Dismiss the lock overlay first
        NotificationCenter.default.post(name: .hideLockScreen, object: nil)

        // Lock the screen using SACLockScreenImmediate (no permissions needed)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            typealias LockFunc = @convention(c) () -> Void
            if let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/login", RTLD_LAZY),
               let sym = dlsym(handle, "SACLockScreenImmediate") {
                let lock = unsafeBitCast(sym, to: LockFunc.self)
                lock()
            }
        }
    }

    func lockOutNow() {
        lockTimer?.invalidate()
        NotificationCenter.default.post(name: .hideLockScreen, object: nil)
        logOut()
    }

    // MARK: - Reset

    func resetForNewSession() {
        workTimer?.invalidate()
        lockTimer?.invalidate()
        allowSleep()
        state = .setup
        messages = []
        endTime = nil
        lockEndTime = nil
        warningShown = false
        addAssistantMessage("Take a moment Chris. Have you spoken to Lucy and told her you are doing this? She is okay with it as long as she knows.\n\nHow long are you working for today?")
    }

    // MARK: - Helpers

    private func addAssistantMessage(_ text: String) {
        messages.append(ChatMessage(role: .assistant, content: text))
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func preventSleep() {
        let reason = "Respect work session active" as CFString
        IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &sleepAssertionID
        )
    }

    private func allowSleep() {
        if sleepAssertionID != 0 {
            IOPMAssertionRelease(sleepAssertionID)
            sleepAssertionID = 0
        }
    }

    // MARK: - Claude API

    private func parseTimeWithClaude(_ input: String, model: String = "claude-sonnet-4-20250514") async throws -> (String, Int) {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a 'on' EEEE, MMMM d, yyyy"
        let currentTime = formatter.string(from: Date())

        let systemPrompt = """
        You are a friendly assistant in a work-timer app called Respect. \
        The current time is \(currentTime). \
        The user will tell you how long they want to work. Parse their input and respond \
        with a brief, warm, encouraging message (2-3 sentences max). \
        On the VERY LAST LINE of your response, include exactly: MINUTES:X \
        where X is the number of minutes from now until they should stop working. \
        Examples: "2 hours" → MINUTES:120, "until 10:30 PM" (if it's 8 PM now) → MINUTES:150, \
        "30 minutes" → MINUTES:30. \
        If the input doesn't make sense as a time duration, respond asking them to clarify \
        and use MINUTES:0 on the last line.
        """

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 200,
            "system": systemPrompt,
            "messages": [["role": "user", "content": input]],
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.httpBody = jsonData
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? "no body"
            throw NSError(
                domain: "Respect", code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "API \(httpResponse.statusCode): \(body)"]
            )
        }

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let content = json["content"] as? [[String: Any]],
            let first = content.first,
            let text = first["text"] as? String
        else {
            throw NSError(
                domain: "Respect", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unexpected API response"]
            )
        }

        // Parse MINUTES:X from the last line
        let lines = text.components(separatedBy: "\n")
        guard
            let minutesLine = lines.last(where: { $0.contains("MINUTES:") }),
            let raw = minutesLine.components(separatedBy: "MINUTES:").last,
            let digits = raw.trimmingCharacters(in: .whitespaces)
                .components(separatedBy: CharacterSet.decimalDigits.inverted).first,
            let minutes = Int(digits),
            minutes > 0
        else {
            throw NSError(
                domain: "Respect", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Could not parse time"]
            )
        }

        let displayText = lines
            .filter { !$0.contains("MINUTES:") }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return (displayText, minutes)
    }
}
