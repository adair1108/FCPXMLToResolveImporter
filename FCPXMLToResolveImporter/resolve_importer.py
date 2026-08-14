#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import sys
import json
import urllib.parse
import xml.etree.ElementTree as ET
from pathlib import Path
from collections import defaultdict

VIDEO_EXTS = {".mov", ".mp4"}
XML_EXTS = {".fcpxml", ".xml"}


def print_json(obj):
    print(json.dumps(obj, ensure_ascii=False))


def strip_namespace(tag):
    if "}" in tag:
        return tag.split("}", 1)[1]
    return tag


def fcpxml_url_to_path(url):
    if not url:
        return None

    url = url.strip()

    if url.startswith("file://"):
        parsed = urllib.parse.urlparse(url)
        path = urllib.parse.unquote(parsed.path)
        return path

    return urllib.parse.unquote(url)


def is_probably_fcpxml(xml_path):
    """
    判断一个 XML 文件是否像 FCPXML。
    .fcpxmld 是包目录时，里面可能有多个 XML；这里优先找根节点为 fcpxml 的文件。
    """
    try:
        for event, elem in ET.iterparse(str(xml_path), events=("start",)):
            tag = strip_namespace(elem.tag).lower()
            return tag == "fcpxml"
    except Exception:
        return False
    return False


def resolve_fcpxml_input(input_path):
    """
    支持：
    1. 普通 .fcpxml 文件
    2. .fcpxmld 包目录
    3. 普通目录内包含 .fcpxml / .xml

    返回：
    (actual_xml_path, output_base_path)

    output_base_path 用于决定 media_list.txt 放在哪里。
    - 如果输入是 .fcpxml 文件：输出在该文件旁边
    - 如果输入是 .fcpxmld 目录：输出在 .fcpxmld 目录旁边，文件名沿用包名
    """
    p = Path(input_path).expanduser().resolve()

    if not p.exists():
        raise FileNotFoundError(f"找不到文件或目录：{p}")

    if p.is_file():
        if p.suffix.lower() not in XML_EXTS:
            raise ValueError(f"请选择 .fcpxml 或 XML 文件：{p}")
        return p, p

    if p.is_dir():
        candidates = []

        # 优先：目录内直接的 .fcpxml
        for child in sorted(p.iterdir()):
            if child.is_file() and child.suffix.lower() == ".fcpxml":
                candidates.append(child)

        # 其次：递归找 .fcpxml
        if not candidates:
            for child in sorted(p.rglob("*.fcpxml")):
                if child.is_file():
                    candidates.append(child)

        # 再其次：递归找根节点为 fcpxml 的 .xml
        if not candidates:
            for child in sorted(p.rglob("*.xml")):
                if child.is_file() and is_probably_fcpxml(child):
                    candidates.append(child)

        if not candidates:
            raise FileNotFoundError(f"在目录内没有找到可解析的 .fcpxml / FCPXML XML：{p}")

        # 如果有多个，优先文件名包含 current / project / event / fcpxml 的，其次取最短路径
        def score(path):
            name = path.name.lower()
            keyword_score = 0
            for kw in ["current", "project", "event", "fcpxml"]:
                if kw in name:
                    keyword_score -= 1
            return (keyword_score, len(str(path)), str(path).lower())

        actual_xml = sorted(candidates, key=score)[0]

        # 输出基名：如果是 .fcpxmld 包，就用包本身旁边生成清单；否则用找到的 xml 旁边生成
        if p.suffix.lower() == ".fcpxmld":
            output_base = p
        else:
            output_base = actual_xml

        return actual_xml, output_base

    raise ValueError(f"不支持的路径类型：{p}")


def collect_media_from_fcpxml(input_path):
    xml_path, output_base = resolve_fcpxml_input(input_path)

    tree = ET.parse(xml_path)
    root = tree.getroot()

    media_paths = set()

    for elem in root.iter():
        tag = strip_namespace(elem.tag)

        src = elem.attrib.get("src")
        if src:
            path = fcpxml_url_to_path(src)
            if path and Path(path).suffix.lower() in VIDEO_EXTS:
                media_paths.add(path)

        if tag == "media-rep":
            src = elem.attrib.get("src")
            if src:
                path = fcpxml_url_to_path(src)
                if path and Path(path).suffix.lower() in VIDEO_EXTS:
                    media_paths.add(path)

    return sorted(media_paths), xml_path, output_base


