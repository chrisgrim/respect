import SwiftUI

import AppKit

extension NSFont {
    static func roundedSystemFont(ofSize size: CGFloat) -> NSFont {
        let systemFont = NSFont.systemFont(ofSize: size)
        if let descriptor = systemFont.fontDescriptor.withDesign(.rounded) {
            return NSFont(descriptor: descriptor, size: size) ?? systemFont
        }
        return systemFont
    }
}

// MARK: - Airbnb-inspired color palette

private let rausch = Color(red: 1.0, green: 0.35, blue: 0.37)       // #FF5A5F
private let babu = Color(red: 0.0, green: 0.51, blue: 0.56)         // #00A699
private let arches = Color(red: 0.99, green: 0.76, blue: 0.53)      // #FC9D87 warm peach
private let foggy = Color(red: 0.47, green: 0.47, blue: 0.47)       // #767676
private let hof = Color(red: 0.28, green: 0.28, blue: 0.28)         // #484848

// MARK: - Content View (router)

struct ContentView: View {
    @EnvironmentObject var session: SessionManager

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            switch session.state {
            case .apiKeyNeeded:
                ApiKeyInputView()
            case .setup, .processing:
                ChatView()
            case .working:
                WorkingView()
            case .locked:
                Color.black.ignoresSafeArea()
            }
        }
        .preferredColorScheme(.light)
    }
}

// MARK: - API Key Input

struct ApiKeyInputView: View {
    @EnvironmentObject var session: SessionManager
    @State private var apiKey = ""

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 32) {
                // Logo area
                ZStack {
                    Circle()
                        .fill(rausch.opacity(0.1))
                        .frame(width: 96, height: 96)
                    Image(systemName: "key.fill")
                        .font(.system(size: 36))
                        .foregroundColor(rausch)
                }

                VStack(spacing: 10) {
                    Text("Welcome to Respect")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(hof)

                    Text("Enter your Anthropic API key to get started.")
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .foregroundColor(foggy)
                }

                VStack(spacing: 16) {
                    SecureField("sk-ant-...", text: $apiKey)
                        .font(.system(size: 16, design: .rounded))
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(white: 0.82), lineWidth: 1)
                        )
                        .frame(maxWidth: 440)
                        .onSubmit { save() }

                    Button(action: save) {
                        Text("Continue")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: 440)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(
                                        apiKey.trimmingCharacters(in: .whitespaces).isEmpty
                                            ? rausch.opacity(0.4) : rausch
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                Link(
                    "Get an API key at console.anthropic.com",
                    destination: URL(string: "https://console.anthropic.com/settings/keys")!
                )
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(rausch)
            }
            .padding(.horizontal, 48)

            Spacer()
        }
    }

    private func save() {
        let key = apiKey.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }
        session.setApiKey(key)
    }
}

// MARK: - Chat View

struct ChatView: View {
    @EnvironmentObject var session: SessionManager
    @State private var userInput = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        GeometryReader { geo in
        VStack(spacing: 0) {
            Spacer()

            // Centered card
            VStack(spacing: 0) {
                // Header
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(rausch)
                            .frame(width: 36, height: 36)
                        Image(systemName: "clock")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    Text("Respect")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(hof)
                }
                .padding(.top, 28)
                .padding(.bottom, 20)

                Rectangle()
                    .fill(Color(white: 0.93))
                    .frame(height: 1)

                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(session.messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }

                            if session.state == .processing {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .tint(rausch)
                                    Text("Thinking...")
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .foregroundColor(foggy)
                                }
                                .padding(.horizontal, 32)
                                .padding(.vertical, 8)
                            }
                        }
                        .padding(.vertical, 24)
                    }
                    .onChange(of: session.messages.count) { _ in
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo(session.messages.last?.id, anchor: .bottom)
                        }
                    }
                }

                Rectangle()
                    .fill(Color(white: 0.93))
                    .frame(height: 1)

                // Recording indicator or text input
                if session.isRecording {
                    RecordingIndicator(transcript: session.liveTranscript)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                } else {
                    // Input
                    HStack(spacing: 14) {
                        TextField("e.g. \"2 hours\" or \"until 10:30 PM\"", text: $userInput)
                            .textFieldStyle(.plain)
                            .font(.system(size: 16, design: .rounded))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 24)
                                    .fill(Color(white: 0.96))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 24)
                                    .stroke(Color(white: 0.88), lineWidth: 1)
                            )
                            .focused($inputFocused)
                            .onSubmit { sendMessage() }
                            .disabled(session.state == .processing)

                        Button(action: sendMessage) {
                            ZStack {
                                Circle()
                                    .fill(
                                        (userInput.trimmingCharacters(in: .whitespaces).isEmpty
                                            || session.state == .processing)
                                            ? rausch.opacity(0.35) : rausch
                                    )
                                    .frame(width: 44, height: 44)
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(
                            userInput.trimmingCharacters(in: .whitespaces).isEmpty
                                || session.state == .processing
                        )
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                }

                // Hint
                Text("Hold spacebar to talk")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(foggy.opacity(0.6))
                    .padding(.bottom, 12)
            }
            .frame(maxWidth: 560, maxHeight: geo.size.height * 0.65)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.08), radius: 24, x: 0, y: 4)
            )

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.97).ignoresSafeArea())
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                inputFocused = true
            }
        }
        .onReceive(session.$spacebarTranscript) { value in
            if !value.isEmpty {
                userInput = value
                session.spacebarTranscript = ""
            }
        }
        .onChange(of: session.submitRequested) { _ in
            if session.submitRequested {
                session.submitRequested = false
                sendMessage()
            }
        }
    }

    private func sendMessage() {
        let text = userInput.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, session.state == .setup else { return }
        userInput = ""
        Task { await session.handleUserInput(text) }
    }
}

