# 参与 LocalDesk

感谢你愿意帮助改进 LocalDesk。

## 开发要求

- macOS 13 或更高版本
- Swift 6 或更高版本
- Xcode 16 或更高版本

## 开发流程

1. Fork 仓库并从 `main` 创建功能分支。
2. 保持改动聚焦，不提交 `.build/`、`dist/`、证书或公证凭据。
3. 为核心逻辑补充测试。
4. 在提交 Pull Request 前运行：

```bash
swift test
./scripts/build-universal.sh
zsh -n scripts/*.sh
```

## 设备相关改动

- 不得用假设备或假成功状态代替真实硬件结果。
- 新增摄像头控制前，需说明设备公开的 CoreMediaIO 能力。
- 输入映射不得拦截鼠标左键、右键或普通键盘输入。
- 无法在本机验证的硬件必须在 Pull Request 中明确标记。

## Pull Request

请说明改动目的、测试结果、权限变化以及实际验证过的设备。界面改动请附截图。
