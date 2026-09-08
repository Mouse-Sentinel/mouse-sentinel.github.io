import AppKit
import ApplicationServices
import CoreGraphics
import SwiftUI

struct ContentView: View {
    @ObservedObject var nudger: MouseNudger
    @StateObject private var permissionMonitor = AccessibilityPermissionMonitor()

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                SentinelBrandMark()
                    .frame(width: 75, height: 75)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 40)

                HeroSection(isEnabled: $nudger.isEnabled)
                    .padding(.bottom, 12)

                CountdownPanel(
                    fractionRemaining: nudger.isEnabled ? nudger.countdownFraction : 0,
                    isActive: nudger.isEnabled,
                    intervalSeconds: nudger.intervalSeconds
                )
                .padding(.bottom, 12)

                IntervalPanel(nudger: nudger)

                AccessibilityIndicator(
                    isGranted: permissionMonitor.hasMouseMovementPermission || nudger.hasMovedSuccessfully,
                    isChecking: permissionMonitor.isChecking,
                    onRequestPermission: permissionMonitor.requestPermission
                )
            }
            .padding(.horizontal, 12)
            .padding(.top, 37)

            FooterBar(isRunning: nudger.isEnabled)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 12)
        }
        .frame(width: 560)
        .background {
            AppBackground()
                .ignoresSafeArea()
        }
        .onAppear {
            permissionMonitor.refresh()
            if nudger.verifyMovementAccess() {
                permissionMonitor.markMovementVerified()
            }
            permissionMonitor.refresh()
        }
        .onChange(of: nudger.hasMovedSuccessfully) { _, didMove in
            if didMove {
                permissionMonitor.markMovementVerified()
            }
        }
    }
}

@MainActor
final class AccessibilityPermissionMonitor: ObservableObject {
    @Published private(set) var hasMouseMovementPermission = AXIsProcessTrusted() || CGPreflightPostEventAccess()
    @Published private(set) var isChecking = true

    private var lastKnownGranted = false
    private var timer: Timer?

    init() {
        completeVisibleCheck(after: 1)

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    deinit {
        timer?.invalidate()
    }

    func refresh() {
        let trusted = AXIsProcessTrusted()
        let postAccess = CGPreflightPostEventAccess()
        hasMouseMovementPermission = trusted || postAccess || lastKnownGranted
    }

    func markMovementVerified() {
        lastKnownGranted = true
        hasMouseMovementPermission = true
        isChecking = false
    }

    func requestPermission() {
        isChecking = true

        let options: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ]
        let accessibilityGranted = AXIsProcessTrustedWithOptions(options)
        let postAccessGranted = CGRequestPostEventAccess()
        lastKnownGranted = lastKnownGranted || accessibilityGranted || postAccessGranted

        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }

        refresh()
        completeVisibleCheck(after: 1.5, probeMovement: true)
    }

    private func completeVisibleCheck(after delay: TimeInterval, probeMovement: Bool = false) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            if probeMovement, MouseNudger.shared.verifyMovementAccess() {
                markMovementVerified()
            } else {
                refresh()
                isChecking = false
            }
        }
    }
}

struct MenuBarContent: View {
    @ObservedObject var nudger: MouseNudger

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(nudger.isEnabled ? "Sentinel active" : "Sentinel stopped")
                .font(.headline)

            Text("Next movement: \(nudger.countdownLabel)")
                .foregroundStyle(.secondary)

            Divider()

            Button(nudger.isEnabled ? "Stop Sentinel" : "Start Sentinel") {
                nudger.isEnabled.toggle()
            }

            Button("Show App") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.unhide(nil)
                NSApp.windows.forEach { $0.makeKeyAndOrderFront(nil) }
            }

            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
        .padding(8)
        .frame(width: 220)
    }
}

private struct HeroSection: View {
    @Binding var isEnabled: Bool

    var body: some View {
        VStack(spacing: 7) {
            Text("Mouse Sentinel")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Color.appInk)

            Text(isEnabled ? "Keeping your Mac awake" : "Ready when you are")
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(Color.appGreen.opacity(isEnabled ? 0.74 : 0.5))

            PowerToggleButton(isEnabled: $isEnabled)
                .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct PowerToggleButton: View {
    @Binding var isEnabled: Bool

    var body: some View {
        Button {
            isEnabled.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isEnabled ? "stop.fill" : "play.fill")
                    .font(.system(size: 12, weight: .bold))

                Text(isEnabled ? "Stop Sentinel" : "Start Sentinel")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
            }
            .foregroundStyle(isEnabled ? Color.appGreenDark : .white)
            .padding(.horizontal, 18)
            .frame(height: 36)
            .background(
                Capsule(style: .continuous)
                    .fill(isEnabled ? Color.appGreen.opacity(0.13) : Color.appGreen)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isEnabled ? "Turn Mouse Sentinel off" : "Turn Mouse Sentinel on")
    }
}

struct CountdownPanel: View {
    let fractionRemaining: Double
    let isActive: Bool
    let intervalSeconds: Double

