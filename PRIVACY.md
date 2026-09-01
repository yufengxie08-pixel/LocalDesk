# LocalDesk 隐私说明

LocalDesk 是本地优先的 macOS 桌面设备控制中心。

## 网络

核心功能不需要网络。当前版本不包含账号、云同步、遥测、广告或使用行为上报。

## 本地数据

- 配置保存在 `~/Library/Application Support/LocalDesk/config.json`。
- 运行日志保存在 `~/Library/Application Support/LocalDesk/Logs/`。
- 日志总量最多 6 MB，不记录按键内容、用户输入文本或文件内容。

## 权限

- 摄像头：发现摄像头并读取设备公开的控制项。
- 输入监控：识别用户主动配置的鼠标中键和侧键。
- 辅助功能：发送用户配置的目标快捷键。

所有权限都可以跳过。未授予输入监控或辅助功能权限时，摄像头与设备发现仍可使用。
