import AppKit
import AVFoundation
import SwiftUI

struct OnboardingView: View {
    @ObservedObject var model: AppModel

    private let stepTitles = ["欢迎", "隐私", "权限", "设备检测"]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(stepTitles.indices, id: \.self) { index in
                    VStack(spacing: 7) {
                        Circle()
                            .fill(index <= model.onboardingStep ? Color.accentColor : Color.secondary.opacity(0.25))
                            .frame(width: 9, height: 9)
                        Text(stepTitles[index])
                            .font(.caption)
                            .foregroundStyle(index == model.onboardingStep ? .primary : .secondary)
                    }
                    if index < stepTitles.count - 1 {
                        Rectangle()
                            .fill(index < model.onboardingStep ? Color.accentColor : Color.secondary.opacity(0.2))
                            .frame(height: 1)
                    }
                }
            }
            .padding(.horizontal, 46)
            .padding(.top, 28)

            Group {
                switch model.onboardingStep {
                case 1: PrivacyOnboardingStep()
                case 2: PermissionOnboardingStep(model: model)
                case 3: DeviceDetectionOnboardingStep(model: model)
                default: WelcomeOnboardingStep()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(40)

            Divider()
            HStack {
                if model.onboardingStep > 0 {
                    Button("上一步") { model.onboardingStep -= 1 }
                }
                Spacer()
                Button("稍后处理") { model.finishOnboarding() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                Button(model.onboardingStep == stepTitles.count - 1 ? "开始使用" : "继续") {
                    if model.onboardingStep == stepTitles.count - 1 {
                        model.finishOnboarding()
                    } else {
                        model.onboardingStep += 1
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(20)
        }
        .frame(width: 680, height: 520)
        .interactiveDismissDisabled()
        .onAppear { model.onboardingStep = 0 }
    }
}

private struct WelcomeOnboardingStep: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "rectangle.connected.to.line.below")
                .font(.system(size: 62, weight: .medium))
                .foregroundStyle(.tint)
            Text("欢迎使用 LocalDesk")
                .font(.largeTitle.bold())
            Text("把摄像头、鼠标和键盘集中到一个本地控制中心，并根据正在使用的应用自动切换设置。")
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 500)
        }
    }
}

private struct PrivacyOnboardingStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("你的设备数据留在本机")
                .font(.largeTitle.bold())
            OnboardingFact(icon: "network.slash", title: "核心功能不需要网络", detail: "设备发现、参数控制和配置切换都在 Mac 上完成。")
            OnboardingFact(icon: "person.crop.circle.badge.xmark", title: "不需要账号", detail: "LocalDesk 不要求登录，也不会上传设备列表或使用记录。")
            OnboardingFact(icon: "externaldrive", title: "配置由你掌控", detail: "配置保存在 Application Support，并可随时导入、导出或删除。")
        }
        .frame(maxWidth: 540)
    }
}

private struct OnboardingFact: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary)
            }
        }
    }
}

private struct PermissionOnboardingStep: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("只授权你需要的功能")
                .font(.largeTitle.bold())
            Text("摄像头控制和侧键映射彼此独立，暂时跳过任何权限都不影响进入 LocalDesk。")
                .foregroundStyle(.secondary)
            PermissionCard(
                icon: "video",
                title: "摄像头",
                detail: "用于发现摄像头并读取设备公开的控制项。",
                status: PermissionText.camera(model.cameraAuthorizationStatus),
                granted: model.cameraAuthorizationStatus == .authorized,
                actionTitle: PermissionText.cameraAction(model.cameraAuthorizationStatus)
            ) {
                if model.cameraAuthorizationStatus == .denied || model.cameraAuthorizationStatus == .restricted {
                    model.openPrivacySettings(.camera)
                } else {
                    Task { await model.requestCameraAccess() }
                }
            }
            PermissionCard(
                icon: "computermouse",
                title: "输入监控与辅助功能",
                detail: "仅在启用鼠标中键或侧键映射时需要。",
                status: model.inputPermissionsSummary,
                granted: model.inputMappingEngine.inputMonitoringGranted && model.inputMappingEngine.accessibilityGranted,
                actionTitle: "检查并授权"
            ) {
                model.inputMappingEngine.requestPermissions()
            }
        }
    }
}

private struct PermissionCard: View {
    let icon: String
    let title: String
    let detail: String
    let status: String
    let granted: Bool
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
                Label(status, systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(granted ? .green : .orange)
            }
            Spacer()
            Button(actionTitle, action: action)
        }
        .padding(14)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct DeviceDetectionOnboardingStep: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("设备检测完成")
                        .font(.largeTitle.bold())
                    Text("当前发现 " + String(model.devices.count) + " 台设备，之后也可以随时重新扫描。")
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
                Label("暂未发现设备；你仍然可以先进入主界面。", systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(model.devices) { device in
                        HStack {
                            Image(systemName: device.kind == .camera ? "video" : (device.kind == .mouse ? "computermouse" : "keyboard"))
                                .frame(width: 28)
                            VStack(alignment: .leading) {
                                Text(device.name)
                                Text(device.kind.label).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                        .padding(.vertical, 10)
                        if device.id != model.devices.last?.id { Divider() }
                    }
                }
                .padding(.horizontal, 14)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .onAppear { model.rescanDevices() }
    }
}

enum PrivacyPermission {
    case camera
    case inputMonitoring
    case accessibility
}

enum PermissionText {
    static func camera(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "已允许"
        case .denied: return "已拒绝"
        case .restricted: return "受系统限制"
        case .notDetermined: return "尚未询问"
        @unknown default: return "未知状态"
        }
    }

    static func cameraAction(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .denied, .restricted: return "打开系统设置"
        case .authorized: return "重新扫描"
        default: return "申请权限"
        }
    }
}
