import SwiftUI
import AVFoundation
import AppKit
import LocalDeskCore

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var selection = "devices"

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("设备", systemImage: "rectangle.3.group")
                    .tag("devices")
                Label("配置方案", systemImage: "slider.horizontal.3")
                    .tag("profiles")
                Label("诊断", systemImage: "waveform.path.ecg")
                    .tag("diagnostics")
                Label("设置", systemImage: "gearshape")
                    .tag("settings")
            }
            .navigationTitle("LocalDesk")
            .listStyle(.sidebar)
        } detail: {
            Group {
                switch selection {
                case "profiles": ProfilesView(model: model)
                case "diagnostics": DiagnosticsView(model: model)
                case "settings": SettingsView(model: model)
                default: DevicesView(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $model.isOnboardingPresented) {
            OnboardingView(model: model)
        }
        .sheet(isPresented: $model.isAboutPresented) {
            AboutView(model: model)
        }
        .onChange(of: model.requestedSection) { requestedSection in
            guard let requestedSection else { return }
            selection = requestedSection
            model.requestedSection = nil
        }
        .alert("LocalDesk 需要注意", isPresented: Binding(
            get: { model.userNotice != nil },
            set: { if !$0 { model.userNotice = nil } }
        )) {
            Button("知道了", role: .cancel) { model.userNotice = nil }
        } message: {
            Text(model.userNotice ?? "")
        }
    }
}

struct DevicesView: View {
    @ObservedObject var model: AppModel
    @State private var selectedDeviceID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("设备")
                        .font(.largeTitle.bold())
                    Text("LocalDesk 会把支持的桌面设备集中显示在这里。")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    model.rescanDevices()
                } label: {
                    Label("重新扫描", systemImage: "arrow.clockwise")
                }
            }

            if model.devices.isEmpty {
                EmptyDevicesView(authorizationStatus: model.cameraAuthorizationStatus)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    List(model.devices, selection: $selectedDeviceID) { device in
                        DeviceRow(device: device)
                            .tag(device.id)
                    }
                    .frame(minWidth: 280, idealWidth: 320)

                    if let device = model.devices.first(where: { $0.id == selectedDeviceID }) {
                        DeviceDetailView(device: device, model: model)
                            .frame(minWidth: 380)
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "rectangle.connected.to.line.below")
                                .font(.system(size: 36))
                                .foregroundStyle(.secondary)
                            Text("选择一个设备")
                                .font(.title3.bold())
                            Text("查看设备能力和可用控制项。")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator.opacity(0.7)))
            }
        }
        .padding(28)
        .task {
            model.rescanDevices()
        }
        .onChange(of: model.devices.map(\.id)) { ids in
            if selectedDeviceID == nil || !ids.contains(selectedDeviceID ?? "") {
                selectedDeviceID = ids.first
            }
        }
        .onAppear {
            selectedDeviceID = model.devices.first?.id
        }
    }
}

struct EmptyDevicesView: View {
    let authorizationStatus: AVAuthorizationStatus

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.connected.to.line.below")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text("暂未发现设备")
                .font(.title3.bold())
            Text(authorizationStatus == .denied ? "LocalDesk 没有摄像头权限。" : "连接摄像头后，点击重新扫描。")
                .foregroundStyle(.secondary)
            if authorizationStatus == .denied {
                Button {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("打开系统设置", systemImage: "gearshape")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DeviceRow: View {
    let device: DeviceDescriptor

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: device.kind == .camera ? "video" : (device.kind == .mouse ? "computermouse" : "keyboard"))
                .font(.title2)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(device.name)
                    .font(.headline)
                Text(device.kind.label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Label(device.isConnected ? "已连接" : "离线", systemImage: device.isConnected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(device.isConnected ? .green : .secondary)
        }
        .padding(.vertical, 8)
    }
}

struct DeviceDetailView: View {
    let device: DeviceDescriptor
    @ObservedObject var model: AppModel

    private var controls: [CameraControlDescriptor] {
        model.cameraControls(for: device.id)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: device.kind == .camera ? "video.fill" : (device.kind == .mouse ? "computermouse.fill" : "keyboard.fill"))
                        .font(.system(size: 24))
                        .foregroundStyle(.tint)
                        .frame(width: 44, height: 44)
                        .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(device.name)
                            .font(.title2.bold())
                        Text(device.kind == .camera
                            ? "已连接 · " + String(controls.count) + " 个可用控制项"
                            : "已连接 · " + device.kind.label)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                Divider()

                if let error = device.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                } else if device.kind != .camera {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(device.kind == .mouse ? "支持安全侧键映射" : "键盘已被系统识别", systemImage: "checkmark.seal")
                            .font(.headline)
                        Text(device.kind == .mouse
                            ? "LocalDesk 只接管中键与侧键，不会拦截左键、右键或移动操作。请在配置方案中添加映射。"
                            : "首个版本不会拦截普通键盘输入；快捷操作由鼠标侧键触发，避免影响正常打字。")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(18)
                    .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
                } else if controls.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("这台摄像头没有公开可调参数", systemImage: "info.circle")
                            .font(.headline)
                        Text("设备仍可正常使用。部分内置摄像头由 macOS 自动管理，不允许第三方应用直接修改曝光、对焦等参数。")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(18)
                    .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
                } else {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("画面参数")
                            .font(.headline)
                        ForEach(controls) { control in
                            CameraControlRow(control: control) { value in
                                model.setCameraControl(value, controlID: control.id, deviceID: device.id)
                            }
                        }
                    }

