
import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {
    @State private var fcpxmlPath: String = ""
    @State private var originalRootPath: String = ""
    @State private var mediaListPath: String = ""
    @State private var orderedMediaListPath: String = ""
    @State private var outputMediaListPath: String = ""
    @State private var projectBaseName: String = ""
    @State private var statusText: String = "请选择一个 FCPXML 或 FCPXMLD 文件。"
    @State private var isBusy: Bool = false

    @State private var linkOriginalFiles: Bool = false
    @State private var createFullTimeline: Bool = true
    @State private var timelineDedupe: Bool = true

    @State private var currentProxyPaths: [String] = []
    @State private var currentFinalPaths: [String] = []
    @State private var currentOrderedPaths: [String] = []
    @State private var unresolvedProxyPaths: [String] = []
    @State private var duplicateReportPath: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("FCPXML / FCPXMLD 导入媒体池 + 创建完整素材时间线")
                .font(.title2)
                .bold()

            Toggle("链接原始文件", isOn: $linkOriginalFiles)
                .disabled(isBusy)

            Toggle("导入后创建完整素材顺序时间线", isOn: $createFullTimeline)
                .disabled(isBusy)

            Toggle("时间线素材按首次出现顺序去重", isOn: $timelineDedupe)
                .disabled(isBusy || !createFullTimeline)

            Text("支持 .fcpxml 文件和 .fcpxmld 包目录。创建时间线时只按 FCPXML 中素材出现顺序排列完整片段，不保留剪辑点。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("当前 FCPXML / FCPXMLD：")
                    .font(.headline)
                Text(fcpxmlPath.isEmpty ? "未选择" : fcpxmlPath)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Text("原始文件目录：")
                    .font(.headline)
                Text(originalRootPath.isEmpty ? "未选择 / 未启用" : originalRootPath)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Text("当前媒体池清单：")
                    .font(.headline)
                Text(mediaListPath.isEmpty ? "未生成" : mediaListPath)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Text("顺序时间线清单：")
                    .font(.headline)
                Text(orderedMediaListPath.isEmpty ? "未生成" : orderedMediaListPath)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            HStack(spacing: 12) {
                Button {
                    chooseFCPXML()
                } label: {
                    Text("加载 FCPXML")
                        .frame(width: 140)
                }
                .disabled(isBusy)

                Button {
                    chooseMediaList()
                } label: {
                    Text("选择已有清单")
                        .frame(width: 140)
                }
                .disabled(isBusy)

                Button {
                    importToResolve()
                } label: {
                    Text("导入 DaVinci")
                        .frame(width: 140)
                }
                .disabled(isBusy || mediaListPath.isEmpty)

                Button {
                    createFullTimelineOnly()
                } label: {
                    Text("创建完整素材时间线")
                        .frame(width: 170)
                }
                .disabled(isBusy || orderedMediaListPath.isEmpty)
            }

            Divider()

            Text("状态")
                .font(.headline)

            ScrollView {
                Text(statusText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .padding(10)
            }
            .frame(minHeight: 150)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Spacer()
        }
        .padding(24)
        .frame(width: 860, height: 660)
    }

    private func chooseMediaList() {
        let panel = NSOpenPanel()
        panel.title = "选择已有素材清单"
        panel.message = "请选择之前生成的 .media_list.txt、.ordered_media_list.txt 或普通 .txt 清单。"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.plainText]

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else {
            return
        }

        resetRelinkState()
        fcpxmlPath = ""
        originalRootPath = ""
        mediaListPath = url.path
        orderedMediaListPath = url.path
        outputMediaListPath = url.path
        projectBaseName = cleanProjectName(from: url)
        statusText = "已选择已有清单：\n\(url.path)\n\n正在检查清单..."
        isBusy = true

        DispatchQueue.global(qos: .userInitiated).async {
            let result = runPython(arguments: ["inspect-list", url.path])

            DispatchQueue.main.async {
                isBusy = false

                if result.exitCode == 0,
                   let parsed = parseJSON(result.output) {
                    let count = parsed["count"] as? Int ?? 0
                    let existing = parsed["existing"] as? Int ?? 0
                    let missing = parsed["missing"] as? Int ?? 0

                    statusText = """
                    已选择已有清单。

                    清单路径：
                    \(url.path)

                    清单素材数量：\(count)
                    本地存在数量：\(existing)
                    缺失文件数量：\(missing)

                    现在可以点击“导入 DaVinci”，也可以单独点击“创建完整素材时间线”。
                    """
                } else {
                    mediaListPath = ""
                    orderedMediaListPath = ""
                    outputMediaListPath = ""
                    statusText = """
                    清单读取失败。

                    输出：
                    \(result.output)

                    错误：
                    \(result.error)
                    """
                }
            }
        }
    }

    private func chooseFCPXML() {
        let panel = NSOpenPanel()
        panel.title = "选择 FCPXML 或 FCPXMLD"
        panel.message = "可选择 .fcpxml 文件，或 .fcpxmld 包目录。"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else {
            return
        }

        let ext = url.pathExtension.lowercased()
        guard ext == "fcpxml" || ext == "fcpxmld" else {
            statusText = "请选择 .fcpxml 文件或 .fcpxmld 包目录。"
            return
        }

        resetRelinkState()

        if linkOriginalFiles {
            let dirPanel = NSOpenPanel()
            dirPanel.title = "选择原始文件目录"
            dirPanel.message = "请选择包含原始 .mov / .mp4 文件的目录，可以是素材盘根目录，软件会递归搜索。"
            dirPanel.canChooseFiles = false
            dirPanel.canChooseDirectories = true
            dirPanel.allowsMultipleSelection = false

            let dirResponse = dirPanel.runModal()
            guard dirResponse == .OK, let dirURL = dirPanel.url else {
                statusText = "已取消选择原始文件目录，未生成清单。"
                return
            }

            originalRootPath = dirURL.path
        } else {
            originalRootPath = ""
        }

        fcpxmlPath = url.path
        projectBaseName = url.deletingPathExtension().lastPathComponent
        mediaListPath = ""
        orderedMediaListPath = ""
        outputMediaListPath = ""

        statusText = linkOriginalFiles
            ? "已选择：\n\(url.path)\n\n已选择原始目录：\n\(originalRootPath)\n\n正在解析并匹配原始文件..."
            : "已选择：\n\(url.path)\n\n正在解析并生成清单..."

        isBusy = true

        DispatchQueue.global(qos: .userInitiated).async {
            var args = ["extract", url.path]
            if !timelineDedupe {
                args.append("--ordered-no-dedupe")
            }
            if linkOriginalFiles {
                args.append("--link-original")
                args.append(originalRootPath)
                args.append("--keep-unmatched")
            }

            let result = runPython(arguments: args)

            DispatchQueue.main.async {
                isBusy = false

                if result.exitCode == 0,
                   let parsed = parseJSON(result.output),
                   let listPath = parsed["media_list"] as? String {

                    mediaListPath = listPath
                    outputMediaListPath = listPath
                    orderedMediaListPath = parsed["ordered_media_list"] as? String ?? ""
                    currentOrderedPaths = parsed["ordered_final_paths"] as? [String] ?? []

                    let count = parsed["count"] as? Int ?? 0
                    let orderedCount = parsed["ordered_count"] as? Int ?? 0
                    let xmlSource = parsed["xml_source"] as? String ?? ""
                    let outputDir = parsed["output_dir"] as? String ?? ""
                    let proxyCount = parsed["proxy_count"] as? Int ?? count
                    let matchedCount = parsed["matched_original_count"] as? Int ?? 0
                    let unmatched = parsed["unmatched_proxy_paths"] as? [String] ?? []
                    let finalPaths = parsed["final_paths"] as? [String] ?? []
                    let proxyPaths = parsed["proxy_paths"] as? [String] ?? []
                    let duplicateCount = parsed["duplicate_original_name_count"] as? Int ?? 0
                    let duplicateList = parsed["duplicate_list"] as? String ?? ""

                    currentProxyPaths = proxyPaths
                    currentFinalPaths = finalPaths
                    unresolvedProxyPaths = unmatched
                    duplicateReportPath = duplicateList

                    if linkOriginalFiles {
                        statusText = """
                        加载成功，并已尝试链接原始文件。

                        实际解析 XML：
                        \(xmlSource)

                        输出目录：
                        \(outputDir)

                        FCPXML 中代理/媒体数量：\(proxyCount)
                        成功匹配原始文件数量：\(matchedCount)
                        最终写入媒体池清单数量：\(count)
                        顺序时间线素材数量：\(orderedCount)
                        未匹配代理数量：\(unmatched.count)
                        原始目录同名冲突数量：\(duplicateCount)

                        媒体池清单：
                        \(listPath)

                        顺序时间线清单：
                        \(orderedMediaListPath)

                        \(duplicateCount > 0 ? "同名冲突清单：\n\(duplicateList)\n" : "")
                        """

                        if !unmatched.isEmpty {
                            presentUnresolvedDialog()
                        } else {
                            statusText += "\n全部原始文件已链接成功。现在可以点击“导入 DaVinci”，也可以单独点击“创建完整素材时间线”。"
                        }
                    } else {
                        statusText = """
                        加载成功。

                        实际解析 XML：
                        \(xmlSource)

                        输出目录：
                        \(outputDir)

                        媒体池清单：
                        \(listPath)

                        顺序时间线清单：
                        \(orderedMediaListPath)

                        去重后素材数量：\(count)
                        顺序时间线素材数量：\(orderedCount)

                        现在可以点击“导入 DaVinci”，也可以单独点击“创建完整素材时间线”。
                        """
                    }
                } else {
                    statusText = """
                    加载失败。

                    输出：
                    \(result.output)

                    错误：
                    \(result.error)
                    """
                }
            }
        }
    }

    private func resetRelinkState() {
        currentProxyPaths = []
        currentFinalPaths = []
        currentOrderedPaths = []
        unresolvedProxyPaths = []
        duplicateReportPath = ""
        outputMediaListPath = ""
        orderedMediaListPath = ""
        projectBaseName = ""
    }

    private func presentUnresolvedDialog() {
        while !unresolvedProxyPaths.isEmpty {
            let choice = showUnresolvedAlert(unresolvedProxyPaths)

            if choice == .skip {
                writeCurrentFinalListAfterSkip()
                return
            }

            guard let dir = chooseAdditionalOriginalDirectory() else {
                writeCurrentFinalListAfterSkip()
                return
            }

            statusText = """
            正在使用新的原始文件目录继续链接未匹配文件：

            \(dir)
            """

            let oldUnresolved = unresolvedProxyPaths

            let relinkResult = runPython(arguments: [
                "relink-unmatched",
                "--proxies-json", jsonString(unresolvedProxyPaths),
                "--current-final-json", jsonString(currentFinalPaths),
                "--original-root", dir,
                "--output-list", outputMediaListPath
            ])

            if relinkResult.exitCode == 0,
               let parsed = parseJSON(relinkResult.output) {

                currentFinalPaths = parsed["final_paths"] as? [String] ?? currentFinalPaths
                unresolvedProxyPaths = parsed["unmatched_proxy_paths"] as? [String] ?? unresolvedProxyPaths
                mediaListPath = parsed["media_list"] as? String ?? mediaListPath

                refreshOrderedListFromCurrentFinal(oldUnresolved: oldUnresolved)

                let newlyMatched = parsed["newly_matched_count"] as? Int ?? 0
                let remaining = unresolvedProxyPaths.count

                statusText = """
                已继续链接原始文件。

                本次新匹配数量：\(newlyMatched)
                剩余未匹配数量：\(remaining)

                当前媒体池清单：
                \(mediaListPath)

                当前顺序时间线清单：
                \(orderedMediaListPath)
                """

                if remaining == 0 {
                    statusText += "\n全部原始文件已链接成功。现在可以点击“导入 DaVinci”，也可以单独点击“创建完整素材时间线”。"
                    return
                }
            } else {
                let alert = NSAlert()
                alert.messageText = "重新链接失败"
                alert.informativeText = """
                输出：
                \(relinkResult.output)

                错误：
                \(relinkResult.error)
                """
                alert.addButton(withTitle: "继续选择目录")
                alert.addButton(withTitle: "跳过")
                let resp = alert.runModal()
                if resp != .alertFirstButtonReturn {
                    writeCurrentFinalListAfterSkip()
                    return
                }
            }
        }
    }

    private enum UnresolvedChoice {
        case chooseDirectory
        case skip
    }

    private func showUnresolvedAlert(_ unresolved: [String]) -> UnresolvedChoice {
        let alert = NSAlert()
        alert.messageText = "有文件未链接到原始文件"
        alert.informativeText = "下面是未链接的文件名和原路径。可以继续选择目录重新链接，或跳过并沿用原路径。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "选择目录链接")
        alert.addButton(withTitle: "跳过（沿用原路径）")

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 640, height: 260))
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.borderType = .bezelBorder

        let textView = NSTextView(frame: scrollView.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.string = unresolved.map { path in
            let name = URL(fileURLWithPath: path).lastPathComponent
            return "文件名：\(name)\n原路径：\(path)"
        }.joined(separator: "\n\n")

        scrollView.documentView = textView
        alert.accessoryView = scrollView

        let response = alert.runModal()
        return response == .alertFirstButtonReturn ? .chooseDirectory : .skip
    }

    private func chooseAdditionalOriginalDirectory() -> String? {
        let dirPanel = NSOpenPanel()
        dirPanel.title = "选择新的原始文件目录"
        dirPanel.message = "请选择可能包含剩余未链接原始文件的目录。"
        dirPanel.canChooseFiles = false
        dirPanel.canChooseDirectories = true
        dirPanel.allowsMultipleSelection = false

        let response = dirPanel.runModal()
        guard response == .OK, let url = dirPanel.url else {
            return nil
        }
        return url.path
    }

    private func writeCurrentFinalListAfterSkip() {
        guard !outputMediaListPath.isEmpty else { return }

        let result = runPython(arguments: [
            "write-list",
            "--paths-json", jsonString(currentFinalPaths),
            "--output-list", outputMediaListPath
        ])

        if result.exitCode == 0 {
            refreshOrderedListFromCurrentFinal(oldUnresolved: unresolvedProxyPaths)
            mediaListPath = outputMediaListPath
            statusText = """
            已跳过剩余未链接文件，并沿用 FCPXML 中的原路径。

            剩余未链接数量：\(unresolvedProxyPaths.count)

            当前媒体池清单：
            \(mediaListPath)

            当前顺序时间线清单：
            \(orderedMediaListPath)

            现在可以点击“导入 DaVinci”，也可以单独点击“创建完整素材时间线”。
            """
        } else {
            statusText = """
            写入清单失败。

            输出：
            \(result.output)

            错误：
            \(result.error)
            """
        }
    }

    private func refreshOrderedListFromCurrentFinal(oldUnresolved: [String]) {
        guard !orderedMediaListPath.isEmpty else { return }

        var byStem: [String: String] = [:]
        for path in currentFinalPaths {
            let stem = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            byStem[stem] = path
        }

        currentOrderedPaths = currentOrderedPaths.map { path in
            let stem = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            return byStem[stem] ?? path
        }

        if timelineDedupe {
            var seen = Set<String>()
            currentOrderedPaths = currentOrderedPaths.filter { path in
                if seen.contains(path) { return false }
                seen.insert(path)
                return true
            }
        }

        _ = runPython(arguments: [
            "write-list",
            "--paths-json", jsonString(currentOrderedPaths),
            "--output-list", orderedMediaListPath
        ])
    }


    private func createFullTimelineOnly() {
        guard !orderedMediaListPath.isEmpty else {
            statusText = "没有 ordered_media_list.txt，请先加载 FCPXML / FCPXMLD。"
            return
        }

        statusText = "正在创建完整素材顺序时间线..."
        isBusy = true

        let shouldDedupeTimeline = timelineDedupe
        let orderedList = orderedMediaListPath
        let timelineName = "\(projectBaseName.isEmpty ? "FCPXML" : projectBaseName)_完整素材顺序"

        DispatchQueue.global(qos: .userInitiated).async {
            var timelineArgs = [
                "create-full-timeline",
                "--ordered-list", orderedList,
                "--timeline-name", timelineName
            ]
            if !shouldDedupeTimeline {
                timelineArgs.append("--no-dedupe")
            }

            let result = runPython(arguments: timelineArgs)
            let timelineText = buildTimelineStatusText(result: result, fallbackName: timelineName)

            DispatchQueue.main.async {
                isBusy = false
                statusText = timelineText
            }
        }
    }

    private func importToResolve() {
        guard !mediaListPath.isEmpty else {
            statusText = "没有可导入的 txt 清单，请先加载 FCPXML / FCPXMLD。"
            return
        }

        statusText = "正在将清单中的素材导入 DaVinci Resolve..."
        isBusy = true

        let shouldCreateTimeline = createFullTimeline
        let shouldDedupeTimeline = timelineDedupe
        let orderedList = orderedMediaListPath
        let timelineName = "\(projectBaseName.isEmpty ? "FCPXML" : projectBaseName)_完整素材顺序"

        DispatchQueue.global(qos: .userInitiated).async {
            let result = runPython(arguments: ["import", mediaListPath])
            var timelineText = ""

            if result.exitCode == 0, shouldCreateTimeline, !orderedList.isEmpty {
                var timelineArgs = [
                    "create-full-timeline",
                    "--ordered-list", orderedList,
                    "--timeline-name", timelineName
                ]
                if !shouldDedupeTimeline {
                    timelineArgs.append("--no-dedupe")
                }

                let timelineResult = runPython(arguments: timelineArgs)
                timelineText = buildTimelineStatusText(result: timelineResult, fallbackName: timelineName)
            } else if shouldCreateTimeline && orderedList.isEmpty {
                timelineText = "\n未创建时间线：没有 ordered_media_list.txt。"
            }

            DispatchQueue.main.async {
                isBusy = false

                if result.exitCode == 0 {
                    if let parsed = parseJSON(result.output) {
                        let requested = parsed["requested"] as? Int ?? 0
                        let existing = parsed["existing"] as? Int ?? 0
                        let imported = parsed["imported"] as? Int ?? 0
                        let missing = parsed["missing"] as? Int ?? 0
                        let missingList = parsed["missing_list"] as? String ?? ""

                        statusText = """
                        已发送至 DaVinci Resolve。

                        清单素材数量：\(requested)
                        本地存在数量：\(existing)
                        成功导入数量：\(imported)
                        缺失文件数量：\(missing)

                        \(missing > 0 ? "缺失清单：\n\(missingList)" : "没有缺失文件。")
                        \(timelineText)
                        """
                    } else {
                        statusText = "导入命令已执行，但无法读取脚本返回结果：\n\(result.output)\n\(result.error)"
                    }
                } else {
                    statusText = """
                    导入 DaVinci 失败。

                    请确认：
                    1. DaVinci Resolve 已打开；
                    2. 已打开一个项目；
                    3. Resolve 偏好设置启用了 External scripting；
                    4. App Sandbox 没有阻止访问；
                    5. 素材盘已挂载。

                    输出：
                    \(result.output)

                    错误：
                    \(result.error)
                    """
                }
            }
        }
    }
}

