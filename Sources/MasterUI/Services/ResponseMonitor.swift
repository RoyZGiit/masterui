import AppKit
import ApplicationServices
import Foundation

// MARK: - ResponseMonitor

/// Monitors the response area of a target AI app for text changes.
/// Uses a dual strategy: AXObserver for notifications + polling as fallback.
class ResponseMonitor {
    static let shared = ResponseMonitor()

    private var observers: [UUID: AXObserver] = [:]
    private var pollingTimers: [UUID: Timer] = [:]
    private var lastKnownValues: [UUID: String] = [:]
    private var stableCounters: [UUID: Int] = [:]
    private var callbacks: [UUID: (String, Bool) -> Void] = [:]

    /// How long the text must remain stable to consider the response "complete".
    private let stableThreshold = 4 // 4 polls x 0.5s = 2 seconds of stability

    /// Polling interval in seconds.
    private let pollInterval: TimeInterval = 0.5

    private init() {}

    // MARK: - Start Monitoring

    /// Start monitoring the response area of a target app.
    /// The callback receives (currentText, isComplete).
    func startMonitoring(
        target: AITarget,
        callback: @escaping (String, Bool) -> Void
    ) {
        // Stop any existing monitoring for this target
        stopMonitoring(targetID: target.id)

        callbacks[target.id] = callback
        lastKnownValues[target.id] = nil
        stableCounters[target.id] = 0

        // Try to set up AXObserver for change notifications
        setupAXObserver(target: target)

        // Always set up polling as a reliable fallback
        startPolling(target: target)
    }

    // MARK: - Stop Monitoring

    /// Stop monitoring a specific target.
    func stopMonitoring(targetID: UUID) {
        // Remove observer
        if let observer = observers.removeValue(forKey: targetID) {
            CFRunLoopRemoveSource(
                CFRunLoopGetCurrent(),
                AXObserverGetRunLoopSource(observer),
                .defaultMode
            )
        }

        // Remove polling timer
        pollingTimers[targetID]?.invalidate()
        pollingTimers.removeValue(forKey: targetID)

        // Clean up state
        lastKnownValues.removeValue(forKey: targetID)
        stableCounters.removeValue(forKey: targetID)
        callbacks.removeValue(forKey: targetID)
    }

    /// Stop all monitoring.
    func stopAll() {
        let targetIDs = Array(observers.keys) + Array(pollingTimers.keys)
        for id in Set(targetIDs) {
            stopMonitoring(targetID: id)
        }
    }

    // MARK: - AXObserver Setup

    private func setupAXObserver(target: AITarget) {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: target.bundleID).first else {
            return
        }

        let pid = app.processIdentifier

        var observer: AXObserver?
        let result = AXObserverCreate(pid, { (_, element, notification, refcon) in
            guard let refcon = refcon else { return }
            let monitor = Unmanaged<ResponseMonitor>.fromOpaque(refcon).takeUnretainedValue()
            // Trigger a poll when we get a notification
            DispatchQueue.main.async {
                monitor.pollAllTargets()
            }
        }, &observer)

        guard result == .success, let obs = observer else { return }

        // Try to find the output element and observe it
        if let outputElement = ElementFinder.shared.findElement(bundleID: target.bundleID, locator: target.outputLocator) {
            let refcon = Unmanaged.passUnretained(self).toOpaque()
            AXObserverAddNotification(obs, outputElement, kAXValueChangedNotification as CFString, refcon)
        }

        // Add to run loop
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(obs), .defaultMode)

        observers[target.id] = obs
    }

    // MARK: - Polling

    private func startPolling(target: AITarget) {
        let timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.pollTarget(target)
        }
        pollingTimers[target.id] = timer
    }

    private func pollAllTargets() {
        // This is called from AXObserver callback - trigger all active polls
        for (targetID, _) in callbacks {
            // We don't have the target object here, so just mark state as potentially changed
            stableCounters[targetID] = 0
        }
    }

    private func pollTarget(_ target: AITarget) {
        guard let callback = callbacks[target.id] else { return }

        // Find the output element
        guard let outputElement = ElementFinder.shared.findElement(bundleID: target.bundleID, locator: target.outputLocator) else {
            return
        }

        // Read current text
        let currentText = AccessibilityService.shared.readAllText(outputElement)

        let previousText = lastKnownValues[target.id]

        if currentText != previousText {
            // Text changed - reset stability counter and report
            stableCounters[target.id] = 0
            lastKnownValues[target.id] = currentText
            callback(currentText, false) // Still streaming
        } else {
            // Text is same as last poll
            let stableCount = (stableCounters[target.id] ?? 0) + 1
            stableCounters[target.id] = stableCount

            if stableCount == stableThreshold && !currentText.isEmpty {
                // Text has been stable long enough - consider response complete
                callback(currentText, true)
            }
        }
    }
}