                    Divider()

                    HStack {
                        Text("保存后，切换到当前配置方案时会自动恢复这些参数。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            model.saveCurrentCameraSettings(deviceID: device.id)
                        } label: {
                            Label("保存到当前配置", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding(24)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.32))
    }
}

struct CameraControlRow: View {
    let control: CameraControlDescriptor
    let onCommit: (Double) -> Void
    @State private var value: Double

    init(control: CameraControlDescriptor, onCommit: @escaping (Double) -> Void) {
        self.control = control
        self.onCommit = onCommit
        _value = State(initialValue: control.currentValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(control.displayName)
                Spacer()
                Text(value.formatted(.percent.precision(.fractionLength(0))))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: 0...1) { editing in
                if !editing { onCommit(value) }
            }
            .disabled(!control.isWritable)
            if !control.isWritable {
                Text("设备将此参数标记为只读")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ProfilesView: View {
    @ObservedObject var model: AppModel
    @State private var selectedProfileID: UUID?

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("配置方案")
                        .font(.largeTitle.bold())
                    Text("为不同应用保存设备设置和快捷键。")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    model.configuration.profiles.append(Profile(name: "新配置"))
                    model.saveConfiguration()
                } label: {
                    Label("新建配置", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }

            List {
                ForEach(model.configuration.profiles) { profile in
                    Button {
                        selectedProfileID = profile.id
                    } label: {
                        HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(profile.name)
                                .font(.headline)
                            Text(profile.bundleIdentifiers.isEmpty ? "未绑定应用" : profile.bundleIdentifiers.joined(separator: ", "))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if profile.id == model.configuration.defaultProfileID {
                            Text("默认")
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.quaternary, in: Capsule())
                        }
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 6)
                }
                .onDelete { offsets in
                    model.configuration.profiles.remove(atOffsets: offsets)
                    if let defaultProfileID = model.configuration.defaultProfileID,
                       !model.configuration.profiles.contains(where: { $0.id == defaultProfileID }) {
                        model.configuration.defaultProfileID = model.configuration.profiles.first?.id
                    }
                    model.saveConfiguration()
                }
            }
            }
            .frame(minWidth: 320, maxWidth: 420, maxHeight: .infinity)
            .padding(28)

            Divider()

            if let selectedProfileID,
               let profile = model.configuration.profiles.first(where: { $0.id == selectedProfileID }) {
                ProfileEditorView(profile: profile, model: model)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("选择一个配置方案")
                        .font(.title3.bold())
                    Text("在这里绑定应用并编辑配置。")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            selectedProfileID = selectedProfileID ?? model.configuration.profiles.first?.id
        }
    }
}

struct ProfileEditorView: View {
    let profile: Profile
    @ObservedObject var model: AppModel
    @State private var bundleIDsText = ""
    @State private var name = ""