struct PythonResult {
    let output: String
    let error: String
    let exitCode: Int32
}

func runPython(arguments: [String]) -> PythonResult {
    guard let scriptURL = Bundle.main.url(forResource: "resolve_importer", withExtension: "py") else {
        return PythonResult(output: "", error: "找不到 resolve_importer.py，请确认它已加入 Copy Bundle Resources。", exitCode: 1)
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    process.arguments = [scriptURL.path] + arguments

    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    do {
        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        let output = String(data: outputData, encoding: .utf8) ?? ""
        let error = String(data: errorData, encoding: .utf8) ?? ""

        return PythonResult(output: output, error: error, exitCode: process.terminationStatus)
    } catch {
        return PythonResult(output: "", error: error.localizedDescription, exitCode: 1)
    }
}

func parseJSON(_ text: String) -> [String: Any]? {
    guard let data = text.data(using: .utf8) else { return nil }

    do {
        let obj = try JSONSerialization.jsonObject(with: data, options: [])
        return obj as? [String: Any]
    } catch {
        return nil
    }
}

func jsonString(_ array: [String]) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: array, options: []),
          let string = String(data: data, encoding: .utf8) else {
        return "[]"
    }
    return string
}

func cleanProjectName(from url: URL) -> String {
    var name = url.deletingPathExtension().lastPathComponent
    name = name.replacingOccurrences(of: ".media_list", with: "")
    name = name.replacingOccurrences(of: ".ordered_media_list", with: "")
    return name.isEmpty ? "FCPXML" : name
}

func buildTimelineStatusText(result: PythonResult, fallbackName: String) -> String {
    if result.exitCode == 0, let parsed = parseJSON(result.output) {
        let name = parsed["timeline_name"] as? String ?? fallbackName
        let requested = parsed["requested"] as? Int ?? 0
        let added = parsed["timeline_added"] as? Int ?? 0
        let missing = parsed["missing"] as? Int ?? 0
        let unresolved = parsed["timeline_unresolved"] as? Int ?? 0
        let missingList = parsed["missing_list"] as? String ?? ""
        let unresolvedList = parsed["timeline_unresolved_list"] as? String ?? ""

        return """

        已创建完整素材顺序时间线：
        \(name)

        顺序清单数量：\(requested)
        加入时间线数量：\(added)
        缺失文件数量：\(missing)
        媒体池未解析数量：\(unresolved)

        \(missing > 0 ? "时间线缺失清单：\n\(missingList)\n" : "")\(unresolved > 0 ? "未解析媒体池项清单：\n\(unresolvedList)" : "")
        """
    }

    return """

    创建完整素材顺序时间线失败。

    输出：
    \(result.output)

    错误：
    \(result.error)
    """
}
