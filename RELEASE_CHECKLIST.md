# LocalDesk 发布检查清单

## 代码

- [ ] `swift test` 全部通过
- [ ] Release 构建通过
- [ ] 可执行文件同时包含 `arm64` 与 `x86_64`
- [ ] 没有密钥、证书、Token 或用户数据进入 Git
- [ ] 版本号、构建号和 CHANGELOG 已更新

## 硬件与权限

- [ ] 在干净 Mac 上验证首次启动引导
- [ ] 验证摄像头拒绝、允许和系统限制状态
- [ ] 验证输入监控与辅助功能未授权状态
- [ ] 验证设备插拔不会导致崩溃
- [ ] 至少验证一台公开可调参数的外接 UVC 摄像头

## 分发

- [ ] 使用 Developer ID Application 签名
- [ ] Hardened Runtime 和安全时间戳已启用
- [ ] DMG 已提交 Apple 公证
- [ ] `stapler validate` 通过
- [ ] `spctl --assess` 通过
- [ ] DMG 可挂载且包含 App、Applications 快捷方式和安装说明
- [ ] SHA-256 与 Release Asset 一致

## GitHub Release

- [ ] 使用语义版本 Tag，例如 `v0.2.0-beta.1`
- [ ] Release 标记为 Pre-release
- [ ] 附加已签名且公证的 DMG
- [ ] Release Notes 包含支持架构、最低系统和已知限制
- [ ] 从另一台 Mac 下载 GitHub Release 并完成安装测试