def scan_original_media(original_root):
    original_root = Path(original_root).expanduser().resolve()

    if not original_root.exists():
        raise FileNotFoundError(f"找不到原始文件目录：{original_root}")

    if not original_root.is_dir():
        raise NotADirectoryError(f"原始文件路径不是目录：{original_root}")

    index = defaultdict(list)

    for root, dirs, files in os.walk(original_root):
        dirs[:] = [d for d in dirs if d not in {".Spotlight-V100", ".Trashes", ".fseventsd"}]

        for filename in files:
            file_path = Path(root) / filename
            suffix = file_path.suffix.lower()

            if suffix in VIDEO_EXTS:
                stem = file_path.stem
                index[stem].append(str(file_path))

    return index


def choose_best_original(candidates):
    if not candidates:
        return None

    def score(path):
        p = Path(path)
        ext_score = 0 if p.suffix.lower() == ".mp4" else 1
        return (ext_score, len(str(p)), str(p).lower())

    return sorted(candidates, key=score)[0]


def relink_to_original(proxy_paths, original_root):
    original_index = scan_original_media(original_root)

    final_paths = []
    unmatched_proxy = []
    duplicate_originals = []

    for proxy_path in proxy_paths:
        stem = Path(proxy_path).stem
        candidates = original_index.get(stem, [])

        if len(candidates) == 0:
            unmatched_proxy.append(proxy_path)
            final_paths.append(proxy_path)
        elif len(candidates) == 1:
            final_paths.append(candidates[0])
        else:
            chosen = choose_best_original(candidates)
            final_paths.append(chosen)
            duplicate_originals.append({
                "proxy": proxy_path,
                "chosen": chosen,
                "candidates": candidates
            })

    seen = set()
    unique_final = []
    for p in final_paths:
        if p not in seen:
            seen.add(p)
            unique_final.append(p)

    return unique_final, unmatched_proxy, duplicate_originals


def write_media_list(media_paths, output_txt):
    output_txt = Path(output_txt).expanduser().resolve()
    output_txt.parent.mkdir(parents=True, exist_ok=True)

    with open(output_txt, "w", encoding="utf-8") as f:
        for p in media_paths:
            f.write(str(p) + "\n")

    return output_txt


def write_duplicate_report(duplicates, output_txt):
    output_txt = Path(output_txt).expanduser().resolve()
    output_txt.parent.mkdir(parents=True, exist_ok=True)

    with open(output_txt, "w", encoding="utf-8") as f:
        for item in duplicates:
            f.write("代理文件：\n")
            f.write(item["proxy"] + "\n")
            f.write("自动选择：\n")
            f.write(item["chosen"] + "\n")
            f.write("候选文件：\n")
            for c in item["candidates"]:
                f.write(c + "\n")
            f.write("\n---\n\n")

    return output_txt


def read_media_list(media_list_path):
    media_list_path = Path(media_list_path).expanduser().resolve()

    if not media_list_path.exists():
        raise FileNotFoundError(f"找不到清单文件：{media_list_path}")

    paths = []
    with open(media_list_path, "r", encoding="utf-8") as f:
        for line in f:
            p = line.strip()
            if p:
                paths.append(p)

    seen = set()
    unique = []
    for p in paths:
        if p not in seen:
            seen.add(p)
            unique.append(p)

    return unique


