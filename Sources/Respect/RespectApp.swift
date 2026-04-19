import SwiftUI
import AppKit
import os.log

// Borderless window that accepts keyboard input
class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@main
struct RespectApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var session = SessionManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
                .frame(minWidth: 600, minHeight: 420)
                .onAppear {
                    appDelegate.session = session
                    if let window = NSApplication.shared.windows.first {
                        window.title = "Respect"
                        appDelegate.mainWindow = window
                        // Hide the main window — we use overlay windows instead
                        window.orderOut(nil)
                    }
                    // Show the setup overlay on launch
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        NotificationCenter.default.post(name: .showSetupScreen, object: session)
                    }
                }
        }
        .defaultSize(width: 700, height: 500)

        MenuBarExtra {
            if session.state == .working {
                Text("Time remaining: \(session.formattedTimeRemaining)")
                Divider()
                Button("End Session Early") { session.lockScreen() }
                Divider()
            }
            if session.state == .locked {
                Text("Screen locked")
                Divider()
            }
            Button("Quit Respect") {
                if session.state != .locked {
                    NSApplication.shared.terminate(nil)
                }
            }
            Divider()
            Button("⚠️ Emergency Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("Q", modifiers: [.command, .shift, .option])
        } label: {
            if session.state == .working && session.timeRemaining <= 600 {
                Text(session.formattedTimeRemaining)
                    .monospacedDigit()
            } else {
                Image(systemName: "clock.badge.checkmark")
            }
        }
    }
}

// MARK: - App Delegate (manages overlay windows)

class AppDelegate: NSObject, NSApplicationDelegate {
    var session: SessionManager?
    var lockWindows: [NSWindow] = []
    var setupWindows: [NSWindow] = []
    var mainWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        log.info("applicationDidFinishLaunching")
        logToFile("applicationDidFinishLaunching")
        NSApplication.shared.setActivationPolicy(.accessory)

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleShowLock(_:)),
            name: .showLockScreen, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleHideLock),
            name: .hideLockScreen, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleShowSetup(_:)),
            name: .showSetupScreen, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleHideSetup),
            name: .hideSetupScreen, object: nil
        )

        // Detect user switching away — cancel timers so it doesn't lock from another account
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(sessionDidResignActive),
            name: NSWorkspace.sessionDidResignActiveNotification, object: nil
        )

        // Detect user switching back (fast user switch)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(sessionDidBecomeActive),
            name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil
        )

        // Detect screen unlock
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(screenUnlocked),
            name: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil
        )
    }

    @objc func sessionDidResignActive() {
        log.info("sessionDidResignActive — user switched away")
        logToFile("sessionDidResignActive — user switched away, cancelling session")
        Task { @MainActor in
            session?.cancelSession()
        }
    }

    @objc func screenUnlocked() {
        log.info("screenUnlocked notification received")
        logToFile("screenUnlocked notification received")
        showSetupScreen()
    }

    @objc func sessionDidBecomeActive() {
        log.info("sessionDidBecomeActive notification received")
        logToFile("sessionDidBecomeActive notification received")
        showSetupScreen()
    }

    private func showSetupScreen() {
        Task { @MainActor in
            guard let session else {
                logToFile("showSetupScreen: no session")
                return
            }
            // Only show setup if not already working
            guard session.state != .working else {
                logToFile("showSetupScreen: skipped (state is working)")
                return
            }
            session.resetForNewSession()
            NotificationCenter.default.post(name: .showSetupScreen, object: session)
        }
    }

    // MARK: - Setup Overlay

    @objc func handleShowSetup(_ notification: Notification) {
        guard let session = notification.object as? SessionManager else {
            logToFile("handleShowSetup: no session in notification")
            return
        }
        logToFile("handleShowSetup: creating setup windows on \(NSScreen.screens.count) screens")

        // Close any existing setup windows
        for window in setupWindows { window.close() }
        setupWindows.removeAll()

        let setupView = ContentView().environmentObject(session)

        for (index, screen) in NSScreen.screens.enumerated() {
            let window = KeyableWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isReleasedWhenClosed = false
            window.backgroundColor = NSColor.white
            window.contentView = NSHostingView(rootView: setupView)
            window.setFrame(screen.frame, display: true)
            window.makeKeyAndOrderFront(nil)
            setupWindows.append(window)

            // Only the first screen's window needs to be key (for keyboard input)
            if index == 0 {
                window.makeKey()
            }
        }

        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @objc func handleHideSetup() {
        logToFile("handleHideSetup: closing \(self.setupWindows.count) setup windows")
        for window in setupWindows {
            window.close()
        }
        setupWindows.removeAll()
    }

    // MARK: - Lock Overlay

    @objc func handleShowLock(_ notification: Notification) {
        guard let session = notification.object as? SessionManager else {
            logToFile("handleShowLock: no session in notification")
            return
        }
        log.info("handleShowLock: creating lock windows on \(NSScreen.screens.count) screens")
        logToFile("handleShowLock: creating lock windows on \(NSScreen.screens.count) screens")

        // Create a lock window on every screen
        let lockView = LockScreenView().environmentObject(session)

        for screen in NSScreen.screens {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isReleasedWhenClosed = false
            window.backgroundColor = .black
            window.contentView = NSHostingView(rootView: lockView)
            window.setFrame(screen.frame, display: true)
            window.makeKeyAndOrderFront(nil)
            lockWindows.append(window)
        }

        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @objc func handleHideLock() {
        log.info("handleHideLock: closing \(self.lockWindows.count) lock windows")
        logToFile("handleHideLock: closing \(self.lockWindows.count) lock windows")
        for window in lockWindows {
            window.close()
        }
        lockWindows.removeAll()
    }

    // MARK: - App Lifecycle

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if session?.state == .locked {
            log.info("applicationShouldTerminate: DENIED (locked)")
            logToFile("applicationShouldTerminate: DENIED (state is locked)")
            return .terminateCancel
        }
        log.info("applicationShouldTerminate: allowed")
        logToFile("applicationShouldTerminate: allowed (state=\(String(describing: self.session?.state)))")
        return .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
