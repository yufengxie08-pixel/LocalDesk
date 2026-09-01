import AppKit
import SwiftUI

struct AboutView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 92, height: 92)
            Text("LocalDesk")
                .font(.largeTitle.bold())
            Text("本地优先的桌面设备控制中心")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("版本 " + AppVersion.displayVersion)
                .font(.callout.monospacedDigit())
            Label("核心功能不需要网络，设备配置保存在本机", systemImage: "lock.shield")
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            HStack {
                Button("显示配置文件") { model.showConfigurationInFinder() }
                Button("打开诊断") {
                    model.isAboutPresented = false
                    model.requestedSection = "diagnostics"
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 8)
        }
        .padding(34)
        .frame(width: 470, height: 410)
    }
}