def find_resolve_script_module_paths():
    """
    自动寻找 DaVinciResolveScript.py 所在目录。

    常见情况：
    1. 系统级安装：
       /Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting/Modules

    2. App 包内部：
       /Applications/DaVinci Resolve/DaVinci Resolve.app/Contents/Libraries/Fusion/Modules
       /Applications/DaVinci Resolve Studio/DaVinci Resolve.app/Contents/Libraries/Fusion/Modules

    3. 用户手动设置环境变量：
       RESOLVE_SCRIPT_API
       RESOLVE_SCRIPT_LIB
    """
    checked = []
    candidates = []

    env_api = os.environ.get("RESOLVE_SCRIPT_API", "")
    env_lib = os.environ.get("RESOLVE_SCRIPT_LIB", "")

    if env_api:
        candidates.append(env_api)
        candidates.append(os.path.join(env_api, "Modules"))

    if env_lib:
        candidates.append(env_lib)
        candidates.append(os.path.join(env_lib, "Modules"))

    candidates.extend([
        "/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting/Modules",
        "/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting",
        "/Applications/DaVinci Resolve Studio.app/Contents/Resources/Developer/Scripting/Modules",
        "/Applications/DaVinci Resolve.app/Contents/Resources/Developer/Scripting/Modules",
        "/Applications/DaVinci Resolve/DaVinci Resolve.app/Contents/Libraries/Fusion/Modules",
        "/Applications/DaVinci Resolve Studio/DaVinci Resolve.app/Contents/Libraries/Fusion/Modules",
        "/Applications/DaVinci Resolve.app/Contents/Libraries/Fusion/Modules",
    ])

    # 再做一次小范围自动搜索，避免不同版本路径略有差异。
    search_roots = [
        "/Library/Application Support/Blackmagic Design",
        "/Applications/DaVinci Resolve",
        "/Applications/DaVinci Resolve Studio",
        "/Applications/DaVinci Resolve.app",
    ]

    for root in search_roots:
        root_path = Path(root)
        if root_path.exists():
            try:
                for found in root_path.rglob("DaVinciResolveScript.py"):
                    candidates.append(str(found.parent))
            except Exception:
                pass

    # 去重并检查
    unique = []
    seen = set()

    for c in candidates:
        if not c:
            continue
        p = str(Path(c).expanduser())
        if p in seen:
            continue
        seen.add(p)
        unique.append(p)

    valid = []
    for p in unique:
        checked.append(p)
        if Path(p, "DaVinciResolveScript.py").exists():
            valid.append(p)

    return valid, checked



def find_fusionscript_library_paths():
    """
    寻找 fusionscript.so 的完整文件路径。
    注意：DaVinciResolveScript.py 读取 RESOLVE_SCRIPT_LIB 时，
    需要的是 fusionscript.so 文件路径，而不是 Fusion 目录路径。

    Studio 版常见路径：
    /Applications/DaVinci Resolve Studio.app/Contents/Libraries/Fusion/fusionscript.so

    普通版常见路径：
    /Applications/DaVinci Resolve.app/Contents/Libraries/Fusion/fusionscript.so
    """
    candidates = [
        "/Applications/DaVinci Resolve Studio.app/Contents/Libraries/Fusion/fusionscript.so",
        "/Applications/DaVinci Resolve.app/Contents/Libraries/Fusion/fusionscript.so",
        "/Applications/DaVinci Resolve/DaVinci Resolve.app/Contents/Libraries/Fusion/fusionscript.so",
        "/Applications/DaVinci Resolve Studio/DaVinci Resolve.app/Contents/Libraries/Fusion/fusionscript.so",
    ]

    search_roots = [
        "/Applications/DaVinci Resolve Studio.app",
        "/Applications/DaVinci Resolve.app",
        "/Applications/DaVinci Resolve",
        "/Applications/DaVinci Resolve Studio",
    ]

    for root in search_roots:
        rp = Path(root)
        if rp.exists():
            try:
                for found in rp.rglob("fusionscript.so"):
                    candidates.append(str(found))
            except Exception:
                pass

    seen = set()
    valid = []
    checked = []

    for c in candidates:
        p = str(Path(c).expanduser())
        if p in seen:
            continue
        seen.add(p)
        checked.append(p)
        if Path(p).exists() and Path(p).name == "fusionscript.so":
            valid.append(p)

    return valid, checked