// MARK: - Recording Indicator (pulsing waveform)

struct RecordingIndicator: View {
    let transcript: String
    @State private var animating = false

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 4) {
                ForEach(0..<5, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(rausch)
                        .frame(width: 4, height: animating ? CGFloat.random(in: 14...32) : 8)
                        .animation(
                            .easeInOut(duration: 0.4)
                                .repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.1),
                            value: animating
                        )
                }
            }
            .frame(height: 36)
            .onAppear { animating = true }

            if !transcript.isEmpty {
                Text(transcript)
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundColor(hof)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            } else {
                Text("Listening...")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(foggy)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

// MARK: - Disable focus ring globally

extension NSTextField {
    override open var focusRingType: NSFocusRingType {
        get { .none }
        set {}
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.role == .user { Spacer(minLength: 100) }

            if message.role == .assistant {
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(rausch.opacity(0.1))
                            .frame(width: 36, height: 36)
                        Image(systemName: "sparkles")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(rausch)
                    }

                    Text(message.content)
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .foregroundColor(hof)
                        .textSelection(.enabled)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color(white: 0.96))
                        )
                }
            } else {
                Text(message.content)
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundColor(.white)
                    .textSelection(.enabled)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(rausch)
                    )
            }

            if message.role == .assistant { Spacer(minLength: 100) }
        }
        .padding(.horizontal, 28)
    }
}

// MARK: - Working View

struct WorkingView: View {
    @EnvironmentObject var session: SessionManager

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 28) {
                ZStack {
                    Circle()
                        .fill(
                            session.timeRemaining <= 600
                                ? rausch.opacity(0.1)
                                : babu.opacity(0.1)
                        )
                        .frame(width: 100, height: 100)
                    Image(systemName: "deskclock.fill")
                        .font(.system(size: 42))
                        .foregroundColor(session.timeRemaining <= 600 ? rausch : babu)
                }

                Text("Session Active")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(hof)

                Text("Working until \(session.formattedEndTime)")
                    .font(.system(size: 17, weight: .regular, design: .rounded))
                    .foregroundColor(foggy)

                Text(session.formattedTimeRemaining)
                    .font(.system(size: 64, weight: .semibold, design: .monospaced))
                    .foregroundColor(session.timeRemaining <= 600 ? rausch : hof)

                if session.timeRemaining <= 600 {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(rausch)
                        Text("Wrapping up soon!")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundColor(rausch)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(rausch.opacity(0.08))
                    )
                }
            }

            Spacer()

            Button(action: { session.lockScreen() }) {
                Text("End Session Early")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(foggy)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(white: 0.82), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Lock Screen View

struct LockScreenView: View {
    @EnvironmentObject var session: SessionManager

    var body: some View {
        ZStack {
            // Dark gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.08, blue: 0.12),
                    Color.black,
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 36) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(rausch.opacity(0.15))
                        .frame(width: 120, height: 120)
                    Image(systemName: "lock.fill")
                        .font(.system(size: 52))
                        .foregroundColor(rausch)
                }

                VStack(spacing: 12) {
                    Text("Time's Up")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text("Great work today. Take a break.")
                        .font(.system(size: 20, weight: .regular, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                }

                VStack(spacing: 10) {
                    Text("Logging out in")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.4))
                        .textCase(.uppercase)
                        .tracking(1.5)

                    Text(session.formattedLockTimeRemaining)
                        .font(.system(size: 72, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                }
                .padding(.top, 12)

                Spacer()

                HStack(spacing: 16) {
                    Button(action: { session.unlock() }) {
                        HStack(spacing: 10) {
                            Image(systemName: "lock.open.fill")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Unlock & Set New Timer")
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 36)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(rausch)
                        )
                    }
                    .buttonStyle(.plain)

                    Button(action: { session.lockOutNow() }) {
                        HStack(spacing: 10) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Lock Out Now")
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 36)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }

                Spacer().frame(height: 60)
            }
        }
        .ignoresSafeArea()
    }
}
