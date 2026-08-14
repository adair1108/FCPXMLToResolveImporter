# FCPXMLToResolveImporter 完整工程版 v1.1

此版本新增支持：

```text
.fcpxmld
```

也就是 FCP 导出的 FCPXMLD 包目录。

## 支持的输入

点击“加载 FCPXML”后，可以选择：

```text
xxx.fcpxml
xxx.fcpxmld
```

如果选择 `.fcpxmld`，脚本会在包目录内自动寻找实际可解析的 FCPXML/XML 文件。

查找顺序：

1. 包目录内直接的 `.fcpxml`
2. 包目录内递归查找 `.fcpxml`
3. 包目录内递归查找根节点为 `<fcpxml>` 的 `.xml`

生成的清单会放在 `.fcpxmld` 同级目录旁边，例如：

```text
/项目/短剧.fcpxmld
/项目/短剧.media_list.txt
```

## 一键打包

```bash
cd FCPXMLToResolveImporter_FullProject_FCPXMLD
./build_app.command
```

生成：

```text
dist/FCPXMLto达芬奇媒体池.app
```

## Cursor 中调试

测试普通 `.fcpxml`：

```bash
python3 FCPXMLToResolveImporter/resolve_importer.py extract /你的路径/项目.fcpxml
```

测试 `.fcpxmld`：

```bash
python3 FCPXMLToResolveImporter/resolve_importer.py extract /你的路径/项目.fcpxmld
```

测试 `.fcpxmld` + 链接原始文件：

```bash
python3 FCPXMLToResolveImporter/resolve_importer.py extract /你的路径/项目.fcpxmld --link-original /你的原始素材目录
```

导入 DaVinci：

```bash
python3 FCPXMLToResolveImporter/resolve_importer.py import /你的路径/项目.media_list.txt
```

检查已有清单：

```bash
python3 FCPXMLToResolveImporter/resolve_importer.py inspect-list /你的路径/项目.media_list.txt
```


## v1.2 修改

修复 macOS 文件选择器无法选择 `.fcpxmld` 的问题。

原因是 `.fcpxmld` 在 macOS 中通常被识别为“包目录”，如果使用 `allowedContentTypes` 或 `allowedFileTypes` 过滤，`NSOpenPanel` 可能会把它显示为不可选。

新版改为：

1. 允许选择文件和目录；
2. 不使用系统级扩展名过滤；
3. 选择后由 App 手动判断扩展名是否为：
   - `.fcpxml`
   - `.fcpxmld`

这样 `.fcpxmld` 可以正常被选中。


## v1.3 修改

修复部分 Xcode / macOS SDK 下编译失败的问题。

v1.2 中曾使用：

```swift
panel.allowedContentTypes = nil
panel.allowedFileTypes = nil
```

某些 SDK 下 `allowedContentTypes` 不能赋值为 `nil`，会导致 `CompileSwift` 失败。

v1.3 改为直接不设置 `allowedContentTypes / allowedFileTypes`，仍然保留：

```swift
panel.canChooseFiles = true
panel.canChooseDirectories = true
panel.treatsFilePackagesAsDirectories = false
```

并在用户选择后手动判断扩展名是否为 `.fcpxml` 或 `.fcpxmld`。


## v1.4 修改

修复部分机器上 App 找不到 `DaVinciResolveScript.py` 的问题。

新版 `resolve_importer.py` 会自动检查多个常见位置：

```text
/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting/Modules
/Applications/DaVinci Resolve/DaVinci Resolve.app/Contents/Libraries/Fusion/Modules
/Applications/DaVinci Resolve Studio/DaVinci Resolve.app/Contents/Libraries/Fusion/Modules
/Applications/DaVinci Resolve.app/Contents/Libraries/Fusion/Modules
```

并会递归搜索：

```text
/Library/Application Support/Blackmagic Design
/Applications/DaVinci Resolve
/Applications/DaVinci Resolve Studio
/Applications/DaVinci Resolve.app
```

如果仍然失败，App 会把所有检查过的路径显示出来。


## v1.5 修改

修复 Studio 版 Resolve 的 `fusionscript.so` 路径问题。

如果只找到：

```text
DaVinciResolveScript.py
```

但导入时报错：

```text
dlopen(/Applications/DaVinci Resolve/DaVinci Resolve.app/Contents/Libraries/Fusion/fusionscript.so): no such file
```

说明当前安装的是：

```text
/Applications/DaVinci Resolve Studio.app
```

而脚本模块默认去找普通版：

```text
/Applications/DaVinci Resolve/DaVinci Resolve.app
```

v1.5 会在导入 DaVinciResolveScript 之前自动寻找 `fusionscript.so`，并设置：

```text
RESOLVE_SCRIPT_LIB
DYLD_LIBRARY_PATH
```

优先使用 Studio.app 内的库路径。


