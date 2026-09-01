import AppKit
@preconcurrency import ApplicationServices
@preconcurrency import CoreGraphics
import LocalDeskCore

@MainActor
final class InputMappingEngine: ObservableObject {
    @Published private(set) var isRunning = false
    @Published var isPaused = false {
        didSet {
            AppLogger.shared.info(isPaused ? "input_mapping_paused" : "input_mapping_resumed")
            rebuildEventTap()
        }
    }
    @Published private(set) var inputMonitoringGranted = CGPreflightListenEventAccess()
    @Published private(set) var accessibilityGranted = AXIsProcessTrusted()

    private var mappings: [String: String] = [:]
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    func apply(_ newMappings: [InputMapping]) {
        mappings = Dictionary(newMappings.map { ($0.source, $0.action) }, uniquingKeysWith: { _, newest in newest })
        refreshPermissionStatus()
        rebuildEventTap()
    }

    func requestPermissions() {
        requestInputMonitoring()
        requestAccessibility()
        refreshPermissionStatus()
    }

    func requestInputMonitoring() {
        _ = CGRequestListenEventAccess()
        refreshPermissionStatus()
    }

    func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refreshPermissionStatus()
    }

    func refreshPermissionStatus() {
        let nextMonitoring = CGPreflightListenEventAccess()
        let nextAccessibility = AXIsProcessTrusted()
        if nextMonitoring != inputMonitoringGranted || nextAccessibility != accessibilityGranted {
            AppLogger.shared.info("input_permissions_changed", metadata: [
                "input_monitoring": String(nextMonitoring),
                "accessibility": String(nextAccessibility)
            ])
        }
        inputMonitoringGranted = nextMonitoring
        accessibilityGranted = nextAccessibility
    }

    private func rebuildEventTap() {
        stop()
        guard !isPaused, !mappings.isEmpty, inputMonitoringGranted else { return }

        let mask = (CGEventMask(1) << CGEventType.otherMouseDown.rawValue)
            | (CGEventMask(1) << CGEventType.otherMouseUp.rawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let owner = Unmanaged<InputMappingEngine>.fromOpaque(context).takeUnretainedValue()
                return MainActor.assumeIsolated {
                    owner.handle(type: type, event: event)
                }
            },
            userInfo: context
        ) else {
            inputMonitoringGranted = CGPreflightListenEventAccess()
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
        isRunning = true
        AppLogger.shared.info("input_mapping_started", metadata: ["mapping_count": String(mappings.count)])
    }

    private func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        runLoopSource = nil
        eventTap = nil
        isRunning = false
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .otherMouseDown || type == .otherMouseUp else {
            return Unmanaged.passUnretained(event)
        }
        let button = event.getIntegerValueField(.mouseEventButtonNumber)
        let source = "mouse.button\(button)"
        guard let action = mappings[source] else { return Unmanaged.passUnretained(event) }

        if type == .otherMouseDown {
            perform(action)
        }
        return nil
    }

    private func perform(_ action: String) {
        switch action {
        case "shortcut.missionControl": postKey(126, flags: .maskControl)
        case "shortcut.appExpose": postKey(125, flags: .maskControl)
        case "shortcut.copy": postKey(8, flags: .maskCommand)
        case "shortcut.paste": postKey(9, flags: .maskCommand)
        case "shortcut.previousTab": postKey(48, flags: [.maskCommand, .maskShift])
        case "shortcut.nextTab": postKey(48, flags: .maskCommand)
        default: break
        }
    }

    private func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags) {
        guard accessibilityGranted else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyDown?.flags = flags
        keyUp?.flags = flags
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}

enum InputMappingCatalog {
    static let sources: [(id: String, label: String)] = [
        ("mouse.button2", "鼠标中键"),
        ("mouse.button3", "鼠标侧键 1"),
        ("mouse.button4", "鼠标侧键 2")
    ]

    static let actions: [(id: String, label: String)] = [
        ("shortcut.missionControl", "调度中心"),
        ("shortcut.appExpose", "当前应用窗口"),
        ("shortcut.copy", "复制"),
        ("shortcut.paste", "粘贴"),
        ("shortcut.previousTab", "上一个标签页"),
        ("shortcut.nextTab", "下一个标签页")
    ]

    static func sourceLabel(_ id: String) -> String {
        sources.first(where: { $0.id == id })?.label ?? id
    }

    static func actionLabel(_ id: String) -> String {
        actions.first(where: { $0.id == id })?.label ?? id
    }
}