    var body: some View {
        Form {
            Section("基本信息") {
                TextField("配置名称", text: $name)
                Toggle("启用此配置", isOn: Binding(
                    get: { profile.isEnabled },
                    set: { newValue in update { $0.isEnabled = newValue } }
                ))
                Button {
                    model.setDefaultProfile(profile)
                } label: {
                    Label("设为默认配置", systemImage: "checkmark.circle")
                }
            }
            Section("绑定应用") {
                TextField("Bundle ID（多个用逗号分隔）", text: $bundleIDsText)
                    .textFieldStyle(.roundedBorder)
                Button {
                    model.chooseApplications(for: profile)
                } label: {
                    Label("从应用程序中选择", systemImage: "app.badge")
                }
                Text("例如：us.zoom.xos, com.obsproject.obs-studio")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("当前状态") {
                LabeledContent("是否当前配置", value: model.activeProfileID == profile.id ? "是" : "否")
                LabeledContent("摄像头参数", value: profile.cameraConfigurations.isEmpty ? "未配置" : "已配置")
            }
            Section("鼠标侧键") {
                if profile.inputMappings.isEmpty {
                    Text("尚未添加映射。LocalDesk 不会接管左键和右键。")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(profile.inputMappings.indices), id: \.self) { index in
                    HStack {
                        Picker("按键", selection: mappingBinding(index: index, keyPath: \.source)) {
                            ForEach(InputMappingCatalog.sources, id: \.id) { item in
                                Text(item.label).tag(item.id)
                            }
                        }
                        Picker("动作", selection: mappingBinding(index: index, keyPath: \.action)) {
                            ForEach(InputMappingCatalog.actions, id: \.id) { item in
                                Text(item.label).tag(item.id)
                            }
                        }
                        Button(role: .destructive) {
                            update { $0.inputMappings.remove(at: index) }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Button {
                    update { $0.inputMappings.append(InputMapping(source: "mouse.button3", action: "shortcut.missionControl")) }
                } label: {
                    Label("添加映射", systemImage: "plus")
                }
            }
        }
        .formStyle(.grouped)
        .padding(28)
        .navigationTitle(profile.name)
        .onAppear {
            name = profile.name
            bundleIDsText = profile.bundleIdentifiers.joined(separator: ", ")
        }
        .onChange(of: name) { newValue in
            update { $0.name = newValue }
        }
        .onChange(of: bundleIDsText) { newValue in
            update { $0.bundleIdentifiers = newValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } }
        }
        .onChange(of: profile.bundleIdentifiers) { bundleIdentifiers in
            let updatedText = bundleIdentifiers.joined(separator: ", ")
            if bundleIDsText != updatedText { bundleIDsText = updatedText }
        }
    }

    private func update(_ mutate: (inout Profile) -> Void) {
        var updated = profile
        mutate(&updated)
        model.updateProfile(updated)
    }

    private func mappingBinding(index: Int, keyPath: WritableKeyPath<InputMapping, String>) -> Binding<String> {
        Binding(
            get: {
                guard profile.inputMappings.indices.contains(index) else { return "" }
                return profile.inputMappings[index][keyPath: keyPath]
            },
            set: { newValue in
                update { updated in
                    guard updated.inputMappings.indices.contains(index) else { return }
                    updated.inputMappings[index][keyPath: keyPath] = newValue
                }
            }
        )
    }
}

struct DiagnosticsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("诊断")
                .font(.largeTitle.bold())
            Form {
                LabeledContent("LocalDesk 版本", value: AppVersion.displayVersion)
                LabeledContent("设备数量", value: "\(model.devices.count)")
                LabeledContent("当前配置", value: model.activeProfileName)
                LabeledContent("配置文件", value: model.configStore.fileURL.path)
            }
            HStack {
                Button {
                    model.copyDiagnostics()
                } label: {
                    Label("复制报告", systemImage: "doc.on.doc")
                }
                Button {
                    model.exportDiagnostics()
                } label: {
                    Label("保存报告", systemImage: "square.and.arrow.down")
                }
                Button {
                    model.showConfigurationInFinder()
                } label: {
                    Label("显示配置文件", systemImage: "folder")
                }
            }
            if let lastError = model.lastError {
                Label(lastError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
            Spacer()
        }
        .padding(28)
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("自动切换") {
                Toggle("根据前台应用自动切换配置", isOn: $model.configuration.automaticSwitchingEnabled)
                    .onChange(of: model.configuration.automaticSwitchingEnabled) { _ in
                        model.saveConfiguration()
                    }
            }
            Section("隐私") {
                LabeledContent("网络访问", value: "核心功能不需要网络")
                LabeledContent("数据位置", value: "仅保存在本机")
            }
            Section("配置数据") {
                HStack {
                    Button("导出配置") { model.exportConfiguration() }
                    Button("导入配置") { model.importConfiguration() }
                }
                Text("导入会替换当前配置；建议先导出一份备份。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            PermissionCenterSettingsView(model: model)
            Section("使用帮助") {
                Button("重新打开使用引导") { model.reopenOnboarding() }
                Button("关于 LocalDesk") { model.isAboutPresented = true }
            }
        }
        .formStyle(.grouped)
        .padding(28)
    }
}

struct PermissionCenterSettingsView: View {
    @ObservedObject var model: AppModel

    private var engine: InputMappingEngine { model.inputMappingEngine }

    var body: some View {
        Section("权限中心") {
            HStack {
                LabeledContent("摄像头", value: PermissionText.camera(model.cameraAuthorizationStatus))
                Button(PermissionText.cameraAction(model.cameraAuthorizationStatus)) {
                    if model.cameraAuthorizationStatus == .denied || model.cameraAuthorizationStatus == .restricted {
                        model.openPrivacySettings(.camera)
                    } else {
                        Task { await model.requestCameraAccess() }
                    }
                }
            }
            Toggle("暂停所有按键映射", isOn: Binding(
                get: { engine.isPaused },
                set: { engine.isPaused = $0 }
            ))
            HStack {
                LabeledContent("输入监控", value: engine.inputMonitoringGranted ? "已允许" : "未允许")
                Button(engine.inputMonitoringGranted ? "打开设置" : "申请权限") {
                    if engine.inputMonitoringGranted { model.openPrivacySettings(.inputMonitoring) }
                    else { engine.requestInputMonitoring() }
                }
            }
            HStack {
                LabeledContent("辅助功能", value: engine.accessibilityGranted ? "已允许" : "未允许")
                Button(engine.accessibilityGranted ? "打开设置" : "申请权限") {
                    if engine.accessibilityGranted { model.openPrivacySettings(.accessibility) }
                    else { engine.requestAccessibility() }
                }
            }
            Button("刷新全部权限状态") {
                engine.refreshPermissionStatus()
                model.rescanDevices()
            }
            Text("只有启用侧键映射时才需要这些权限；相机控制和设备发现不受影响。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