    var body: some View {
        SoftCard {
            CountdownRing(
                fractionRemaining: fractionRemaining,
                isActive: isActive,
                intervalSeconds: intervalSeconds
            )
            .frame(width: 158, height: 158)
        }
        .frame(width: 320, height: 178)
    }
}

struct CountdownRing: View {
    let fractionRemaining: Double
    let isActive: Bool
    let intervalSeconds: Double

    var body: some View {
        let clampedFraction = max(0, min(1, fractionRemaining))
        let secondsRemaining = isActive ? max(0, Int(ceil(clampedFraction * intervalSeconds))) : 0

        ZStack {
            Circle()
                .stroke(Color.appGreen.opacity(0.16), lineWidth: 14)

            Circle()
                .trim(from: 0, to: clampedFraction)
                .stroke(
                    AngularGradient(
                        colors: [
                            Color.appGreenSoft,
                            Color.appGreen,
                            Color.appGreenDark
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: Color.appGreen.opacity(isActive ? 0.35 : 0), radius: 13)
                .animation(.linear(duration: 0.05), value: clampedFraction)

            Circle()
                .fill(isActive ? Color.appGreen : Color.secondary.opacity(0.45))
                .frame(width: 16, height: 16)
                .offset(y: -87)
                .shadow(color: Color.appGreen.opacity(isActive ? 0.38 : 0), radius: 12)

            VStack(spacing: 3) {
                if isActive {
                    Text("Next movement in")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.appMuted)

                    Text("\(secondsRemaining)")
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.appGreen)
                        .contentTransition(.numericText())

                    Text("seconds")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.appMuted)
                } else {
                    Text("Sentinel is off")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.appMuted)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isActive)
        }
        .accessibilityLabel(isActive ? "\(secondsRemaining) seconds until next movement" : "Countdown disabled")
    }
}

private struct IntervalPanel: View {
    @ObservedObject var nudger: MouseNudger

    var body: some View {
        SoftCard {
            VStack(spacing: 16) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.appGreen.opacity(0.13))
                        Image(systemName: "clock")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(Color.appGreenDark)
                    }
                    .frame(width: 42, height: 42)

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Movement interval")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.appInk)

                        Text("\(Int(nudger.intervalSeconds)) seconds")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.appGreenDark)
                    }

                    Spacer()
                }

                VStack(spacing: 10) {
                    Slider(
                        value: Binding(
                            get: { nudger.intervalSeconds },
                            set: { nudger.updateIntervalSeconds($0) }
                        ),
                        in: 5...60,
                        step: 1
                    )
                    .tint(Color.appGreen)

                    HStack {
                        Text("5s")
                        Spacer()
                        Text("15s")
                        Spacer()
                        Text("30s")
                        Spacer()
                        Text("60s")
                    }
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.appMuted)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 142)
    }
}

private struct StatusPanel: View {
    let accessibilityPermissionGranted: Bool
    let isAccessibilityChecking: Bool
    let isEnabled: Bool
    let requestAccessibilityPermission: () -> Void

    var body: some View {
        SoftCard {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    Button {
                        requestAccessibilityPermission()
                    } label: {
                        StatusRow(
                            isGood: accessibilityPermissionGranted,
                            isChecking: isAccessibilityChecking && !accessibilityPermissionGranted,
                            title: accessibilityPermissionTitle,
                            subtitle: accessibilityPermissionSubtitle
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(accessibilityPermissionGranted)
                    .accessibilityHint(accessibilityPermissionGranted ? "Accessibility permission is already enabled." : "Opens the macOS Accessibility permission flow.")

                    StatusRow(
                        isGood: isEnabled,
                        isChecking: false,
                        title: isEnabled ? "Mouse movement active" : "Mouse movement paused",
                        subtitle: isEnabled ? "Your Mac will stay awake" : "Turn Sentinel on to keep your Mac awake"
                    )
                }
                .padding(.bottom, 5)

                Spacer()

                Image(systemName: "display")
                    .font(.system(size: 27, weight: .medium))
                    .foregroundStyle(Color.appGreenDark)
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 112)
    }

    private var accessibilityPermissionTitle: String {
        if accessibilityPermissionGranted {
            return "Accessibility permission granted"
        }

        return isAccessibilityChecking ? "Checking accessibility permission" : "Accessibility permission needed"
    }

    private var accessibilityPermissionSubtitle: String {
        if accessibilityPermissionGranted {
            return "Mouse movement allowed"
        }

        return isAccessibilityChecking ? "Confirming mouse movement access" : "Click to re-authorize this build"
    }
}

private struct StatusRow: View {
    let isGood: Bool
    let isChecking: Bool
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            if isChecking {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 22, height: 22)
            } else {
                Image(systemName: isGood ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isGood ? Color.appGreen : Color.orange)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.appInk)