def configure_resolve_environment():
    """
    DaVinciResolveScript.py 在导入时会读取 RESOLVE_SCRIPT_LIB。
    如果没有设置，它可能默认去找普通版 DaVinci Resolve.app。
    对 Studio 版用户，需要在 import DaVinciResolveScript 之前设置到 Studio.app 的 fusionscript.so 目录。
    """
    lib_paths, checked_lib_paths = find_fusionscript_library_paths()

    if lib_paths:
        # 优先选择 Studio.app
        studio_paths = [p for p in lib_paths if "DaVinci Resolve Studio.app" in p]
        chosen_file = studio_paths[0] if studio_paths else lib_paths[0]
        chosen_dir = str(Path(chosen_file).parent)

        # 关键：RESOLVE_SCRIPT_LIB 必须是 fusionscript.so 的完整文件路径
        os.environ["RESOLVE_SCRIPT_LIB"] = chosen_file

        # DYLD_LIBRARY_PATH 使用 fusionscript.so 所在目录
        old_dyld = os.environ.get("DYLD_LIBRARY_PATH", "")
        if chosen_dir not in old_dyld.split(":"):
            os.environ["DYLD_LIBRARY_PATH"] = chosen_dir + (":" + old_dyld if old_dyld else "")

    return {
        "fusionscript_valid_paths": lib_paths,
        "fusionscript_checked_paths": checked_lib_paths,
        "RESOLVE_SCRIPT_LIB": os.environ.get("RESOLVE_SCRIPT_LIB", ""),
        "DYLD_LIBRARY_PATH": os.environ.get("DYLD_LIBRARY_PATH", ""),
    }



def import_davinci_module():
    """
    导入 DaVinciResolveScript。
    先配置 RESOLVE_SCRIPT_LIB，避免 Studio 版用户被 DaVinciResolveScript.py 错误指向普通版路径。
    """
    env_info = configure_resolve_environment()

    first_error = None

    try:
        import DaVinciResolveScript as dvr_script
        return dvr_script
    except ImportError as e:
        first_error = e

    valid_paths, checked_paths = find_resolve_script_module_paths()

    for module_path in valid_paths:
        if module_path not in sys.path:
            sys.path.insert(0, module_path)
        try:
            import DaVinciResolveScript as dvr_script
            return dvr_script
        except ImportError as e:
            first_error = e
            continue

    message = (
        "无法导入 DaVinciResolveScript。\\n\\n"
        "最后一次 ImportError：\\n"
        + (str(first_error) if first_error else "未知")
        + "\\n\\n"
        "当前 RESOLVE_SCRIPT_LIB：\\n"
        + env_info.get("RESOLVE_SCRIPT_LIB", "")
        + "\\n\\n"
        "已找到 fusionscript.so 文件：\\n"
        + "\\n".join(env_info.get("fusionscript_valid_paths", []))
        + "\\n\\n"
        "已检查 DaVinciResolveScript.py 路径：\\n"
        + "\\n".join(checked_paths)
        + "\\n\\n"
        "请在终端运行：\\n"
        "find /Applications '/Library/Application Support/Blackmagic Design' -name fusionscript.so -o -name DaVinciResolveScript.py 2>/dev/null\\n"
    )
    raise RuntimeError(message)


def import_to_resolve(media_paths):
    dvr_script = import_davinci_module()

    resolve = dvr_script.scriptapp("Resolve")
    if not resolve:
        raise RuntimeError("无法连接 DaVinci Resolve。请先打开 DaVinci Resolve，并启用 External scripting。")

    project_manager = resolve.GetProjectManager()
    if not project_manager:
        raise RuntimeError("无法获取 ProjectManager。")

    project = project_manager.GetCurrentProject()
    if not project:
        raise RuntimeError("当前没有打开的 DaVinci Resolve 项目。")

    media_pool = project.GetMediaPool()
    if not media_pool:
        raise RuntimeError("无法获取 Media Pool。")

    existing_files = []
    missing_files = []

    for p in media_paths:
        if os.path.exists(p):
            existing_files.append(p)
        else:
            missing_files.append(p)

    imported_items = []
    if existing_files:
        imported_items = media_pool.ImportMedia(existing_files)

    return imported_items or [], existing_files, missing_files


