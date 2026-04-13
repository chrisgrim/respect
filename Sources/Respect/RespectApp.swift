import SwiftUI
import AppKit

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
                        // Go full screen on launch
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            window.toggleFullScreen(nil)
                        }
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

// MARK: - App Delegate (manages lock window)

class AppDelegate: NSObject, NSApplicationDelegate {
    var session: SessionManager?
    var lockWindows: [NSWindow] = []
    weak var mainWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleShowLock(_:)),
            name: .showLockScreen, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleHideLock),
            name: .hideLockScreen, object: nil
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

    @objc func screenUnlocked() {
        showSetupScreen()
    }

    @objc func sessionDidBecomeActive() {
        showSetupScreen()
    }

    private func showSetupScreen() {
        Task { @MainActor in
            guard let session, let mainWindow else { return }

            // Always reset and show setup when switching back to this user
            session.resetForNewSession()

            NSApplication.shared.unhide(nil)
            mainWindow.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if !mainWindow.styleMask.contains(.fullScreen) {
                    mainWindow.toggleFullScreen(nil)
                }
            }
        }
    }

    @objc func handleShowLock(_ notification: Notification) {
        guard let session = notification.object as? SessionManager else { return }

        // Hide all existing app windows
        for window in NSApplication.shared.windows {
            if !lockWindows.contains(window) {
                window.orderOut(nil)
            }
        }

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
        for window in lockWindows {
            window.close()
        }
        lockWindows.removeAll()

        // Re-show the main window and go full screen
        guard let mainWindow = self.mainWindow else { return }

        NSApplication.shared.unhide(nil)
        mainWindow.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)

        // Give the window time to fully appear before toggling full screen
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if !mainWindow.styleMask.contains(.fullScreen) {
                mainWindow.toggleFullScreen(nil)
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if session?.state == .locked {
            return .terminateCancel
        }
        return .terminateNow
    }

    // Hide instead of quit when the window close button is clicked
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let mainWindow {
            mainWindow.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false // Keep running in menu bar
    }
}
