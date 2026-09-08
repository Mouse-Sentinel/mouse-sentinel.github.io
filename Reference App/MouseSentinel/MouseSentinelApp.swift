import AppKit
import Combine
import CoreGraphics
import Foundation
import SwiftUI

@main
struct MouseSentinelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var nudger = MouseNudger.shared

    var body: some Scene {
        WindowGroup {
            ContentView(nudger: nudger)
        }
        .defaultSize(width: 560, height: 760)
        .windowResizability(.contentSize)

        // SwiftUI MenuBarExtra uses a true template glyph that Liquid Glass can tint.
        MenuBarExtra {
            StatusMenuContent(nudger: nudger)
        } label: {
            Image(systemName: "cursorarrow.rays")
                .symbolRenderingMode(nudger.isEnabled ? .palette : .monochrome)
                // Active: green cursor (primary layer), template-tinted rays (secondary).
                .foregroundStyle(
                    nudger.isEnabled ? Color(red: 0.09, green: 0.70, blue: 0.20) : .primary,
                    .primary
                )
                .accessibilityLabel("Mouse Sentinel")
                .help(nudger.menuBarTitle)
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct StatusMenuContent: View {
    @ObservedObject var nudger: MouseNudger

    var body: some View {
        Text(nudger.isEnabled ? "Sentinel active" : "Sentinel stopped")
        Text("Next movement: \(nudger.countdownLabel)")
        Divider()
        Button(nudger.isEnabled ? "Stop Sentinel" : "Start Sentinel") {
            nudger.isEnabled.toggle()
        }
        Button("Show App") {
            AppDelegate.showMainWindow()
        }
        Button("Quit") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        DispatchQueue.main.async {
            Self.showMainWindow()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Self.showMainWindow()
        return true
    }

    static func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.unhide(nil)
        for window in NSApp.windows where window.styleMask.contains(.titled) {
            window.backgroundColor = NSColor(red: 0.985, green: 0.982, blue: 0.955, alpha: 1)
            window.isOpaque = true
            window.makeKeyAndOrderFront(nil)
        }
    }
}

@MainActor
final class MouseNudger: ObservableObject {
    static let shared = MouseNudger()

    @Published var isEnabled = false {
        didSet {
            if isEnabled {
                startKeepingAwake()
                startMonitoringUserActivity()
                startTimer()
                resetCountdown()
            } else {
                stopMonitoringUserActivity()
                stopTimer()
                stopKeepingAwake()
                resetCountdown()
            }
        }
    }

    @Published var countdownFraction: Double = 0
    @Published private(set) var hasMovedSuccessfully = false
    @Published private(set) var intervalSeconds: Double = 15.0

    private var timer: Timer?
    private var cycleStartDate: Date?
    private var previousNudgeVector: CGVector?
    private var awakeActivity: NSObjectProtocol?
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var ignoreMouseActivityUntil: Date?

    func nudgeOnce() {
        let currentLocation = NSEvent.mouseLocation
        let nudgeVector = randomNudgeVector()

        let targetPoint = clampToScreen(CGPoint(
            x: currentLocation.x + nudgeVector.dx,
            y: currentLocation.y + nudgeVector.dy
        ))

        if performMove(to: targetPoint, from: currentLocation) {
            hasMovedSuccessfully = true
        }
    }

    /// Tiny move + restore to confirm cursor control without a full nudge cycle.
    @discardableResult
    func verifyMovementAccess() -> Bool {
        let origin = NSEvent.mouseLocation
        let probe = probePoint(from: origin)

        ignoreMouseActivityUntil = Date().addingTimeInterval(0.35)

        guard performMove(to: probe, from: origin) else {
            return false
        }

        _ = performMove(to: origin, from: NSEvent.mouseLocation)
        hasMovedSuccessfully = true
        return true
    }

    var countdownLabel: String {
        isEnabled ? "\(remainingSecondsText) left" : "Stopped"
    }

    var menuBarTitle: String {
        isEnabled ? "Mouse Sentinel • \(remainingSecondsText)" : "Mouse Sentinel • Off"
    }

    func updateIntervalSeconds(_ newValue: Double) {
        let clampedValue = max(5.0, min(60.0, newValue))
        guard abs(clampedValue - intervalSeconds) > 0.0001 else { return }

        intervalSeconds = clampedValue

        if isEnabled {
            cycleStartDate = Date()
            updateCountdown()
        } else {
            resetCountdown()
        }
    }

    private func startTimer() {
        stopTimer()

        cycleStartDate = Date()
        updateCountdown()

        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        cycleStartDate = nil
    }

    private func startMonitoringUserActivity() {
        stopMonitoringUserActivity()

        let userActivityMask: NSEvent.EventTypeMask = [
            .mouseMoved,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
            .leftMouseDragged,
            .rightMouseDragged,
            .otherMouseDragged,
            .scrollWheel,
            .keyDown,
            .flagsChanged
        ]

        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: userActivityMask) { [weak self] event in
            guard let self else { return event }
            Task { @MainActor in
                self.handleUserActivity(event)
            }
            return event
        }

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: userActivityMask) { [weak self] event in
            Task { @MainActor in
                self?.handleUserActivity(event)
            }
        }
    }

    private func stopMonitoringUserActivity() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }

        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }
    }

    private func startKeepingAwake() {
        stopKeepingAwake()

        awakeActivity = ProcessInfo.processInfo.beginActivity(
            options: [.idleDisplaySleepDisabled, .idleSystemSleepDisabled],
            reason: "Mouse Sentinel is actively nudging the mouse"
        )
    }

    private func stopKeepingAwake() {
        if let awakeActivity {
            ProcessInfo.processInfo.endActivity(awakeActivity)
            self.awakeActivity = nil
        }
    }

    private func tick() {
        guard isEnabled else { return }

        if let cycleStartDate {
            let elapsed = Date().timeIntervalSince(cycleStartDate)
            if elapsed >= intervalSeconds {
                nudgeOnce()
                self.cycleStartDate = Date()
            }
        }

        updateCountdown()
    }

    private func updateCountdown() {
        guard isEnabled, let cycleStartDate else {
            countdownFraction = 0
            return
        }

        let elapsed = Date().timeIntervalSince(cycleStartDate)
        let interval = max(1.0, intervalSeconds)
        let remaining = max(0, interval - elapsed)
        countdownFraction = remaining / interval
    }

    private var remainingSecondsText: String {
        if !isEnabled {
            return "Off"
        }

        let remaining = max(0, Int(ceil(countdownFraction * max(1.0, intervalSeconds))))
        return "\(remaining)s"
    }

    private func resetCountdown() {
        countdownFraction = isEnabled ? 1 : 0
    }

    private func handleUserActivity(_ event: NSEvent) {
        guard isEnabled else { return }

        if event.type == .mouseMoved,
           let ignoreMouseActivityUntil,
           Date() < ignoreMouseActivityUntil {
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.restartCountdownAfterUserActivity()
        }
    }

    private func restartCountdownAfterUserActivity() {
        guard isEnabled else { return }

        cycleStartDate = Date()
        updateCountdown()
    }

    private func randomNudgeVector() -> CGVector {
        let minimumDistance: CGFloat = 8
        let maximumDistance: CGFloat = 28
        let similarityThreshold: CGFloat = 0.85

        for _ in 0..<12 {
            let angle = CGFloat.random(in: 0..<(2 * .pi))
            let normalizedDistance = pow(CGFloat.random(in: 0...1), 0.45)
            let distance = minimumDistance + (maximumDistance - minimumDistance) * normalizedDistance
            let candidate = CGVector(
                dx: cos(angle) * distance,
                dy: sin(angle) * distance
            )

            if isDistinctEnough(from: candidate, comparedTo: previousNudgeVector, threshold: similarityThreshold) {
                previousNudgeVector = candidate
                return candidate
            }
        }

        let fallbackAngle = CGFloat.random(in: 0..<(2 * .pi))
        let fallbackDistance = CGFloat.random(in: minimumDistance...maximumDistance)
        let fallback = CGVector(
            dx: cos(fallbackAngle) * fallbackDistance,
            dy: sin(fallbackAngle) * fallbackDistance
        )
        previousNudgeVector = fallback
        return fallback
    }

    private func isDistinctEnough(
        from candidate: CGVector,
        comparedTo previous: CGVector?,
        threshold: CGFloat
    ) -> Bool {
        guard let previous else { return true }

        let candidateMagnitude = hypot(candidate.dx, candidate.dy)
        let previousMagnitude = hypot(previous.dx, previous.dy)
        guard candidateMagnitude > 0, previousMagnitude > 0 else { return true }

        let dotProduct = candidate.dx * previous.dx + candidate.dy * previous.dy
        let cosineSimilarity = dotProduct / (candidateMagnitude * previousMagnitude)
        return abs(cosineSimilarity) < threshold
    }

    private func clampToScreen(_ point: CGPoint) -> CGPoint {
        let screen = screenContainingMouse() ?? NSScreen.main
        let frame = screen?.frame ?? .zero
        let x = min(max(point.x, frame.minX + 1), frame.maxX - 1)
        let y = min(max(point.y, frame.minY + 1), frame.maxY - 1)
        return CGPoint(x: x, y: y)
    }

    private func probePoint(from origin: CGPoint) -> CGPoint {
        let offsets: [CGPoint] = [
            CGPoint(x: 6, y: 0),
            CGPoint(x: -6, y: 0),
            CGPoint(x: 0, y: 6),
            CGPoint(x: 0, y: -6)
        ]

        for offset in offsets {
            let candidate = clampToScreen(CGPoint(x: origin.x + offset.x, y: origin.y + offset.y))
            if hypot(candidate.x - origin.x, candidate.y - origin.y) >= 2 {
                return candidate
            }
        }

        return origin
    }

    /// Returns true if the cursor left its prior position after the move APIs ran.
    @discardableResult
    private func performMove(to point: CGPoint, from start: CGPoint) -> Bool {
        moveCursor(to: point)
        postMouseMoveEvent(to: point)
        // Let AppKit/CoreGraphics publish the new cursor position before sampling it.
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
        let after = NSEvent.mouseLocation
        return hypot(after.x - start.x, after.y - start.y) >= 0.5
    }

    private func moveCursor(to point: CGPoint) {
        guard let screen = screenContainingPoint(point),
              let displayID = screenDisplayID(screen) else {
            CGWarpMouseCursorPosition(point)
            return
        }

        let localPoint = CGPoint(
            x: point.x - screen.frame.minX,
            y: screen.frame.maxY - point.y
        )

        let result = CGDisplayMoveCursorToPoint(displayID, localPoint)
        if result != .success {
            CGWarpMouseCursorPosition(point)
        }
    }

    private func screenContainingMouse() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { screen in
            screen.frame.contains(location)
        }
    }

    private func screenContainingPoint(_ point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { screen in
            screen.frame.contains(point)
        }
    }

    private func screenDisplayID(_ screen: NSScreen) -> CGDirectDisplayID? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }

        return CGDirectDisplayID(number.uint32Value)
    }

    private func postMouseMoveEvent(to point: CGPoint) {
        ignoreMouseActivityUntil = Date().addingTimeInterval(0.2)

        guard let source = CGEventSource(stateID: .hidSystemState),
              let event = CGEvent(
            mouseEventSource: source,
            mouseType: .mouseMoved,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else {
            CGWarpMouseCursorPosition(point)
            return
        }

        event.post(tap: .cghidEventTap)
        CGWarpMouseCursorPosition(point)
    }
}
