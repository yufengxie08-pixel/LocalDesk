# LocalDesk

[![CI](https://github.com/yufengxie08-pixel/LocalDesk/actions/workflows/ci.yml/badge.svg)](https://github.com/yufengxie08-pixel/LocalDesk/actions/workflows/ci.yml)

LocalDesk 是一个 macOS 本地优先的桌面设备控制中心，目标是统一管理摄像头、键鼠和其他桌面外设，并按前台应用自动切换配置。

> 当前状态：Beta 源码已开放。官方 DMG 将在完成 Developer ID 签名、Apple 公证和干净 Mac 安装验证后发布；请勿将本地 ad-hoc 构建作为正式安装包分发。

当前 Beta 0.2.0 已包含：

- SwiftUI 菜单栏应用与主窗口
- 本地 JSON 配置存储
- 按前台应用自动切换的配置方案
- AVFoundation 摄像头发现与 CoreMediaIO 能力枚举、参数写入和回读
- IOHID 鼠标/键盘发现与实时插拔监听
- 仅限中键和侧键的安全按键映射，可随时暂停
- 应用选择器、配置导入导出和诊断报告
- 首次启动引导、权限中心和 About 页面
- 容量受控的本地日志、配置损坏备份与恢复
- 应用图标、DMG 和签名/公证发布脚本
- 配置版本兼容与核心单元测试

## 开发环境

- macOS 13+
- Xcode 16+
- Swift 6.0+
- Apple Silicon 与 Intel Mac（Universal Binary）

## 运行

```bash
swift test
swift run LocalDesk
```

## 构建 macOS App

```bash
chmod +x scripts/build-app.sh
./scripts/build-app.sh
open dist/LocalDesk.app
```

`build-app.sh` 使用 ad-hoc 签名，仅用于当前 Mac 的开发测试。

## 构建 Beta DMG

```bash
./scripts/release.sh
./scripts/verify-release.sh
```

产物包括：

- `dist/LocalDesk.app`
- `dist/LocalDesk-0.2.0.dmg`
- `dist/LocalDesk-0.2.0-release-status.txt`

如果没有 Developer ID，脚本会明确生成 `local-test-ad-hoc` 本地测试版，不会把它标记成正式签名或已公证版本。

公开发布所需的检查项见 [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md)。

## Developer ID 签名与公证

先确认钥匙串中存在可用身份：

```bash
security find-identity -v -p codesigning
```

将公证凭据保存到钥匙串。命令会安全地询问 App 专用密码，不要把密码写入仓库：

```bash
xcrun notarytool store-credentials LocalDeskNotary \
  --apple-id "你的 Apple ID" \
  --team-id "你的 Team ID"
```

执行正式发布：

```bash
export SIGNING_IDENTITY="Developer ID Application: 你的名称 (TEAMID)"
export NOTARY_PROFILE="LocalDeskNotary"
./scripts/release.sh
REQUIRE_NOTARIZATION=1 ./scripts/verify-release.sh
```

签名证书和公证凭据只从钥匙串或环境变量读取，不应提交到源码。

## 权限说明

- 摄像头：用于发现摄像头和读取设备公开的控制项。
- 输入监控：只在启用鼠标中键或侧键映射时使用。
- 辅助功能：只在侧键映射需要发送目标快捷键时使用。

所有权限都可以在首次引导中跳过，之后从“设置 → 权限中心”重新申请。

## 本地数据

- 配置：`~/Library/Application Support/LocalDesk/config.json`
- 日志：`~/Library/Application Support/LocalDesk/Logs/`
- 日志最多占用 6 MB，不记录按键内容或用户输入文本。
- 配置损坏时，原文件会被保存为带时间戳的 `corrupt` 备份。

## 设备兼容性

摄像头参数取决于设备通过 CoreMediaIO 实际公开的能力。部分 Mac 内置摄像头由系统自动管理，因此会显示“暂无可调参数”；LocalDesk 不使用假设备或假成功状态冒充硬件支持。

## 开源许可

LocalDesk 使用 [MIT License](LICENSE)。参与贡献前请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)，安全问题请按 [SECURITY.md](SECURITY.md) 私下报告。