                Text(subtitle)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.appMuted)
            }
        }
    }
}

private struct AccessibilityIndicator: View {
    let isGranted: Bool
    let isChecking: Bool
    let onRequestPermission: () -> Void

    var body: some View {
        Button {
            if !isGranted {
                onRequestPermission()
            }
        } label: {
            HStack(spacing: 10) {
                if isChecking && !isGranted {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isGranted ? Color.appGreen : Color.orange)
                }

                Text(isGranted ? "Accessibility granted" : (isChecking ? "Checking accessibility..." : "Accessibility needed"))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.appMuted)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.7))
            )
        }
        .buttonStyle(.plain)
        .disabled(isGranted)
        .accessibilityHint(isGranted ? "Accessibility permission is already enabled." : "Opens the macOS Accessibility permission flow.")
    }
}

private struct FooterBar: View {
    let isRunning: Bool

    var body: some View {
        HStack {
            Image(systemName: "shield")
                .font(.system(size: 16, weight: .medium))

            Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                .font(.system(size: 13, weight: .semibold, design: .rounded))

            Spacer()

            Text(isRunning ? "Running in background" : "Not running")
                .font(.system(size: 13, weight: .semibold, design: .rounded))

            Circle()
                .fill(isRunning ? Color.appGreen : Color.red)
                .frame(width: 9, height: 9)
                .offset(y: 1)
        }
        .foregroundStyle(Color.appMuted.opacity(0.76))
    }
}

private struct SoftCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.88))
                    .shadow(color: Color.black.opacity(0.11), radius: 18, x: 0, y: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.black.opacity(0.07), lineWidth: 1)
            )
    }
}

private struct SentinelBrandMark: View {
    var body: some View {
        ZStack {
            ShieldShape()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.37, green: 0.77, blue: 0.23),
                            Color(red: 0.05, green: 0.60, blue: 0.39),
                            Color(red: 0.39, green: 0.78, blue: 0.37)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            ShieldShape()
                .fill(Color.black.opacity(0.12))
                .clipShape(ShieldHalf())

            MouseMark()
                .fill(Color(red: 0.96, green: 0.94, blue: 0.88))
                .frame(width: 86, height: 98)
                .offset(y: 14)

            EarPair()
                .fill(Color(red: 0.98, green: 0.96, blue: 0.91))
                .frame(width: 106, height: 62)
                .offset(y: -21)

            Whiskers()
                .stroke(Color.appInk.opacity(0.78), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 88, height: 35)
                .offset(y: 31)

            HStack(spacing: 18) {
                Circle()
                    .fill(Color.appInk.opacity(0.92))
                Circle()
                    .fill(Color.appInk.opacity(0.92))
            }
            .frame(width: 46, height: 9)
            .offset(y: 16)

            Circle()
                .fill(Color.appInk.opacity(0.92))
                .frame(width: 10, height: 10)
                .offset(y: 54)
        }
        .shadow(color: Color.appGreen.opacity(0.2), radius: 16, x: 0, y: 10)
        .accessibilityHidden(true)
    }
}

private struct AppBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.985, green: 0.982, blue: 0.955)

            RadialGradient(
                colors: [Color.appGreen.opacity(0.08), .clear],
                center: .top,
                startRadius: 20,
                endRadius: 280
            )
        }
    }
}

private struct ShieldShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.26))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.56))
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control1: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.78),
            control2: CGPoint(x: rect.midX + rect.width * 0.24, y: rect.maxY - rect.height * 0.04)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.56),
            control1: CGPoint(x: rect.midX - rect.width * 0.24, y: rect.maxY - rect.height * 0.04),
            control2: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.78)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.26))
        path.closeSubpath()
        return path
    }
}

private struct ShieldHalf: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private extension Color {
    static let appGreen = Color(red: 0.09, green: 0.70, blue: 0.20)
    static let appGreenDark = Color(red: 0.05, green: 0.52, blue: 0.17)
    static let appGreenSoft = Color(red: 0.68, green: 0.88, blue: 0.63)
    static let appInk = Color(red: 0.10, green: 0.14, blue: 0.19)
    static let appMuted = Color(red: 0.39, green: 0.43, blue: 0.50)
}
