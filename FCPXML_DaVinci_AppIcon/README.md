# AppIcon 使用说明

本包包含：

- `AppIcon_1024.png`：1024×1024 高分辨率图标预览
- `AppIcon.iconset/`：macOS iconset 目录
- `AppIcon.icns`：macOS App 可用图标文件

## 放入 Xcode 工程

推荐方式：

1. 打开 Xcode 工程；
2. 找到 `Assets.xcassets`；
3. 新建 `AppIcon`；
4. 将 `AppIcon.iconset` 里的各尺寸 PNG 分别拖入对应位置。

或者在工程 Build Settings / Info 里直接指定 `.icns` 文件。

## 用 iconutil 重新生成 icns

如果需要在 macOS 终端重新生成：

```bash
iconutil -c icns AppIcon.iconset -o AppIcon.icns
```

## 设计说明

图标使用抽象化的 FCPXML 卡片和媒体池色轮卡片斜向重叠设计，并在下方分别标注：

- FCPXML
- 媒体池

没有直接复制 Final Cut Pro 或 DaVinci Resolve 的官方商标图形。
