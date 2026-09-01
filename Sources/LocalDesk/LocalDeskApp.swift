import SwiftUI
import AVFoundation
import AppKit
import UniformTypeIdentifiers
import LocalDeskCore

@main
struct LocalDeskApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycleDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("LocalDesk", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 900, minHeight: 580)
        }
        .defaultSize(width: 1020, height: 680)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("关于 LocalDesk") { model.isAboutPresented = true }
            }
        }

        MenuBarExtra {
            MenuBarView(model: model)
        } label: {
            Image(systemName: "rectangle.connected.to.line.below")
        }
        .menuBarExtraStyle(.menu)
    }
}

final class AppLifecycleDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        AppLogger.shared.info("app_will_terminate")
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var configuration: LocalDeskConfiguration
    @Published var devices: [DeviceDescriptor] = []
    @Published var activeProfileName = "默认桌面"
    @Published var activeProfileID: UUID?
    @Published var lastError: String?
    @Published var userNotice: String?
    @Published var cameraAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @Published var isOnboardingPresented: Bool
    @Published var onboardingStep = 0
    @Published var isAboutPresented = false
    @Published var requestedSection: String?

    let configStore = ConfigStore()
    let cameraManager = CameraManager()
    let hidDeviceManager = HIDDeviceManager()
    let inputMappingEngine = InputMappingEngine()
    private let profileEngine = ProfileEngine()
    private var appFocusMonitor: AppFocusMonitor?

    init() {
        configuration = (try? configStore.load()) ?? LocalDeskConfiguration()
        isOnboardingPresented = !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        lastError = configStore.recoveryNotice
        userNotice = configStore.recoveryNotice
        activeProfileID = configuration.defaultProfileID
        activeProfileName = configuration.profiles.first(where: { $0.id == activeProfileID })?.name ?? "默认桌面"
        appFocusMonitor = AppFocusMonitor { [weak self] bundleIdentifier in
            self?.updateActiveProfile(for: bundleIdentifier)
        }
        appFocusMonitor?.start()
        hidDeviceManager.onDevicesChanged = { [weak self] in
            self?.mergeDeviceLists()
        }
        hidDeviceManager.start()
        devices = hidDeviceManager.descriptors
        if let activeProfile = configuration.profiles.first(where: { $0.id == activeProfileID }) {
            inputMappingEngine.apply(activeProfile.inputMappings)
        }
        AppLogger.shared.info("app_started", metadata: ["version": AppVersion.displayVersion])
        if configStore.recoveryNotice != nil {
            AppLogger.shared.warning("configuration_recovered")
        }
    }

    var inputPermissionsSummary: String {
        let monitoring = inputMappingEngine.inputMonitoringGranted
        let accessibility = inputMappingEngine.accessibilityGranted
        if monitoring && accessibility { return "均已允许" }
        if !monitoring && !accessibility { return "两项均未允许" }
        return monitoring ? "仍需辅助功能权限" : "仍需输入监控权限"
    }

    func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        isOnboardingPresented = false
        onboardingStep = 0
        AppLogger.shared.info("onboarding_completed")
    }

    func reopenOnboarding() {
        onboardingStep = 0
        isOnboardingPresented = true
    }

    func openPrivacySettings(_ permission: PrivacyPermission) {
        let anchor: String
        switch permission {
        case .camera: anchor = "Privacy_Camera"
        case .inputMonitoring: anchor = "Privacy_ListenEvent"
        case .accessibility: anchor = "Privacy_Accessibility"
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?" + anchor) {
            NSWorkspace.shared.open(url)
        }
    }

    func saveConfiguration() {
        do {
            try configStore.save(configuration)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            userNotice = error.localizedDescription
            AppLogger.shared.error("configuration_save_failed", metadata: ["reason": error.localizedDescription])
        }
    }

    func rescanDevices() {
        cameraManager.rescan()
        hidDeviceManager.rescan()
        mergeDeviceLists()
        lastError = nil
        cameraAuthorizationStatus = cameraManager.authorizationStatus
    }

    private func mergeDeviceLists() {
        let previousIDs = Set(devices.map(\.id))
        let merged = (cameraManager.descriptors + hidDeviceManager.descriptors).sorted {
            if $0.kind == $1.kind { return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            return $0.kind.rawValue < $1.kind.rawValue
        }
        devices = merged
        if Set(merged.map(\.id)) != previousIDs {
            AppLogger.shared.info("devices_changed", metadata: ["count": String(merged.count)])
        }
    }

    func cameraControls(for deviceID: String) -> [CameraControlDescriptor] {
        cameraManager.controls(for: deviceID)
    }

    func setCameraControl(_ value: Double, controlID: String, deviceID: String) {
        do {
            _ = try cameraManager.setControl(value, controlID: controlID, deviceID: deviceID)
            lastError = nil
            objectWillChange.send()
            AppLogger.shared.info("camera_control_applied", metadata: ["control": controlID])
        } catch {
            lastError = error.localizedDescription
            userNotice = error.localizedDescription
            AppLogger.shared.error("camera_control_failed", metadata: ["reason": error.localizedDescription])
        }
    }

    func saveCurrentCameraSettings(deviceID: String) {
        guard let profileID = activeProfileID ?? configuration.defaultProfileID,
              let profileIndex = configuration.profiles.firstIndex(where: { $0.id == profileID }) else {
            lastError = "请先创建或选择一个配置方案。"
            return
        }

        var cameraConfiguration = CameraConfiguration()
        for control in cameraManager.controls(for: deviceID) {
            switch control.capability {
            case .brightness: cameraConfiguration.brightness = control.currentValue
            case .contrast: cameraConfiguration.contrast = control.currentValue
            case .saturation: cameraConfiguration.saturation = control.currentValue
            case .sharpness: cameraConfiguration.sharpness = control.currentValue
            case .exposure: cameraConfiguration.exposure = control.currentValue
            case .focus: cameraConfiguration.focus = control.currentValue
            case .whiteBalance: cameraConfiguration.whiteBalance = control.currentValue
            default: break
            }
        }
        configuration.profiles[profileIndex].cameraConfigurations[deviceID] = cameraConfiguration
        saveConfiguration()
    }

    func requestCameraAccess() async {
        let granted = await cameraManager.requestAccess()
        rescanDevices()
        AppLogger.shared.info("camera_permission_updated", metadata: ["granted": String(granted)])
    }

    func applyCameraConfiguration(_ configuration: CameraConfiguration, to deviceID: String) {
        do {
            try cameraManager.apply(configuration, to: deviceID)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func applyProfile(_ profile: Profile) {
        activeProfileID = profile.id
        activeProfileName = profile.name
        for (deviceID, cameraConfiguration) in profile.cameraConfigurations {
            applyCameraConfiguration(cameraConfiguration, to: deviceID)
        }
        inputMappingEngine.apply(profile.inputMappings)
        AppLogger.shared.info("profile_applied", metadata: ["profile_id": profile.id.uuidString])
    }

    func updateActiveProfile(for bundleIdentifier: String?) {
        if let profile = profileEngine.matchingProfile(bundleIdentifier: bundleIdentifier, configuration: configuration) {
            applyProfile(profile)
        }
    }

    func updateProfile(_ profile: Profile) {
        guard let index = configuration.profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        configuration.profiles[index] = profile
        if activeProfileID == profile.id {
            activeProfileName = profile.name
            inputMappingEngine.apply(profile.inputMappings)
        }
        saveConfiguration()
    }

    func setDefaultProfile(_ profile: Profile) {
        configuration.defaultProfileID = profile.id
        saveConfiguration()
    }

    func chooseApplications(for profile: Profile) {
        let panel = NSOpenPanel()
        panel.title = "选择要绑定的应用"
        panel.prompt = "绑定"
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }

        let selectedBundleIDs = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
        guard !selectedBundleIDs.isEmpty else {
            lastError = "所选应用没有可读取的 Bundle ID。"
            return
        }
        var updated = profile
        updated.bundleIdentifiers = Array(Set(updated.bundleIdentifiers + selectedBundleIDs)).sorted()
        updateProfile(updated)
    }

    func exportConfiguration() {
        let panel = NSSavePanel()
        panel.title = "导出 LocalDesk 配置"
        panel.nameFieldStringValue = "LocalDesk-config.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            try configStore.export(configuration, to: destination)
            lastError = nil
        } catch {
            lastError = "导出失败：\(error.localizedDescription)"
        }
    }

    func importConfiguration() {
        let panel = NSOpenPanel()
        panel.title = "导入 LocalDesk 配置"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let source = panel.url else { return }
        do {
            _ = try configStore.backupCurrentConfiguration(label: "pre-import")
            let imported = try configStore.importConfiguration(from: source)
            guard !imported.profiles.isEmpty else {
                lastError = "导入文件不包含任何配置方案。"
                return
            }
            configuration = imported
            activeProfileID = imported.defaultProfileID ?? imported.profiles.first?.id
            if let profile = imported.profiles.first(where: { $0.id == activeProfileID }) ?? imported.profiles.first {
                applyProfile(profile)
            }
            saveConfiguration()
            AppLogger.shared.info("configuration_imported")
        } catch {
            lastError = "导入失败：文件格式不是有效的 LocalDesk 配置。"
            userNotice = lastError
            AppLogger.shared.error("configuration_import_failed")
        }
    }

    var diagnosticsReport: String {
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let deviceLines = devices.map {
            "- \($0.kind.label): \($0.name) [\($0.isConnected ? "已连接" : "离线")] 能力=\($0.capabilities.map(\.label).sorted().joined(separator: ", "))"
        }.joined(separator: "\n")
        return """
        LocalDesk 诊断报告
        版本: \(AppVersion.displayVersion)
        系统: \(os)
        当前配置: \(activeProfileName)
        自动切换: \(configuration.automaticSwitchingEnabled ? "开启" : "关闭")
        摄像头权限: \(cameraAuthorizationStatus == .authorized ? "已允许" : "未允许")
        输入监控: \(inputMappingEngine.inputMonitoringGranted ? "已允许" : "未允许")
        辅助功能: \(inputMappingEngine.accessibilityGranted ? "已允许" : "未允许")
        配置文件: \(configStore.fileURL.path)
        日志目录: \(AppLogger.shared.store.directoryURL.path)
        日志大小: \(AppLogger.shared.store.totalSize) bytes
        设备数: \(devices.count)
        \(deviceLines.isEmpty ? "- 未发现设备" : deviceLines)
        最近错误: \(lastError ?? "无")
        """
    }

    func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnosticsReport, forType: .string)
    }

    func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.title = "保存诊断报告"
        panel.nameFieldStringValue = "LocalDesk-diagnostics.txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            let exported = diagnosticsReport + "\n\n运行日志\n" + AppLogger.shared.store.exportText()
            try exported.write(to: destination, atomically: true, encoding: .utf8)
            lastError = nil
            AppLogger.shared.info("diagnostics_exported")
        } catch {
            lastError = "诊断报告保存失败：\(error.localizedDescription)"
        }
    }

    func showConfigurationInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([configStore.fileURL])
    }
}

struct MenuBarView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("当前配置：\(model.activeProfileName)")
        Divider()
        ForEach(model.configuration.profiles) { profile in
            Button(profile.name) { model.applyProfile(profile) }
        }
        Divider()
        Toggle("暂停按键映射", isOn: Binding(
            get: { model.inputMappingEngine.isPaused },
            set: { model.inputMappingEngine.isPaused = $0 }
        ))
        Button("打开 LocalDesk") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "main")
        }
        Button("重新扫描设备") { model.rescanDevices() }
        Button("退出") { NSApplication.shared.terminate(nil) }
    }
}