def output_paths_from_base(output_base):
    """
    output_base 可能是：
    - xxx.fcpxml 文件
    - xxx.fcpxmld 目录

    都统一生成：
    xxx.media_list.txt
    xxx.unmatched_proxy_media.txt
    xxx.duplicate_original_media.txt
    """
    base = Path(output_base).expanduser().resolve()

    if base.suffix.lower() in {".fcpxml", ".xml", ".fcpxmld"}:
        media = base.with_suffix(".media_list.txt")
        unmatched = base.with_suffix(".unmatched_proxy_media.txt")
        duplicate = base.with_suffix(".duplicate_original_media.txt")
    else:
        media = Path(str(base) + ".media_list.txt")
        unmatched = Path(str(base) + ".unmatched_proxy_media.txt")
        duplicate = Path(str(base) + ".duplicate_original_media.txt")

    return media, unmatched, duplicate


def cmd_extract(args):
    if len(args) < 1:
        raise ValueError("extract 模式需要 FCPXML / FCPXMLD 路径")

    input_path = args[0]
    link_original = False
    original_root = ""

    if "--link-original" in args:
        idx = args.index("--link-original")
        if idx + 1 >= len(args):
            raise ValueError("--link-original 后面需要原始文件目录")
        link_original = True
        original_root = args[idx + 1]

    proxy_paths, xml_source, output_base = collect_media_from_fcpxml(input_path)

    output_txt, unmatched_txt, duplicate_txt = output_paths_from_base(output_base)

    unmatched_list_path = ""
    duplicate_list_path = ""
    unmatched_proxy = []
    duplicate_originals = []

    if link_original:
        final_paths, unmatched_proxy, duplicate_originals = relink_to_original(proxy_paths, original_root)

        if unmatched_proxy:
            write_media_list(unmatched_proxy, unmatched_txt)
            unmatched_list_path = str(unmatched_txt)

        if duplicate_originals:
            write_duplicate_report(duplicate_originals, duplicate_txt)
            duplicate_list_path = str(duplicate_txt)
    else:
        final_paths = proxy_paths

    write_media_list(final_paths, output_txt)

    matched_count = 0
    if link_original:
        matched_count = len(proxy_paths) - len(unmatched_proxy)

    print_json({
        "ok": True,
        "mode": "extract",
        "input": str(Path(input_path).expanduser().resolve()),
        "xml_source": str(xml_source),
        "output_base": str(output_base),
        "media_list": str(output_txt),
        "count": len(final_paths),
        "link_original": link_original,
        "original_root": str(Path(original_root).expanduser().resolve()) if original_root else "",
        "proxy_count": len(proxy_paths),
        "proxy_paths": proxy_paths,
        "final_paths": final_paths,
        "matched_original_count": matched_count,
        "unmatched_proxy_count": len(unmatched_proxy),
        "unmatched_proxy_paths": unmatched_proxy,
        "duplicate_original_name_count": len(duplicate_originals),
        "unmatched_list": unmatched_list_path,
        "duplicate_list": duplicate_list_path
    })




def parse_json_arg(args, key):
    if key not in args:
        raise ValueError(f"缺少参数：{key}")
    idx = args.index(key)
    if idx + 1 >= len(args):
        raise ValueError(f"{key} 后面缺少 JSON 字符串")
    return json.loads(args[idx + 1])


def parse_value_arg(args, key):
    if key not in args:
        raise ValueError(f"缺少参数：{key}")
    idx = args.index(key)
    if idx + 1 >= len(args):
        raise ValueError(f"{key} 后面缺少值")
    return args[idx + 1]


def relink_unmatched_only(unmatched_proxies, current_final_paths, original_root):
    """
    只针对剩余未链接的代理文件再次匹配。
    匹配成功：替换 current_final_paths 中对应的原代理路径。
    仍未匹配：继续保留原代理路径，并返回 remaining_unmatched。
    """
    original_index = scan_original_media(original_root)

    updated_final = list(current_final_paths)
    remaining_unmatched = []
    newly_matched = []
    duplicate_originals = []

    for proxy_path in unmatched_proxies:
        stem = Path(proxy_path).stem
        candidates = original_index.get(stem, [])

        if len(candidates) == 0:
            remaining_unmatched.append(proxy_path)
            continue

        if len(candidates) == 1:
            chosen = candidates[0]
        else:
            chosen = choose_best_original(candidates)
            duplicate_originals.append({
                "proxy": proxy_path,
                "chosen": chosen,
                "candidates": candidates
            })

        replaced = False
        for i, existing in enumerate(updated_final):
            if existing == proxy_path:
                updated_final[i] = chosen
                replaced = True
                break

        if not replaced:
            updated_final.append(chosen)

        newly_matched.append(proxy_path)

    # 保序去重
    seen = set()
    unique_final = []
    for p in updated_final:
        if p not in seen:
            seen.add(p)
            unique_final.append(p)

    return unique_final, remaining_unmatched, newly_matched, duplicate_originals