## v1.6 修改

修复 v1.5 中 `RESOLVE_SCRIPT_LIB` 设置错误的问题。

实测 DaVinciResolveScript.py 需要：

```bash
export RESOLVE_SCRIPT_LIB="/Applications/DaVinci Resolve Studio.app/Contents/Libraries/Fusion/fusionscript.so"
```

也就是 **fusionscript.so 的完整文件路径**，不是：

```bash
/Applications/DaVinci Resolve Studio.app/Contents/Libraries/Fusion
```

v1.6 已自动改为写入完整文件路径，同时 `DYLD_LIBRARY_PATH` 仍使用 `fusionscript.so` 所在目录。


## v1.7 修改

新增“未完全链接时持续弹窗重新选择目录”功能。

当勾选“链接原始文件”后，如果第一次选择的原始文件目录没有完全匹配：

1. App 会弹出提示窗口；
2. 窗口内有可滚动文本框，显示：
   - 未链接文件名
   - FCPXML 中的原路径
3. 下方有两个按钮：
   - 选择目录链接
   - 跳过（沿用原路径）
4. 点击“选择目录链接”后，只会针对剩余未链接文件继续匹配；
5. 如果仍有未链接项，会继续弹窗；
6. 直到全部链接成功，或用户点击“跳过”。

跳过后，未链接文件会继续沿用 FCPXML 中的原路径写入 `media_list.txt`。


## v1.8 修改

新增“选择已有清单”按钮。

现在可以不重新加载 FCPXML / FCPXMLD，直接选择之前生成的 `.media_list.txt` 或普通 `.txt` 素材清单。App 会先检查清单数量、本地存在数量和缺失数量，然后可以点击“导入 DaVinci”发送给 DaVinci Resolve。


## 本次合并修改说明

此版本是在你上传的 `FCPXMLToResolveImporter.zip` 代码基础上合并修改，不是基于之前另一个压缩包重建。

已合并功能：

### 1. v1.8：生成文件统一归并目录

加载 FCPXML / FCPXMLD 后，不再在原目录散落生成多个 txt，而是在旁边创建：

```text
项目名_resolve_import/
```

并将所有生成文件放入其中：

```text
项目名_resolve_import/
├── 项目名.media_list.txt
├── 项目名.ordered_media_list.txt
├── 项目名.unmatched_proxy_media.txt
├── 项目名.duplicate_original_media.txt
├── 项目名.media_list.missing_media.txt
├── 项目名.ordered_media_list.timeline_missing_media.txt
└── 项目名.ordered_media_list.timeline_unresolved_items.txt
```

### 2. v1.9：完整素材顺序时间线

界面新增：

```text
☑ 导入后创建完整素材顺序时间线
☑ 时间线素材按首次出现顺序去重
```

创建时间线时，只按照 FCPXML 中素材出现顺序，把素材完整片段追加到 DaVinci 时间线，不保留 FCP 的剪辑点、入点、出点、duration、转场或 gap。

### 3. v2.0：图标打包

保留并使用你当前压缩包中的：

```text
FCPXMLToResolveImporter/AppIcon.icns
```

`project.pbxproj` 和 `Info.plist` 已经包含图标配置。新增的 `build_app.command` 会检查图标文件并执行打包。

## 打包方式

```bash
cd FCPXMLToResolveImporter_base_plus_v20
chmod +x build_app.command
./build_app.command
```

如果仍提示权限：

```bash
bash build_app.command
```

生成结果：

```text
dist/FCPXMLToResolveImporter.app
```


## v2.1 修改

在界面中增加独立按钮：

```text
创建完整素材时间线
```

这样不需要只依赖“导入后创建完整素材顺序时间线”的勾选项。

使用方式：

1. 先点击“加载 FCPXML”；
2. 软件生成 `ordered_media_list.txt`；
3. 点击“创建完整素材时间线”；
4. DaVinci 中会按 FCPXML 素材出现顺序，把完整素材片段依次放入新时间线。

仍然保留“导入 DaVinci”按钮中的自动创建时间线逻辑。


## v2.2 修改

修复“创建完整素材顺序时间线后时间线为空”的问题。

原因：
部分 DaVinci Resolve 版本中，`AppendToTimeline` / `CreateTimelineFromClips` 对参数格式比较敏感。
直接传入 `[MediaPoolItem]` 可能创建时间线但没有真正追加片段。

v2.2 改为优先使用：

```python
[{"mediaPoolItem": item}, ...]
```

并提供多级 fallback：

1. `CreateTimelineFromClips(name, clipInfos)`
2. `CreateTimelineFromClips(name, mediaPoolItems)`
3. `CreateEmptyTimeline(name)` + `AppendToTimeline(clipInfos)`
4. `AppendToTimeline(mediaPoolItems)`

同时会在界面返回“实际检测到片段数量”。
