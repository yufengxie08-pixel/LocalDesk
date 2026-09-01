import AppKit

@MainActor
final class AppFocusMonitor {
    private var observer: NSObjectProtocol?
    private let onBundleIdentifierChange: @MainActor @Sendable (String?) -> Void

    init(onBundleIdentifierChange: @escaping @MainActor @Sendable (String?) -> Void) {
        self.onBundleIdentifierChange = onBundleIdentifierChange
    }

    func start() {
        guard observer == nil else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleIdentifier = application?.bundleIdentifier
            Task { @MainActor [weak self] in
                self?.onBundleIdentifierChange(bundleIdentifier)
            }
        }

        onBundleIdentifierChange(NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    }

}