def cmd_relink_unmatched(args):
    proxies = parse_json_arg(args, "--proxies-json")
    current_final = parse_json_arg(args, "--current-final-json")
    original_root = parse_value_arg(args, "--original-root")
    output_list = parse_value_arg(args, "--output-list")

    final_paths, remaining, newly_matched, duplicates = relink_unmatched_only(
        proxies,
        current_final,
        original_root
    )

    write_media_list(final_paths, output_list)

    duplicate_list_path = ""
    if duplicates:
        out = Path(output_list).with_suffix(".duplicate_original_media.txt")
        write_duplicate_report(duplicates, out)
        duplicate_list_path = str(out)

    print_json({
        "ok": True,
        "mode": "relink-unmatched",
        "media_list": str(Path(output_list).expanduser().resolve()),
        "final_paths": final_paths,
        "unmatched_proxy_paths": remaining,
        "remaining_unmatched_count": len(remaining),
        "newly_matched_count": len(newly_matched),
        "duplicate_original_name_count": len(duplicates),
        "duplicate_list": duplicate_list_path
    })


def cmd_write_list(args):
    paths = parse_json_arg(args, "--paths-json")
    output_list = parse_value_arg(args, "--output-list")
    write_media_list(paths, output_list)
    print_json({
        "ok": True,
        "mode": "write-list",
        "media_list": str(Path(output_list).expanduser().resolve()),
        "count": len(paths)
    })



def cmd_import(media_list_path):
    media_paths = read_media_list(media_list_path)
    imported_items, existing_files, missing_files = import_to_resolve(media_paths)

    media_list = Path(media_list_path).expanduser().resolve()
    missing_txt = media_list.with_suffix(".missing_media.txt")

    if missing_files:
        write_media_list(missing_files, missing_txt)
        missing_list_path = str(missing_txt)
    else:
        missing_list_path = ""

    print_json({
        "ok": True,
        "mode": "import",
        "media_list": str(media_list),
        "requested": len(media_paths),
        "existing": len(existing_files),
        "imported": len(imported_items),
        "missing": len(missing_files),
        "missing_list": missing_list_path
    })


def cmd_inspect_list(media_list_path):
    media_paths = read_media_list(media_list_path)
    existing_files = []
    missing_files = []

    for p in media_paths:
        if os.path.exists(p):
            existing_files.append(p)
        else:
            missing_files.append(p)

    print_json({
        "ok": True,
        "mode": "inspect-list",
        "media_list": str(Path(media_list_path).expanduser().resolve()),
        "count": len(media_paths),
        "existing": len(existing_files),
        "missing": len(missing_files)
    })


def main():
    if len(sys.argv) < 3:
        raise SystemExit("用法：resolve_importer.py extract xxx.fcpxml/xxx.fcpxmld [--link-original 原始文件目录] 或 resolve_importer.py inspect-list/import xxx.media_list.txt")

    mode = sys.argv[1]

    if mode == "extract":
        cmd_extract(sys.argv[2:])
    elif mode == "relink-unmatched":
        cmd_relink_unmatched(sys.argv[2:])
    elif mode == "write-list":
        cmd_write_list(sys.argv[2:])
    elif mode == "inspect-list":
        cmd_inspect_list(sys.argv[2])
    elif mode == "import":
        cmd_import(sys.argv[2])
    else:
        raise SystemExit(f"未知模式：{mode}")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print_json({
            "ok": False,
            "error": str(e)
        })
        sys.exit(1)
